package io.cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3f;
import org.joml.Vector4f;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.entity.Entity;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.handler.Handler;
import io.cubyz.handler.PlaceBlockHandler;
import io.cubyz.handler.RemoveBlockHandler;
import io.cubyz.items.ItemStack;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

/**
 * Managing system for the 3d block map of a torus.
 */

public abstract class Surface {
	
	protected StellarTorus torus;
	protected ArrayList<PlaceBlockHandler> placeBlockHandlers = new ArrayList<>();
	protected ArrayList<RemoveBlockHandler> removeBlockHandlers = new ArrayList<>();
	public ArrayList<BlockVisibilityChangeHandler> visibHandlers = new ArrayList<>();
	
	public void addHandler(Handler handler) {
		if (handler instanceof PlaceBlockHandler) {
			placeBlockHandlers.add((PlaceBlockHandler) handler);
		} else if (handler instanceof RemoveBlockHandler) {
			removeBlockHandlers.add((RemoveBlockHandler) handler);
		} else if (handler instanceof BlockVisibilityChangeHandler) {
			visibHandlers.add((BlockVisibilityChangeHandler) handler);
		} else {
			throw new IllegalArgumentException("Handler isn't accepted by surface");
		}
	}
	
	public abstract void removeBlock(int x, int y, int z);
	public abstract void placeBlock(int x, int y, int z, Block b, byte data);
	public abstract void updateBlockData(int x, int y, int z, byte data);
	
	public abstract Block getBlock(int x, int y, int z);
	public abstract byte getBlockData(int x, int y, int z);
	public abstract BlockEntity getBlockEntity(int x, int y, int z);
	
	/**
	 * 
	 * @param action - Chunk action
	 */
	public abstract void queueChunk(NormalChunk ch);
	
	public abstract float getGlobalLighting();

	public abstract Vector3f getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting);
	public abstract void getLight(int x, int y, int z, int[] array);

	public abstract NormalChunk getChunk(int x, int z);
	public abstract Region getRegion(int wx, int wz);
	public abstract Biome getBiome(int x, int z);

	public abstract ReducedChunk[] getReducedChunks();
	public abstract NormalChunk[] getChunks();
	public abstract Block[] getPlanetBlocks();
	public abstract Entity[] getEntities();
	
	public abstract void addEntity(Entity en);
	public abstract void removeEntity(Entity ent);
	
	public abstract int getHeight(int x, int z);
	public abstract void seek(int x, int z, int renderDistance, int highestLOD, float LODFactor);
	
	public abstract void cleanup();
	public abstract void update();
	
	public abstract Vector4f getClearColor();
	
	public abstract CurrentSurfaceRegistries getCurrentRegistries();
	
	public abstract void drop(ItemStack stack, Vector3f pos, Vector3f dir, float vel);
	
	public abstract Biome.Type[][] getBiomeMap();
	
	public abstract ChunkEntityManager getEntityManagerAt(int wx, int wz);
	public abstract ChunkEntityManager[] getEntityManagers();
	
	public int getSizeX() {
		return Integer.MIN_VALUE;
	}
	
	public int getSizeZ() {
		return Integer.MIN_VALUE;
	}
	
	public StellarTorus getStellarTorus() {
		return torus;
	}

	public abstract void getMapData(int x, int z, int width, int height, float[][] heightMap, Biome[][] biomeMap);

	public abstract boolean isValidSpawnLocation(int x, int z);
}
