 package io.cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.Utilities;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.math.Bits;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;
import io.cubyz.save.Palette;
import io.cubyz.util.FastList;
import io.cubyz.world.generator.SurfaceGenerator;

/**
 * A 16×WORLD_HEIGHT×16 big chunk of the world map.
 */

public class NormalChunk extends Chunk {
	/**
	 * Used for easy for-loop access of neighbors and their relative direction:
	 * East, West, South, North, Down, Up.
	 */
	private static final int[] neighborRelativeX = {-1, 1, 0, 0, 0, 0},
							   neighborRelativeY = {0, 0, 0, 0, -1, 1},
							   neighborRelativeZ = {0, 0, -1, 1, 0, 0};
	/**Due to having powers of 2 as dimensions it is more efficient to use a one-dimensional array.*/
	protected Block[] blocks;
	/**Important data used to store rotation. Will be used later for water levels and stuff like that.*/
	protected byte[] blockData;
	/**Stores all visible BlockInstances. Can be faster accessed using coordinates.*/
	protected BlockInstance[] inst;
	/**Stores the local index of the block.*/
	private ArrayList<Integer> liquids = new ArrayList<>();
	/**Liquids that should be updated at next frame. Stores the local index of the block.*/
	private ArrayList<Integer> updatingLiquids = new ArrayList<>();
	/**Reports block changes. Only those will be saved!*/
	private final ArrayList<BlockChange> changes;
	private FastList<BlockInstance> visibles = new FastList<BlockInstance>(50, BlockInstance.class);
	protected final int cx, cz;
	protected final int wx, wz;
	protected boolean generated;
	protected boolean startedloading;
	protected boolean loaded;
	protected boolean updated = true;
	private ArrayList<BlockEntity> blockEntities = new ArrayList<>();
	
	protected final Surface surface;
	
	/**A random block used as a replacement for blocks from yet unloaded chunks.*/
	Block noLight = new Block();
	
	public final Region region;
	
	public NormalChunk(Integer cx, Integer cz, Surface surface) {
		if(surface != null) {
			cx = CubyzMath.worldModulo(cx, surface.getSizeX() >>> 4);
			cz = CubyzMath.worldModulo(cz, surface.getSizeZ() >>> 4);
		}
		inst = new BlockInstance[16*World.WORLD_HEIGHT*16];
		blocks = new Block[16*World.WORLD_HEIGHT*16];
		blockData = new byte[16*World.WORLD_HEIGHT*16];
		this.cx = cx;
		this.cz = cz;
		wx = cx << 4;
		wz = cz << 4;
		this.surface = surface;
		this.region = surface.getRegion(wx, wz);
		changes = region.regIO.getBlockChanges(cx, cz);
	}
	
	public void generateFrom(SurfaceGenerator gen) {
		gen.generate(this, surface);
		applyBlockChanges();
		generated = true;
	}
	
	/**
	 * Clears the data structures which are used for visible blocks.
	 */
	public void clear() {
		visibles.clear();
		Utilities.fillArray(inst, null);
	}
	
	/**
	 * Function calls are faster than two pointer references, which would happen when using a 3D-array, and functions can additionally be inlined by the VM.
	 * @param x
	 * @param y
	 * @param z
	 * @param b
	 * @param data
	 */
	private void setBlock(int x, int y, int z, Block b, byte data) {
		int index = (x << 4) | (y << 8) | z;
		blocks[index] = b;
		blockData[index] = data;
		updated = true;
	}
	
	public void setBlockData(int x, int y, int z, byte data) {
		int index = (x << 4) | (y << 8) | z;
		if(blockData[index] != data) {
			// Registers blockChange:
			int bcIndex = -1; // Checks if it is already in the list
			for(int i = 0; i < changes.size(); i++) {
				BlockChange bc = changes.get(i);
				if(bc.index == index) {
					bcIndex = i;
					break;
				}
			}
			if(bcIndex == -1) { // Creates a new object if the block wasn't changed before
				changes.add(new BlockChange(-1, blocks[index].ID, index, blockData[index], data));
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
		updated = true;
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
				if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, blocksBlockNot(b, neighbors[k], data, ((x << 4) | (y << 8) | z) - indices[k]), surface.getStellarTorus().getWorld().getLocalPlayer());
			}
			
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksBlockNot(neighbors[i], b, dataN[i], ((x << 4) | (y << 8) | z) - indices[i])) {
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
							if (blocksBlockNot(neighbors1[j], neighbors[i], dataN1[j], indices[i] - indices1[j])) {
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
		int blockIndex = ((x & 15) << 4) | (y << 8) | (z & 15);
		int index = -1; // Checks if it is already in the list
		for(int i = 0; i < changes.size(); i++) {
			BlockChange bc = changes.get(i);
			if(bc.index == blockIndex) {
				index = i;
				break;
			}
		}
		if(index == -1) { // Creates a new object if the block wasn't changed before
			changes.add(new BlockChange(-1, b.ID, blockIndex, (byte)0, data));
		} else if(b.ID == changes.get(index).oldType && data == changes.get(index).oldData) { // Removes the object if the block reverted to it's original state.
			changes.remove(index);
		} else {
			changes.get(index).newType = b.ID;
			changes.get(index).newData = data;
		}
		if(startedloading)
			lightUpdate(x, y, z);
	}
	
	/**
	 * Apply Block Changes loaded from file/stored in WorldIO. Must be called before loading.
	 */
	public void applyBlockChanges() {
		for(BlockChange bc : changes) {
			bc.oldType = blocks[bc.index] == null ? -1 : blocks[bc.index].ID;
			bc.oldData = blockData[bc.index];
			Block b = bc.newType == -1 ? null : surface.getPlanetBlocks()[bc.newType];
			if (b != null && b.hasBlockEntity()) {
				int z = bc.index & 15;
				int x = (bc.index >>> 4) & 15;
				int y = bc.index >>> 8;
				Vector3i pos = new Vector3i(wx+x, y, wz+z);
				blockEntities.add(b.createBlockEntity(surface, pos));
			}
			blocks[bc.index] = b;
			blockData[bc.index] = bc.newData;
		}
		updated = true;
	}
	
	/**
	 * Returns true if <i>blocker</i> does not block <i>blocked</i>.
	 * @param blocker
	 * @param blocked
	 * @param blockerData
	 * @param direction
	 * @return
	 */
	public boolean blocksBlockNot(Block blocker, Block blocked, byte blockerData, int direction) {
		return blocker == null || blocker.mode.checkTransparency(blockerData, direction) || (blocker != blocked && blocker.isViewThrough(blockerData));
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
		updated = true;
	}
	
	public synchronized void revealBlock(int x, int y, int z) {
		// Make some sanity check for y coordinate:
		if(y < 0 || y >= World.WORLD_HEIGHT) return;
		int index = (x << 4) | (y << 8) | z;
		Block b = blocks[index];
		BlockInstance bi = new BlockInstance(b, blockData[index], new Vector3i(x + wx, y, z + wz), surface.getStellarTorus().getWorld().getLocalPlayer(), this);
		byte[] data = new byte[6];
		int[] indices = new int[6];
		Block[] neighbors = getNeighbors(x, y ,z, data, indices);
		for(int k = 0; k < 6; k++) {
			bi.updateNeighbor(k, blocksBlockNot(neighbors[k], b, data[k], index - indices[k]), surface.getStellarTorus().getWorld().getLocalPlayer());
		}
		bi.setStellarTorus(surface);
		visibles.add(bi);
		inst[(x << 4) | (y << 8) | z] = bi;
		if (surface != null) {
			for (BlockVisibilityChangeHandler handler : surface.visibHandlers) {
				if (bi != null) handler.onBlockAppear(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
			}
		}
		updated = true;
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
			if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, true, surface.getStellarTorus().getWorld().getLocalPlayer());
		}
		if(startedloading)
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
			int blockIndex = ((x & 15) << 4) | (y << 8) | (z & 15);
			// Registers blockChange:
			int index = -1; // Checks if it is already in the list
			for(int i = 0; i < changes.size(); i++) {
				BlockChange bc = changes.get(i);
				if(bc.index == blockIndex) {
					index = i;
					break;
				}
			}
			if(index == -1) { // Creates a new object if the block wasn't changed before
				changes.add(new BlockChange(block.ID, -1, blockIndex, oldData, (byte)0));
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
	public byte[] save(Palette<Block> blockPalette) {
		byte[] data = new byte[12 + (changes.size()*9)];
		Bits.putInt(data, 0, cx);
		Bits.putInt(data, 4, cz);
		Bits.putInt(data, 8, changes.size());
		for(int i = 0; i < changes.size(); i++) {
			changes.get(i).save(data, 12 + i*9, blockPalette);
		}
		return data;
	}
	
	public int[] getData() {
		int[] data = new int[2];
		data[0] = cx;
		data[1] = cz;
		return data;
	}
	
	/**
	 * This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	 * @param x
	 * @param z
	 * @return
	 */
	public NormalChunk getChunk(int x, int z) {
		x >>= 4;
		z >>= 4;
		if(cx != x || cz != z)
			return surface.getChunk(x, z);
		return this;
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
	
	/**
	 * Uses relative coordinates!
	 * @param x
	 * @param y
	 * @param z
	 * @return block at the coordinates x+wx, y, z+wz
	 */
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

	
	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return block at the coordinates x+wx, y, z+wz
	 */
	public Block getBlockUnbound(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return null;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) return chunk.getBlockUnbound(x & 15, y, z & 15);
			return noLight; // Let the lighting engine think this region is blocked.
		}
		return blocks[(x << 4) | (y << 8) | z];
	}


	
	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return blockdata at the coordinates x+wx, y, z+wz
	 */
	public byte getDataUnbound(int x, int y, int z) {
		if(y < 0 || y >= World.WORLD_HEIGHT || !generated) return 0;
		if(x < 0 || x > 15 || z < 0 || z > 15) {
			NormalChunk chunk = surface.getChunk(cx + ((x & ~15) >> 4), cz + ((z & ~15) >> 4));
			if(chunk != null && chunk.isGenerated()) return chunk.getDataUnbound(x & 15, y, z & 15);
			return 0; // Let the lighting engine think this region is blocked.
		}
		return blockData[(x << 4) | (y << 8) | z];
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
	
	public boolean wasUpdated() {
		return updated;
	}
	
	public int startIndex(int start) {
		return start;
	}
	
	// Interface to client-only functionality:
	// TODO: Minimize them.
	
	protected void lightUpdate(int x, int y, int z) {}
	public void load() {}
	public int getLight(int x, int y, int z) {return 0;}
	
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
		updated = true;
	}
	
	public void updateBlock(int x, int y, int z, Block newBlock) {
		updateBlock(x, y, z, newBlock, newBlock == null ? 0 : newBlock.mode.getNaturalStandard());
	}
	
	@Override
	public void setChunkMesh(Object mesh) {
		updated = false;
		super.setChunkMesh(mesh);
	}

	@Override
	public void updateBlock(int x, int y, int z, Block newBlock, byte data) {
		int index = (x << 4) | (y << 8) | z;
		if (newBlock != null && newBlock.getBlockClass() == BlockClass.FLUID) {
			liquids.add(index);
		}
		blocks[index] = newBlock;
		blockData[index] = data;
		updated = true;
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
