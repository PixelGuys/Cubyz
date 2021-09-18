package cubyz.rendering.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import cubyz.api.Resource;
import cubyz.client.Meshes;
import cubyz.utils.datastructures.ByteWrapper;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.NormalChunk;
import cubyz.world.Surface;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.Entity;

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
	public boolean generateData(Surface surface, int x, int y, int z, Vector3f relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, ByteWrapper currentData, boolean blockPlacing) {
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
	public Byte updateData(byte data, int dir, Block newNeighbor) {
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
		
		Meshes.blockMeshes.get(bi.getBlock()).model.addToChunkMeshSimpleRotation(bi.x & NormalChunk.chunkMask, bi.y & NormalChunk.chunkMask, bi.z & NormalChunk.chunkMask, directionMap, directionInversion, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
		return renderIndex + 1;
	}
}
