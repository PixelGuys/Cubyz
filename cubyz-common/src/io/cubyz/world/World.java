package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

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
	
	public static enum ChunkActionType {
		/**
		 * generates the chunk
		 */
		GENERATE,
		/**
		 * loads the chunk
		 */
		LOAD,
		/**
		 * Unloads the chunk
		 */
		UNLOAD;
	}
	
	public static class ChunkAction {
		public Chunk chunk;
		public ChunkActionType type;
		
		public ChunkAction(Chunk chunk, ChunkActionType type) {
			this.chunk = chunk;
			this.type = type;
		}
	}
	
	/**
	 * Used internally, allow the client to know whether or not it should update the visible blocks list.
	 * Mostly unused since recently.
	 */
	public abstract boolean isEdited();
	
	/**
	 * Used internally, allow the client to know whether or not it should update the visible blocks list.
	 * Mostly unused since recently.
	 */
	public abstract void unmarkEdit();
	
	/**
	 * Used internally, allow the client to know whether or not it should update the visible blocks list.
	 * Mostly unused since recently.
	 */
	public abstract void markEdit();
	
	public abstract Player getLocalPlayer();
	
	public int getHeight() {
		return WORLD_HEIGHT;
	}
	
	public abstract Map<Block, ArrayList<BlockInstance>> visibleBlocks();
	public abstract Entity[] getEntities();
	
	public abstract void synchronousSeek(int x, int z);
	public abstract void seek(int x, int z);
	
	/**
	 * 
	 * @param action - Chunk action
	 */
	public abstract void queueChunk(ChunkAction action);
	
	public abstract Chunk getChunk(int x, int z);
	public abstract BlockInstance getBlock(int x, int y, int z);
	public BlockInstance getBlock(Vector3i vec) {
		return getBlock(vec.x, vec.y, vec.z);
	}
	public abstract void removeBlock(int x, int y, int z);
	
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
