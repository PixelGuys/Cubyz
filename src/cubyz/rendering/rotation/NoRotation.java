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
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.Entity;

/**
 * The default RotationMode that places the block in the grid without translation or rotation.
 */

public class NoRotation implements RotationMode {
	Resource id = new Resource("cubyz", "no_rotation");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public boolean generateData(World world, int x, int y, int z, Vector3d relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, IntWrapper currentData, boolean blockPlacing) {
		if (!blockPlacing) return false;
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
		BlockMeshes.mesh(bi.getBlock() & Blocks.TYPE_MASK).model.addToChunkMesh(bi.x & Chunk.chunkMask, bi.y & Chunk.chunkMask, bi.z & Chunk.chunkMask, BlockMeshes.textureIndices(bi.getBlock()), bi.light, bi.getNeighbors(), vertices, faces);
	}
}
