package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Region;

/**
 * Used to generate rivers.<br>
 * TODO: Make them a lot bigger.
 */

public class RiverGenerator implements BigGenerator {
	
	@Override
	public int getPriority() {
		return 1536;
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_river");
	}
	private static Block water = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water");

	@Override
	public void generate(long seed, int lx, int lz, NormalChunk chunk, boolean[][] vegetationIgnoreMap, Region nn, Region np, Region pn, Region pp) {
		// Consider coordinates in each Region.
		considerRegion(nn, lx, lz, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
		considerRegion(np, lx, lz, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
		considerRegion(pn, lx, lz, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
		considerRegion(pp, lx, lz, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
	}
	
	private void considerRegion(Region reg, int lx, int lz, NormalChunk chunk, Region nn, Region np, Region pn, Region pp, long seed, boolean[][] vegetationIgnoreMap) {
		Random rand = new Random(seed^((long)reg.wx*Float.floatToRawIntBits(reg.heightMap[255][0]))^((long)reg.wz*Float.floatToRawIntBits(reg.heightMap[0][255])));
		int num = 2 + rand.nextInt(4);
		for(int i = 0; i < num; i++) {
			int x = rand.nextInt(256);
			int z = rand.nextInt(256);
			if(reg.biomeMap[x][z].supportsRivers) {
				if(reg == pp || reg == pn) {
					x += 256;
				}
				if(reg == pp || reg == np) {
					z += 256;
				}
				makeRiver(x, z, lx, lz, chunk, nn, np, pn, pp, rand.nextFloat()+1.5f, x, z, new float[2], getHeight(x, z, nn, np, pn, pp), vegetationIgnoreMap, 256);
			}
		}
	}
	
	private float getHeight(int x, int z, Region nn, Region np, Region pn, Region pp) {
		if(x < 256) {
			if(z < 256) {
				return nn.heightMap[x][z];
			} else {
				return np.heightMap[x][z-256];
			}
		} else {
			if(z < 256) {
				return pn.heightMap[x-256][z];
			} else {
				return pp.heightMap[x-256][z-256];
			}
		}
	}
	
	float[] getGradient(int x, int z, Region nn, Region np, Region pn, Region pp) {
		float[] res = new float[2];
		res[0] = -(getHeight(x+1, z, nn, np, pn, pp) - getHeight(x-1, z, nn, np, pn, pp));
		res[1] = -(getHeight(x, z+1, nn, np, pn, pp) - getHeight(x, z-1, nn, np, pn, pp));
		return res;
	}
	private float[] getGradient(float dx, float dz, float[] grad00, float[] grad01, float[] grad10, float[] grad11) {
		float[] res = new float[2];
		for(int i = 0; i < 2; i++) {
			res[i] += dx*dz*grad11[i];
			res[i] += dx*(1-dz)*grad10[i];
			res[i] += (1-dx)*dz*grad01[i];
			res[i] += (1-dx)*(1-dz)*grad00[i];
		}
		return res;
	}
	
	private void makeRiver(float x, float z, int lx, int lz, NormalChunk chunk, Region nn, Region np, Region pn, Region pp, float width, int x00, int y00, float[] oldDir, float curHeight, boolean[][] vegetationIgnoreMap, int maxLength) {
		float dist = (float)Math.sqrt((x-x00)*(x-x00) + (z-y00)*(z-y00));
		if(128-dist-2*width <= 0 || maxLength == 0) return;
		// Get the gradient of the surrounding positions in the heightMap:
		int x0 = (int)x;
		int y0 = (int)z;
		int x1 = x0+1;
		int y1 = y0+1;
		if(x0 <= 0 || y0 <= 0 || x1 >= 511 || y1 >= 511) return; // Don't leave the 4 surrounding regions.
		float[] grad00 = getGradient(x0, y0, nn, np, pn, pp);
		float[] grad01 = getGradient(x0, y1, nn, np, pn, pp);
		float[] grad10 = getGradient(x1, y0, nn, np, pn, pp);
		float[] grad11 = getGradient(x1, y1, nn, np, pn, pp);
		// Get an estimation of the gradient at the float position and normalize it so the river movement is 1:
		float[] dir = getGradient(x%1, z%1, grad00, grad01, grad10, grad11);
		float val = (float)Math.sqrt(dir[0]*dir[0] + dir[1]*dir[1]);
		if(dir[0]*oldDir[0]+dir[1]*oldDir[1] <= -0.9*val && maxLength > 5) {
			maxLength = 5; // The river has to end if the direction of flow and the mountain slope are too far apart.
		}
		if(oldDir[0] != 0 || oldDir[1] != 0) {
			dir[0] += oldDir[0]/16;
			dir[1] += oldDir[1]/16;
		}
		val = (float)Math.sqrt(dir[0]*dir[0] + dir[1]*dir[1]);
		dir[0] /= val;
		dir[1] /= val;
		float nextHeight = Math.min(curHeight, getHeight(x0, y0, nn, np, pn, pp));
		if(nextHeight <= 102.0f/256.0f) return; // No need to get any lower than sea level.
		if(128-dist-2*width <= 5 || maxLength <= 5) {
			if(maxLength > 5) maxLength = 5;
			nextHeight -= 0.004f; // Let the river slowly disappear underground.
		}
		makeRiver(x+dir[0], z+dir[1], lx, lz, chunk, nn, np, pn, pp, width, x00, y00, dir, nextHeight, vegetationIgnoreMap, maxLength-1);
		// If the river touches the generated area adjust the blocks to river style:
		if(x+width >= lx-8 && x-width < lx+24 && z+width >= lz-8 && z-width < lz+24) {
			int xMin = Math.max((int)Math.ceil(x-width), lx-8);
			int xMax = Math.min((int)Math.floor(x+width), lx+23);
			int zMin = Math.max((int)Math.ceil(z-width), lz-8);
			int zMax = Math.min((int)Math.floor(z+width), lz+23);
			for(int px = xMin; px <= xMax; px++) {
				for(int pz = zMin; pz <= zMax; pz++) {
					if(Math.sqrt((px-x)*(px-x) + (pz-z)*(pz-z)) <= width) {
						if(((px-lx)&(~15)) == 0 && ((pz-lz)&(~15)) == 0) {
							int ix = px&15;
							int iz = pz&15;
							int height0 = (int)(getHeight(px, pz, nn, np, pn, pp));
							int height1 = (int)(curHeight);
							int height2 = (int)(nextHeight);
							if(height0-height1 < 0) height1 = height0;
							if(height1-height2 < 1) height2 = height1-2;
							if(maxLength > 5) {
								for(int h = height1; h <= height0; h++) {
									chunk.updateBlock(ix, h, iz, null);
								}
							}
							for(int h = height2; h < height1; h++) {
								chunk.updateBlock(ix, h, iz, water);
							}
						}
						// Add to the vegetationIgnoreMap if on a river:
						int ix = px-(lx-8);
						int iy = pz-(lz-8);
						vegetationIgnoreMap[ix][iy] = true;
					}
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0xe94966f1a3853a9eL;
	}
}
