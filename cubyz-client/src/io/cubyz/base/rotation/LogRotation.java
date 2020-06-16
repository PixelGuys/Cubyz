package io.cubyz.base.rotation;

import org.joml.Vector3i;

import io.cubyz.ClientOnly;
import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.world.BlockSpatial;

public class LogRotation implements RotationMode {
	private static final float PI = (float)Math.PI;
	private static final float PI_HALF = PI/2;
	
	Resource id = new Resource("cubyz", "log");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public byte generateData(Vector3i dir, byte oldData) {
		byte data = 0;
		if(dir.x == 1) data = (byte)0b10;
		if(dir.x == -1) data = (byte)0b11;
		if(dir.y == -1) data = (byte)0b0;
		if(dir.y == 1) data = (byte)0b1;
		if(dir.z == 1) data = (byte)0b100;
		if(dir.z == -1) data = (byte)0b101;
		return data;
	}

	@Override
	public Object[] generateSpatials(BlockInstance bi, byte data) {
		BlockSpatial[] spatials = new BlockSpatial[1];
		BlockSpatial tmp = (BlockSpatial)ClientOnly.createBlockSpatial.apply(bi);
		switch(data) {
			default:
				break;
			case 1:
				tmp.setRotation(PI, 0, 0);
				break;
			case 2:
				tmp.setRotation(0, 0, -PI_HALF);
				break;
			case 3:
				tmp.setRotation(0, 0, PI_HALF);
				break;
			case 4:
				tmp.setRotation(PI_HALF, 0, 0);
				break;
			case 5:
				tmp.setRotation(-PI_HALF, 0, 0);
				break;
		}
		spatials[0] = tmp;
		return spatials;
	}
}
