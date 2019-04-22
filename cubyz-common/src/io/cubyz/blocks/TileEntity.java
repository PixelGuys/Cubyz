package io.cubyz.blocks;

public abstract class TileEntity {

	private BlockInstance block;
	
	public TileEntity(BlockInstance bi) {
		block = bi;
	}
	
	public BlockInstance getBlockInstance() {
		return block;
	}
	
}
