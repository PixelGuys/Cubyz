package cubyz.gui.input;

import java.util.ArrayList;

import cubyz.utils.Logger;

import static org.lwjgl.glfw.GLFW.*;

public class Keyboard {

	static ArrayList<Integer> pressedKeys = new ArrayList<Integer>();
	static ArrayList<Integer> releasedKeys = new ArrayList<Integer>();
	private static int bufferLen = 256;
	static final char[] charBuffer = new char[bufferLen]; // Pseudo-circular buffer of the last chars, to avoid problems if the user is a fast typer or uses macros or compose key.
	private static int lastStart = 0, lastEnd = 0, current = 0;
	static int keyMods;
	
	/**
	 * There can be only one KeyListener to prevent issues like interacting with multiple GUI elements at the same time.
	 */
	public static KeyListener activeComponent;
	
	public static void pushChar(char ch) {
		int next = (current+1)%bufferLen;
		if (next == lastStart) {
			Logger.warning("Char buffer is full. Ignoring char '"+ch+"'.");
			return;
		}
		charBuffer[current] = ch;
		current = next;
	}
	
	public static boolean hasCharSequence() {
		return lastStart != lastEnd;
	}

	public static void glfwKeyCallback(int key, int scancode, int action, int mods) {
		setKeyPressed(key, action != GLFW_RELEASE);
		setKeyMods(mods);
		if(action == GLFW_RELEASE) {
			releasedKeys.add(key);
		}
	}
	
	/**
	 * Returns the last chars input by the user.
	 * @return chars typed in by the user. Calls to backspace are encrypted using '\0'.
	 */
	public static char[] getCharSequence() {
		char[] sequence = new char[(lastEnd - lastStart + bufferLen)%bufferLen];
		int index = 0;
		for(int i = lastStart; i != lastEnd; i = (i+1)%bufferLen) {
			sequence[index++] = charBuffer[i];
		}
		return sequence;
	}
	
	/**
	 * Resets buffers.
	 */
	public static void release() {
		lastStart = lastEnd;
		lastEnd = current;
		releasedKeys.clear();
	}
	
	public static boolean isKeyPressed(int key) {
		return pressedKeys.contains(key);
	}
	
	public static boolean isKeyReleased(int key) {
		return releasedKeys.contains(key);
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
			if (activeComponent != null)
				activeComponent.onKeyPress(key);
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
