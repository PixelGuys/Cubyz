package cubyz.rendering;

import java.util.ArrayList;

import cubyz.client.ClientSettings;
import cubyz.utils.Utilities;
import cubyz.world.Chunk;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.World;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockInstance;

/**
 * The client version of a chunk that handles all the features that are related to rendering and therefore not needed on servers.
 */

public class VisibleChunk extends NormalChunk {
	/**Stores sun r g b channels of each light channel in one integer. This makes it easier to store and to access.*/
	private int[] light;
	
	public VisibleChunk(World world, Integer wx, Integer wy, Integer wz) {
		super(world, wx, wy, wz);
		if (ClientSettings.easyLighting) {
			light = new int[blocks.length];
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
		if (startedloading) {
			// Empty the list, so blocks won't get added twice. This will also be important, when there is a manual chunk reloading.
			clear();
		}
		
		startedloading = true;
		VisibleChunk [] chunks = new VisibleChunk[6];
		VisibleChunk ch = (VisibleChunk)world.getChunk(wx - Chunk.chunkSize, wy, wz);
		chunks[Neighbors.DIR_NEG_X] = ch;
		boolean chx0 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(wx + Chunk.chunkSize, wy, wz);
		chunks[Neighbors.DIR_POS_X] = ch;
		boolean chx1 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(wx, wy, wz - Chunk.chunkSize);
		chunks[Neighbors.DIR_NEG_Z] = ch;
		boolean chz0 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(wx, wy, wz + Chunk.chunkSize);
		chunks[Neighbors.DIR_POS_Z] = ch;
		boolean chz1 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(wx, wy - Chunk.chunkSize, wz);
		chunks[Neighbors.DIR_DOWN] = ch;
		boolean chy0 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(wx, wy + Chunk.chunkSize, wz);
		chunks[Neighbors.DIR_UP] = ch;
		boolean chy1 = ch != null && ch.startedloading;
		// Use lighting calculations that are done anyways if easyLighting is enabled to determine the maximum height inside this chunk.
		ArrayList<Integer> lightSources = new ArrayList<>();
		// Go through all blocks(which is more efficient than creating a block-list at generation time because about half of the blocks are non-air).
		for(int x = 0; x < chunkSize; x++) {
			for(int y = 0; y < chunkSize; y++) {
				for(int  z = 0; z < chunkSize; z++) {
					int index = getIndex(x, y, z);
					int b = blocks[index];
					if (b != 0) {
						int[] neighbors = getNeighbors(x, y, z);
						for (int i = 0; i < Neighbors.NEIGHBORS; i++) {
							if (blocksBlockNot(neighbors[i], b, i)
														&& (y != 0 || i != Neighbors.DIR_DOWN || chy0)
														&& (y != chunkMask || i != Neighbors.DIR_UP || chy1)
														&& (x != 0 || i != Neighbors.DIR_NEG_X || chx0)
														&& (x != chunkMask || i != Neighbors.DIR_POS_X || chx1)
														&& (z != 0 || i != Neighbors.DIR_NEG_Z || chz0)
														&& (z != chunkMask || i != Neighbors.DIR_POS_Z || chz1)) {
								revealBlock(x, y, z);
								break;
							}
						}
						if (ClientSettings.easyLighting && Blocks.light(b) != 0) { // Process light sources
							lightSources.add(index);
						}
					}
				}
			}
		}
		if (ClientSettings.easyLighting) {
			// Update the sun channel:
			for(int x = 0; x < chunkSize; x++) {
				for(int z = 0; z < chunkSize; z++) {
					int startHeight = map.mapIO.getHeight(x+wx, z+wz, map);
					startHeight -= wy;
					if (startHeight < chunkSize) {
						propagateSunLight(getIndex(x, chunkMask, z));
					}
				}
			}
			// Take care about light sources:
			for(int index : lightSources) {
				constructiveLightUpdate(index);
			}
		}
		boolean [] toCheck = {chx0, chx1, chz0, chz1, chy0, chy1};
		int[] chunkIndices = {Neighbors.DIR_NEG_X, Neighbors.DIR_POS_X, Neighbors.DIR_NEG_Z, Neighbors.DIR_POS_Z, Neighbors.DIR_DOWN, Neighbors.DIR_UP};
		for (int i = 0; i < chunkSize; i++) {
			for (int j = 0; j < chunkSize; j++) {
				// Checks if blocks from neighboring chunks are changed
				int [] dx = {chunkMask, 0, i, i, i, i};
				int [] dy = {j, j, j, j, chunkMask, 0};
				int [] dz = {i, i, chunkMask, 0, j, j};
				int [] invdx = {0, chunkMask, i, i, i, i};
				int [] invdy = {j, j, j, j, 0, chunkMask};
				int [] invdz = {i, i, 0, chunkMask, j, j};
				for(int k = 0; k < chunks.length; k++) {
					if (toCheck[k]) {
						ch = chunks[chunkIndices[k]];
						// Load light from loaded chunks:
						int indexThis = getIndex(invdx[k], invdy[k], invdz[k]);
						int indexOther = getIndex(dx[k], dy[k], dz[k]);
						constructiveLightUpdate(indexThis, ch.light[indexOther]);
						// Update blocks from loaded chunks:
						BlockInstance inst = ch.getBlockInstanceAt(indexOther);
						int block = ch.blocks[indexOther];
						// Update neighbor information:
						if (inst != null) {
							inst.updateNeighbor(chunkIndices[k] ^ 1, blocksBlockNot(blocks[indexThis], block, indexThis - indexOther));
							continue;
						}
						// Update visibility:
						if (block == 0) {
							continue;
						}
						if (blocksBlockNot(blocks[indexThis], block, indexThis - indexOther)) {
							ch.revealBlock(dx[k], dy[k], dz[k]);
							continue;
						}
						ch.setUpdated();
					}
				}
			}
		}
		loaded = true;
	}
	
	/**
	 * Used if the sunlight channel is at maximum.
	 * @param index
	 */
	public void propagateSunLight(int index) {
		if (blocks[index] != 0 && (!Blocks.lightingTransparent(blocks[index]) || (Blocks.absorption(blocks[index]) & 0xff000000) != 0)) {
			int x = index>>chunkShift & chunkMask;
			int y = index>>chunkShift2 & chunkMask;
			int z = index & chunkMask;
			map.mapIO.setHeight(x+wx, z+wz, y+wy, map);
			return;
		} else if ((light[index] & 0xff000000) != 0xff000000) {
			constructiveLightUpdate(index, 255+8, 24);
			// y-1:
			if ((index & getIndex(0, chunkMask, 0)) == 0) { // if (y == 0)
				VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy - Chunk.chunkSize, wz);
				if (neighborChunk != null) {
					neighborChunk.propagateSunLight(index ^ getIndex(0, chunkMask, 0));
				}
			} else {
				propagateSunLight(index - getIndex(0, 1, 0));
			}
		}
	}

	/**
	 * Updates all light channels of this block <b>constructively</b>.
	 * @param index
	 */
	public void constructiveLightUpdate(int index) {
		int blockColor = Blocks.light(blocks[index]);
		int s = blockColor >>> 24;
		int r = (blockColor >>> 16) & 255;
		int g = (blockColor >>> 8) & 255;
		int b = blockColor & 255;
		if (s != 0) constructiveLightUpdate(index, s, 24);
		if (r != 0) constructiveLightUpdate(index, r, 16);
		if (g != 0) constructiveLightUpdate(index, g, 8);
		if (b != 0) constructiveLightUpdate(index, b, 0);
	}

	/**
	 * Updates all light channels of this block <b>constructively</b>.
	 * @param index
	 */
	public void constructiveLightUpdate(int index, int color) {
		int s = color >>> 24;
		int r = (color >>> 16) & 255;
		int g = (color >>> 8) & 255;
		int b = color & 255;
		if (s != 0) constructiveLightUpdate(index, s, 24);
		if (r != 0) constructiveLightUpdate(index, r, 16);
		if (g != 0) constructiveLightUpdate(index, g, 8);
		if (b != 0) constructiveLightUpdate(index, b, 0);
	}
	
	/**
	 * Updates one specific light channel of this block <b>constructively</b>.
	 * @param index
	 * @param channelMask
	 * @param channelShift
	 */
	public void constructiveLightUpdate(int index, int lightValue, int channelShift) {
		if (!startedloading) return;
		if (!Blocks.lightingTransparent(blocks[index]) && ((Blocks.light(blocks[index]) >>> channelShift) & 255) != lightValue) return;
		lightValue = propagateLight(blocks[index], lightValue, channelShift);
		if (blocks[index] != 0)
			lightValue = Math.max(lightValue, ((Blocks.light(blocks[index]) >>> channelShift) & 255));
		int prevValue = (light[index] >>> channelShift) & 255;
		setUpdated();
		if (lightValue <= prevValue) return;
		if (channelShift == 24 && lightValue == 255) { // Update the sun height map.
			int x = index/getIndex(chunkMask, 0, 0) & chunkMask;
			int y = index/getIndex(0, chunkMask, 0) & chunkMask;
			int z = index/getIndex(0, 0, chunkMask) & chunkMask;
			map.mapIO.setHeight(x+wx, z+wz, Math.min(y+wy-1, map.mapIO.getHeight(x+wx, z+wz, map)), map);
		}
		light[index] = (~(255 << channelShift) & light[index]) | (lightValue << channelShift);
		// Go through all neighbors:
		// z-1:
		if ((index & getIndex(0, 0, chunkMask)) == 0) { // if (z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy, wz - Chunk.chunkSize);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ getIndex(0, 0, chunkMask), lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index - getIndex(0, 0, 1), lightValue, channelShift);
		}
		// z+1:
		if ((index & getIndex(0, 0, chunkMask)) == getIndex(0, 0, chunkMask)) { // if (z == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy, wz + Chunk.chunkSize);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ getIndex(0, 0, chunkMask), lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index + getIndex(0, 0, 1), lightValue, channelShift);
		}
		// x-1:
		if ((index & getIndex(chunkMask, 0, 0)) == 0) { // if (x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx - Chunk.chunkSize, wy, wz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ getIndex(chunkMask, 0, 0), lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index - getIndex(1, 0, 0), lightValue, channelShift);
		}
		// x+1:
		if ((index & getIndex(chunkMask, 0, 0)) == getIndex(chunkMask, 0, 0)) { // if (x == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx + Chunk.chunkSize, wy, wz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ getIndex(chunkMask, 0, 0), lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index + getIndex(1, 0, 0), lightValue, channelShift);
		}
		// y-1:
		if ((index & getIndex(0, chunkMask, 0)) == 0) { // if (y == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy - Chunk.chunkSize, wz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ getIndex(0, chunkMask, 0), lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift);
			}
		} else {
			constructiveLightUpdate(index - getIndex(0, 1, 0), lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift);
		}
		// y+1:
		if ((index & getIndex(0, chunkMask, 0)) == getIndex(0, chunkMask, 0)) { // if (y == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy + Chunk.chunkSize, wz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ getIndex(0, chunkMask, 0), lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index + getIndex(0, 1, 0), lightValue, channelShift);
		}
	}
	
	/**
	 * Update the local light level after a block update.
	 * @param x
	 * @param y
	 * @param z
	 */
	public void lightUpdate(int x, int y, int z) {
		lightUpdate(getIndex(x, y, z));
	}
	
	/**
	 * Updates all light channels of this block <b>destructively</b>.
	 * @param index
	 */
	public void lightUpdate(int index) {
		lightUpdateInternal(index, 24);
		lightUpdateInternal(index, 16);
		lightUpdateInternal(index, 8);
		lightUpdateInternal(index, 0);
	}
	
	/**
	 * Updates one specific light channel of this block <b>destructively</b>. This means that the engine tries to remove lighting and re-add it if it was falsely removed.
	 * @param index
	 * @param channelMask
	 * @param channelShift
	 */
	public void lightUpdateInternal(int index, int channelShift) {
		if (!startedloading) return;
		int newValue = 0;
		if (blocks[index] != 0) newValue = (Blocks.light(blocks[index]) >>> channelShift) & 255;
		int prevValue = (light[index] >>> channelShift) & 255;
		// Go through all neighbors and check if the old value comes from them:
		// z-1:
		if ((index & getIndex(0, 0, chunkMask)) == 0) { // if (z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy, wz - Chunk.chunkSize);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ getIndex(0, 0, chunkMask)] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index - getIndex(0, 0, 1)] >>> channelShift) & 255, channelShift));
		}
		// z+1:
		if ((index & getIndex(0, 0, chunkMask)) == getIndex(0, 0, chunkMask)) { // if (z == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy, wz + Chunk.chunkSize);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ getIndex(0, 0, chunkMask)] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index + getIndex(0, 0, 1)] >>> channelShift) & 255, channelShift));
		}
		// x-1:
		if ((index & getIndex(chunkMask, 0, 0)) == 0) { // if (x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx - Chunk.chunkSize, wy, wz);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ getIndex(chunkMask, 0, 0)] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index - getIndex(1, 0, 0)] >>> channelShift) & 255, channelShift));
		}
		// x+1:
		if ((index & getIndex(chunkMask, 0, 0)) == getIndex(chunkMask, 0, 0)) { // if (x == chunkSIze-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx + Chunk.chunkSize, wy, wz);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ getIndex(chunkMask, 0, 0)] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index + getIndex(1, 0, 0)] >>> channelShift) & 255, channelShift));
		}
		// y-1:
		if ((index & getIndex(0, chunkMask, 0)) == 0) { // if (y == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy - Chunk.chunkSize, wz);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], ((neighborChunk.light[index ^ getIndex(0, chunkMask, 0)] >>> channelShift) & 255), channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], ((light[index - getIndex(0, 1, 0)] >>> channelShift) & 255), channelShift));
		}
		// y+1:
		if ((index & getIndex(0, chunkMask, 0)) == getIndex(0, chunkMask, 0)) { // if (y == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy + Chunk.chunkSize, wz);
			if (neighborChunk != null) {
				int lightValue = ((neighborChunk.light[index ^ getIndex(0, chunkMask, 0)] >>> channelShift) & 255);
				newValue = Math.max(newValue, propagateLight(blocks[index], lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift));
			}
		} else {
			int lightValue = ((light[index + getIndex(0, 1, 0)] >>> channelShift) & 255);
			newValue = Math.max(newValue, propagateLight(blocks[index], lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift));
		}
		
		// Insert the new value and update neighbors:
		if (newValue == prevValue) return;
		if (newValue >= prevValue) {
			if (channelShift == 24 && newValue == 255) {
				propagateSunLight(index);
			} else {
				constructiveLightUpdate(index, newValue - propagateLight(blocks[index], 0, channelShift), channelShift);
			}
				return;
		}
		if (channelShift == 24 && prevValue == 255) { // Update the sun height map.
			int x = index/getIndex(chunkMask, 0, 0) & chunkMask;
			int y = index/getIndex(0, chunkMask, 0) & chunkMask;
			int z = index/getIndex(0, 0, chunkMask) & chunkMask;
			map.mapIO.setHeight(x+wx, z+wz, Math.max(y+wy, map.mapIO.getHeight(x+wx, z+wz, map)), map);
		}
		setUpdated();
		light[index] = (light[index] & ~(255 << channelShift)) | (newValue << channelShift);
		// Go through all neighbors and update them:
		// z-1:
		if ((index & getIndex(0, 0, chunkMask)) == 0) { // if (z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy, wz - Chunk.chunkSize);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ getIndex(0, 0, chunkMask), channelShift);
			}
		} else {
			lightUpdateInternal(index - getIndex(0, 0, 1), channelShift);
		}
		// z+1:
		if ((index & getIndex(0, 0, chunkMask)) == getIndex(0, 0, chunkMask)) { // if (z == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy, wz + Chunk.chunkSize);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ getIndex(0, 0, chunkMask), channelShift);
			}
		} else {
			lightUpdateInternal(index + getIndex(0, 0, 1), channelShift);
		}
		// x-1:
		if ((index & getIndex(chunkMask, 0, 0)) == 0) { // if (x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx - Chunk.chunkSize, wy, wz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ getIndex(chunkMask, 0, 0), channelShift);
			}
		} else {
			lightUpdateInternal(index - getIndex(1, 0, 0), channelShift);
		}
		// x+1:
		if ((index & getIndex(chunkMask, 0, 0)) == getIndex(chunkMask, 0, 0)) { // if (x == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx + Chunk.chunkSize, wy, wz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ getIndex(chunkMask, 0, 0), channelShift);
			}
		} else {
			lightUpdateInternal(index + getIndex(1, 0, 0), channelShift);
		}
		// y-1:
		if ((index & getIndex(0, chunkMask, 0)) == 0) { // if (y == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy - Chunk.chunkSize, wz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ getIndex(0, chunkMask, 0), channelShift);
			}
		} else {
			lightUpdateInternal(index - getIndex(0, 1, 0), channelShift);
		}
		// y+1:
		if ((index & getIndex(0, chunkMask, 0)) == getIndex(0, chunkMask, 0)) { // if (y == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(wx, wy + Chunk.chunkSize, wz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ getIndex(0, chunkMask, 0), channelShift);
			}
		} else {
			lightUpdateInternal(index + getIndex(0, 1, 0), channelShift);
		}
	}
	
	private int propagateLight(int block, int previousValue, int channelShift) {
		if (!Blocks.lightingTransparent(block)) return 0;
		int transparencyFactor = 8;
		transparencyFactor += (Blocks.absorption(block) >>> channelShift) & 255;
		return previousValue - transparencyFactor;
	}
	
	@Override
	public int getLight(int x, int y, int z) {
		return light[getIndex(x, y, z)];
	}
}
