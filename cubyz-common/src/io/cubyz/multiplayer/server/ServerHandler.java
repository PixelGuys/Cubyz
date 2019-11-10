package io.cubyz.multiplayer.server;

import java.util.HashMap;
import java.util.UUID;

import io.cubyz.Constants;
import io.cubyz.multiplayer.Packet;
import io.cubyz.world.LocalWorld;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

@SuppressWarnings("unused")
public class ServerHandler extends ChannelInboundHandlerAdapter {
	
	int online;
	int max = 20;
	int playerPingTime = 5000; // Time between each ping packets
	int playerTimeout  = 5000; // Maximum time a client can respond to ping packets.
	boolean init;
	boolean isInternal;
	boolean onlineMode;
	CubyzServer server;
	
	public static LocalWorld world;
	static Thread th;
	
	String motd;
	
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
		onlineMode = settings.onlineMode;
		isInternal = settings.internal;
		world = new LocalWorld();
		world.generate();
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
		world.seek(0, 0);
		byte[] data = world.getChunkData(x, z);
		out.writeByte(Packet.PACKET_CHUNK);
		out.writeInt(x);
		out.writeInt(z);
		out.writeInt(world.getSeed());
		out.writeInt(data.length);
		out.writeBytes(data);
		return out;
	}
	
	@Override
    public void channelRead(ChannelHandlerContext ctx, Object omsg) {
		if (!init) {
			motd = "A Cubyz server";
			// TODO load properties
			if (motd.length() > 500) {
				throw new IllegalArgumentException("MOTD cannot be more than 500 characters long");
			}
			init = true;
		}
		ByteBuf msg = (ByteBuf) omsg;
		Client client = getClient(ctx);
		byte packetType = msg.readByte();
		if (CubyzServer.internal) {
			//System.out.println("[Integrated Server] packet type: " + packetType);
		}
		if (packetType == Packet.PACKET_GETVERSION) {
			ByteBuf out = ctx.alloc().ioBuffer(128); // 128-length version including brand
			out.writeByte(Packet.PACKET_GETVERSION);
			String seq = Constants.GAME_BRAND + ";" + Constants.GAME_VERSION;
			out.writeByte(seq.length());
			out.writeCharSequence(seq, Constants.CHARSET);
			ctx.write(out);
		}
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
		if (packetType == Packet.PACKET_PINGDATA) {
			ByteBuf out = ctx.alloc().ioBuffer(512);
			out.writeByte(Packet.PACKET_PINGDATA); // 1 byte
			out.writeShort(motd.length()); // 2 bytes
			out.writeCharSequence(motd, Constants.CHARSET);
			out.writeInt(online); // 4 bytes
			out.writeInt(max); // 4 bytes
			// 1+2+4+4=11 bytes of "same size" data
			//512-11=501, so 501 characters max for motd
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
