package io.cubyz.blocks;

import org.joml.Vector3f;

public class Water extends Block {
	protected Vector3f WaterAdjust = new Vector3f(0.3f, 0.4f, 1.0f);
	public Water() {
		setTexture("water");
		setID("cubyz:water");
		setSelectable(false);
		setSolid(false);
		transparent = true;
	}
	
	@Override
	public Vector3f getLightAdjust() {
		return WaterAdjust;
	}
}
