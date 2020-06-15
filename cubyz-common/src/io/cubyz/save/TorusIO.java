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
import java.util.HashMap;
import java.util.zip.DeflaterOutputStream;
import java.util.zip.InflaterInputStream;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.entity.Entity;
import io.cubyz.math.Bits;
import io.cubyz.ndt.NDTContainer;
import io.cubyz.world.Chunk;
import io.cubyz.world.LocalStellarTorus;
import io.cubyz.world.LocalSurface;

public class TorusIO {

	private File dir;
	private LocalStellarTorus torus;
	private ArrayList<byte[]> blockData = new ArrayList<>();
	private ArrayList<int[]> chunkData = new ArrayList<>();
	public HashMap<Block, Integer> blockPalette = new HashMap<>();

	public TorusIO(LocalStellarTorus torus, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.torus = torus;
	}
	
	public void link(LocalSurface surface) {
		surface.blockData = blockData;
		surface.chunkData = chunkData;
	}

	public boolean hasTorusData() {
		return new File(dir, "torus.dat").exists();
	}

	public void loadTorusData(LocalSurface surface) {
		try {
			InputStream in = new FileInputStream(new File(dir, "torus.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			byte[] dst = new byte[l];
			in.read(dst);
			
			NDTContainer ndt = new NDTContainer(dst);
			if (ndt.getInteger("version") < 2) {
				throw new RuntimeException("World is out-of-date");
			}
			torus.setName(ndt.getString("name"));
			NDTContainer blockPaletteNdt = ndt.getContainer("blockPalette");
			for (String key : blockPaletteNdt.keys()) {
				Block b = CubyzRegistries.BLOCK_REGISTRY.getByID(key);
				if (b != null) {
					blockPalette.put(b, blockPaletteNdt.getInteger(key));
				} else {
					CubyzLogger.instance.warning("A block with ID " + key + " is used in world but isn't available.");
				}
			}
			Entity[] entities = new Entity[ndt.getInteger("entityCount")];
			for (int i = 0; i < entities.length; i++) {
				// TODO: Only load entities that are in loaded chunks.
				entities[i] = EntityIO.loadEntity(in, surface);
			}
			if (surface != null) {
				surface.setEntities(entities);
			}
			in.close();
			in = new BufferedInputStream(new InflaterInputStream(new FileInputStream(new File(dir, "region.dat"))));
			// read block data
			in.read(len);
			l = Bits.getInt(len, 0);
			for (int i = 0; i < l; i++) {
				byte[] b = new byte[4];
				in.read(b);
				int ln = Bits.getInt(b, 0);
				byte[] data = new byte[ln];
				in.read(data);
				blockData.add(data);
				
				int ox = Bits.getInt(data, 0);
				int oz = Bits.getInt(data, 4);
				int[] ckData = new int[] {ox, oz};
				chunkData.add(ckData);
			}
			in.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
	
	public void saveTorusData(LocalSurface surface) {
		try {
			OutputStream out = new FileOutputStream(new File(dir, "torus.dat"));
			NDTContainer ndt = new NDTContainer();
			ndt.setInteger("version", 2);
			ndt.setString("name", torus.getName());
			ndt.setInteger("entityCount", surface == null ? 0 : surface.getEntities().length);
			NDTContainer blockPaletteNdt = new NDTContainer();
			for (Block b : blockPalette.keySet()) {
				blockPaletteNdt.setInteger(b.getRegistryID().toString(), blockPalette.get(b));
			}
			ndt.setContainer("blockPalette", blockPaletteNdt);
			byte[] len = new byte[4];
			Bits.putInt(len, 0, ndt.getData().length);
			out.write(len);
			out.write(ndt.getData());
			if (surface != null) {
				for (Entity ent : surface.getEntities()) {
					if(ent != null)
						EntityIO.saveEntity(ent, out);
				}
			}
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
		try {
			BufferedOutputStream out = new BufferedOutputStream(new DeflaterOutputStream(new FileOutputStream(new File(dir, "region.dat"))));
			synchronized (blockData) {
				byte[] len = new byte[4];
				int l = 0;
				for (byte[] data : blockData)
					if (data.length > 12)
						l++;
				Bits.putInt(len, 0, l);
				out.write(len);
				for (byte[] data : blockData) {
					if(data.length > 12) { // Only write data if there is any data other than the chunk coordinates.
						byte[] b = new byte[4];
						Bits.putInt(b, 0, data.length);
						out.write(b);
						out.write(data);
					}
				}
			}
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	public void saveChunk(Chunk ch) {
		byte[] cb = ch.save(blockPalette);
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
