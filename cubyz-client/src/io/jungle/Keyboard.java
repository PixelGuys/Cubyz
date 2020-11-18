package io.jungle;

import java.util.ArrayList;

import io.cubyz.CubyzLogger;

public class Keyboard {

	static ArrayList<Integer> pressedKeys = new ArrayList<Integer>();
	private static int bufferLen = 256;
	static final char[] charBuffer = new char[bufferLen]; // Pseudo-circular buffer of the last chars, to avoid problems if the user is a fast typer or uses macros or compose key.
	private static int lastStart = 0, lastEnd = 0, current = 0;
	static int currentKeyCode;
	static boolean hasKeyCode;
	static int keyMods;
	
	public static void pushChar(char ch) {
		int next = (current+1)%bufferLen;
		if(next == lastStart) {
			CubyzLogger.logger.warning("Char buffer is full. Ignoring char '"+ch+"'.");
			return;
		}
		charBuffer[current] = ch;
		current = next;
	}
	
	public static boolean hasCharSequence() {
		return lastStart != lastEnd;
	}
	
	/**
	 * Returns the last chars input by the user.
	 * @return
	 */
	public static String getCharSequence() {
		String sequence = "";
		for(int i = lastStart; i != lastEnd; i = (i+1)%bufferLen) {
			sequence += charBuffer[i];
		}
		return sequence;
	}
	
	public static void pushKeyCode(int keyCode) {
		currentKeyCode = keyCode;
		hasKeyCode = true;
	}
	
	public static boolean hasKeyCode() {
		return hasKeyCode;
	}
	
	/**
	 * Resets buffers.
	 */
	public static void release() {
		releaseKeyCode();
		lastStart = lastEnd;
		lastEnd = current;
	}
	
	/**
	 * Reads key code, keeps it on buffer.
	 * @return key code
	 */
	public static int getKeyCode() {
		return currentKeyCode;
	}
	
	/**
	 * Reads key code, does not keep it on buffer.
	 * @return key code
	 */
	public static int releaseKeyCode() {
		int kc = currentKeyCode;
		currentKeyCode = 0;
		hasKeyCode = false;
		return kc;
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
