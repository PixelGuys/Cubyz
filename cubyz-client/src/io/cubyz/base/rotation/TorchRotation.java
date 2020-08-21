package io.cubyz.base.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.entity.Player;
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
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSize) {
		BlockSpatial[] spatials = new BlockSpatial[5];
		int index = 0;
		if((data & 0b1) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
			tmp.setPosition(bi.getX() + POS_X.x, bi.getY() + POS_X.y, bi.getZ() + POS_X.z, player, worldSize);
			tmp.setRotation(0, 0, -0.3f);
			spatials[index++] = tmp;
		}
		if((data & 0b10) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
			tmp.setPosition(bi.getX() + NEG_X.x, bi.getY() + NEG_X.y, bi.getZ() + NEG_X.z, player, worldSize);
			tmp.setRotation(0, 0, 0.3f);
			spatials[index++] = tmp;
		}
		if((data & 0b100) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
			tmp.setPosition(bi.getX() + POS_Z.x, bi.getY() + POS_Z.y, bi.getZ() + POS_Z.z, player, worldSize);
			tmp.setRotation(0.3f, 0, 0);
			spatials[index++] = tmp;
		}
		if((data & 0b1000) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
			tmp.setPosition(bi.getX() + NEG_Z.x, bi.getY() + NEG_Z.y, bi.getZ() + NEG_Z.z, player, worldSize);
			tmp.setRotation(-0.3f, 0, 0);
			spatials[index++] = tmp;
		}
		if((data & 0b10000) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSize);
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

	@Override
	public boolean checkTransparency(byte data, int dir) {
		return false;
	}

	@Override
	public byte getNaturalStandard() {
		return 1;
	}

	@Override
	public boolean changesHitbox() {
		return false;
	}

	@Override
	public float getRayIntersection(RayAabIntersection arg0, BlockInstance arg1, Vector3f min, Vector3f max, Vector3f transformedPosition) {
		return 0;
	}
}
