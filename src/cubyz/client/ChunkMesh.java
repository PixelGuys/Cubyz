package cubyz.client;

import cubyz.world.Chunk;

public abstract class ChunkMesh {

	public final int wx, wy, wz, size;

	protected final ReducedChunkMesh replacement;

	public ChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		this.replacement = replacement;
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		this.size = size;
	}

	public abstract boolean needsUpdate();
	public abstract void cleanUp();
	public abstract void regenerateMesh();
	public abstract void render();
	public abstract Chunk getChunk();
}
