package io.cubyz.blocks;

import org.joml.Vector3i;

public interface Updateable {

	public boolean randomUpdates();
	public void update(boolean isRandomUpdate);
	
}
