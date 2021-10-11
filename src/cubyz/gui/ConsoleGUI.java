package cubyz.gui;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.util.ArrayList;
import java.util.Comparator;

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

	//Textinput
	TextInput input;
	
	//Basic console properties
	private static final int CONSOLE_HEIGHT = 40; //TODO Changeable via Options
	private static final int CONSOLE_WIDTH = 400; //TODO Changeable via Options
	private static final int SIZE = 128;

	//Storage and pionter for managing console-history
	private static String[] consoleArray = new String[SIZE];
	private static int end;
	private static int current;

	//Input-output File
	private static boolean gotData = false;
	private static final String PATH = "ConsoleHistory";

	//Storage and pointer for searching in commands
	private static final CommandBase[] COMMANDS = CubyzRegistries.COMMAND_REGISTRY.registered(new CommandBase[0]);
	private static ArrayList<CommandBase> possibleCommands = new ArrayList<>();
	private static CommandBase command;
	private static int bestGuessIndex;
	private static boolean searchmode;
	private static String text;

	//Iterater for arguments of commands
	private static int arg;

	//Textline for showing autocomplete suggestions and expected arguments of commands
	private static final String COMPLETION_COLOR = "#606060";
	private static TextLine textLine = new TextLine(Fonts.PIXEL_FONT, "", CONSOLE_HEIGHT - 2, false);

	@Override
	public void init() {
		input = new TextInput();
		text = "";
		input.setBounds(0, 0, CONSOLE_WIDTH, CONSOLE_HEIGHT, Component.ALIGN_TOP_LEFT);

		input.setFontSize(CONSOLE_HEIGHT - 2);
		input.textLine.endSelection(0);
		input.setFocused(true);
		Mouse.setGrabbed(false);

		searchmode = false;
		textLine.updateText("");
		bestGuessIndex = -1;
		command = null;

		if (!gotData) {
			try {
				ObjectInputStream iS = new ObjectInputStream(new FileInputStream(PATH));
				consoleArray = (String[]) iS.readObject();
				end = (int) iS.readObject();
				iS.close();
			} catch (IOException ioE) {
				//Creates new history if cant read file(wrong format; doesnt exist; damaged)
				for (int i = 0; i < SIZE; i++) {
					consoleArray[i] = "";
				}
				end = 0;
				current = 0;
			} catch (ClassNotFoundException cnfE) {
				Logger.error(cnfE);
			}
			gotData = true;
		}
		current = end;
		arg = -1;
	}

	@Override
	public void render() {
		input.render();
		text = input.getText();
		if (searchmode) {
			//Updates suggestions in case of new chars
			if (Keyboard.hasCharSequence()) {
				updatePossibleCommands();	
			}
			//Updates suggestions in case of deletion of chars
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_BACKSPACE)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_BACKSPACE, false);
				if (command == null) {
					updatePossibleCommands();
				} else if (text.startsWith(command.getCommandName())) {
					command = null;
					arg = -1;
					textLine.updateText("");
				}
			}
		}
		textLine.render(input.textLine.getTextWidth() + 4, 0);
		//Autocompletes commands and arguments when pressing enter
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
			//Autocompletes command if in searchmode and there is a possible command
			if (searchmode && command == null && bestGuessIndex != -1) {
				command = possibleCommands.get(bestGuessIndex);
				text = command.getCommandName();
				input.setText(text);
			}
			if (command == null) {
				for (int i = 0; i < COMMANDS.length; i++) {
					if (COMMANDS[i].getCommandName().equals(text)) {
						command = COMMANDS[i];
					}
				}
			}
			//Executes command and puts it in history if there is no argument or all arguments are set
			if (text != "" && (!searchmode || command == null || (command != null && command.getExpectedArgs().length == 0 || (arg > -1 && arg + 1 == command.getExpectedArgs().length)))) {
				consoleArray[end] = text;
				end = (end + 1) % SIZE;
				current = end;
				consoleArray[current] = "";
				CommandExecutor.execute(text, Cubyz.player);
				textLine.updateText("");
				input.setText("");
				arg = -1;
				command = null;
				searchmode = false;
			//Sets arguments
			} else if(searchmode && command != null && command.getExpectedArgs().length != 0){
				arg++;
				text += " ";
				input.setText(text);
				float startSelection = input.textLine.getTextWidth() + 10;
				text += command.getExpectedArgs()[arg];
				input.setText(text);
				input.textLine.startSelection(startSelection);
				input.textLine.endSelection(input.textLine.getTextWidth());
				String s = "";
				for (int i = arg + 1; i < command.getExpectedArgs().length; i++) {
					s += " " + command.getExpectedArgs()[i];
				}
				textLine.updateText(s);
			}
			try {
				ObjectOutputStream oS = new ObjectOutputStream(new FileOutputStream(PATH));
				oS.writeObject(consoleArray);
				oS.writeObject(end);
				oS.close();
			} catch (IOException e) {
				Logger.error(e);
			}

		}
		//Cycles back/up in history/suggestions
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_UP)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_UP, false);
			if (searchmode) {
				if (possibleCommands.size()>0) {
					bestGuessIndex = (bestGuessIndex + 1) % possibleCommands.size();
					textLine.updateText(COMPLETION_COLOR+possibleCommands.get(bestGuessIndex).getCommandName().substring(text.length()));
				}
			} else {
				if (!("".equals(consoleArray[(SIZE + current - 1) % SIZE]))) {
					current = (SIZE + current - 1) % SIZE;
					input.setText(consoleArray[current]);
					input.textLine.endSelection(CONSOLE_WIDTH);
				}
			}
		}
		//Cycles forward/down in history/suggestions
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_DOWN)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_DOWN, false);
			if (searchmode) {
				if (possibleCommands.size() > 0) {
					bestGuessIndex = (possibleCommands.size() + bestGuessIndex - 1) % possibleCommands.size();
					textLine.updateText(COMPLETION_COLOR+possibleCommands.get(bestGuessIndex).getCommandName().substring(text.length()));
				}
			} else {
				if (!("".equals(consoleArray[current]))) {
					current = (current + 1) % SIZE;
					input.setText(consoleArray[current]);
					input.textLine.endSelection(CONSOLE_WIDTH);
				}
			}
		}
		//Starts autocompletion by tab and if active cycles through
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_TAB)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_TAB, false);
			if (command == null) {
				if (searchmode) {
					if (possibleCommands.size() > 0) {
						bestGuessIndex = (bestGuessIndex + 1) % possibleCommands.size();
						textLine.updateText(COMPLETION_COLOR + possibleCommands.get(bestGuessIndex).getCommandName().substring(text.length()));
					}
				} else {
					searchmode = true;
					updatePossibleCommands();
				}
			}
			
		}
	}

	//Finds commands a sorted arraylist of commands starting with the userinput
	private void updatePossibleCommands() {
		if (searchmode && command == null) {
			possibleCommands.clear();
			for (int i = 0; i < COMMANDS.length; i++) {
				if (COMMANDS[i].getCommandName().startsWith(text)) {
					possibleCommands.add(COMMANDS[i]);
				}
			}
			possibleCommands.sort(
				new Comparator<CommandBase>() {
					@Override
					public int compare(CommandBase cb1, CommandBase cb2) {
						return cb1.getCommandName().compareTo(cb2.getCommandName());
					}
				}
			);
			if (possibleCommands.size() == 0) {
				bestGuessIndex = -1;
			} else {
				bestGuessIndex = 0;
			}
			if (bestGuessIndex>-1) {
				textLine.updateText(COMPLETION_COLOR+possibleCommands.get(bestGuessIndex).getCommandName().substring(text.length()));
			} else {
				textLine.updateText("");
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