package io.cubyz.save;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.world.Chunk;
import io.cubyz.world.World;

public class WorldIO {

	private File dir;
	private World world;
	
	// CHANGING FINAL VARIABLES WILL BREAK COMPATIBILITY WITH EXISTING SAVES!!
	public static final int REGION_RADIUS = 8; // the chunk radius of a "region" file
	
	private class RegionData {
		
		private Chunk[][] chunks = new Chunk[REGION_RADIUS][REGION_RADIUS];
		
		public Chunk getChunk(int x, int z) {
			return chunks[x][z];
		}
		
		public void setChunk(int x, int z, Chunk ch) {
			chunks[x][z] = ch;
		}
		
	}
	
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
			File regions = new File(dir, "regions");
			if (!regions.exists()) {
				regions.mkdir();
			}
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
	
	public void saveChunk(Chunk ch, int x, int z) {
		int rx = (int) Math.floor((double) x / 16);
		int rz = (int) Math.floor((double) z / 16);
		File rf = new File(dir, "regions/r." + rx + "." + rz + ".dat");
		/*
		try {
			System.out.println("Saving..");
			RegionData data = new RegionData();
			if (rf.exists()) {
				DataInputStream dis = new DataInputStream(new FileInputStream(rf));
				for (int i = 0; i < REGION_RADIUS; i++) {
					for (int j = 0; j < REGION_RADIUS; j++) {
						if (!dis.readBoolean()) continue;
						Chunk ck = new Chunk(x + i, z + j, world);
						for (int a = 0; a < 16; a++) {
							for (int c = 0; c < 16; c++) {
								for (int b = 0; b < world.getHeight(); b++) {
									if (dis.readBoolean()) {
										int id = dis.readShort();
										Block bl = (Block) CubyzRegistries.BLOCK_REGISTRY.registered()[id];
										ck.addBlock(bl, a, b, c);
									}
								}
							}
						}
						ck.setLoaded(true);
						data.setChunk(i, j, ck);
					}
				}
				dis.close();
			}
			//System.out.println(world.getHeight());
			data.setChunk(x - (rx*REGION_RADIUS), z - (rz*REGION_RADIUS), ch);
			DataOutputStream dos = new DataOutputStream(new FileOutputStream(rf));
			for (int i = 0; i < REGION_RADIUS; i++) {
				for (int j = 0; j < REGION_RADIUS; j++) {
					Chunk ck = data.getChunk(i, j);
					if (ck == null) {
						dos.writeBoolean(false);
					} else {
						dos.writeBoolean(true);
						for (BlockInstance bi : ck.list()) {
							int lx = bi.getX() & 15;
							int ly = bi.getY();
							int lz = bi.getZ() & 15;
							
						}
						for (int a = 0; a < 16; a++) {
							for (int c = 0; c < 16; c++) {
								for (int b = 0; b < world.getHeight(); b++) {
									BlockInstance inst = ck.getBlockInstanceAt(a, b, c);
									if (inst != null) {
										dos.writeBoolean(true);
										dos.writeShort(CubyzRegistries.BLOCK_REGISTRY.indexOf(inst.getBlock()));
									} else {
										dos.writeBoolean(false);
									}
								}
							}
						}
					}
				}
			}
			dos.close();
		} catch (Exception e) {
			e.printStackTrace();
		}
		*/ // temporaly disabled for being TOO SLOW
	}
	
	public void saveAround(int x, int z) {
		int cx = x / 16;
		int cz = z / 16;
		for (int i = cx - REGION_RADIUS / 2; i < cx + REGION_RADIUS / 2; i++) {
			for (int j = cz - REGION_RADIUS / 2; j < cz + REGION_RADIUS / 2; j++) {
				Chunk ch = world.getChunk(cx, cz);
				if (ch.isGenerated() && ch.isLoaded()) {
					saveChunk(ch, i, j);
				}
			}
		}
	}
	
}
