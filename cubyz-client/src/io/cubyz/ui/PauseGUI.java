package io.cubyz.ui;

import io.cubyz.Logger;
import io.cubyz.client.Cubyz;
import io.cubyz.client.GameLauncher;
import io.cubyz.input.Keybindings;
import io.cubyz.input.Keyboard;
import io.cubyz.rendering.Window;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.settings.SettingsGUI;
import io.cubyz.world.LocalSurface;

/**
 * GUI shown when pressing escape while in a world.
 */

public class PauseGUI extends MenuGUI {

	private Button exit;
	private Button resume;
	private Button reload;
	private Button settings;
	
	@Override
	public void init(long nvg) {
		GameLauncher.input.mouse.setGrabbed(false);
		if (Cubyz.world != null) {
			if (Cubyz.world.isLocal()) {
				LocalSurface surface = (LocalSurface) Cubyz.surface;
				surface.forceSave();
			}
		}
		exit = new Button("gui.cubyz.pause.exit");
		resume = new Button("gui.cubyz.pause.resume");
		reload = new Button("gui.cubyz.debug.reload");
		settings = new Button("gui.cubyz.mainmenu.settings");
		
		settings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SettingsGUI());
		});
		
		resume.setOnAction(() -> {
			GameLauncher.input.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null);
		});
		
		exit.setOnAction(() -> {
			GameLauncher.logic.quitWorld();
			Cubyz.gameUI.setMenu(new MainMenuGUI());
		});
		
		reload.setOnAction(() -> {
			Cubyz.renderDeque.add(() -> {
				try {
					Logger.log("Reloading shaders..");
					GameLauncher.renderer.unloadShaders();
					GameLauncher.renderer.loadShaders();
					Logger.log("Reloaded!");
				} catch (Exception e) {
					Logger.throwable(e);
				}
			});
		});

		exit.setBounds(-100, 200, 200, 50, Component.ALIGN_BOTTOM);
		resume.setBounds(-100, 100, 200, 50, Component.ALIGN_TOP);
		reload.setBounds(-100, 300, 200, 50, Component.ALIGN_BOTTOM);
		settings.setBounds(-100, 200, 200, 50, Component.ALIGN_TOP);
	}

	@Override
	public void render(long nvg, Window win) {
		if (Keybindings.isPressed("menu")) {
			Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
			GameLauncher.input.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null, TransitionStyle.NONE);
		}
		if(resume == null) init(nvg); // Prevents a bug that sometimes occurs.
		exit.render(nvg, win);
		resume.render(nvg, win);
		settings.render(nvg, win);
		if (GameLauncher.input.clientShowDebug) {
			reload.render(nvg, win);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
