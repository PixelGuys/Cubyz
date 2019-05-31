package io.cubyz.save;

import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;

import io.cubyz.entity.Entity;
import io.cubyz.world.Chunk;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.World;

public class WorldIO {

	private File dir;
	private World world;
	private ArrayList<byte[]> blockData = new ArrayList<>();
	private ArrayList<int[]> chunkData = new ArrayList<>();

	public WorldIO(World world, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.world = world;

		// TODO: make this more general to World rather than LocalWorld.
		LocalWorld w = (LocalWorld) world;
		w.blockData = blockData;
		w.chunkData = chunkData;
	}

	public boolean hasWorldData() {
		return new File(dir, "world.dat").exists();
	}

	public void loadWorldData() {
		try {
			DataInputStream in = new DataInputStream(new FileInputStream(new File(dir, "world.dat")));
			world.setName(in.readUTF());
			world.setHeight(in.readInt());
			world.setSeed(in.readInt());
			Entity[] entities = new Entity[in.readInt()];
			for (int i = 0; i < entities.length; i++) {
				entities[i] = EntityIO.loadEntity(in);
			}
			// TODO set entities
			in.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	public void saveWorldData() {
		try {
			DataOutputStream out = new DataOutputStream(new FileOutputStream(new File(dir, "world.dat")));
			out.writeUTF(world.getName());
			out.writeInt(world.getHeight());
			out.writeInt(world.getSeed());
			out.writeInt(world.getEntities().length);
			for (Entity ent : world.getEntities()) {
				EntityIO.saveEntity(ent, out);
			}
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
		try {
			BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(new File(dir, "region.dat")));
			synchronized (blockData) {
				for (byte[] data : blockData) {
					if(data.length > 12) // Only write data if there is any data except the chunk coordinates.
						out.write(data);
				}
			}
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	public void loadAround(int x, int z) {

	}

	public void saveChunk(Chunk ch, int x, int z) {
		byte[] cb = ch.save();
		int[] cd = ch.getData();
		int index = -1;
		synchronized (blockData) {
			for (int i = 0; i < blockData.size(); i++) {
				int[] cd2 = chunkData.get(i);
				if (cd[0] == cd2[0] && cd[1] == cd2[1]) {
					index = i;
					break;
				}
			}
			if (index == -1) {
				blockData.add(cb);
				chunkData.add(cd);
			} else {
				blockData.set(index, cb);
				chunkData.set(index, cd);
			}
		}
	}

}
