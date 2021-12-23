package cubyz.client;

import org.joml.Vector3d;

import cubyz.world.Chunk;
import cubyz.world.ChunkData;

/**
 * A chunk mesh contains all rendering data of a single chunk.
 */

public abstract class ChunkMesh extends ChunkData {

	public final int size;

	protected final ReducedChunkMesh replacement;

	protected boolean generated = false;

	public ChunkMesh(ReducedChunkMesh replacement, int wx, int wy, int wz, int size) {
		super(wx, wy, wz, size/Chunk.chunkSize);
		this.size = size;
		this.replacement = replacement;
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

	/**
	 * The player position is subtracted before render. This allows the GPU to calculate on floats even if the player is at high coordinates.
	 * @param playerPosition
	 */
	public abstract void render(Vector3d playerPosition);

	/**
	 * Returns the chunk associated with the mesh.
	 * @return chunk. Can be null!
	 */
	public abstract ChunkData getChunk();
}
