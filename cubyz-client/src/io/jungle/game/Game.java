package io.jungle.game;

import io.jungle.Window;

public class Game {

	protected boolean running;
	protected Window win;
	protected IGameLogic logic;
	private GameOptions opt;
	double secsPerUpdate = 1.d / 30d;
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
		double previous2 = previous;
		double steps = 0.0;
		int updates = 0;
		int frames = 0;
		while (running) {
			double loopStartTime = getTime();
			double elapsed = loopStartTime - previous;

			if (previous2 < getTime() - 1) {
				previous2 = getTime();
				fps = frames;
				ups = updates;
				frames = 0;
				updates = 0;
			}
			
			previous = loopStartTime;
			steps += elapsed;

			handleInput();

			while (steps >= secsPerUpdate) {
				update();
				updates++;
				steps -= secsPerUpdate;
			}

			render();
			frames++;
			sync(loopStartTime);
		}
	}

	private void sync(double loopStartTime) {
		float loopSlot = 1f / 90;
		double endTime = loopStartTime + loopSlot;
		while (System.currentTimeMillis() < endTime) {
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
