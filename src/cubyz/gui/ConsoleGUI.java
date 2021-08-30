package cubyz.gui;

import org.lwjgl.glfw.GLFW;

import cubyz.client.Cubyz;
import cubyz.command.CommandExecutor;
import cubyz.gui.components.TextInput;
import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;

// (the console GUI is different from chat GUI)

/**
 * A GUI to enter cheat commands.
 */

public class ConsoleGUI extends MenuGUI {

	TextInput input;
	
	@Override
	public void init() {
		input = new TextInput();
		input.setBounds(0, 0, 200, 20, Component.ALIGN_TOP_LEFT);
		Mouse.setGrabbed(false);
	}

	@Override
	public void render() {
		input.render();
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
