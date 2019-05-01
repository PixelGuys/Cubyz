package io.cubyz.multiplayer.server;

import java.nio.charset.Charset;

import io.cubyz.Constants;
import io.cubyz.multiplayer.Packet;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

public class ServerHandler extends ChannelInboundHandlerAdapter {
	
	int online;
	int max = 20;
	boolean init;
	CubyzServer server;
	
	String motd;
	
	public ServerHandler(CubyzServer server) {
		this.server = server;
	}
	
	@Override
    public void channelRead(ChannelHandlerContext ctx, Object omsg) {
		
		if (!init) {
			motd = "A Cubyz server";
			
			if (motd.length() > 500) {
				throw new IllegalArgumentException("MOTD cannot be more than 500 characters long");
			}
			init = true;
		}
		
		ByteBuf msg = (ByteBuf) omsg;
		byte packetType = msg.readByte();
		if (CubyzServer.internal) {
			System.out.println("[Integrated Server] packet type: " + packetType);
		}
		if (packetType == Packet.PACKET_GETVERSION) {
			ByteBuf out = ctx.alloc().ioBuffer(128); // 128-length version including brand
			out.writeByte(Packet.PACKET_GETVERSION);
			String seq = Constants.GAME_BRAND + ";" + Constants.GAME_VERSION;
			out.writeByte(seq.length());
			out.writeCharSequence(seq, Charset.forName("UTF-8"));
			ctx.write(out);
		}
		if (packetType == Packet.PACKET_PINGDATA) {
			ByteBuf out = ctx.alloc().ioBuffer(512);
			out.writeByte(Packet.PACKET_PINGDATA); // 1 byte
			out.writeShort(motd.length()); // 2 bytes
			out.writeCharSequence(motd, Charset.forName("UTF-8"));
			out.writeInt(online); // 4 bytes
			out.writeInt(max); // 4 bytes
			// 1+2+4+4=11 bytes of "same size" data
			//512-11=501, so 501 characters max for motd
			ctx.write(out);
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
