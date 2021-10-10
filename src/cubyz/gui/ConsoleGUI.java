package cubyz.gui;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.util.ArrayList;

import org.lwjgl.glfw.GLFW;

import cubyz.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.client.Cubyz;
import cubyz.command.CommandBase;
import cubyz.command.CommandExecutor;
import cubyz.gui.components.TextInput;
import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.rendering.text.Fonts;
import cubyz.rendering.text.TextLine;

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
	private final static String PATH = "ConsoleHistory";

	private final static CommandBase[] COMMANDS = CubyzRegistries.COMMAND_REGISTRY.registered(new CommandBase[0]);
	private static ArrayList<String> possibleCommands = new ArrayList<>();
	private static int bestGuessIndex;
	private static boolean searchmode;
	private static String text;

	private final static String COMPLETIONCOLOR = "#606060";
	private static TextLine textLine = new TextLine(Fonts.PIXEL_FONT, "", CONSOLE_HEIGHT-2, false);

	@Override
	public void init() {
		input = new TextInput();
		text = "";
		input.setBounds(0, 0, CONSOLE_WIDTH, CONSOLE_HEIGHT, Component.ALIGN_TOP_LEFT);

		input.setFontSize(CONSOLE_HEIGHT-2);
		input.textLine.endSelection(0);
		input.setFocused(true);
		Mouse.setGrabbed(false);

		updatePossibleCommands();
		searchmode = false;
		textLine.updateText("");

		if (!gotData) {
			try {
				iS = new ObjectInputStream(new FileInputStream(PATH));
				consoleArray = (String[]) iS.readObject();
				end = (int) iS.readObject();
				iS.close();
			} catch (IOException ioE){
				for (int i = 0; i < SIZE; i++) {
					consoleArray[i]="";
				}
				end = 0;
				current = 0;
			} catch (ClassNotFoundException cnfE) {
				Logger.error(cnfE);
			}
			gotData = true;
		}
		current = end;	
	}

	@Override
	public void render() {
		input.render();
		text = input.getText();
		if (searchmode) {
			if (Keyboard.hasCharSequence()) {
				updatePossibleCommands();
				if (bestGuessIndex>-1){
					textLine.updateText(COMPLETIONCOLOR+possibleCommands.get(bestGuessIndex).substring(text.length()));
				}else {
					textLine.updateText("");
				}
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_BACKSPACE)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_BACKSPACE, false);
				updatePossibleCommands();
				if (bestGuessIndex>-1){
					textLine.updateText(COMPLETIONCOLOR+possibleCommands.get(bestGuessIndex).substring(text.length()));
				}else {
					textLine.updateText("");
				}
			}
		}
		textLine.render(input.getTextWidth()+4, 0);
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
			if (searchmode && bestGuessIndex != -1) {
				text = possibleCommands.get(bestGuessIndex);
			}
			searchmode = false;
			consoleArray[end]=text;
			end = (end+1)%SIZE;
			current = end;
			consoleArray[current]="";
			CommandExecutor.execute(text, Cubyz.player);
			input.setText("");
			updatePossibleCommands();
			textLine.updateText("");
			
			try {
				oS = new ObjectOutputStream(new FileOutputStream(PATH));
				oS.writeObject(consoleArray);
				oS.writeObject(end);
				oS.close();
			} catch (IOException e) {
				Logger.error(e);
			}
		}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_UP)){
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_UP, false);
				if (searchmode) {
					if (possibleCommands.size()>0) {
						bestGuessIndex = (bestGuessIndex+1)%possibleCommands.size();
						textLine.updateText(COMPLETIONCOLOR+possibleCommands.get(bestGuessIndex).substring(text.length()));
					}
				}else {
					if (!("".equals(consoleArray[(SIZE+current-1)%SIZE]))) {
						current=(SIZE+current-1)%SIZE;
						input.setText(consoleArray[current]);
						input.textLine.endSelection(CONSOLE_WIDTH);
					}
				}
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_DOWN)){
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_DOWN, false);
				if (searchmode) {
					if (possibleCommands.size()>0) {
						bestGuessIndex = (possibleCommands.size() + bestGuessIndex-1)%possibleCommands.size();
						textLine.updateText(COMPLETIONCOLOR+possibleCommands.get(bestGuessIndex).substring(text.length()));
					}
				}else {
					if (!("".equals(consoleArray[current]))) {
						current=(current+1)%SIZE;
						input.setText(consoleArray[current]);
						input.textLine.endSelection(CONSOLE_WIDTH);
					}
				}
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_TAB)){
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_TAB, false);
				if (searchmode) {
					if (possibleCommands.size()>0) {
						bestGuessIndex = (bestGuessIndex+1)%possibleCommands.size();
						textLine.updateText(COMPLETIONCOLOR+possibleCommands.get(bestGuessIndex).substring(text.length()));
					}
				}else {
					updatePossibleCommands();
					searchmode = true;
					if (bestGuessIndex>-1){
						textLine.updateText(COMPLETIONCOLOR+possibleCommands.get(bestGuessIndex).substring(text.length()));
					}else {
						textLine.updateText("");
					}
				}
				
			}
	}

	private void updatePossibleCommands() {
		possibleCommands.clear();
		for (int i = 0; i < COMMANDS.length; i++) {
			if (COMMANDS[i].getCommandName().startsWith(text)) {
				possibleCommands.add(COMMANDS[i].getCommandName());	
			}
		}
		possibleCommands.sort(String.CASE_INSENSITIVE_ORDER);
		if (possibleCommands.size()==0) {
			bestGuessIndex = -1;
		}else {
			bestGuessIndex = 0;
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
