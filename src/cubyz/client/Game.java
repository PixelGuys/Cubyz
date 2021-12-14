package cubyz.client;

import cubyz.utils.Logger;
import cubyz.rendering.Window;

public class Game {
	protected volatile boolean running;
	private Thread renderThread;
	
	private int fps;
	
	public int getFPS() {
		return fps;
	}

	public Thread getRenderThread() {
		return renderThread;
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
			GameLauncher.logic.clientUpdate(); // TODO: Maybe move this to an extra thread.
			if (Cubyz.player != null)
				Cubyz.player.update();
			++frames;
		}
	}

	public void handleInput() {
		GameLauncher.input.update();
	}
	
	public void render() {
		GameLauncher.renderer.render();
		Window.render();
	}
}
