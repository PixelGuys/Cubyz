package io.cubyz.world.generator;

import io.cubyz.api.IRegistryElement;
import io.cubyz.world.Chunk;
import io.cubyz.world.Surface;

public abstract class SurfaceGenerator implements IRegistryElement {

	public abstract void generate(Chunk chunk, Surface surface);
	
}
