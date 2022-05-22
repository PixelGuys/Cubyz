package cubyz.world.terrain.biomes;

import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * Generates stone boulders of various sizes.
 */
public class Boulder extends StructureModel {
	private final int block;
	private final float size, sizeVariation;

	public Boulder() {
		super(new Resource("cubyz", "boulder"), 0);
		block = 0;
		size = 0;
		sizeVariation = 0;
	}

	public Boulder(JsonObject json) {
		super(new Resource("cubyz", "boulder"), json.getFloat("chance", 0.5f));
		block = Blocks.getByID(json.getString("block", "cubyz:stone"));
		size = json.getFloat("size", 4);
		sizeVariation = json.getFloat("size_variation", 1);
	}

	@Override
	public void generate(int x, int z, int y, Chunk chunk, CaveMap map, FastRandom rand) {
		float radius = size + sizeVariation*(rand.nextFloat()*2 - 1);
		// My basic idea is to use a point cloud and a potential function to achieve somewhat smooth boulders without being a sphere.
		final int numberOfPoints = 4;
		float[] pointCloud = new float[numberOfPoints*3];
		for(int i = 0; i < pointCloud.length; i++) {
			pointCloud[i] = (rand.nextFloat() - 0.5f)*radius/2;
		}
		// My potential functions is ¹⁄ₙ Σ (radius/2)²/(x⃗ - x⃗ₚₒᵢₙₜ)²
		// This ensures that the entire boulder is inside of a square with sidelength 2*radius.
		for(int px = chunk.startIndex((int)(x - radius)); px <= (int)(x + radius); px += chunk.voxelSize) {
			for(int py = chunk.startIndex((int)(y - radius)); py <= (int)(y + radius); py += chunk.voxelSize) {
				for(int pz = chunk.startIndex((int)(z - radius)); pz <= (int)(z + radius); pz += chunk.voxelSize) {
					if (!chunk.liesInChunk(px, py, pz)) continue;
					float potential = 0;
					for(int i = 0; i < numberOfPoints; i++) {
						float dx = px - x - pointCloud[3*i];
						float dy = py - y - pointCloud[3*i + 1];
						float dz = pz - z - pointCloud[3*i + 2];
						float distSqr = dx*dx + dy*dy + dz*dz;
						potential += 1/distSqr;
					}
					potential *= radius*radius/4/numberOfPoints;
					if(potential >= 1) {
							chunk.updateBlockInGeneration(px, py, pz, block);
					}
				}
			}
		}
	}

	@Override
	public StructureModel loadStructureModel(JsonObject json) {
		return new Boulder(json);
	}
}
