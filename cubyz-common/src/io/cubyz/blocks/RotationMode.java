package io.cubyz.blocks;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.api.RegistryElement;
import io.cubyz.entity.Entity;
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

	/**
	 * Check if the entity would collide with the block.
	 * @param ent Entity to consider
	 * @param x x-coordinate of the block.
	 * @param y y-coordinate of the block.
	 * @param z z-coordinate of the block.
	 * @param data block data
	 * @return Whether the entity and block hitboxes overlap.
	 */
	public boolean checkEntity(Entity ent, int x, int y, int z, byte blockData);
	
	/**
	 * Check if the entity would collide with the block, if its position was changed by `vel`.
	 * If a collision occurs, adjust the velocity in way such that the entity does not move inside the block.
	 * @param ent Entity to consider
	 * @param vel Velocity of the entity. The 4th element is reserved for stepping: a y-movement that is done exactly once.
	 * @param x x-coordinate of the block.
	 * @param y y-coordinate of the block.
	 * @param z z-coordinate of the block.
	 * @param data block data
	 * @return Returns true if the block behaves like a normal block and therefor needs to be handled like a normal block in the specified direction. Returns false if everything has been handled already in here.
	 */
	public boolean checkEntityAndDoCollision(Entity ent, Vector4f vel, int x, int y, int z, byte blockData);
}
