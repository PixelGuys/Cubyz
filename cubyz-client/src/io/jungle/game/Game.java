package io.jungle.game;

import io.jungle.Window;

public class Game {

	protected volatile boolean running;
	protected Window win;
	protected IGameLogic logic;
	private Thread updateThread;
	private Thread renderThread;
	double secsPerUpdate = 1d / 30d;
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
	
	public Window getWindow() {
		return win;
	}
	
	public void updateLoop() {
		double previous = getTime() + 1;
		double loopStartTime = getTime();
		int updates = 0;
		while (running) {
			loopStartTime = getTime();
			handleInput();
			update();
			updates++;
			if (getTime() > previous) {
				previous = getTime() + 1;
				ups = updates;
				updates = 0;
			}
			sync(loopStartTime, secsPerUpdate);
		}
	}

	public void start() {
		running = true;
		win = new Window();
		win.init();
		logic.bind(this);
		try {
			logic.init(win);
		} catch (Exception e) {
			e.printStackTrace();
		}
		win.show();
		updateThread = new Thread(() -> {
			updateLoop();
		});
		updateThread.setName("Game-Update-Thread");
		updateThread.start();
		renderThread = Thread.currentThread();
		loop();
		logic.cleanup();
	}
	
	public void exit() {
		running = false;
	}
	
	public double getTime() {
        return System.nanoTime() / 1000000000d;
	}

	public void loop() {
		double previous = getTime();
		double loopStartTime = getTime();
		int frames = 0;
		while (running) {
			loopStartTime = getTime();

			if (previous < getTime() - 1) {
				previous = getTime();
				fps = frames;
				frames = 0;
			}
			
			render();
			++frames;
			sync(loopStartTime, 1 / 60);
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
		logic.input(win);
	}

	public void update() {
		logic.update(1.0f);
	}

	public void render() {
		logic.render(win);
		win.render();
	}

}
