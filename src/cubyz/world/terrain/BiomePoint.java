package cubyz.world.terrain;

import java.util.Random;

import cubyz.world.terrain.biomes.Biome;

public class BiomePoint {
	public final Biome biome;
	public final float x;
	public final float z;
	public final float height;
	public final long seed;
	public BiomePoint(Biome biome, float x, float z, float height, long seed) {
		this.biome = biome;
		this.x = x;
		this.z = z;
		this.height = height;
		this.seed = seed;
	}
	public float distSquare(float x, float z) {
		return (this.x - x)*(this.x - x) + (this.z - z)*(this.z - z);
	}
	public float maxNorm(float x, float z) {
		return Math.max(Math.abs(x - this.x), Math.abs(z - this.z));
	}
	public Biome getFittingReplacement(float height) {
		// Check if the existing Biome fits and if not choose a fitting replacement:
		Biome biome = this.biome;
		if (height < biome.minHeight) {
			Random rand = new Random(seed ^ 654295489239294L);
			while (height < biome.minHeight) {
				if (biome.lowerReplacements.length == 0) break;
				biome = biome.lowerReplacements[rand.nextInt(biome.lowerReplacements.length)];
			}
		} else if (height > biome.maxHeight) {
			Random rand = new Random(seed ^ 56473865395165948L);
			while (height > biome.maxHeight) {
				if (biome.upperReplacements.length == 0) break;
				biome = biome.upperReplacements[rand.nextInt(biome.upperReplacements.length)];
			}
		}
		return biome;
	}
}