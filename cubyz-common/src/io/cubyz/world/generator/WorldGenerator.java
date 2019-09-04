package io.cubyz.world.generator;

import io.cubyz.world.Chunk;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.World;

public abstract class WorldGenerator {

	public abstract void generate(Chunk chunk, World world);
	
}
