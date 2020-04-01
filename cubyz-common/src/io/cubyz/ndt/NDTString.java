package io.cubyz.ndt;

import java.nio.ByteBuffer;

import io.cubyz.Constants;

public class NDTString extends NDTTag {

	{
		this.expectedLength = -1;
		this.type = NDTConstants.TYPE_STRING;
	}
	
	public int getLength() {
		return content.length;
	}
	
	public String getValue() {
		return Constants.CHARSET.decode(ByteBuffer.wrap(content)).toString();
	}
	
	public void setValue(String str) {
		content = Constants.CHARSET.encode(str).array();
	}
	
	public boolean validate() {
		return getLength() == content.length-2;
	}
	
	public String toString() {
		return "NDTString[value=" + getValue() + "]";
	}
}
