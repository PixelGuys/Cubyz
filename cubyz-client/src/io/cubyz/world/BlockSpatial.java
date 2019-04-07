package io.cubyz.world;

import org.jungle.Mesh;
import org.jungle.Spatial;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.IBlockSpatial;
import io.cubyz.client.ClientBlockPair;

public class BlockSpatial extends Spatial implements IBlockSpatial {

	private BlockInstance owner;
	
	public BlockSpatial(BlockInstance bi) {
		super((Mesh) ((ClientBlockPair) bi.getBlock().getBlockPair()).get("meshCache"));
		this.setPosition(bi.getX(), bi.getY(), bi.getZ());
		//this.setScale(0.5f);
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
