package cubyz.rendering.rotation;

import java.util.Random;

import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4d;

import cubyz.utils.Logger;
import cubyz.utils.VertexAttribList;
import cubyz.api.DataOrientedRegistry;
import cubyz.api.Resource;
import cubyz.client.BlockMeshes;
import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.json.JsonArray;
import cubyz.utils.json.JsonElement;
import cubyz.utils.json.JsonObject;
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

public class MultiTexture implements RotationMode, DataOrientedRegistry {

	private int size = 1;
	private int[][][] textureIndicesVariants = new int[Blocks.MAX_BLOCK_COUNT][][];
	private Random rand = new Random();

	@Override
	public int register(String assetFolder, Resource id, JsonObject json) {
		if (json.getString("rotation", "cubyz:no_rotation").equals(this.id.toString())) {
			JsonArray variants = json.getArray("multi_texture_variants");
			if (variants != null && variants.array.size() != 0) {
				int[][] indices = new int[variants.array.size()][6];
				textureIndicesVariants[size] = indices;
				for(int i = 0; i < variants.array.size(); i++) {
					JsonElement el = variants.array.get(i);
					if (el instanceof JsonObject) {
						BlockMeshes.getTextureIndices((JsonObject) el, assetFolder, indices[i]);
					}
				}
			} else {
				Logger.warning("Couldn't find \"multi_texture_variants\" argument for block "+id+". Using default textures instead.");
				textureIndicesVariants[size] = new int[1][];
				textureIndicesVariants[size][0] = BlockMeshes.textureIndices(size);
			}
		}
		return size++;
	}

	@Override
	public void reset(int len) {
		for(int i = len; i < size; i++) {
			textureIndicesVariants[i] = null;
		}
		size = len;
	}


	Resource id = new Resource("cubyz", "multi_texture");
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
		long seed = bi.x*4835871844237932163L ^ bi.y*80268680099511559L ^ bi.z*2595762606481225891L ^ bi.getBlock();
		rand.setSeed(seed);
		int randomIndex = rand.nextInt(textureIndicesVariants[bi.getBlock() & Blocks.TYPE_MASK].length);
		int[] indices = textureIndicesVariants[bi.getBlock() & Blocks.TYPE_MASK][randomIndex % textureIndicesVariants[bi.getBlock() & Blocks.TYPE_MASK].length];
		BlockMeshes.mesh(bi.getBlock() & Blocks.TYPE_MASK).model.addToChunkMesh(bi.x & Chunk.chunkMask, bi.y & Chunk.chunkMask, bi.z & Chunk.chunkMask, indices, bi.light, bi.getNeighbors(), vertices, faces);
	}
}

