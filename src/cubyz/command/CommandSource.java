package cubyz.command;

import cubyz.world.World;

/**
 * Base interface for all entities that can execute commands.
 * @author zenith391
 */

public interface CommandSource {
	
	public void feedback(String feedback);
	public World getWorld();
	
}
