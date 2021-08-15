package cubyz.world.generator;

import cubyz.api.RegistryElement;
import cubyz.world.Chunk;
import cubyz.world.Surface;

public abstract class SurfaceGenerator implements RegistryElement {

	public abstract void generate(Chunk chunk, Surface surface);
	
}
