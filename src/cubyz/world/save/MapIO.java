package cubyz.world.save;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.zip.DeflaterOutputStream;
import java.util.zip.InflaterInputStream;

import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.NormalChunk;
import cubyz.world.World;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.terrain.MapFragment;

/**
 * Handles saving and loading of all Chunks within a Region.
 */

public class MapIO {
	private final File dir;
	private final WorldIO wio;
	private int[][] heightMap;
	
	public MapIO(MapFragment map, WorldIO wio) {
		this.wio = wio;
		dir = new File(wio.dir.getAbsolutePath()+"/"+map.wx+","+map.wz);
	}
	
	public void loadHeightMap(MapFragment map) {
		heightMap = new int[MapFragment.MAP_SIZE][MapFragment.MAP_SIZE];
		if (dir.exists() && new File(dir+"/height.dat").exists()) {
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
				Logger.error(e);
			}
		} else {
			for(int x = 0; x < MapFragment.MAP_SIZE; x++) {
				for(int z = 0; z < MapFragment.MAP_SIZE; z++) {
					heightMap[x][z] = (int)map.getHeight(x, z);
				}
			}
		}
	}
	
	public void saveData() {
		if (!dir.exists()) dir.mkdirs();
		// Save height map:
		if (heightMap != null) {
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
				Logger.error(e);
			}
		}
	}
	
	public ItemEntityManager readItemEntities(World world, NormalChunk chunk) {
		File file = new File(dir, "itemEnt"+chunk.wx+" "+chunk.wy+" "+chunk.wz);
		if (!file.exists()) return new ItemEntityManager(world, chunk, 1);
		try {
			byte[] data = new byte[(int) file.length()];
			DataInputStream stream = new DataInputStream(new FileInputStream(file));
			stream.readFully(data);
			stream.close();
			return new ItemEntityManager(world, chunk, data, wio.itemPalette);
		} catch (IOException e) {
			Logger.error(e);
		}
		return new ItemEntityManager(world, chunk, 1);
	}
	
	public void saveItemEntities(ItemEntityManager manager) {
		if (manager.size == 0) return;
		File file = new File(dir, "itemEnt"+manager.chunk.wx+" "+manager.chunk.wy+" "+manager.chunk.wz);
		if (!dir.exists()) dir.mkdirs();
		try {
			BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(file));
			byte[] data = manager.store(wio.itemPalette);
			out.write(data);
			out.close();
		} catch (IOException e) {
			Logger.error(e);
		}
	}
	
	public int getHeight(int wx, int wz, MapFragment map) {
		wx &= MapFragment.MAP_MASK;
		wz &= MapFragment.MAP_MASK;
		if (heightMap == null) this.loadHeightMap(map);
		return heightMap[wx][wz];
	}
	
	public void setHeight(int wx, int wz, int height, MapFragment map) {
		wx &= MapFragment.MAP_MASK;
		wz &= MapFragment.MAP_MASK;
		if (heightMap == null) this.loadHeightMap(map);
		heightMap[wx][wz] = height;
	}
}
