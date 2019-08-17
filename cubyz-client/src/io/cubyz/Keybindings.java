package io.cubyz;

import static org.lwjgl.glfw.GLFW.*;

public class Keybindings {

	public static String[] keyNames = {
		"forward",
		"backward",
		"left",
		"right"
	};
	
	public static int[] keyCodes = {
			GLFW_KEY_W,
			GLFW_KEY_S,
			GLFW_KEY_A,
			GLFW_KEY_D
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
