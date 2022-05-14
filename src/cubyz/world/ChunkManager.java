package cubyz.world;

import java.util.Arrays;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocols;
import cubyz.server.Server;
import cubyz.server.User;
import cubyz.utils.Logger;
import cubyz.utils.datastructures.BlockingMaxHeap;
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
	private final BlockingMaxHeap<ChunkData> loadList;
	private final ServerWorld world;
	private final Thread[] threads;

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

	private class ChunkGenerationThread extends Thread {
		volatile boolean running = true;
		public void run() {
			while (running) {
				ChunkData popped;
				try {
					popped = loadList.extractMax();
				} catch (InterruptedException e) {
					break;
				}
				try {
					synchronousGenerate(popped);
				} catch (Throwable e) {
					Logger.error("Could not generate " + popped.voxelSize + "-chunk " + popped.wx + ", " + popped.wy + ", " + popped.wz + " !");
					Logger.error(e);
				}
				// Update the priority of all elements:
				// TODO: Make this more efficient. For example by using a better datastructure.
				ChunkData[] array = loadList.toArray();
				for(ChunkData element : array) {
					if (element != null) {
						element.updatePriority(world.player);
					}
				}
				loadList.updatePriority();
			}
		}
		
		@Override
		public void interrupt() {
			running = false; // Make sure the Thread stops in all cases.
			super.interrupt();
		}
	}

	public ChunkManager(ServerWorld world, JsonObject settings, int numberOfThreads) {
		loadList = new BlockingMaxHeap<>(new ChunkData[1024], numberOfThreads);
		this.world = world;

		terrainGenerationProfile = new TerrainGenerationProfile(settings, world.getCurrentRegistries(), world.getSeed());

		CaveBiomeMap.init(terrainGenerationProfile);
		CaveMap.init(terrainGenerationProfile);
		ClimateMap.init(terrainGenerationProfile);

		threads = new Thread[numberOfThreads];
		for (int i = 0; i < numberOfThreads; i++) {
			ChunkGenerationThread thread = new ChunkGenerationThread();
			thread.setName("Local-Chunk-Thread-" + i);
			thread.setPriority(Thread.MIN_PRIORITY);
			thread.setDaemon(true);
			threads[i] = thread;
		}
	}

	public void startThreads() {
		for(Thread thread : threads) {
			thread.start();
		}
	}

	public void queueChunk(ChunkData ch) {
		if(ch.voxelSize == 1 && !(ch instanceof NormalChunk)) {
			// Special case: Normal chunk is queued
			// If the chunk doesn't exist yet, nothing is done.
			// If the chunk isn't generated yet, nothing is done.
			// If the chunk is already fully generated, it is returned.
			NormalChunk chunk = world.getChunk(ch.wx, ch.wy, ch.wz);
			if(chunk != null && chunk.isLoaded()) {
				//Cubyz.chunkTree.updateChunkMesh(chunk); // TODO: Do this over the network.
				for(User user : Server.userManager.users) {
					Protocols.CHUNK_TRANSMISSION.sendChunk(user, chunk);
				}
			}
			return;
		}
		ch.updatePriority(world.player);
		loadList.add(ch);
	}
	
	public void unQueueChunk(ChunkData ch) {
		loadList.remove(ch);
	}
	
	public int getChunkQueueSize() {
		return loadList.size();
	}
	
	public void synchronousGenerate(ChunkData ch) {
		if (ch instanceof NormalChunk) {
			if(!((NormalChunk)ch).isLoaded()) { // Prevent reloading.
				((NormalChunk) ch).generate(world.getSeed(), terrainGenerationProfile);
				((NormalChunk) ch).load();
			}
			//Cubyz.chunkTree.updateChunkMesh((NormalChunk) ch); // TODO: Do this over the network.
			for(User user : Server.userManager.users) {
				Protocols.CHUNK_TRANSMISSION.sendChunk(user, ch);
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
		loadList.clear();
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
		try {
			for (Thread thread : threads) {
				thread.interrupt();
				thread.join();
			}
		} catch(InterruptedException e) {
			Logger.error(e);
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
