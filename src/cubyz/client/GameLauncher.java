package cubyz.client;

import cubyz.Logger;
import cubyz.gui.input.Input;
import cubyz.rendering.MainRenderer;
import cubyz.rendering.Window;

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
			Window.init();
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