 package io.cubyz.world;

import java.util.ArrayList;
import java.util.Map;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.Settings;
import io.cubyz.Utilities;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.math.Bits;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;
import io.cubyz.util.FastList;
import io.cubyz.world.generator.SurfaceGenerator;

/**
 * A 16×WORLD_HEIGHT×16 big chunk of the world map.
 */

public class NormalChunk implements Chunk {
	// used for easy for-loop access of neighbors and their relative direction:
	// East, West, South, North, Down, Up.
	private static final int[] neighborRelativeX = {-1, 1, 0, 0, 0, 0};
	private static final int[] neighborRelativeY = {0, 0, 0, 0, -1, 1};
	private static final int[] neighborRelativeZ = {0, 0, -1, 1, 0, 0};
	// Due to having powers of 2 as dimensions it is more efficient to use a one-dimensional array.
	private Block[] blocks;
	private byte[] blockData; // Important data used to store rotation. Will be used later for water levels and stuff like that.
	private BlockInstance[] inst; // Stores all visible BlockInstances. Can be faster accessed using coordinates.
	private int[] light; // Stores sun r g b channels of each light channel in one integer. This makes it easier to store and to access.
	private ArrayList<Integer> liquids = new ArrayList<>(); // Stores the local index of the block.
	private ArrayList<Integer> updatingLiquids = new ArrayList<>(); // liquids that should be updated at next frame. Stores the local index of the block.
	private ArrayList<BlockChange> changes; // Reports block changes. Only those will be saved!
	private FastList<BlockInstance> visibles = new FastList<BlockInstance>(50, BlockInstance.class);
	private int cx, cz;
	private int wx, wz;
	private boolean generated;
	private boolean loaded;
	private ArrayList<BlockEntity> blockEntities = new ArrayList<>();
	
	private Surface surface;
	
	Block noLight = new Block(); // A random block used as a replacement for blocks from yet unloaded chunks.
	
	private int maxHeight; // Max height of the terrain after loading. Used to prevent bugs at chunk borders.
	
	public NormalChunk(int cx, int cz, Surface surface, ArrayList<BlockChange> changes) {
		if(surface != null) {
			cx = CubyzMath.worldModulo(cx, surface.getSizeX() >>> 4);
			cz = CubyzMath.worldModulo(cz, surface.getSizeZ() >>> 4);
		}
		if(Settings.easyLighting) {
			light = new int[16*World.WORLD_HEIGHT*16];
		}
		inst = new BlockInstance[16*World.WORLD_HEIGHT*16];
		blocks = new Block[16*World.WORLD_HEIGHT*16];
		blockData = new byte[16*World.WORLD_HEIGHT*16];
		this.cx = cx;
		this.cz = cz;
		wx = cx << 4;
		wz = cz << 4;
		this.surface = surface;
		this.changes = changes;
	}
	
	public void generateFrom(SurfaceGenerator gen) {
		gen.generate(this, surface);
		generated = true;
	}
	// Clears the data structures which are used for visible blocks.
	public void clear() {
		visibles.clear();
		Utilities.fillArray(inst, null);
		Utilities.fillArray(light, 0);
	}
	// Loads the chunk
	public void load() {
		if(loaded) {
			// Empty the list, so blocks won't get added twice. This will also be important, when there is a manual chunk reloading.
			clear();
		}
		
		loaded = true;
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
		if(Settings.easyLighting) {
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
		if(Settings.easyLighting) {
			// Update the highest layer that is not just air:
			for(int x = 0; x < 16; x++) {
				for(int z = 0; z < 16; z++) {
					localLightUpdate(x, maxHeight, z, 24, 0x00ffffff);
				}
			}
			// Look at the neighboring chunks. Update only the outer corners:
			NormalChunk no = surface.getChunk(cx-1, cz);
			NormalChunk po = surface.getChunk(cx+1, cz);
			NormalChunk on = surface.getChunk(cx, cz-1);
			NormalChunk op = surface.getChunk(cx, cz+1);
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
			// Take care about light sources:
			for(int index : lightSources) {
				lightUpdate((index >>> 4) & 15, (index >>> 8) & 255, index & 15);
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
						if(Settings.easyLighting && b.getLight() != 0) { // Process light sources
							lightSources.add(index);
						}
					}
				}
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
						}
						// Update visibility:
						if(block == null) {
							continue;
						}
						if(ch.contains(dx[k] + wx, j, dz[k] + wz)) {
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
	}
	
	// Function calls are faster than two pointer references, which would happen when using a 3D-array, and functions can additionally be inlined by the VM.
	private void setBlock(int x, int y, int z, Block b, byte data) {
		int index = (x << 4) | (y << 8) | z;
		blocks[index] = b;
		blockData[index] = data;
	}
	
	public void setBlockData(int x, int y, int z, byte data) {
		int index = (x << 4) | (y << 8) | z;
		if(blockData[index] != data) {
			// Registers blockChange:
			int bcIndex = -1; // Checks if it is already in the list
			for(int i = 0; i < changes.size(); i++) {
				BlockChange bc = changes.get(i);
				if(bc.x == x && bc.y == y && bc.z == z) {
					bcIndex = i;
					break;
				}
			}
			if(index == -1) { // Creates a new object if the block wasn't changed before
				changes.add(new BlockChange(-1, blocks[index].ID, x, y, z, blockData[index], data));
			} else if(blocks[index].ID == changes.get(bcIndex).oldType && data == changes.get(bcIndex).oldData) { // Removes the object if the block reverted to it's original state.
				changes.remove(bcIndex);
			} else {
				changes.get(bcIndex).newData = data;
			}
			blockData[index] = data;
			// Update the instance:
			if(inst[index] != null)
				inst[index].setData(data, surface.getStellarTorus().getWorld().getLocalPlayer());
		}
	}
	
	public byte getBlockData(int x, int y, int z) {
		int index = (x << 4) | (y << 8) | z;
		return blockData[index];
	}
	
	/**
	 * Internal "hack" method used for the overlay, DO NOT USE!
	 */
	@Deprecated
	public void createBlocksForOverlay() {
		blocks = new Block[16*256*16];
		blockData = new byte[65536];
	}
	// Performs a light update in all channels on this block.
	private void lightUpdate(int x, int y, int z) {
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
	// Update only 1 corner. Since this is always done during loading, only constructive updates are needed:
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
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null) chunk.constructiveLightUpdate(x & 15, y, z & 15, shift, mask, value, nx, px, ny, py, nz, pz);
			return;
		}
		// Ignore if the current light value is brighter.
		if(((light[(x << 4) | (y << 8) | z] >>> shift) & 255) >= value) {
			return;
		}
		light[(x << 4) | (y << 8) | z] = (light[(x << 4) | (y << 8) | z] & mask) | (value << shift);
		// Get all eight neighbors of this lighting node:
		Block[] neighbors = new Block[8];
		for(int dx = -1; dx <= 0; dx++) {
			for(int dy = -1; dy <= 0; dy++) {
				for(int dz = -1; dz <= 0; dz++) {
					neighbors[7 + (dx << 2) + (dy << 1) + dz] = getBlockUnboundAndUpdateLight(x+dx, y+dy, z+dz);
					// Take care about the case that this block is a light source, that is brighter than the current light level:
					if(neighbors[7 + (dx << 2) + (dy << 1) + dz] != null && ((neighbors[7 + (dx << 2) + (dy << 1) + dz].getLight() >>> shift) & 255) > value)
						return;
				}
			}
		}
		// Update all neighbors that should be updated:
		if(nx) {
			int light = applyNeighborsConstructive(value, shift, neighbors[0], neighbors[1], neighbors[2], neighbors[3]);
			constructiveLightUpdate(x-1, y, z, shift, mask, light, true, false, true, true, true, true);
		}
		if(px) {
			int light = applyNeighborsConstructive(value, shift, neighbors[4], neighbors[5], neighbors[6], neighbors[7]);
			constructiveLightUpdate(x+1, y, z, shift, mask, light, false, true, true, true, true, true);
		}
		if(nz) {
			int light = applyNeighborsConstructive(value, shift, neighbors[0], neighbors[2], neighbors[4], neighbors[6]);
			constructiveLightUpdate(x, y, z-1, shift, mask, light, true, true, true, true, true, false);
		}
		if(pz) {
			int light = applyNeighborsConstructive(value, shift, neighbors[1], neighbors[3], neighbors[5], neighbors[7]);
			constructiveLightUpdate(x, y, z+1, shift, mask, light, true, true, true, true, false, true);
		}
		if(ny) {
			int light = applyNeighborsConstructive(value, shift, neighbors[0], neighbors[1], neighbors[4], neighbors[5]);
			if(shift == 24 && light != 0)
				light += 8;
			constructiveLightUpdate(x, y-1, z, shift, mask, light, true, true, true, false, true, true);
		}
		if(py) {
			int light = applyNeighborsConstructive(value, shift, neighbors[2], neighbors[3], neighbors[6], neighbors[7]);
			constructiveLightUpdate(x, y+1, z, shift, mask, light, true, true, false, true, true, true);
		}
	}
	private int applyNeighbors(int light, int shift, Block n1, Block n2, Block n3, Block n4) {
		light = applyNeighborsConstructive((light >>> shift) & 255, shift, n1, n2, n3, n4);
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
	private int applyNeighborsConstructive(int light, int shift, Block n1, Block n2, Block n3, Block n4) {
		light <<= 2; // make sure small absorptions don't get ignored while dividing by 4.
		int solidNeighbors = 0;
		if(n1 != null) {
			if(n1.isTransparent()) {
				light -= (n1.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		if(n2 != null) {
			if(n2.isTransparent()) {
				light -= (n2.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		if(n3 != null) {
			if(n3.isTransparent()) {
				light -= (n3.getAbsorption() >>> shift) & 255;
			} else
				solidNeighbors++;
		}
		if(n4 != null) {
			if(n4.isTransparent()) {
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
		if(!Settings.easyLighting || y < 0 || y >= World.WORLD_HEIGHT || !generated) return -1;
		// Check if it's inside this chunk:
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null) return chunk.localLightUpdate(x & 15, y, z & 15, shift, mask);
			return -1;
		}
		int maxLight = 0;
		
		// Get all eight neighbors of this lighting node:
		Block[] neighbors = new Block[8];
		for(int dx = -1; dx <= 0; dx++) {
			for(int dy = -1; dy <= 0; dy++) {
				for(int dz = -1; dz <= 0; dz++) {
					neighbors[7 + (dx << 2) + (dy << 1) + dz] = getBlockUnbound(x+dx, y+dy, z+dz);
					// Take care about the case that this block is a light source:
					if(neighbors[7 + (dx << 2) + (dy << 1) + dz] != null)
						maxLight = Math.max(maxLight, (neighbors[7 + (dx << 2) + (dy << 1) + dz].getLight() >>> shift) & 255);
				}
			}
		}
		
		// Check all neighbors and find their highest lighting in the specified channel after applying block-specific effects to it:
		int index = (x << 4) | (y << 8) | z; // Works close to the datastructure. Allows for some optimizations.
		
		if(x != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-16], shift, neighbors[0], neighbors[1], neighbors[2], neighbors[3]));
		} else {
			NormalChunk chunk = surface.getChunk(cx-1, cz);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index | 0xf0], shift, neighbors[0], neighbors[1], neighbors[2], neighbors[3]));
			}
		}
		if(x != 15) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index+16], shift, neighbors[4], neighbors[5], neighbors[6], neighbors[7]));
		} else {
			NormalChunk chunk = surface.getChunk(cx+1, cz);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index & ~0xf0], shift, neighbors[4], neighbors[5], neighbors[6], neighbors[7]));
			}
		}
		if(z != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-1], shift, neighbors[0], neighbors[2], neighbors[4], neighbors[6]));
		} else {
			NormalChunk chunk = surface.getChunk(cx, cz-1);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index | 0xf], shift, neighbors[0], neighbors[2], neighbors[4], neighbors[6]));
			}
		}
		if(z != 15) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index+1], shift, neighbors[1], neighbors[3], neighbors[5], neighbors[7]));
		} else {
			NormalChunk chunk = surface.getChunk(cx, cz+1);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index & ~0xf], shift, neighbors[1], neighbors[3], neighbors[5], neighbors[7]));
			}
		}
		if(y != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-256], shift, neighbors[0], neighbors[1], neighbors[4], neighbors[5]));
		}
		if(y != 255) {
			int local = applyNeighbors(light[index+256], shift, neighbors[2], neighbors[3], neighbors[6], neighbors[7]);
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
			return maxLight;
		}
		return -1;
	}
	// Used for first time loading. For later update also negative changes have to be taken into account making the system more complex.
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
	
	/**
	 * Add the <code>Block</code> b at relative space defined by X, Y, and Z, and if out of bounds, call this method from the other chunk<br/>
	 * Meaning that if x or z are out of bounds, this method will call the same method from other chunks to add it.
	 * @param b
	 * @param x global
	 * @param y global
	 * @param z
	 * @param considerPrevious If the degradability of the block which was there before should be considered.
	 */
	public void addBlockPossiblyOutside(Block b, byte data, int x, int y, int z, boolean considerPrevious) {
		// Make the boundary checks:
		if (b == null) return;
		if(y >= World.WORLD_HEIGHT)
			return;
		int rx = x - wx;
		int rz = z - wz;
		if(rx < 0 || rx > 15 || rz < 0 || rz > 15) {
			if (surface.getChunk(cx + ((rx & ~15) >> 4), cz + ((rz & ~15) >> 4)) == null)
				return;
			surface.getChunk(cx + ((rx & ~15) >> 4), cz + ((rz & ~15) >> 4)).addBlock(b, data, x & 15, y, z & 15, considerPrevious);
			return;
		} else {
			addBlock(b, data, x & 15, y, z & 15, considerPrevious);
		}
	}
	
	/**
	 * @param b
	 * @param data
	 * @param x Relative to this Chunk.
	 * @param y
	 * @param z Relative to this Chunk.
	 * @param registerBlockChange
	 * @param considerPrevious If the degradability of the block which was there before should be considered.
	 */
	public void addBlock(Block b, byte data, int x, int y, int z, boolean considerPrevious) {
		if(y >= World.WORLD_HEIGHT)
			return;
		Block b2 = getBlockAt(x, y, z);
		if(b2 != null) {
			if((!b2.isDegradable() || b.isDegradable()) && considerPrevious) {
				return;
			}
			removeBlockAt(x, y, z, false);
		}
		setBlock(x, y, z, b, data);
		if (b.hasBlockEntity()) {
			Vector3i pos = new Vector3i(wx+x, y, wz+z);
			blockEntities.add(b.createBlockEntity(surface, pos));
		}
		if (b.getBlockClass() == BlockClass.FLUID) {
			liquids.add((x << 4) | (y << 8) | z);
			updatingLiquids.add((x << 4) | (y << 8) | z);
		}
		if(generated) {
			byte[] dataN = new byte[6];
			int[] indices = new int[6];
			Block[] neighbors = getNeighbors(x, y ,z, dataN, indices);
			BlockInstance[] visibleNeighbors = getVisibleNeighbors(x + wx, y, z + wz);
			for(int k = 0; k < 6; k++) {
				if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, getsBlocked(neighbors[k], b, dataN[k], ((x << 4) | (y << 8) | z) - indices[k]), surface.getStellarTorus().getWorld().getLocalPlayer());
			}
			
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksLight(neighbors[i], b, dataN[i], ((x << 4) | (y << 8) | z) - indices[i])) {
					revealBlock(x&15, y, z&15);
					break;
				}
			}
			
			for (int i = 0; i < neighbors.length; i++) {
				if(neighbors[i] != null) {
					int x2 = x+neighborRelativeX[i];
					int y2 = y+neighborRelativeY[i];
					int z2 = z+neighborRelativeZ[i];
					NormalChunk ch = getChunk(x2 + wx, z2 + wz);
					if (ch.contains(x2 & 15, y2, z2 & 15)) {
						byte[] dataN1 = new byte[6];
						int[] indices1 = new int[6];
						Block[] neighbors1 = ch.getNeighbors(x2 & 15, y2, z2 & 15, dataN1, indices1);
						boolean vis = true;
						for (int j = 0; j < neighbors1.length; j++) {
							if (blocksLight(neighbors1[j], neighbors[i], dataN1[i], indices[i] - indices1[j])) {
								vis = false;
								break;
							}
						}
						if(vis) {
							ch.hideBlock(x2 & 15, y2, z2 & 15);
						}
					}
					if (neighbors[i].getBlockClass() == BlockClass.FLUID) {
						int index = ((x2 & 15) << 4) | (y2 << 8) | (z2 & 15);
						if (!updatingLiquids.contains(index))
							updatingLiquids.add(index);
					}
				}
			}
		}

		// Registers blockChange:
		int index = -1; // Checks if it is already in the list
		for(int i = 0; i < changes.size(); i++) {
			BlockChange bc = changes.get(i);
			if(bc.x == x && bc.y == y && bc.z == z) {
				index = i;
				break;
			}
		}
		if(index == -1) { // Creates a new object if the block wasn't changed before
			changes.add(new BlockChange(-1, b.ID, x, y, z, (byte)0, data));
		} else if(b.ID == changes.get(index).oldType && data == changes.get(index).oldData) { // Removes the object if the block reverted to it's original state.
			changes.remove(index);
		} else {
			changes.get(index).newType = b.ID;
			changes.get(index).newData = data;
		}
		if(loaded)
			lightUpdate(x, y, z);
	}
	
	// Apply Block Changes loaded from file/stored in WorldIO. Must be called before loading.
	public void applyBlockChanges() {
		for(BlockChange bc : changes) {
			int index = (bc.x << 4) | (bc.y << 8) | bc.z;
			bc.oldType = blocks[index] == null ? -1 : blocks[index].ID;
			bc.oldData = blockData[index];
			Block b = bc.newType == -1 ? null : surface.getPlanetBlocks()[bc.newType];
			if (b != null && b.hasBlockEntity()) {
				Vector3i pos = new Vector3i(wx+bc.x, bc.y, wz+bc.z);
				blockEntities.add(b.createBlockEntity(surface, pos));
			}
			blocks[index] = b;
			blockData[index] = bc.newData;
		}
	}
	
	public boolean blocksLight(Block b, Block a, byte data, int difference) {
		if(b == null || (b.isTransparent() && a != b) || b.mode.checkTransparency(data, difference)) {
			return true;
		}
		return false;
	}
	
	public boolean getsBlocked(Block b, Block a, byte data, int difference) {
		//return !blocksLight(a, b, data, difference);
		return a != null && !(b == null || (b.isTransparent() && b != a) || b.mode.checkTransparency(data, difference));
	}
	
	public void hideBlock(int x, int y, int z) {
		// Search for the BlockInstance in visibles:
		BlockInstance res = inst[(x << 4) | (y << 8) | z];
		if(res == null) return;
		visibles.remove(res);
		inst[(x << 4) | (y << 8) | z] = null;
		if (surface != null) {
			for (BlockVisibilityChangeHandler handler : surface.visibHandlers) {
				if (res != null) handler.onBlockHide(res.getBlock(), res.getX(), res.getY(), res.getZ());
			}
		}
	}
	
	public synchronized void revealBlock(int x, int y, int z) {
		// Make some sanity check for y coordinate:
		if(y < 0 || y >= World.WORLD_HEIGHT) return;
		int index = (x << 4) | (y << 8) | z;
		Block b = blocks[index];
		BlockInstance bi = new BlockInstance(b, blockData[index], new Vector3i(x + wx, y, z + wz), surface.getStellarTorus().getWorld().getLocalPlayer());
		byte[] data = new byte[6];
		int[] indices = new int[6];
		Block[] neighbors = getNeighbors(x, y ,z, data, indices);
		for(int k = 0; k < 6; k++) {
			if(neighbors[k] != null) bi.updateNeighbor(k, getsBlocked(neighbors[k], b, data[k], index - indices[k]), surface.getStellarTorus().getWorld().getLocalPlayer());
		}
		bi.setStellarTorus(surface);
		visibles.add(bi);
		inst[(x << 4) | (y << 8) | z] = bi;
		if (surface != null) {
			for (BlockVisibilityChangeHandler handler : surface.visibHandlers) {
				if (bi != null) handler.onBlockAppear(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
			}
		}
	}
	
	public void removeBlockAt(int x, int y, int z, boolean registerBlockChange) {
		Block block = getBlockAt(x, y, z);
		if(block == null)
			return;
		hideBlock(x & 15, y, z & 15);
		if (block.getBlockClass() == BlockClass.FLUID) {
			liquids.remove((Object) (((x & 15) << 4) | (y << 8) | (z & 15)));
		}
		if (block.hasBlockEntity()) {
			//blockEntities.remove(block);
			// TODO : be more efficient (maybe have a reference to block entity in BlockInstance?, but it would have yet another big memory footprint)
			for (BlockEntity be : blockEntities) {
				Vector3i pos = be.getPosition();
				if (pos.x == wx+x && pos.y == y && pos.z == wz+z) {
					blockEntities.remove(be);
					break;
				}
			}
		}
		setBlock(x, y, z, null, (byte)0);
		BlockInstance[] visibleNeighbors = getVisibleNeighbors(x, y, z);
		for(int k = 0; k < 6; k++) {
			if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, false, surface.getStellarTorus().getWorld().getLocalPlayer());
		}
		if(loaded)
			lightUpdate(x, y, z);
		Block[] neighbors = getNeighbors(x, y, z);
		for (int i = 0; i < neighbors.length; i++) {
			Block neighbor = neighbors[i];
			if (neighbor != null) {
				int nx = x+neighborRelativeX[i]+wx;
				int ny = y+neighborRelativeY[i];
				int nz = z+neighborRelativeZ[i]+wz;
				NormalChunk ch = getChunk(nx, nz);
				// Check if the block is structurally depending on the removed block:
				if(neighbor.mode.dependsOnNeightbors()) {
					byte oldData = ch.getBlockData(nx & 15, ny, nz & 15);
					Byte newData = neighbor.mode.updateData(oldData, i ^ 1);
					if(newData == null) {
						surface.removeBlock(nx, ny, nz);
						break; // Break here to prevent making a non-existent block visible.
					} else if(newData.byteValue() != oldData) {
						surface.updateBlockData(nx, ny, nz, newData);
						// TODO: Eventual item drops.
					}
				}
				if (!ch.contains(nx, ny, nz)) {
					ch.revealBlock((x+neighborRelativeX[i]) & 15, y+neighborRelativeY[i], (z+neighborRelativeZ[i]) & 15);
				}
				if (neighbor.getBlockClass() == BlockClass.FLUID) {
					int index = (((x+neighborRelativeX[i]) & 15) << 4) | ((y+neighborRelativeY[i]) << 8) | ((z+neighborRelativeZ[i]) & 15);
					if (!updatingLiquids.contains(index))
						updatingLiquids.add(index);
				}
			}
		}
		byte oldData = getBlockData(x, y, z);
		setBlock(x, y, z, null, (byte)0); // TODO: Investigate why this is called twice.

		if(registerBlockChange) {
			// Registers blockChange:
			int index = -1; // Checks if it is already in the list
			for(int i = 0; i < changes.size(); i++) {
				BlockChange bc = changes.get(i);
				if(bc.x == x && bc.y == y && bc.z == z) {
					index = i;
					break;
				}
			}
			if(index == -1) { // Creates a new object if the block wasn't changed before
				changes.add(new BlockChange(block.ID, -1, x, y, z, oldData, (byte)0));
				return;
			}
			if(changes.get(index).oldType == -1) { // Removes the object if the block reverted to it's original state(air).
				changes.remove(index);
				return;
			}
			changes.get(index).newType = -1;
		}
	}
	
	public boolean contains(int x, int y, int z) {
		return inst[((x & 15) << 4) | (y << 8) | (z & 15)] != null;
	}
	
	/**
	 * Feed an empty block palette and it will be filled with all block types. 
	 * @param blockPalette
	 * @return chunk data as byte[]
	 */
	public byte[] save(Map<Block, Integer> blockPalette) {
		byte[] data = new byte[12 + (changes.size()*17)];
		Bits.putInt(data, 0, cx);
		Bits.putInt(data, 4, cz);
		Bits.putInt(data, 8, changes.size());
		for(int i = 0; i < changes.size(); i++) {
			changes.get(i).save(data, 12 + i*17, blockPalette);
		}
		return data;
	}
	
	public int[] getData() {
		int[] data = new int[2];
		data[0] = cx;
		data[1] = cz;
		return data;
	}
	// This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	public NormalChunk getChunk(int x, int z) {
		x >>= 4;
		z >>= 4;
		if(cx != x || cz != z)
			return surface.getChunk(x, z);
		return this;
	}
	
	public int getLight(int x, int y, int z) {
		if(y < 0) return 0;
		if(y >= World.WORLD_HEIGHT) return 0xff000000;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + (x >> 4), cz + (z >> 4));
			if(chunk != null) return chunk.getLight(x & 15, y, z & 15);
			return -1;
		}
		return light[(x << 4) | (y << 8) | z];
		
	}
	
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
	
	public Block[] getNeighbors(int x, int y, int z) {
		Block[] neighbors = new Block[6];
		x &= 15;
		z &= 15;
		for(int i = 0; i < 6; i++) {
			int xi = x+neighborRelativeX[i];
			int yi = y+neighborRelativeY[i];
			int zi = z+neighborRelativeZ[i];
			if(yi == (yi&255)) { // Simple double-bound test for y.
				if(xi == (xi & 15) && zi == (zi & 15)) { // Simple double-bound test for x and z.
					neighbors[i] = getBlockAt(xi, yi, zi);
				} else {
					NormalChunk ch = surface.getChunk((xi >> 4) + cx, (zi >> 4) +cz);
					if(ch != null)
						neighbors[i] = ch.getBlockAt(xi & 15, yi, zi & 15);
				}
			}
		}
		return neighbors;
	}
	
	public Block[] getNeighbors(int x, int y, int z, byte[] data, int[] indices) {
		Block[] neighbors = new Block[6];
		x &= 15;
		z &= 15;
		for(int i = 0; i < 6; i++) {
			int xi = x+neighborRelativeX[i];
			int yi = y+neighborRelativeY[i];
			int zi = z+neighborRelativeZ[i];
			if(yi == (yi&255)) { // Simple double-bound test for y.
				if(xi == (xi & 15) && zi == (zi & 15)) { // Simple double-bound test for x and z.
					neighbors[i] = getBlockAt(xi, yi, zi);
				} else {
					NormalChunk ch = surface.getChunk((xi >> 4) + cx, (zi >> 4) +cz);
					if(ch != null && y <= World.WORLD_HEIGHT-1) {
						int index = ((xi & 15) << 4) | (yi << 8) | (zi & 15);
						neighbors[i] = ch.getBlockAt(xi & 15, yi, zi & 15);
						data[i] = ch.blockData[index];
						indices[i] = index;
					}
				}
			}
		}
		return neighbors;
	}
	
	public BlockInstance[] getVisibleNeighbors(int x, int y, int z) { // returns the corresponding BlockInstance for all visible neighbors of this block.
		BlockInstance[] inst = new BlockInstance[6];
		for(int i = 0; i < 6; i++) {
			inst[i] = getVisibleUnbound(x+neighborRelativeX[i], y+neighborRelativeY[i], z+neighborRelativeZ[i]);
		}
		return inst;
	}
	
	public Block getNeighbor(int i, int x, int y, int z) {
		int xi = x+neighborRelativeX[i];
		int yi = y+neighborRelativeY[i];
		int zi = z+neighborRelativeZ[i];
		if(yi == (yi&255)) { // Simple double-bound test for y.
			if(xi == (xi & 15) && zi == (zi & 15)) { // Simple double-bound test for x and z.
				return getBlockAt(xi, yi, zi);
			} else {
				return surface.getBlock(xi + wx, yi, zi + wz);
			}
		}
		return null;
	}
	
	public Block getBlockAt(int x, int y, int z) {
		if (y > World.WORLD_HEIGHT-1)
			return null;
		return blocks[(x << 4) | (y << 8) | z];
	}
	
	public Block getBlockAtIndex(int pos) {
		return blocks[pos];
	}
	
	public BlockInstance getBlockInstanceAt(int pos) {
		return inst[pos];
	}
	
	private Block getBlockUnboundAndUpdateLight(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) return chunk.getBlockUnboundAndUpdateLight(x & 15, y, z & 15);
			return noLight; // Let the lighting engine think this region is blocked.
		}
		if(inst[(x << 4) | (y << 8) | z] != null) {
			inst[(x << 4) | (y << 8) | z].scheduleLightUpdate();
		}
		return blocks[(x << 4) | (y << 8) | z];
	}
	
	private Block getBlockUnbound(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) return chunk.getBlockUnbound(x & 15, y, z & 15);
			return noLight; // Let the lighting engine think this region is blocked.
		}
		return blocks[(x << 4) | (y << 8) | z];
	}
	
	private void updateLight(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) chunk.updateLight(x & 15, y, z & 15);
			return;
		}
		if(inst[(x << 4) | (y << 8) | z] != null) {
			inst[(x << 4) | (y << 8) | z].scheduleLightUpdate();
		}
	}
	
	private BlockInstance getVisibleUnbound(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null) return chunk.getVisibleUnbound(x & 15, y, z & 15);
			return null;
		}
		return inst[(x << 4) | (y << 8) | z];
	}
	
	public Vector3f getMin(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(wx, x0, worldSizeX), 0, CubyzMath.match(wz, z0, worldSizeZ));
	}
	
	public Vector3f getMax(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(wx, x0, worldSizeX) + 16, 256, CubyzMath.match(wz, z0, worldSizeZ) + 16);
	}
	
	public int getX() {
		return cx;
	}
	
	public int getZ() {
		return cz;
	}
	
	public ArrayList<Integer> getLiquids() {
		return liquids;
	}
	
	public ArrayList<Integer> getUpdatingLiquids() {
		return updatingLiquids;
	}
	
	public FastList<BlockInstance> getVisibles() {
		return visibles;
	}
	
	public ArrayList<BlockEntity> getBlockEntities() {
		return blockEntities;
	}
	
	public boolean isGenerated() {
		return generated;
	}
	
	public boolean isLoaded() {
		return loaded;
	}
	
	public int startIndex(int start) {
		return start;
	}
	
	// Implementations of interface Chunk:
	
	public void updateBlockIfAir(int x, int y, int z, Block newBlock) {
		int index = (x << 4) | (y << 8) | z;
		if(blocks[index] == null) {
			if (newBlock != null && newBlock.getBlockClass() == BlockClass.FLUID) {
				liquids.add(index);
			}
			blocks[index] = newBlock;
			blockData[index] = newBlock == null ? 0 : newBlock.mode.getNaturalStandard();
		}
	}
	
	public void updateBlock(int x, int y, int z, Block newBlock) {
		updateBlock(x, y, z, newBlock, newBlock == null ? 0 : newBlock.mode.getNaturalStandard());
	}

	@Override
	public void updateBlock(int x, int y, int z, Block newBlock, byte data) {
		int index = (x << 4) | (y << 8) | z;
		if (newBlock != null && newBlock.getBlockClass() == BlockClass.FLUID) {
			liquids.add(index);
		}
		blocks[index] = newBlock;
		blockData[index] = data;
	}

	@Override
	public boolean liesInChunk(int x, int z) {
		return x >= 0 && x < 16 && z >= 0 && z < 16;
	}

	@Override
	public boolean liesInChunk(int y) {
		return y >= 0 && y < World.WORLD_HEIGHT;
	}

	@Override
	public int getVoxelSize() {
		return 1;
	}

	@Override
	public int getWorldX() {
		return wx;
	}

	@Override
	public int getWorldZ() {
		return wz;
	}
	
	@Override
	public int getWidth() {
		return 16;
	}
}
