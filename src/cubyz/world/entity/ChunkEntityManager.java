package cubyz.world.entity;

import cubyz.world.NormalChunk;
import cubyz.world.World;

/**
 * TODO: Will store a reference to each entity of a chunk.
 */

public class ChunkEntityManager {
	public final int wx, wy, wz;
	public final NormalChunk chunk;
	public final ItemEntityManager itemEntityManager;
	public ChunkEntityManager(World world, NormalChunk chunk) {
		wx = chunk.wx;
		wy = chunk.wy;
		wz = chunk.wz;
		this.chunk = chunk;
		itemEntityManager = chunk.map.mapIO.readItemEntities(world, chunk);
	}
	
	public void update(float deltaTime) {
		itemEntityManager.update(deltaTime);
	}
}
