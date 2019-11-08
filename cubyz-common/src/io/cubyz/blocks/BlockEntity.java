package io.cubyz.blocks;

public abstract class BlockEntity {

	private BlockInstance block;
	
	public BlockEntity(BlockInstance bi) {
		block = bi;
	}
	
	public BlockInstance getBlockInstance() {
		return block;
	}
	
}
