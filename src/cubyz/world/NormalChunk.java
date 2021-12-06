package cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3d;
import org.joml.Vector3i;

import cubyz.utils.Utilities;
import cubyz.utils.datastructures.FastList;
import cubyz.utils.math.Bits;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks.BlockClass;
import cubyz.world.save.BlockChange;
import cubyz.world.save.BlockPalette;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.worldgenerators.SurfaceGenerator;

/**
 * 32³ chunk of the world.
 */

public class NormalChunk extends Chunk {
	
	public static final int chunkShift = 5;
	
	public static final int chunkShift2 = 2*chunkShift;
	
	public static final int chunkSize = 1 << chunkShift;
	
	public static final int chunkMask = chunkSize - 1;
	
	public static final int arraySize = chunkSize*chunkSize*chunkSize;

	/**Due to having powers of 2 as dimensions it is more efficient to use a one-dimensional array.*/
	protected int[] blocks;
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
	protected boolean generated = false;
	protected boolean startedloading = false;
	protected boolean loaded = false;
	private ArrayList<BlockEntity> blockEntities = new ArrayList<>();
	
	protected final ServerWorld world;
	
	public final MapFragment map;

	public boolean updated;
	
	public NormalChunk(int cx, int cy, int cz, ServerWorld world) {
		super(cx << chunkShift, cy << chunkShift, cz << chunkShift, 1);
		inst = new BlockInstance[arraySize];
		blocks = new int[arraySize];
		this.cx = cx;
		this.cy = cy;
		this.cz = cz;
		this.world = world;
		this.map = world.getOrGenerateMapFragment(wx, wz, 1);
		changes = map.mapIO.getBlockChanges(cx, cy, cz);
	}
	
	public void generateFrom(SurfaceGenerator gen) {
		gen.generate(this, world);
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
	public static int getIndex(int x, int y, int z) {
		return (x << chunkShift) | (y << chunkShift2) | z;
	}
	
	/**
	 * Function calls are faster than two pointer references, which would happen when using a 3D-array, and functions can additionally be inlined by the VM.
	 * @param x
	 * @param y
	 * @param z
	 * @param b
	 * @param data
	 * ghueiwoav????
	 */
	@Deprecated
	private void setBlock(int x, int y, int z, int b) {
		int index = getIndex(x, y, z);
		blocks[index] = b;
		setUpdated();
	}
	
	/**
	 * Updates the block without changing visibility.
	 * @param x relative to this
	 * @param y relative to this
	 * @param z relative to this
	 * @param block
	 */
	@Override
	public void updateBlockInGeneration(int x, int y, int z, int b) {
		int index = getIndex(x, y, z);
		if (Blocks.blockClass(b) == BlockClass.FLUID) {
			liquids.add(index);
		}
		blocks[index] = b;
	}

	public void updateBlock(int x, int y, int z, int b) {
		int index = getIndex(x, y, z);
		if(blocks[index] != b) {
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
				changes.add(new BlockChange(0, b, index));
			} else if(b == changes.get(bcIndex).oldType) { // Removes the object if the block reverted to it's original state.
				changes.remove(bcIndex);
			} else {
				changes.get(bcIndex).newType = b;
			}
			blocks[index] = b;
			// Update the instance:
			if(inst[index] != null)
				inst[index].setBlock(b);
		}
		if (Blocks.blockClass(b) == BlockClass.FLUID) {
			liquids.add(index);
		}
		setUpdated();
	}
	
	/**
	 * Internal "hack" method used for the overlay, DO NOT USE!
	 */
	@Deprecated
	public void createBlocksForOverlay() {
		blocks = new int[arraySize];
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
	public void addBlockPossiblyOutside(int b, int x, int y, int z, boolean considerPrevious) {
		// Make the boundary checks:
		if (b == 0) return;
		int rx = x - wx;
		int ry = y - wy;
		int rz = z - wz;
		if(rx < 0 || rx >= chunkSize || ry < 0 || ry >= chunkSize || rz < 0 || rz >= chunkSize) {
			if (world.getChunk(cx + (rx >> chunkShift), cy + (ry >> chunkShift), cz + (rz >> chunkShift)) == null)
				return;
			world.getChunk(cx + (rx >> chunkShift), cy + (ry >> chunkShift), cz + (rz >> chunkShift)).addBlock(b, x & chunkMask, y & chunkMask, z & chunkMask, considerPrevious);
			return;
		} else {
			addBlock(b, rx, ry, rz, considerPrevious);
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
	public void addBlock(int b, int x, int y, int z, boolean considerPrevious) {
		int b2 = getBlock(x, y, z);
		if(b2 != 0) {
			if((!Blocks.degradable(b2) || Blocks.degradable(b)) && considerPrevious) {
				return;
			}
			removeBlockAt(x, y, z, false);
		}
		setBlock(x, y, z, b);
		if (Blocks.blockEntity(b) != null) {
			Vector3i pos = new Vector3i(wx+x, wy+y, wz+z);
			blockEntities.add(Blocks.createBlockEntity(b, world, pos));
		}
		if (Blocks.blockClass(b) == BlockClass.FLUID) {
			liquids.add(getIndex(x, y, z));
			updatingLiquids.add(getIndex(x, y, z));
		}
		if(generated) {
			int[] indices = new int[6];
			int[] neighbors = getNeighbors(x, y ,z, indices);
			BlockInstance[] visibleNeighbors = getVisibleNeighbors(x + wx, y + wy, z + wz);
			for(int k = 0; k < 6; k++) {
				if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, blocksBlockNot(b, neighbors[k], (getIndex(x, y, z) - indices[k])));
			}
			
			for (int i = 0; i < neighbors.length; i++) {
				if (blocksBlockNot(neighbors[i], b, (getIndex(x, y, z) - indices[i]))) {
					revealBlock(x & chunkMask, y & chunkMask, z & chunkMask);
					break;
				}
			}
			for (int i = 0; i < neighbors.length; i++) {
				if(neighbors[i] != 0) {
					int x2 = x+Neighbors.REL_X[i];
					int y2 = y+Neighbors.REL_Y[i];
					int z2 = z+Neighbors.REL_Z[i];
					int nx = x2 + wx;
					int ny = y2 + wy;
					int nz = z2 + wz;
					NormalChunk ch = getChunk(nx, ny, nz);
					if(Blocks.mode(neighbors[i]).dependsOnNeightbors()) {
						int newBlock = Blocks.mode(neighbors[i]).updateData(neighbors[i], i ^ 1, b);
						if(newBlock == 0) {
							world.removeBlock(nx, ny, nz);
							break; // Break here to prevent making stuff with non-existent blocks.
						} else if(newBlock != neighbors[i]) {
							world.updateBlock(nx, ny, nz, newBlock);
							// TODO: Eventual item drops.
						}
					}
					if (ch.contains(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask)) {
						int[] indices1 = new int[6];
						int[] neighbors1 = ch.getNeighbors(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask, indices1);
						boolean vis = true;
						for (int j = 0; j < neighbors1.length; j++) {
							if (blocksBlockNot(neighbors1[j], neighbors[i], indices[i] - indices1[j])) {
								vis = false;
								break;
							}
						}
						if(vis) {
							ch.hideBlock(x2 & chunkMask, y2 & chunkMask, z2 & chunkMask);
						}
					}
					if (Blocks.blockClass(neighbors[i]) == BlockClass.FLUID) {
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
			changes.add(new BlockChange(0, b, blockIndex));
		} else if(b == changes.get(index).oldType) { // Removes the object if the block reverted to it's original state.
			changes.remove(index);
		} else {
			changes.get(index).newType = b;
		}
		if(startedloading)
			lightUpdate(x, y, z);
	}
	
	/**
	 * Apply Block Changes loaded from file/stored in WorldIO. Must be called before loading.
	 */
	public void applyBlockChanges() {
		for(BlockChange bc : changes) {
			bc.oldType = blocks[bc.index];
			int b = bc.newType;
			if (Blocks.blockEntity(b) != null) {
				int z = bc.index & chunkMask;
				int x = (bc.index >>> chunkShift) & chunkMask;
				int y = (bc.index >>> chunkShift2) & chunkMask;
				Vector3i pos = new Vector3i(wx+x, wy+y, wz+z);
				blockEntities.add(Blocks.createBlockEntity(b, world, pos));
			}
			blocks[bc.index] = b;
		}
		setUpdated();
	}
	
	/**
	 * Returns true if <i>blocker</i> does not block <i>blocked</i>.
	 * @param blocker
	 * @param blocked
	 * @param blockerData
	 * @param direction
	 * @return
	 */
	public boolean blocksBlockNot(int blocker, int blocked, int direction) {
		return blocker == 0 || Blocks.mode(blocker).checkTransparency(blocker, direction) || (blocker != blocked && Blocks.viewThrough(blocker));
	}
	
	public void hideBlock(int x, int y, int z) {
		// Search for the BlockInstance in visibles:
		BlockInstance res = inst[getIndex(x, y, z)];
		if(res == null) return;
		visibles.remove(res);
		inst[getIndex(x, y, z)] = null;
		/*if (world != null) {
			for (BlockVisibilityChangeHandler handler : world.visibHandlers) {
				if (res != null) handler.onBlockHide(res.getBlock(), res.getX(), res.getY(), res.getZ());
			}
		}*/
		setUpdated();
	}
	
	/**
	 * Doesn't make any bound checks!
	 * @param x
	 * @param y
	 * @param z
	 */
	public synchronized void revealBlock(int x, int y, int z) {
		int index = getIndex(x, y, z);
		int b = blocks[index];
		BlockInstance bi = new BlockInstance(b, new Vector3i(x + wx, y + wy, z + wz), this);
		int[] indices = new int[6];
		int[] neighbors = getNeighbors(x, y ,z, indices);
		for(int k = 0; k < 6; k++) {
			bi.updateNeighbor(k, blocksBlockNot(neighbors[k], b, index - indices[k]));
		}
		bi.setWorld(world);
		visibles.add(bi);
		inst[index] = bi;
		/*if (world != null) {
			for (BlockVisibilityChangeHandler handler : world.visibHandlers) {
				if (bi != null) handler.onBlockAppear(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ());
			}
		}*/
		setUpdated();
	}
	
	/**
	 * Doesn't do any bound checks!
	 * @param x
	 * @param y
	 * @param z
	 * @param registerBlockChange
	 */
	public void removeBlockAt(int x, int y, int z, boolean registerBlockChange) {
		int block = getBlock(x, y, z);
		if(block == 0)
			return;
		hideBlock(x, y, z);
		if (Blocks.blockClass(block) == BlockClass.FLUID) {
			liquids.remove((Object) getIndex(x, y, z));
		}
		if (Blocks.blockEntity(block) != null) {
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
		setBlock(x, y, z, 0);
		BlockInstance[] visibleNeighbors = getVisibleNeighbors(x, y, z);
		for(int k = 0; k < 6; k++) {
			if(visibleNeighbors[k] != null) visibleNeighbors[k].updateNeighbor(k ^ 1, true);
		}
		if(startedloading)
			lightUpdate(x, y, z);
		int[] neighbors = getNeighbors(x, y, z);
		for (int i = 0; i < neighbors.length; i++) {
			int neighbor = neighbors[i];
			if (neighbor != 0) {
				int nx = x + Neighbors.REL_X[i] + wx;
				int ny = y + Neighbors.REL_Y[i] + wy;
				int nz = z + Neighbors.REL_Z[i] + wz;
				NormalChunk ch = getChunk(nx, ny, nz);
				// Check if the block is structurally depending on the removed block:
				if(Blocks.mode(neighbor).dependsOnNeightbors()) {
					int newBlock = Blocks.mode(neighbor).updateData(neighbor, i ^ 1, 0);
					if(newBlock == 0) {
						world.removeBlock(nx, ny, nz);
						break; // Break here to prevent making a non-existent block visible.
					} else if(newBlock != neighbor) {
						world.updateBlock(nx, ny, nz, newBlock);
						// TODO: Eventual item drops.
					}
				}
				if (!ch.contains(nx, ny, nz)) {
					ch.revealBlock(x+Neighbors.REL_X[i] & chunkMask, y+Neighbors.REL_Y[i] & chunkMask, z+Neighbors.REL_Z[i] & chunkMask);
				}
				if (Blocks.blockClass(neighbor) == BlockClass.FLUID) {
					int index = getIndex(x+Neighbors.REL_X[i] & chunkMask, y+Neighbors.REL_Y[i] & chunkMask, z+Neighbors.REL_Z[i] & chunkMask);
					if (!updatingLiquids.contains(index))
						updatingLiquids.add(index);
				}
			}
		}
		setBlock(x, y, z, 0); // TODO: Investigate why this is called twice.

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
				changes.add(new BlockChange(block, 0, blockIndex));
			} else if(changes.get(index).oldType == 0) { // Removes the object if the block reverted to it's original state(air).
				changes.remove(index);
			} else {
				changes.get(index).newType = 0;
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
	public byte[] save(BlockPalette blockPalette) {
		byte[] data = new byte[16 + (changes.size()*8)];
		Bits.putInt(data, 0, cx);
		Bits.putInt(data, 4, cy);
		Bits.putInt(data, 8, cz);
		Bits.putInt(data, 12, changes.size());
		for(int i = 0; i < changes.size(); i++) {
			changes.get(i).save(data, 16 + i*8, blockPalette);
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
			return world.getChunk(x, y, z);
		return this;
	}
	
	public int[] getNeighbors(int x, int y, int z) {
		int[] neighbors = new int[6];
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(int i = 0; i < 6; i++) {
			int xi = x+Neighbors.REL_X[i];
			int yi = y+Neighbors.REL_Y[i];
			int zi = z+Neighbors.REL_Z[i];
			if(xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				neighbors[i] = getBlock(xi, yi, zi);
			} else {
				NormalChunk ch = world.getChunk((xi >> chunkShift) + cx, (yi >> chunkShift) + cy, (zi >> chunkShift) +cz);
				if(ch != null) {
					neighbors[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
				} else {
					neighbors[i] = 1; // Some solid replacement, in case the chunk isn't loaded. TODO: Properly choose a solid block.
				}
			}
		}
		return neighbors;
	}
	
	public int[] getNeighbors(int x, int y, int z, int[] indices) {
		int[] neighbors = new int[6];
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(int i = 0; i < 6; i++) {
			int xi = x+Neighbors.REL_X[i];
			int yi = y+Neighbors.REL_Y[i];
			int zi = z+Neighbors.REL_Z[i];
			if(xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				int index = getIndex(xi, yi, zi);
				neighbors[i] = getBlock(xi, yi, zi);
				indices[i] = index;
			} else {
				NormalChunk ch = world.getChunk((xi >> chunkShift) + cx, (yi >> chunkShift) + cy, (zi >> chunkShift) + cz);
				if(ch != null && ch.startedloading) {
					int index = getIndex(xi & chunkMask, yi & chunkMask, zi & chunkMask);
					neighbors[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
					indices[i] = index;
				} else {
					neighbors[i] = 1; // Some solid replacement, in case the chunk isn't loaded. TODO: Properly choose a solid block.
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
			int xi = x+Neighbors.REL_X[i];
			int yi = y+Neighbors.REL_Y[i];
			int zi = z+Neighbors.REL_Z[i];
			if(xi != (xi & chunkMask) || yi != (yi & chunkMask) || zi != (zi & chunkMask)) { // Simple double-bound test for coordinates.
				NormalChunk ch = world.getChunk((xi >> chunkShift) + cx, (yi >> chunkShift) + cy, (zi >> chunkShift) + cz);
				if(ch != null)
					ch.setUpdated();
			}
		}
		setUpdated();
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
			inst[i] = getVisibleUnbound(x+Neighbors.REL_X[i], y+Neighbors.REL_Y[i], z+Neighbors.REL_Z[i]);
		}
		return inst;
	}
	
	public int getNeighbor(int i, int x, int y, int z) {
		int xi = x+Neighbors.REL_X[i];
		int yi = y+Neighbors.REL_Y[i];
		int zi = z+Neighbors.REL_Z[i];
		if(xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
			return getBlock(xi, yi, zi);
		} else {
			return world.getBlock(xi + wx, yi + wy, zi + wz);
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
	public int getBlock(int x, int y, int z) {
		return blocks[getIndex(x, y, z)];
	}
	
	public int getBlockAtIndex(int index) {
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
	public int getBlockUnbound(int x, int y, int z) {
		if(!generated) return 0;
		if(x < 0 || x >= chunkSize || y < 0 || y >= chunkSize || z < 0 || z >= chunkSize) {
			NormalChunk chunk = world.getChunk(cx + (x >> chunkShift), cy + (y >> chunkShift), cz + (z >> chunkShift));
			if(chunk != null && chunk.isGenerated()) return chunk.getBlockUnbound(x & chunkMask, y & chunkMask, z & chunkMask);
			return 0;
		}
		return blocks[getIndex(x, y, z)];
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
			NormalChunk chunk = world.getChunk(cx + (x >> chunkShift), cy + (y >> chunkShift), cz + (z >> chunkShift));
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
	
	/**
	 * Checks if a given coordinate is inside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public boolean isInside(double x, double y, double z) {
		return (x - wx) >= 0 && (x - wx) < chunkSize && (y - wy) >= 0 && (y - wy) < chunkSize && (z - wz) >= 0 && (z - wz) < chunkSize;
	}
	
	public Vector3d getMin() {
		return new Vector3d(wx, wy, wz);
	}
	
	public Vector3d getMax() {
		return new Vector3d(wx + chunkSize, wy + chunkSize, wz + chunkSize);
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

	@Override
	public void updateBlockIfDegradable(int x, int y, int z, int newBlock) {
		int index = getIndex(x, y, z);
		if(Blocks.degradable(blocks[index])) {
			if (Blocks.blockClass(newBlock) == BlockClass.FLUID) {
				liquids.add(index);
			}
			blocks[index] = Blocks.mode(newBlock).getNaturalStandard(newBlock);
			setUpdated();
		}
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
