package cubyz.client;

import cubyz.world.Chunk;

/**
 * A chunk mesh contains all rendering data of a single chunk.
 */

public abstract class ChunkMesh implements Comparable<ChunkMesh> {

	public final int wx, wy, wz, size;

	protected final ReducedChunkMesh replacement;

	protected float priority = 0;

	protected boolean generated = false;

	public ChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		this.replacement = replacement;
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		this.size = size;
	}

	public void updatePriority(float priority) {
		this.priority = priority;
	}

	/**
	 * Removes all data from the GPU.
	 * MUST BE CALLED BEFORE GETTING RID OF THE OBJECT!
	 */
	public abstract void cleanUp();
	
	/**
	 * Updates the Mesh based on changes of the chunk.
	 */
	public abstract void regenerateMesh();

	public abstract void render();

	/**
	 * Returns the chunk associated with the mesh.
	 * @return chunk. Can be null!
	 */
	public abstract Chunk getChunk();

	@Override
	public int compareTo(ChunkMesh arg0) {
		return (int)Math.signum(priority - arg0.priority);
	}
}
