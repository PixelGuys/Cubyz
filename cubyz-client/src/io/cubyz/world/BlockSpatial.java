package io.cubyz.world;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.client.Meshes;
import io.cubyz.entity.Player;
import io.jungle.Spatial;

/**
 * Spatial that also stores a reference to the BlockInstance.
 */

public class BlockSpatial extends Spatial {
	private BlockInstance owner;
	
	public BlockSpatial(BlockInstance bi, Player p, int worldSize) {
		super(Meshes.blockMeshes.get(bi.getBlock()), bi.light);
		setPosition(bi.getX(), bi.getY(), bi.getZ(), p, worldSize);
		this.owner = bi;
	}

	public BlockInstance getBlockInstance() {
		return owner;
	}
	
}
