package io.cubyz.multiplayer.client;

import java.nio.charset.Charset;
import java.util.ArrayList;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;

import io.cubyz.Constants;
import io.cubyz.CubyzLogger;
import io.cubyz.client.GameLogic;
import io.cubyz.client.GameLauncher;
import io.cubyz.multiplayer.BufUtils;
import io.cubyz.multiplayer.Packet;
import io.cubyz.world.NormalChunk;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

import static io.cubyz.CubyzLogger.logger;

@SuppressWarnings("unused")
public class MPClientHandler extends ChannelInboundHandlerAdapter {

	private MPClient cl;
	private ChannelHandlerContext ctx;
	private ChatHandler chHandler;
	private ArrayList<String> messages;
	
	private NormalChunk lastChunkReceived;
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
		buf.writeByte(Packet.PACKET_SERVER_INFO);
		ctx.writeAndFlush(buf);
	}
	
	public void connect() {
		ByteBuf buf = ctx.alloc().buffer(1);
		buf.writeByte(Packet.PACKET_LISTEN);
		buf.writeCharSequence(GameLauncher.logic.profile.getUUID().toString(), Constants.CHARSET);
		String username = GameLauncher.logic.profile.getUsername();
		buf.writeShort(username.length());
		buf.writeCharSequence(username, Constants.CHARSET);
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
		channelActive = true;
	}
	
	private static final Gson GSON = new GsonBuilder().create();

	@Override
	public void channelRead(ChannelHandlerContext ctx, Object msg) {
		ByteBuf buf = (ByteBuf) msg;
		while (buf.isReadable()) {
			byte responseType = buf.readByte();
			
			if (responseType == Packet.PACKET_SERVER_INFO) {
				PingResponse pr = new PingResponse();
				String json = BufUtils.readString(buf);
				
				JsonObject info = GSON.fromJson(json, JsonObject.class);
				JsonObject brand = info.get("brand").getAsJsonObject();
				JsonObject players = info.get("players").getAsJsonObject();
				
				pr.motd = info.get("description").getAsString();
				pr.onlinePlayers = players.get("online").getAsInt();
				pr.maxPlayers = players.get("max").getAsInt();
				
				cl.getLocalServer().lastPingResponse = pr;
			}
			
			if (responseType == Packet.PACKET_PINGPONG) {
				ByteBuf b = ctx.alloc().buffer(37);
				b.writeByte(Packet.PACKET_PINGPONG);
				b.writeCharSequence(GameLauncher.logic.profile.getUUID().toString(), Constants.CHARSET);
				ctx.write(b);
			}
			
			if (responseType == Packet.PACKET_CHATMSG) {
				short len = buf.readShort();
				String chat = buf.readCharSequence(len, Constants.CHARSET).toString();
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
