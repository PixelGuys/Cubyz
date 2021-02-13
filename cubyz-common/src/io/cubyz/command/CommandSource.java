package io.cubyz.command;

import io.cubyz.world.Surface;

/**
 * Base interface for all entities that can execute commands.
 * @author zenith391
 */

public interface CommandSource {
	
	public void feedback(String feedback);
	public Surface getSurface();
	
}
