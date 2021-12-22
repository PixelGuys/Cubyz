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

public class ServerWorld {
	public static final int DAY_CYCLE = 12000; // Length of one in-game day in 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	public static final float GRAVITY = 9.81F*1.5F;

	private HashMap<HashMapKey3D, MetaChunk> metaChunks = new HashMap<HashMapKey3D, MetaChunk>();
	private NormalChunk[] chunks = new NormalChunk[0];
	private ChunkEntityManager[] entityManagers = new ChunkEntityManager[0];
	private int lastX = Integer.MAX_VALUE, lastY = Integer.MAX_VALUE, lastZ = Integer.MAX_VALUE; // Chunk coordinates of the last chunk update.
	private ArrayList<Entity> entities = new ArrayList<>();
	
	final WorldIO wio;
	
	public final ChunkManager chunkManager;
	private boolean generated;

	private long gameTime;
	private long milliTime;
	private long lastUpdateTime = System.currentTimeMillis();
	private boolean doGameTimeCycle = true;
	
	private final long seed;

	private final String name;

	private Player player;

	public ClientConnection clientConnection = GameLauncher.logic;
	
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);
	
	public final Class<?> chunkProvider;
	
	boolean liquidUpdate;
	
	BlockEntity[] blockEntities = new BlockEntity[0];
	Integer[] liquids = new Integer[0];
	
	public CurrentWorldRegistries registries;
	
	public ServerWorld(String name, JsonObject generatorSettings, Class<?> chunkProvider) {
		if(generatorSettings == null) {
			generatorSettings = JsonParser.parseObjectFromFile("saves/" + name + "/generatorSettings.json");
		} else {
			// Store generator settings:
			Logger.debug("Store");
			JsonParser.storeToFile(generatorSettings, "saves/" + name + "/generatorSettings.json");
		}
		this.name = name;
		this.chunkProvider = chunkProvider;
		// Check if the chunkProvider is valid:
		if (!NormalChunk.class.isAssignableFrom(chunkProvider) ||
				chunkProvider.getConstructors().length != 1 ||
				chunkProvider.getConstructors()[0].getParameterTypes().length != 4 ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[0].equals(ServerWorld.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[1].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[2].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[3].equals(Integer.class))
			throw new IllegalArgumentException("Chunk provider "+chunkProvider+" is invalid! It needs to be a subclass of NormalChunk and MUST contain a single constructor with parameters (ServerWorld, Integer, Integer, Integer)");
		
		wio = new WorldIO(this, new File("saves/" + name));
		milliTime = System.currentTimeMillis();
		if (wio.hasWorldData()) {
			seed = wio.loadWorldSeed();
			generated = true;
			registries = new CurrentWorldRegistries(this);
		} else {
			seed = new Random().nextInt();
			registries = new CurrentWorldRegistries(this);
			wio.saveWorldData();
		}
		// Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
		ModLoader.postWorldGen(registries);

		chunkManager = new ChunkManager(this, generatorSettings, Runtime.getRuntime().availableProcessors() - 1);
	}

	// Returns the blocks, so their meshes can be created and stored.
	public void generate() {

		wio.loadWorldData(); // load data here in order for entities to also be loaded.
		
		if (generated) {
			wio.saveWorldData();
		}
		generated = true;

		for (Entity ent : getEntities()) {
			if (ent instanceof Player) {
				player = (Player) ent;
			}
		}

		if (player == null) {
			player = (Player) CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity(this);
			addEntity(player);
			Random rnd = new Random();
			int dx = 0;
			int dz = 0;
			Logger.info("Finding position..");
			int tryCount = 0;
			while (tryCount < 1000) {
				dx = rnd.nextInt(65536);
				dz = rnd.nextInt(65536);
				Logger.info("Trying " + dx + " ? " + dz);
				if (isValidSpawnLocation(dx, dz))
					break;
				tryCount++;
			}
			int startY = (int)chunkManager.getOrGenerateMapFragment((int)dx, (int)dz, 1).getHeight(dx, dz);
			seek((int)dx, startY, (int)dz, ClientSettings.RENDER_DISTANCE, ClientSettings.EFFECTIVE_RENDER_DISTANCE*Chunk.chunkSize*2);
			player.setPosition(new Vector3i(dx, startY+2, dz));
			Logger.info("OK!");
		}
		wio.saveWorldData();
	}

	public Player getLocalPlayer() {
		return player;
	}

	
	public void forceSave() {
		for(MetaChunk chunk : metaChunks.values()) {
			if (chunk != null) chunk.save();
		}
		wio.saveWorldData();
		chunkManager.forceSave();
		ChunkIO.save();
	}
	
	public void addEntity(Entity ent) {
		entities.add(ent);
	}
	
	public void removeEntity(Entity ent) {
		entities.remove(ent);
	}
	
	public void setEntities(Entity[] arr) {
		entities = new ArrayList<>(arr.length);
		for (Entity e : arr) {
			entities.add(e);
		}
	}
	
	public boolean isValidSpawnLocation(int x, int z) {
        int radius = 3;
        boolean found = false;
        for (int i = x - radius; i <= x + radius; i++) {
            for (int j = z - radius; j <= z + radius; j++) {
                found = chunkManager.getOrGenerateMapFragment(i, j, 1).getBiome(i, j).isValidPlayerSpawn;
            }
        }
        return found;
	}
	
	public void removeBlock(int x, int y, int z) {
		NormalChunk ch = getChunk(x >> Chunk.chunkShift, y >> Chunk.chunkShift, z >> Chunk.chunkShift);
		if (ch != null) {
			int b = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
			ch.removeBlockAt(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, true);
			for (RemoveBlockHandler hand : CubyzRegistries.REMOVE_HANDLER_REGISTRY.registered(new RemoveBlockHandler[0])) {
				hand.onBlockRemoved(this, b, x, y, z);
			}
			// Fetch block drops:
			for(BlockDrop drop : Blocks.blockDrops(b)) {
				int amount = (int)(drop.amount);
				float randomPart = drop.amount - amount;
				if (Math.random() < randomPart) amount++;
				if (amount > 0) {
					ItemEntityManager manager = this.getEntityManagerAt(x & ~Chunk.chunkMask, y & ~Chunk.chunkMask, z & ~Chunk.chunkMask).itemEntityManager;
					manager.add(x, y, z, 0, 0, 0, new ItemStack(drop.item, amount), 30*300 /*5 minutes at normal update speed.*/);
				}
			}
		}
	}
	
	public void placeBlock(int x, int y, int z, int b) {
		NormalChunk ch = getChunk(x >> Chunk.chunkShift, y >> Chunk.chunkShift, z >> Chunk.chunkShift);
		if (ch != null) {
			ch.addBlock(b, x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, false);
			for (PlaceBlockHandler hand : CubyzRegistries.PLACE_HANDLER_REGISTRY.registered(new PlaceBlockHandler[0])) {
				hand.onBlockPlaced(this, b, x, y, z);
			}
		}
	}
	
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity, int pickupCooldown) {
		ItemEntityManager manager = this.getEntityManagerAt((int)pos.x & ~Chunk.chunkMask, (int)pos.y & ~Chunk.chunkMask, (int)pos.z & ~Chunk.chunkMask).itemEntityManager;
		manager.add(pos.x, pos.y, pos.z, dir.x*velocity, dir.y*velocity, dir.z*velocity, stack, Server.UPDATES_PER_SEC*300 /*5 minutes at normal update speed.*/, pickupCooldown);
	}
	
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity) {
		drop(stack, pos, dir, velocity, 0);
	}
	
	public void updateBlock(int x, int y, int z, int block) {
		NormalChunk ch = getChunk(x >> Chunk.chunkShift, y >> Chunk.chunkShift, z >> Chunk.chunkShift);
		if (ch != null) {
			ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, block);
		}
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
	
	public void update() {
		long newTime = System.currentTimeMillis();
		float deltaTime = (newTime - lastUpdateTime)/1000.0f;
		lastUpdateTime = newTime;
		if (deltaTime > 0.3f) {
			Logger.warning("Update time is getting too high. It's already at "+deltaTime+" s!");
			deltaTime = 0.3f;
		}
		
		if (milliTime + 100 < newTime) {
			milliTime += 100;
			if (doGameTimeCycle) gameTime++; // gameTime is measured in 100ms.
		}
		if (milliTime < newTime - 1000) {
			Logger.warning("Behind update schedule by " + (newTime - milliTime) / 1000.0f + "s!");
			milliTime = newTime - 1000; // so we don't accumulate too much time to catch
		}
		int dayCycle = ServerWorld.DAY_CYCLE;
		// Ambient light
		{
			int dayTime = Math.abs((int)(gameTime % dayCycle) - (dayCycle >> 1));
			if (dayTime < (dayCycle >> 2)-(dayCycle >> 4)) {
				ambientLight = 0.1f;
				clearColor.x = clearColor.y = clearColor.z = 0;
			} else if (dayTime > (dayCycle >> 2)+(dayCycle >> 4)) {
				ambientLight = 1.0f;
				clearColor.x = clearColor.y = 0.8f;
				clearColor.z = 1.0f;
			} else {
				//b:
				if (dayTime > (dayCycle >> 2)) {
					clearColor.z = 1.0f*(dayTime-(dayCycle >> 2))/(dayCycle >> 4);
				} else {
					clearColor.z = 0.0f;
				}
				//g:
				if (dayTime > (dayCycle >> 2)+(dayCycle >> 5)) {
					clearColor.y = 0.8f;
				} else if (dayTime > (dayCycle >> 2)-(dayCycle >> 5)) {
					clearColor.y = 0.8f+0.8f*(dayTime-(dayCycle >> 2)-(dayCycle >> 5))/(dayCycle >> 4);
				} else {
					clearColor.y = 0.0f;
				}
				//r:
				if (dayTime > (dayCycle >> 2)) {
					clearColor.x = 0.8f;
				} else {
					clearColor.x = 0.8f+0.8f*(dayTime-(dayCycle >> 2))/(dayCycle >> 4);
				}
				dayTime -= (dayCycle >> 2);
				dayTime <<= 3;
				ambientLight = 0.55f + 0.45f*dayTime/(dayCycle >> 1);
			}
		}
		// Entities
		for (int i = 0; i < entities.size(); i++) {
			Entity en = entities.get(i);
			en.update(deltaTime);
			// Check item entities:
			if (en.getInventory() != null) {
				int x0 = (int)(en.getPosition().x - en.width) & ~Chunk.chunkMask;
				int y0 = (int)(en.getPosition().y - en.width) & ~Chunk.chunkMask;
				int z0 = (int)(en.getPosition().z - en.width) & ~Chunk.chunkMask;
				int x1 = (int)(en.getPosition().x + en.width) & ~Chunk.chunkMask;
				int y1 = (int)(en.getPosition().y + en.width) & ~Chunk.chunkMask;
				int z1 = (int)(en.getPosition().z + en.width) & ~Chunk.chunkMask;
				if (getEntityManagerAt(x0, y0, z0) != null)
					getEntityManagerAt(x0, y0, z0).itemEntityManager.checkEntity(en);
				if (x0 != x1) {
					if (getEntityManagerAt(x1, y0, z0) != null)
						getEntityManagerAt(x1, y0, z0).itemEntityManager.checkEntity(en);
					if (y0 != y1) {
						if (getEntityManagerAt(x0, y1, z0) != null)
							getEntityManagerAt(x0, y1, z0).itemEntityManager.checkEntity(en);
						if (getEntityManagerAt(x1, y1, z0) != null)
							getEntityManagerAt(x1, y1, z0).itemEntityManager.checkEntity(en);
						if (z0 != z1) {
							if (getEntityManagerAt(x0, y0, z1) != null)
								getEntityManagerAt(x0, y0, z1).itemEntityManager.checkEntity(en);
							if (getEntityManagerAt(x1, y0, z1) != null)
								getEntityManagerAt(x1, y0, z1).itemEntityManager.checkEntity(en);
							if (getEntityManagerAt(x0, y1, z1) != null)
								getEntityManagerAt(x0, y1, z1).itemEntityManager.checkEntity(en);
							if (getEntityManagerAt(x1, y1, z1) != null)
								getEntityManagerAt(x1, y1, z1).itemEntityManager.checkEntity(en);
						}
					}
				} else if (y0 != y1) {
					if (getEntityManagerAt(x0, y1, z0) != null)
						getEntityManagerAt(x0, y1, z0).itemEntityManager.checkEntity(en);
					if (z0 != z1) {
						if (getEntityManagerAt(x0, y0, z1) != null)
							getEntityManagerAt(x0, y0, z1).itemEntityManager.checkEntity(en);
						if (getEntityManagerAt(x0, y1, z1) != null)
							getEntityManagerAt(x0, y1, z1).itemEntityManager.checkEntity(en);
					}
				} else if (z0 != z1) {
					if (getEntityManagerAt(x0, y0, z1) != null)
						getEntityManagerAt(x0, y0, z1).itemEntityManager.checkEntity(en);
				}
			}
		}
		// Item Entities
		for(int i = 0; i < entityManagers.length; i++) {
			entityManagers[i].itemEntityManager.update(deltaTime);
		}
		// Block Entities
		for(MetaChunk chunk : metaChunks.values()) {
			chunk.updateBlockEntities();
		}
		
		// Liquids
		if (gameTime % 3 == 0) {
			//Profiler.startProfiling();
			for(MetaChunk chunk : metaChunks.values()) {
				chunk.liquidUpdate();
			}
			//Profiler.printProfileTime("liquid-update");
		}

		// Send updates to the player:
		// TODO: Multiplayer
		for(NormalChunk ch : chunks) {
			if (ch.updated && ch.generated) {
				ch.updated = false;
				clientConnection.updateChunkMesh(ch);
			}
		}
	}

	public void queueChunk(ChunkData ch) {
		chunkManager.queueChunk(ch);
	}
	
	public void unQueueChunk(ChunkData ch) {
		chunkManager.unQueueChunk(ch);
	}
	
	public int getChunkQueueSize() {
		return chunkManager.getChunkQueueSize();
	}
	
	public void seek(int x, int y, int z, int renderDistance, int regionRenderDistance) {
		int xOld = x;
		int yOld = y;
		int zOld = z;
		
		// Care about the metaChunks:
		if (x != lastX || y != lastY || z != lastZ) {
			ArrayList<NormalChunk> chunkList = new ArrayList<>();
			ArrayList<ChunkEntityManager> managers = new ArrayList<>();
			HashMap<HashMapKey3D, MetaChunk> oldMetaChunks = new HashMap<HashMapKey3D, MetaChunk>(metaChunks);
			HashMap<HashMapKey3D, MetaChunk> newMetaChunks = new HashMap<HashMapKey3D, MetaChunk>();
			int metaRenderDistance = (int)Math.ceil(renderDistance/(float)(MetaChunk.metaChunkSize*Chunk.chunkSize));
			int x0 = x >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
			int y0 = y >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
			int z0 = z >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
			for(int metaX = x0 - metaRenderDistance; metaX <= x0 + metaRenderDistance + 1; metaX++) {
				for(int metaY = y0 - metaRenderDistance; metaY <= y0 + metaRenderDistance + 1; metaY++) {
					for(int metaZ = z0 - metaRenderDistance; metaZ <= z0 + metaRenderDistance + 1; metaZ++) {
						int xReal = metaX;
						int zReal = metaZ;
						HashMapKey3D key = new HashMapKey3D(xReal, metaY, zReal);
						// Check if it already exists:
						MetaChunk metaChunk = oldMetaChunks.get(key);
						oldMetaChunks.remove(key);
						if (metaChunk == null) {
							metaChunk = new MetaChunk(xReal*(MetaChunk.metaChunkSize*Chunk.chunkSize), metaY*(MetaChunk.metaChunkSize*Chunk.chunkSize), zReal*(MetaChunk.metaChunkSize*Chunk.chunkSize), this);
						}
						newMetaChunks.put(key, metaChunk);
						metaChunk.updatePlayer(xOld, yOld, zOld, renderDistance, Settings.entityDistance, chunkList, managers);
					}
				}
			}
			oldMetaChunks.forEach((key, chunk) -> {
				chunk.clean();
			});
			chunks = chunkList.toArray(new NormalChunk[0]);
			entityManagers = managers.toArray(new ChunkEntityManager[0]);
			metaChunks = newMetaChunks;
			lastX = xOld;
			lastY = yOld;
			lastZ = zOld;
		}
	}
	
	public MetaChunk getMetaChunk(int cx, int cy, int cz) {
		// Test if the metachunk exists:
		int metaX = cx >> (MetaChunk.metaChunkShift);
		int metaY = cy >> (MetaChunk.metaChunkShift);
		int metaZ = cz >> (MetaChunk.metaChunkShift);
		HashMapKey3D key = new HashMapKey3D(metaX, metaY, metaZ);
		return metaChunks.get(key);
	}
	
	public NormalChunk getChunk(int cx, int cy, int cz) {
		MetaChunk meta = getMetaChunk(cx, cy, cz);
		if (meta != null) {
			return meta.getChunk(cx, cy, cz);
		}
		return null;
	}

	public ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz) {
		int cx = wx >> Chunk.chunkShift;
		int cy = wy >> Chunk.chunkShift;
		int cz = wz >> Chunk.chunkShift;
		MetaChunk meta = getMetaChunk(cx, cy, cz);
		if (meta != null) {
			return meta.getEntityManager(cx, cy, cz);
		}
		return null;
	}
	
	public ChunkEntityManager[] getEntityManagers() {
		return entityManagers;
	}

	public int getBlock(int x, int y, int z) {
		NormalChunk ch = getChunk(x >> Chunk.chunkShift, y >> Chunk.chunkShift, z >> Chunk.chunkShift);
		if (ch != null && ch.isGenerated()) {
			int b = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
			return b;
		} else {
			return 0;
		}
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

	public BlockEntity getBlockEntity(int x, int y, int z) {
		/*BlockInstance bi = getBlockInstance(x, y, z);
		Chunk ck = _getNoGenerateChunk(bi.getX() >> NormalChunk.chunkShift, bi.getZ() >> NormalChunk.chunkShift);
		return ck.blockEntities().get(bi);*/
		return null; // TODO: Work on BlockEntities!
	}

	public NormalChunk[] getChunks() {
		return chunks;
	}
	
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	public int getHeight(int wx, int wz) {
		return (int)chunkManager.getOrGenerateMapFragment(wx, wz, 1).getHeight(wx, wz);
	}

	public void cleanup() {
		// Be sure to dereference and finalize the maximum of things
		try {
			for(MetaChunk chunk : metaChunks.values()) {
				if (chunk != null) chunk.clean();
			}
			wio.saveWorldData();
			chunkManager.forceSave();
			ChunkIO.save();

			chunkManager.cleanup();
			
			ChunkIO.clean();
			
			metaChunks = null;
		} catch (Exception e) {
			Logger.error(e);
		}
	}

	public CurrentWorldRegistries getCurrentRegistries() {
		return registries;
	}

	public Biome getBiome(int wx, int wz) {
		MapFragment reg = chunkManager.getOrGenerateMapFragment(wx, wz, 1);
		return reg.getBiome(wx, wz);
	}

	public int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		NormalChunk ch = getChunk(x >> Chunk.chunkShift, y >> Chunk.chunkShift, z >> Chunk.chunkShift);
		if (ch == null || !ch.isLoaded() || !easyLighting)
			return 0xffffffff;
		return ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
	}

	public void getLight(NormalChunk ch, int x, int y, int z, int[] array) {
		int block = getBlock(x, y, z);
		if (block == 0) return;
		int selfLight = Blocks.light(block);
		x--;
		y--;
		z--;
		for(int ix = 0; ix < 3; ix++) {
			for(int iy = 0; iy < 3; iy++) {
				for(int iz = 0; iz < 3; iz++) {
					array[ix + iy*3 + iz*9] = getLight(ch, x+ix, y+iy, z+iz, selfLight);
				}
			}
		}
	}
	
	private int getLight(NormalChunk ch, int x, int y, int z, int minLight) {
		if (x - ch.wx != (x & Chunk.chunkMask) || y - ch.wy != (y & Chunk.chunkMask) || z - ch.wz != (z & Chunk.chunkMask))
			ch = getChunk(x >> Chunk.chunkShift, y >> Chunk.chunkShift, z >> Chunk.chunkShift);
		if (ch == null || !ch.isLoaded())
			return 0xff000000;
		int light = ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
		// Make sure all light channels are at least as big as the minimum:
		if ((light & 0xff000000) >>> 24 < (minLight & 0xff000000) >>> 24) light = (light & 0x00ffffff) | (minLight & 0xff000000);
		if ((light & 0x00ff0000) < (minLight & 0x00ff0000)) light = (light & 0xff00ffff) | (minLight & 0x00ff0000);
		if ((light & 0x0000ff00) < (minLight & 0x0000ff00)) light = (light & 0xffff00ff) | (minLight & 0x0000ff00);
		if ((light & 0x000000ff) < (minLight & 0x000000ff)) light = (light & 0xffffff00) | (minLight & 0x000000ff);
		return light;
	}
}
