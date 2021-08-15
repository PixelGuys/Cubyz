package cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.api.CurrentSurfaceRegistries;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.Entity;
import cubyz.world.handler.BlockVisibilityChangeHandler;
import cubyz.world.handler.Handler;
import cubyz.world.handler.PlaceBlockHandler;
import cubyz.world.handler.RemoveBlockHandler;
import cubyz.world.items.ItemStack;

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
	 * Doesn't check if the chunk is already queued!
	 * @param action - Chunk action
	 */
	public abstract void queueChunk(Chunk ch);
	public abstract void unQueueChunk(Chunk ch);
	
	public abstract float getGlobalLighting();

	public abstract Vector3f getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting);
	public abstract void getLight(int x, int y, int z, int[] array);

	public abstract NormalChunk getChunk(int x, int y, int z);
	public abstract Region getRegion(int wx, int wz, int voxelSize);
	public abstract Biome getBiome(int x, int z);

	public abstract NormalChunk[] getChunks();
	public abstract Block[] getPlanetBlocks();
	public abstract Entity[] getEntities();
	
	public abstract void addEntity(Entity en);
	public abstract void removeEntity(Entity ent);
	
	public abstract int getHeight(int x, int z);
	public abstract void seek(int x, int y, int z, int renderDistance, int regionRenderDistance);
	
	public abstract void cleanup();
	public abstract void update();
	
	public abstract Vector4f getClearColor();
	
	public abstract CurrentSurfaceRegistries getCurrentRegistries();
	
	public abstract void drop(ItemStack stack, Vector3f pos, Vector3f dir, float vel);
	
	public abstract Biome.Type[][] getBiomeMap();
	
	public abstract ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz);
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

	public abstract boolean isValidSpawnLocation(int x, int z);
}
