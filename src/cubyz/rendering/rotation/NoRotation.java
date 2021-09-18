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
 * The default RotationMode that places the block in the grid without translation or rotation.
 */

public class NoRotation implements RotationMode {
	Resource id = new Resource("cubyz", "no_rotation");
	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public boolean generateData(Surface surface, int x, int y, int z, Vector3f relativePlayerPosition, Vector3f playerDirection, Vector3i relativeDirection, ByteWrapper currentData, boolean blockPlacing) {
		if(!blockPlacing) return false;
		currentData.data = 0;
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
		Meshes.blockMeshes.get(bi.getBlock()).model.addToChunkMesh(bi.x & NormalChunk.chunkMask, bi.y & NormalChunk.chunkMask, bi.z & NormalChunk.chunkMask, bi.getBlock().textureIndices, bi.light, bi.getNeighbors(), vertices, normals, faces, lighting, texture, renderIndices, renderIndex);
		return renderIndex + 1;
	}
}
