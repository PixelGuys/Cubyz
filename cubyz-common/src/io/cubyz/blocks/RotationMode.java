package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.api.RegistryElement;

public interface RotationMode extends RegistryElement {
	public Object[] generateSpatials(BlockInstance bi, byte data);
	// currentData will be 0 if the blockTypes don't match.
	public byte generateData(Vector3i placementPosition, byte currentData);
}
