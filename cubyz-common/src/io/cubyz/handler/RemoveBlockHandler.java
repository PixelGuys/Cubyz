package io.cubyz.handler;

import io.cubyz.blocks.Block;

public interface RemoveBlockHandler extends Handler {

	public void onBlockRemoved(Block b, int x, int y, int z);
	
}
