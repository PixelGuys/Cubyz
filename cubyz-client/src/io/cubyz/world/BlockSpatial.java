package io.cubyz.world;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.client.Meshes;
import io.jungle.Spatial;

public class BlockSpatial extends Spatial {

	private BlockInstance owner;
	
	public BlockSpatial(BlockInstance bi) {
		super(Meshes.blockMeshes.get(bi.getBlock()));
		this.setPosition(bi.getX(), bi.getY(), bi.getZ());
		this.owner = bi;
	}
	
	public BlockSpatial(BlockSpatial toCopy) {
		super(toCopy);
		owner = toCopy.owner;
	}
	
	public BlockInstance getBlock() {
		return owner;
	}

	public BlockInstance getBlockInstance() {
		return owner;
	}
	
}
