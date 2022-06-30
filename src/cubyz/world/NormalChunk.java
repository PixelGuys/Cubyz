package cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3i;

import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.Blocks.BlockClass;

/**
 * 32³ chunk of the world.
 */

public class NormalChunk extends Chunk {
	/**Stores the local index of the block.*/
	private final ArrayList<Integer> liquids = new ArrayList<>();
	/**Liquids that should be updated at next frame. Stores the local index of the block.*/
	private final ArrayList<Integer> updatingLiquids = new ArrayList<>();
	protected boolean startedloading = false;
	protected boolean loaded = false;
	private final ArrayList<BlockEntity> blockEntities = new ArrayList<>();

	public boolean updated; // TODO: Move this over to VisibleChunk, the only place where it's actually used(I think).
	
	public NormalChunk(World world, Integer wx, Integer wy, Integer wz) {
		super(world, wx, wy, wz, 1);
	}

	/**
	 * Clears the data structures which are used for visible blocks.
	 */
	public void clear() {
	}
	
	/**
	 * Updates the block without changing visibility.
	 * @param x relative to this
	 * @param y relative to this
	 * @param z relative to this
	 * @param b block
	 */
	@Override
	public void updateBlockInGeneration(int x, int y, int z, int b) {
		assert !generated : "It's literally called updateBlockInGENERATION";
		int index = getIndex(x, y, z);
		if (Blocks.blockClass(b) == BlockClass.FLUID) {
			liquids.add(index);
		}
		blocks[index] = b;
	}

	protected void updateVisibleBlock(int index, int b) {}

	public void updateBlock(int x, int y, int z, int b) {
		int index = getIndex(x, y, z);
		if(b == 0) {
			removeBlockAt(x, y, z, true);
		} else if(blocks[index] == 0) {
			addBlock(b, x, y, z, false);
		} else {
			if((b & Blocks.TYPE_MASK) == (blocks[index] & Blocks.TYPE_MASK)) {
				blocks[index] = b;
				updateVisibleBlock(index, b);
				setChanged();
			} else {
				removeBlockAt(x, y, z, true);
				addBlock(b, x, y, z, false);
			}
		}
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
		if (b == 0) return;
		int rx = x - wx;
		int ry = y - wy;
		int rz = z - wz;
		if (rx < 0 || rx >= chunkSize || ry < 0 || ry >= chunkSize || rz < 0 || rz >= chunkSize) {
			if (world.getChunk(wx + rx, wy + ry, wz + rz) == null)
				return;
			world.getChunk(wx + rx, wy + ry, wz + rz).addBlock(b, x & chunkMask, y & chunkMask, z & chunkMask, considerPrevious);
		} else {
			addBlock(b, rx, ry, rz, considerPrevious);
		}
	}
	
	/**
	 * Does not check bounds!
	 * @param b
	 * @param x Relative to this Chunk.
	 * @param y Relative to this Chunk.
	 * @param z Relative to this Chunk.
	 * @param considerPrevious If the degradability of the block which was there before should be considered.
	 */
	public void addBlock(int b, int x, int y, int z, boolean considerPrevious) {
		int b2 = getBlock(x, y, z);
		if (b2 != 0) {
			if ((!Blocks.degradable(b2) || Blocks.degradable(b)) && considerPrevious) {
				return;
			}
			removeBlockAt(x, y, z, false);
		}
		blocks[getIndex(x, y, z)] = b;
		if (Blocks.blockEntity(b) != null) {
			Vector3i pos = new Vector3i(wx+x, wy+y, wz+z);
			blockEntities.add(Blocks.createBlockEntity(b, world, pos));
		}
		if (Blocks.blockClass(b) == BlockClass.FLUID) {
			liquids.add(getIndex(x, y, z));
			updatingLiquids.add(getIndex(x, y, z));
		}
		if (generated) {
			int[] neighbors = getNeighbors(x, y , z);
			for (int i = 0; i < Neighbors.NEIGHBORS; i++) {
				if (neighbors[i] != 0) {
					int nx = x + Neighbors.REL_X[i] + wx;
					int ny = y + Neighbors.REL_Y[i] + wy;
					int nz = z + Neighbors.REL_Z[i] + wz;
					NormalChunk ch = getChunk(nx, ny, nz);
					if(ch == null) continue;
					if (Blocks.mode(neighbors[i]).dependsOnNeightbors()) {
						int newBlock = Blocks.mode(neighbors[i]).updateData(neighbors[i], i ^ 1, b);
						if (newBlock == 0) {
							world.updateBlock(nx, ny, nz, 0);
							continue; // Prevent making stuff with non-existent blocks.
						} else if (newBlock != neighbors[i]) {
							world.updateBlock(nx, ny, nz, newBlock);
							// TODO: Eventual item drops.
						}
					}
					nx &= chunkMask;
					ny &= chunkMask;
					nz &= chunkMask;
					if (Blocks.blockClass(neighbors[i]) == BlockClass.FLUID) {
						int index = getIndex(nx, ny, nz);
						if (!updatingLiquids.contains(index))
							updatingLiquids.add(index);
					}
				}
			}
		}
		if (startedloading)
			lightUpdate(x, y, z);

		// Registers blockChange:
		setChanged();
	}
	
	/**
	 * Returns true if <i>blocker</i> does not block <i>blocked</i>.
	 * @param blocker
	 * @param blocked
	 * @param neighbor →direction
	 * @return
	 */
	public boolean blocksBlockNot(int blocker, int blocked, int neighbor) {
		return blocker == 0 || Blocks.mode(blocker).checkTransparency(blocker, neighbor) || (blocker != blocked && Blocks.viewThrough(blocker));
	}
	
	public void hideBlock(int x, int y, int z) {
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
		if (block == 0)
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
		blocks[getIndex(x, y, z)] = 0;
		if (startedloading)
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
				if (Blocks.mode(neighbor).dependsOnNeightbors()) {
					int newBlock = Blocks.mode(neighbor).updateData(neighbor, i ^ 1, 0);
					if (newBlock == 0) {
						world.updateBlock(nx, ny, nz, 0);
						continue; // Prevent making a non-existent block visible.
					} else if (newBlock != neighbor) {
						world.updateBlock(nx, ny, nz, newBlock);
						// TODO: Eventual item drops.
					}
				}
				nx &= chunkMask;
				ny &= chunkMask;
				nz &= chunkMask;
				if (Blocks.blockClass(neighbor) == BlockClass.FLUID) {
					int index = getIndex(nx, ny, nz);
					if (!updatingLiquids.contains(index))
						updatingLiquids.add(index);
				}
			}
		}

		if (registerBlockChange) {
			setChanged();
		}
		
		updateNeighborChunks(x, y, z);
	}

	/**
	 * This function is here because it is mostly used by addBlock, where the neighbors to the added block usually are in the same chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public NormalChunk getChunk(int x, int y, int z) {
		if(!this.liesInChunk(x, y, z))
			return world.getChunk(x, y, z);
		return this;
	}
	
	public int[] getNeighbors(int x, int y, int z) {
		int[] neighbors = new int[Neighbors.NEIGHBORS];
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(int i = 0; i < Neighbors.NEIGHBORS; i++) {
			int xi = x+Neighbors.REL_X[i];
			int yi = y+Neighbors.REL_Y[i];
			int zi = z+Neighbors.REL_Z[i];
			if (xi == (xi & chunkMask) && yi == (yi & chunkMask) && zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				neighbors[i] = getBlock(xi, yi, zi);
			} else {
				NormalChunk ch = world.getChunk(xi + wx, yi + wy, zi + wz);
				if (ch != null) {
					neighbors[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
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
			if (xi != (xi & chunkMask) || yi != (yi & chunkMask) || zi != (zi & chunkMask)) { // Simple double-bound test for coordinates.
				NormalChunk ch = world.getChunk(xi + wx, yi + wy, zi + wz);
				if (ch != null)
					ch.setUpdated();
			}
		}
		setUpdated();
	}
	
	/**
	 * Uses relative coordinates and doesn't do any bound checks!
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

	
	/**
	 * Uses relative coordinates. Correctly works for blocks outside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return block at the coordinates x+wx, y+wy, z+wz
	 */
	public int getBlockPossiblyOutside(int x, int y, int z) {
		if (!generated) return 0;
		if (x < 0 || x >= chunkSize || y < 0 || y >= chunkSize || z < 0 || z >= chunkSize) {
			NormalChunk chunk = world.getChunk(wx + x, wy + y, wz + z);
			if (chunk != null && chunk.generated) return chunk.getBlockPossiblyOutside(x & chunkMask, y & chunkMask, z & chunkMask);
			return 0;
		}
		return blocks[getIndex(x, y, z)];
	}

	/**
	 * Checks if a given world coordinate is inside this chunk.
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public boolean isInside(double x, double y, double z) {
		return (x - wx) >= 0 && (x - wx) < chunkSize && (y - wy) >= 0 && (y - wy) < chunkSize && (z - wz) >= 0 && (z - wz) < chunkSize;
	}
	
	public ArrayList<Integer> getLiquids() {
		return liquids;
	}
	
	public ArrayList<Integer> getUpdatingLiquids() {
		return updatingLiquids;
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
	
	@Override
	public int startIndex(int start) {
		return start;
	}
	
	// Interface to client-only functionality:
	// TODO: Minimize them.
	
	protected void lightUpdate(int x, int y, int z) {}
	public void load() {
		loaded = true;
	}
	public int getLight(int x, int y, int z) {return 0;}
	
	// Implementations of interface Chunk:

	@Override
	public void updateBlockIfDegradable(int x, int y, int z, int newBlock) {
		int index = getIndex(x, y, z);
		if (Blocks.degradable(blocks[index])) {
			if (Blocks.blockClass(newBlock) == BlockClass.FLUID) {
				liquids.add(index);
			}
			blocks[index] = Blocks.mode(newBlock).getNaturalStandard(newBlock);
			setUpdated();
		}
	}
}
