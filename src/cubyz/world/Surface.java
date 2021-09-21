package cubyz.world;

import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.api.CurrentSurfaceRegistries;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.Entity;
import cubyz.world.items.ItemStack;
import cubyz.world.terrain.MapFragment;

/**
 * Managing system for the 3d block map of a torus.
 */

public abstract class Surface {
	
	protected StellarTorus torus;
	
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
	public abstract MapFragment getMapFragment(int wx, int wz, int voxelSize);
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
	
	public abstract ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz);
	public abstract ChunkEntityManager[] getEntityManagers();
	
	public StellarTorus getStellarTorus() {
		return torus;
	}

	public abstract boolean isValidSpawnLocation(int x, int z);
}
