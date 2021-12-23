package cubyz.rendering;

import java.util.ArrayList;

import cubyz.client.ClientSettings;
import cubyz.utils.Utilities;
import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockInstance;

/**
 * The client version of a chunk that handles all the features that are related to rendering and therefore not needed on servers.
 */

public class VisibleChunk extends NormalChunk {
	/**Stores sun r g b channels of each light channel in one integer. This makes it easier to store and to access.*/
	private int[] light;
	
	public VisibleChunk(ServerWorld world, Integer cx, Integer cy, Integer cz) {
		super(world, cx, cy, cz);
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
		VisibleChunk ch = (VisibleChunk)world.getChunk(cx - 1, cy, cz);
		chunks[Neighbors.DIR_NEG_X] = ch;
		boolean chx0 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(cx + 1, cy, cz);
		chunks[Neighbors.DIR_POS_X] = ch;
		boolean chx1 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(cx, cy, cz - 1);
		chunks[Neighbors.DIR_NEG_Z] = ch;
		boolean chz0 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(cx, cy, cz + 1);
		chunks[Neighbors.DIR_POS_Z] = ch;
		boolean chz1 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(cx, cy - 1, cz);
		chunks[Neighbors.DIR_DOWN] = ch;
		boolean chy0 = ch != null && ch.startedloading;
		ch = (VisibleChunk)world.getChunk(cx, cy + 1, cz);
		chunks[Neighbors.DIR_UP] = ch;
		boolean chy1 = ch != null && ch.startedloading;
		// Use lighting calculations that are done anyways if easyLighting is enabled to determine the maximum height inside this chunk.
		ArrayList<Integer> lightSources = new ArrayList<>();
		// Go through all blocks(which is more efficient than creating a block-list at generation time because about half of the blocks are non-air).
		for(int x = 0; x < chunkSize; x++) {
			for(int y = 0; y < chunkSize; y++) {
				for(int  z = 0; z < chunkSize; z++) {
					int index = (x << chunkShift) | (y << chunkShift2) | z;
					int b = blocks[index];
					if (b != 0) {
						int[] indices = new int[6];
						int[] neighbors = getNeighbors(x, y , z, indices);
						for (int i = 0; i < neighbors.length; i++) {
							if (blocksBlockNot(neighbors[i], b, index - indices[i])
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
			if ((index & chunkMask<<chunkShift2) == 0) { // if (y == 0)
				VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy-1, cz);
				if (neighborChunk != null) {
					neighborChunk.propagateSunLight(index ^ chunkMask<<chunkShift2);
				}
			} else {
				propagateSunLight(index - (1 << chunkShift2));
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
			int x = index>>chunkShift & chunkMask;
			int y = index>>chunkShift2 & chunkMask;
			int z = index & chunkMask;
			map.mapIO.setHeight(x+wx, z+wz, Math.min(y+wy-1, map.mapIO.getHeight(x+wx, z+wz, map)), map);
		}
		light[index] = (~(255 << channelShift) & light[index]) | (lightValue << channelShift);
		// Go through all neighbors:
		// z-1:
		if ((index & chunkMask) == 0) { // if (z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy, cz-1);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index^0x000f, lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index-1, lightValue, channelShift);
		}
		// z+1:
		if ((index & chunkMask) == chunkMask) { // if (z == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy, cz+1);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ chunkMask, lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index+1, lightValue, channelShift);
		}
		// x-1:
		if ((index & chunkMask<<chunkShift) == 0) { // if (x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx-1, cy, cz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ chunkMask<<chunkShift, lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index-(1 << chunkShift), lightValue, channelShift);
		}
		// x+1:
		if ((index & chunkMask<<chunkShift) == chunkMask<<chunkShift) { // if (x == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx+1, cy, cz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ chunkMask<<chunkShift, lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index+(1 << chunkShift), lightValue, channelShift);
		}
		// y-1:
		if ((index & chunkMask<<chunkShift2) == 0) { // if (y == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy-1, cz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ chunkMask<<chunkShift2, lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift);
			}
		} else {
			constructiveLightUpdate(index-(1 << chunkShift2), lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift);
		}
		// y+1:
		if ((index & chunkMask<<chunkShift2) == chunkMask<<chunkShift2) { // if (y == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy+1, cz);
			if (neighborChunk != null) {
				neighborChunk.constructiveLightUpdate(index ^ chunkMask<<chunkShift2, lightValue, channelShift);
			}
		} else {
			constructiveLightUpdate(index+(1 << chunkShift2), lightValue, channelShift);
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
		if ((index & chunkMask) == 0) { // if (z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy, cz-1);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ chunkMask] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index - 1] >>> channelShift) & 255, channelShift));
		}
		// z+1:
		if ((index & chunkMask) == chunkMask) { // if (z == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy, cz+1);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ chunkMask] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index + 1] >>> channelShift) & 255, channelShift));
		}
		// x-1:
		if ((index & chunkMask<<chunkShift) == 0) { // if (x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx-1, cy, cz);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ chunkMask<<chunkShift] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index-(1 << chunkShift)] >>> channelShift) & 255, channelShift));
		}
		// x+1:
		if ((index & chunkMask<<chunkShift) == chunkMask<<chunkShift) { // if (x == chunkSIze-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx+1, cy, cz);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], (neighborChunk.light[index ^ chunkMask<<chunkShift] >>> channelShift) & 255, channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], (light[index+(1 << chunkShift)] >>> channelShift) & 255, channelShift));
		}
		// y-1:
		if ((index & chunkMask<<chunkShift2) == 0) { // if (y == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy-1, cz);
			if (neighborChunk != null) {
				newValue = Math.max(newValue, propagateLight(blocks[index], ((neighborChunk.light[index ^ chunkMask<<chunkShift2] >>> channelShift) & 255), channelShift));
			}
		} else {
			newValue = Math.max(newValue, propagateLight(blocks[index], ((light[index-(1 << chunkShift2)] >>> channelShift) & 255), channelShift));
		}
		// y+1:
		if ((index & chunkMask<<chunkShift2) == chunkMask<<chunkShift2) { // if (y == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy+1, cz);
			if (neighborChunk != null) {
				int lightValue = ((neighborChunk.light[index ^ chunkMask<<chunkShift2] >>> channelShift) & 255);
				newValue = Math.max(newValue, propagateLight(blocks[index], lightValue + (channelShift == 24 && lightValue == 255 ? 8 : 0), channelShift));
			}
		} else {
			int lightValue = ((light[index+(1 << chunkShift2)] >>> channelShift) & 255);
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
			int x = index>>chunkShift & chunkMask;
			int y = index>>chunkShift2 & chunkMask;
			int z = index & chunkMask;
			map.mapIO.setHeight(x+wx, z+wz, Math.max(y+wy, map.mapIO.getHeight(x+wx, z+wz, map)), map);
		}
		setUpdated();
		light[index] = (light[index] & ~(255 << channelShift)) | (newValue << channelShift);
		// Go through all neighbors and update them:
		// z-1:
		if ((index & chunkMask) == 0) { // if (z == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy, cz-1);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ chunkMask, channelShift);
			}
		} else {
			lightUpdateInternal(index-1, channelShift);
		}
		// z+1:
		if ((index & chunkMask) == chunkMask) { // if (z == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy, cz+1);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ chunkMask, channelShift);
			}
		} else {
			lightUpdateInternal(index+1, channelShift);
		}
		// x-1:
		if ((index & chunkMask<<chunkShift) == 0) { // if (x == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx-1, cy, cz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ chunkMask<<chunkShift, channelShift);
			}
		} else {
			lightUpdateInternal(index-(1 << chunkShift), channelShift);
		}
		// x+1:
		if ((index & chunkMask<<chunkShift) == chunkMask<<chunkShift) { // if (x == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx+1, cy, cz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ chunkMask<<chunkShift, channelShift);
			}
		} else {
			lightUpdateInternal(index+(1 << chunkShift), channelShift);
		}
		// y-1:
		if ((index & chunkMask<<chunkShift2) == 0) { // if (y == 0)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy-1, cz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ chunkMask<<chunkShift2, channelShift);
			}
		} else {
			lightUpdateInternal(index-(1 << chunkShift2), channelShift);
		}
		// y+1:
		if ((index & chunkMask<<chunkShift2) == chunkMask<<chunkShift2) { // if (y == chunkSize-1)
			VisibleChunk neighborChunk = (VisibleChunk)world.getChunk(cx, cy+1, cz);
			if (neighborChunk != null) {
				neighborChunk.lightUpdateInternal(index ^ chunkMask<<chunkShift2, channelShift);
			}
		} else {
			lightUpdateInternal(index+(1 << chunkShift2), channelShift);
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
