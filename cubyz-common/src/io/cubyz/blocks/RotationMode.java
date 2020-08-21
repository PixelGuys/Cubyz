package io.cubyz.blocks;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.api.RegistryElement;
import io.cubyz.entity.Player;

public interface RotationMode extends RegistryElement {
	public Object[] generateSpatials(BlockInstance bi, byte data, Player player, int worldSize);
	// currentData will be 0 if the blockTypes don't match.
	public byte generateData(Vector3i placementPosition, byte currentData);

	public boolean dependsOnNeightbors(); // Returns if the block should be destroyed or changed when a certain neighbor is removed.
	public Byte updateData(byte oldData, int removedDir); // removedDir is given in the same format as used in Chunk. If the returned value is null, then the block will be removed instead of only updating the data.
	
	/**
	 * A RotationMode may even alter the blocks transparency. Here is where it's done.
	 * @param data The blocks data
	 * @param relativeDir the relative direction of the other block. Given as difference of the indices in the Chunk array. 100% unintuitive to use, maybe I'll add an automatic transformation later.
	 */
	public boolean checkTransparency(byte data, int relativeDir);
	
	/**
	 * @return standard data for natural generation.
	 */
	public byte getNaturalStandard();
	
	/**
	 * @return Whether this RotationMode changes this blocks hitbox for player collision or block selection.
	 */
	public boolean changesHitbox();
	
	/**
	 * 
	 * @param intersection
	 * @param bi
	 * @param min minimal point of the surrounding block. May be overwritten.
	 * @param max maximal point of the surrounding block. May be overwritten.
	 * @return
	 */
	public float getRayIntersection(RayAabIntersection intersection, BlockInstance bi, Vector3f min, Vector3f max, Vector3f transformedPosition);
}
