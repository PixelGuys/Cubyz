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
import io.cubyz.world.LocalStellarTorus;
import io.cubyz.world.LocalTorusSurface;

public class TorusIO {

	private File dir;
	private LocalStellarTorus torus;
	private LocalTorusSurface surface;
	private ArrayList<byte[]> blockData = new ArrayList<>();
	private ArrayList<int[]> chunkData = new ArrayList<>();

	public TorusIO(LocalStellarTorus torus, File directory) {
		dir = directory;
		if (!dir.exists()) {
			dir.mkdirs();
		}
		this.torus = torus;
	}
	
	public void link() {
		surface = (LocalTorusSurface) torus.getSurface();
		surface.blockData = blockData;
		surface.chunkData = chunkData;
	}

	public boolean hasTorusData() {
		return new File(dir, "torus.dat").exists();
	}

	public void loadTorusData() {
		try {
			InputStream in = new FileInputStream(new File(dir, "torus.dat"));
			byte[] len = new byte[4];
			in.read(len);
			int l = Bits.getInt(len, 0);
			byte[] dst = new byte[l];
			in.read(dst);
			
			NDTContainer ndt = new NDTContainer(dst);
			torus.setName(ndt.getString("name"));
			Entity[] entities = new Entity[ndt.getInteger("entityCount")];
			for (int i = 0; i < entities.length; i++) {
				entities[i] = EntityIO.loadEntity(in);
				entities[i].setStellarTorus(torus);
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
	
	public void saveTorusData() {
		try {
			OutputStream out = new FileOutputStream(new File(dir, "torus.dat"));
			NDTContainer ndt = new NDTContainer();
			ndt.setInteger("version", 1);
			ndt.setString("name", torus.getName());
			ndt.setInteger("entityCount", surface == null ? 0 : surface.getEntities().length);
			byte[] len = new byte[4];
			Bits.putInt(len, 0, ndt.getData().length);
			out.write(len);
			out.write(ndt.getData());
			if (surface != null) {
				for (Entity ent : surface.getEntities()) {
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
					if(data.length > 12) { // Only write data if there is any data except the chunk coordinates.
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
