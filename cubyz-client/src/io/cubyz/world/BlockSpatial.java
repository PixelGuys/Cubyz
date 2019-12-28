package io.cubyz.world;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.IBlockSpatial;
import io.cubyz.client.Meshes;
import io.jungle.Spatial;

public class BlockSpatial extends Spatial implements IBlockSpatial {

	private BlockInstance owner;
	
	public BlockSpatial(BlockInstance bi) {
		super(Meshes.blockMeshes.get(bi.getBlock()));
		this.setPosition(bi.getX(), bi.getY(), bi.getZ());
		this.owner = bi;
	}
	
	public BlockInstance getBlock() {
		return owner;
	}

	@Override
	public BlockInstance getBlockInstance() {
		return owner;
	}
	
}
