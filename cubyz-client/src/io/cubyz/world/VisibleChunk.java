package io.cubyz.world;

import java.util.ArrayList;

import io.cubyz.ClientSettings;
import io.cubyz.Utilities;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;

/**
 * The client version of a chunk that handles all the features that are related to rendering and therefore not needed on servers.
 */

public class VisibleChunk extends NormalChunk {
	/**Stores sun r g b channels of each light channel in one integer. This makes it easier to store and to access.*/
	private int[] light;
	/**Max height of the terrain after loading. Used to prevent bugs at chunk borders.*/
	private int maxHeight;
	
	public VisibleChunk(Integer cx, Integer cz, Surface surface) {
		super(cx, cz, surface);
		if(ClientSettings.easyLighting) {
			light = new int[16*World.WORLD_HEIGHT*16];
		}
	}

	@Override
	public void clear() {
		super.clear();
		Utilities.fillArray(light, 0);
	}
	
	/**
	 * Loads the chunk
	 */
	@Override
	public void load() {
		if(startedloading) {
			// Empty the list, so blocks won't get added twice. This will also be important, when there is a manual chunk reloading.
			clear();
		}
		
		startedloading = true;
		NormalChunk [] chunks = new NormalChunk[4];
		NormalChunk ch = surface.getChunk(cx - 1, cz);
		chunks[0] = ch;
		boolean chx0 = ch != null && ch.isGenerated();
		ch = surface.getChunk(cx + 1, cz);
		chunks[1] = ch;
		boolean chx1 = ch != null && ch.isGenerated();
		ch = surface.getChunk(cx, cz - 1);
		chunks[2] = ch;
		boolean chz0 = ch != null && ch.isGenerated();
		ch = surface.getChunk(cx, cz + 1);
		boolean chz1 = ch != null && ch.isGenerated();
		chunks[3] = ch;
		maxHeight = 255; // The biggest height that supports blocks.
		// Use lighting calculations that are done anyways if easyLighting is enabled to determine the maximum height inside this chunk.
		ArrayList<Integer> lightSources = null;
		if(ClientSettings.easyLighting) {
			lightSources = new ArrayList<>();
			// First of all update the top air blocks on which the sun is constant:
			maxHeight = World.WORLD_HEIGHT-1;
			boolean stopped = false;
			while(!stopped) {
				--maxHeight;
				for(int xz = 0; xz < 256; xz++) {
					light[((maxHeight+1) << 8) | xz] |= 0xff000000;
					if(blocks[(maxHeight << 8) | xz] != null) {
						stopped = true;
					}
				}
			}
		} else { // TODO: Find a similar optimization for easyLighting disabled.
			
		}
		// Do some light updates.
		if(ClientSettings.easyLighting) {
			// Update the highest layer that is not just air:
			for(int x = 0; x < 16; x++) {
				for(int z = 0; z < 16; z++) {
					localLightUpdate(x, maxHeight, z, 24, 0x00ffffff);
				}
			}
			// Look at the neighboring chunks. Update only the outer corners:
			VisibleChunk no = (VisibleChunk)surface.getChunk(cx-1, cz);
			VisibleChunk po = (VisibleChunk)surface.getChunk(cx+1, cz);
			VisibleChunk on = (VisibleChunk)surface.getChunk(cx, cz-1);
			VisibleChunk op = (VisibleChunk)surface.getChunk(cx, cz+1);
			if(no != null || on != null) {
				int x = 0, z = 0;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(no != null || op != null) {
				int x = 0, z = 15;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(po != null || on != null) {
				int x = 15, z = 0;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(po != null || op != null) {
				int x = 15, z = 15;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(no != null) {
				int x = 0;
				for(int z = 1; z < 15; z++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
				x = 15;
				for(int z = 0; z < 16; z++) {
					int y = no.maxHeight;
					no.singleLightUpdate(x, y, z);
				}
			}
			if(po != null) {
				int x = 15;
				for(int z = 1; z < 15; z++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
				x = 0;
				for(int z = 0; z < 16; z++) {
					int y = po.maxHeight;
					po.singleLightUpdate(x, y, z);
				}
			}
			if(on != null) {
				int z = 0;
				for(int x = 1; x < 15; x++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
				z = 15;
				for(int x = 0; x < 16; x++) {
					int y = on.maxHeight;
					on.singleLightUpdate(x, y, z);
				}
			}
			if(op != null) {
				int z = 15;
				for(int x = 1; x < 15; x++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
				z = 0;
				for(int x = 0; x < 16; x++) {
					int y = op.maxHeight;
					op.singleLightUpdate(x, y, z);
				}
			}
		}
		// Sadly the new system doesn't allow for easy access on the BlockInstances through a list, so we have to go through all blocks(which probably is even more efficient because about half of the blocks are non-air).
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y <= maxHeight; y++) {
				for(int  z = 0; z < 16; z++) {
					int index = (x << 4) | (y << 8) | z;
					Block b = blocks[index];
					if(b != null) {
						byte[] data = new byte[6];
						int[] indices = new int[6];
						Block[] neighbors = getNeighbors(x, y ,z, data, indices);
						for (int i = 0; i < neighbors.length; i++) {
							if (blocksLight(neighbors[i], b, data[i], index - indices[i])
														&& (y != 0 || i != 4)
														&& (x != 0 || i != 0 || chx0)
														&& (x != 15 || i != 1 || chx1)
														&& (z != 0 || i != 2 || chz0)
														&& (z != 15 || i != 3 || chz1)) {
								revealBlock(x, y, z);
								break;
							}
						}
						if(ClientSettings.easyLighting && b.getLight() != 0) { // Process light sources
							lightSources.add(index);
						}
					}
				}
			}
		}
		if(ClientSettings.easyLighting) {
			// Take care about light sources:
			for(int index : lightSources) {
				lightUpdate((index >>> 4) & 15, (index >>> 8) & 255, index & 15);
			}
		}
		boolean [] toCheck = {chx0, chx1, chz0, chz1};
		for (int i = 0; i < 16; i++) {
			// Checks if blocks from neighboring chunks are changed
			int [] dx = {15, 0, i, i};
			int [] dz = {i, i, 15, 0};
			int [] invdx = {0, 15, i, i};
			int [] invdz = {i, i, 0, 15};
			for(int k = 0; k < 4; k++) {
				if (toCheck[k]) {
					ch = chunks[k];
					for (int j = World.WORLD_HEIGHT - 1; j >= 0; j--) {
						BlockInstance inst = ch.getBlockInstanceAt((dx[k] << 4) | (j << 8) | dz[k]);
						Block block = ch.getBlockAt(dx[k], j, dz[k]);
						// Update neighbor information:
						if(inst != null) {
							inst.updateNeighbor(k ^ 1, getsBlocked(block, blocks[(invdx[k] << 4) | (j << 8) | invdz[k]], ch.blockData[(dx[k] << 4) | (j << 8) | dz[k]], (invdx[k] << 4) | (j << 8) | invdz[k] - (dx[k] << 4) | (j << 8) | dz[k]), surface.getStellarTorus().getWorld().getLocalPlayer());
							continue;
						}
						// Update visibility:
						if(block == null) {
							continue;
						}
						if (blocksLight(getBlockAt(invdx[k], j, invdz[k]), block, blockData[(invdx[k] << 4) | (j << 8) | invdz[k]], (dx[k] << 4) | (j << 8) | dz[k] - (invdx[k] << 4) | (j << 8) | invdz[k])) {
							ch.revealBlock(dx[k], j, dz[k]);
							continue;
						}
					}
				}
			}
		}
		loaded = true;
	}
	
	/**
	 * Performs a light update in all channels on this block.
	 * @param x
	 * @param y
	 * @param z
	 */
	@Override
	protected void lightUpdate(int x, int y, int z) {
		ArrayList<int[]> updates = new ArrayList<>();
		// Sun:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 24, 0x00ffffff);
					if(newLight != -1) {
						int[] arr = new int[]{x, y, z, newLight};
						updates.add(arr);
					}
				}
			}
		}
		lightUpdate(updates, 24, 0x00ffffff);
		// Red:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 16, 0xff00ffff);
					if(newLight != -1) {
						int[] arr = new int[]{x, y, z, newLight};
						updates.add(arr);
					}
				}
			}
		}
		lightUpdate(updates, 16, 0xff00ffff);
		// Green:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 8, 0xffff00ff);
					if(newLight != -1) {
						int[] arr = new int[]{x, y, z, newLight};
						updates.add(arr);
					}
				}
			}
		}
		lightUpdate(updates, 8, 0xffff00ff);
		// Blue:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 0, 0xffffff00);
					if(newLight != -1) {
						int[] arr = new int[]{x, y, z, newLight};
						updates.add(arr);
					}
				}
			}
		}
		lightUpdate(updates, 0, 0xffffff00);
	}
	
	/**
	 * Update only 1 corner. Since this is always done during loading, only constructive updates are needed:
	 * @param x
	 * @param y
	 * @param z
	 */
	private void singleLightUpdate(int x, int y, int z) {
		// Sun:
		localLightUpdate(x, y, z, 24, 0x00ffffff);
		// Red:
		localLightUpdate(x, y, z, 16, 0xff00ffff);
		// Green:
		localLightUpdate(x, y, z, 8, 0xffff00ff);
		// Blue:
		localLightUpdate(x, y, z, 0, 0xffffff00);
	}
	
	private void constructiveLightUpdate(int x, int y, int z, int shift, int mask, int value, boolean nx, boolean px, boolean ny, boolean py, boolean nz, boolean pz) {
		// Make some bound checks:
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return;
		// Check if it's inside this chunk:
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null) chunk.constructiveLightUpdate(x & 15, y, z & 15, shift, mask, value, nx, px, ny, py, nz, pz);
			return;
		}
		// Ignore if the current light value is brighter.
		if(((light[(x << 4) | (y << 8) | z] >>> shift) & 255) >= value) {
			return;
		}
		light[(x << 4) | (y << 8) | z] = (light[(x << 4) | (y << 8) | z] & mask) | (value << shift);
		updated = true;
		// Get all eight neighbors of this lighting node:
		Block[] neighbors = new Block[8];
		byte[] neighborData = new byte[8];
		for(int dx = -1; dx <= 0; dx++) {
			for(int dy = -1; dy <= 0; dy++) {
				for(int dz = -1; dz <= 0; dz++) {
					neighbors[7 + (dx << 2) + (dy << 1) + dz] = getBlockUnboundAndUpdateLight(x+dx, y+dy, z+dz);
					neighborData[7 + (dx << 2) + (dy << 1) + dz] = getDataUnbound(x+dx, y+dy, z+dz);
					// Take care about the case that this block is a light source, that is brighter than the current light level:
					if(neighbors[7 + (dx << 2) + (dy << 1) + dz] != null && ((neighbors[7 + (dx << 2) + (dy << 1) + dz].getLight() >>> shift) & 255) > value)
						return;
				}
			}
		}
		// Update all neighbors that should be updated:
		if(nx) {
			int light = applyNeighborsConstructive(value, shift, neighbors[0], neighborData[0], neighbors[1], neighborData[1], neighbors[2], neighborData[2], neighbors[3], neighborData[3]);
			constructiveLightUpdate(x-1, y, z, shift, mask, light, true, false, true, true, true, true);
		}
		if(px) {
			int light = applyNeighborsConstructive(value, shift, neighbors[4], neighborData[4], neighbors[5], neighborData[5], neighbors[6], neighborData[6], neighbors[7], neighborData[7]);
			constructiveLightUpdate(x+1, y, z, shift, mask, light, false, true, true, true, true, true);
		}
		if(nz) {
			int light = applyNeighborsConstructive(value, shift, neighbors[0], neighborData[0], neighbors[2], neighborData[2], neighbors[4], neighborData[4], neighbors[6], neighborData[6]);
			constructiveLightUpdate(x, y, z-1, shift, mask, light, true, true, true, true, true, false);
		}
		if(pz) {
			int light = applyNeighborsConstructive(value, shift, neighbors[1], neighborData[1], neighbors[3], neighborData[3], neighbors[5], neighborData[5], neighbors[7], neighborData[7]);
			constructiveLightUpdate(x, y, z+1, shift, mask, light, true, true, true, true, false, true);
		}
		if(ny) {
			int light = applyNeighborsConstructive(value, shift, neighbors[0], neighborData[0], neighbors[1], neighborData[1], neighbors[4], neighborData[4], neighbors[5], neighborData[5]);
			if(shift == 24 && light != 0)
				light += 8;
			constructiveLightUpdate(x, y-1, z, shift, mask, light, true, true, true, false, true, true);
		}
		if(py) {
			int light = applyNeighborsConstructive(value, shift, neighbors[2], neighborData[2], neighbors[3], neighborData[3], neighbors[6], neighborData[6], neighbors[7], neighborData[7]);
			constructiveLightUpdate(x, y+1, z, shift, mask, light, true, true, false, true, true, true);
		}
	}
	
	private int applyNeighbors(int light, int shift, Block n1, byte d1, Block n2, byte d2, Block n3, byte d3, Block n4, byte d4) {
		light = applyNeighborsConstructive((light >>> shift) & 255, shift, n1, d1, n2, d2, n3, d3, n4, d4);
		// Check if one of the blocks is glowing bright enough to support more light:
		if(n1 != null) {
			light = Math.max(light, (n1.getLight() >>> shift) & 255);
		}
		if(n2 != null) {
			light = Math.max(light, (n2.getLight() >>> shift) & 255);
		}
		if(n3 != null) {
			light = Math.max(light, (n3.getLight() >>> shift) & 255);
		}
		if(n4 != null) {
			light = Math.max(light, (n4.getLight() >>> shift) & 255);
		}
		return light;
	}
	
	private int applyNeighborsConstructive(int light, int shift, Block n1, byte d1, Block n2, byte d2, Block n3, byte d3, Block n4, byte d4) {
		light <<= 2; // make sure small absorptions don't get ignored while dividing by 4.
		int solidNeighbors = 0;
		if(n1 != null) {
			if(n1.isTransparent(d1)) {
				light -= (n1.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		if(n2 != null) {
			if(n2.isTransparent(d2)) {
				light -= (n2.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		if(n3 != null) {
			if(n3.isTransparent(d3)) {
				light -= (n3.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		if(n4 != null) {
			if(n4.isTransparent(d4)) {
				light -= (n4.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		light >>= 2; // Divide by 4.
		switch(solidNeighbors) {
			case 4:
				return 0;
			case 3:
				light -= 64; // ⅜ of all light is absorbed if there is a corner. That is exactly the same value as with the first attempt at a lighting system.
			case 2:
				light -= 16;
			case 1:
				light -= 8;
			case 0:
				light -= 8;
		}
		if(light < 0) return 0;
		return light;
	}
	
	private int localLightUpdate(int x, int y, int z, int shift, int mask) {
		// Make some bound checks:
		if(!ClientSettings.easyLighting || y < 0 || y >= World.WORLD_HEIGHT || !generated) return -1;
		// Check if it's inside this chunk:
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null) return chunk.localLightUpdate(x & 15, y, z & 15, shift, mask);
			return -1;
		}
		int maxLight = 0;
		
		// Get all eight neighbors of this lighting node:
		Block[] neighbors = new Block[8];
		byte[] neighborData = new byte[8];
		for(int dx = -1; dx <= 0; dx++) {
			for(int dy = -1; dy <= 0; dy++) {
				for(int dz = -1; dz <= 0; dz++) {
					neighbors[7 + (dx << 2) + (dy << 1) + dz] = getBlockUnbound(x+dx, y+dy, z+dz);
					neighborData[7 + (dx << 2) + (dy << 1) + dz] = getDataUnbound(x+dx, y+dy, z+dz);
					// Take care about the case that this block is a light source:
					if(neighbors[7 + (dx << 2) + (dy << 1) + dz] != null)
						maxLight = Math.max(maxLight, (neighbors[7 + (dx << 2) + (dy << 1) + dz].getLight() >>> shift) & 255);
				}
			}
		}
		
		// Check all neighbors and find their highest lighting in the specified channel after applying block-specific effects to it:
		int index = (x << 4) | (y << 8) | z; // Works close to the datastructure. Allows for some optimizations.
		
		if(x != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-16], shift, neighbors[0], neighborData[0], neighbors[1], neighborData[1], neighbors[2], neighborData[2], neighbors[3], neighborData[3]));
		} else {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx-1, cz);
			if(chunk != null && chunk.startedloading) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index | 0xf0], shift, neighbors[0], neighborData[0], neighbors[1], neighborData[1], neighbors[2], neighborData[2], neighbors[3], neighborData[3]));
			}
		}
		if(x != 15) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index+16], shift, neighbors[4], neighborData[4], neighbors[5], neighborData[5], neighbors[6], neighborData[6], neighbors[7], neighborData[7]));
		} else {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx+1, cz);
			if(chunk != null && chunk.startedloading) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index & ~0xf0], shift, neighbors[4], neighborData[4], neighbors[5], neighborData[5], neighbors[6], neighborData[6], neighbors[7], neighborData[7]));
			}
		}
		if(z != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-1], shift, neighbors[0], neighborData[0], neighbors[2], neighborData[2], neighbors[4], neighborData[4], neighbors[6], neighborData[6]));
		} else {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx, cz-1);
			if(chunk != null && chunk.startedloading) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index | 0xf], shift, neighbors[0], neighborData[0], neighbors[2], neighborData[2], neighbors[4], neighborData[4], neighbors[6], neighborData[6]));
			}
		}
		if(z != 15) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index+1], shift, neighbors[1], neighborData[1], neighbors[3], neighborData[3], neighbors[5], neighborData[5], neighbors[7], neighborData[7]));
		} else {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx, cz+1);
			if(chunk != null && chunk.startedloading) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index & ~0xf], shift, neighbors[1], neighborData[1], neighbors[3], neighborData[3], neighbors[5], neighborData[5], neighbors[7], neighborData[7]));
			}
		}
		if(y != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-256], shift, neighbors[0], neighborData[0], neighbors[1], neighborData[1], neighbors[4], neighborData[4], neighbors[5], neighborData[5]));
		}
		if(y != 255) {
			int local = applyNeighbors(light[index+256], shift, neighbors[2], neighborData[2], neighbors[3], neighborData[3], neighbors[6], neighborData[6], neighbors[7], neighborData[7]);
			if(shift == 24 && local != 0)
				local += 8;
			maxLight = Math.max(maxLight, local);
		} else if(shift == 24) {
			maxLight = 255; // The top block gets always maximum sunlight.
		}
		// Update the light and return.
		int curLight = (light[index] >>> shift) & 255;
		if(maxLight < 0) maxLight = 0;
		if(curLight < maxLight) {
			// Do a constructive light update(which is faster) and then return -1 to signal other lightUpdate functions that no further update is needed.
			constructiveLightUpdate(x, y, z, shift, mask, maxLight, true, true, true, true, true, true);
			return -1;
		}
		if(curLight != maxLight) {
			light[index] = (light[index] & mask) | (maxLight << shift);
			for(int dx = -1; dx <= 0; dx++) {
				for(int dy = -1; dy <= 0; dy++) {
					for(int dz = -1; dz <= 0; dz++) {
						updateLight(x+dx, y+dy, z+dz);
					}
				}
			}
			updated = true;
			return maxLight;
		}
		return -1;
	}
	
	/**
	 * Used for first time loading. For later update also negative changes have to be taken into account making the system more complex.
	 * @param lightUpdates
	 * @param shift
	 * @param mask
	 */
	public void lightUpdate(ArrayList<int[]> lightUpdates, int shift, int mask) {
		while(lightUpdates.size() != 0) {
			// Find the block with the highest light level from the list:
			int[][] updates = lightUpdates.toArray(new int[0][]);
			int[] max = updates[0];
			for(int i = 1; i < updates.length; i++) {
				if(max[3] < updates[i][3]) {
					max = updates[i];
					if(max[3] == 255)
						break;
				}
			}
			lightUpdates.remove(max);
			int[] dx = {-1, 1, 0, 0, 0, 0};
			int[] dy = {0, 0, -1, 1, 0, 0};
			int[] dz = {0, 0, 0, 0, -1, 1};
			// Look at the neighbors:
			for(int n = 0; n < 6; n++) {
				int x = max[0]+dx[n];
				int y = max[1]+dy[n];
				int z = max[2]+dz[n];
				int light;
				if((light = localLightUpdate(x, y, z, shift, mask)) >= 0) {
					for(int i = 0;; i++) {
						if(i == updates.length) {
							lightUpdates.add(new int[]{x, y, z, light});
							break;
						}
						if(updates[i][0] == x && updates[i][1] == y && updates[i][2] == z) {
							updates[i][3] = light;
							break;
						}
					}
				}
			}
		}
	}
	
	@Override
	public int getLight(int x, int y, int z) {
		if(y < 0) return 0;
		if(y >= World.WORLD_HEIGHT) return 0xff000000;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx + (x >> 4), cz + (z >> 4));
			if(chunk != null) return chunk.getLight(x & 15, y, z & 15);
			return -1;
		}
		return light[(x << 4) | (y << 8) | z];
	}
	
	@Override
	public void getCornerLight(int x, int y, int z, int[] arr) {
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					arr[(dx << 2) | (dy << 1) | dz] = getLight(x+dx, y+dy, z+dz);
				}
			}
		}
		for(int i = 0; i < 8; i++) {
			if(arr[i] == -1) {
				if(i == 0)
					arr[i] = arr[7];
				else
					arr[i] = arr[i-1];
			}
		}
	}

	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return block at the coordinates x+wx, y, z+wz
	 */
	private Block getBlockUnboundAndUpdateLight(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) return chunk.getBlockUnboundAndUpdateLight(x & 15, y, z & 15);
			return noLight; // Let the lighting engine think this region is blocked.
		}
		if(inst[(x << 4) | (y << 8) | z] != null) {
			inst[(x << 4) | (y << 8) | z].scheduleLightUpdate();
		}
		return blocks[(x << 4) | (y << 8) | z];
	}
	
	private void updateLight(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			VisibleChunk chunk = (VisibleChunk)surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) chunk.updateLight(x & 15, y, z & 15);
			return;
		}
		if(inst[(x << 4) | (y << 8) | z] != null) {
			inst[(x << 4) | (y << 8) | z].scheduleLightUpdate();
		}
	}
}
