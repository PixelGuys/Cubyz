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
import io.cubyz.util.ByteWrapper;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;

/**
 * Rotates the block based on the direction the player is placing it.
 */

public class LogRotation implements RotationMode {
	
	Resource id = new Resource("cubyz", "log");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public boolean generateData(Vector3f relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, ByteWrapper currentData, boolean blockPlacing) {
		if(!blockPlacing) return false;
		byte data = -1;
		if(relativeDirection.x == 1) data = (byte)0b10;
		if(relativeDirection.x == -1) data = (byte)0b11;
		if(relativeDirection.y == -1) data = (byte)0b0;
		if(relativeDirection.y == 1) data = (byte)0b1;
		if(relativeDirection.z == 1) data = (byte)0b100;
		if(relativeDirection.z == -1) data = (byte)0b101;
		if(data == -1) return false;
		currentData.data = data;
		return true;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return false;
	}

	@Override
	public Byte updateData(byte data, int dir) {
		return 0;
	}

	@Override
	public boolean checkTransparency(byte data, int dir) {
		return false;
	}

	@Override
	public byte getNaturalStandard() {
		return 0;
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
	public boolean checkEntity(Vector3f pos, float width, float height, int x, int y, int z, byte blockData) {
		return false;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity arg0, Vector4f arg1, int x, int y, int z, byte arg2) {
		return true;
	}
	
	@Override
	public int generateChunkMesh(BlockInstance bi, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		
		boolean[] directionInversion;
		int[] directionMap;
		switch(bi.getData()) {
			default:{
				directionInversion = new boolean[] {false, false, false};
				directionMap = new int[] {0, 1, 2};
				break;
			}
			case 1: {
				directionInversion = new boolean[] {true, true, false};
				directionMap = new int[] {0, 1, 2};
				break;
			}
			case 2: {
				directionInversion = new boolean[] {true, false, false};
				directionMap = new int[] {1, 0, 2};
				break;
			}
			case 3: {
				directionInversion = new boolean[] {false, true, false};
				directionMap = new int[] {1, 0, 2};
				break;
			}
			case 4: {
				directionInversion = new boolean[] {false, false, true};
				directionMap = new int[] {0, 2, 1};
				break;
			}
			case 5: {
				directionInversion = new boolean[] {false, true, false};
				directionMap = new int[] {0, 2, 1};
				break;
			}
		}
		
		Meshes.blockMeshes.get(bi.getBlock()).model.addToChunkMeshSimpleRotation(bi.x & 15, bi.y, bi.z & 15, directionMap, directionInversion, bi.getBlock().atlasX, bi.getBlock().atlasY, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
		return renderIndex + 1;
	}
}
