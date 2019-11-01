 package io.cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.TileEntity;
import io.cubyz.entity.Player;
import io.cubyz.math.Bits;
import io.cubyz.save.BlockChange;
import io.cubyz.world.generator.WorldGenerator;

public class Chunk {

	private BlockInstance[][][] inst;
	private ArrayList<BlockInstance> list = new ArrayList<>();
	private ArrayList<BlockChange> changes; // Reports block changes. Only those will be saved!s
	//private ArrayList<BlockInstance> visibles = new ArrayList<>();
	private BlockInstance[] visibles = new BlockInstance[10]; // Using an array here to speed up the renderer.
	private int visiblesSize = 0;
	private int ox, oy;
	private boolean generated;
	private boolean loaded;
	private Map<BlockInstance, TileEntity> tileEntities = new HashMap<>();
	
	private World world;
	
	public Chunk(int ox, int oy, World world, ArrayList<BlockChange> changes) {
		this.ox = ox;
		this.oy = oy;
		this.world = world;
		this.changes = changes;
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
	
	public BlockInstance[] getVisibles() {
		return visibles;
	}
	
	public Map<BlockInstance, TileEntity> tileEntities() {
		return tileEntities;
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
		if(y >= world.getHeight())
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
			inst = new BlockInstance[16][world.getHeight()][16];
		} else { // Checks if there is a block on that position and deposits it if degradable.
			BlockInstance bi = inst[rx][y][rz];
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
		if (b.hasTileEntity()) {
			TileEntity te = b.createTileEntity(inst0);
			tileEntities.put(inst0, te);
		}
		list.add(inst0);
		inst[rx][y][rz] = inst0;
		if(generated) {
			BlockInstance[] neighbors = inst0.getNeighbors(this);
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
				}
			}
		}
	}
	
	public void generateFrom(WorldGenerator gen) {
		if(inst == null) {
			inst = new BlockInstance[16][world.getHeight()][16];
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
			if(inst[bc.x][bc.y][bc.z] == null) {
				addBlockAt(bc.x, bc.y, bc.z, bl, false);
				bc.oldType = -1;
				continue;
			}
			bc.oldType = inst[bc.x][bc.y][bc.z].getID();
			inst[bc.x][bc.y][bc.z].setBlock(bl);
		}
	}
	
	// Loads the chunk
	public void load() {
		loaded = true;
		boolean chx0 = world._getChunk(ox - 1, oy).isGenerated();
		boolean chx1 = world._getChunk(ox + 1, oy).isGenerated();
		boolean chy0 = world._getChunk(ox, oy - 1).isGenerated();
		boolean chy1 = world._getChunk(ox, oy + 1).isGenerated();
		for(BlockInstance bi : list) {
			BlockInstance[] neighbors = bi.getNeighbors(this);
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
					for (int j = world.getHeight() - 1; j >= 0; j--) {
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
	}
	
	public boolean blocksLight(BlockInstance bi, boolean transparent) {
		if(bi == null || (bi.getBlock().isTransparent() && !transparent)) {
			return true;
		}
		return false;
	}
	
	public boolean isGenerated() {
		return generated;
	}
	
	public BlockInstance getBlockInstanceAt(int x, int y, int z) {
		try {
			return inst[x][y][z];
		} catch (Exception e) {
			return null;
		}
	}
	
	// This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	public Chunk getChunk(int x, int y) {

		int cx = x;
		if(cx < 0)
			cx -= 15;
		cx = cx / 16;
		int cz = y;
		if(cz < 0)
			cz -= 15;
		cz = cz / 16;
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
	}
	
	public void revealBlock(BlockInstance bi) {
		if(visiblesSize + 1 >= visibles.length) { // Always leave a null at the end of the array to make it unnecessary to test for the length in the renderer.
			BlockInstance[] old = visibles;
			visibles = new BlockInstance[visiblesSize + (visiblesSize >> 1)]; // Increase size by 1.5. Similar to `ArrayList`.
			System.arraycopy(old, 0, visibles, 0, visiblesSize);
		}
		visibles[visiblesSize] = bi;
		visiblesSize++;
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
		list.remove(bi);
		if (bi.getBlock().hasTileEntity()) {
			tileEntities.remove(bi);
		}
		inst[x][y][z] = null;
		BlockInstance[] neighbors = bi.getNeighbors(this);
		for (int i = 0; i < neighbors.length; i++) {
			BlockInstance inst = neighbors[i];
			if (inst != null && inst != bi) {
				Chunk ch = getChunk(inst.getX(), inst.getZ());
				if (!ch.contains(inst)) {
					ch.revealBlock(inst);
				}
			}
		}
		inst[x][y][z] = null;

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
		if(y >= world.getHeight())
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
			inst[x][y][z] = null;
			return;
		}
		if (bi != null) {
			bi.setWorld(world);
			list.add(bi);
		}
		inst[x][y][z] = bi;
	}
	
	public void addBlockAt(int x, int y, int z, BlockInstance inst0, boolean registerBlockChange) {
		int wx = ox << 4;
		int wy = oy << 4;
		if(y >= world.getHeight())
			return;
		removeBlockAt(x, y, z, false);
		Block b = inst0.getBlock();
		inst0.setPosition(new Vector3i(x + wx, y, z + wy));
		inst0.setWorld(world);
		if (b.hasTileEntity()) {
			TileEntity te = b.createTileEntity(inst0);
			tileEntities.put(inst0, te);
		}
		list.add(inst0);
		inst[x][y][z] = inst0;
		BlockInstance[] neighbors = inst0.getNeighbors(this);
		
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
	}
	
	public Vector3f getMin(Player localPlayer) {
		return new Vector3f(((ox << 4) - localPlayer.getPosition().x) - localPlayer.getPosition().relX, 0, ((oy << 4) - localPlayer.getPosition().z) - localPlayer.getPosition().relZ);
	}
	
	public Vector3f getMax(Player localPlayer) {
		return new Vector3f(((ox << 4) - localPlayer.getPosition().x + 16) - localPlayer.getPosition().relX, 255, ((oy << 4) - localPlayer.getPosition().z + 16) - localPlayer.getPosition().relZ);
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
