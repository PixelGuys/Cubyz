package io.cubyz.ndt;

import io.cubyz.math.Bits;
import io.cubyz.math.FloatingInteger;

/**
 * Corresponds to a Vector3fi component
 */
public class NDTFloatingInteger extends NDTTag {

	{
		this.expectedLength = 8;
		this.type = NDTConstants.TYPE_FLOATINT;
	}
	
	public FloatingInteger getValue() {
		return new FloatingInteger(Bits.getInt(content, 0), Bits.getFloat(content, 4));
	}
	
	public void setValue(int i, float rel) {
		content = new byte[8];
		Bits.putInt(content, 0, i);
		Bits.putFloat(content, 4, rel);
	}
	
}
