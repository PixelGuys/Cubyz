package cubyz.world.handler;

import cubyz.world.Surface;
import cubyz.world.blocks.Block;

public interface RemoveBlockHandler {

	public void onBlockRemoved(Surface surface, Block b, int x, int y, int z);
	
}
