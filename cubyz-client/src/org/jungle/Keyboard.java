package org.jungle;

import java.util.ArrayList;

public class Keyboard {

	static ArrayList<Integer> pressedKeys;
	static char currentCodePoint;
	static boolean hasCodePoint;
	static int keyMods;
	
	static {
		pressedKeys = new ArrayList<Integer>();
		currentCodePoint = 0;
		hasCodePoint = false;
	}
	
	public static void pushCodePoint(char codePoint) {
		currentCodePoint = codePoint;
		hasCodePoint = true;
	}
	
	public static boolean hasCodePoint() {
		return hasCodePoint;
	}
	
	/**
	 * Reads code point, keeps it on buffer.
	 * @return code point
	 */
	public static char getCodePoint() {
		return currentCodePoint;
	}
	
	/**
	 * Reads code point, does not keep it on buffer.
	 * @return code point
	 */
	public static char releaseCodePoint() {
		char cp = currentCodePoint;
		currentCodePoint = 0;
		hasCodePoint = false;
		return cp;
	}
	
	public static boolean isKeyPressed(int key) {
		return pressedKeys.contains(key);
	}
	
	/**
	 * Key mods are additional control key pressed with the current key. (e.g. C is pressed with Shift+Ctrl)
	 * @return key mods
	 */
	public static int getKeyMods() {
		return keyMods;
	}
	
	public static void setKeyMods(int mods) {
		keyMods = mods;
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
