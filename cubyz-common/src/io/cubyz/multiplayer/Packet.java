package io.cubyz.multiplayer;

public class Packet {

	// server info related
	public static final byte PACKET_PINGPONG = 0x00;
	public static final byte PACKET_SERVER_INFO = 0x01;
	
	// player related
	public static final byte PACKET_SETBLOCK = 0x02;
	public static final byte PACKET_MOVE = 0x03;
	public static final byte PACKET_CHATMSG = 0x04;
	public static final byte PACKET_LISTEN = 0x05; // listen for update packets
	
	// world related
	public static final byte PACKET_PLACE = 0x06;
	public static final byte PACKET_DESTROY = 0x07;
	public static final byte PACKET_CHUNK = 0x08;
	
}
