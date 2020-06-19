package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.api.RegistryElement;

public interface RotationMode extends RegistryElement {
	public Object[] generateSpatials(BlockInstance bi, byte data);
	// currentData will be 0 if the blockTypes don't match.
	public byte generateData(Vector3i placementPosition, byte currentData);

	public boolean dependsOnNeightbors(); // Returns if the block should be destroyed or changed when a certain neighbor is removed.
	public Byte updateData(byte oldData, int removedDir); // removedDir is given in the same format as used in Chunk. If the returned value is null, then the block will be removed instead of only updating the data.
}
