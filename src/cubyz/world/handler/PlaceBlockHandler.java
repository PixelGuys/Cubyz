package cubyz.world.handler;

import cubyz.world.ServerWorld;

public interface PlaceBlockHandler {

	public void onBlockPlaced(ServerWorld world, int b, int x, int y, int z);
	
}
