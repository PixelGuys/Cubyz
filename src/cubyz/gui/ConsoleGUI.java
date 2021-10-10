package cubyz.gui;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.IOException;

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
	
	private final static int CONSOLE_HEIGHT = 40; //TODO Changeable via Options
	private final static int CONSOLE_WIDTH = 400; //TODO Changeable via Options
	private final static int SIZE = 128;

	private static String[] consoleArray = new String[SIZE];
	private static int end;
	private static int current;

	private static boolean gotData = false;
	private static ObjectInputStream iS;
	private static ObjectOutputStream oS;
	private final static String PATH = "ConsoleHistory.tmp";
	
	

	@Override
	public void init() {
		input = new TextInput();
		input.setBounds(0, 0, CONSOLE_WIDTH, CONSOLE_HEIGHT, Component.ALIGN_TOP_LEFT);
		input.setFontSize(CONSOLE_HEIGHT-2);
		input.textLine.endSelection(0);
		input.setFocused(true);

		Mouse.setGrabbed(false);

		if (!gotData) {
			try {
				iS = new ObjectInputStream(new FileInputStream(PATH));
			} catch (IOException f){
				for (int i = 0; i < SIZE; i++) {
					consoleArray[i]="";
				}
				end = 0;
				current = 0;
			}
			gotData = true;
			try{
				consoleArray = (String[]) iS.readObject();
				end = (int) iS.readObject();
				current = (int) iS.readObject();
				iS.close();
			} catch (Exception e) {
				//Now we are fucked
			}
		}

		
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

			try {
				oS = new ObjectOutputStream(new FileOutputStream(PATH));
			} catch (IOException f){
				//Do nothing
			}
			try{
				oS.writeObject(consoleArray);
				oS.writeObject(end);
				oS.writeObject(current);
				oS.close();
			} catch (Exception e) {
				//Now we are fucked
			}

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
