package cubyz.world.handler;

import cubyz.world.blocks.Block;

public interface RemoveBlockHandler extends Handler {

	public void onBlockRemoved(Block b, int x, int y, int z);
	
}
