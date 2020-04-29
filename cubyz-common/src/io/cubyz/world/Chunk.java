 package io.cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.Settings;
import io.cubyz.base.init.BlockInit;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.entity.Player;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.math.Bits;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;
import io.cubyz.util.FastList;
import io.cubyz.world.generator.SurfaceGenerator;

public class Chunk {
	// used for easy for-loop access of neighbors and their relative direction:
	private static final int[] neighborRelativeX = {-1, 1, 0, 0, 0, 0};
	private static final int[] neighborRelativeY = {0, 0, 0, 0, -1, 1};
	private static final int[] neighborRelativeZ = {0, 0, -1, 1, 0, 0};
	// Due to having powers of 2 as dimensions it is more efficient to use a one-dimensional array.
	private Block[] blocks;
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
	private Map<BlockInstance, BlockEntity> blockEntities = new HashMap<>();
	
	private Surface surface;
	
	public Chunk(int ox, int oz, Surface surface, ArrayList<BlockChange> changes) {
		if(surface != null) {
			ox &= surface.getAnd() >>> 4;
			oz &= surface.getAnd() >>> 4;
		}
		if(Settings.easyLighting) {
			light = new int[16*World.WORLD_HEIGHT*16];
		}
		inst = new BlockInstance[16*World.WORLD_HEIGHT*16];
		blocks = new Block[16*World.WORLD_HEIGHT*16];
		this.cx = ox;
		this.cz = oz;
		wx = ox << 4;
		wz = oz << 4;
		this.surface = surface;
		this.changes = changes;
	}
	
	// Functions calls are faster than two pointer references, which would happen when using a 3D-array, and functions can additionally be inlined by the VM.
	private void setInst(int x, int y, int z, Block b) {
		blocks[(x << 4) | (y << 8) | z] = b;
	}
	public Block getBlockAt(int x, int y, int z) {
		if (y > World.WORLD_HEIGHT-1)
			return null;
		return blocks[(x << 4) | (y << 8) | z];
	}
	private Block getBlockUnbound(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			Chunk chunk = surface._getNoGenerateChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null) return chunk.getBlockUnbound(x & 15, y, z & 15);
			return BlockInit.dirt; // Let the lighting engine think this region is blocked.
		}
		return blocks[(x << 4) | (y << 8) | z];
	}
	private BlockInstance getVisibleAbsoluteUnbound(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		int rx = x - wx;
		int rz = z - wz;
		if(rx < 0 || rx > 15 || rz < 0 || rz > 15) {
			Chunk chunk = surface._getNoGenerateChunk((x & ~15) >> 4, (z & ~15) >> 4);
			if(chunk != null) return chunk.getVisibleAbsoluteUnbound(x, y, z);
			return null;
		}
		return inst[(rx << 4) | (y << 8) | rz];
	}
	
	/**
	 * Internal "hack" method used for the overlay, DO NOT USE!
	 */
	@Deprecated
	public void createBlocksForOverlay() {
		blocks = new Block[16*256*16];
	}
	
	public void setLoaded(boolean loaded) {
		this.loaded = loaded;
	}
	
	public boolean isLoaded() {
		return loaded;
	}
	
	public int getX() {
		return cx;
	}
	
	public int getZ() {
		return cz;
	}
	
	public ArrayList<Integer> liquids() {
		return liquids;
	}
	
	public ArrayList<Integer> updatingLiquids() {
		return updatingLiquids;
	}
	
	public FastList<BlockInstance> getVisibles() {
		return visibles;
	}
	
	public Map<BlockInstance, BlockEntity> blockEntities() {
		return blockEntities;
	}
	// Performs a light update in all channels on this block.
	private void lightUpdate(int x, int y, int z) {
		ArrayList<int[]> updates = new ArrayList<>();
		// Sun:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 24, 0x00ffffff);
					int[] arr = new int[]{x, y, z, newLight};
					updates.add(arr);
				}
			}
		}
		lightUpdate(updates, 24, 0x00ffffff);
		// Red:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 16, 0xff00ffff);
					int[] arr = new int[]{x, y, z, newLight};
					updates.add(arr);
				}
			}
		}
		lightUpdate(updates, 16, 0xff00ffff);
		// Green:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 8, 0xffff00ff);
					int[] arr = new int[]{x, y, z, newLight};
					updates.add(arr);
				}
			}
		}
		lightUpdate(updates, 8, 0xffff00ff);
		// Blue:
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					int newLight = localLightUpdate(x+dx, y+dy, z+dz, 0, 0xffffff00);
					int[] arr = new int[]{x, y, z, newLight};
					updates.add(arr);
				}
			}
		}
		lightUpdate(updates, 0, 0xffffff00);
	}
	// Update only 1 corner:
	private void singleLightUpdate(int x, int y, int z) {
		ArrayList<int[]> updates = new ArrayList<>();
		// Sun:
		int newLight = localLightUpdate(x, y, z, 24, 0x00ffffff);
		int[] arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 24, 0x00ffffff);
		// Red:
		newLight = localLightUpdate(x, y, z, 16, 0xff00ffff);
		arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 16, 0xff00ffff);
		// Green:
		newLight = localLightUpdate(x, y, z, 8, 0xffff00ff);
		arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 8, 0xffff00ff);
		// Blue:
		newLight = localLightUpdate(x, y, z, 0, 0xffffff00);
		arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 0, 0xffffff00);
	}
	private int applyNeighbors(int light, int shift, Block n1, Block n2, Block n3, Block n4) {
		light = (light >>> shift) & 255;
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
		// Check if one of the blocks is glowing bright enough to support more light:
		if(n1 != null) {
			light = Math.max(light, (n1.getAbsorption() >>> shift) & 255);
		}
		if(n2 != null) {
			light = Math.max(light, (n2.getAbsorption() >>> shift) & 255);
		}
		if(n3 != null) {
			light = Math.max(light, (n3.getAbsorption() >>> shift) & 255);
		}
		if(n4 != null) {
			light = Math.max(light, (n4.getAbsorption() >>> shift) & 255);
		}
		return light;
	}
	private int localLightUpdate(int x, int y, int z, int shift, int mask) {
		// Make some bound checks:
		if(!Settings.easyLighting || y < 0 || y >= World.WORLD_HEIGHT || !generated) return -1;
		// Check if it's inside this chunk:
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			Chunk chunk = surface._getNoGenerateChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
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
			Chunk chunk = surface._getNoGenerateChunk(cx-1, cz);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index | 0xf0], shift, neighbors[0], neighbors[1], neighbors[2], neighbors[3]));
			}
		}
		if(x != 15) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index+16], shift, neighbors[4], neighbors[5], neighbors[6], neighbors[7]));
		} else {
			Chunk chunk = surface._getNoGenerateChunk(cx+1, cz);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index & ~0xf0], shift, neighbors[4], neighbors[5], neighbors[6], neighbors[7]));
			}
		}
		if(z != 0) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index-1], shift, neighbors[0], neighbors[2], neighbors[4], neighbors[6]));
		} else {
			Chunk chunk = surface._getNoGenerateChunk(cx, cz-1);
			if(chunk != null && chunk.isLoaded()) {
				maxLight = Math.max(maxLight, applyNeighbors(chunk.light[index | 0xf], shift, neighbors[0], neighbors[2], neighbors[4], neighbors[6]));
			}
		}
		if(z != 15) {
			maxLight = Math.max(maxLight, applyNeighbors(light[index+1], shift, neighbors[1], neighbors[3], neighbors[5], neighbors[7]));
		} else {
			Chunk chunk = surface._getNoGenerateChunk(cx, cz+1);
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
		if(curLight != maxLight) {
			light[index] = (light[index] & mask) | (maxLight << shift);
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
	 * Add the <code>Block</code> b at relative space defined by X, Y, and Z, and if out of bounds, call this method from the other chunk (only work for 1 chunk radius)<br/>
	 * Meaning that if x or z are out of bounds, this method will call the same method from other chunks to add it.
	 * @param b
	 * @param x
	 * @param y
	 * @param z
	 */
	public void addBlockPossiblyOutside(Block b, int x, int y, int z) {
		// Make the boundary checks:
		if (b == null) return;
		if(y >= World.WORLD_HEIGHT)
			return;
		int rx = x - wx;
		int rz = z - wz;
		if(rx < 0 || rx > 15 || rz < 0 || rz > 15) {
			surface._getNoGenerateChunk(cx + ((rx & ~15) >> 4), cz + ((rz & ~15) >> 4)).addBlock(b, x & 15, y, z & 15);
			return;
		} else {
			addBlock(b, x & 15, y, z & 15);
		}
	}
	
	public void addBlock(Block b, int x, int y, int z) {
		// Checks if there is a block on that position and deposits it if degradable.
		Block b2 = getBlockAt(x, y, z);
		if(b2 != null) {
			if(!b2.isDegradable() || b.isDegradable()) {
				return;
			}
			removeBlockAt(x, y, z, false);
		}
		if(b.hasBlockEntity() || b.getBlockClass() == BlockClass.FLUID) {
			BlockInstance inst0 = new BlockInstance(b);
			inst0.setPosition(new Vector3i(x + wx, y, z + wz));
			inst0.setStellarTorus(surface);
			if (b.hasBlockEntity()) {
				BlockEntity te = b.createBlockEntity(inst0.getPosition());
				blockEntities.put(inst0, te);
			}
			if (b.getBlockClass() == BlockClass.FLUID) {
				liquids.add((x << 4) | (y << 8) | z);
				updatingLiquids.add((x << 4) | (y << 8) | z);
			}
		}
		setInst(x, y, z, b);
		if(generated) {
			Block[] neighbors = getNeighbors(x, y, z);
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksLight(neighbors[i], b.isTransparent())) {
					revealBlock(x&15, y, z&15);
					break;
				}
			}
			BlockInstance[] visibleNeighbors = getVisibleNeighbors(x + wx, y, z + wz);
			if(visibleNeighbors[0] != null) visibleNeighbors[0].neighborWest = getsBlocked(neighbors[0], b.isTransparent());
			if(visibleNeighbors[1] != null) visibleNeighbors[1].neighborEast = getsBlocked(neighbors[1], b.isTransparent());
			if(visibleNeighbors[2] != null) visibleNeighbors[2].neighborNorth = getsBlocked(neighbors[2], b.isTransparent());
			if(visibleNeighbors[3] != null) visibleNeighbors[3].neighborSouth = getsBlocked(neighbors[3], b.isTransparent());
			if(visibleNeighbors[4] != null) visibleNeighbors[4].neighborUp = getsBlocked(neighbors[4], b.isTransparent());
			if(visibleNeighbors[5] != null) visibleNeighbors[5].neighborDown = getsBlocked(neighbors[5], b.isTransparent());
			for (int i = 0; i < neighbors.length; i++) {
				if(neighbors[i] != null) {
					int x2 = x+neighborRelativeX[i];
					int y2 = y+neighborRelativeY[i];
					int z2 = z+neighborRelativeZ[i];
					Chunk ch = getChunk(x2 + wx, z2 + wz);
					if (ch.contains(x2 & 15, y2, z2 & 15)) {
						Block[] neighbors1 = ch.getNeighbors(x2 & 15, y2, z2 & 15);
						boolean vis = true;
						for (int j = 0; j < neighbors1.length; j++) {
							if (blocksLight(neighbors1[j], neighbors[i].isTransparent())) {
								vis = false;
								break;
							}
						}
						if(vis) {
							ch.hideBlock(x2 & 15, y2, z2 & 15);
						}
					}
				}
			}
		}
		if(loaded)
			lightUpdate(x, y, z);
	}
	
	public void generateFrom(SurfaceGenerator gen) {
		gen.generate(this, surface);
		generated = true;
	}
	
	// Apply Block Changes loaded from file/stored in WorldIO
	public void applyBlockChanges() {
		for(BlockChange bc : changes) {
			if(bc.newType == -1) {
				removeBlockAt(bc.x, bc.y, bc.z, false);
				continue;
			}
			Block bl = surface.getPlanetBlocks()[bc.newType];
			if(getBlockAt(bc.x, bc.y, bc.z) == null) {
				addBlockAt(bc.x, bc.y, bc.z, bl, false);
				bc.oldType = -1;
				continue;
			}
			bc.oldType = getBlockAt(bc.x, bc.y, bc.z).ID;
			setInst(bc.x, bc.y, bc.z, bl);
		}
	}
	
	public void clear() { // Clears the data structures which are used for visible blocks.
		visibles.clear();
		inst = new BlockInstance[16*256*16]; // TODO: Fill it with nulls instead of reallocating it.
	}
	
	// Loads the chunk
	public void load() {
		// Empty the list, so blocks won't get added twice. This will also be important, when there is a manual chunk reloading.
		clear();
		
		loaded = true;
		Chunk [] chunks = new Chunk[4];
		Chunk ch = surface._getNoGenerateChunk(cx - 1, cz);
		chunks[0] = ch;
		boolean chx0 = ch != null && ch.isGenerated();
		ch = surface._getNoGenerateChunk(cx + 1, cz);
		chunks[1] = ch;
		boolean chx1 = ch != null && ch.isGenerated();
		ch = surface._getNoGenerateChunk(cx, cz - 1);
		chunks[2] = ch;
		boolean chz0 = ch != null && ch.isGenerated();
		ch = surface._getNoGenerateChunk(cx, cz + 1);
		boolean chz1 = ch != null && ch.isGenerated();
		chunks[3] = ch;
		int maxHeight = 255; // The biggest height that supports blocks.
		// Use lighting calculations that are done anyways if easyLighting is enabled to determine the maximum height inside this chunk.
		ArrayList<int[]> lightUpdates = null;
		ArrayList<Integer> lightSources = null;
		if(Settings.easyLighting) {
			lightUpdates = new ArrayList<>();
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
		// Sadly the new system doesn't allow for easy access on the BlockInstances through a list, so we have to go through all blocks(which probably is even more efficient because about half of the blocks are non-air).
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y <= maxHeight; y++) {
				for(int  z = 0; z < 16; z++) {
					Block b = getBlockAt(x, y, z);
					if(b != null) {
						Block[] neighbors = getNeighbors(x, y, z);
						BlockInstance[] visibleNeighbors = getVisibleNeighbors(x + wx, y, z + wz);
						if(visibleNeighbors[0] != null) visibleNeighbors[0].neighborWest = getsBlocked(neighbors[0], b.isTransparent());
						if(visibleNeighbors[1] != null) visibleNeighbors[1].neighborEast = getsBlocked(neighbors[1], b.isTransparent());
						if(visibleNeighbors[2] != null) visibleNeighbors[2].neighborNorth = getsBlocked(neighbors[2], b.isTransparent());
						if(visibleNeighbors[3] != null) visibleNeighbors[3].neighborSouth = getsBlocked(neighbors[3], b.isTransparent());
						if(visibleNeighbors[4] != null) visibleNeighbors[4].neighborUp = getsBlocked(neighbors[4], b.isTransparent());
						if(visibleNeighbors[5] != null) visibleNeighbors[5].neighborDown = getsBlocked(neighbors[5], b.isTransparent());
						for (int i = 0; i < neighbors.length; i++) {
							if (blocksLight(neighbors[i], b.isTransparent())
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
							lightSources.add((x << 4) | (y << 8) | z);
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
						Block inst0 = ch.getBlockAt(dx[k], j, dz[k]);
						if(inst0 == null) {
							continue;
						}
						if(ch.contains(dx[k] + wx, j, dz[k] + wz)) {
							continue;
						}
						if (blocksLight(getBlockAt(invdx[k], j, invdz[k]), inst0.isTransparent())) {
							ch.revealBlock(dx[k], j, dz[k]);
							continue;
						}
					}
				}
			}
		}
		// Do some light updates.
		if(Settings.easyLighting) {
			// Add the lowest layer to the updates list:
			for(int x = 0; x < 16; x++) {
				for(int z = 0; z < 16; z++) {
					if(getBlockAt(x, maxHeight, z) == null)
						lightUpdates.add(new int[] {x, maxHeight, z, 255});
				}
			}
			lightUpdate(lightUpdates, 24, 0x00ffffff);
			// Look at the neighboring chunks. Update only the outer corners:
			boolean no = surface._getNoGenerateChunk(cx-1, cz) != null;
			boolean po = surface._getNoGenerateChunk(cx+1, cz) != null;
			boolean on = surface._getNoGenerateChunk(cx, cz-1) != null;
			boolean op = surface._getNoGenerateChunk(cx, cz+1) != null;
			if(no || on) {
				int x = 0, z = 0;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(no || op) {
				int x = 0, z = 15;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(po || on) {
				int x = 15, z = 0;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(po || op) {
				int x = 15, z = 15;
				for(int y = 0; y < maxHeight; y++) {
					singleLightUpdate(x, y, z);
				}
			}
			if(no) {
				int x = 0;
				for(int z = 1; z < 15; z++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
			}
			if(po) {
				int x = 15;
				for(int z = 1; z < 15; z++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
			}
			if(on) {
				int z = 0;
				for(int x = 1; x < 15; x++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
			}
			if(op) {
				int z = 15;
				for(int x = 1; x < 15; x++) {
					for(int y = 0; y < maxHeight; y++) {
						singleLightUpdate(x, y, z);
					}
				}
			}
			// Take care about light sources:
			for(int index : lightSources) {
				lightUpdate((index >>> 4) & 15, (index >>> 8) & 255, index & 15);
			}
		}
	}
	
	public boolean blocksLight(Block b, boolean transparent) {
		if(b == null || (b.isTransparent() && !transparent)) {
			return true;
		}
		return false;
	}
	
	public boolean getsBlocked(Block b, boolean transparent) {
		return b == null || !(!b.isTransparent() && transparent);
	}
	
	public boolean getsBlocked(Block b, Block a) {
		return a != null && !(b == null || (b.isTransparent() && b != a));
	}
	
	public boolean isGenerated() {
		return generated;
	}
	
	// This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	public Chunk getChunk(int x, int z) {
		x >>= 4;
		z >>= 4;
		if(cx != x || cz != z)
			return surface._getNoGenerateChunk(x, z);
		return this;
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
		Block b = getBlockAt(x, y, z);
		BlockInstance bi = new BlockInstance(b);
		Block[] neighbors = getNeighbors(x, y ,z);
		if(neighbors[0] != null) bi.neighborEast = getsBlocked(neighbors[0], bi.getBlock());
		if(neighbors[1] != null) bi.neighborWest = getsBlocked(neighbors[1], bi.getBlock());
		if(neighbors[2] != null) bi.neighborSouth = getsBlocked(neighbors[2], bi.getBlock());
		if(neighbors[3] != null) bi.neighborNorth = getsBlocked(neighbors[3], bi.getBlock());
		if(neighbors[4] != null) bi.neighborDown = getsBlocked(neighbors[4], bi.getBlock());
		if(neighbors[5] != null) bi.neighborUp = getsBlocked(neighbors[5], bi.getBlock());
		bi.setPosition(new Vector3i(x + wx, y, z + wz));
		bi.setStellarTorus(surface);
		visibles.add(bi);
		inst[(x << 4) | (y << 8) | z] = bi;
		if (surface != null) {
			for (BlockVisibilityChangeHandler handler : surface.visibHandlers) {
				if (bi != null) handler.onBlockAppear(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
			}
		}
	}
	
	public boolean contains(int x, int y, int z) {
		return inst[((x & 15) << 4) | (y << 8) | (z & 15)] != null;
	}
	
	public void removeBlockAt(int x, int y, int z, boolean registerBlockChange) {
		Block bi = getBlockAt(x, y, z);
		if(bi == null)
			return;
		hideBlock(x & 15, y, z & 15);
		if (bi.getBlockClass() == BlockClass.FLUID) {
			liquids.remove(((x & 15) << 4) | (y << 8) | (z & 15));
		}
		if (bi.hasBlockEntity()) {
			blockEntities.remove(bi);
		}
		setInst(x, y, z, null);
		BlockInstance[] visibleNeighbors = getVisibleNeighbors(x, y, z);
		if(visibleNeighbors[0] != null) visibleNeighbors[0].neighborWest = false;
		if(visibleNeighbors[1] != null) visibleNeighbors[1].neighborEast = false;
		if(visibleNeighbors[2] != null) visibleNeighbors[2].neighborNorth = false;
		if(visibleNeighbors[3] != null) visibleNeighbors[3].neighborSouth = false;
		if(visibleNeighbors[4] != null) visibleNeighbors[4].neighborUp = false;
		if(visibleNeighbors[5] != null) visibleNeighbors[5].neighborDown = false;
		if(loaded)
			lightUpdate(x, y, z);
		Block[] neighbors = getNeighbors(x, y, z);
		for (int i = 0; i < neighbors.length; i++) {
			Block inst = neighbors[i];
			if (inst != null) {
				Chunk ch = getChunk(x+neighborRelativeX[i]+wx, z+neighborRelativeZ[i]+wz);
				if (!ch.contains(x+neighborRelativeX[i]+wx, y+neighborRelativeY[i], z+neighborRelativeZ[i]+wz)) {
					ch.revealBlock((x+neighborRelativeX[i]) & 15, y+neighborRelativeY[i], (z+neighborRelativeZ[i]) & 15);
				}
				if (inst.getBlockClass() == BlockClass.FLUID) {
					int index = (((x+neighborRelativeX[i]) & 15) << 4) | ((y+neighborRelativeY[i]) << 8) | ((z+neighborRelativeZ[i]) & 15);
					if (!updatingLiquids.contains(index))
						updatingLiquids.add(index);
				}
			}
		}
		setInst(x, y, z, null);

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
				changes.add(new BlockChange(bi.ID, -1, x, y, z));
				return;
			}
			if(-1 == changes.get(index).oldType) { // Removes the object if the block reverted to it's original state.
				changes.remove(index);
				return;
			}
			changes.get(index).newType = -1;
		}
	}
	
	/**
	 * Raw add block. Doesn't do any checks. To use with WorldGenerators
	 * @param x
	 * @param y
	 * @param z
	 */
	public void rawAddBlock(int x, int y, int z, Block bi) {
		if (bi  == null) {
			setInst(x, y, z, null);
			return;
		}
		if (bi != null) {
			if (bi.getBlockClass() == BlockClass.FLUID) {
				liquids.add((x << 4) | (y << 8) | z);
			}
		}
		setInst(x, y, z, bi);
	}
	
	public void addBlockAt(int x, int y, int z, Block b, boolean registerBlockChange) {
		if(y >= World.WORLD_HEIGHT)
			return;
		removeBlockAt(x, y, z, false);
		//if (b.hasBlockEntity()) { TODO: Block entities.
		//	BlockEntity te = b.createBlockEntity(inst0.getPosition());
		//	blockEntities.put(inst0, te);
		//}
		if (b.getBlockClass() == BlockClass.FLUID) {
			liquids.add((x << 4) | (y << 8) | z);
			updatingLiquids.add((x << 4) | (y << 8) | z);
		}
		setInst(x, y, z, b);
		Block[] neighbors = getNeighbors(x+wx, y, z+wz);
		BlockInstance[] visibleNeighbors = getVisibleNeighbors(x+wx, y, z+wz);
		if(visibleNeighbors[0] != null) visibleNeighbors[0].neighborWest = getsBlocked(neighbors[0], b.isTransparent());
		if(visibleNeighbors[1] != null) visibleNeighbors[1].neighborEast = getsBlocked(neighbors[1], b.isTransparent());
		if(visibleNeighbors[2] != null) visibleNeighbors[2].neighborNorth = getsBlocked(neighbors[2], b.isTransparent());
		if(visibleNeighbors[3] != null) visibleNeighbors[3].neighborSouth = getsBlocked(neighbors[3], b.isTransparent());
		if(visibleNeighbors[4] != null) visibleNeighbors[4].neighborUp = getsBlocked(neighbors[4], b.isTransparent());
		if(visibleNeighbors[5] != null) visibleNeighbors[5].neighborDown = getsBlocked(neighbors[5], b.isTransparent());
		
		for (int i = 0; i < neighbors.length; i++) {
			if (blocksLight(neighbors[i], b.isTransparent())) {
				revealBlock(x, y, z);
				break;
			}
		}
		
		for (int i = 0; i < neighbors.length; i++) {
			int rx = x+neighborRelativeX[i];
			int ry = y+neighborRelativeY[i];
			int rz = z+neighborRelativeZ[i];
			if(neighbors[i] != null) {
				Chunk ch = getChunk(rx+wx, rz+wz);
				if (ch.contains(rx+wx, ry, rz+wz)) {
					Block[] neighbors1 = getNeighbors(rx, ry, rz);
					boolean vis = true;
					for (int j = 0; j < neighbors1.length; j++) {
						if (blocksLight(neighbors1[j], neighbors[i].isTransparent())) {
							vis = false;
							break;
						}
					}
					if(vis) {
						ch.hideBlock(rx & 15, ry, rz & 15);
					}
				}
				if (neighbors[i].getBlockClass() == BlockClass.FLUID) {
					int index = ((rx & 15) << 4) | (ry << 8) | (rz & 15);
					if (!updatingLiquids.contains(index))
						updatingLiquids.add(index);
				}
			}
		}

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
				changes.add(new BlockChange(-1, b.ID, x, y, z));
				return;
			}
			if(b.ID == changes.get(index).oldType) { // Removes the object if the block reverted to it's original state.
				changes.remove(index);
				return;
			}
			changes.get(index).newType = b.ID;
		}
		if(loaded)
			lightUpdate(x, y, z);
	}
	
	public Vector3f getMin(Player localPlayer, int worldAnd) {
		return new Vector3f(CubyzMath.matchSign((wx - localPlayer.getPosition().x) & worldAnd, worldAnd) - localPlayer.getPosition().relX, -localPlayer.getPosition().y, CubyzMath.matchSign((wz - localPlayer.getPosition().z) & worldAnd, worldAnd) - localPlayer.getPosition().relZ);
	}
	
	public Vector3f getMax(Player localPlayer, int worldAnd) {
		return new Vector3f(CubyzMath.matchSign((wx - localPlayer.getPosition().x + 16) & worldAnd, worldAnd) - localPlayer.getPosition().relX, 255-localPlayer.getPosition().y, CubyzMath.matchSign((wz - localPlayer.getPosition().z + 16) & worldAnd, worldAnd) - localPlayer.getPosition().relZ);
	}
	
	public byte[] save() {
		byte[] data = new byte[12 + (changes.size() << 4)];
		Bits.putInt(data, 0, cx);
		Bits.putInt(data, 4, cz);
		Bits.putInt(data, 8, changes.size());
		for(int i = 0; i < changes.size(); i++) {
			changes.get(i).save(data, 12 + (i << 4));
		}
		return data;
	}
	
	public int[] getData() {
		int[] data = new int[2];
		data[0] = cx;
		data[1] = cz;
		return data;
	}
	
	public int getLight(int x, int y, int z, Vector3f sunLight) {
		if(y < 0) return 0;
		if(y >= World.WORLD_HEIGHT) return 0xff000000;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			Chunk chunk = surface._getNoGenerateChunk(cx + (x >> 4), cz + (z >> 4));
			if(chunk != null) return chunk.getLight(x & 15, y, z & 15, sunLight);
			return -1;
		}
		return light[(x << 4) | (y << 8) | z];
		
	}
	
	public void getCornerLight(int x, int y, int z, Vector3f sunLight, int[] arr) {
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					arr[(dx << 2) | (dy << 1) | dz] = getLight(x+dx, y+dy, z+dz, sunLight);
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
		Block[] inst = new Block[6];
		x &= 15;
		z &= 15;
		// 0 = EAST  (x - 1)
		// 1 = WEST  (x + 1)
		// 2 = SOUTH (z - 1)
		// 3 = NORTH (z + 1)
		// 4 = DOWN
		// 5 = UP
		for(int i = 0; i < 6; i++) {
			int xi = x+neighborRelativeX[i];
			int yi = y+neighborRelativeY[i];
			int zi = z+neighborRelativeZ[i];
			if(yi == (yi&255)) { // Simple double-bound test for y.
				if(xi == (xi & 15) && zi == (zi & 15)) { // Simple double-bound test for x and z.
					inst[i] = getBlockAt(xi, yi, zi);
				} else {
					Chunk ch = surface._getNoGenerateChunk((xi >> 4) + cx, (zi >> 4) +cz);
					if(ch != null)
						inst[i] = ch.getBlockAt(xi & 15, yi, zi & 15);
				}
			}
		}
		return inst;
	}
	
	public BlockInstance[] getVisibleNeighbors(int x, int y, int z) { // returns the corresponding BlockInstance for all visible neighbors of this block.
		BlockInstance[] inst = new BlockInstance[6];
		for(int i = 0; i < 6; i++) {
			inst[i] = getVisibleAbsoluteUnbound(x+neighborRelativeX[i], y+neighborRelativeY[i], z+neighborRelativeZ[i]);
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
}
