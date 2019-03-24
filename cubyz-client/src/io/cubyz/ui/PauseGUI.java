package io.cubyz.ui;

import org.jungle.Keyboard;
import org.jungle.Window;
import org.lwjgl.glfw.GLFW;

import io.cubyz.client.Cubyz;
import io.cubyz.ui.components.Button;

public class PauseGUI extends MenuGUI {

	private Button exit;
	private Button game;
	
	@Override
	public void init(long nvg) {
		Cubyz.mouse.setGrabbed(false);
		exit = new Button();
		game = new Button();
		exit.setText("Exit to main menu");
		game.setText("Continue");
		
		game.setOnAction(() -> {
			Cubyz.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null);
		});
		
		exit.setOnAction(() -> {
			Cubyz.world = null;
			Cubyz.gameUI.setMenu(new MainMenuGUI());
		});
		
		exit.setSize(200, 50);
		game.setSize(200, 50);
	}

	@Override
	public void render(long nvg, Window win) {
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ESCAPE)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_ESCAPE, false);
			Cubyz.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null);
		}
		game.setPosition(win.getWidth() / 2 - 100, 100);
		exit.setPosition(win.getWidth() / 2 - 100, win.getHeight() - 100);
		exit.render(nvg, win);
		game.render(nvg, win);
	}

	@Override
	public boolean isFullscreen() {
		return true;
	}

}
