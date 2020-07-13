package io.cubyz.client;

import io.jungle.game.Game;

import static io.cubyz.CubyzLogger.logger;

public class GameLauncher extends Game {

	public static GameLauncher instance;
	
	public static void main(String[] args) {
		GameLauncher.instance = new GameLauncher();
		instance.logic = new Cubyz();
		instance.start();
		logger.info("Stopped!");
		System.exit(0);
	}
	
}