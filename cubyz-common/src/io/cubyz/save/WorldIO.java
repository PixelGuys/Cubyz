package io.cubyz.save;

import java.io.BufferedOutputStream;
import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.zip.DeflaterOutputStream;
import java.util.zip.InflaterInputStream;

import io.cubyz.entity.Entity;
import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.Chunk;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.World;

// TODO: TorusIO
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
			byte[] dst = new byte[l];
			in.read(dst);
			NDTContainer ndt = new NDTContainer(dst);
			world.setSeed(ndt.getInteger("seed"));
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
			ndt.setInteger("version", 1);
			ndt.setString("name", world.getName());
			ndt.setInteger("seed", world.getSeed());
			ndt.setLong("gameTime", world.getGameTime());
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

}
