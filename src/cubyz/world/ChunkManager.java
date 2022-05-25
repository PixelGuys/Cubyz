package cubyz.world;

import java.util.Arrays;

import cubyz.multiplayer.Protocols;
import cubyz.server.Server;
import cubyz.server.User;
import cubyz.utils.ThreadPool;
import cubyz.utils.datastructures.Cache;
import cubyz.utils.math.CubyzMath;
import cubyz.world.save.ChunkIO;
import cubyz.world.terrain.*;
import pixelguys.json.JsonObject;

/**
 * Responsible for loading and storing the chunks of the world.
 */
public class ChunkManager {
	
	// synchronized common list for chunk generation
	private final ServerWorld world;

	public final TerrainGenerationProfile terrainGenerationProfile;

	// There will be at most 1 GiB of reduced chunks in here.
	private static final int CHUNK_CACHE_MASK = 2047;
	private final Cache<ReducedChunk> reducedChunkCache = new Cache<ReducedChunk>(new ReducedChunk[CHUNK_CACHE_MASK+1][4]);
	// There will be at most 1 GiB of map data in here.
	private static final int[] MAP_CACHE_MASK = {
		7, // 256 MiB // 4(1 in best-case) maps are needed at most for each player. So 32 will be enough for 8(32 in best case) player groups.
		31, // 256 MiB
		63, // 128 MiB
		255, // 128 MiB
		511, // 64 MiB
		2047, // 64 MiB
	};
	@SuppressWarnings("unchecked")
	private final Cache<MapFragment>[] mapCache = new Cache[] {
	    new Cache<MapFragment>(new MapFragment[MAP_CACHE_MASK[0] + 1][4]),
	    new Cache<MapFragment>(new MapFragment[MAP_CACHE_MASK[1] + 1][4]),
	    new Cache<MapFragment>(new MapFragment[MAP_CACHE_MASK[2] + 1][4]),
	    new Cache<MapFragment>(new MapFragment[MAP_CACHE_MASK[3] + 1][4]),
	    new Cache<MapFragment>(new MapFragment[MAP_CACHE_MASK[4] + 1][4]),
	    new Cache<MapFragment>(new MapFragment[MAP_CACHE_MASK[5] + 1][4]),
	};

	private class ChunkLoadTask extends ThreadPool.Task {
		private final ChunkData ch;
		public ChunkLoadTask(ChunkData ch) {
			this.ch = ch;
		}
		@Override
		public float getPriority() {
			return ch.getPriority(Server.world.player);
		}

		@Override
		public boolean isStillNeeded() {
			return true; // TODO: Optimize that using the players render distance.
		}

		@Override
		public void run() {
			synchronousGenerate(ch);
		}
	}

	public ChunkManager(ServerWorld world, JsonObject settings) {
		this.world = world;

		terrainGenerationProfile = new TerrainGenerationProfile(settings, world.getCurrentRegistries(), world.getSeed());

		CaveBiomeMap.init(terrainGenerationProfile);
		CaveMap.init(terrainGenerationProfile);
		ClimateMap.init(terrainGenerationProfile);
	}

	public void queueChunk(ChunkData ch) {
		if(ch.voxelSize == 1 && !(ch instanceof NormalChunk)) {
			// Special case: Normal chunk is queued
			// If the chunk doesn't exist yet, nothing is done.
			// If the chunk isn't generated yet, nothing is done.
			// If the chunk is already fully generated, it is returned.
			NormalChunk chunk = world.getChunk(ch.wx, ch.wy, ch.wz);
			if(chunk != null && chunk.isLoaded()) {
				for(User user : Server.userManager.users) {
					Protocols.CHUNK_TRANSMISSION.sendChunk(user, chunk);
				}
				return;
			}
		}
		ThreadPool.addTask(new ChunkLoadTask(ch));
	}
	
	public void synchronousGenerate(ChunkData ch) {
		if (ch.voxelSize == 1) {
			NormalChunk chunk;
			if(ch instanceof NormalChunk) {
				chunk = (NormalChunk)ch;
			} else {
				chunk = new NormalChunk(world, ch.wx, ch.wy, ch.wz); // TODO: Cache this.
			}
			if(!chunk.isLoaded()) { // Prevent reloading.
				chunk.generate(world.getSeed(), terrainGenerationProfile);
				chunk.load();
			}
			//Cubyz.chunkTree.updateChunkMesh((NormalChunk) ch); // TODO: Do this over the network.
			for(User user : Server.userManager.users) {
				Protocols.CHUNK_TRANSMISSION.sendChunk(user, chunk);
			}
		} else {
			ReducedChunkVisibilityData visibilityData = new ReducedChunkVisibilityData(world, ch.wx, ch.wy, ch.wz, ch.voxelSize);
			for(User user : Server.userManager.users) {
				Protocols.CHUNK_TRANSMISSION.sendChunk(user, visibilityData);
			}
		}
	}

	public MapFragment getOrGenerateMapFragment(int wx, int wz, int voxelSize) {
		wx &= ~MapFragment.MAP_MASK;
		wz &= ~MapFragment.MAP_MASK;

		MapFragmentCompare data = new MapFragmentCompare(wx, wz, voxelSize);
		int index = CubyzMath.binaryLog(voxelSize);
		int hash = data.hashCode() & MAP_CACHE_MASK[index];

		MapFragment res = mapCache[index].find(data, hash);
		if (res != null) return res;

		synchronized(mapCache[index].cache[hash]) {
			res = mapCache[index].find(data, hash);
			if (res != null) return res;

			// Generate a new map fragment:
			res = new MapFragment(wx, wz, voxelSize);
			terrainGenerationProfile.mapFragmentGenerator.generateMapFragment(res, world.getSeed());
			mapCache[index].addToCache(res, hash);
		}
		return res;
	}

	/**
	 * Only for internal use. Generates a reduced chunk at a given location, or if possible gets it from the cache.
	 * @param wx
	 * @param wy
	 * @param wz
	 * @param voxelSize
	 * @return
	 */
	public ReducedChunk getOrGenerateReducedChunk(int wx, int wy, int wz, int voxelSize) {
		int chunkMask = ~(voxelSize*Chunk.chunkSize - 1);
		wx &= chunkMask;
		wy &= chunkMask;
		wz &= chunkMask;
		ChunkData data = new ChunkData(wx, wy, wz, voxelSize);
		int hash = data.hashCode() & CHUNK_CACHE_MASK;
		ReducedChunk res = reducedChunkCache.find(data, hash);
		if (res != null) return res;
		synchronized(reducedChunkCache.cache[hash]) {
			res = reducedChunkCache.find(data, hash);
			if (res != null) return res;
			// Generate a new chunk:
			res = new ReducedChunk(world, wx, wy, wz, CubyzMath.binaryLog(voxelSize));
			res.generate(world.getSeed(), terrainGenerationProfile);
			ReducedChunk old = reducedChunkCache.addToCache(res, hash);
			if(old != null)
				old.clean();
		}
		return res;
	}

	public void cleanup() {
		for(Cache<MapFragment> cache : mapCache) {
			cache.clear();
		}
		ThreadPool.clearAndStopThreads();
		for(int i = 0; i < 5; i++) { // Saving one chunk may create and update a new lower resolution chunk.
		
			for(ReducedChunk[] array : reducedChunkCache.cache) {
				array = Arrays.copyOf(array, array.length); // Make a copy to prevent issues if the cache gets resorted during cleanup.
				for(ReducedChunk chunk : array) {
					if (chunk != null)
						chunk.clean();
				}
			}
		}
		for(Cache<MapFragment> cache : mapCache) {
			cache.clear();
		}
		CaveBiomeMap.cleanup();
		CaveMap.cleanup();
		ClimateMap.cleanup();
		reducedChunkCache.clear();
		ChunkIO.clean();
	}

	public void forceSave() {
		for(int i = 0; i < 5; i++) { // Saving one chunk may create and update a new lower resolution chunk.
			reducedChunkCache.foreach(Chunk::save);
		}
	}
}
