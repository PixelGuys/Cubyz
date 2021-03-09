package io.cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.Utilities;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.math.Bits;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;
import io.cubyz.save.Palette;
import io.cubyz.util.FastList;
import io.cubyz.world.generator.SurfaceGenerator;

/**
 * 32³ chunk of the world.
 */

public class NormalChunk extends Chunk {
	
	public static final int chunkShift = 5;
	
	public static final int chunkShift2 = 2*chunkShift;
	
	public static final int chunkSize = 1 << chunkShift;
	
	public static final int chunkMask = chunkSize - 1;
	
	public static final int arraySize = chunkSize*chunkSize*chunkSize;
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
	protected final int cx, cy, cz;
	protected final int wx, wy, wz;
	protected boolean generated;
	protected boolean startedloading;
	protected boolean loaded;
	protected boolean updated = true;
	private ArrayList<BlockEntity> blockEntities = new ArrayList<>();
	
	protected final Surface surface;
	
	public final Region region;
	
	public NormalChunk(int cx, int cy, int cz, Surface surface) {
		if(surface != null) {
			cx = CubyzMath.worldModulo(cx, surface.getSizeX() >> chunkShift);
			cz = CubyzMath.worldModulo(cz, surface.getSizeZ() >> chunkShift);
		}
		inst = new BlockInstance[arraySize];
		blocks = new Block[arraySize];
		blockData = new byte[arraySize];
		this.cx = cx;
		this.cy = cy;
		this.cz = cz;
		wx = cx << chunkShift;
		wy = cy << chunkShift;
		wz = cz << chunkShift;
		this.surface = surface;
		this.region = surface.getRegion(wx, wz, 1);
		changes = region.regIO.getBlockChanges(cx, cy, cz);
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
	 * Gets the index of a given position inside this chunk.
	 * Use this as much as possible, so it gets inlined by the VM.
	 * @param x 0 ≤ x < chunkSize
	 * @param y 0 ≤ y < chunkSize
	 * @param z 0 ≤ z < chunkSize
	 * @return
	 */
	public int getIndex(int x, int y, int z) {
		return (x << chunkShift) | (y << chunkShift2) | z;
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
		int index = getIndex(x, y, z);
		blocks[index] = b;
		blockData[index] = data;
		updated = true;
	}
	
	public void setBlockData(int x, int y, int z, byte data) {
		int index = getIndex(x, y, z);
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
				inst[index].setData(data);
		}
		updated = true;
	}
	
	public byte getBlockData(int x, int y, int z) {
		int index = getIndex(x, y, z);
		return blockData[index];
	}
	
	/**
	 * Internal "hack" method used for the overlay, DO NOT USE!
	 */
	@Deprecated
	public void createBlocksForOverlay() {
		blocks = new Block[arraySize];
		blockData = new byte[arraySize];
	}
	
	
	/**
	 * Add the <code>Block</code> b at relative space defined by X, Y, and Z, and if out of bounds, call this method from the other chunk<br/>
	 * Meaning that if x, y, z are out of bounds, this method will call the same method from other chunks to add it.
	 * @param b
	 * @param x global
	 * @param y global
	 * @param z global
	 * @param considerPrevious If the degradability of the block which was there before should be considered.
	 */
	public void addBlockPossiblyOutside(Block b, byte data, int x, int y, int z, boolean considerPrevious) {
		// Make the boundary checks:
		if (b == null) return;
		int rx = x - wx;
		int ry = y - wy;
		int rz = z - wz;
		if(rx < 0 || rx >= chunkSize || ry < 0 || ry >= chunkSize || rz < 0 || rz >= chunkSize) {
			if (surface.getChunk(cx + (rx >> chunkShift), cy + (ry >> chunkShift), cz + (rz >> chunkShift)) == null)
				return;
			surface.getChunk(cx + (rx >> chunkShift), cy + (ry >> chunkShift), cz + (rz >> chunkShift)).addBlock(b, data, x & chunkMask, y & chunkMask, z & chunkMask, considerPrevious);
			return;
		} else {
			addBlock(b, data, rx, ry, rz, considerPrevious);
		}
	}
	
	/**
	 * Does not check bounds!
	 * @param b
	 * @param data
	 * @param x Relative to this Chunk.
	 * @param y Relative to this Chunk.
	 * @param z Relative to this Chunk.
	 * @param registerBlockChange
	 * @param considerPrevious If the degradability of the block which was there before should be considered.
	 */
	public void addBlock(Block b, byte data, int x, int y, int z, boolean considerPrevious) {
		Block b2 = getBlock(x, y, z);
		if(b2 != null) {
			if((!b2.isDegradable() || b.isDegradable()) && considerPrevious) {
				return;
			}
			removeBlockAt(x, y, z, false);
		}
		setBlock(x, y, z, b, data);
		if (b.hasBlockEntity()) {
			Vector3i pos = new Vector3i(wx+x, wy+y, wz+z);
			blockEntities.add(b.createBlockEntity(surface, pos));
		}
		if (b.getBlockClass() == BlockClass.FLUID) {
			liquids.add(getIndex(x, y, z));
			updatingLiquids.add(getIndex(x, y, z));
		}
		if(generated) {
			byte[] dataN = new byte[6];
			int[] indices = new int[6];
			Block[] neighbors = getNeighbors(x, y ,z, dataN, indices);
			BlockInstance[] visibleNeighbors = getVisibleNeighbors(x + wx, y + wy, z + wz);
			for(int k = 0; k < 6; k++) {
				if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, blocksBlockNot(b, neighbors[k], data, (getIndex(x, y, z) - indices[k])));
			}
			
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksBlockNot(neighbors[i], b, dataN[i], (getIndex(x, y, z) - indices[i]))) {
					revealBlock(x & chunkMask, y & chunkMask, z & chunkMask);
					break;
				}
			}
			
			for (int i = 0; i < neighbors.length; i++) {
				if(neighbors[i] != null) {
					int x2 = x+neighborRelativeX[i];
					int y2 = y+neighborRelativeY[i];
					int z2 = z+neighborRelativeZ[i];
					NormalChunk ch = getChunk(x2 + wx, y2 + wy, z2 + wz);
					if (ch.contains(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask)) {
						byte[] dataN1 = new byte[6];
						int[] indices1 = new int[6];
						Block[] neighbors1 = ch.getNeighbors(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask, dataN1, indices1);
						boolean vis = true;
						for (int j = 0; j < neighbors1.length; j++) {
							if (blocksBlockNot(neighbors1[j], neighbors[i], dataN1[j], indices[i] - indices1[j])) {
								vis = false;
								break;
							}
						}
						if(vis) {
							ch.hideBlock(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask);
						}
					}
					if (neighbors[i].getBlockClass() == BlockClass.FLUID) {
						int index = getIndex(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask);
						if (!updatingLiquids.contains(index))
							updatingLiquids.add(index);
					}
				}
			}
		}

		// Registers blockChange:
		int blockIndex = getIndex(x & chunkMask, y & chunkMask, z & chunkMask);
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
				int z = bc.index & chunkMask;
				int x = (bc.index >>> chunkShift) & chunkMask;
				int y = (bc.index >>> chunkShift2) & chunkMask;
				Vector3i pos = new Vector3i(wx+x, wy+y, wz+z);
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
		BlockInstance res = inst[getIndex(x, y, z)];
		if(res == null) return;
		visibles.remove(res);
		inst[getIndex(x, y, z)] = null;
		if (surface != null) {
			for (BlockVisibilityChangeHandler handler : surface.visibHandlers) {
				if (res != null) handler.onBlockHide(res.getBlock(), res.getX(), res.getY(), res.getZ());
			}
		}
		updated = true;
	}
	
	/**
	 * Doesn't make any bound checks!
	 * @param x
	 * @param y
	 * @param z
	 */
	public synchronized void revealBlock(int x, int y, int z) {
		int index = getIndex(x, y, z);
		Block b = blocks[index];
		BlockInstance bi = new BlockInstance(b, blockData[index], new Vector3i(x + wx, y + wy, z + wz), this);
		byte[] data = new byte[6];
		int[] indices = new int[6];
		Block[] neighbors = getNeighbors(x, y ,z, data, indices);
		for(int k = 0; k < 6; k++) {
			bi.updateNeighbor(k, blocksBlockNot(neighbors[k], b, data[k], index - indices[k]));
		}
		bi.setStellarTorus(surface);
		visibles.add(bi);
		inst[index] = bi;
		if (surface != null) {
			for (BlockVisibilityChangeHandler handler : surface.visibHandlers) {
				if (bi != null) handler.onBlockAppear(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
			}
		}
		updated = true;
	}
	
	/**
	 * Doesn't do any bound checks!
	 * @param x
	 * @param y
	 * @param z
	 * @param registerBlockChange
	 */
	public void removeBlockAt(int x, int y, int z, boolean registerBlockChange) {
		Block block = getBlock(x, y, z);
		if(block == null)
			return;
		hideBlock(x, y, z);
		if (block.getBlockClass() == BlockClass.FLUID) {
			liquids.remove((Object) getIndex(x, y, z));
		}
		if (block.hasBlockEntity()) {
			//blockEntities.remove(block);
			// TODO : be more efficient (maybe have a reference to block entity in BlockInstance?, but it would have yet another big memory footprint)
			for (BlockEntity be : blockEntities) {
				Vector3i pos = be.getPosition();
				if (pos.x == wx + x && pos.y == wy + y && pos.z == wz + z) {
					blockEntities.remove(be);
					break;
				}
			}
		}
		setBlock(x, y, z, null, (byte)0);
		BlockInstance[] visibleNeighbors = getVisibleNeighbors(x, y, z);
		for(int k = 0; k < 6; k++) {
			if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, true);
		}
		if(startedloading)
			lightUpdate(x, y, z);
		Block[] neighbors = getNeighbors(x, y, z);
		for (int i = 0; i < neighbors.length; i++) {
			Block neighbor = neighbors[i];
			if (neighbor != null) {
				int nx = x + neighborRelativeX[i] + wx;
				int ny = y + neighborRelativeY[i] + wy;
				int nz = z + neighborRelativeZ[i] + wz;
				NormalChunk ch = getChunk(nx, ny, nz);
				// Check if the block is structurally depending on the removed block:
				if(neighbor.mode.dependsOnNeightbors()) {
					byte oldData = ch.getBlockData(nx & chunkMask, ny & chunkMask, nz & chunkMask);
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
					ch.revealBlock(x+neighborRelativeX[i] & chunkMask, y+neighborRelativeY[i] & chunkMask, z+neighborRelativeZ[i] & chunkMask);
				}
				if (neighbor.getBlockClass() == BlockClass.FLUID) {
					int index = getIndex(x+neighborRelativeX[i] & chunkMask, y+neighborRelativeY[i] & chunkMask, z+neighborRelativeZ[i] & chunkMask);
					if (!updatingLiquids.contains(index))
						updatingLiquids.add(index);
				}
			}
		}
		byte oldData = getBlockData(x, y, z);
		setBlock(x, y, z, null, (byte)0); // TODO: Investigate why this is called twice.

		if(registerBlockChange) {
			int blockIndex = getIndex(x & chunkMask, y & chunkMask, z & chunkMask);
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
			} else if(changes.get(index).oldType == -1) { // Removes the object if the block reverted to it's original state(air).
				changes.remove(index);
			} else {
				changes.get(index).newType = -1;
			}
		}
		
		updateNeighborChunks(x, y, z);
	}
	
	/**
	 * Doesn't make any bound checks!
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public boolean contains(int x, int y, int z) {
		return inst[getIndex(x & chunkMask, y & chunkMask, z & chunkMask)] != null;
	}
	
	/**
	 * Feed an empty block palette and it will be filled with all block types. 
	 * @param blockPalette
	 * @return chunk data as byte[]
	 */
	public byte[] save(Palette<Block> blockPalette) {
		byte[] data = new byte[16 + (changes.size()*9)];
		Bits.putInt(data, 0, cx);
		Bits.putInt(data, 4, cy);
		Bits.putInt(data, 8, cz);
		Bits.putInt(data, 12, changes.size());
		for(int i = 0; i < changes.size(); i++) {
			changes.get(i).save(data, 16 + i*9, blockPalette);
		}
		return data;
	}
	
	public int[] getData() {
		int[] data = new int[3];
		data[0] = cx;
		data[1] = cy;
		data[2] = cz;
		return data;
	}
	
	/**
	 * This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public NormalChunk getChunk(int x, int y, int z) {
		x >>= chunkShift;
		y >>= chunkShift;
		z >>= chunkShift;
		if(cx != x || cy != y || cz != z)
			return surface.getChunk(x, y, z);
		return this;
	}
	
	public Block[] getNeighbors(int x, int y, int z) {
		Block[] neighbors = new Block[6];
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(int i = 0; i < 6; i++) {
			int xi = x+neighborRelativeX[i];
			int yi = y+neighborRelativeY[i];
			int zi = z+neighborRelativeZ[i];
			if(xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				neighbors[i] = getBlock(xi, yi, zi);
			} else {
				NormalChunk ch = surface.getChunk((xi >> chunkShift) + cx, (yi >> chunkShift) + cy, (zi >> chunkShift) +cz);
				if(ch != null)
					neighbors[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
			}
		}
		return neighbors;
	}
	
	public Block[] getNeighbors(int x, int y, int z, byte[] data, int[] indices) {
		Block[] neighbors = new Block[6];
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(int i = 0; i < 6; i++) {
			int xi = x+neighborRelativeX[i];
			int yi = y+neighborRelativeY[i];
			int zi = z+neighborRelativeZ[i];
			if(xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				int index = getIndex(xi, yi, zi);
				neighbors[i] = getBlock(xi, yi, zi);
				data[i] = blockData[index];
				indices[i] = index;
			} else {
				NormalChunk ch = surface.getChunk((xi >> chunkShift) + cx, (yi >> chunkShift) + cy, (zi >> chunkShift) + cz);
				if(ch != null) {
					int index = getIndex(xi & chunkMask, yi & chunkMask, zi & chunkMask);
					neighbors[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
					data[i] = ch.blockData[index];
					indices[i] = index;
				}
			}
		}
		return neighbors;
	}
	
	/**
	 * Ensures that all neighboring chunks around a block update are updated to prevent light bugs on block removal.
	 * @param x
	 * @param y
	 * @param z
	 */
	public void updateNeighborChunks(int x, int y, int z) {
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(int i = 0; i < 6; i++) {
			int xi = x+neighborRelativeX[i];
			int yi = y+neighborRelativeY[i];
			int zi = z+neighborRelativeZ[i];
			if(xi != (xi & chunkMask) || yi != (yi & chunkMask) || zi != (zi & chunkMask)) { // Simple double-bound test for coordinates.
				NormalChunk ch = surface.getChunk((xi >> chunkShift) + cx, (yi >> chunkShift) + cy, (zi >> chunkShift) + cz);
				if(ch != null)
					ch.setUpdated();
			}
		}
	}
	
	/**
	 * Returns the corresponding BlockInstance for all visible neighbors of this block.
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public BlockInstance[] getVisibleNeighbors(int x, int y, int z) {
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
		if(xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
			return getBlock(xi, yi, zi);
		} else {
			return surface.getBlock(xi + wx, yi + wy, zi + wz);
		}
	}
	
	/**
	 * Uses relative coordinates and doesnt do any bound checks!
	 * @param x
	 * @param y
	 * @param z
	 * @return block at the coordinates x+wx, y, z+wz
	 */
	@Override
	public Block getBlock(int x, int y, int z) {
		return blocks[getIndex(x, y, z)];
	}
	
	public Block getBlockAtIndex(int index) {
		return blocks[index];
	}
	
	public BlockInstance getBlockInstanceAt(int index) {
		return inst[index];
	}

	
	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return block at the coordinates x+wx, y+wy, z+wz
	 */
	public Block getBlockUnbound(int x, int y, int z) {
		if(!generated) return null;
		if(x < 0 || x >= chunkSize || y < 0 || y >= chunkSize || z < 0 || z >= chunkSize) {
			NormalChunk chunk = surface.getChunk(cx + (x >> chunkShift), cy + (y >> chunkShift), cz + (z >> chunkShift));
			if(chunk != null && chunk.isGenerated()) return chunk.getBlockUnbound(x & chunkMask, y & chunkMask, z & chunkMask);
			return null;
		}
		return blocks[getIndex(x, y, z)];
	}


	
	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return blockdata at the coordinates x+wx, y+wy, z+wz
	 */
	public byte getDataUnbound(int x, int y, int z) {
		if(!generated) return 0;
		if(x < 0 || x >= chunkSize || y < 0 || y >= chunkSize || z < 0 || z >= chunkSize) {
			NormalChunk chunk = surface.getChunk(cx + (x >> chunkShift), cy + (y >> chunkShift), cz + (z >> chunkShift));
			if(chunk != null && chunk.isGenerated()) return chunk.getDataUnbound(x & chunkMask, y & chunkMask, z & chunkMask);
			return 0; // Let the lighting engine think this region is blocked.
		}
		return blockData[getIndex(x, y, z)];
	}

	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return BlockInstance at the coordinates x+wx, y+wy, z+wz
	 */
	private BlockInstance getVisibleUnbound(int x, int y, int z) {
		if(!generated) return null;
		if(x < 0 || x >= chunkSize || y < 0 || y >= chunkSize || z < 0 || z >= chunkSize) {
			NormalChunk chunk = surface.getChunk(cx + (x >> chunkShift), cy + (y >> chunkShift), cz + (z >> chunkShift));
			if(chunk != null) return chunk.getVisibleUnbound(x & chunkMask, y & chunkMask, z & chunkMask);
			return null;
		}
		return inst[getIndex(x, y, z)];
	}
	
	/**
	 * Checks if a given coordinate is inside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public boolean isInside(float x, float y, float z) {
		return (x - wx) >= 0 && (x - wx) < chunkSize && (y - wy) >= 0 && (y - wy) < chunkSize && (z - wz) >= 0 && (z - wz) < chunkSize;
	}
	
	public Vector3f getMin(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(wx, x0, worldSizeX), wy, CubyzMath.match(wz, z0, worldSizeZ));
	}
	
	public Vector3f getMax(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(wx, x0, worldSizeX) + chunkSize, wy + chunkSize, CubyzMath.match(wz, z0, worldSizeZ) + chunkSize);
	}
	
	public int getX() {
		return cx;
	}
	
	public int getY() {
		return cy;
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
	
	public void setUpdated() {
		updated = true;
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
		int index = getIndex(x, y, z);
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
		int index = getIndex(x, y, z);
		if (newBlock != null && newBlock.getBlockClass() == BlockClass.FLUID) {
			liquids.add(index);
		}
		blocks[index] = newBlock;
		blockData[index] = data;
		updated = true;
	}

	@Override
	public boolean liesInChunk(int x, int y, int z) {
		return x >= 0 && x < chunkSize && y >= 0 && y < chunkSize && z >= 0 && z < chunkSize;
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
	public int getWorldY() {
		return wy;
	}

	@Override
	public int getWorldZ() {
		return wz;
	}
	
	@Override
	public int getWidth() {
		return chunkSize;
	}
}
