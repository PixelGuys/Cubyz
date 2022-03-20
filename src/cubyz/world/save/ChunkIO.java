package cubyz.world.save;

import cubyz.utils.datastructures.Cache;
import cubyz.world.SavableChunk;
import cubyz.world.World;

public final class ChunkIO {
	private ChunkIO() {} // No instances allowed.

	// Region files generally seem to be less than 1 MB on disk. To be on the safe side the amount of cached region files is limited to 128.
	private static final int HASH_MASK = 31;
	private static final Cache<RegionFile> regionCache = new Cache<>(new RegionFile[HASH_MASK+1][4]);
	
	private static RegionFile getOrLoadRegionFile(World world, int wx, int wy, int wz, int voxelSize, String fileEnding) {
		wx = RegionFile.findCoordinate(wx, voxelSize);
		wy = RegionFile.findCoordinate(wy, voxelSize);
		wz = RegionFile.findCoordinate(wz, voxelSize);
		RegionFileCompare data = new RegionFileCompare(wx, wy, wz, voxelSize, fileEnding);
		int hash = data.hashCode() & HASH_MASK;
		RegionFile res = regionCache.find(data, hash);
		if (res != null) return res;
		synchronized(regionCache.cache[hash]) {
			res = regionCache.find(data, hash);
			if (res != null) return res;
			// Generate a new chunk:
			res = new RegionFile(world, wx, wy, wz, voxelSize, fileEnding);
			RegionFile old = regionCache.addToCache(res, hash);
			if(old != null) {
				old.clean();
			}
		}
		return res;
	}
	public static boolean loadChunkFromFile(World world, SavableChunk ch) {
		RegionFile region = getOrLoadRegionFile(world, ch.wx, ch.wy, ch.wz, ch.voxelSize, ch.fileEnding());
		return region.loadChunk(ch);
	}
	public static void storeChunkToFile(World world, SavableChunk ch) {
		RegionFile region = getOrLoadRegionFile(world, ch.wx, ch.wy, ch.wz, ch.voxelSize, ch.fileEnding());
		region.saveChunk(ch);
	}
	
	public static void save() {
		regionCache.foreach(RegionFile::clean);
	}
	
	public static void clean() {
		save();
		regionCache.clear();
	}
}
