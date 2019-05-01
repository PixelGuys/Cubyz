package io.cubyz.multiplayer.client;

import java.nio.charset.Charset;
import java.util.ArrayList;

import io.cubyz.CubyzLogger;
import io.cubyz.multiplayer.Packet;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

public class MPClientHandler extends ChannelInboundHandlerAdapter {

	private MPClient cl;
	private ChannelHandlerContext ctx;
	private ChatHandler chHandler;
	private ArrayList<String> messages;

	private boolean hasPinged;
	public boolean channelActive;
	
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
					buf.writeCharSequence(msg, Charset.forName("UTF-8")); // a message using UTF-16 or UTF-32 would crash the game!
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
	
	@Override
	public void channelActive(ChannelHandlerContext ctx) {
		this.ctx = ctx;
		messages = new ArrayList<>();
		ByteBuf buf = ctx.alloc().buffer(1);
		buf.writeByte(Packet.PACKET_GETVERSION);
		ctx.write(buf);
		ctx.flush();
		channelActive = true;
	}

	@Override
	public void channelRead(ChannelHandlerContext ctx, Object msg) {
		ByteBuf buf = (ByteBuf) msg;
		byte responseType = buf.readByte();
		
		if (responseType == Packet.PACKET_GETVERSION) {
			int length = buf.readUnsignedByte();
			String raw = buf.readCharSequence(length, Charset.forName("UTF-8")).toString();
			cl.getLocalServer().brand = raw.split(";")[0];
			cl.getLocalServer().version = raw.split(";")[1];
			CubyzLogger.instance.fine("[MPClientHandler] Raw version + brand: " + raw);
		}
		
		if (responseType == Packet.PACKET_PINGDATA) {
			PingResponse pr = new PingResponse();
			pr.motd = buf.readCharSequence(buf.readShort(), Charset.forName("UTF-8")).toString();
			pr.onlinePlayers = buf.readInt();
			pr.maxPlayers = buf.readInt();
			cl.getLocalServer().lastPingResponse = pr;
		}
		
		if (responseType == Packet.PACKET_PINGPONG) {
			ByteBuf b = ctx.alloc().buffer(5);
			b.writeByte(Packet.PACKET_PINGPONG);
			b.writeInt(buf.readInt());
		}
	}

	@Override
	public void channelReadComplete(ChannelHandlerContext ctx) {
		ctx.flush();
	}

	@Override
	public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
		// Close the connection when an exception is raised.
		cause.printStackTrace();
		ctx.close();
	}

}
