package io.cubyz.save;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;

import io.cubyz.entity.Entity;
import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.Chunk;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.World;

public class WorldIO {

	private File dir;
	private LocalWorld world;
	private ArrayList<byte[]> blockData = new ArrayList<>();
	private ArrayList<int[]> chunkData = new ArrayList<>();

	public WorldIO(World world, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.world = (LocalWorld) world;

		// RemoteWorld doesn't have to be saved and only blockData is used for remote world (which can be easily overwritten without WorldIO)
		LocalWorld w = (LocalWorld) world;
		w.blockData = blockData;
		w.chunkData = chunkData;
	}

	public boolean hasWorldData() {
		return new File(dir, "world.dat").exists();
	}

	public void loadWorldData() {
		try {
			FileInputStream in = new FileInputStream(new File(dir, "world.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			
			ByteBuffer dst = ByteBuffer.allocate(l);
			in.getChannel().read(dst);
			dst.flip();
			
			NDTContainer ndt = new NDTContainer(dst.array());
			world.setName(ndt.getString("name"));
			world.setHeight(ndt.getInteger("height"));
			world.setSeed(ndt.getInteger("seed"));
			world.setGameTime(ndt.getLong("gameTime"));
			Entity[] entities = new Entity[ndt.getInteger("entityNumber")];
			for (int i = 0; i < entities.length; i++) {
				entities[i] = EntityIO.loadEntity(in);
				entities[i].setWorld(world);
			}
			world.setEntities(entities);
			in.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	public void saveWorldData() {
		try {
			FileOutputStream out = new FileOutputStream(new File(dir, "world.dat"));
			NDTContainer ndt = new NDTContainer();
			ndt.setInteger("version", 1);
			ndt.setString("name", world.getName());
			ndt.setInteger("height", world.getHeight());
			ndt.setInteger("seed", world.getSeed());
			ndt.setLong("gameTime", world.getGameTime());
			ndt.setInteger("entityNumber", world.getEntities().length);
			byte[] len = new byte[4];
			Bits.putInt(len, 0, ndt.getData().length);
			out.write(len);
			out.write(ndt.getData());
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
