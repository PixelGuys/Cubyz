package io.cubyz.multiplayer;

public class Packet {

	// server info related
	public static final byte PACKET_GETVERSION = 15;
	public static final byte PACKET_PINGPONG = 16;
	public static final byte PACKET_PINGDATA = 13;
	
	// player related
	public static final byte PACKET_SETBLOCK = 3;
	public static final byte PACKET_MOVE = 4;
	public static final byte PACKET_CHATMSG = 5;
	public static final byte PACKET_LISTEN = 6; // listen for update packets
	
	// world related
	public static final byte PACKET_PLACE = 17;
	public static final byte PACKET_DESTROY = 18;
	public static final byte PACKET_CHUNK_RQ = 19;
	public static final byte PACKET_CHUNK = 20;
	
}
