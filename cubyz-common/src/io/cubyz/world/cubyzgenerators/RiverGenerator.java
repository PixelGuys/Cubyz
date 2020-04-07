package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.World;

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
	public void generate(long seed, int wx, int wy, Block[][][] chunk, boolean[][] vegetationIgnoreMap, LocalWorld world) {
		// Gets the four surrounding MetaChunks and switch to a relative coordinate system.
		int lx, ly;
		MetaChunk nn, np, pn, pp;
		if((wx & 255) < 128) {
			lx = (wx & 255) + 256;
			if((wy & 255) < 128) {
				ly = (wy & 255) + 256;
				nn = world.getMetaChunk((wx & (~255)) - 256, (wy & (~255)) - 256);
				np = world.getMetaChunk((wx & (~255)) - 256, (wy & (~255)));
				pn = world.getMetaChunk((wx & (~255)), (wy & (~255)) - 256);
				pp = world.getMetaChunk((wx & (~255)), (wy & (~255)));
			} else {
				ly = (wy & 255);
				nn = world.getMetaChunk((wx & (~255)) - 256, (wy & (~255)));
				np = world.getMetaChunk((wx & (~255)) - 256, (wy & (~255)) + 256);
				pn = world.getMetaChunk((wx & (~255)), (wy & (~255)));
				pp = world.getMetaChunk((wx & (~255)), (wy & (~255)) + 256);
			}
		} else {
			lx = (wx & 255);
			if((wy & 255) < 128) {
				ly = (wy & 255) + 256;
				nn = world.getMetaChunk((wx & (~255)), (wy & (~255)) - 256);
				np = world.getMetaChunk((wx & (~255)), (wy & (~255)));
				pn = world.getMetaChunk((wx & (~255)) + 256, (wy & (~255)) - 256);
				pp = world.getMetaChunk((wx & (~255)) + 256, (wy & (~255)));
			} else {
				ly = (wy & 255);
				nn = world.getMetaChunk((wx & (~255)), (wy & (~255)));
				np = world.getMetaChunk((wx & (~255)), (wy & (~255)) + 256);
				pn = world.getMetaChunk((wx & (~255)) + 256, (wy & (~255)));
				pp = world.getMetaChunk((wx & (~255)) + 256, (wy & (~255)) + 256);
			}
		}
		// Consider coordinates in each MetaChunk.
		considerMetaChunk(nn, lx, ly, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
		considerMetaChunk(np, lx, ly, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
		considerMetaChunk(pn, lx, ly, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
		considerMetaChunk(pp, lx, ly, chunk, nn, np, pn, pp, seed, vegetationIgnoreMap);
	}
	
	private void considerMetaChunk(MetaChunk m, int lx, int ly, Block[][][] chunk, MetaChunk nn, MetaChunk np, MetaChunk pn, MetaChunk pp, long seed, boolean[][] vegetationIgnoreMap) {
		Random rand = new Random(seed^((long)m.x*Float.floatToRawIntBits(m.heightMap[255][0]))^((long)m.y*Float.floatToRawIntBits(m.heightMap[0][255])));
		int num = rand.nextInt(16);
		for(int i = 0; i < num; i++) {
			int x = rand.nextInt(256);
			int y = rand.nextInt(256);
			if(m.biomeMap[x][y].supportsRivers()) {
				if(m == pp || m == pn) {
					x += 256;
				}
				if(m == pp || m == np) {
					y += 256;
				}
				makeRiver(x, y, lx, ly, chunk, nn, np, pn, pp, rand.nextFloat()+2, 128, new float[2], getHeight(x, y, nn, np, pn, pp), vegetationIgnoreMap);
			}
		}
	}
	
	private float getHeight(int x, int y, MetaChunk nn, MetaChunk np, MetaChunk pn, MetaChunk pp) {
		if(x < 256) {
			if(y < 256) {
				return nn.heightMap[x][y];
			} else {
				return np.heightMap[x][y-256];
			}
		} else {
			if(y < 256) {
				return nn.heightMap[x-256][y];
			} else {
				return np.heightMap[x-256][y-256];
			}
		}
	}
	
	float[] getGradient(int x, int y, MetaChunk nn, MetaChunk np, MetaChunk pn, MetaChunk pp) {
		float[] res = new float[2];
		res[0] = -(getHeight(x+1, y, nn, np, pn, pp) - getHeight(x-1, y, nn, np, pn, pp));
		res[1] = -(getHeight(x, y+1, nn, np, pn, pp) - getHeight(x, y-1, nn, np, pn, pp));
		return res;
	}
	private float[] getNormalizedGradient(float dx, float dy, float[] grad00, float[] grad01, float[] grad10, float[] grad11) {
		float[] res = new float[2];
		for(int i = 0; i < 2; i++) {
			res[i] += dx*dy*grad11[i];
			res[i] += dx*(1-dy)*grad10[i];
			res[i] += (1-dx)*dy*grad01[i];
			res[i] += (1-dx)*(1-dy)*grad00[i];
		}
		float val = (float)Math.sqrt(res[0]*res[0] + res[1]*res[1]);
		res[0] /= val;
		res[1] /= val;
		return res;
	}
	
	private void makeRiver(float x, float y, int lx, int ly, Block[][][] chunk, MetaChunk nn, MetaChunk np, MetaChunk pn, MetaChunk pp, float width, int maxLength, float[] oldDir, float curHeight, boolean[][] vegetationIgnoreMap) {
		if(maxLength == 0) return; // An abrupt ending. Maybe add some kind of disappearing to the underground?
		// Get the gradient of the surrounding positions in the heightMap:
		int x0 = (int)x;
		int y0 = (int)y;
		int x1 = x0+1;
		int y1 = y0+1;
		if(x0 <= 0 || y0 <= 0 || x1 >= 511 || y1 >= 511) return; // Don't leave the 4 surrounding metaChunks.
		float[] grad00 = getGradient(x0, y0, nn, np, pn, pp);
		float[] grad01 = getGradient(x0, y1, nn, np, pn, pp);
		float[] grad10 = getGradient(x1, y0, nn, np, pn, pp);
		float[] grad11 = getGradient(x1, y1, nn, np, pn, pp);
		// Get an estimation of the gradient at the float position and normalize it so the river movement is 1:
		float[] dir = getNormalizedGradient(x%1, y%1, grad00, grad01, grad10, grad11);
		dir[0] = (dir[0]+2*oldDir[0])/3;
		dir[1] = (dir[1]+2*oldDir[1])/3;
		float nextHeight = Math.min(curHeight, getHeight(x0, y0, nn, np, pn, pp)-0.004f);
		if(nextHeight <= 102.0f/256.0f) return; // No need to get any lower than sea level.
		if(maxLength <= 5) {
			nextHeight -= 0.004f; // Let the river slowly disappear underground.
		}
		makeRiver(x+dir[0], y+dir[1], lx, ly, chunk, nn, np, pn, pp, width, maxLength-1, dir, nextHeight, vegetationIgnoreMap);
		// If the river touches the generated area adjust the blocks to river style:
		if(x+width >= lx-8 && x-width < lx+24 && y+width >= ly-8 && y-width < ly+24) {
			int xMin = Math.max((int)Math.ceil(x-width), lx-8);
			int xMax = Math.min((int)Math.floor(x+width), lx+23);
			int yMin = Math.max((int)Math.ceil(y-width), ly-8);
			int yMax = Math.min((int)Math.floor(y+width), ly+23);
			for(int px = xMin; px <= xMax; px++) {
				for(int py = yMin; py <= yMax; py++) {
					if(Math.sqrt((px-x)*(px-x) + (py-y)*(py-y)) <= width) {
						if(((px-lx)&(~15)) == 0 && ((py-ly)&(~15)) == 0) {
							int ix = px&15;
							int iy = py&15;
							int height0 = (int)(getHeight(px, py, nn, np, pn, pp)*World.WORLD_HEIGHT);
							int height1 = (int)(curHeight*World.WORLD_HEIGHT);
							int height2 = (int)(nextHeight*World.WORLD_HEIGHT);
							if(height1-height2 < 1) height2 = height1-2;
							if(maxLength > 5) {
								for(int h = height1; h <= height0; h++) {
									chunk[ix][iy][h] = null;
								}
							}
							for(int h = height2; h < height1; h++) {
								chunk[ix][iy][h] = water;
							}
						}
						// Add to the vegetationIgnoreMap if on a river:
						int ix = px-(lx-8);
						int iy = py-(ly-8);
						vegetationIgnoreMap[ix][iy] = true;
					}
				}
			}
		}
	}
}
