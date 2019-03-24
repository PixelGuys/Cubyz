package io.cubyz.multiplayer.server;

import java.nio.charset.Charset;

import io.cubyz.Constants;
import io.cubyz.multiplayer.Packet;
import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;

public class ServerHandler extends ChannelInboundHandlerAdapter {
	
	@Override
    public void channelRead(ChannelHandlerContext ctx, Object omsg) {
		ByteBuf msg = (ByteBuf) omsg;
		byte packetType = msg.readByte();
		if (CubzServer.internal) {
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
			out.writeByte(Packet.PACKET_PINGDATA);
			String motd = "A Cubz Server.";
			int online = 0; int max = 20;
			out.writeShort(motd.length());
			out.writeCharSequence(motd, Charset.forName("UTF-8"));
			out.writeInt(online);
			out.writeInt(max);
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
