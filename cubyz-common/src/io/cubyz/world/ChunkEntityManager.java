package io.cubyz.world;

import io.cubyz.entity.ItemEntityManager;

/**
 * TODO: Will store a reference to each entity of a chunk.
 */

public class ChunkEntityManager {
	public final int wx, wz;
	public final NormalChunk chunk;
	public final ItemEntityManager itemEntityManager;
	public ChunkEntityManager(Surface surface, NormalChunk chunk) {
		wx = chunk.getWorldX();
		wz = chunk.getWorldZ();
		this.chunk = chunk;
		itemEntityManager = new ItemEntityManager(surface, chunk, 1);
	}
	
	public void update() {
		itemEntityManager.update();
	}
}
