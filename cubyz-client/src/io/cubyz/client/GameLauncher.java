package io.cubyz.client;

import org.jungle.game.Game;
import org.jungle.game.GameOptions;
import org.jungle.game.GameOptionsPrompt;

public class GameLauncher extends Game {

	public static GameLauncher instance;
	
	public static void main(String[] args) {
		boolean showPrompt = Boolean.parseBoolean(System.getProperty("cubyz.showStartPrompt", "false"));
		GameLauncher.instance = new GameLauncher();
		instance.logic = new Cubyz();
		GameOptions opt = null;
		
		if (showPrompt) {
			GameOptionsPrompt prompt = new GameOptionsPrompt();
			prompt.setLocationRelativeTo(null);
			prompt.setTitle("Cubyz Settings");
			prompt.setVisible(true);
			while (prompt.isVisible()) {
				System.out.print(""); // Avoid bugs
			}
			
			opt = prompt.generateOptions();
		} else {
			opt = new GameOptions();
			opt.blending = true;
			opt.cullFace = true;
			opt.frustumCulling = true;
			opt.showTriangles = false;
			opt.fullscreen = false;
			opt.antialiasing = false;
		}
		
		instance.start(opt);
		Cubyz.log.info("Stopped!");
		System.exit(0);
	}
	
}