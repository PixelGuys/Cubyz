package org.jungle;

import java.util.ArrayList;

public class Keyboard {

	static ArrayList<Integer> pressedKeys;
	
	static {
		pressedKeys = new ArrayList<Integer>();
	}
	
	public static boolean isKeyPressed(int key) {
		return pressedKeys.contains(key);
	}
	
	public static void setKeyPressed(int key, boolean press) {
		if (press) {
			if (!pressedKeys.contains(key)) {
				pressedKeys.add(key);
			}
		} else {
			if (pressedKeys.contains(key)) {
				pressedKeys.remove((Integer) key);
			}
		}
	}

}
