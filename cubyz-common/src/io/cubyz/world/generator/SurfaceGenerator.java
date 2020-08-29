package io.cubyz.world.generator;

import io.cubyz.api.RegistryElement;
import io.cubyz.world.Chunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;

public abstract class SurfaceGenerator implements RegistryElement {

	public abstract void generate(Chunk chunk, Surface surface);

	public abstract void generate(ReducedChunk chunk, Surface surface);
	
}
