package cubyz.world.handler;

import cubyz.world.World;

public interface RemoveBlockHandler {

	public void onBlockRemoved(World world, int b, int x, int y, int z);
	
}
