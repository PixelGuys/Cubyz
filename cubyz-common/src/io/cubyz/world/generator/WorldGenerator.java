package io.cubyz.world.generator;

import io.cubyz.world.Chunk;
import io.cubyz.world.LocalWorld;

public abstract class WorldGenerator {

	// LocalWorld is used as a generator will only operate on a world in which he can generate freely (which is not the case of remote world)
	// And by somehow making RemoteWorld as a LocalWorld, it would just make the player detected as "cheater" by the server
	public abstract void generate(Chunk chunk, LocalWorld world);
	
}
