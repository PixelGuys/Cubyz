package io.cubyz.save;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.zip.DeflaterOutputStream;
import java.util.zip.InflaterInputStream;

import io.cubyz.entity.ItemEntityManager;
import io.cubyz.math.Bits;
import io.cubyz.world.Region;
import io.cubyz.world.Surface;
import io.cubyz.world.NormalChunk;

/**
 * Handles saving and loading of all Chunks within a Region.
 */

public class RegionIO {
	private ArrayList<byte[]> blockData;
	private ArrayList<int[]> chunkData;
	private final File dir;
	private final TorusIO tio;
	
	public RegionIO(Region region, TorusIO tio) {
		this.tio = tio;
		dir = new File(tio.dir.getAbsolutePath()+"/"+region.wx+","+region.wz);
	}
	
	public ArrayList<BlockChange> transformData(byte[] data) {
		int size = Bits.getInt(data, 8);
		ArrayList<BlockChange> list = new ArrayList<BlockChange>(size);
		for (int i = 0; i < size; i++) {
			try {
				list.add(new BlockChange(data, 12 + i*9, tio.blockPalette));
			} catch (MissingBlockException e) {
				// If the block is missing, we replace it by nothing
				int off = 12 + i*9;
				int index = Bits.getInt(data, off + 0);
				list.add(new BlockChange(-2, -1, index, (byte)0, (byte)0));
			}
		}
		return list;
	}
	
	private void readFile() {
		blockData = new ArrayList<>();
		chunkData = new ArrayList<>();
		if(dir.exists()) {
			try {
				InputStream in = new BufferedInputStream(new InflaterInputStream(new FileInputStream(dir+"/blocks.dat")));
				// read block data
				byte[] len = new byte[4];
				in.read(len);
				int l = Bits.getInt(len, 0);
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
	}
	
	public void saveData() {
		if(blockData == null) return;
		if(!dir.exists()) dir.mkdirs();
		try {
			BufferedOutputStream out = new BufferedOutputStream(new DeflaterOutputStream(new FileOutputStream(new File(dir, "blocks.dat"))));
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
	
	public ArrayList<BlockChange> getBlockChanges(int cx, int cz) {
		if(blockData == null) {
			readFile();
		}
		int index = -1;
		for(int i = 0; i < chunkData.size(); i++) {
			int [] arr = chunkData.get(i);
			if(arr[0] == cx && arr[1] == cz) {
				index = i;
				break;
			}
		}
		if(index == -1) {
			byte[] dummy = new byte[12];
			Bits.putInt(dummy, 0, cx);
			Bits.putInt(dummy, 4, cz);
			Bits.putInt(dummy, 8, 0);
			return transformData(dummy);
		}
		return transformData(blockData.get(index));
	}

	public void saveChunk(NormalChunk ch) {
		byte[] cb = ch.save(tio.blockPalette);
		int[] cd = ch.getData();
		if(cb.length <= 12) return;
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
	
	public ItemEntityManager readItemEntities(Surface surface, NormalChunk chunk) {
		File file = new File(dir, "itemEnt"+chunk.getWorldX()+" "+chunk.getWorldZ());
		if(!file.exists()) return new ItemEntityManager(surface, chunk, 1);
		try {
			byte[] data = new byte[(int) file.length()];
			DataInputStream stream = new DataInputStream(new InflaterInputStream(new FileInputStream(file)));
			stream.readFully(data);
			stream.close();
			return new ItemEntityManager(surface, chunk, data, tio.itemPalette);
		} catch (IOException e) {
			e.printStackTrace();
		}
		return new ItemEntityManager(surface, chunk, 1);
	}
	
	public void saveItemEntities(ItemEntityManager manager) {
		if(manager.size == 0) return;
		File file = new File(dir, "itemEnt"+manager.chunk.getWorldX()+" "+manager.chunk.getWorldZ());
		if(!dir.exists()) dir.mkdirs();
		try {
			BufferedOutputStream out = new BufferedOutputStream(new DeflaterOutputStream(new FileOutputStream(file)));
			out.write(manager.store(tio.itemPalette));
			out.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}
}
