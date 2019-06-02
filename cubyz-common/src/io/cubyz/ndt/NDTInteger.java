package io.cubyz.ndt;

public class NDTInteger extends NDTTag {

	{
		this.expectedLength = 4;
		this.type = NDTConstants.TYPE_INT;
	}
	
	public int getValue() {
		return ((content[3] & 0xFF)) +
				((content[2] & 0xFF) << 8) +
				((content[1] & 0xFF) << 16) +
				((content[0]) << 24);
	}
	
}
