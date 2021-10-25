package cubyz.client;

import cubyz.Logger;
import cubyz.rendering.Window;

public class Game {
	protected volatile boolean running;
	private Thread updateThread;
	private Thread renderThread;
	public double secsPerUpdate = 1d / 30d;
	private int targetFps = 60;
	
	private int fps;
	private int ups;
	
	public int getFPS() {
		return fps;
	}
	
	public int getUPS() {
		return ups;
	}
	
	public Thread getUpdateThread() {
		return updateThread;
	}

	public Thread getRenderThread() {
		return renderThread;
	}

	public void setTargetFps(int target) {
		targetFps = target;
	}
	
	public void setTargetUps(int target) {
		secsPerUpdate = 1.d / (double) target;
	}
	
	public int getTargetFps() {
		return targetFps;
	}
	
	public void updateLoop() {
		try {
			double previous = getTime() + 1;
			double loopStartTime = getTime();
			int updates = 0;
			while (running) {
				loopStartTime = getTime();
				update();
				updates++;
				if (getTime() > previous) {
					previous = getTime() + 1;
					ups = updates;
					updates = 0;
				}
				sync(loopStartTime, secsPerUpdate);
			}
		} catch (Exception e) {
			Logger.crash(e);
		}
	}

	public void start() {
		running = true;
		try {
			GameLauncher.logic.init();
		} catch (Exception e) {
			Logger.crash(e);
		}
		GameLauncher.input.init();
		Window.show();
		updateThread = new Thread(() -> {
			updateLoop();
		});
		updateThread.setName("Game-Update-Thread");
		updateThread.start();
		renderThread = Thread.currentThread();
		renderThread.setPriority(Thread.MAX_PRIORITY);
		loop();
		GameLauncher.logic.cleanup();
	}
	
	public void exit() {
		running = false;
	}
	
	public double getTime() {
        return System.nanoTime() / 1000000000d;
	}

	public void loop() {
		double previous = getTime();
		int frames = 0;
		while (running) {
			if (previous < getTime() - 1) {
				previous = getTime();
				fps = frames;
				frames = 0;
			}
			
			render();
			handleInput();
			if(Cubyz.player != null)
				Cubyz.player.update();
			++frames;
		}
	}
	
	// not very precise, we should only rely on this when v-sync is disabled
	private void sync(double loopStartTime, double loopSlot) {
		double endTime = loopStartTime + loopSlot;
		while (getTime() < endTime) {
			try {
				Thread.sleep(1);
			} catch (InterruptedException ie) {
			}
		}
	}

	public void handleInput() {
		GameLauncher.input.update();
	}

	public void update() {
		GameLauncher.logic.update(1.0f);
	}
	
	public void render() {
		GameLauncher.renderer.render();
		Window.render();
	}
}
