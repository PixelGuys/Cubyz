package cubyz.gui.game;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.util.ArrayList;
import java.util.Comparator;

import org.lwjgl.glfw.GLFW;

import cubyz.utils.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.client.Cubyz;
import cubyz.command.CommandBase;
import cubyz.command.CommandExecutor;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Component;
import cubyz.gui.components.TextInput;
import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.rendering.text.Fonts;
import cubyz.rendering.text.TextLine;

import static cubyz.client.ClientSettings.GUI_SCALE;

// (the console GUI is different from chat GUI)

/**
 * A GUI to enter cheat commands.
 */

public class ConsoleGUI extends MenuGUI {

	TextInput input;
	
	//Basic console properties
	private static final int CONSOLE_HEIGHT = 20;
	private static final int CONSOLE_WIDTH = 200;

	//Storage and pointer for managing console-history
	private static final int HISTORY_SIZE = 128;
	private static String[] consoleArray = new String[HISTORY_SIZE];
	private static int end;
	private static int current;

	//Input-output File
	private static boolean gotData = false;
	private static final String PATH = "ConsoleHistory";

	//Storage and pointer for searching in commands
	private static final CommandBase[] COMMANDS = CubyzRegistries.COMMAND_REGISTRY.registered(new CommandBase[0]);
	private static final int NORMAL = -1;
	private static final int AUTOCOMPLETE = -2;
	private static final int ARGUMENTS = 0;
	private static final int HISTORY = 1;
	private static int mode = NORMAL;
	private static final ArrayList<CommandBase> possibleCommands = new ArrayList<>();
	private static int commandSelection = 0;
	private static String[] expectedArgs = new String[0];
	private static int argument;

	//Textline for showing autocomplete suggestions and expected arguments of commands
	private static final String COMPLETION_COLOR = "#606060";
	private static TextLine textLine = new TextLine(Fonts.PIXEL_FONT, "", CONSOLE_HEIGHT - 2, false);

	@Override
	public void init() {
		input = new TextInput();

		input.textLine.endSelection(0);
		input.setFocused(true);
		Mouse.setGrabbed(false);

		mode = NORMAL;
		textLine.updateText("");

		updateGUIScale();

		if (!gotData) {
			try {
				ObjectInputStream iS = new ObjectInputStream(new FileInputStream(PATH));
				consoleArray = (String[]) iS.readObject();
				end = (int) iS.readObject();
				iS.close();
			} catch (IOException ioE) {
				//Creates new history if cant read file(wrong format; doesnt exist; damaged)
				for (int i = 0; i < HISTORY_SIZE; i++) {
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
	}

	@Override
	public void updateGUIScale() {
		input.setBounds(0 * GUI_SCALE, 0 * GUI_SCALE, CONSOLE_WIDTH * GUI_SCALE, CONSOLE_HEIGHT * GUI_SCALE, Component.ALIGN_TOP_LEFT);
		input.setFontSize((CONSOLE_HEIGHT - 4) * GUI_SCALE);
	}

	public void update() {
		if (mode == NORMAL) {
			// Normal user input
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_TAB)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_TAB, false);
				updatePossibleCommands();
				if (possibleCommands.size() == 0) {
					mode = NORMAL;
				} else if (input.getText().contains("\\s+")) {
					findArguments();
					if (argument != -1) {
						mode = ARGUMENTS;

						showNextArgument();

						argument++;
					}
				} else if (possibleCommands.size() == 1) {
					input.setText(possibleCommands.get(0).getCommandName());
					expectedArgs = possibleCommands.get(0).getExpectedArgs();
					if (expectedArgs.length != 0) {
						mode = ARGUMENTS;
						argument = 0;
						showNextArgument();
						argument++;
					}
				} else {
					mode = AUTOCOMPLETE;
				}
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
				execute();
				Cubyz.gameUI.back();
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_UP)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_UP, false);
				if (!("".equals(consoleArray[(HISTORY_SIZE + current - 1) % HISTORY_SIZE]))) {
					mode = HISTORY;
					current = (HISTORY_SIZE + current - 1) % HISTORY_SIZE;
				}
			} 
		} else if (mode == AUTOCOMPLETE) {
			// Autcomplete command
			if (Keyboard.hasCharSequence()) {
				if (Keyboard.getCharSequence()[0] == ' ') {
					completeCommand();
				} else {
					mode = NORMAL;
				}
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_TAB) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_TAB, false);
				completeCommand();
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_UP)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_UP, false);
				commandSelection = (commandSelection + 1) % possibleCommands.size();
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_DOWN)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_DOWN, false);
				commandSelection = (possibleCommands.size() + commandSelection - 1) % possibleCommands.size();
			}
		} else if (mode == ARGUMENTS) {
			// Argument selection
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_BACKSPACE)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_BACKSPACE, false);
				if (argument == (input.getText() + "foo").split("(\\s)+").length) {
					mode = NORMAL;
				}
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_TAB) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
				if (argument < expectedArgs.length) {

					showNextArgument();

					argument++;
				} else {
					if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
						execute();
					}
				}
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_TAB, false);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
			}
		} else if (mode == HISTORY) {
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_UP) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_TAB)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_UP, false);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_TAB, false);
				if (!("".equals(consoleArray[(HISTORY_SIZE + current - 1) % HISTORY_SIZE]))) {
					current = (HISTORY_SIZE + current - 1) % HISTORY_SIZE;
				}
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_DOWN)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_DOWN, false);
				if (!("".equals(consoleArray[current]))) {
					current = (current + 1) % HISTORY_SIZE;
				}
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
				findArguments();
				if (argument != -1) {
					Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
					mode = ARGUMENTS;
					showNextArgument();
					argument++;
				} else {
					mode = NORMAL;
				}
			} else if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_BACKSPACE) || Keyboard.hasCharSequence() || Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_HOME)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_BACKSPACE, false);
				mode = NORMAL;
			}
		}
	}

	private void showNextArgument() {
		input.setText(input.getText() + " ");
		float startSelection = input.textLine.getTextWidth() + 10;
		input.setText(input.getText() + expectedArgs[argument]);
		input.textLine.startSelection(startSelection);
		input.textLine.endSelection(input.textLine.getTextWidth());
	}

	@Override
	public void render() {
		update();
		String text = input.getText();
		if (mode == NORMAL) {
			textLine.updateText("");
		} else if (mode == AUTOCOMPLETE) {
			textLine.updateText(COMPLETION_COLOR+possibleCommands.get(commandSelection).getCommandName().substring(text.length()));
		} else if (mode == ARGUMENTS) {
			String s = "";
			for (int i = argument; i < expectedArgs.length; i++) {
				s += " " + expectedArgs[i];
			}
			textLine.updateText(COMPLETION_COLOR+s);
		} else if (mode == HISTORY) {
			input.setText(consoleArray[current]);		
			input.textLine.endSelection(CONSOLE_WIDTH);
		}
		input.render();
		textLine.render(input.textLine.getTextWidth() + 4, 0);
	}

	private void execute() {
		//Adds to history
		String text = input.getText();
		if (text != "") {
			//Prevents multiple entries of the same command in history
			if (!text.equals(consoleArray[(HISTORY_SIZE + end - 1) % HISTORY_SIZE])) {
				consoleArray[end] = text;
				end = (end + 1) % HISTORY_SIZE;
			}
			current = end;
			consoleArray[current] = "";
			//Executes
			CommandExecutor.execute(text, Cubyz.player);
			//Resets
			textLine.updateText("");
			input.setText("");
			mode = NORMAL;
			//Saves history
			try {
				ObjectOutputStream oS = new ObjectOutputStream(new FileOutputStream(PATH));
				oS.writeObject(consoleArray);
				oS.writeObject(end);
				oS.close();
			} catch (IOException e) {
				Logger.error(e);
			}
		}
	}
	
	//Finds commands a sorted arraylist of commands starting with the userinput
	private void updatePossibleCommands() {
		String command = input.getText().split("\\s+")[0];
		possibleCommands.clear();
		for (int i = 0; i < COMMANDS.length; i++) {
			if (COMMANDS[i].getCommandName().startsWith(command)) {
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
		commandSelection = 0;
	}

	private void completeCommand() {
		CommandBase command = possibleCommands.get(commandSelection);
		input.setText(command.getCommandName());
		expectedArgs = command.getExpectedArgs();
		if (expectedArgs.length == 0) {
			mode = NORMAL;
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ENTER)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_ENTER, false);
				execute();
			}
		} else {
			mode = ARGUMENTS;
			argument = 0;
			showNextArgument();
			argument++;
		}
	}

	private void findArguments() {
		String[] commandAndArgs = input.getText().split("\\s+");
		CommandBase command = null;
		for (int i = 0; i < COMMANDS.length; i++) {
			if (COMMANDS[i].getCommandName().equals(commandAndArgs[0])) {
				command = COMMANDS[i];
				break;
			}
		}
		if (command == null) {
			argument = -1;
			return;
		}
		expectedArgs = command.getExpectedArgs();
		argument = commandAndArgs.length - 1;
		if (argument >= expectedArgs.length) {
			argument = -1;
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