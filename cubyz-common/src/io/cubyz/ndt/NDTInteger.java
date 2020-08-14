package io.cubyz.ndt;

import io.cubyz.math.Bits;

@Deprecated
public class NDTInteger extends NDTTag {

	{
		this.expectedLength = 4;
		this.type = NDTConstants.TYPE_INT;
	}
	
	public int getValue() {
		return Bits.getInt(content, 0);
	}
	
	public void setValue(int i) {
		content = new byte[4];
		Bits.putInt(content, 0, i);
	}
	
	public String toString() {
		return "NDTInteger[value=" + getValue() + "]";
	}
	
}
