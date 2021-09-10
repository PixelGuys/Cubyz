package cubyz.world;

import cubyz.world.blocks.Block;
import cubyz.world.generator.SurfaceGenerator;

public abstract class Chunk {
	protected Runnable meshListener;

	/**
	 * The mesh listener will be notified every time the mesh should change.
	 * @param listener
	 */
	public void setMeshListener(Runnable listener) {
		meshListener = listener;
	}
	/**
	 * This is useful to convert for loops to work for reduced resolution:<br>
	 * Instead of using<br>
	 * for(int x = start; x < end; x++)<br>
	 * for(int x = chunk.startIndex(start); x < end; x += chunk.getVoxelSize())<br>
	 * should be used to only activate those voxels that are used in Cubyz's downscaling technique.
	 * @param index The normal starting index(for normal generation).
	 * @return the next higher index that is inside the grid of this chunk.
	 */
	public abstract int startIndex(int start);
	
	/**
	 * Updates a block if current value is air or the current block is degradable.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public abstract void updateBlockIfDegradable(int x, int y, int z, Block newBlock);
	
	/**
	 * Updates a block if it is inside this chunk.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public abstract void updateBlock(int x, int y, int z, Block newBlock);
	
	/**
	 * Updates a block if it is inside this chunk.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @return block at x y z
	 */
	public abstract Block getBlock(int x, int y, int z);
	
	/**
	 * Updates a block if it is inside this chunk and sets its block data to the specified value(if blockdata is supported).<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 * @param data block data.
	 */
	public abstract void updateBlock(int x, int y, int z, Block newBlock, byte data);
	
	/**
	 * Generates this chunk.
	 * @param gen
	 */
	public abstract void generateFrom(SurfaceGenerator gen);
	
	/**
	 * Checks if the given <b>relative</b> coordinates lie within the bounds of this chunk.
	 * @param x
	 * @param z
	 * @return
	 */
	public abstract boolean liesInChunk(int x, int y, int z);
	
	/**
	 * @return The size of one voxel unit inside the given Chunk.
	 */
	public abstract int getVoxelSize();
	
	/**
	 * @return starting x coordinate of this chunk relative to the current surface.
	 */
	public abstract int getWorldX();
	/**
	 * @return starting y coordinate of this chunk relative to the current surface.
	 */
	public abstract int getWorldY();
	/**
	 * @return starting z coordinate of this chunk relative to the current surface.
	 */
	public abstract int getWorldZ();
	/**
	 * @return this chunks width.
	 */
	public abstract int getWidth();
}
