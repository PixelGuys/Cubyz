package io.cubyz;

import static org.lwjgl.glfw.GLFW.*;

public class Keybindings {

	public static final String[] keyNames = {
		"forward",
		"backward",
		"left",
		"right"
	};
	
	public static final int[] keyCodes = {
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
	
}
