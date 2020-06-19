package io.cubyz.base.rotation;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.world.BlockSpatial;

public class TorchRotation implements RotationMode {
	private static final Vector3f POS_X = new Vector3f(0.4f, 0.2f, 0);
	private static final Vector3f NEG_X = new Vector3f(-0.4f, 0.2f, 0);
	private static final Vector3f POS_Z = new Vector3f(0, 0.2f, 0.4f);
	private static final Vector3f NEG_Z = new Vector3f(0, 0.2f, -0.4f);
	
	Resource id = new Resource("cubyz", "torch");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public byte generateData(Vector3i dir, byte oldData) {
		byte data = (byte)0;
		if(dir.x == 1) data = (byte)0b1;
		if(dir.x == -1) data = (byte)0b10;
		if(dir.y == -1) data = (byte)0b10000;
		if(dir.z == 1) data = (byte)0b100;
		if(dir.z == -1) data = (byte)0b1000;
		return (byte)(data | oldData);
	}

	@Override
	public Object[] generateSpatials(BlockInstance bi, byte data) {
		BlockSpatial[] spatials = new BlockSpatial[5];
		int index = 0;
		if((data & 0b1) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi);
			tmp.setOffset(POS_X);
			tmp.setRotation(0, 0, -0.3f);
			spatials[index++] = tmp;
		}
		if((data & 0b10) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi);
			tmp.setOffset(NEG_X);
			tmp.setRotation(0, 0, 0.3f);
			spatials[index++] = tmp;
		}
		if((data & 0b100) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi);
			tmp.setOffset(POS_Z);
			tmp.setRotation(0.3f, 0, 0);
			spatials[index++] = tmp;
		}
		if((data & 0b1000) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi);
			tmp.setOffset(NEG_Z);
			tmp.setRotation(-0.3f, 0, 0);
			spatials[index++] = tmp;
		}
		if((data & 0b10000) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi);
			spatials[index++] = tmp;
		}
		if(index == spatials.length) {
			return spatials;
		}
		BlockSpatial[] trimmedArray = new BlockSpatial[index];
		System.arraycopy(spatials, 0, trimmedArray, 0, index);
		return trimmedArray;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return true;
	}

	@Override
	public Byte updateData(byte data, int dir) {
		switch(dir) {
			case 0: {
				data &= ~0b10;
				break;
			}
			case 1: {
				data &= ~0b1;
				break;
			}
			case 2: {
				data &= ~0b1000;
				break;
			}
			case 3: {
				data &= ~0b100;
				break;
			}
			case 4: {
				data &= ~0b10000;
				break;
			}
			default: {
				break;
			}
		}
		// Torches are removed when they have no contact to another block.
		if(data == 0) return null;
		return data;
	}
}
