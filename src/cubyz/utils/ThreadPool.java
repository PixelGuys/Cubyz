package cubyz.utils;

import cubyz.utils.datastructures.BlockingMaxHeap;

public final class ThreadPool {

	private static final int REFRESH_TIME = 100; // The time after which all priorities get refreshed in milliseconds.

	private static final Thread[] threads;
	private static final BlockingMaxHeap<Task> loadList;

	static {
		threads = new Thread[Math.max(1, Runtime.getRuntime().availableProcessors() - 2)];
		for (int i = 0; i < threads.length; i++) {
			Thread thread = new Thread(ThreadPool::run);
			thread.setName("Worker-Thread-" + (i+1));
			thread.setPriority(Thread.MIN_PRIORITY);
			thread.setDaemon(true);
			thread.start();
			threads[i] = thread;
		}
		loadList = new BlockingMaxHeap<>(new Task[1024], threads.length);
	}

	private static void run() {
		long lastUpdate = System.currentTimeMillis();
		while (true) {
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
			if(Thread.currentThread() == threads[0] && System.currentTimeMillis() - lastUpdate > REFRESH_TIME) { // Only update priorities on the first worker thread and after a specific amount of time.
				lastUpdate = System.currentTimeMillis();
				// Update the priority of all elements:
				Task[] array = loadList.toArray();
				for(Task element : array) {
					if (element != null) {
						if(!element.isStillNeeded()) {
							loadList.remove(element);
							continue;
						}
						element.cachedPriority = element.getPriority();
					}
				}
				loadList.updatePriority();
			}
		}
	}

	public static void clear() {
		loadList.clear();
		// Wait until all in-progress tasks are done:
		while(loadList.waitingThreadCount() < threads.length) {
			try {
				Thread.sleep(1);
			} catch(Exception e) {}
		}
	}

	public static void addTask(Task task) {
		if(task.isStillNeeded()) {
			task.cachedPriority = task.getPriority();
			loadList.add(task);
		}
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
		public abstract boolean isStillNeeded();
	}
}
