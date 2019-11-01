package io.cubyz.multiplayer.client;

import java.nio.charset.Charset;
import java.util.ArrayList;

import io.cubyz.Constants;
import io.cubyz.CubyzLogger;
import io.cubyz.client.Cubyz;
import io.cubyz.multiplayer.Packet;
import io.cubyz.world.Chunk;
import io.cubyz.world.RemoteWorld;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

@SuppressWarnings("unused")
public class MPClientHandler extends ChannelInboundHandlerAdapter {

	private MPClient cl;
	private ChannelHandlerContext ctx;
	private ChatHandler chHandler;
	private ArrayList<String> messages;
	
	private Chunk lastChunkReceived;
	private RemoteWorld world;

	private boolean hasPinged;
	public boolean channelActive;
	private boolean worldInited;
	
	public ChatHandler getChatHandler() {
		if (chHandler == null) {
			chHandler = new ChatHandler() {

				@Override
				public ArrayList<String> getAllMessages() {
					return messages;
				}

				@Override
				public void send(String msg) {
					ByteBuf buf = ctx.alloc().buffer(1 + msg.length());
					buf.writeByte(Packet.PACKET_CHATMSG);
					buf.writeShort(msg.length());
					buf.writeCharSequence(msg, Charset.forName("UTF-8"));
					ctx.writeAndFlush(buf);
				}
				
			};
		}
		return chHandler;
	}
	
	public MPClientHandler(MPClient cl, boolean doPing) {
		this.cl = cl;
	}
	
	public void ping() {
		ByteBuf buf = ctx.alloc().buffer(1);
		buf.writeByte(Packet.PACKET_PINGDATA);
		ctx.writeAndFlush(buf);
	}
	
	public void connect() {
		ByteBuf buf = ctx.alloc().buffer(1);
		buf.writeByte(Packet.PACKET_LISTEN);
		buf.writeCharSequence(Cubyz.profile.getUUID().toString(), Constants.CHARSET_IMPL);
		String username = Cubyz.profile.getUsername();
		buf.writeShort(username.length());
		buf.writeCharSequence(username, Constants.CHARSET_IMPL);
		ctx.writeAndFlush(buf);
		world = new RemoteWorld();
	}
	
	public RemoteWorld getWorld() {
		return world;
	}
	
	@Override
	public void channelActive(ChannelHandlerContext ctx) {
		this.ctx = ctx;
		messages = new ArrayList<>();
		ByteBuf buf = ctx.alloc().buffer(1);
		buf.writeByte(Packet.PACKET_GETVERSION);
		ctx.writeAndFlush(buf);
		channelActive = true;
	}

	@Override
	public void channelRead(ChannelHandlerContext ctx, Object msg) {
		ByteBuf buf = (ByteBuf) msg;
		while (buf.isReadable()) {
			byte responseType = buf.readByte();
			
			if (responseType == Packet.PACKET_GETVERSION) {
				int length = buf.readUnsignedByte();
				String raw = buf.readCharSequence(length, Constants.CHARSET_IMPL).toString();
				cl.getLocalServer().brand = raw.split(";")[0];
				cl.getLocalServer().version = raw.split(";")[1];
				CubyzLogger.instance.fine("[MPClientHandler] Raw version + brand: " + raw);
			}
			
			if (responseType == Packet.PACKET_PINGDATA) {
				PingResponse pr = new PingResponse();
				pr.motd = buf.readCharSequence(buf.readShort(), Constants.CHARSET_IMPL).toString();
				pr.onlinePlayers = buf.readInt();
				pr.maxPlayers = buf.readInt();
				cl.getLocalServer().lastPingResponse = pr;
			}
			
			if (responseType == Packet.PACKET_PINGPONG) {
				ByteBuf b = ctx.alloc().buffer(37);
				b.writeByte(Packet.PACKET_PINGPONG);
				b.writeCharSequence(Cubyz.profile.getUUID().toString(), Constants.CHARSET_IMPL);
				ctx.write(b);
			}
			
			if (responseType == Packet.PACKET_CHATMSG) {
				short len = buf.readShort();
				String chat = buf.readCharSequence(len, Constants.CHARSET_IMPL).toString();
				messages.add(chat);
			}
			
			if (responseType == Packet.PACKET_CHUNK) {
				int x = buf.readInt();
				int z = buf.readInt();
				int seed = buf.readInt();
				int len = buf.readInt();
				byte[] data = new byte[len];
				buf.readBytes(data);
				System.out.println("Got " + x + ", " + z);
				if (!worldInited) {
					world.worldData(seed);
					worldInited = true;
				}
				world.submit(x, z, data);
			}
		}
		buf.release();
	}

	@Override
	public void channelReadComplete(ChannelHandlerContext ctx) {
		ctx.flush();
	}

	@Override
	public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
		cause.printStackTrace();
		ctx.close();
	}

}
