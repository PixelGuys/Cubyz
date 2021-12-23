package cubyz.world.save;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;

import cubyz.utils.Logger;
import cubyz.utils.json.JsonArray;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;
import cubyz.world.World;
import cubyz.world.entity.Entity;
import cubyz.world.items.Item;

public class WorldIO {
	public static final int WORLD_DATA_VERSION = 1;

	public final File dir;
	private World world;
	public BlockPalette blockPalette = new BlockPalette(null);
	public Palette<Item> itemPalette = new Palette<Item>(null, null);

	public WorldIO(World world, File directory) {
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
			blockPalette = new BlockPalette(worldData.getObject("blockPalette"));
			itemPalette = new Palette<Item>(worldData.getObject("itemPalette"), world.registries.itemRegistry);

			JsonArray entityJson = worldData.getArrayNoNull("entities");
			
			Entity[] entities = new Entity[entityJson.array.size()];
			for(int i = 0; i < entities.length; i++) {
				// TODO: Only load entities that are in loaded chunks.
				entities[i] = EntityIO.loadEntity((JsonObject)entityJson.array.get(i), world);
			}
			if (world != null) {
				world.setEntities(entities);
			}
			world.setGameTimeCycle(worldData.getBool("doGameTimeCycle", true));
			world.setGameTime(worldData.getLong("gameTime", 0));
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
			worldData.put("gameTime", world.getGameTime());
			worldData.put("entityCount", world == null ? 0 : world.getEntities().length);
			worldData.put("blockPalette", blockPalette.save());
			worldData.put("itemPalette", itemPalette.save());
			JsonArray entityData = new JsonArray();
			worldData.put("entities", entityData);
			if (world != null) {
				for (Entity ent : world.getEntities()) {
					if (ent != null)
						entityData.add(ent.save());
				}
			}
			out.write(worldData.toString().getBytes());
			out.close();
		} catch (IOException e) {
			Logger.error(e);
		}
	}

}
