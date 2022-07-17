package cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;

import cubyz.world.entity.ItemEntityManager;
import cubyz.world.save.BlockPalette;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.api.CurrentWorldRegistries;
import cubyz.utils.datastructures.HashMapKey3D;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.entity.Entity;
import cubyz.world.items.ItemStack;
import cubyz.world.save.WorldIO;
import cubyz.world.terrain.biomes.Biome;
import org.joml.Vector3i;

public abstract class World {
	public static final int DAY_CYCLE = 12000; // Length of one in-game day in 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	public static final float GRAVITY = 9.81F*1.5F;

	protected HashMap<HashMapKey3D, MetaChunk> metaChunks = new HashMap<HashMapKey3D, MetaChunk>();
	protected NormalChunk[] chunks = new NormalChunk[0];
	public ItemEntityManager itemEntityManager;
	protected ArrayList<Entity> entities = new ArrayList<>();
	public BlockPalette blockPalette;
	
	public WorldIO wio;

	protected boolean generated;

	public long gameTime;
	protected long milliTime;
	protected long lastUpdateTime = System.currentTimeMillis();
	protected boolean doGameTimeCycle = true;
	
	protected long seed;

	protected final String name;
	
	boolean liquidUpdate;
	
	BlockEntity[] blockEntities = new BlockEntity[0];
	Integer[] liquids = new Integer[0];
	
	public CurrentWorldRegistries registries;

	public final Vector3i spawn = new Vector3i(0, Integer.MIN_VALUE, 0);
	
	public World(String name) {
		this.name = name;

		milliTime = System.currentTimeMillis();
	}

	public void setGameTimeCycle(boolean value)
	{
		doGameTimeCycle = value;
	}

	public boolean shouldDoGameTimeCycle()
	{
		return doGameTimeCycle;
	}
	public long getSeed() {
		return seed;
	}

	public String getName() {
		return name;
	}

	public Entity[] getEntities() {
		return entities.toArray(new Entity[0]);
	}

	// Returns the blocks, so their meshes can be created and stored.
	public abstract void generate();
	
	public abstract void addEntity(Entity ent);
	public abstract void removeEntity(Entity ent);
	
	public abstract void setEntities(Entity[] arr);
	
	public abstract boolean isValidSpawnLocation(int x, int z);
	
	public abstract void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity);
	
	public abstract void updateBlock(int x, int y, int z, int block);

	public abstract void update();

	public abstract void queueChunks(ChunkData[] chunks);
	
	public abstract MetaChunk getMetaChunk(int wx, int wy, int wz);
	
	public abstract NormalChunk getChunk(int wx, int wy, int wz);

	public final int getBlock(int x, int y, int z) {
		NormalChunk ch = getChunk(x, y, z);
		if (ch != null && ch.isGenerated()) {
			return ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
		} else {
			return 0;
		}
	}

	public abstract BlockEntity getBlockEntity(int x, int y, int z);



	public abstract void cleanup() ;

	public abstract int getHeight(int wx, int wz);

	public abstract CurrentWorldRegistries getCurrentRegistries();

	public abstract Biome getBiome(int wx, int wy, int wz);

	public abstract int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting);

	public abstract void getLight(NormalChunk ch, int x, int y, int z, int[] array);
	
	protected abstract int getLight(NormalChunk ch, int x, int y, int z, int minLight);
}
