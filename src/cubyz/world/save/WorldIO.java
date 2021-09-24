package cubyz.world.save;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import cubyz.Logger;
import cubyz.utils.math.Bits;
import cubyz.utils.ndt.NDTContainer;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;
import cubyz.world.entity.Entity;
import cubyz.world.items.Item;

public class WorldIO {

	final File dir;
	private ServerWorld world;
	public Palette<Block> blockPalette = new Palette<Block>(null, null);
	public Palette<Item> itemPalette = new Palette<Item>(null, null);

	public WorldIO(ServerWorld world, File directory) {
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
			InputStream in = new FileInputStream(new File(dir, "world.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			byte[] src = new byte[l];
			in.read(src);
			NDTContainer ndt = new NDTContainer(src);
			if (ndt.getInteger("version") != 3) {
				in.close();
				throw new IOException("Cannot read version " + ndt.getInteger("version"));
			}
			in.close();
			return ndt.getLong("seed");
		} catch (IOException e) {
			Logger.error(e);
			return -1;
		}
	}

	public void loadWorldData() {
		try {
			InputStream in = new FileInputStream(new File(dir, "world.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			byte[] dst = new byte[l];
			in.read(dst);
			
			NDTContainer ndt = new NDTContainer(dst);
			if (ndt.getInteger("version") < 3) {
				in.close();
				throw new RuntimeException("World is out-of-date");
			}
			blockPalette = new Palette<Block>(ndt.getContainer("blockPalette"), world.registries.blockRegistry);
			itemPalette = new Palette<Item>(ndt.getContainer("itemPalette"), world.registries.itemRegistry);
			Entity[] entities = new Entity[ndt.getInteger("entityCount")];
			for (int i = 0; i < entities.length; i++) {
				// TODO: Only load entities that are in loaded chunks.
				entities[i] = EntityIO.loadEntity(in, world);
			}
			if (world != null) {
				world.setEntities(entities);
			}
			world.setGameTime(ndt.getLong("gameTime"));
			in.close();
		} catch (IOException e) {
			Logger.error(e);
		}
	}
	
	public void saveWorldData() {
		try {
			OutputStream out = new FileOutputStream(new File(dir, "world.dat"));
			NDTContainer ndt = new NDTContainer();
			ndt.setInteger("version", 3);
			ndt.setLong("seed", world.getSeed());
			ndt.setLong("gameTime", world.getGameTime());
			ndt.setInteger("entityCount", world == null ? 0 : world.getEntities().length);
			ndt.setContainer("blockPalette", blockPalette.saveTo(new NDTContainer()));
			ndt.setContainer("itemPalette", itemPalette.saveTo(new NDTContainer()));
			byte[] len = new byte[4];
			Bits.putInt(len, 0, ndt.getData().length);
			out.write(len);
			out.write(ndt.getData());

			if (world != null) {
				for (Entity ent : world.getEntities()) {
					if(ent != null)
						EntityIO.saveEntity(ent, out);
				}
			}
			out.close();
		} catch (IOException e) {
			Logger.error(e);
		}
	}

}
