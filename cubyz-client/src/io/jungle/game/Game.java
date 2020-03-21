package io.jungle.game;

import io.jungle.Window;

public class Game {

	protected volatile boolean running;
	protected Window win;
	protected IGameLogic logic;
	private GameOptions opt;
	private Thread updateThread;
	double secsPerUpdate = 1d / 40d; // TODO: fix; always was supposed to be 30/s but somehow for that the value needs to be 1 / 40d
	private int targetFps = 60;
	
	private int fps;
	private int ups;
	
	public int getFPS() {
		return fps;
	}
	
	public int getUPS() {
		return ups;
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
		double steps = 0.0;
		double previous = getTime() + 1;
		double loopStartTime = getTime();
		int updates = 0;
		while (running) {
			loopStartTime = getTime();
			while (steps >= secsPerUpdate) {
				handleInput();
				update();
				steps -= secsPerUpdate;
				updates++;
			}
			if (getTime() > previous) {
				previous = getTime() + 1;
				ups = updates;
				updates = 0;
			}
			steps += getTime() - loopStartTime;
		}
	}

	public void start(GameOptions opt) {
		this.opt = opt;
		running = true;
		win = new Window();
		win.init(this.opt);
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
			sync(loopStartTime);
		}
	}

	private void sync(double loopStartTime) {
		float loopSlot = 1f / 60;
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
		win.update();
		logic.update(1.0f);
	}

	public void render() {
		logic.render(win);
		win.render();
	}

}
