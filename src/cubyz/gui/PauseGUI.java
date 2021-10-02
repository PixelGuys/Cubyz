package cubyz.gui;

import cubyz.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.components.Button;
import cubyz.gui.input.Keybindings;
import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.gui.settings.SettingsGUI;

/**
 * GUI shown when pressing escape while in a world.
 */

public class PauseGUI extends MenuGUI {

	private Button exit;
	private Button resume;
	private Button reload;
	private Button settings;
	
	@Override
	public void init() {
		Mouse.setGrabbed(false);
		if (Cubyz.world != null) {
			Cubyz.world.forceSave();
		}
		exit = new Button("gui.cubyz.pause.exit");
		resume = new Button("gui.cubyz.pause.resume");
		reload = new Button("gui.cubyz.debug.reload");
		settings = new Button("gui.cubyz.mainmenu.settings");
		
		settings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SettingsGUI());
		});
		
		resume.setOnAction(() -> {
			Mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null);
		});
		
		exit.setOnAction(() -> {
			GameLauncher.logic.quitWorld();
			Cubyz.gameUI.setMenu(new MainMenuGUI());
		});
		
		reload.setOnAction(() -> {
			Cubyz.renderDeque.add(() -> {
				try {
					Logger.info("Reloading shaders..");
					GameLauncher.renderer.unloadShaders();
					GameLauncher.renderer.loadShaders();
					Logger.info("Reloaded!");
				} catch (Exception e) {
					Logger.error(e);
				}
			});
		});

		exit.setBounds(-100, 200, 200, 50, Component.ALIGN_BOTTOM);
		exit.setFontSize(32);
		resume.setBounds(-100, 100, 200, 50, Component.ALIGN_TOP);
		resume.setFontSize(32);
		reload.setBounds(-100, 300, 200, 50, Component.ALIGN_BOTTOM);
		reload.setFontSize(32);
		settings.setBounds(-100, 200, 200, 50, Component.ALIGN_TOP);
		settings.setFontSize(32);
	}

	@Override
	public void render() {
		if (Keybindings.isPressed("menu")) {
			Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
			Mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null, new Transition.None());
		}
		if(resume == null) init(); // Prevents a bug that sometimes occurs.
		exit.render();
		resume.render();
		settings.render();
		if (GameLauncher.input.clientShowDebug) {
			reload.render();
		}
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
