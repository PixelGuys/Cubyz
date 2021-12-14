package cubyz.gui.input;

import org.joml.Vector2d;

import cubyz.rendering.Window;

import static org.lwjgl.glfw.GLFW.*;

public abstract class Mouse {

	private static final Vector2d currentPos = new Vector2d();

	// Mouse deltas are averaged over multiple frames using a circular buffer:
	private static final float[] deltaX = new float[3],
								deltaY = new float[deltaX.length];
	private static int deltaBufferPosition = 0;

	private static boolean leftButtonPressed = false;
	private static boolean middleButtonPressed = false;
	private static boolean rightButtonPressed = false;

	private static boolean grabbed = false;

	private static boolean ignoreDataAfterRecentGrab = false;
	
	private static int lastScroll = 0, curScroll = 0, scrollOffset = 0;

	public static void clearDelta() {
		deltaBufferPosition++;
		deltaBufferPosition = deltaBufferPosition%deltaX.length;
		deltaX[deltaBufferPosition] = 0;
		deltaY[deltaBufferPosition] = 0;
	}
	
	public static double getScrollOffset() {
		return scrollOffset;
	}
	
	public static void clearScroll() {
		int last = lastScroll;
		lastScroll = curScroll;
		scrollOffset = lastScroll-last;
	}

	public static boolean isGrabbed() {
		return grabbed;
	}

	public static void setGrabbed(boolean grab) {
		if (grabbed != grab) {
			if (!grab) {
				glfwSetInputMode(Window.getWindowHandle(), GLFW_CURSOR, GLFW_CURSOR_NORMAL);
			} else {
				glfwSetInputMode(Window.getWindowHandle(), GLFW_CURSOR, GLFW_CURSOR_DISABLED);
				if (glfwRawMouseMotionSupported())
					glfwSetInputMode(Window.getWindowHandle(), GLFW_RAW_MOUSE_MOTION, GLFW_TRUE);
				ignoreDataAfterRecentGrab = true;
			}
			grabbed = grab;
		}
	}

	public static Vector2d getCurrentPos() {
		return currentPos;
	}

	public static double getX() {
		return currentPos.x;
	}

	public static double getY() {
		return currentPos.y;
	}

	public static void init() {
		glfwSetCursorPosCallback(Window.getWindowHandle(), (windowHandle, x, y) -> {
			if (grabbed && !ignoreDataAfterRecentGrab) {
				deltaX[deltaBufferPosition] += x - currentPos.x;
				deltaY[deltaBufferPosition] += y - currentPos.y;
			}
			ignoreDataAfterRecentGrab = false;
			currentPos.x = x;
			currentPos.y = y;
		});
		glfwSetMouseButtonCallback(Window.getWindowHandle(), (windowHandle, button, action, mode) -> {
			if (action == GLFW_PRESS || action == GLFW_RELEASE) {
				if (button == GLFW_MOUSE_BUTTON_1) {
					leftButtonPressed = action == GLFW_PRESS;
				}
				else if (button == GLFW_MOUSE_BUTTON_2) {
					rightButtonPressed = action == GLFW_PRESS;
				}
				else if (button == GLFW_MOUSE_BUTTON_3) {
					middleButtonPressed = action == GLFW_PRESS;
				}
			}
		});
		glfwSetScrollCallback(Window.getWindowHandle(), (windowHandle, xoffset, yoffset) -> {
			curScroll += yoffset;
		});
	}

	/**
	 * Calculates the mouse delta average of the last frames.
	 * @return x
	 */
	public static float getDeltaX() {
		float result = 0;
		for(int i = 0; i < deltaX.length; i++) {
			result += deltaX[i];
		}
		result /= deltaX.length;
		return result;
	}

	/**
	 * Calculates the mouse delta average of the last frames.
	 * @return y
	 */
	public static float getDeltaY() {
		float result = 0;
		for(int i = 0; i < deltaY.length; i++) {
			result += deltaY[i];
		}
		result /= deltaY.length;
		return result;
	}

	public static boolean isLeftButtonPressed() {
		return leftButtonPressed;
	}
	
	public static boolean isMiddleButtonPressed() {
		return middleButtonPressed;
	}

	public static boolean isRightButtonPressed() {
		return rightButtonPressed;
	}
}