package io.cubyz.world;

// A metaChunk stores map data for a much bigger area of the world.

public class MetaChunk {
	float[][] heightMap, heatMap;
	int x, y;
	
	public MetaChunk(int x, int y, long seed) {
		this.x = x;
		this.y = y;
		heightMap = Noise.generateFractalTerrain(x, y, 256, 256, 256, seed);
		heatMap = Noise.generateMapFragment(x, y, 256, 256, 256, seed ^ 123456789); // Somehow only a scale of 256 works. Other scales leave visible edges in the world. Not a huge issue, but I would rather use 512.
	}
}