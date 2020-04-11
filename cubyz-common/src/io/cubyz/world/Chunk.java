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
	
	// The shift and mask gives information about the color channel that is used for this lighting update. The mask is inverted!
	public void lightUpdate(byte x, int y, byte z, int shift, int mask) {
		// Make some bound checks:
		if(!easyLighting || y < 0 || y >= World.WORLD_HEIGHT || !generated) return;
		if(x < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox-1, oy);
			if(chunk != null) chunk.lightUpdate((byte)(x+16), y, z, shift, mask);
			return;
		}
		if(x > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox+1, oy);
			if(chunk != null) chunk.lightUpdate((byte)(x-16), y, z, shift, mask);
			return;
		}
		if(z < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy-1);
			if(chunk != null) chunk.lightUpdate(x, y, (byte)(z+16), shift, mask);
			return;
		}
		if(z > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy+1);
			if(chunk != null) chunk.lightUpdate(x, y, (byte)(z-16), shift, mask);
			return;
		}
		int index = (x << 4) | (y << 8) | z; // Works close to the datastructure. Allows for some optimizations.
		
		BlockInstance bi = inst[index];
		int maxLight = 1; // Make sure the light of a block never gets below 0.
		if(x != 0) {
			if(inst[index-16] == null) {
				maxLight = Math.max(maxLight, (light[index-16] >>> shift) & 255);
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox-1, oy);
			if(chunk != null && chunk.isLoaded()) {
				if(chunk.getInst(15, y, z) == null)
					maxLight = Math.max(maxLight, (chunk.light[index | 0xf0] >>> shift) & 255);
			}
		}
		if(x != 15) {
			if(inst[index+16] == null) {
				maxLight = Math.max(maxLight, (light[index+16] >>> shift) & 255);
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox+1, oy);
			if(chunk != null && chunk.isLoaded()) {
				if(chunk.getInst(0, y, z) == null)
					maxLight = Math.max(maxLight, (chunk.light[index & ~0xf0] >>> shift) & 255);
			}
		}
		if(z != 0) {
			if(inst[index-1] == null) {
				maxLight = Math.max(maxLight, (light[index-1] >>> shift) & 255);
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox, oy-1);
			if(chunk != null && chunk.isLoaded()) {
				if(chunk.getInst(x, y, 15) == null)
					maxLight = Math.max(maxLight, (chunk.light[index | 0xf] >>> shift) & 255);
			}
		}
		if(z != 15) {
			if(inst[index+1] == null) {
				maxLight = Math.max(maxLight, (light[index+1] >>> shift) & 255);
			}
		} else {
			Chunk chunk = world._getNoGenerateChunk(ox, oy+1);
			if(chunk != null && chunk.isLoaded()) {
				if(chunk.getInst(x, y, 0) == null)
					maxLight = Math.max(maxLight, (chunk.light[index & ~0xf0] >>> shift) & 255);
			}
		}
		if(y != 0) {
			if(inst[index-256] != null) {
				maxLight = Math.max(maxLight, (light[index-256] >>> shift) & 255);
			}
		}
		if(y != 255) {
			if(inst[index+256] != null) {
				int local = (light[index+256] >>> shift) & 255;
				if(shift == 24) // Sun channel
					local += 8;
				maxLight = Math.max(maxLight, local);
			}
		} else if(shift == 24) {
			maxLight = 263;
		}
		maxLight -= 8;
		if(bi != null) {
			if(maxLight == (maxLight & 255)) {
				light[index] = (light[index] & mask) | (maxLight << shift);
				bi.light = light[index];
			}
		} else {
			int curLight = (light[index] >>> shift) & 255;
			if(curLight != maxLight && maxLight == (maxLight & 255)) {
				light[index] = (light[index] & mask) | (maxLight << shift);
				lightUpdate((byte)(x-1), y, z, shift, mask);
				lightUpdate((byte)(x+1), y, z, shift, mask);
				lightUpdate(x, y-1, z, shift, mask);
				lightUpdate(x, y+1, z, shift, mask);
				lightUpdate(x, y, (byte)(z-1), shift, mask);
				lightUpdate(x, y, (byte)(z+1), shift, mask);
			}
		}
	}
	
	// Used for first time loading. For later update also negative changes have to be taken into account making the system more complex.
	public void constructiveLightUpdate(byte x, int y, byte z, int maxLight, int shift, int mask) {
		// Make some bound checks:
		if(!easyLighting || y < 0 || y >= World.WORLD_HEIGHT || !generated) return;
		if(x < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox-1, oy);
			if(chunk != null) chunk.constructiveLightUpdate((byte)(x+16), y, z, maxLight, shift, mask);
			return;
		}
		if(x > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox+1, oy);
			if(chunk != null) chunk.constructiveLightUpdate((byte)(x-16), y, z, maxLight, shift, mask);
			return;
		}
		if(z < 0) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy-1);
			if(chunk != null) chunk.constructiveLightUpdate(x, y, (byte)(z+16), maxLight, shift, mask);
			return;
		}
		if(z > 15) {
			Chunk chunk = world._getNoGenerateChunk(ox, oy+1);
			if(chunk != null) chunk.constructiveLightUpdate(x, y, (byte)(z-16), maxLight, shift, mask);
			return;
		}
		int index = (x << 4) | (y << 8) | z; // Works close to the datastructure. Allows for some optimizations.
		
		BlockInstance bi = inst[index];
		if(bi != null) {
			int curLight = (light[index] >>> shift) & 255;
			if(bi.getBlock().isTransparent()) {
				if(curLight < maxLight) {
					light[index] = (light[index] & mask) | (maxLight << shift);
					bi.light = light[index];
					maxLight -= 8;
					if(maxLight > 0) {
						constructiveLightUpdate((byte)(x-1), y, z, maxLight, shift, mask);
						constructiveLightUpdate((byte)(x+1), y, z, maxLight, shift, mask);
						constructiveLightUpdate(x, y-1, z, (byte)(maxLight+(shift == 24 ? 8 : 0)), shift, mask);
						constructiveLightUpdate(x, y+1, z, maxLight, shift, mask);
						constructiveLightUpdate(x, y, (byte)(z-1), maxLight, shift, mask);
						constructiveLightUpdate(x, y, (byte)(z+1), maxLight, shift, mask);
					}
				}
			} else {
				if(curLight < maxLight) {
					light[index] = (light[index] & mask) | (maxLight << shift);
					bi.light = light[index];
				}
			}
		} else {
			int curLight = (light[index] >>> shift) & 255;
			if(curLight < maxLight) {
				light[index] = (light[index] & mask) | (maxLight << shift);
				maxLight -= 8;
				if(maxLight > 0) {
					constructiveLightUpdate((byte)(x-1), y, z, maxLight, shift, mask);
					constructiveLightUpdate((byte)(x+1), y, z, maxLight, shift, mask);
					constructiveLightUpdate(x, y-1, z, (byte)(maxLight+(shift == 24 ? 8 : 0)), shift, mask);
					constructiveLightUpdate(x, y+1, z, maxLight, shift, mask);
					constructiveLightUpdate(x, y, (byte)(z-1), maxLight, shift, mask);
					constructiveLightUpdate(x, y, (byte)(z+1), maxLight, shift, mask);
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
					lightUpdate((byte)(neighbors[i].getX() & 15), neighbors[i].getY(), (byte)(neighbors[i].getZ() & 15), 24, 0x00ffffff);
				}
			}
		}
		lightUpdate((byte)rx, y, (byte)rz, 24, 0x00ffffff);
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
			for(byte x = 0; x < 16; x++) {
				for(byte z = 0; z < 16; z++) {
					constructiveLightUpdate(x, 255, z, 255, 24, 0x00ffffff);
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
		for (int i = 0; i < neighbors.length; i++) {
			BlockInstance inst = neighbors[i];
			if (inst != null && inst != bi) {
				lightUpdate((byte)(neighbors[i].getX() & 15), neighbors[i].getY(), (byte)(neighbors[i].getZ() & 15), 24, 0x00ffffff);
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
		lightUpdate((byte)x, y, (byte)z, 24, 0x00ffffff);
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
}
