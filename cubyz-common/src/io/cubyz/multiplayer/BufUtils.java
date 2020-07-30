package io.cubyz.multiplayer;

import java.nio.ByteBuffer;

import io.cubyz.Constants;
import io.netty.buffer.ByteBuf;

public class BufUtils {

	public static void writeVarInt(ByteBuf buf, int n) {
		do {
			int b = n & 0x7F;
			n = n >>> 7;
			if (n != 0) {
				b |= 0x80;
			}
			buf.writeByte(b);
		} while (n != 0);
	}
	
	public static int readVarInt(ByteBuf buf) {
		int b = 0;
		int n = 0;
		do {
			b = buf.readByte();
			n <<= 7;
			n |= b & 0x7F;
		} while ((b & 0x80) != 0);
		return n;
	}
	
	public static String readString(ByteBuf buf) {
		int length = readVarInt(buf);
		String str = buf.readCharSequence(length, Constants.CHARSET).toString();
		System.out.println("result: " + str + " (" + length + ")");
		return str;
	}
	
	public static void writeString(ByteBuf buf, String str) {
		ByteBuffer bytes = Constants.CHARSET.encode(str);
		writeVarInt(buf, bytes.limit());
		buf.writeBytes(bytes);
	}
	
}
