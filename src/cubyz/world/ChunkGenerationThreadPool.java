package cubyz.world;

import cubyz.utils.Logger;
import cubyz.utils.datastructures.BlockingMaxHeap;

public class ChunkGenerationThreadPool {
	
	// synchronized common list for chunk generation
	private final BlockingMaxHeap<ChunkData> loadList;
	private final ServerWorld world;
	private final Thread[] threads;

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

	public ChunkGenerationThreadPool(ServerWorld world, int numberOfThreads) {
		loadList = new BlockingMaxHeap<>(new ChunkData[1024], numberOfThreads);
		this.world = world;

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
			((NormalChunk) ch).generateFrom(world.getGenerator());
			((NormalChunk) ch).load();
			world.clientConnection.updateChunkMesh((NormalChunk) ch);
		} else {
			ReducedChunkVisibilityData visibilityData = new ReducedChunkVisibilityData(world, ch.wx, ch.wy, ch.wz, ch.voxelSize);
			world.clientConnection.updateChunkMesh(visibilityData);
		}
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
	}
}
