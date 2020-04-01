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
		ByteBuffer b = Constants.CHARSET.encode(str);
		content = new byte[b.limit()];
		for (int i = 0; i < b.limit(); i++) {
			content[i] = b.get(i);
		}
	}
	
	public boolean validate() {
		return true;
	}
	
	public String toString() {
		return "NDTString[value=" + getValue() + "]";
	}
}
