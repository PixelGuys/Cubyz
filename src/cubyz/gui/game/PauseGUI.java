package cubyz.gui.game;

import cubyz.utils.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.MenuGUI;
import cubyz.gui.Transition;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.input.Keybindings;
import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.gui.menu.MainMenuGUI;
import cubyz.gui.menu.settings.SettingsGUI;

import static cubyz.client.ClientSettings.GUI_SCALE;

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
					GameLauncher.renderer.loadShaders();
					Logger.info("Reloaded!");
				} catch (Exception e) {
					Logger.error(e);
				}
			});
		});

		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		exit.setBounds(-50 * GUI_SCALE, 100 * GUI_SCALE, 100 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_BOTTOM);
		exit.setFontSize(16 * GUI_SCALE);
		resume.setBounds(-50 * GUI_SCALE, 50 * GUI_SCALE, 100 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		resume.setFontSize(16 * GUI_SCALE);
		reload.setBounds(-50 * GUI_SCALE, 150 * GUI_SCALE, 100 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_BOTTOM);
		reload.setFontSize(16 * GUI_SCALE);
		settings.setBounds(-50 * GUI_SCALE, 100 * GUI_SCALE, 100 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP);
		settings.setFontSize(16 * GUI_SCALE);
	}

	@Override
	public void render() {
		if (Keybindings.isPressed("menu")) {
			Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
			Mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null, new Transition.None());
		}
		if (resume == null) init(); // Prevents a bug that sometimes occurs.
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
