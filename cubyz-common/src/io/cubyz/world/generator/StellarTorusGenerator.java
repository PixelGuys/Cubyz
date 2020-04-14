package io.cubyz.world.generator;

import io.cubyz.api.IRegistryElement;
import io.cubyz.world.Chunk;
import io.cubyz.world.StellarTorus;
import io.cubyz.world.World;

public abstract class StellarTorusGenerator implements IRegistryElement {

	public abstract void generate(Chunk chunk, StellarTorus torus);
	
	@Override
	public void setID(int id) {
		throw new UnsupportedOperationException();
	}
	
}
