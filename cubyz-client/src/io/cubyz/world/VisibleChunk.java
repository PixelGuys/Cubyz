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
			outer:
			while(true) {
				--maxHeight;
				for(int xz = 0; xz < 256; xz++) {
					light[((maxHeight+1) << 8) | xz] |= 0xff000000;
					if(blocks[(maxHeight << 8) | xz] != null) {
						break outer;
					}
				}
			}
		} else { // TODO: Find a similar optimization for easyLighting disabled.
			
		}
		// Go through all blocks(which is more efficient than creating a block-list at generation time because about half of the blocks are non-air).
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
							if (blocksBlockNot(neighbors[i], b, data[i], index - indices[i])
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
			// Update the sun channel:
			for(int xz = 0; xz < 256; xz++) {
				constructiveLightUpdate(((maxHeight+1) << 8) | xz, 255, 0xff000000, 24);
				constructiveLightUpdate((maxHeight << 8) | xz, 255, 0xff000000, 24);
			}
			// Take care about light sources:
			for(int index : lightSources) {
				constructiveLightUpdate(index);
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
							inst.updateNeighbor(k ^ 1, blocksBlockNot(blocks[(invdx[k] << 4) | (j << 8) | invdz[k]], block, blockData[(invdx[k] << 4) | (j << 8) | invdz[k]], (invdx[k] << 4) | (j << 8) | invdz[k] - (dx[k] << 4) | (j << 8) | dz[k]), surface.getStellarTorus().getWorld().getLocalPlayer());
							continue;
						}
						// Update visibility:
						if(block == null) {
							continue;
						}
						if (blocksBlockNot(getBlockAt(invdx[k], j, invdz[k]), block, blockData[(invdx[k] << 4) | (j << 8) | invdz[k]], (dx[k] << 4) | (j << 8) | dz[k] - (invdx[k] << 4) | (j << 8) | invdz[k])) {
							ch.revealBlock(dx[k], j, dz[k]);
							continue;
						}
					}
					ch.updated = true;
				}
			}
			// TODO: Fix lighting that from loaded chunks.
		}
		loaded = true;
	}
	
	/**
	 * Updates all light channels of this block <b>constructively</b>.
	 * @param index
	 */
	public void constructiveLightUpdate(int index) {
		int blockColor = blocks[index].getLight();
		int s = blockColor >>> 24;
		int r = (blockColor >>> 16) & 255;
		int g = (blockColor >>> 8) & 255;
		int b = blockColor & 255;
		if(s != 0) constructiveLightUpdate(index, s, 0xff000000, 24);
		if(r != 0) constructiveLightUpdate(index, r, 0x00ff0000, 16);
		if(g != 0) constructiveLightUpdate(index, g, 0x0000ff00, 8);
		if(b != 0) constructiveLightUpdate(index, b, 0x000000ff, 0);
	}
	
	/**
	 * Updates one specific light channel of this block <b>constructively</b>.
	 * @param index
	 * @param channelMask
	 * @param channelShift
	 */
	public void constructiveLightUpdate(int index, int lightValue, int channelMask, int channelShift) {
		if(!startedloading) return;
		if(blocks[index] != null && !blocks[index].isLightingTransparent(blockData[index]) && ((blocks[index].getLight() >>> channelShift) & 255) != lightValue) return;
		lightValue = propagateLight(blocks[index], blockData[index], lightValue, channelShift);
		if(blocks[index] != null)
			lightValue = Math.max(lightValue, ((blocks[index].getLight() >>> channelShift) & 255));
		int prevValue = (light[index] >>> channelShift) & 255;
		if(lightValue <= prevValue) return;
		light[index] = (~channelMask & light[index]) | (lightValue << channelShift);
		updated = true;
		// Go through all neighbors:
		// z-1:
		if((index & 0x000f) == 0) { // if(z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx, cz-1);
			if(neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index^0x000f, lightValue, channelMask, channelShift);
			}
		} else {
			constructiveLightUpdate(index-1, lightValue, channelMask, channelShift);
		}
		// z+1:
		if((index & 0x000f) == 0x000f) { // if(z == 15)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx, cz+1);
			if(neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index^0x000f, lightValue, channelMask, channelShift);
			}
		} else {
			constructiveLightUpdate(index+1, lightValue, channelMask, channelShift);
		}
		// x-1:
		if((index & 0x00f0) == 0) { // if(x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx-1, cz);
			if(neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index^0x00f0, lightValue, channelMask, channelShift);
			}
		} else {
			constructiveLightUpdate(index-16, lightValue, channelMask, channelShift);
		}
		// z+1:
		if((index & 0x00f0) == 0x00f0) { // if(x == 15)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx+1, cz);
			if(neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index^0x00f0, lightValue, channelMask, channelShift);
			}
		} else {
			constructiveLightUpdate(index+16, lightValue, channelMask, channelShift);
		}
		// y-1:
		if((index & 0xff00) != 0) { // if(y != 0)
			constructiveLightUpdate(index-256, lightValue + (channelShift == 24 ? 8 : 0), channelMask, channelShift);
		}
		// y+1:
		if((index & 0xff00) != 0xff00) { // if(y != 255)
			constructiveLightUpdate(index+256, lightValue - (channelShift == 24 ? 8 : 0), channelMask, channelShift);
		}
	}
	
	/**
	 * Update the local light level after a block update.
	 * @param x
	 * @param y
	 * @param z
	 */
	public void lightUpdate(int x, int y, int z) {
		int index = (x << 4) | (y << 8) | z;
		lightUpdate(index);
	}
	
	/**
	 * Updates all light channels of this block <b>destructively</b>.
	 * @param index
	 */
	public void lightUpdate(int index) {
		lightUpdateInternal(index, 0xff000000, 24);
		lightUpdateInternal(index, 0x00ff0000, 16);
		lightUpdateInternal(index, 0x0000ff00, 8);
		lightUpdateInternal(index, 0x000000ff, 0);
	}
	
	/**
	 * Updates one specific light channel of this block <b>destructively</b>. This means that the engine tries to remove lighting and re-add it if it was falsely removed.
	 * @param index
	 * @param channelMask
	 * @param channelShift
	 */
	public void lightUpdateInternal(int index, int channelMask, int channelShift) {
		if(!startedloading) return;
		int newValue = 0;
		if(blocks[index] != null) newValue = (blocks[index].getLight() >>> channelShift) & 255;
		int prevValue = (light[index] >>> channelShift) & 255;
		// Go through all neighbors and check if the old value comes from them:
		// z-1:
		if((index & 0x000f) == 0) { // if(z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx, cz-1);
			if(neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (neighborChunk.light[index ^ 0x000f] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (light[index - 1] >>> channelShift) & 255, channelShift));
		}
		// z+1:
		if((index & 0x000f) == 0x000f) { // if(z == 15)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx, cz+1);
			if(neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (neighborChunk.light[index ^ 0x000f] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (light[index + 1] >>> channelShift) & 255, channelShift));
		}
		// x-1:
		if((index & 0x00f0) == 0) { // if(x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx-1, cz);
			if(neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (neighborChunk.light[index ^ 0x00f0] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (light[index - 16] >>> channelShift) & 255, channelShift));
		}
		// x+1:
		if((index & 0x00f0) == 0x00f0) { // if(x == 15)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx+1, cz);
			if(neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (neighborChunk.light[index ^ 0x00f0] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], (light[index + 16] >>> channelShift) & 255, channelShift));
		}
		// y-1:
		if((index & 0xff00) != 0) { // if(y != 0)
			newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], ((light[index - 256] >>> channelShift) & 255) - (channelShift == 24 ? 8 : 0), channelShift));
		}
		// y+1:
		if((index & 0xff00) != 0xff00) { // if(y != 255)
			newValue = Math.max(newValue, propagateLight(blocks[index], blockData[index], ((light[index + 256] >>> channelShift) & 255) + (channelShift == 24 ? 8 : 0), channelShift));
		} else if(blocks[index] != null && !blocks[index].isLightingTransparent(blockData[index])) {
			newValue = 255;
		}
		
		// Insert the new value and update neighbors:
		if(newValue == prevValue) return;
		if(newValue >= prevValue) {
			constructiveLightUpdate(index, newValue - propagateLight(blocks[index], blockData[index], 0, channelShift), channelMask, channelShift);
			return;
		}
		updated = true;
		light[index] = (light[index] & ~channelMask) | (newValue << channelShift);
		// Go through all neighbors and update them:
		// z-1:
		if((index & 0x000f) == 0) { // if(z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx, cz-1);
			if(neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index^0x000f, channelMask, channelShift);
			}
		} else {
			lightUpdateInternal(index-1, channelMask, channelShift);
		}
		// z+1:
		if((index & 0x000f) == 0x000f) { // if(z == 15)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx, cz+1);
			if(neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index^0x000f, channelMask, channelShift);
			}
		} else {
			lightUpdateInternal(index+1, channelMask, channelShift);
		}
		// x-1:
		if((index & 0x00f0) == 0) { // if(x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx-1, cz);
			if(neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index^0x00f0, channelMask, channelShift);
			}
		} else {
			lightUpdateInternal(index-16, channelMask, channelShift);
		}
		// z+1:
		if((index & 0x00f0) == 0x00f0) { // if(x == 15)
			VisibleChunk neighborChunk = (VisibleChunk)surface.getChunk(cx+1, cz);
			if(neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index^0x00f0, channelMask, channelShift);
			}
		} else {
			lightUpdateInternal(index+16, channelMask, channelShift);
		}
		// y-1:
		if((index & 0xff00) != 0) { // if(y != 0)
			lightUpdateInternal(index-256, channelMask, channelShift);
		}
		// y+1:
		if((index & 0xff00) != 0xff00) { // if(y != 255)
			lightUpdateInternal(index+256, channelMask, channelShift);
		}
	}
	
	private int propagateLight(Block block, byte data, int previousValue, int channelShift) {
		if(block != null && !block.isLightingTransparent(data)) return 0;
		int transparencyFactor = 8;
		if(block != null) {
			transparencyFactor += (block.getAbsorption() >>> channelShift) & 255;
		}
		return previousValue - transparencyFactor;
	}
	
	@Override
	public int getLight(int x, int y, int z) {
		if(y < 0) return 0;
		if(y >= 256) return 0xff000000;
		return light[(x << 4) | (y << 8) | z];
	}
}
