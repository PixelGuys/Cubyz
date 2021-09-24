package cubyz.world.generator;

import cubyz.api.RegistryElement;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;

public abstract class SurfaceGenerator implements RegistryElement {

	public abstract void generate(Chunk chunk, ServerWorld world);
	
}
