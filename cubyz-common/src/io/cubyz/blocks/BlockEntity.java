package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.world.Surface;

public abstract class BlockEntity {

	protected Vector3i position;
	protected Surface surface;
	
	public BlockEntity(Surface surface, Vector3i pos) {
		this.surface = surface;
		this.position = pos;
	}
	
	public Surface getSurface() {
		return surface;
	}
	
	public Vector3i getPosition() {
		return position;
	}
	
}
