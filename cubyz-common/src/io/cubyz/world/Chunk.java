package io.cubyz.world;

import io.cubyz.blocks.Block;

/**
 * Common interface for chunks of all scales and sizes.
 */

public interface Chunk {
	
	/**
	 * This is useful to convert for loops to work for reduced resolution:<br>
	 * Instead of using<br>
	 * for(int x = start; x < end; x++)<br>
	 * for(int x = chunk.startIndex(start); x < end; x += chunk.getVoxelSize())<br>
	 * should be used to only activate those voxels that are used in Cubyz's downscaling technique.
	 * @param index The normal starting index(for normal generation).
	 * @return the next higher index that is inside the grid of this chunk.
	 */
	public int startIndex(int start);
	
	/**
	 * Updates a block if current value is 0 (air) and if it is inside this chunk.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public void updateBlockIfAir(int x, int y, int z, Block newBlock);
	
	/**
	 * Updates a block if it is inside this chunk.<br>
	 * Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newBlock
	 */
	public void updateBlock(int x, int y, int z, Block newBlock);
	
	/**
	 * Checks if the given <b>relative</b> coordinates lie within the resolved grid of this chunk.
	 * @param x
	 * @param z
	 * @return
	 */
	public boolean liesInChunk(int x, int z);
	
	/**
	 * @return The size of one voxel unit inside the given Chunk.
	 */
	public int getVoxelSize();
	
	/**
	 * @return starting x coordinate of this chunk relative to the current surface.
	 */
	public int getWorldX();
	/**
	 * @return starting z coordinate of this chunk relative to the current surface.
	 */
	public int getWorldZ();
	/**
	 * @return this chunks width.
	 */
	public int getWidth();
}
