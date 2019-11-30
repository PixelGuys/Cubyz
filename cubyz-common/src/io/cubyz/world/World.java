package io.cubyz.world;

import java.util.List;

import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;

/**
 * Base class for Cubyz worlds.
 * @author zenith391
 *
 */
public abstract class World {

	public static final int WORLD_HEIGHT = 255;
	protected int height = WORLD_HEIGHT;
	protected int seed;
	
	public abstract Player getLocalPlayer();
	
	public void setHeight(int height) {
		this.height = height;
	}
	
	public int getHeight() {
		return height;
	}

	public abstract void cleanup();
	
	public abstract List<Chunk> getChunks();
	public abstract Chunk [] getVisibleChunks();
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
	public abstract Block getBlock(int x, int y, int z);
	/**
	 * ONLY USE IF NEEDED!
	 * @param x
	 * @param y
	 * @param z
	 * @return
	 */
	public abstract BlockInstance getBlockInstance(int x, int y, int z);
	public abstract BlockEntity getBlockEntity(int x, int y, int z);
	
	public Block getBlock(Vector3i vec) {
		return getBlock(vec.x, vec.y, vec.z);
	}
	
	public abstract void removeBlock(int x, int y, int z);
	public abstract void placeBlock(int x, int y, int z, Block b);
	
	public abstract float getGlobalLighting();
	public abstract Vector4f getClearColor();
	public abstract long getGameTime();
	public abstract void setGameTime(long time);
	
	public int getHighestBlock(int x, int z) {
		for (int y = getHeight(); y > 0; y--) {
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
	
	public abstract void setRenderDistance(int RD);
	public abstract int getRenderDistance();
	
	public void update() {}
}
