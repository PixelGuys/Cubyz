package cubyz.rendering.rotation;

import org.joml.Matrix3f;
import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4d;

import cubyz.api.Resource;
import cubyz.client.Meshes;
import cubyz.rendering.models.Model;
import cubyz.utils.datastructures.ByteWrapper;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockInstance;
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
	public boolean generateData(ServerWorld world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, ByteWrapper currentData, boolean blockPlacing) {
		byte data = (byte)0;
		if(relativeDirection.x == 1) data = (byte)0b1;
		if(relativeDirection.x == -1) data = (byte)0b10;
		if(relativeDirection.y == -1) data = (byte)0b10000;
		if(relativeDirection.z == 1) data = (byte)0b100;
		if(relativeDirection.z == -1) data = (byte)0b1000;
		data |= currentData.data;
		if(data == currentData.data) return false;
		currentData.data = data;
		return true;
	}

	@Override
	public boolean dependsOnNeightbors() {
		return true;
	}

	@Override
	public Byte updateData(byte data, int dir, Block newNeighbor) {
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
	public boolean checkEntity(Vector3d pos, double width, double height, int x, int y, int z, byte blockData) {
		return false;
	}

	@Override
	public boolean checkEntityAndDoCollision(Entity arg0, Vector4d arg1, int x, int y, int z, byte arg2) {
		return true;
	}
	
	@Override
	public int generateChunkMesh(BlockInstance bi, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		byte data = bi.getData();
		Model model = Meshes.blockMeshes.get(bi.getBlock()).model;
		if((data & 0b1) != 0) {
			model.addToChunkMeshRotation((bi.x & NormalChunk.chunkMask) + 0.9f, (bi.y & NormalChunk.chunkMask) + 0.7f, (bi.z & NormalChunk.chunkMask) + 0.5f, POS_X, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if((data & 0b10) != 0) {
			model.addToChunkMeshRotation((bi.x & NormalChunk.chunkMask) + 0.1f, (bi.y & NormalChunk.chunkMask) + 0.7f, (bi.z & NormalChunk.chunkMask) + 0.5f, NEG_X, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if((data & 0b100) != 0) {
			model.addToChunkMeshRotation((bi.x & NormalChunk.chunkMask) + 0.5f, (bi.y & NormalChunk.chunkMask) + 0.7f, (bi.z & NormalChunk.chunkMask) + 0.9f, POS_Z, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if((data & 0b1000) != 0) {
			model.addToChunkMeshRotation((bi.x & NormalChunk.chunkMask) + 0.5f, (bi.y & NormalChunk.chunkMask) + 0.7f, (bi.z & NormalChunk.chunkMask) + 0.1f, NEG_Z, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		if((data & 0b10000) != 0) {
			model.addToChunkMeshRotation((bi.x & NormalChunk.chunkMask) + 0.5f, (bi.y & NormalChunk.chunkMask) + 0.5f, (bi.z & NormalChunk.chunkMask) + 0.5f, null, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
			renderIndex++;
		}
		return renderIndex;
	}
}
