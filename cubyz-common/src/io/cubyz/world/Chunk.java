 package io.cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.entity.Player;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.math.Bits;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;
import io.cubyz.world.generator.WorldGenerator;

// TODO: adapt the whole thing to work for toruses
public class Chunk {
	public static boolean easyLighting = true; // Enables the easy-lighting system.
	// Due to having powers of 2 as dimensions it is more efficient to use a one-dimensional array.
	private BlockInstance[] inst;
	private int[] light; // Stores sun r g b channels of each light channel in one integer. This makes it easier to store and to access.
	private ArrayList<BlockInstance> list = new ArrayList<>();
	private ArrayList<BlockInstance> liquids = new ArrayList<>();
	private ArrayList<BlockInstance> updatingLiquids = new ArrayList<>(); // liquids that should be updated at next frame
	private ArrayList<BlockChange> changes; // Reports block changes. Only those will be saved!
	//private ArrayList<BlockInstance> visibles = new ArrayList<>();
	private BlockInstance[] visibles = new BlockInstance[50]; // Using an array here to speed up the renderer.
	private int visiblesSize = 0;
	private int ox, oy;
	private boolean generated;
	private boolean loaded;
	private Map<BlockInstance, BlockEntity> blockEntities = new HashMap<>();
	
	private World world;
	
	public Chunk(int ox, int oy, World world, ArrayList<BlockChange> changes) {
		if(world != null) {
			ox &= world.getWorldAnd() >>> 4;
			oy &= world.getWorldAnd() >>> 4;
		}
		if(easyLighting) {
			light = new int[16*World.WORLD_HEIGHT*16];
		}
		this.ox = ox;
		this.oy = oy;
		this.world = world;
		this.changes = changes;
	}
	
	// Functions calls are faster than two pointer references, which would happen when using a 3D-array, and functions can additionally be inlined by the VM.
	private void setInst(int x, int y, int z, BlockInstance bi) {
		inst[(x << 4) | (y << 8) | z] = bi;
	}
	private BlockInstance getInst(int x, int y, int z) {
		return inst[(x << 4) | (y << 8) | z];
	}
	
	/**
	 * Internal "hack" method used for the overlay, DO NOT USE!
	 */
	@Deprecated
	public void createBlocksForOverlay() {
		inst = new BlockInstance[16*256*16];
	}
	
	public void setLoaded(boolean loaded) {
		this.loaded = loaded;
	}
	
	public boolean isLoaded() {
		return loaded;
	}
	
	public int getX() {
		return ox;
	}
	
	public int getZ() {
		return oy;
	}
	
	public ArrayList<BlockInstance> list() {
		return list;
	}
	
	public ArrayList<BlockInstance> liquids() {
		return liquids;
	}
	
	public ArrayList<BlockInstance> updatingLiquids() {
		return updatingLiquids;
	}
	
	public BlockInstance[] getVisibles() {
		return visibles;
	}
	
	public Map<BlockInstance, BlockEntity> blockEntities() {
		return blockEntities;
	}
	// Performs a light update in all channels on this block.
	private void lightUpdate(int x, int y, int z) {
		ArrayList<int[]> updates = new ArrayList<>();
		int newLight = localLightUpdate(x, y, z, 24, 0x00ffffff); // Sun
		int[] arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 24, 0x00ffffff);
		newLight = localLightUpdate(x, y, z, 16, 0xff00ffff); // Red
		arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 16, 0xff00ffff);
		newLight = localLightUpdate(x, y, z, 8, 0xffff00ff); // Green
		arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 8, 0xffff00ff);
		newLight = localLightUpdate(x, y, z, 0, 0xffffff00); // Blue
		arr = new int[]{x, y, z, newLight};
		updates.add(arr);
		lightUpdate(updates, 0, 0xffffff00);
	}
	private int localLightUpdate(int x, int y, int z, int shift, int mask) {
		// Make some bound checks:
		if(!easyLighting || y < 0 || y >= World.WORLD_HEIGHT || !generated) return 0;
		// Check if it's inside this chunk:
		if(x < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox-1, oy);
			if(chunk != null) return chunk.localLightUpdate(x+16, y, z, shift, mask);
			return 0;
		}
		if(x > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox+1, oy);
			if(chunk != null) return chunk.localLightUpdate(x-16, y, z, shift, mask);
			return 0;
		}
		if(z < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy-1);
			if(chunk != null) return chunk.localLightUpdate(x, y, z+16, shift, mask);
			return 0;
		}
		if(z > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy+1);
			if(chunk != null) return chunk.localLightUpdate(x, y, z-16, shift, mask);
			return 0;
		}
		// Check all neighbors and find their highest lighting in the specified channel:

		int index = (x << 4) | (y << 8) | z; // Works close to the datastructure. Allows for some optimizations.
		
		int maxLight = 8; // Make sure the light of a block never gets below 0.
		int neighbors = 0; // Count the neighbors for later.
		if(x != 0) {
			BlockInstance bi = inst[index-16];
			if(bi == null || bi.getBlock().isTransparent()) {
				maxLight = Math.max(maxLight, (light[index-16] >>> shift) & 255);
			} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
				maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			} else {
				neighbors++;
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox-1, oy);
			if(chunk != null && chunk.isLoaded()) {
				BlockInstance bi = chunk.getInst(15, y, z);
				if(bi == null || bi.getBlock().isTransparent()) {
					maxLight = Math.max(maxLight, (chunk.light[index | 0xf0] >>> shift) & 255);
				} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
					maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
				} else {
						neighbors++;
				}
			}
		}
		if(x != 15) {
			BlockInstance bi = inst[index+16];
			if(bi == null || bi.getBlock().isTransparent()) {
				maxLight = Math.max(maxLight, (light[index+16] >>> shift) & 255);
			} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
				maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			} else {
				neighbors++;
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox+1, oy);
			if(chunk != null && chunk.isLoaded()) {
				BlockInstance bi = chunk.getInst(0, y, z);
				if(bi == null || bi.getBlock().isTransparent()) {
					maxLight = Math.max(maxLight, (chunk.light[index & ~0xf0] >>> shift) & 255);
				} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
					maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
				} else {
					neighbors++;
				}
			}
		}
		if(z != 0) {
			BlockInstance bi = inst[index-1];
			if(bi == null || bi.getBlock().isTransparent()) {
				maxLight = Math.max(maxLight, (light[index-1] >>> shift) & 255);
			} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
				maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			} else {
				neighbors++;
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox, oy-1);
			if(chunk != null && chunk.isLoaded()) {
				BlockInstance bi = chunk.getInst(x, y, 15);
				if(bi == null || bi.getBlock().isTransparent()) {
					maxLight = Math.max(maxLight, (chunk.light[index | 0xf] >>> shift) & 255);
				} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
					maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
				} else {
					neighbors++;
				}
			}
		}
		if(z != 15) {
			BlockInstance bi = inst[index+1];
			if(bi == null || bi.getBlock().isTransparent()) {
				maxLight = Math.max(maxLight, (light[index+1] >>> shift) & 255);
			} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
				maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			} else {
				neighbors++;
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox, oy+1);
			if(chunk != null && chunk.isLoaded()) {
				BlockInstance bi = chunk.getInst(x, y, 0);
				if(bi == null || bi.getBlock().isTransparent()) {
					maxLight = Math.max(maxLight, (chunk.light[index & ~0xf] >>> shift) & 255);
				} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
					maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
				} else {
					neighbors++;
				}
			}
		}
		if(y != 0) {
			BlockInstance bi = inst[index-256];
			if(bi == null || bi.getBlock().isTransparent()) {
				maxLight = Math.max(maxLight, (light[index-256] >>> shift) & 255);
			} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
				maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			} else {
				neighbors++;
			}
		}
		if(y != 255) {
			BlockInstance bi = inst[index+256];
			if(bi == null || bi.getBlock().isTransparent()) {
				int local = (light[index+256] >>> shift) & 255;
				if(shift == 24) // Sunlight can freely go down. Even after being weakened by glass(TODO: Add glass) or other things.
					local += 8;
				maxLight = Math.max(maxLight, local);
			} else if(bi.getBlock().getLight() != 0) { // Take care of emmissions:
				maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			} else {
				neighbors++;
			}
		} else if(shift == 24) {
			maxLight = 263; // The top block gets always maximum lighting.
		}
		// Update the light and return.
		int curLight = (light[index] >>> shift) & 255;
		maxLight -= 8;
		maxLight -= neighbors; // Account for light getting absorbed by neighboring blocks.
		BlockInstance bi = inst[index];
		if(bi != null) {
			maxLight = Math.max(maxLight, (bi.getBlock().getLight() >>> shift) & 255);
			if(bi.getBlock().isTransparent()) {
				maxLight -= (bi.getBlock().getAbsorption() >>> shift) & 255; // Most transparent blocks will absorb a siquinificant portion of light.
			}
		}
		if(maxLight < 0) maxLight = 0;
		if(curLight != maxLight) {
			light[index] = (light[index] & mask) | (maxLight << shift);
			if(bi != null) {
				bi.light = light[index];
				return bi.getBlock().isTransparent() ? maxLight : 0; // Only do light updates through transparent blocks.
			}
			return maxLight;
		}
		return 0;
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
				if((light = localLightUpdate(x, y, z, shift, mask)) > 0) {
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
	public void addBlock(Block b, int x, int y, int z) {
		if (b == null) return;
		if(y >= World.WORLD_HEIGHT)
			return;
		int rx = x - (ox << 4);
		// Determines if the block is part of another chunk.
		if (rx < 0) {
			world._getChunk(ox - 1, oy).addBlock(b, x, y, z);
			return;
		}
		if (rx > 15) {
			world._getChunk(ox + 1, oy).addBlock(b, x, y, z);
			return;
		}
		int rz = z - (oy << 4);
		if (rz < 0) {
			world._getChunk(ox, oy - 1).addBlock(b, x, y, z);
			return;
		}
		if (rz > 15) {
			world._getChunk(ox, oy + 1).addBlock(b, x, y, z);
			return;
		}
		if(inst == null) {
			inst = new BlockInstance[16*World.WORLD_HEIGHT*16];
		} else { // Checks if there is a block on that position and deposits it if degradable.
			BlockInstance bi = getInst(rx, y, rz);
			if(bi != null) {
				if(!bi.getBlock().isDegradable() || b.isDegradable()) {
					return;
				}
				removeBlockAt(rx, y, rz, false);
			}
		}
		BlockInstance inst0 = new BlockInstance(b);
		inst0.setPosition(new Vector3i(x, y, z));
		inst0.setWorld(world);
		if (b.hasBlockEntity()) {
			BlockEntity te = b.createBlockEntity(inst0.getPosition());
			blockEntities.put(inst0, te);
		}
		if (b.getBlockClass() == BlockClass.FLUID) {
			liquids.add(inst0);
			updatingLiquids.add(inst0);
		}
		list.add(inst0);
		setInst(rx, y, rz, inst0);
		if(generated) {
			BlockInstance[] neighbors = inst0.getNeighbors(this);
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksLight(neighbors[i], inst0.getBlock().isTransparent())) {
					revealBlock(inst0);
					break;
				}
			}
			if(neighbors[0] != null) neighbors[0].neighborWest = getsBlocked(neighbors[0], inst0.getBlock().isTransparent());
			if(neighbors[1] != null) neighbors[1].neighborEast = getsBlocked(neighbors[1], inst0.getBlock().isTransparent());
			if(neighbors[2] != null) neighbors[2].neighborSouth = getsBlocked(neighbors[2], inst0.getBlock().isTransparent());
			if(neighbors[3] != null) neighbors[3].neighborNorth = getsBlocked(neighbors[3], inst0.getBlock().isTransparent());
			if(neighbors[4] != null) neighbors[4].neighborUp = getsBlocked(neighbors[4], inst0.getBlock().isTransparent());
			if(neighbors[5] != null) neighbors[5].neighborDown = getsBlocked(neighbors[5], inst0.getBlock().isTransparent());
			for (int i = 0; i < neighbors.length; i++) {
				if(neighbors[i] != null) {
					Chunk ch = getChunk(neighbors[i].getX(), neighbors[i].getZ());
					if (ch.contains(neighbors[i])) {
						BlockInstance[] neighbors1 = neighbors[i].getNeighbors(ch);
						boolean vis = true;
						for (int j = 0; j < neighbors1.length; j++) {
							if (blocksLight(neighbors1[j], neighbors[i].getBlock().isTransparent())) {
								vis = false;
								break;
							}
						}
						if(vis) {
							ch.hideBlock(neighbors[i]);
						}
					}
				}
			}
		}
		lightUpdate(rx, y, rz);
	}
	
	public void generateFrom(WorldGenerator gen) {
		if(inst == null) {
			inst = new BlockInstance[16*World.WORLD_HEIGHT*16];
		}
		gen.generate(this, world);
		generated = true;
	}
	
	// Apply Block Changes loaded from file/stored in WorldIO
	public void applyBlockChanges() {
		for(BlockChange bc : changes) {
			if(bc.newType == -1) {
				removeBlockAt(bc.x, bc.y, bc.z, false);
				continue;
			}
			Block bl = world.getBlocks()[bc.newType];
			if(getInst(bc.x, bc.y, bc.z) == null) {
				addBlockAt(bc.x, bc.y, bc.z, bl, false);
				bc.oldType = -1;
				continue;
			}
			bc.oldType = getInst(bc.x, bc.y, bc.z).getID();
			getInst(bc.x, bc.y, bc.z).setBlock(bl);
		}
	}
	
	// Loads the chunk
	public void load() {
		// Empty the list, so blocks won't get added twice. This will also be important, when there is a manual chunk reloading.
		visibles = new BlockInstance[10];
		visiblesSize = 0;
		
		loaded = true;
		boolean chx0 = world._getChunk(ox - 1, oy).isGenerated();
		boolean chx1 = world._getChunk(ox + 1, oy).isGenerated();
		boolean chy0 = world._getChunk(ox, oy - 1).isGenerated();
		boolean chy1 = world._getChunk(ox, oy + 1).isGenerated();
		for(int k = 0; k < list.size(); k++) {
			BlockInstance bi = list.get(k);
			BlockInstance[] neighbors = bi.getNeighbors(this);
			if(neighbors[0] != null) neighbors[0].neighborWest = getsBlocked(neighbors[0], bi.getBlock().isTransparent());
			if(neighbors[1] != null) neighbors[1].neighborEast = getsBlocked(neighbors[1], bi.getBlock().isTransparent());
			if(neighbors[2] != null) neighbors[2].neighborSouth = getsBlocked(neighbors[2], bi.getBlock().isTransparent());
			if(neighbors[3] != null) neighbors[3].neighborNorth = getsBlocked(neighbors[3], bi.getBlock().isTransparent());
			if(neighbors[4] != null) neighbors[4].neighborUp = getsBlocked(neighbors[4], bi.getBlock().isTransparent());
			if(neighbors[5] != null) neighbors[5].neighborDown = getsBlocked(neighbors[5], bi.getBlock().isTransparent());
			int j = bi.getY();
			int px = bi.getX()&15;
			int py = bi.getZ()&15;
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksLight(neighbors[i], bi.getBlock().isTransparent())
											&& (j != 0 || i != 4)
											&& (px != 0 || i != 0 || chx0)
											&& (px != 15 || i != 1 || chx1)
											&& (py != 0 || i != 3 || chy0)
											&& (py != 15 || i != 2 || chy1)) {
					revealBlock(bi);
					break;
				}
			}
		}
		for (int i = 0; i < 16; i++) {
			// Checks if blocks from neighboring chunks are changed
			int [] dx = {15, 0, i, i};
			int [] dy = {i, i, 15, 0};
			int [] invdx = {0, 15, i, i};
			int [] invdy = {i, i, 0, 15};
			boolean [] toCheck = {chx0, chx1, chy0, chy1};
			Chunk [] chunks = {
					world._getChunk(ox-1, oy),
					world._getChunk(ox+1, oy),
					world._getChunk(ox, oy-1),
					world._getChunk(ox, oy+1),
					};
			for(int k = 0; k < 4; k++) {
				if (toCheck[k]) {
					Chunk ch = chunks[k];
					for (int j = World.WORLD_HEIGHT - 1; j >= 0; j--) {
						BlockInstance inst0 = ch.getBlockInstanceAt(dx[k], j, dy[k]);
						if(inst0 == null) {
							continue;
						}
						if(ch.contains(inst0)) {
							continue;
						}
						if (blocksLight(getBlockInstanceAt(invdx[k], j, invdy[k]), inst0.getBlock().isTransparent())) {
							ch.revealBlock(inst0);
							continue;
						}
					}
				}
			}
		}
		// Do some light updates.
		if(easyLighting) {
			ArrayList<int[]> lightUpdates = new ArrayList<>();
			// First of all update the top air blocks on which the sun is constant:
			int y0 = World.WORLD_HEIGHT;
			boolean stopped = false;
			while(!stopped) {
				--y0;
				for(int xz = 0; xz < 256; xz++) {
					light[(y0 << 8) | xz] |= 0xff000000;
					if(inst[(y0 << 8) | xz] != null) {
						inst[(y0 << 8) | xz].light |= 0xff000000;
						stopped = true;
					}
				}
			}
			// Add the lowest layer to the updates list:
			for(int x = 0; x < 16; x++) {
				for(int z = 0; z < 16; z++) {
					if(getInst(x, y0, z) == null)
						lightUpdates.add(new int[] {x, y0, z, 255});
				}
			}
			lightUpdate(lightUpdates, 24, 0x00ffffff);
			// Look at the neighboring chunks:
			boolean no = world._getNoGenerateChunk(ox-1, oy) != null;
			boolean po = world._getNoGenerateChunk(ox+1, oy) != null;
			boolean on = world._getNoGenerateChunk(ox, oy-1) != null;
			boolean op = world._getNoGenerateChunk(ox, oy+1) != null;
			if(no || on) {
				int x = 0, z = 0;
				for(int y = 0; y < y0; y++) {
					lightUpdate(x, y, z);
				}
			}
			if(no || op) {
				int x = 0, z = 15;
				for(int y = 0; y < y0; y++) {
					lightUpdate(x, y, z);
				}
			}
			if(po || on) {
				int x = 15, z = 0;
				for(int y = 0; y < y0; y++) {
					lightUpdate(x, y, z);
				}
			}
			if(po || op) {
				int x = 15, z = 15;
				for(int y = 0; y < y0; y++) {
					lightUpdate(x, y, z);
				}
			}
			if(no) {
				int x = 0;
				for(int z = 1; z < 15; z++) {
					for(int y = 0; y < y0; y++) {
						lightUpdate(x, y, z);
					}
				}
			}
			if(po) {
				int x = 15;
				for(int z = 1; z < 15; z++) {
					for(int y = 0; y < y0; y++) {
						lightUpdate(x, y, z);
					}
				}
			}
			if(on) {
				int z = 0;
				for(int x = 1; x < 15; x++) {
					for(int y = 0; y < y0; y++) {
						lightUpdate(x, y, z);
					}
				}
			}
			if(op) {
				int z = 15;
				for(int x = 1; x < 15; x++) {
					for(int y = 0; y < y0; y++) {
						lightUpdate(x, y, z);
					}
				}
			}
			// Take care about light sources:
			for(BlockInstance bi: list) {
				if(bi.getBlock().getLight() != 0) {
					lightUpdate(bi.getX(), bi.getY(), bi.getZ());
				}
			}
		}
	}
	
	public boolean blocksLight(BlockInstance bi, boolean transparent) {
		if(bi == null || (bi.getBlock().isTransparent() && !transparent)) {
			return true;
		}
		return false;
	}
	
	public boolean getsBlocked(BlockInstance bi, boolean transparent) {
		return !(!bi.getBlock().isTransparent() && transparent);
	}
	
	public boolean isGenerated() {
		return generated;
	}
	
	public BlockInstance getBlockInstanceAt(int x, int y, int z) {
		try {
			return getInst(x, y, z);
		} catch (Exception e) {
			return null;
		}
	}
	
	// This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	public Chunk getChunk(int x, int y) {
		int cx = x;
		cx >>= 4;
		int cz = y;
		cz >>= 4;
		if(ox != cx || oy != cz)
			return world._getChunk(cx, cz);
		return this;
	}
	
	public void hideBlock(BlockInstance bi) {
		int index = -1;
		for(int i = 0; i < visiblesSize; i++) {
			if(visibles[i] == bi) {
				index = i;
				break;
			}
		}
		if(index == -1)
			return;
		visiblesSize--;
		System.arraycopy(visibles, index+1, visibles, index, visiblesSize-index);
		visibles[visiblesSize] = null;
		if(visiblesSize < visibles.length >> 1) { // Decrease capacity if the array is less than 50% filled.
			BlockInstance[] old = visibles;
			visibles = new BlockInstance[old.length >> 1];
			System.arraycopy(old, 0, visibles, 0, visiblesSize);
		}
		if (world != null) for (BlockVisibilityChangeHandler handler : world.visibHandlers) {
			if (bi != null) handler.onBlockHide(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
		}
	}
	
	public synchronized void revealBlock(BlockInstance bi) {
		if(visiblesSize + 1 >= visibles.length) { // Always leave a null at the end of the array to make it unnecessary to test for the length in the renderer.
			BlockInstance[] old = visibles;
			visibles = new BlockInstance[visibles.length + (visibles.length >> 1)]; // Increase size by 1.5. Similar to `ArrayList`.
			System.arraycopy(old, 0, visibles, 0, visiblesSize);
		}
		visibles[visiblesSize] = bi;
		visiblesSize++;
		if (world != null) for (BlockVisibilityChangeHandler handler : world.visibHandlers) {
			if (bi != null) handler.onBlockAppear(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
		}
	}
	
	public boolean contains(BlockInstance bi) {
		for(int i = 0; i < visiblesSize; i++) {
			if(visibles[i] == bi)
				return true;
		}
		return false;
	}
	
	public void removeBlockAt(int x, int y, int z, boolean registerBlockChange) {
		BlockInstance bi = getBlockInstanceAt(x, y, z);
		if(bi == null)
			return;
		hideBlock(bi);
		if (bi.getBlock().getBlockClass() == BlockClass.FLUID) {
			liquids.remove(bi);
		}
		list.remove(bi);
		if (bi.getBlock().hasBlockEntity()) {
			blockEntities.remove(bi);
		}
		setInst(x, y, z, null);
		BlockInstance[] neighbors = bi.getNeighbors(this);
		if(neighbors[0] != null) neighbors[0].neighborWest = false;
		if(neighbors[1] != null) neighbors[1].neighborEast = false;
		if(neighbors[2] != null) neighbors[2].neighborSouth = false;
		if(neighbors[3] != null) neighbors[3].neighborNorth = false;
		if(neighbors[4] != null) neighbors[4].neighborUp = false;
		if(neighbors[5] != null) neighbors[5].neighborDown = false;
		lightUpdate(x, y, z);
		for (int i = 0; i < neighbors.length; i++) {
			BlockInstance inst = neighbors[i];
			if (inst != null && inst != bi) {
				Chunk ch = getChunk(inst.getX(), inst.getZ());
				if (!ch.contains(inst)) {
					ch.revealBlock(inst);
				}
				if (inst.getBlock().getBlockClass() == BlockClass.FLUID) {
					if (!updatingLiquids.contains(inst))
						updatingLiquids.add(inst);
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
				changes.add(new BlockChange(bi.getID(), -1, x, y, z));
				return;
			}
			if(-1 == changes.get(index).oldType) { // Removes the object if the block reverted to it's original state.
				changes.remove(index);
				return;
			}
			changes.get(index).newType = -1;
		}
	}
	
	public void addBlockAt(int x, int y, int z, Block b, boolean registerBlockChange) {
		if(y >= World.WORLD_HEIGHT)
			return;
		removeBlockAt(x, y, z, false);
		BlockInstance inst0 = new BlockInstance(b);
		addBlockAt(x, y, z, inst0, registerBlockChange);
	}
	
	/**
	 * Raw add block. Doesn't do any checks. To use with WorldGenerators
	 * @param x
	 * @param y
	 * @param z
	 */
	public void rawAddBlock(int x, int y, int z, BlockInstance bi) {
		if (bi != null && bi.getBlock() == null) {
			setInst(x, y, z, null);
			return;
		}
		if (bi != null) {
			bi.setWorld(world);
			list.add(bi);
			if (bi.getBlock().getBlockClass() == BlockClass.FLUID) {
				liquids.add(bi);
			}
		}
		setInst(x, y, z, bi);
	}
	
	public void addBlockAt(int x, int y, int z, BlockInstance inst0, boolean registerBlockChange) {
		int wx = ox << 4;
		int wy = oy << 4;
		if(y >= World.WORLD_HEIGHT)
			return;
		removeBlockAt(x, y, z, false);
		Block b = inst0.getBlock();
		inst0.setPosition(new Vector3i(x + wx, y, z + wy));
		inst0.setWorld(world);
		if (b.hasBlockEntity()) {
			BlockEntity te = b.createBlockEntity(inst0.getPosition());
			blockEntities.put(inst0, te);
		}
		list.add(inst0);
		if (b.getBlockClass() == BlockClass.FLUID) {
			liquids.add(inst0);
			updatingLiquids.add(inst0);
		}
		setInst(x, y, z, inst0);
		BlockInstance[] neighbors = inst0.getNeighbors(this);
		if(neighbors[0] != null) neighbors[0].neighborWest = getsBlocked(neighbors[0], inst0.getBlock().isTransparent());
		if(neighbors[1] != null) neighbors[1].neighborEast = getsBlocked(neighbors[1], inst0.getBlock().isTransparent());
		if(neighbors[2] != null) neighbors[2].neighborSouth = getsBlocked(neighbors[2], inst0.getBlock().isTransparent());
		if(neighbors[3] != null) neighbors[3].neighborNorth = getsBlocked(neighbors[3], inst0.getBlock().isTransparent());
		if(neighbors[4] != null) neighbors[4].neighborUp = getsBlocked(neighbors[4], inst0.getBlock().isTransparent());
		if(neighbors[5] != null) neighbors[5].neighborDown = getsBlocked(neighbors[5], inst0.getBlock().isTransparent());
		
		for (int i = 0; i < neighbors.length; i++) {
			if (blocksLight(neighbors[i], inst0.getBlock().isTransparent())) {
				revealBlock(inst0);
				break;
			}
		}
		
		for (int i = 0; i < neighbors.length; i++) {
			if(neighbors[i] != null) {
				Chunk ch = getChunk(neighbors[i].getX(), neighbors[i].getZ());
				if (ch.contains(neighbors[i])) {
					BlockInstance[] neighbors1 = neighbors[i].getNeighbors(ch);
					boolean vis = true;
					for (int j = 0; j < neighbors1.length; j++) {
						if (blocksLight(neighbors1[j], neighbors[i].getBlock().isTransparent())) {
							vis = false;
							break;
						}
					}
					if(vis) {
						ch.hideBlock(neighbors[i]);
					}
				}
				if (neighbors[i].getBlock().getBlockClass() == BlockClass.FLUID) {
					if (!updatingLiquids.contains(neighbors[i]))
						updatingLiquids.add(neighbors[i]);
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
		lightUpdate(x, y, z);
	}
	
	public Vector3f getMin(Player localPlayer, int worldAnd) {
		return new Vector3f(CubyzMath.matchSign(((ox << 4) - localPlayer.getPosition().x) & worldAnd, worldAnd) - localPlayer.getPosition().relX, -localPlayer.getPosition().y, CubyzMath.matchSign(((oy << 4) - localPlayer.getPosition().z) & worldAnd, worldAnd) - localPlayer.getPosition().relZ);
	}
	
	public Vector3f getMax(Player localPlayer, int worldAnd) {
		return new Vector3f(CubyzMath.matchSign(((ox << 4) - localPlayer.getPosition().x + 16) & worldAnd, worldAnd) - localPlayer.getPosition().relX, 255-localPlayer.getPosition().y, CubyzMath.matchSign(((oy << 4) - localPlayer.getPosition().z + 16) & worldAnd, worldAnd) - localPlayer.getPosition().relZ);
	}
	
	public byte[] save() {
		byte[] data = new byte[12 + (changes.size() << 4)];
		Bits.putInt(data, 0, ox);
		Bits.putInt(data, 4, oy);
		Bits.putInt(data, 8, changes.size());
		for(int i = 0; i < changes.size(); i++) {
			changes.get(i).save(data, 12 + (i << 4));
		}
		return data;
	}
	
	public int[] getData() {
		int[] data = new int[2];
		data[0] = ox;
		data[1] = oy;
		return data;
	}
	
	public int getLight(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT) return 0;
		if(x < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox-1, oy);
			if(chunk != null) return chunk.getLight(x+16, y, z);
			return 0;
		}
		if(x > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox+1, oy);
			if(chunk != null) return chunk.getLight(x-16, y, z);
			return 0;
		}
		if(z < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy-1);
			if(chunk != null) return chunk.getLight(x, y, z+16);
			return 0;
		}
		if(z > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy+1);
			if(chunk != null) return chunk.getLight(x, y, z-16);
			return 0;
		}
		return light[(x << 4) | (y << 8) | z];
	}
	public int averaging(Vector3f sunLight, int ...col) {
		int rAvg = 0, gAvg = 0, bAvg = 0;
		for(int i = 0; i < 8; i++) {
			int light = col[i];
			int sun = (light >>> 24) & 255;
			rAvg += Math.max((light >>> 16) & 255, (int)(sun*sunLight.x));
			gAvg += Math.max((light >>> 8) & 255, (int)(sun*sunLight.y));
			bAvg += Math.max((light >>> 0) & 255, (int)(sun*sunLight.z));
		}
		rAvg >>>= 3;
		gAvg >>>= 3;
		bAvg >>>= 3;
		return (rAvg << 16) | (gAvg << 8) | bAvg;
	}
	
	public int[] getCornerLight(BlockInstance bi, Vector3f sunLight) {
		// Get the light level of all 26 surrounding blocks:
		int[][][] light = new int[3][3][3];
		for(int dx = -1; dx <= 1; dx++) {
			for(int dy = -1; dy <= 1; dy++) {
				for(int dz = -1; dz <= 1; dz++) {
					light[dx+1][dy+1][dz+1] = getLight((bi.getX() & 15)+dx, bi.getY()+dy, (bi.getZ() & 15)+dz);
				}
			}
		}
		int[] res = new int[8];
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					res[(dx << 2) | (dy << 1) | dz] = averaging(sunLight, light[dx][dy][dz], light[dx][dy][dz+1], light[dx][dy+1][dz], light[dx][dy+1][dz+1], light[dx+1][dy][dz], light[dx+1][dy][dz+1], light[dx+1][dy+1][dz], light[dx+1][dy+1][dz+1]);
				}
			}
		}
		return res;
	}
}
