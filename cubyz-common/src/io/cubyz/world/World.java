package io.cubyz.world;

import java.util.List;
import org.joml.Vector3i;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;

/**
 * Base class for Cubz worlds.
 * @author zenith391
 *
 */
public abstract class World {

	public static final int WORLD_HEIGHT = 255;
	protected int seed;
	
	public abstract Player getLocalPlayer();
	
	public int getHeight() {
		return WORLD_HEIGHT;
	}
	
	public abstract List<Chunk> getChunks();
	public abstract Block [] getBlocks();
	public abstract Entity[] getEntities();
	
	public abstract void synchronousSeek(int x, int z);
	public abstract void seek(int x, int z);
	
	/**
	 * 
	 * @param action - Chunk action
	 */
	public abstract void queueChunk(Chunk ch);

	public abstract Chunk getChunk(int x, int z);	// Works with world coordinates
	public abstract Chunk _getChunk(int x, int z);	// Works with chunk coordinates
	public abstract BlockInstance getBlock(int x, int y, int z);
	public BlockInstance getBlock(Vector3i vec) {
		return getBlock(vec.x, vec.y, vec.z);
	}
	public abstract void removeBlock(int x, int y, int z);
	public abstract void placeBlock(int x, int y, int z, Block b);
	
	public int getHighestBlock(int x, int z) {
		for (int y = 255; y > 0; y--) {
			if (getBlock(x, y, z) != null) {
				return y;
			}
		}
		return -1; // not generated
	}
	
	public boolean isLocal() {
		return this instanceof LocalWorld;
	}
	
	public void setSeed(int seed) {
		this.seed = seed;
	}
	
	public int getSeed() {
		return seed;
	}
	
	public void setName(String name) {
		throw new UnsupportedOperationException();
	}
	
	public String getName() {
		throw new UnsupportedOperationException();
	}
}
