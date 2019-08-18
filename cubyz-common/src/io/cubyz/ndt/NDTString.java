package io.cubyz.ndt;

import io.cubyz.math.Bits;

public class NDTString extends NDTTag {

	{
		this.expectedLength = -1;
		this.type = NDTConstants.TYPE_STRING;
	}
	
	public short getLength() {
		//return Bits.getShort(content, 0);
		return (short) ((short) content.length-2);
	}
	
	public String getValue() {
		StringBuilder builder = new StringBuilder();
		for (int i = 0; i < getLength(); i++) {
			builder.append((char) content[2 + i]);
		}
		return builder.toString();
	}
	
	public void setValue(String str) {
		content = new byte[2 + str.length()];
		Bits.putShort(content, 0, (short) str.length());
		for (int i = 0; i < str.length(); i++) {
			content[i + 2] = (byte) str.charAt(i);
		}
	}
	
	public boolean validate() {
		return getLength() == content.length-2;
	}
	
	public String toString() {
		return "NDTString[value=" + getValue() + "]";
	}
}
