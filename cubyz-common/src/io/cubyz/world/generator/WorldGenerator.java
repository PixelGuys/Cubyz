package io.cubyz.world.generator;

import io.cubyz.api.IRegistryElement;
import io.cubyz.world.Chunk;
import io.cubyz.world.World;

public abstract class WorldGenerator implements IRegistryElement {

	public abstract void generate(Chunk chunk, World world);
	
	@Override
	public void setID(int id) {
		throw new UnsupportedOperationException();
	}
	
}
