package io.cubyz.client;

import io.jungle.game.Game;
import io.jungle.game.GameOptions;

public class GameLauncher extends Game {

	public static GameLauncher instance;
	
	public static void main(String[] args) {
		GameLauncher.instance = new GameLauncher();
		instance.logic = new Cubyz();
		GameOptions opt = new GameOptions();
		opt.blending = true;
		opt.cullFace = true;
		opt.frustumCulling = true;
		opt.showTriangles = false;
		opt.fullscreen = false;
		opt.antialiasing = false;
		
		instance.start(opt);
		Cubyz.log.info("Stopped!");
		System.exit(0);
	}
	
}