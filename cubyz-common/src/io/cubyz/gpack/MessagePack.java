package io.cubyz.gpack;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.util.Map.Entry;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;

import io.cubyz.Constants;

public class MessagePack {

	public static byte[] encode(JsonElement json) throws IOException {
		ByteArrayOutputStream baos = new ByteArrayOutputStream();
		DataOutputStream out = new DataOutputStream(baos);
		
		if (json.isJsonObject()) {
			JsonObject obj = json.getAsJsonObject();
			int size = obj.size();
			if (size <= 0xF) {
				out.write(0b10000000 | size);
			} else if (size <= 0xFFFF) {
				out.write(0xDE);
				out.writeShort((short) size);
			} else {
				out.write(0xDF);
				out.writeInt(size);
			}
			
			for (Entry<String, JsonElement> entry : obj.entrySet()) {
				out.write(encode(new JsonPrimitive(entry.getKey())));
				out.write(encode(entry.getValue()));
			}
		} else if (json.isJsonNull()) {
			out.write(0xC0);
		} else if (json.isJsonPrimitive()) {
			JsonPrimitive prim = json.getAsJsonPrimitive();
			if (prim.isBoolean()) {
				out.write(prim.getAsBoolean() ? 0xc3 : 0xc2);
			} else if (prim.isString()) {
				String str = prim.getAsString();
				int len = str.length();
				if (len < 32) { // fixstr
					out.write(0b10100000 | len);
					out.write(str.getBytes(Constants.CHARSET));
				} else if (len < 0xFF) { // str 8
					out.write(0xD9);
					out.write(len);
					out.write(str.getBytes(Constants.CHARSET));
				} else if (len < 0xFFFF) { // str 16
					out.write(0xDA);
					out.writeShort(len);
					out.write(str.getBytes(Constants.CHARSET));
				} else if (len < 0xFFFFFFFF) { // str 32
					out.write(0xDB);
					out.writeInt(len);
					out.write(str.getBytes(Constants.CHARSET));
				}
			} else if (prim.isNumber()) {
				long num = prim.getAsLong();
				double doubleNum = prim.getAsDouble();
				if (num != doubleNum) { // floating number
					float singleNum = prim.getAsFloat();
					if (singleNum != doubleNum) { // if float doesn't have as much precision as double
						out.write(0xCB);
						out.writeDouble(doubleNum);
					} else { // it fits perfectly in a float
						out.write(0xCA);
						out.writeFloat(singleNum);
					}
				} else { // integer
					if (num >= 0) {
						if (num <= 0x7F) { // 7-bit positive
							out.write((int) num);
						} else if (num <= 0xFF) { // 8-bit unsigned
							out.write(0xCC);
							out.write((int) num);
						} else if (num <= 0xFFFF) { // 16-bit unsigned
							out.write(0xCD);
							out.writeShort((short) num);
						} else if (num <= 0xFFFFFFFFL) { // 32-bit unsigned
							out.write(0xCE);
							out.writeInt((int) num);
						} else { // 64-bit unsigned (actually 63-bit due to Java's long being signed)
							out.write(0xCF);
							out.writeLong(num);
						}
					} else if (num < 0) {
						if (num >= -0x1F) { // 5-bit negative
							int b = 0b11100000 | Math.abs((int) num);
							out.write(b);
						} else if (num >= Byte.MIN_VALUE) { // 8-bit signed
							out.write(0xD0);
							out.write((int) num);
						} else if (num >= Short.MIN_VALUE) { // 16-bit signed
							out.write(0xD1);
							out.writeShort((short) num);
						} else if (num >= Integer.MIN_VALUE) { // 32-bit signed
							out.write(0xD2);
							out.writeInt((int) num);
						} else { // 64-bit signed
							out.write(0xD3);
							out.writeLong(num);
						}
					}
				}
			}
		}
		
		out.close();
		return baos.toByteArray();
	}
	
}
