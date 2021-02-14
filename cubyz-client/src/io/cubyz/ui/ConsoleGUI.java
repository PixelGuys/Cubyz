package io.cubyz.ui;

import org.lwjgl.glfw.GLFW;

import io.cubyz.client.Cubyz;
import io.cubyz.client.GameLauncher;
import io.cubyz.command.CommandExecutor;
import io.cubyz.input.Keyboard;
import io.cubyz.rendering.Window;
import io.cubyz.ui.components.TextInput;

// (the console GUI is different from chat GUI)

/**
 * A GUI to enter cheat commands.
 */

public class ConsoleGUI extends MenuGUI {

	TextInput input;
	
	@Override
	public void init(long nvg) {
		input = new TextInput();
		input.setBounds(0, 0, 200, 20, Component.ALIGN_TOP_LEFT);
		GameLauncher.input.mouse.setGrabbed(false);
	}

	@Override
	public void render(long nvg, Window win) {
		input.render(nvg, win);
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
			String text = input.getText();
			CommandExecutor.execute(text, Cubyz.player);
			input.setText("");
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
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
