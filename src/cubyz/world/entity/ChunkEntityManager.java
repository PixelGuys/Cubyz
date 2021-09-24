package cubyz.world.entity;

import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;

/**
 * TODO: Will store a reference to each entity of a chunk.
 */

public class ChunkEntityManager {
	public final int wx, wy, wz;
	public final NormalChunk chunk;
	public final ItemEntityManager itemEntityManager;
	public ChunkEntityManager(ServerWorld world, NormalChunk chunk) {
		wx = chunk.getWorldX();
		wy = chunk.getWorldY();
		wz = chunk.getWorldZ();
		this.chunk = chunk;
		itemEntityManager = chunk.map.mapIO.readItemEntities(world, chunk);
	}
	
	public void update() {
		itemEntityManager.update();
	}
}
