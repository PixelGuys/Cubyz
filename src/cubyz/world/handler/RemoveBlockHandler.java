package cubyz.world.handler;

import cubyz.world.ServerWorld;

public interface RemoveBlockHandler {

	public void onBlockRemoved(ServerWorld world, int b, int x, int y, int z);
	
}
