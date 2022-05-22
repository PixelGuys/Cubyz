package cubyz.world.terrain.generators;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.FastRandom;
import cubyz.world.Chunk;
import cubyz.world.NormalChunk;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.Blocks.BlockClass;
import cubyz.world.terrain.CaveBiomeMap;
import cubyz.world.terrain.CaveMap;
import pixelguys.json.JsonObject;

/**
 * Generates a special cavern that contains giant crystals.
 */

public class CrystalGenerator implements Generator {

	private final String[] COLORS = new String[] {
			"red", "orange", "yellow", "green", "cyan", "blue", "violet", "purple", // 8 Base colors
			"dark_red", "dark_green", "light_blue", "brown", // 4 darker colors
			"white", "gray", "dark_gray", "black", // 4 grayscale colors
	};
	private final int[] glowCrystals = new int[COLORS.length];

	private static final int SURFACE_DIST = 2; // How far away crystal can spawn from the wall.


	public CrystalGenerator() {

	}

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		// Find all the glow crystal ores:
		for(int i = 0; i < COLORS.length; i++) {
			String color = COLORS[i];
			String oreID = "cubyz:glow_crystal/"+color;
			glowCrystals[i] = Blocks.getByID(oreID);
		}
	}


	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "crystal");
	}

	@Override
	public int getPriority() {
		return 65537; // Directly after normal caves.
	}

	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, CaveMap caveMap, CaveBiomeMap biomeMap) {
		if (chunk.voxelSize > 2) return;
		int size = chunk.getWidth();
		FastRandom rand = new FastRandom(seed);
		int rand1 = rand.nextInt() | 1;
		int rand2 = rand.nextInt() | 1;
		int rand3 = rand.nextInt() | 1;
		// Generate caves from all nearby chunks:
		for(int x = wx - NormalChunk.chunkSize; x < wx + size + NormalChunk.chunkSize; x += NormalChunk.chunkSize) {
			for(int y = wy - NormalChunk.chunkSize; y < wy + size + NormalChunk.chunkSize; y += NormalChunk.chunkSize) {
				for(int z = wz - NormalChunk.chunkSize; z < wz + size + NormalChunk.chunkSize; z += NormalChunk.chunkSize) {
					int randX = x*rand1;
					int randY = y*rand2;
					int randZ = z*rand3;
					rand.setSeed((randY << 48) ^ (randY >>> 16) ^ (randX << 32) ^ randZ ^ seed);
					considerCoordinates(x, y, z, chunk, caveMap, biomeMap, rand);
				}
			}
		}
	}

	private double distSqr(double x, double y, double z) {
		return x*x+y*y+z*z;
	}

	private void considerCrystal(int wx, int wy, int wz, int x, int y, int z, Chunk chunk, FastRandom rand, boolean useNeedles, int[] types) {
		x -= wx;
		y -= wy;
		z -= wz;
		int type = types[rand.nextInt(types.length)];
		// Make some crystal spikes in random directions:
		int spikes = 4;
		if (useNeedles) spikes++;
		spikes += rand.nextInt(spikes); // Use somewhat between spikes and 2*spikes spikes.
		for(int i = 0; i < spikes; i++) {
			int length = rand.nextInt(24)+8;
			// Choose a random direction:
			double theta = 2*Math.PI*rand.nextDouble();
			double phi = Math.acos(1 - 2*rand.nextDouble());
			double delX = Math.sin(phi)*Math.cos(theta);
			double delY = Math.sin(phi)*Math.sin(theta);
			double delZ = Math.cos(phi);
			for(double j = 0; j < length;) {
				double x2 = x + delX*j;
				double y2 = y + delY*j;
				double z2 = z + delZ*j;
				double size;
				if (useNeedles)
					size = 0.7;
				else
					size = 12*(length-j)/length/spikes;
				int xMin = (int)(x2-size);
				int xMax = (int)(x2+size);
				int yMin = (int)(y2-size);
				int yMax = (int)(y2+size);
				int zMin = (int)(z2-size);
				int zMax = (int)(z2+size);
				for(int x3 = xMin; x3 <= xMax; x3++) {
					for(int y3 = yMin; y3 <= yMax; y3++) {
						for(int z3 = zMin; z3 <= zMax; z3++) {
							double dist = distSqr(x3-x2, y3-y2, z3-z2);
							if (dist <= size*size) {
								if (x3 >= 0 && x3 < chunk.getWidth() && y3 >= 0 && y3 < chunk.getWidth() && z3 >= 0 && z3 < chunk.getWidth()) {
									if (chunk.getBlock(x3, y3, z3) == 0 || Blocks.degradable(chunk.getBlock(x3, y3, z3)) || Blocks.blockClass(chunk.getBlock(x3, y3, z3)) == BlockClass.FLUID) {
										chunk.updateBlockInGeneration(x3, y3, z3, glowCrystals[type]);
									}
								}
							}
						}
					}
				}
				if (size > 2) size = 2;
				j += size/2; // Make sure there are no crystal bits floating in the air.
				if (size < 0.5) break; // Also preventing floating crystal bits.
			}
		}
	}

	private void considerCoordinates(int x, int y, int z, Chunk chunk, CaveMap caveMap, CaveBiomeMap biomeMap, FastRandom rand) {
		long[] biomeMapSeed = new long[1];
		int crystalSpawns = biomeMap.getBiomeAndSeed(x + Chunk.chunkSize/2 - chunk.wx, y + Chunk.chunkSize/2 - chunk.wy, z + Chunk.chunkSize/2 - chunk.wz, biomeMapSeed).crystals;
		long oldSeed = rand.nextLong();
		// Select the colors using a biome specific seed:
		rand.setSeed(biomeMapSeed[0]);
		int differentColors = 1;
		if(rand.nextBoolean()) {
			// ¹⁄₄ Chance that a cave has multiple crystals.
			while(rand.nextBoolean() && differentColors < 32) {
				differentColors++; // Exponentially diminishing chance to have multiple crystals per cavern.
			}
		}
		int[] colors = new int[differentColors];
		for(int i = 0; i < differentColors; i++) {
			colors[i] = rand.nextInt(COLORS.length);
		}
		boolean useNeedles = rand.nextBoolean(); // Different crystal type.
		// Spawn the crystals using the old position specific seed:
		rand.setSeed(oldSeed);
		for(int crystal = 0; crystal < crystalSpawns; crystal++) {
			// Choose some in world coordinates to start generating:
			int worldX = x + rand.nextInt(NormalChunk.chunkSize);
			int worldY = y + rand.nextInt(NormalChunk.chunkSize);
			int worldZ = z + rand.nextInt(NormalChunk.chunkSize);
			int relX = worldX - chunk.wx;
			int relY = worldY - chunk.wy;
			int relZ = worldZ - chunk.wz;
			if(caveMap.isSolid(relX, relY, relZ)) {// Only start crystal in solid blocks
				if( // Only start crystal when they are close to the surface (±SURFACE_DIST blocks)
					(worldX - x >= SURFACE_DIST && !caveMap.isSolid(relX - SURFACE_DIST, relY, relZ))
					|| (worldX - x < Chunk.chunkSize - SURFACE_DIST && !caveMap.isSolid(relX + SURFACE_DIST, relY, relZ))
					|| (worldY - y >= SURFACE_DIST && !caveMap.isSolid(relX, relY - SURFACE_DIST, relZ))
					|| (worldY - y < Chunk.chunkSize - SURFACE_DIST && !caveMap.isSolid(relX, relY + SURFACE_DIST, relZ))
					|| (worldZ - z >= SURFACE_DIST && !caveMap.isSolid(relX, relY, relZ - SURFACE_DIST))
					|| (worldZ - z < Chunk.chunkSize - SURFACE_DIST && !caveMap.isSolid(relX, relY, relZ + SURFACE_DIST))
				) {
					// Generate the crystal:
					considerCrystal(chunk.wx, chunk.wy, chunk.wz, worldX, worldY, worldZ, chunk, rand, useNeedles, colors);
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x9b450ffb0d415317L;
	}
}
