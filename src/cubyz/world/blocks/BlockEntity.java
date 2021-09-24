package cubyz.world.blocks;

import org.joml.Vector3i;

import cubyz.world.ServerWorld;

/**
 * BlockEntities are blocks that have need additional data, like an inventory, or need to be iterated, like meltable blocks.
 */

public abstract class BlockEntity {

	protected Vector3i position;
	protected ServerWorld world;
	
	public BlockEntity(ServerWorld world, Vector3i pos) {
		this.world = world;
		this.position = pos;
	}
	
	public ServerWorld getWorld() {
		return world;
	}
	
	public Vector3i getPosition() {
		return position;
	}
	
}
