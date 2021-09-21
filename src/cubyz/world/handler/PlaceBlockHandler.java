package cubyz.world.handler;

import cubyz.world.Surface;
import cubyz.world.blocks.Block;

public interface PlaceBlockHandler {

	public void onBlockPlaced(Surface surface, Block b, int x, int y, int z);
	
}
