package io.cubyz.ui;

import io.cubyz.Keybindings;
import io.cubyz.client.Cubyz;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.settings.SettingsGUI;
import io.cubyz.world.LocalSurface;
import io.jungle.Keyboard;
import io.jungle.Window;

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
		Cubyz.mouse.setGrabbed(false);
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
			Cubyz.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null);
		});
		
		exit.setOnAction(() -> {
			Cubyz.quitWorld();
			Cubyz.gameUI.setMenu(new MainMenuGUI());
		});
		
		reload.setOnAction(() -> {
			Cubyz.renderDeque.add(() -> {
				try {
					System.out.println("Reloading shaders..");
					Cubyz.renderer.unloadShaders();
					Cubyz.renderer.loadShaders();
					System.out.println("Reloaded!");
				} catch (Exception e) {
					e.printStackTrace();
				}
			});
		});
		
		exit.setSize(200, 50);
		resume.setSize(200, 50);
		reload.setSize(200, 50);
		settings.setSize(200, 50);
	}

	@Override
	public void render(long nvg, Window win) {
		if (Keybindings.isPressed("menu")) {
			Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
			Cubyz.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null, TransitionStyle.NONE);
		}
		if(resume == null) init(nvg); // Prevents a bug that sometimes occurs.
		resume.setPosition(win.getWidth() / 2 - 100, 100);
		exit.setPosition(win.getWidth() / 2 - 100, win.getHeight() - 200);
		reload.setPosition(win.getWidth() / 2 - 100, win.getHeight() - 300);
		settings.setPosition(win.getWidth() / 2 - 100, 200);
		exit.render(nvg, win);
		resume.render(nvg, win);
		settings.render(nvg, win);
		if (Cubyz.clientShowDebug) {
			reload.render(nvg, win);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
