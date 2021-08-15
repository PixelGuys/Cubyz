package cubyz.gui;

import org.lwjgl.glfw.GLFW;

import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.rendering.Window;
import cubyz.command.CommandExecutor;
import cubyz.gui.components.TextInput;
import cubyz.gui.input.Keyboard;

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
