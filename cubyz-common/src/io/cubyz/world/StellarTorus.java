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

/*
 * STELLAR TORUSES !!1!!!
 */
public abstract class StellarTorus {
	protected int season; // 0=Spring, 1=Summer, 2=Autumn, 3=Winter
	protected World world;
	
	protected ArrayList<PlaceBlockHandler> placeBlockHandlers = new ArrayList<>();
	protected ArrayList<RemoveBlockHandler> removeBlockHandlers = new ArrayList<>();
	public ArrayList<BlockVisibilityChangeHandler> visibHandlers = new ArrayList<>();
	
	public int DAYCYCLE;

	public abstract void cleanup();
	
	public void addHandler(Handler handler) {
		if (handler instanceof PlaceBlockHandler) {
			placeBlockHandlers.add((PlaceBlockHandler) handler);
		} else if (handler instanceof RemoveBlockHandler) {
			removeBlockHandlers.add((RemoveBlockHandler) handler);
		} else if (handler instanceof BlockVisibilityChangeHandler) {
			visibHandlers.add((BlockVisibilityChangeHandler) handler);
		} else {
			throw new IllegalArgumentException("Handler isn't accepted by Planet");
		}
	}
	
	public abstract List<Chunk> getChunks();
	public abstract Chunk [] getVisibleChunks();
	public abstract Block [] getPlanetBlocks();
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
	public abstract Chunk _getNoGenerateChunk(int x, int z);
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
	
	public abstract long getLocalSeed();

	public int getAnd() {
		return -1; // WorldAnd of maximum supported world size.
	}
	
	public int getHighestBlock(int x, int z) {
		for (int y = World.WORLD_HEIGHT; y > 0; y--) {
			if (getBlock(x, y, z) != null) {
				return y;
			}
		}
		return -1; // not generated
	}
	
	public int getSeason() {
		return season;
	}
	
	public void setName(String name) {}
	
	public String getName() {return "";}
	
	public World getWorld() {
		return world;
	}
	
	public void update() {}
}
