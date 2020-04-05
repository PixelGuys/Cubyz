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
		heightMap = Noise.generateFractalTerrain(x, y, 256, 256, 256, seed);
		heatMap = Noise.generateMapFragment(x, y, 256, 256, 256, seed ^ 123456789); // Somehow only a scale of 256 works. Other scales leave visible edges in the world. Not a huge issue, but I would rather use 512.
		biomeMap = new Biome[256][256];
		for(int i = 0; i < 256; i++) {
			for(int j = 0; j < 256; j++) {
				biomeMap[i][j] = Biome.getBiome(heightMap[i][j], heatMap[i][j]);
			}
		}
		// Do internal heightMap updates based on biome:
		for(int i = 1; i < 255; i++) {
			for(int j = 1; j < 255; j++) {
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j-1].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
		}
		// Check the surrounding Metachunks:
		MetaChunk nX = world.getNoGenerateMetaChunk(x-256, y);
		MetaChunk pX = world.getNoGenerateMetaChunk(x+256, y);
		MetaChunk nY = world.getNoGenerateMetaChunk(x, y-256);
		MetaChunk pY = world.getNoGenerateMetaChunk(x, y+256);
		if(nX != null) {
			int i = 0;
			for(int j = 1; j < 255; j++) {
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += nX.biomeMap[255][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j-1].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			if(nY != null) {
				int j = 0;
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += nX.biomeMap[255][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				res += nY.biomeMap[i][255].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			if(pY != null) {
				int j = 0;
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += nX.biomeMap[255][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j-1].evaluatePolynomial(heightMap[i][j]);
				res += pY.biomeMap[i][0].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			i = 255;
			for(int j = 1; j < 255; j++) {
				float res = 0;
				res += nX.biomeMap[i][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i-1][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += biomeMap[0][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i][j-1].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i][j+1].evaluatePolynomial(nX.heightMap[i][j]);
				nX.heightMap[i][j] = res/5;
			}
		}
		if(pX != null) {
			int i = 255;
			for(int j = 1; j < 255; j++) {
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				res += pX.biomeMap[0][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j-1].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			if(nY != null) {
				int j = 0;
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				res += pX.biomeMap[0][j].evaluatePolynomial(heightMap[i][j]);
				res += nY.biomeMap[i][255].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			if(pY != null) {
				int j = 255;
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				res += pX.biomeMap[0][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j-1].evaluatePolynomial(heightMap[i][j]);
				res += pY.biomeMap[i][0].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			i = 0;
			for(int j = 1; j < 255; j++) {
				float res = 0;
				res += pX.biomeMap[i][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += biomeMap[255][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i+1][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i][j-1].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i][j+1].evaluatePolynomial(pX.heightMap[i][j]);
				pX.heightMap[i][j] = res/5;
			}
		}
		if(nY != null) {
			int j = 0;
			for(int i = 1; i < 255; i++) {
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				res += nY.biomeMap[i][255].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][j+1].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			j = 255;
			for(int i = 1; i < 255; i++) {
				float res = 0;
				res += nY.biomeMap[i][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i-1][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i+1][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i][j-1].evaluatePolynomial(nY.heightMap[i][j]);
				res += biomeMap[i][0].evaluatePolynomial(nY.heightMap[i][j]);
				nY.heightMap[i][j] = res/5;
			}
		}
		if(pY != null) {
			int j = 255;
			for(int i = 1; i < 255; i++) {
				float res = 0;
				res += biomeMap[i][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i-1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i+1][j].evaluatePolynomial(heightMap[i][j]);
				res += biomeMap[i][i-1].evaluatePolynomial(heightMap[i][j]);
				res += pY.biomeMap[i][0].evaluatePolynomial(heightMap[i][j]);
				heightMap[i][j] = res/5;
			}
			j = 0;
			for(int i = 1; i < 255; i++) {
				float res = 0;
				res += pY.biomeMap[i][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i-1][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i+1][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += biomeMap[i][255].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i][j+1].evaluatePolynomial(pY.heightMap[i][j]);
				pY.heightMap[i][j] = res/5;
			}
		}
		// Now the corner cases in those neighboring metachunks:
		MetaChunk nn = world.getNoGenerateMetaChunk(x-256, y-256);
		MetaChunk np = world.getNoGenerateMetaChunk(x-256, y+256);
		MetaChunk pn = world.getNoGenerateMetaChunk(x+256, y-256);
		MetaChunk pp = world.getNoGenerateMetaChunk(x+256, y+256);
		if(nn != null) {
			if(nX != null) {
				int i = 255, j = 0;
				float res = 0;
				res += nX.biomeMap[i][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i-1][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += biomeMap[0][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += nn.biomeMap[i][255].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i][j+1].evaluatePolynomial(nX.heightMap[i][j]);
				nX.heightMap[i][j] = res/5;
			}
			if(nY != null) {
				int i = 0, j = 255;
				float res = 0;
				res += nY.biomeMap[i][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nn.biomeMap[255][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i+1][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i][j-1].evaluatePolynomial(nY.heightMap[i][j]);
				res += biomeMap[i][0].evaluatePolynomial(nY.heightMap[i][j]);
				nY.heightMap[i][j] = res/5;
			}
		}
		if(np != null) {
			if(nX != null) {
				int i = 255, j = 255;
				float res = 0;
				res += nX.biomeMap[i][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i-1][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += biomeMap[0][j].evaluatePolynomial(nX.heightMap[i][j]);
				res += nX.biomeMap[i][j-1].evaluatePolynomial(nX.heightMap[i][j]);
				res += np.biomeMap[i][0].evaluatePolynomial(nX.heightMap[i][j]);
				nX.heightMap[i][j] = res/5;
			}
			if(pY != null) {
				int i = 0, j = 0;
				float res = 0;
				res += pY.biomeMap[i][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += np.biomeMap[255][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i+1][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += biomeMap[i][255].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i][j+1].evaluatePolynomial(pY.heightMap[i][j]);
				pY.heightMap[i][j] = res/5;
			}
		}
		if(pn != null) {
			if(pX != null) {
				int i = 0, j = 0;
				float res = 0;
				res += pX.biomeMap[i][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += biomeMap[255][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i+1][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += pn.biomeMap[i][255].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i][j+1].evaluatePolynomial(pX.heightMap[i][j]);
				pX.heightMap[i][j] = res/5;
			}
			if(nY != null) {
				int i = 255, j = 255;
				float res = 0;
				res += nY.biomeMap[i][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i-1][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += pn.biomeMap[0][j].evaluatePolynomial(nY.heightMap[i][j]);
				res += nY.biomeMap[i][j-1].evaluatePolynomial(nY.heightMap[i][j]);
				res += biomeMap[i][0].evaluatePolynomial(nY.heightMap[i][j]);
				nY.heightMap[i][j] = res/5;
			}
		}
		if(pp != null) {
			if(pX != null) {
				int i = 0, j = 255;
				float res = 0;
				res += pX.biomeMap[i][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += biomeMap[255][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i+1][j].evaluatePolynomial(pX.heightMap[i][j]);
				res += pX.biomeMap[i][j-1].evaluatePolynomial(pX.heightMap[i][j]);
				res += pp.biomeMap[i][0].evaluatePolynomial(pX.heightMap[i][j]);
				pX.heightMap[i][j] = res/5;
			}
			if(nY != null) {
				int i = 255, j = 0;
				float res = 0;
				res += pY.biomeMap[i][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i-1][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += pp.biomeMap[0][j].evaluatePolynomial(pY.heightMap[i][j]);
				res += biomeMap[i][255].evaluatePolynomial(pY.heightMap[i][j]);
				res += pY.biomeMap[i][j+1].evaluatePolynomial(pY.heightMap[i][j]);
				pY.heightMap[i][j] = res/5;
			}
		}
	}
}