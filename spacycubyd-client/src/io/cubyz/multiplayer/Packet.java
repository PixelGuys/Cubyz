package io.cubyz.multiplayer;

public class Packet {

	public static final byte PACKET_GETVERSION = 15; //NOTE: Normal > 15
	public static final byte PACKET_PINGPONG = 16; //NOTE: Normal > 16
	public static final byte PACKET_PINGDATA = 13; //NOTE: Normal > 13
	
	public static final byte PACKET_SETBLOCK = 3; //NOTE: Normal > 3
	public static final byte PACKET_MOVE = 4; //NOTE: Normal > 4
	
}
