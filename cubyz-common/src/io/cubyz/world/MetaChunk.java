package io.cubyz.world;

import io.cubyz.world.cubyzgenerators.biomes.Biome;

// A metaChunk stores map data for a much bigger area of the world.

public class MetaChunk {
	public float[][] heightMap, heatMap;
	public Biome[][] biomeMap;
	LocalPlanet world;
	public int x, y;
	
	public MetaChunk(int x, int y, long seed, LocalPlanet world) {
		this.x = x;
		this.y = y;
		this.world = world;
		heightMap = Noise.generateFractalTerrain(x, y, 256, 256, 512, seed, world.getWorldAnd());
		heatMap = Noise.generateFractalTerrain(x, y, 256, 256, 512, seed ^ 123456789, world.getWorldAnd()); // Somehow only a scale of 256 works. Other scales leave visible edges in the world. Not a huge issue, but I would rather use 512.
		biomeMap = new Biome[256][256];
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				biomeMap[i][j] = Biome.getBiome(heightMap[i][j], heatMap[i][j]);
			}
		}
		// Do internal heightMap updates based on biome. Interpolate between the four direct neighbors(if inside this metachunk):
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				heightMap[i][j] = Biome.evaluatePolynomial(heightMap[i][j], heatMap[i][j], heightMap[i][j]);
			}
		}
	}
}