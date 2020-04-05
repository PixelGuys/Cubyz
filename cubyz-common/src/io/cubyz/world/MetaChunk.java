package io.cubyz.world;

import io.cubyz.world.cubyzgenerators.biomes.Biome;

// A metaChunk stores map data for a much bigger area of the world.

public class MetaChunk {
	float[][] heightMap, heatMap;
	Biome[][] biomeMap;
	LocalWorld world;
	int x, y;
	
	public MetaChunk(int x, int y, long seed, LocalWorld world) {
		this.x = x;
		this.y = y;
		this.world = world;
		heightMap = Noise.generateFractalTerrain(x, y, 256, 256, 512, seed);
		heatMap = Noise.generateFractalTerrain(x, y, 256, 256, 512, seed ^ 123456789); // Somehow only a scale of 256 works. Other scales leave visible edges in the world. Not a huge issue, but I would rather use 512.
		biomeMap = new Biome[256][256];
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				biomeMap[i][j] = Biome.getBiome(heightMap[i][j], heatMap[i][j]);
			}
		}
		// Do internal heightMap updates based on biome. Interpolate between the four direct neighbors(if inside this metachunk):
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				int n = 5;
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				if(i == 0) {
					n--;
				} else {
					res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				}
				if(i == 255) {
					n--;
				} else {
					res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				}
				if(j == 0) {
					n--;
				} else {
					res += biomeMap[i][j-1].evaluatePolynomial(heightMap[i][j]);
				}
				if(j == 255) {
					n--;
				} else {
					res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				}
				heightMap[i][j] = res/n;
			}
		}
	}
}