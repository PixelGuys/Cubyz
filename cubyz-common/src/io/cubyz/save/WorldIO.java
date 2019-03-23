package io.cubyz.save;

import java.io.DataOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

import io.cubyz.world.World;

public class WorldIO {

	private File dir;
	private World world;
	
	// CHANGING THE FOLLOWING VARIABLE WILL BREAK COMPATIBILITY WITH EXISTING SAVES!!
	private static final int SAVE_CHUNK_RADIUS = 16; // the chunk radius of a "region" file
	
	public WorldIO(World world, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.world = world;
	}
	
	public void saveWorldData() {
		try {
			DataOutputStream out = new DataOutputStream(new FileOutputStream(new File(dir, "world.dat")));
			out.writeUTF(world.getName());
			out.writeInt(world.getHeight());
			out.writeInt(world.getSeed());
			
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	public void saveAround(int x, int z) {
		
	}
	
}
