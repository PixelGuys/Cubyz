package cubyz.world;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Random;

import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;

import cubyz.utils.Logger;
import cubyz.Settings;
import cubyz.api.ClientConnection;
import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.client.ClientSettings;
import cubyz.client.GameLauncher;
import cubyz.modding.ModLoader;
import cubyz.utils.datastructures.HashMapKey3D;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.Entity;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.entity.Player;
import cubyz.world.handler.PlaceBlockHandler;
import cubyz.world.handler.RemoveBlockHandler;
import cubyz.world.items.BlockDrop;
import cubyz.world.items.ItemStack;
import cubyz.world.save.ChunkIO;
import cubyz.world.save.WorldIO;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;
import cubyz.server.Server;

public abstract class World {
	public static final int DAY_CYCLE = 12000; // Length of one in-game day in 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	public static final float GRAVITY = 9.81F*1.5F;

	protected HashMap<HashMapKey3D, MetaChunk> metaChunks = new HashMap<HashMapKey3D, MetaChunk>();
	protected NormalChunk[] chunks = new NormalChunk[0];
	protected ChunkEntityManager[] entityManagers = new ChunkEntityManager[0];
	protected int lastX = Integer.MAX_VALUE, lastY = Integer.MAX_VALUE, lastZ = Integer.MAX_VALUE; // Chunk coordinates of the last chunk update.
	protected ArrayList<Entity> entities = new ArrayList<>();
	
	WorldIO wio;
	
	public ChunkManager chunkManager;
	protected boolean generated;

	protected long gameTime;
	protected long milliTime;
	protected long lastUpdateTime = System.currentTimeMillis();
	protected boolean doGameTimeCycle = true;
	
	protected long seed;

	protected final String name;

	protected Player player;

	public ClientConnection clientConnection = GameLauncher.logic;
	
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);
	
	public final Class<?> chunkProvider;
	
	boolean liquidUpdate;
	
	BlockEntity[] blockEntities = new BlockEntity[0];
	Integer[] liquids = new Integer[0];
	
	public CurrentWorldRegistries registries;
	
	public World(String name, Class<?> chunkProvider) {
		this.name = name;
		this.chunkProvider = chunkProvider;

		// Check if the chunkProvider is valid:
		if (!NormalChunk.class.isAssignableFrom(chunkProvider) ||
				chunkProvider.getConstructors().length != 1 ||
				chunkProvider.getConstructors()[0].getParameterTypes().length != 4 ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[0].equals(World.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[1].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[2].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[3].equals(Integer.class))
			throw new IllegalArgumentException("Chunk provider "+chunkProvider+" is invalid! It needs to be a subclass of NormalChunk and MUST contain a single constructor with parameters (ServerWorld, Integer, Integer, Integer)");
		milliTime = System.currentTimeMillis();

	}
	public Player getLocalPlayer() {
		return player;
	}
	public void setGameTime(long time) {
		gameTime = time;
	}

	public long getGameTime() {
		return gameTime;
	}
	public void setGameTimeCycle(boolean value)
	{
		doGameTimeCycle = value;
	}

	public boolean shouldDoGameTimeCycle()
	{
		return doGameTimeCycle;
	}
	public ChunkEntityManager[] getEntityManagers() {
		return entityManagers;
	}
	public long getSeed() {
		return seed;
	}

	public float getGlobalLighting() {
		return ambientLight;
	}

	public Vector4f getClearColor() {
		return clearColor;
	}

	public String getName() {
		return name;
	}
	public NormalChunk[] getChunks() {
		return chunks;
	}

	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}

	// Returns the blocks, so their meshes can be created and stored.
	public abstract void generate();
	public abstract void forceSave();
	
	public abstract void addEntity(Entity ent);
	public abstract void removeEntity(Entity ent);
	
	public abstract void setEntities(Entity[] arr);
	
	public abstract boolean isValidSpawnLocation(int x, int z);
	
	public abstract void removeBlock(int x, int y, int z);
	
	public abstract void placeBlock(int x, int y, int z, int b);
	
	public abstract void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity, int pickupCooldown);
	
	public abstract void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity);
	
	public abstract void updateBlock(int x, int y, int z, int block);

	public abstract void update();

	public abstract void queueChunk(ChunkData ch);
	
	public abstract void unQueueChunk(ChunkData ch);
	
	public abstract int getChunkQueueSize();
	
	public abstract void seek(int x, int y, int z, int renderDistance, int regionRenderDistance);
	
	public abstract MetaChunk getMetaChunk(int wx, int wy, int wz);
	
	public abstract NormalChunk getChunk(int wx, int wy, int wz);

	public abstract ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz);
	


	public abstract int getBlock(int x, int y, int z) ;


	public abstract BlockEntity getBlockEntity(int x, int y, int z);



	public abstract void cleanup() ;

	public abstract int getHeight(int wx, int wz);

	public abstract CurrentWorldRegistries getCurrentRegistries();

	public abstract Biome getBiome(int wx, int wz);

	public abstract int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting);

	public abstract void getLight(NormalChunk ch, int x, int y, int z, int[] array);
	
	protected abstract int getLight(NormalChunk ch, int x, int y, int z, int minLight);
}
