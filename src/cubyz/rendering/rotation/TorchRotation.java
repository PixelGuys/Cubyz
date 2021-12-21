package cubyz.rendering.rotation;

import org.joml.Matrix3f;
import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4d;

import cubyz.api.Resource;
import cubyz.client.BlockMeshes;
import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.Entity;

/**
 * Rotates and translates the model, so it hangs on the wall or stands on the ground like a torch.<br>
 * It also allows the player to place multiple torches of the same type in different rotation in the same block.
 */

public class TorchRotation implements RotationMode {
	// Rotation/translation matrices for torches on the wall:
	private static final Matrix3f POS_X = new Matrix3f().identity().rotateXYZ(0, 0, 0.3f);
	private static final Matrix3f NEG_X = new Matrix3f().identity().rotateXYZ(0, 0, -0.3f);
	private static final Matrix3f POS_Z = new Matrix3f().identity().rotateXYZ(-0.3f, 0, 0);
	private static final Matrix3f NEG_Z = new Matrix3f().identity().rotateXYZ(0.3f, 0, 0);
	
	Resource id = new Resource("cubyz", "torch");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public boolean generateData(ServerWorld world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, IntWrapper currentData, boolean blockPlacing) {
		int data = 0;
		if (relativeDirection.x == 1) data = 0b1;
		if (relativeDirection.x == -1) data = 0b10;
		if (relativeDirection.y == -1) data = 0b10000;
		if (relativeDirection.z == 1) data = 0b100;
		if (relativeDirection.z == -1) data = 0b1000;
		data |= currentData.data >>> 16;
		if (data == currentData.data >>> 16) return false;
		currentData.data = (currentData.data & Blocks.TYPE_MASK) | data << 16;
		return true;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return true;
	}

	@Override
	public int updateData(int block, int dir, int newNeighbor) {
		int data = block >>> 16;
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
		if (data == 0) return 0;
		return (block & Blocks.TYPE_MASK) | data << 16;
	}

	@Override
	public boolean checkTransparency(int block, int dir) {
		return false;
	}

	@Override
	public int getNaturalStandard(int block) {
		return block | 0x10000;
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
	public int generateChunkMesh(BlockInstance bi, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		int data = bi.getBlock() >>> 16;
		Model model = BlockMeshes.mesh(bi.getBlock() & Blocks.TYPE_MASK).model;
		if ((data & 0b1) != 0) {
			model.addToChunkMeshRotation((bi.x & Chunk.chunkMask) + 0.9f, (bi.y & Chunk.chunkMask) + 0.7f, (bi.z & Chunk.chunkMask) + 0.5f, POS_X, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if ((data & 0b10) != 0) {
			model.addToChunkMeshRotation((bi.x & Chunk.chunkMask) + 0.1f, (bi.y & Chunk.chunkMask) + 0.7f, (bi.z & Chunk.chunkMask) + 0.5f, NEG_X, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if ((data & 0b100) != 0) {
			model.addToChunkMeshRotation((bi.x & Chunk.chunkMask) + 0.5f, (bi.y & Chunk.chunkMask) + 0.7f, (bi.z & Chunk.chunkMask) + 0.9f, POS_Z, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if ((data & 0b1000) != 0) {
			model.addToChunkMeshRotation((bi.x & Chunk.chunkMask) + 0.5f, (bi.y & Chunk.chunkMask) + 0.7f, (bi.z & Chunk.chunkMask) + 0.1f, NEG_Z, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if ((data & 0b10000) != 0) {
			model.addToChunkMeshRotation((bi.x & Chunk.chunkMask) + 0.5f, (bi.y & Chunk.chunkMask) + 0.5f, (bi.z & Chunk.chunkMask) + 0.5f, null, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		return renderIndex;
	}
}
