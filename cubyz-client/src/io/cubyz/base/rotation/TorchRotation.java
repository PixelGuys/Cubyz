package io.cubyz.base.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.api.Resource;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.RotationMode;
import io.cubyz.client.Meshes;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;
import io.cubyz.world.BlockSpatial;

/**
 * Rotates and translates the model, so it hangs on the wall or stands on the ground like a torch.<br>
 * It also allows the player to place multiple torches of the same type in different rotation in the same block.
 */

public class TorchRotation implements RotationMode {
	// Position offsets for the torch hanging on the wall:
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
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSizeX, int worldSizeZ) {
		BlockSpatial[] spatials = new BlockSpatial[5];
		int index = 0;
		if((data & 0b1) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
			tmp.setPosition(bi.getX() + POS_X.x, bi.getY() + POS_X.y, bi.getZ() + POS_X.z, player, worldSizeX, worldSizeZ);
			tmp.setRotation(0, 0, -0.3f);
			spatials[index++] = tmp;
		}
		if((data & 0b10) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
			tmp.setPosition(bi.getX() + NEG_X.x, bi.getY() + NEG_X.y, bi.getZ() + NEG_X.z, player, worldSizeX, worldSizeZ);
			tmp.setRotation(0, 0, 0.3f);
			spatials[index++] = tmp;
		}
		if((data & 0b100) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
			tmp.setPosition(bi.getX() + POS_Z.x, bi.getY() + POS_Z.y, bi.getZ() + POS_Z.z, player, worldSizeX, worldSizeZ);
			tmp.setRotation(0.3f, 0, 0);
			spatials[index++] = tmp;
		}
		if((data & 0b1000) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
			tmp.setPosition(bi.getX() + NEG_Z.x, bi.getY() + NEG_Z.y, bi.getZ() + NEG_Z.z, player, worldSizeX, worldSizeZ);
			tmp.setRotation(-0.3f, 0, 0);
			spatials[index++] = tmp;
		}
		if((data & 0b10000) != 0) {
			BlockSpatial tmp = new BlockSpatial(bi, player, worldSizeX, worldSizeZ);
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

	@Override
	public boolean checkEntity(Entity arg0, int x, int y, int z, byte arg2) {
		return false;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity arg0, Vector4f arg1, int x, int y, int z, byte arg2) {
		return true;
	}
	
	@Override
	public void generateChunkMesh(BlockInstance bi, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture) {
		// TODO: Add rotation and translation.
		Meshes.blockMeshes.get(bi.getBlock()).model.addToChunkMesh(bi.x & 15, bi.y, bi.z & 15, bi.light, vertices, normals, faces, lighting, texture);
	}
}
