package io.cubyz;

import static org.lwjgl.glfw.GLFW.*;

public class Keybindings {

	public static String[] keyNames = {
		"forward",
		"backward",
		"left",
		"right",
		"jump",
		"fall",
		"inventory",
		"menu",
		"hotbar 1",
		"hotbar 2",
		"hotbar 3",
		"hotbar 4",
		"hotbar 5",
		"hotbar 6",
		"hotbar 7",
		"hotbar 8"
	};
	
	public static int[] keyCodes = {
			GLFW_KEY_W,
			GLFW_KEY_S,
			GLFW_KEY_A,
			GLFW_KEY_D,
			GLFW_KEY_SPACE,
			GLFW_KEY_LEFT_SHIFT,
			GLFW_KEY_I,
			GLFW_KEY_ESCAPE,
			GLFW_KEY_1,
			GLFW_KEY_2,
			GLFW_KEY_3,
			GLFW_KEY_4,
			GLFW_KEY_5,
			GLFW_KEY_6,
			GLFW_KEY_7,
			GLFW_KEY_8,
	};
	
	public static void setKeyCode(String name, int key) {
		for (int i = 0; i < keyNames.length; i++) {
			if (keyNames[i].equals(name)) {
				keyCodes[i] = key;
			}
		}
	}
	
	public static int getKeyCode(String name) {
		for (int i = 0; i < keyNames.length; i++) {
			if (keyNames[i].equals(name)) {
				return keyCodes[i];
			}
		}
		return -1;
	}
	
	/**
	 * Registers keybinding <code>name</code> with default value <code>def</code>
	 * @param name
	 * @param def
	 * @throws Error If keybinding is already defined
	 */
	public static void register(String name, int def) {
		if (getKeyCode(name) != -1) {
			throw new Error("Keybinding " + name + " already exists");
		}
		String[] newKeyNames = new String[keyNames.length+1];
		int[] newKeyCodes = new int[keyCodes.length+1];
		
		System.arraycopy(keyNames, 0, newKeyNames, 0, keyNames.length);
		System.arraycopy(keyCodes, 0, newKeyCodes, 0, keyCodes.length);
		
		newKeyNames[keyNames.length] = name;
		newKeyCodes[keyCodes.length] = def;
		
		keyNames = newKeyNames;
		keyCodes = newKeyCodes;
	}
	
}
