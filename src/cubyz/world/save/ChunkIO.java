package cubyz.world.save;

import cubyz.utils.datastructures.Cache;
import cubyz.world.Chunk;
import cubyz.world.ChunkData;
import cubyz.world.ServerWorld;

public class ChunkIO {
	private static final int HASH_MASK = 7;
	private static Cache<RegionFile> regionCache = new Cache<>(new RegionFile[HASH_MASK+1][4]);
	
	private static RegionFile getOrLoadRegionFile(ServerWorld world, int wx, int wy, int wz, int voxelSize) {
		wx = RegionFile.findCoordinate(wx, voxelSize);
		wy = RegionFile.findCoordinate(wy, voxelSize);
		wz = RegionFile.findCoordinate(wz, voxelSize);
		ChunkData data = new ChunkData(wx, wy, wz, voxelSize);
		int hash = data.hashCode() & HASH_MASK;
		RegionFile res = regionCache.find(data, hash);
		if (res != null) return res;
		synchronized(regionCache.cache[hash]) {
			res = regionCache.find(data, hash);
			if (res != null) return res;
			// Generate a new chunk:
			res = new RegionFile(world, wx, wy, wz, voxelSize);
			RegionFile old = regionCache.addToCache(res, hash);
			if(old != null) {
				old.store();
				old.storeOnChange = true;
			}
		}
		return res;
	}
	public static boolean loadChunkFromFile(ServerWorld world, Chunk ch) {
		RegionFile region = getOrLoadRegionFile(world, ch.wx, ch.wy, ch.wz, ch.voxelSize);
		return region.loadChunk(ch);
	}
	public static void storeChunkToFile(ServerWorld world, Chunk ch) {
		RegionFile region = getOrLoadRegionFile(world, ch.wx, ch.wy, ch.wz, ch.voxelSize);
		region.saveChunk(ch);
	}
	
	public static void save() {
		regionCache.foreach((region) -> {
			region.store();
			region.storeOnChange = true;
		});
	}
	
	public static void clean() {
		save();
		regionCache.clear();
	}
}
