package cubyz.world;

import cubyz.Settings;
import cubyz.api.CurrentWorldRegistries;
import cubyz.modding.ModLoader;
import cubyz.multiplayer.Protocols;
import cubyz.server.Server;
import cubyz.server.User;
import cubyz.utils.FastRandom;
import cubyz.utils.Logger;
import cubyz.utils.Utils;
import cubyz.utils.datastructures.HashMapKey3D;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.*;
import cubyz.world.items.ItemStack;
import cubyz.world.save.BlockPalette;
import cubyz.world.save.ChunkIO;
import cubyz.world.save.WorldIO;
import cubyz.world.terrain.CaveBiomeMapFragment;
import cubyz.world.terrain.InterpolatableCaveBiomeMap;
import cubyz.world.terrain.biomes.Biome;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

import org.joml.Vector3d;
import org.joml.Vector3f;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;

public class ServerWorld extends World {
	public ChunkManager chunkManager;

	public ServerWorld(String name, JsonObject generatorSettings) {
		super(name);

		if(generatorSettings == null) {
			generatorSettings = JsonParser.parseObjectFromFile("saves/" + name + "/generatorSettings.json");
		} else {
			// Store generator settings:
			Logger.debug("Store");
			JsonParser.storeToFile(generatorSettings, "saves/" + name + "/generatorSettings.json");
		}

		wio = new WorldIO(this, new File("saves/" + name));
		blockPalette = new BlockPalette(JsonParser.parseObjectFromFile("saves/" + name + "/palette.json").getObjectOrNew("blocks"));
		if (wio.hasWorldData()) {
			seed = wio.loadWorldSeed();
			generated = true;
			registries = new CurrentWorldRegistries(this, "saves/" + name + "/assets/", blockPalette);
		} else {
			seed = new FastRandom(System.nanoTime()).nextInt();
			registries = new CurrentWorldRegistries(this, "saves/" + name + "/assets/", blockPalette);
			wio.saveWorldData();
		}
		JsonParser.storeToFile(blockPalette.save(), "saves/" + name + "/palette.json");

		// Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
		ModLoader.postWorldGen(registries);

		chunkManager = new ChunkManager(this, generatorSettings);
		generate();
	}

	// Returns the blocks, so their meshes can be created and stored.
	@Override
	public void generate() {

		wio.loadWorldData(); // load data here in order for entities to also be loaded.

		if (generated) {
			wio.saveWorldData();
		}
		generated = true;

		if (spawn.y == Integer.MIN_VALUE) {
			FastRandom rnd = new FastRandom(System.nanoTime());
			Logger.info("Finding position..");
			int tryCount = 0;
			while (tryCount < 1000) {
				spawn.x = rnd.nextInt(65536);
				spawn.z = rnd.nextInt(65536);
				Logger.info("Trying " + spawn.x + " ? " + spawn.z);
				if (isValidSpawnLocation(spawn.x, spawn.z))
					break;
				tryCount++;
			}
			spawn.y = (int)chunkManager.getOrGenerateMapFragment(spawn.x, spawn.z, 1).getHeight(spawn.x, spawn.z);
		}
		wio.saveWorldData();
	}

	public Player findPlayer(User user) {
		JsonObject playerData = JsonParser.parseObjectFromFile("saves/" + name + "/players/" + Utils.escapeFolderName(user.name) + ".json");
		Player player = new Player(this, user.name);
		addEntity(player);
		if(playerData.map.isEmpty()) {
			// Generate a new player:
			player.setPosition(spawn);
		} else {
			player.loadFrom(playerData);
		}
		return player;
	}

	private void savePlayers() {
		for(User user : Server.users) {
			try {
				File file = new File("saves/" + name + "/players/" + Utils.escapeFolderName(user.name) + ".json");
				file.getParentFile().mkdirs();
				PrintWriter writer = new PrintWriter(new FileOutputStream("saves/" + name + "/players/" + Utils.escapeFolderName(user.name) + ".json"), false, StandardCharsets.UTF_8);
				user.player.save().writeObjectToStream(writer);
				writer.close();
			} catch(FileNotFoundException e) {
				Logger.error(e);
			}
		}
	}

	public void forceSave() {
		for(MetaChunk chunk : metaChunks.values()) {
			if (chunk != null) chunk.save();
		}
		wio.saveWorldData();
		savePlayers();
		chunkManager.forceSave();
		ChunkIO.save();
	}
	@Override
	public void addEntity(Entity ent) {
		entities.add(ent);
	}
	@Override
	public void removeEntity(Entity ent) {
		entities.remove(ent);
	}
	@Override
	public void setEntities(Entity[] arr) {
		entities = new ArrayList<>(arr.length);
		for (Entity e : arr) {
			entities.add(e);
		}
	}
	@Override
	public boolean isValidSpawnLocation(int x, int z) {
		return chunkManager.getOrGenerateMapFragment(x, z, 32).getBiome(x, z).isValidPlayerSpawn;
	}
	@Override
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity, int pickupCooldown) {
		ItemEntityManager manager = this.getEntityManagerAt((int)pos.x & ~Chunk.chunkMask, (int)pos.y & ~Chunk.chunkMask, (int)pos.z & ~Chunk.chunkMask).itemEntityManager;
		manager.add(pos.x, pos.y, pos.z, dir.x*velocity, dir.y*velocity, dir.z*velocity, stack, Server.UPDATES_PER_SEC*300, pickupCooldown);
	}
	@Override
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity) {
		drop(stack, pos, dir, velocity, 0);
	}
	@Override
	public void updateBlock(int x, int y, int z, int newBlock) {
		NormalChunk ch = getChunk(x, y, z);
		if (ch != null) {
			int old = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
			if(old == newBlock) return;
			Logger.error("Block drops aren't implemented in multiplayer yet");
			ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, newBlock);
			// Send the block update to all players:
			for(User user : Server.users) {
				Protocols.BLOCK_UPDATE.send(user, x, y, z, newBlock);
			}
		}
	}
	@Override
	public void setGameTime(long time) {
		gameTime = time;
	}
	@Override
	public long getGameTime() {
		return gameTime;
	}
	@Override
	public void setGameTimeCycle(boolean value)
	{
		doGameTimeCycle = value;
	}
	@Override
	public boolean shouldDoGameTimeCycle()
	{
		return doGameTimeCycle;
	}
	@Override
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

		seek();
	}
	@Override
	public void queueChunk(ChunkData ch) {
		chunkManager.queueChunk(ch);
	}

	public void seek() {
		// Care about the metaChunks:
		HashMap<HashMapKey3D, MetaChunk> oldMetaChunks = new HashMap<HashMapKey3D, MetaChunk>(metaChunks);
		HashMap<HashMapKey3D, MetaChunk> newMetaChunks = new HashMap<HashMapKey3D, MetaChunk>();
		for(User user : Server.users) {
			ArrayList<NormalChunk> chunkList = new ArrayList<>();
			ArrayList<ChunkEntityManager> managers = new ArrayList<>();
			int metaRenderDistance = (int)Math.ceil(Settings.entityDistance/(float)(MetaChunk.metaChunkSize*Chunk.chunkSize));
			int x0 = (int)user.player.getPosition().x >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
			int y0 = (int)user.player.getPosition().y >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
			int z0 = (int)user.player.getPosition().z >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
			for(int metaX = x0 - metaRenderDistance; metaX <= x0 + metaRenderDistance + 1; metaX++) {
				for(int metaY = y0 - metaRenderDistance; metaY <= y0 + metaRenderDistance + 1; metaY++) {
					for(int metaZ = z0 - metaRenderDistance; metaZ <= z0 + metaRenderDistance + 1; metaZ++) {
						HashMapKey3D key = new HashMapKey3D(metaX, metaY, metaZ);
						if(newMetaChunks.containsKey(key)) continue; // It was already updated from another players perspective.
						// Check if it already exists:
						MetaChunk metaChunk = oldMetaChunks.get(key);
						oldMetaChunks.remove(key);
						if (metaChunk == null) {
							metaChunk = new MetaChunk(metaX *(MetaChunk.metaChunkSize*Chunk.chunkSize), metaY*(MetaChunk.metaChunkSize*Chunk.chunkSize), metaZ *(MetaChunk.metaChunkSize*Chunk.chunkSize), this);
						}
						newMetaChunks.put(key, metaChunk);
						metaChunk.update(Settings.entityDistance, chunkList, managers);
					}
				}
			}
			oldMetaChunks.forEach((key, chunk) -> {
				chunk.clean();
			});
			chunks = chunkList.toArray(new NormalChunk[0]);
			entityManagers = managers.toArray(new ChunkEntityManager[0]);
			metaChunks = newMetaChunks;
		}
	}
	@Override
	public MetaChunk getMetaChunk(int wx, int wy, int wz) {
		// Test if the metachunk exists:
		int metaX = wx >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
		int metaY = wy >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
		int metaZ = wz >> (MetaChunk.metaChunkShift + Chunk.chunkShift);
		HashMapKey3D key = new HashMapKey3D(metaX, metaY, metaZ);
		return metaChunks.get(key);
	}
	@Override
	public NormalChunk getChunk(int wx, int wy, int wz) {
		MetaChunk meta = getMetaChunk(wx, wy, wz);
		if (meta != null) {
			return meta.getChunk(wx, wy, wz);
		}
		return null;
	}
	@Override
	public ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz) {
		MetaChunk meta = getMetaChunk(wx, wy, wz);
		if (meta != null) {
			return meta.getEntityManager(wx, wy, wz);
		}
		return null;
	}
	@Override
	public ChunkEntityManager[] getEntityManagers() {
		return entityManagers;
	}
	@Override
	public long getSeed() {
		return seed;
	}
	@Override
	public String getName() {
		return name;
	}
	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		/*BlockInstance bi = getBlockInstance(x, y, z);
		Chunk ck = _getNoGenerateChunk(bi.getX() >> NormalChunk.chunkShift, bi.getZ() >> NormalChunk.chunkShift);
		return ck.blockEntities().get(bi);*/
		return null; // TODO: Work on BlockEntities!
	}
	public NormalChunk[] getChunks() {
		return chunks;
	}
	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[0]);
	}
	@Override
	public int getHeight(int wx, int wz) {
		return (int)chunkManager.getOrGenerateMapFragment(wx, wz, 1).getHeight(wx, wz);
	}
	@Override
	public void cleanup() {
		// Be sure to dereference and finalize the maximum of things
		try {
			for(MetaChunk chunk : metaChunks.values()) {
				if (chunk != null) chunk.clean();
			}
			chunkManager.forceSave();
			ChunkIO.save();

			chunkManager.cleanup();

			ChunkIO.clean();
			
			wio.saveWorldData();
			savePlayers();
			metaChunks = null;
		} catch (Exception e) {
			Logger.error(e);
		}
	}
	@Override
	public CurrentWorldRegistries getCurrentRegistries() {
		return registries;
	}
	@Override
	public Biome getBiome(int wx, int wy, int wz) {
		return new InterpolatableCaveBiomeMap(new ChunkData(
			wx & ~CaveBiomeMapFragment.CAVE_BIOME_MASK,
			wy & ~CaveBiomeMapFragment.CAVE_BIOME_MASK,
			wz & ~CaveBiomeMapFragment.CAVE_BIOME_MASK, 1
		), 0).getRoughBiome(wx, wy, wz, null, true);
	}
	@Override
	@Deprecated
	public int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		NormalChunk ch = getChunk(x, y, z);
		if (ch == null || !ch.isLoaded() || !easyLighting)
			return 0xffffffff;
		return ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
	}
	@Override
	@Deprecated
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
	@Override
	@Deprecated
	protected int getLight(NormalChunk ch, int x, int y, int z, int minLight) {
		if (x - ch.wx != (x & Chunk.chunkMask) || y - ch.wy != (y & Chunk.chunkMask) || z - ch.wz != (z & Chunk.chunkMask))
			ch = getChunk(x, y, z);
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
