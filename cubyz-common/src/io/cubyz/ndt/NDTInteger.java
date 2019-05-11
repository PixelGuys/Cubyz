package io.cubyz.ndt;

public class NDTInteger extends NDTTag {

	public int getValue() {
		return ((content[3] & 0xFF)) +
				((content[2] & 0xFF) << 8) +
				((content[1] & 0xFF) << 16) +
				((content[0]) << 24);
	}

	public boolean validate() {
		return super.validate() && contentLength == 4;
	}

}
