package cubyz.world;

import java.util.Arrays;

import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
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

	// There will be at most 1 GiB of reduced and 500 MB of normal chunks in here.
	private static final int REDUCED_CHUNK_CACHE_MASK = 2047;
	private static final int NORMAL_CHUNK_CACHE_MASK = 1023;
	private final Cache<ReducedChunk> reducedChunkCache = new Cache<>(new ReducedChunk[REDUCED_CHUNK_CACHE_MASK+1][4]);
	private final Cache<NormalChunk> normalChunkCache = new Cache<>(new NormalChunk[NORMAL_CHUNK_CACHE_MASK+1][4]);
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
	    new Cache<>(new MapFragment[MAP_CACHE_MASK[0] + 1][4]),
	    new Cache<>(new MapFragment[MAP_CACHE_MASK[1] + 1][4]),
	    new Cache<>(new MapFragment[MAP_CACHE_MASK[2] + 1][4]),
	    new Cache<>(new MapFragment[MAP_CACHE_MASK[3] + 1][4]),
	    new Cache<>(new MapFragment[MAP_CACHE_MASK[4] + 1][4]),
	    new Cache<>(new MapFragment[MAP_CACHE_MASK[5] + 1][4]),
	};

	private class ChunkLoadTask extends ThreadPool.Task {
		private final ChunkData ch;
		private final long creationTime;
		private final User source;
		public ChunkLoadTask(ChunkData ch, User source) {
			this.ch = ch;
			this.source = source;
			creationTime = System.currentTimeMillis();
		}
		@Override
		public float getPriority() {
			float priority = -Float.MAX_VALUE;
			for(User user : Server.users) {
				priority = Math.max(ch.getPriority(user.player), priority);
			}
			return priority;
		}

		@Override
		public boolean isStillNeeded() {
			if(source != null) {
				boolean isConnected = false;
				for(User user : Server.users) {
					if(source == user) {
						isConnected = true;
						break;
					}
				}
				if(!isConnected) {
					return false;
				}
			}
			if(System.currentTimeMillis() - creationTime > 10000) { // Only remove stuff after 10 seconds to account for trouble when for example teleporting.
				for(User user : Server.users) {
					double minDistSquare = ch.getMinDistanceSquared(user.player.getPosition().x, user.player.getPosition().y, user.player.getPosition().z);
					//                                                                   ↓ Margin for error. (diagonal of 1 chunk)
					double targetRenderDistance = (user.renderDistance*Chunk.chunkSize + Chunk.chunkSize*Math.sqrt(3));//*Math.pow(user.LODFactor, Math.log(ch.voxelSize)/Math.log(2));
					if(ch.voxelSize != 1) {
						targetRenderDistance *= ch.voxelSize*user.LODFactor;
					}
					if(minDistSquare <= targetRenderDistance*targetRenderDistance) {
						return true;
					}
				}
				return false;
			}
			return true;
		}

		@Override
		public void run() {
			synchronousGenerate(ch, source);
		}
	}

	public ChunkManager(ServerWorld world, JsonObject settings) {
		this.world = world;

		terrainGenerationProfile = new TerrainGenerationProfile(settings, world.getCurrentRegistries(), world.getSeed());

		CaveBiomeMap.init(terrainGenerationProfile);
		CaveMap.init(terrainGenerationProfile);
		ClimateMap.init(terrainGenerationProfile);
	}

	public void queueChunk(ChunkData ch, User source) {
		if(ch.voxelSize == 1 && !(ch instanceof NormalChunk)) {
			// Special case: Normal chunk is queued
			// If the chunk doesn't exist yet, it is generated.
			// If the chunk isn't generated yet, nothing is done.
			// If the chunk is already fully generated, it is returned.
			NormalChunk chunk = getNormalChunkFromCache(ch);
			if(chunk != null && chunk.isLoaded()) {
				if(source != null) {
					Protocols.CHUNK_TRANSMISSION.sendChunk(source, chunk);
				} else {
					for(User user : Server.users) {
						Protocols.CHUNK_TRANSMISSION.sendChunk(user, chunk);
					}
				}
				return;
			}
		}
		ThreadPool.addTask(new ChunkLoadTask(ch, source));
	}
	
	public void synchronousGenerate(ChunkData ch, User source) {
		if (ch.voxelSize == 1) {
			NormalChunk chunk;
			if(ch instanceof NormalChunk) {
				chunk = (NormalChunk)ch;
				if(!chunk.isLoaded()) { // Prevent reloading.
					chunk.generate(world.getSeed(), terrainGenerationProfile);
					chunk.load();
				}
			} else {
				chunk = getOrGenerateNormalChunk(ch);
			}
			if(source != null) {
				Protocols.CHUNK_TRANSMISSION.sendChunk(source, chunk);
			} else {
				for(User user : Server.users) {
					Protocols.CHUNK_TRANSMISSION.sendChunk(user, chunk);
				}
			}
		} else {
			ReducedChunkVisibilityData visibilityData = new ReducedChunkVisibilityData(world, ch.wx, ch.wy, ch.wz, ch.voxelSize);
			if(source != null) {
				Protocols.CHUNK_TRANSMISSION.sendChunk(source, visibilityData);
			} else {
				for(User user : Server.users) {
					Protocols.CHUNK_TRANSMISSION.sendChunk(user, visibilityData);
				}
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
		int hash = data.hashCode() & REDUCED_CHUNK_CACHE_MASK;
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

	/**
	 * Only for internal use. Generates a normal chunk at a given location, or if possible gets it from the cache.
	 * @param data
	 * @return
	 */
	public NormalChunk getOrGenerateNormalChunk(ChunkData data) {
		int hash = data.hashCode() & NORMAL_CHUNK_CACHE_MASK;
		NormalChunk res = normalChunkCache.find(data, hash);
		if (res != null) return res;
		synchronized(normalChunkCache.cache[hash]) {
			res = normalChunkCache.find(data, hash);
			if (res != null) return res;
			// Generate a new chunk:
			res = new NormalChunk(world, data.wx, data.wy, data.wz);
			res.generate(world.getSeed(), terrainGenerationProfile);
			res.load();
			NormalChunk old = normalChunkCache.addToCache(res, hash);
			if(old != null)
				old.clean();
		}
		return res;
	}
	public NormalChunk getNormalChunkFromCache(ChunkData data) {
		int hash = data.hashCode() & NORMAL_CHUNK_CACHE_MASK;
		return normalChunkCache.find(data, hash);
	}

	public void cleanup() {
		for(Cache<MapFragment> cache : mapCache) {
			cache.clear();
		}
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
		ThreadPool.clear();
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
