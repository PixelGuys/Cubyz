package io.cubyz.multiplayer.server;

import java.util.HashMap;
import java.util.UUID;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;

import io.cubyz.ClientOnly;
import io.cubyz.Constants;
import io.cubyz.blocks.Block;
import io.cubyz.multiplayer.BufUtils;
import io.cubyz.multiplayer.Packet;
import io.cubyz.world.LocalStellarTorus;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

@SuppressWarnings("unused")
public class ServerHandler extends ChannelInboundHandlerAdapter {
	
	int online;
	int max = 20;
	int playerPingTime = 5000; // Time between each ping packets
	int playerTimeout  = 5000; // Maximum time a client can respond to ping packets.
	CubyzServer server;
	
	public static LocalStellarTorus stellarTorus;
	static Thread th;
	
	String description;
	
	HashMap<String, Client> clients = new HashMap<>();
	class Client {
		public ChannelHandlerContext ctx;
		public String username;
		public UUID uuid;
		public long lastPing;
		public long lastSendedPing = -1;
	}
	
	public Client getClient(ChannelHandlerContext ctx) {
		for (Client cl : clients.values()) {
			if (cl.ctx.equals(ctx)) {
				return cl;
			}
		}
		return null;
	}
	
	public ServerHandler(CubyzServer server, ServerSettings settings) {
		this.server = server;
		max = settings.maxPlayers;
		playerPingTime = settings.playerPingTime;
		playerTimeout = settings.playerTimeout;
		description = "A Cubyz server";
		//stellarTorus = new LocalStellarTorus(); TODO!
		//Block[] blocks = stellarTorus.generate(); TODO!
		// Generate the Block meshes:
		/*for(Block b : blocks) { TODO!
			ClientOnly.createBlockMesh.accept(b);
		}*/
		th = new Thread(() -> {
			while (true) {
				for (String uuid : clients.keySet()) {
					Client cl = clients.get(uuid);
					if (cl.lastSendedPing != -1) {
						if (cl.lastSendedPing < System.currentTimeMillis() - playerTimeout) {
							// timed out
							clients.remove(uuid);
							System.out.println(cl.username + " timed out!");
						}
					}
					if (cl.lastPing < System.currentTimeMillis() - playerPingTime && cl.lastSendedPing == -1) {
						cl.lastSendedPing = System.currentTimeMillis();
						ByteBuf buf = cl.ctx.alloc().buffer();
						buf.writeByte(Packet.PACKET_PINGPONG);
						cl.ctx.writeAndFlush(buf);
					}
				}
				if (Thread.interrupted()) {
					break;
				}
				try {
					Thread.sleep(100);
				} catch (InterruptedException e) {
					break;
				}
			}
		});
		th.start();
	}
	
	public ByteBuf sendChunk(ChannelHandlerContext ctx, int x, int z) {
		ByteBuf out = ctx.alloc().buffer();
		//world.seek(x*16, z*16);
		/*stellarTorus.seek(0, 0); TODO!
		byte[] data = stellarTorus.getChunkData(x, z);
		out.writeByte(Packet.PACKET_CHUNK);
		out.writeInt(x);
		out.writeInt(z);
		out.writeInt(stellarTorus.getLocalSeed());
		out.writeInt(data.length);
		out.writeBytes(data);*/
		return out;
	}
	
	private static final Gson GSON = new GsonBuilder().create();
	
	@Override
    public void channelRead(ChannelHandlerContext ctx, Object omsg) {
		ByteBuf msg = (ByteBuf) omsg;
		Client client = getClient(ctx);
		byte packetType = msg.readByte();
		
		if (packetType == Packet.PACKET_CHATMSG) {
			short chatLen = msg.readShort();
			String chat = msg.readCharSequence(chatLen, Constants.CHARSET).toString();
			for (Client cl : clients.values()) {
				ByteBuf buf = cl.ctx.alloc().buffer(1 + chatLen);
				buf.writeByte(Packet.PACKET_CHATMSG);
				buf.writeShort(chatLen);
				buf.writeCharSequence(chat, Constants.CHARSET);
				cl.ctx.write(buf);
			}
			System.out.println("[Server | Chat] " + chat);
		}
		if (packetType == Packet.PACKET_PINGPONG) {
			UUID uuid = UUID.fromString(msg.readCharSequence(36, Constants.CHARSET).toString());
			Client cl = clients.get(uuid.toString());
			cl.lastPing = System.currentTimeMillis();
			cl.lastSendedPing = -1;
		}
		if (packetType == Packet.PACKET_LISTEN) {
			UUID uuid = UUID.fromString(msg.readCharSequence(36, Constants.CHARSET).toString());
			Client cl = new Client();
			int usernamelen = msg.readShort();
			cl.ctx = ctx;
			cl.uuid = uuid;
			cl.username = msg.readCharSequence(usernamelen, Constants.CHARSET).toString(); // TODO retrieve username
			cl.lastPing = System.currentTimeMillis();
			clients.put(uuid.toString(), cl);
			for (int x = 0; x < 4; x++) {
				for (int y = 0; y < 4; y++) {
					ctx.writeAndFlush(sendChunk(ctx, x, y));
				}
			}
		}
		if (packetType == Packet.PACKET_SERVER_INFO) {
			ByteBuf out = ctx.alloc().ioBuffer();
			out.writeByte(Packet.PACKET_SERVER_INFO); // 1 byte
			
			JsonObject serverInfo = new JsonObject();
			serverInfo.addProperty("description", description);
			
			JsonObject playersInfo = new JsonObject();
			playersInfo.addProperty("online", online);
			playersInfo.addProperty("max", max);
			serverInfo.add("players", playersInfo);
			
			JsonObject brandInfo = new JsonObject();
			brandInfo.addProperty("name", Constants.GAME_BRAND);
			brandInfo.addProperty("version", Constants.GAME_VERSION);
			brandInfo.addProperty("protocolVersion", Constants.GAME_PROTOCOL_VERSION);
			serverInfo.add("brand", brandInfo);
			
			BufUtils.writeString(out, GSON.toJson(serverInfo));
			ctx.write(out);
		}
		if (packetType == Packet.PACKET_MOVE) {
			int x = msg.readInt();
			int y = msg.readInt();
			int z = msg.readInt();
			
		}
        msg.release();
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
