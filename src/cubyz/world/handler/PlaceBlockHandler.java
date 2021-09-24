package cubyz.world.handler;

import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;

public interface PlaceBlockHandler {

	public void onBlockPlaced(ServerWorld world, Block b, int x, int y, int z);
	
}
