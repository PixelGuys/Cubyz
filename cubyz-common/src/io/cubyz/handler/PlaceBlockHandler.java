package io.cubyz.handler;

import io.cubyz.blocks.Block;

public interface PlaceBlockHandler extends Handler {

	public void onBlockPlaced(Block b, int x, int y, int z);
	
}
