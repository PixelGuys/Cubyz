package io.cubyz.ui;

import org.lwjgl.glfw.GLFW;

import io.cubyz.Keybindings;
import io.cubyz.client.Cubyz;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.options.OptionsGUI;
import io.cubyz.world.LocalWorld;
import io.jungle.Keyboard;
import io.jungle.Window;

public class PauseGUI extends MenuGUI {

	private Button exit;
	private Button resume;
	private Button reload;
	private Button options;
	
	@Override
	public void init(long nvg) {
		Cubyz.mouse.setGrabbed(false);
		if (Cubyz.world != null) {
			if (Cubyz.world.isLocal()) {
				LocalWorld world = (LocalWorld) Cubyz.world;
				world.forceSave();
			}
		}
		exit = new Button("gui.cubyz.pause.exit");
		resume = new Button("gui.cubyz.pause.resume");
		reload = new Button("gui.cubyz.debug.reload");
		options = new Button("gui.cubyz.mainmenu.options");
		
		options.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new OptionsGUI());
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
		options.setSize(200, 50);
	}

	@Override
	public void render(long nvg, Window win) {
		if (Keybindings.isPressed("menu")) {
			Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
			Cubyz.mouse.setGrabbed(true);
			Cubyz.gameUI.setMenu(null);
		}
		resume.setPosition(win.getWidth() / 2 - 100, 100);
		exit.setPosition(win.getWidth() / 2 - 100, win.getHeight() - 200);
		reload.setPosition(win.getWidth() / 2 - 100, win.getHeight() - 300);
		options.setPosition(win.getWidth() / 2 - 100, 200);
		exit.render(nvg, win);
		resume.render(nvg, win);
		options.render(nvg, win);
		if (Cubyz.clientShowDebug) {
			reload.render(nvg, win);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
