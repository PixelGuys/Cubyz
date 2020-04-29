package io.cubyz.client;

import io.jungle.game.Game;

public class GameLauncher extends Game {

	public static GameLauncher instance;
	
	public static void main(String[] args) {
		GameLauncher.instance = new GameLauncher();
		instance.logic = new Cubyz();
		instance.start();
		Cubyz.log.info("Stopped!");
		System.exit(0);
	}
	
}