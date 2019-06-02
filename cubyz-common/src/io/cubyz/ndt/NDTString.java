package io.cubyz.ndt;

import io.cubyz.math.Bits;

public class NDTString extends NDTTag {

	{
		this.expectedLength = -1;
		this.type = NDTConstants.TYPE_STRING;
	}
	
	short getLength() {
		return Bits.getShort(content, 0);
	}
	
	public String getValue() {
		StringBuilder builder = new StringBuilder();
		for (int i = 0; i < getLength(); i++) {
			builder.append((char) content[2 + i]);
		}
		return builder.toString();
	}
	
	public boolean validate() {
		return getLength() == content.length+2;
	}
}
