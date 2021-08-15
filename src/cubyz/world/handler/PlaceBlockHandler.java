package cubyz.world.handler;

import cubyz.world.blocks.Block;

public interface PlaceBlockHandler extends Handler {

	public void onBlockPlaced(Block b, int x, int y, int z);
	
}
