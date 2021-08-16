package cubyz.world.save;

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

import cubyz.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.NormalChunk;
import cubyz.world.Surface;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.terrain.MapFragment;

/**
 * Handles saving and loading of all Chunks within a Region.
 */

public class MapIO {
	private ArrayList<byte[]> blockData;
	private ArrayList<int[]> chunkData;
	private final File dir;
	private final TorusIO tio;
	private int[][] heightMap;
	
	public MapIO(MapFragment map, TorusIO tio) {
		this.tio = tio;
		dir = new File(tio.dir.getAbsolutePath()+"/"+map.wx+","+map.wz);
	}
	
	public void loadHeightMap(MapFragment map) {
		heightMap = new int[MapFragment.MAP_SIZE][MapFragment.MAP_SIZE];
		if(dir.exists()) {
			try {
				InputStream in = new BufferedInputStream(new InflaterInputStream(new FileInputStream(dir+"/height.dat")));
				byte[] data = new byte[MapFragment.MAP_SIZE*MapFragment.MAP_SIZE*4];
				in.read(data);
				int index = 0;
				for(int x = 0; x < MapFragment.MAP_SIZE; x++) {
					for(int z = 0; z < MapFragment.MAP_SIZE; z++) {
						heightMap[x][z] = Bits.getInt(data, index);
						index += 4;
					}
				}
				in.close();
			} catch (IOException e) {
				Logger.throwable(e);
			}
		} else {
			for(int x = 0; x < MapFragment.MAP_SIZE; x++) {
				for(int z = 0; z < MapFragment.MAP_SIZE; z++) {
					heightMap[x][z] = (int)map.getHeight(x, z);
				}
			}
		}
	}
	
	public ArrayList<BlockChange> transformData(byte[] data) {
		int size = Bits.getInt(data, 12);
		ArrayList<BlockChange> list = new ArrayList<BlockChange>(size);
		for (int i = 0; i < size; i++) {
			try {
				list.add(new BlockChange(data, 16 + i*9, tio.blockPalette));
			} catch (MissingBlockException e) {
				// If the block is missing, we replace it by nothing
				int off = 16 + i*9;
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
					
					int cx = Bits.getInt(data, 0);
					int cy = Bits.getInt(data, 4);
					int cz = Bits.getInt(data, 8);
					int[] ckData = new int[] {cx, cy, cz};
					chunkData.add(ckData);
				}
				in.close();
			} catch (IOException e) {
				Logger.throwable(e);
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
					if (data.length > 16)
						l++;
				Bits.putInt(len, 0, l);
				out.write(len);
				for (byte[] data : blockData) {
					if(data.length > 16) { // Only write data if there is any data other than the chunk coordinates.
						byte[] b = new byte[4];
						Bits.putInt(b, 0, data.length);
						out.write(b);
						out.write(data);
					}
				}
			}
			out.close();
		} catch (IOException e) {
			Logger.throwable(e);
		}
		// Save height map:
		if(dir.exists() && heightMap != null) {
			try {
				BufferedOutputStream out = new BufferedOutputStream(new DeflaterOutputStream(new FileOutputStream(dir+"/height.dat")));
				byte[] data = new byte[MapFragment.MAP_SIZE*MapFragment.MAP_SIZE*4];
				int index = 0;
				for(int x = 0; x < MapFragment.MAP_SIZE; x++) {
					for(int z = 0; z < MapFragment.MAP_SIZE; z++) {
						Bits.putInt(data, index, heightMap[x][z]);
						index += 4;
					}
				}
				out.write(data);
				out.close();
			} catch (IOException e) {
				Logger.throwable(e);
			}
		}
	}
	
	public ArrayList<BlockChange> getBlockChanges(int cx, int cy, int cz) {
		if(blockData == null) {
			readFile();
		}
		int index = -1;
		for(int i = 0; i < chunkData.size(); i++) {
			int [] arr = chunkData.get(i);
			if(arr[0] == cx && arr[1] == cy && arr[2] == cz) {
				index = i;
				break;
			}
		}
		if(index == -1) {
			byte[] dummy = new byte[16];
			Bits.putInt(dummy, 0, cx);
			Bits.putInt(dummy, 4, cy);
			Bits.putInt(dummy, 8, cz);
			Bits.putInt(dummy, 12, 0);
			return transformData(dummy);
		}
		return transformData(blockData.get(index));
	}

	public void saveChunk(NormalChunk ch) {
		byte[] cb = ch.save(tio.blockPalette);
		int[] cd = ch.getData();
		if(cb.length <= 16) return;
		int index = -1;
		synchronized (blockData) {
			for (int i = 0; i < blockData.size(); i++) {
				int[] cd2 = chunkData.get(i);
				if (cd[0] == cd2[0] && cd[1] == cd2[1] && cd[2] == cd2[2]) {
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
		File file = new File(dir, "itemEnt"+chunk.getWorldX()+" "+chunk.getWorldY()+" "+chunk.getWorldZ());
		if(!file.exists()) return new ItemEntityManager(surface, chunk, 1);
		try {
			byte[] data = new byte[(int) file.length()];
			DataInputStream stream = new DataInputStream(new FileInputStream(file));
			stream.readFully(data);
			stream.close();
			return new ItemEntityManager(surface, chunk, data, tio.itemPalette);
		} catch (IOException e) {
			Logger.throwable(e);
		}
		return new ItemEntityManager(surface, chunk, 1);
	}
	
	public void saveItemEntities(ItemEntityManager manager) {
		if(manager.size == 0) return;
		File file = new File(dir, "itemEnt"+manager.chunk.getWorldX()+" "+manager.chunk.getWorldY()+" "+manager.chunk.getWorldZ());
		if(!dir.exists()) dir.mkdirs();
		try {
			BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(file));
			byte[] data = manager.store(tio.itemPalette);
			out.write(data);
			out.close();
		} catch (IOException e) {
			Logger.throwable(e);
		}
	}
	
	public int getHeight(int wx, int wz, MapFragment map) {
		wx &= MapFragment.MAP_MASK;
		wz &= MapFragment.MAP_MASK;
		if(heightMap == null) this.loadHeightMap(map);
		return heightMap[wx][wz];
	}
	
	public void setHeight(int wx, int wz, int height, MapFragment map) {
		wx &= MapFragment.MAP_MASK;
		wz &= MapFragment.MAP_MASK;
		if(heightMap == null) this.loadHeightMap(map);
		heightMap[wx][wz] = height;
	}
}
