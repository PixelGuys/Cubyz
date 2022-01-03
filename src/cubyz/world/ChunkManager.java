package cubyz.world;

import java.util.Arrays;
import java.util.Comparator;

import cubyz.api.CubyzRegistries;
import cubyz.utils.Logger;
import cubyz.utils.datastructures.BlockingMaxHeap;
import cubyz.utils.datastructures.Cache;
import cubyz.utils.json.JsonObject;
import cubyz.utils.math.CubyzMath;
import cubyz.world.terrain.ClimateMapGenerator;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.MapFragmentCompare;
import cubyz.world.terrain.MapGenerator;
import cubyz.world.terrain.generators.Generator;

/**
 * Responsible for loading and storing the chunks of the world.
 * Also contains all the info for generation(like what Generators are used).
 */
public class ChunkManager {
	
	// synchronized common list for chunk generation
	private final BlockingMaxHeap<ChunkData> loadList;
	private final World world;
	private final Thread[] threads;

	public final MapGenerator mapFragmentGenerator;
	public final ClimateMapGenerator climateGenerator;
	public final Generator[] generators;

	// There will be at most 1 GB of reduced chunks in here.
	private static final int CHUNK_CACHE_MASK = 8191;
	private final Cache<ReducedChunk> reducedChunkCache = new Cache<ReducedChunk>(new ReducedChunk[CHUNK_CACHE_MASK+1][4]);
	// There will be at most 1 GB of map data in here.
	private static final int[] MAP_CACHE_MASK = {
		7, // 256 MB // 4(1 in best-case) maps are needed at most for each player. So 32 will be enough for 8(32 in best case) player groups.
		31, // 256 MB
		63, // 128 MB
		255, // 128 MB
		511, // 64 MB
		2047, // 64 MB
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
				ChunkData popped = null;
				try {
					popped = loadList.extractMax();
				} catch (InterruptedException e) {
					break;
				}
				try {
					synchronousGenerate(popped);
				} catch (Exception e) {
					Logger.error("Could not generate " + popped.voxelSize + "-chunk " + popped.wx + ", " + popped.wy + ", " + popped.wz + " !");
					Logger.error(e);
				}
				// Update the priority of all elements:
				// TODO: Make this more efficient. For example by using a better datastructure.
				ChunkData[] array = loadList.toArray();
				for(ChunkData element : array) {
					if (element != null) {
						element.updatePriority(world.getLocalPlayer());
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

	public ChunkManager(World world, JsonObject settings, int numberOfThreads) {
		loadList = new BlockingMaxHeap<>(new ChunkData[1024], numberOfThreads);
		this.world = world;
		
		JsonObject generator = settings.getObjectOrNew("mapGenerator");
		mapFragmentGenerator = CubyzRegistries.MAP_GENERATOR_REGISTRY.getByID(generator.getString("id", "cubyz:mapgen_v1"));
		mapFragmentGenerator.init(generator, world.getCurrentRegistries());
		generator = settings.getObjectOrNew("climateGenerator");
		climateGenerator = CubyzRegistries.CLIMATE_GENERATOR_REGISTRY.getByID(generator.getString("id", "cubyz:polar_circles"));
		climateGenerator.init(generator, world.getCurrentRegistries());

		generators = CubyzRegistries.GENERATORS.registered(new Generator[0]);
		for(int i = 0; i < generators.length; i++) {
			generators[i].init(null, world.getCurrentRegistries());
		}
		Arrays.sort(generators, new Comparator<Generator>() {
			@Override
			public int compare(Generator a, Generator b) {
				if (a.getPriority() > b.getPriority()) {
					return 1;
				} else if (a.getPriority() < b.getPriority()) {
					return -1;
				} else {
					return 0;
				}
			}
		});

		threads = new Thread[numberOfThreads];
		for (int i = 0; i < numberOfThreads; i++) {
			ChunkGenerationThread thread = new ChunkGenerationThread();
			thread.setName("Local-Chunk-Thread-" + i);
			thread.setPriority(Thread.MIN_PRIORITY);
			thread.setDaemon(true);
			thread.start();
			threads[i] = thread;
		}
	}

	public void queueChunk(ChunkData ch) {
		ch.updatePriority(world.getLocalPlayer());
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
				((NormalChunk) ch).generateFrom(this);
				((NormalChunk) ch).load();
			}
			world.clientConnection.updateChunkMesh((NormalChunk) ch);
		} else {
			ReducedChunkVisibilityData visibilityData = new ReducedChunkVisibilityData(world, ch.wx, ch.wy, ch.wz, ch.voxelSize);
			world.clientConnection.updateChunkMesh(visibilityData);
		}
	}

	public void generate(Chunk chunk) {
		int wx = chunk.wx;
		int wy = chunk.wy;
		int wz = chunk.wz;
		long seed = world.getSeed();
		
		MapFragment containing = getOrGenerateMapFragment(wx, wz, chunk.voxelSize);
		
		for (Generator g : generators) {
			g.generate(seed ^ g.getGeneratorSeed(), wx, wy, wz, chunk, containing, this);
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
			res = new MapFragment(wx, wz, world, world.wio, voxelSize);
			mapFragmentGenerator.generateMapFragment(res);
			MapFragment old = mapCache[index].addToCache(res, hash);
			if (old != null)
				old.mapIO.saveData();
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
			res.generateFrom(this);
			ReducedChunk old = reducedChunkCache.addToCache(res, hash);
			if(old != null)
				old.clean();
		}
		return res;
	}

	public void cleanup() {
		try {
			for (Thread thread : threads) {
				thread.interrupt();
				thread.join();
			}
		} catch(InterruptedException e) {
			Logger.error(e);
		}
		for(Cache<MapFragment> cache : mapCache) {
			cache.foreach((map) -> {
				map.mapIO.saveData();
			});
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
		reducedChunkCache.clear();
	}

	public void forceSave() {
		for(Cache<MapFragment> cache : mapCache) {
			cache.foreach((map) -> {
				map.mapIO.saveData();
			});
		}
		for(int i = 0; i < 5; i++) { // Saving one chunk may create and update a new lower resolution chunk.
			reducedChunkCache.foreach((chunk) -> {
				chunk.save();
			});
		}
	}
}
