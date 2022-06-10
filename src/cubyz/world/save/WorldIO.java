package cubyz.world.save;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

import cubyz.utils.Logger;
import cubyz.world.World;
import cubyz.world.entity.Entity;
import cubyz.world.entity.PlayerEntity;
import cubyz.world.items.Item;
import pixelguys.json.JsonArray;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

public class WorldIO {
	public static final int WORLD_DATA_VERSION = 1;

	public final File dir;
	private final World world;
	public Palette<Item> itemPalette = new Palette<>(null, null, this);

	public WorldIO(World world, File directory) {
		assert world != null;
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.world = world;
	}

	public boolean hasWorldData() {
		return new File(dir, "world.dat").exists();
	}

	// Load the seed, which is needed before custom item and ore generation.
	public long loadWorldSeed() {
		try {
			JsonObject worldData = JsonParser.parseObjectFromFile(dir+"/world.dat");
			if (worldData.getInt("version", -1) != WORLD_DATA_VERSION) {
				throw new IOException("Cannot read version " + worldData.getInt("version", -1));
			}
			return worldData.getLong("seed", -1);
		} catch (IOException e) {
			Logger.error(e);
			return -1;
		}
	}

	public void loadWorldData() {
		try {
			JsonObject worldData = JsonParser.parseObjectFromFile(dir+"/world.dat");
			if (worldData.getInt("version", -1) != WORLD_DATA_VERSION) {
				throw new IOException("Cannot read version " + worldData.getInt("version", -1));
			}
			itemPalette = new Palette<>(worldData.getObject("itemPalette"), world.registries.itemRegistry, this);

			JsonArray entityJson = worldData.getArrayNoNull("entities");
			
			Entity[] entities = new Entity[entityJson.array.size()];
			for(int i = 0; i < entities.length; i++) {
				// TODO: Only load entities that are in loaded chunks.
				entities[i] = EntityIO.loadEntity((JsonObject)entityJson.array.get(i), world);
			}
			world.setEntities(entities);
			world.setGameTimeCycle(worldData.getBool("doGameTimeCycle", true));
			world.gameTime = worldData.getLong("gameTime", 0);
			JsonObject spawnData = worldData.getObjectOrNew("spawn");
			world.spawn.x = spawnData.getInt("x", 0);
			world.spawn.y = spawnData.getInt("y", Integer.MIN_VALUE);
			world.spawn.z = spawnData.getInt("z", 0);
		} catch (IOException e) {
			Logger.error(e);
		}
	}
	
	public void saveWorldData() {
		try {
			OutputStream out = new FileOutputStream(new File(dir, "world.dat"));
			JsonObject worldData = new JsonObject();
			worldData.put("version", WORLD_DATA_VERSION);
			worldData.put("seed", world.getSeed());
			worldData.put("doGameTimeCycle", world.shouldDoGameTimeCycle());
			worldData.put("gameTime", world.gameTime);
			worldData.put("entityCount", world.getEntities().length);
			worldData.put("itemPalette", itemPalette.save());
			JsonObject spawnData = new JsonObject();
			spawnData.put("x", world.spawn.x);
			spawnData.put("y", world.spawn.y);
			spawnData.put("z", world.spawn.z);
			worldData.put("spawn", spawnData);
			JsonArray entityData = new JsonArray();
			worldData.put("entities", entityData);
			// TODO: Store entities per chunk.
			for (Entity ent : world.getEntities()) {
				if (ent != null && ent.getType().getClass() != PlayerEntity.class) {
					entityData.add(ent.save());
				}
			}
			out.write(worldData.toString().getBytes(StandardCharsets.UTF_8));
			out.close();
		} catch (IOException e) {
			Logger.error(e);
			saveWorldData();
		}
	}

}
