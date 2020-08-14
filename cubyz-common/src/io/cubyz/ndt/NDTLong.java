package io.cubyz.ndt;

import io.cubyz.math.Bits;

@Deprecated
public class NDTLong extends NDTTag {

	{
		this.expectedLength = 8;
		this.type = NDTConstants.TYPE_LONG;
	}
	
	public long getValue() {
		return Bits.getLong(content, 0);
	}
	
	public void setValue(long i) {
		content = new byte[8];
		Bits.putLong(content, 0, i);
	}
	
	public String toString() {
		return "NDTLong[value=" + getValue() + "]";
	}
	
}
