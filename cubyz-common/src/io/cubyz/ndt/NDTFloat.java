package io.cubyz.ndt;

import io.cubyz.math.Bits;

@Deprecated
public class NDTFloat extends NDTTag {

	{
		this.expectedLength = 4;
		this.type = NDTConstants.TYPE_FLOAT;
	}
	
	public float getValue() {
		return Bits.getFloat(content, 0);
	}
	
	public void setValue(float i) {
		content = new byte[4];
		Bits.putFloat(content, 0, i);
	}
	
	public String toString() {
		return "NDTFloat[value=" + getValue() + "]";
	}
	
}
