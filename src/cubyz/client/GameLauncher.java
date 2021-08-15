package cubyz.client;

import cubyz.Logger;
import cubyz.client.rendering.MainRenderer;
import cubyz.gui.input.Input;

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
			Logger.log("Stopped!");
			System.exit(0);
		} catch(Exception e) {
			Logger.throwable(e);
			throw e;
		}
	}
	
}