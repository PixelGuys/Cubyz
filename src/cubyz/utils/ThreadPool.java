package cubyz.utils;

import cubyz.utils.datastructures.BlockingMaxHeap;
import cubyz.world.ChunkData;
import cubyz.world.ChunkManager;

public final class ThreadPool {
	private static final Thread[] threads;
	private static final BlockingMaxHeap<Task> loadList;

	private static volatile boolean running = false;

	static {
		threads = new Thread[Math.max(1, Runtime.getRuntime().availableProcessors() - 2)];
		for (int i = 0; i < threads.length; i++) {
			Thread thread = new Thread(ThreadPool::run);
			thread.setName("Worker-Thread-" + (i+1));
			thread.setPriority(Thread.MIN_PRIORITY);
			thread.setDaemon(true);
			threads[i] = thread;
		}
		loadList = new BlockingMaxHeap<>(new Task[1024], threads.length);
	}

	private static void run() {
		while (running) {
			Task popped;
			try {
				popped = loadList.extractMax();
			} catch (InterruptedException e) {
				break;
			}
			try {
				popped.run();
			} catch (Throwable e) {
				Logger.error("Could not run task " + popped + " !");
				Logger.error(e);
			}
			// Update the priority of all elements:
			// TODO: Make this more efficient. For example by using a better datastructure.
			Task[] array = loadList.toArray();
			for(Task element : array) {
				if (element != null) {
					element.cachedPriority = element.getPriority();
				}
			}
			loadList.updatePriority();
		}
	}

	public static void clearAndStopThreads() {
		running = false;
		try {
			for (Thread thread : threads) {
				thread.interrupt();
				thread.join();
			}
		} catch(InterruptedException e) {
			Logger.error(e);
		}
	}

	public static void startThreads() {
		running = true;
		for(Thread thread : threads) {
			thread.start();
		}
	}

	public static void addTask(Task task) {
		task.cachedPriority = task.getPriority();
		loadList.add(task);
	}

	public static int getQueueSize() {
		return loadList.size();
	}

	public abstract static class Task implements Comparable<Task>, Runnable {
		private float cachedPriority;
		@Override
		public int compareTo(Task other) {
			return (int)Math.signum(cachedPriority - other.cachedPriority);
		}

		public abstract float getPriority();
	}
}
