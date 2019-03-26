package io.cubyz.client;

import org.jungle.game.Game;
import org.jungle.game.GameOptions;
import org.jungle.game.GameOptionsPrompt;

public class GameLauncher extends Game {

	public static GameLauncher instance;
	
	public static void main(String[] args) {
		
		GameLauncher.instance = new GameLauncher();
		instance.logic = new Cubyz();
		
		GameOptionsPrompt prompt = new GameOptionsPrompt();
		prompt.setLocationRelativeTo(null);
		prompt.setTitle("Cubz Settings");
		prompt.setVisible(true);
		while (prompt.isVisible()) {
			System.out.print(""); // Avoid bugs
		}
		
		GameOptions opt = prompt.generateOptions();
		
		instance.start(opt);
		Cubyz.log.info("Stopped!");
		System.exit(0);
	}
	
}