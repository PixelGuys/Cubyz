package cubyz.gui.input;

import org.joml.Vector2d;
import org.joml.Vector2f;

import cubyz.Logger;
import cubyz.client.GameLauncher;
import cubyz.rendering.Window;

import static org.lwjgl.glfw.GLFW.*;

import java.awt.MouseInfo;
import java.awt.Point;
import java.awt.Robot;

public abstract class Mouse {

	private static final Vector2d currentPos = new Vector2d();
	private static final Vector2f displVec = new Vector2f();

	private static boolean leftButtonPressed = false;
	private static boolean middleButtonPressed = false;
	private static boolean rightButtonPressed = false;

	private static boolean grabbed = false;
	private static Robot r;
	
	private static int lastScroll = 0, curScroll = 0, scrollOffset = 0;

	static {
		try {
			r = new Robot();
		} catch (Exception e) {
			Logger.throwable(e);
		}
	}

	public static void clearPos(int x, int y) {
		currentPos.set(x, y);
		displVec.set(0, 0);
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
				int[] pos = Window.getPosition();
				r.mouseMove(pos[0] + Window.getWidth() / 2, pos[1] + Window.getHeight() / 2);
				glfwSetInputMode(Window.getWindowHandle(), GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
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

	public static Vector2f getDisplVec() {
		return displVec;
	}

	public static void input() {
		int[] pos = Window.getPosition();
		Point mousePosition = MouseInfo.getPointerInfo().getLocation();
		currentPos.x = mousePosition.getX() - pos[0];
		currentPos.y = mousePosition.getY() - pos[1];
		if (grabbed && Window.isFocused()) {
			displVec.y += currentPos.x - (Window.getWidth() >> 1);
			displVec.x += currentPos.y - (Window.getHeight() >> 1);
			if (GameLauncher.instance.getRenderThread().isAlive() && GameLauncher.instance.getUpdateThread().isAlive()) {
				r.mouseMove(pos[0] + (Window.getWidth() >> 1), pos[1] + (Window.getHeight() >> 1));
			}
		}
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