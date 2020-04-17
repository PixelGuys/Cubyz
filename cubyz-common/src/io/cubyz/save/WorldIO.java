package io.cubyz.save;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.LocalTorusSurface;
import io.cubyz.world.LocalWorld;

public class WorldIO {

	private File dir;
	private LocalWorld world;

	public WorldIO(LocalWorld world, File directory) {
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
	public void loadWorldSeed() {
		try {
			InputStream in = new FileInputStream(new File(dir, "world.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			byte[] src = new byte[l];
			in.read(src);
			NDTContainer ndt = new NDTContainer(src);
			if (ndt.getInteger("version") != 2) {
				throw new IOException("Cannot read version " + ndt.getInteger("version"));
			}
			world.setSeed(ndt.getInteger("seed"));
			world.setCurrentTorusID(ndt.getLong("currentTorusID"));
			in.close();
		} catch (IOException e) {
			e.printStackTrace();
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
			world.setName(ndt.getString("name"));
			world.setGameTime(ndt.getLong("gameTime"));
			in.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	public void saveWorldData() {
		try {
			OutputStream out = new FileOutputStream(new File(dir, "world.dat"));
			NDTContainer ndt = new NDTContainer();
			ndt.setInteger("version", 2);
			ndt.setString("name", world.getName());
			ndt.setInteger("seed", world.getSeed());
			ndt.setLong("gameTime", world.getGameTime());
			if (world.getCurrentTorus() != null) {
				ndt.setLong("currentTorusID", world.getCurrentTorus().getSeed());
			}
			byte[] len = new byte[4];
			Bits.putInt(len, 0, ndt.getData().length);
			out.write(len);
			out.write(ndt.getData());
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

}
