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
	final static int CONSOLE_HEIGHT = 40; //TODO Changeable via Options
	final static int CONSOLE_WIDTH = 400; //TODO Changeable via Options
	final static int SIZE = 128;
	private static int end = -1;
	private static int current = -1;
	private static String[] consoleArray = new String[SIZE];

	@Override
	public void init() {
		input = new TextInput();
		input.setBounds(0, 0, CONSOLE_WIDTH, CONSOLE_HEIGHT, Component.ALIGN_TOP_LEFT);
		input.setFontSize(CONSOLE_HEIGHT-2);
		input.textLine.endSelection(0);
		input.setFocused(true);
		if (end == -1){
			end = 0;
		}
		if (current == -1){
			current = 0;
		}
		for (int i = 0; i < SIZE; i++) {
			if(consoleArray[i]==null){
				consoleArray[i]="";
			}
		}
		Mouse.setGrabbed(false);
	}

	@Override
	public void render() {
		input.render();
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
			String text = input.getText();
			consoleArray[end]=text;
			end = (end+1)%SIZE;
			current = end;
			consoleArray[current]="";
			CommandExecutor.execute(text, Cubyz.player);
			input.setText("");	
		}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_UP)){
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_UP, false);
				if (!("".equals(consoleArray[(SIZE+current-1)%SIZE]))) {
					current=(SIZE+current-1)%SIZE;
					input.setText(consoleArray[current]);
				}
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_DOWN)){
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_DOWN, false);
				if (!("".equals(consoleArray[current]))) {
					current=(current+1)%SIZE;
					input.setText(consoleArray[current]);
				}
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
