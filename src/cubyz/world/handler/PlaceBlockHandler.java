package cubyz.world.handler;

import cubyz.world.World;

public interface PlaceBlockHandler {

	void onBlockPlaced(World world, int b, int x, int y, int z);
	
}
