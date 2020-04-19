package io.cubyz.world.generator;

import io.cubyz.api.IRegistryElement;
import io.cubyz.world.Chunk;
import io.cubyz.world.TorusSurface;

public abstract class StellarTorusGenerator implements IRegistryElement {

	public abstract void generate(Chunk chunk, TorusSurface surface);
	
	@Override
	public void setID(int id) {
		throw new UnsupportedOperationException();
	}
	
}
