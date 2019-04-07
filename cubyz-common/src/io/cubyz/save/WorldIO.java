package io.cubyz.save;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.world.Chunk;
import io.cubyz.world.World;

public class WorldIO {

	private File dir;
	private World world;
	
	// CHANGING THE FOLLOWING VARIABLE WILL BREAK COMPATIBILITY WITH EXISTING SAVES!!
	public static final int REGION_RADIUS = 16; // the chunk radius of a "region" file
	
	public WorldIO(World world, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.world = world;
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
	}
	
	public void loadAround(int x, int z) {
		
	}
	
	public void saveAround(int x, int z) {
		int cx = x / 16;
		int cz = z / 16;
		for (int i = cx - REGION_RADIUS / 2; i < cx + REGION_RADIUS / 2; i++) {
			for (int j = cz - REGION_RADIUS / 2; j < cz + REGION_RADIUS / 2; j++) {
				Chunk ch = world.getChunk(cx, cz);
				if (ch.isGenerated() && ch.isLoaded()) {
					
				}
			}
		}
	}
	
}
