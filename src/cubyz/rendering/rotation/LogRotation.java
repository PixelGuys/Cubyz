package cubyz.rendering.rotation;

import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4d;

import cubyz.api.Resource;
import cubyz.client.BlockMeshes;
import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.VertexAttribList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Chunk;
import cubyz.world.World;
import cubyz.world.blocks.Blocks;
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
	public boolean generateData(World world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, IntWrapper currentData, boolean blockPlacing) {
		if (!blockPlacing) return false;
		int data = -1;
		if (relativeDirection.x == 1) data = (byte)0b10;
		if (relativeDirection.x == -1) data = (byte)0b11;
		if (relativeDirection.y == -1) data = (byte)0b0;
		if (relativeDirection.y == 1) data = (byte)0b1;
		if (relativeDirection.z == 1) data = (byte)0b100;
		if (relativeDirection.z == -1) data = (byte)0b101;
		if (data == -1) return false;
		currentData.data = (currentData.data & Blocks.TYPE_MASK) | data << 16;
		return true;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return false;
	}

	@Override
	public int updateData(int block, int dir, int newNeighbor) {
		return block;
	}

	@Override
	public boolean checkTransparency(int block, int dir) {
		return false;
	}

	@Override
	public int getNaturalStandard(int block) {
		return block;
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
	public boolean checkEntity(Vector3d pos, double width, double height, int x, int y, int z, int block) {
		return false;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity arg0, Vector4d arg1, int x, int y, int z, int block) {
		return true;
	}
	
	@Override
	public void generateChunkMesh(BlockInstance bi, VertexAttribList vertices, IntFastList faces) {
		
		boolean[] directionInversion;
		int[] directionMap;
		switch(bi.getBlock() >>> 16) {
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
		
		BlockMeshes.mesh(bi.getBlock() & Blocks.TYPE_MASK).model.addToChunkMeshSimpleRotation(bi.x & Chunk.chunkMask, bi.y & Chunk.chunkMask, bi.z & Chunk.chunkMask, directionMap, directionInversion, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, faces);
	}
}
