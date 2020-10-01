package io.cubyz.client;

import io.jungle.game.Game;

import static io.cubyz.CubyzLogger.logger;

import io.cubyz.CubyzLogger;

public class GameLauncher extends Game {

	public static GameLauncher instance;
	
	public static void main(String[] args) {
		try {
			GameLauncher.instance = new GameLauncher();
			instance.logic = new Cubyz();
			instance.start();
			logger.info("Stopped!");
			System.exit(0);
		} catch(Exception e) {
			CubyzLogger.logger.throwable(e);
			throw e;
		}
	}
	
}