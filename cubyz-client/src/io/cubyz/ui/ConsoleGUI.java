package io.cubyz.ui;

import org.lwjgl.glfw.GLFW;

import io.cubyz.client.Cubyz;
import io.cubyz.command.CommandExecutor;
import io.cubyz.ui.components.TextInput;
import io.jungle.Keyboard;
import io.jungle.Window;

// (the console GUI is different from chat GUI)
public class ConsoleGUI extends MenuGUI {

	TextInput input;
	
	@Override
	public void init(long nvg) {
		input = new TextInput();
		input.setWidth(200);
		input.setHeight(20);
		Cubyz.mouse.setGrabbed(false);
	}

	@Override
	public void render(long nvg, Window win) {
		input.render(nvg, win);
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
			String text = input.getText();
			CommandExecutor.execute(text, Cubyz.world.getLocalPlayer());
			input.setText("");
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ESCAPE)) {
			Cubyz.mouse.setGrabbed(false);
			Cubyz.gameUI.setMenu(null);
		}
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}
	
	@Override
	public boolean ungrabsMouse() {
		return true;
	}

}
