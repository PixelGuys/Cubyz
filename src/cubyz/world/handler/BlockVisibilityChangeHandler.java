package cubyz.world.handler;

import cubyz.world.blocks.Block;

public interface BlockVisibilityChangeHandler {

	public void onBlockAppear(Block b, int x, int y, int z);
	public void onBlockHide(Block b, int x, int y, int z);
	
}
