package cubyz.world.terrain.generators;

import java.util.Random;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.NormalChunk;
import cubyz.world.ChunkManager;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.Ore;
import cubyz.world.terrain.MapFragment;

/**
 * Generator of ore veins.
 */

public class OreGenerator implements Generator {
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_ore");
	}
	
	@Override
	public int getPriority() {
		return 32768; // Somewhere before cave generation.
	}

	private Ore[] ores;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		ores = registries.oreRegistry.registered(new Ore[0]);
	}


	// Works basically similar to cave generation, but considers a lot less chunks and has a few other differences.
	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ChunkManager generator) {
		if (!(chunk instanceof NormalChunk)) return;
		Random rand = new Random(seed);
		int rand1 = rand.nextInt() | 1;
		int rand2 = rand.nextInt() | 1;
		int rand3 = rand.nextInt() | 1;
		int cx = wx >> NormalChunk.chunkShift;
		int cy = wy >> NormalChunk.chunkShift;
		int cz = wz >> NormalChunk.chunkShift;
		// Generate caves from all nearby chunks:
		for(int x = cx - 1; x <= cx + 1; ++x) {
			for(int y = cy - 1; y <= cy + 1; ++y) {
				for(int z = cz - 1; z <= cz + 1; ++z) {
					int randX = x*rand1;
					int randY = y*rand2;
					int randZ = z*rand3;
					considerCoordinates(x, y, z, cx, cy, cz, chunk, (randY << 48) ^ (randY >>> 16) ^ (randX << 32) ^ randZ ^ seed);
				}
			}
		}
	}

	private void considerCoordinates(int x, int y, int z, int cx, int cy, int cz, Chunk chunk, long seed) {
		Random rand = new Random();
		for(int i = 0; i < ores.length; i++) {
			if (ores[i].maxHeight <= y << NormalChunk.chunkShift) continue;
			// Compose the seeds from some random stats of the ore. They generally shouldn't be the same for two different ores.
			rand.setSeed(seed^(ores[i].maxHeight)^(Float.floatToIntBits(ores[i].size))^Blocks.id(ores[i].block).getID().charAt(0)^Float.floatToIntBits(Blocks.hardness(ores[i].block)));
			// Determine how many veins of this type start in this chunk. The number depends on parameters set for the specific ore:
			int veins = (int)ores[i].veins;
			if (ores[i].veins - veins >= rand.nextFloat()) veins++;
			for(int j = 0; j < veins; ++j) {
				// Choose some in world coordinates to start generating:
				double relX = (x-cx << NormalChunk.chunkShift) + rand.nextFloat()*NormalChunk.chunkSize;
				double relY = (y-cy << NormalChunk.chunkShift) + rand.nextFloat()*NormalChunk.chunkSize;
				double relZ = (z-cz << NormalChunk.chunkShift) + rand.nextFloat()*NormalChunk.chunkSize;
				// Choose a random direction for the main axis of the ellipsoid. This approach is a little biased towards the corners, but I don't care.
				double dirX = rand.nextFloat() - 0.5f;
				double dirY = rand.nextFloat() - 0.5f;
				double dirZ = rand.nextFloat() - 0.5f;
				
				double unitLength = Math.sqrt(dirX*dirX + dirY*dirY + dirZ*dirZ);
				// Choose a random ratio between main and the other sides:
				double ratio = rand.nextFloat() + 1;
				// Simple sphere formula with 2 shorter sides.
				double unitVolume = unitLength*unitLength/ratio*unitLength/ratio*Math.PI*4/3;

				// Now choose a size. Size as in how many blocks should be ore. The total volume will be determined by the density.
				double size = (rand.nextFloat() + 0.5f)*ores[i].size;
				double expectedVolume = size/ores[i].density;

				// By how much the dir vector needs to be scaled. Chooses twice the volume to make sure that even at high density all ores can fit.
				double scale = Math.pow(2*expectedVolume/unitVolume, 1/3.0);

				// Choose 2*`size` random points inside the ellipsoid. It is actually good if there is more points in the center.
				// There are twice as many samples taken because often the random point will already be taken by another ore.
				for(int num = 0; num < size*2; num++) {
					// Because of that the easiest approach is to start with a random point in a sphere using uniform distribution in a spherical coordinate system. This leads to more points in the center.
					double r = Math.pow(rand.nextFloat(), 1+ores[i].density)*scale*unitLength/ratio; // The power here is to make sure that at high densities the result is more uniform, so the target block count can be met easier.
					double phi = rand.nextFloat()*Math.PI*2;
					double theta = rand.nextFloat()*Math.PI;
					double xPoint = r*Math.cos(theta);
					double yPoint = r*Math.sin(theta)*Math.cos(phi);
					double zPoint = r*Math.sin(theta)*Math.sin(phi);
					// Then the result can be morphed onto the ellipsoid.
					double proj = xPoint*dirX/unitLength + yPoint*dirX/unitLength + zPoint*dirX/unitLength;
					xPoint += proj*dirX/unitLength;
					yPoint += proj*dirY/unitLength;
					zPoint += proj*dirZ/unitLength;
					// And that's it!
					xPoint += relX;
					yPoint += relY;
					zPoint += relZ;
					if (xPoint >= 0 && xPoint < NormalChunk.chunkSize && yPoint >= 0 && yPoint < NormalChunk.chunkSize && zPoint >= 0 && zPoint < NormalChunk.chunkSize) { // Bound check.
						if (ores[i].canCreateVeinInBlock(chunk.getBlock((int)xPoint, (int)yPoint, (int)zPoint))) {
							chunk.updateBlockInGeneration((int)xPoint, (int)yPoint, (int)zPoint, ores[i].block);
						}
					}
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x88773787bc9e0105L;
	}
}
