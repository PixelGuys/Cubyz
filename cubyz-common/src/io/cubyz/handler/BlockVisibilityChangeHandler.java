package io.cubyz.handler;

import io.cubyz.blocks.Block;

public interface BlockVisibilityChangeHandler extends Handler {

	public void onBlockAppear(Block b, int x, int y, int z);
	public void onBlockHide(Block b, int x, int y, int z);
	
}
