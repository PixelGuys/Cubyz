package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;

import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.handler.Handler;
import io.cubyz.handler.PlaceBlockHandler;
import io.cubyz.handler.RemoveBlockHandler;

/**
 * Base class for Cubyz worlds.
 * @author zenith391
 *
 */
public abstract class World {

	public static final int WORLD_HEIGHT = 256;
	protected int seed;
	protected int season; // 0=Spring, 1=Summer, 2=Autumn, 3=Winter
	
	protected ArrayList<PlaceBlockHandler> placeBlockHandlers = new ArrayList<>();
	protected ArrayList<RemoveBlockHandler> removeBlockHandlers = new ArrayList<>();
	public ArrayList<BlockVisibilityChangeHandler> visibHandlers = new ArrayList<>();
	
	public abstract Player getLocalPlayer();

	public abstract void cleanup();
	
	public void addHandler(Handler handler) {
		if (handler instanceof PlaceBlockHandler) {
			placeBlockHandlers.add((PlaceBlockHandler) handler);
		} else if (handler instanceof RemoveBlockHandler) {
			removeBlockHandlers.add((RemoveBlockHandler) handler);
		} else if (handler instanceof BlockVisibilityChangeHandler) {
			visibHandlers.add((BlockVisibilityChangeHandler) handler);
		} else {
			throw new IllegalArgumentException("handler isn't accepted by World");
		}
	}
	
	public abstract List<Chunk> getChunks();
	public abstract Chunk [] getVisibleChunks();
	public abstract Block [] getBlocks();
	public abstract Entity[] getEntities();
	public abstract void addEntity(Entity en);
	
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
		for (int y = WORLD_HEIGHT; y > 0; y--) {
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
	
	public int getSeason() {
		return season;
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
