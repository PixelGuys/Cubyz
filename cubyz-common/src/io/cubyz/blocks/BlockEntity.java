package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.world.Surface;

/**
 * BlockEntities are blocks that have need additional data, like an inventory, or need to be iterated, like meltable blocks.
 */

public abstract class BlockEntity {

	protected Vector3i position;
	protected Surface surface;
	
	public BlockEntity(Surface surface, Vector3i pos) {
		this.surface = surface;
		this.position = pos;
	}
	
	public Surface getSurface() {
		return surface;
	}
	
	public Vector3i getPosition() {
		return position;
	}
	
}
