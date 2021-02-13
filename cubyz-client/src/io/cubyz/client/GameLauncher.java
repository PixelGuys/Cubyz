package io.cubyz.client;

import static io.cubyz.CubyzLogger.logger;

import io.cubyz.CubyzLogger;
import io.cubyz.input.Input;
import io.cubyz.rendering.MainRenderer;

/**
 * Class containing the main function.
 */

public abstract class GameLauncher {
	public static MainRenderer renderer;
	public static Game instance;
	public static Input input;
	public static GameLogic logic;
	
	public static void main(String[] args) {
		try {
			input = new Input();
			instance = new Game();
			renderer = new MainRenderer();
			logic = new GameLogic();
			instance.start();
			logger.info("Stopped!");
			System.exit(0);
		} catch(Exception e) {
			CubyzLogger.logger.throwable(e);
			throw e;
		}
	}
	
}