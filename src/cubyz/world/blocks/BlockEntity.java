package cubyz.world.blocks;

import org.joml.Vector3i;

import cubyz.world.World;

/**
 * BlockEntities are blocks that have need additional data, like an inventory, or need to be iterated, like meltable blocks.
 */

public abstract class BlockEntity {

	protected Vector3i position;
	protected World world;
	
	public BlockEntity(World world, Vector3i pos) {
		this.world = world;
		this.position = pos;
	}
	
	public World getWorld() {
		return world;
	}
	
	public Vector3i getPosition() {
		return position;
	}
	
}
