package org.jungle;

import org.joml.Vector2d;
import org.joml.Vector2f;
import static org.lwjgl.glfw.GLFW.*;

public class MouseInput {

	private final Vector2d previousPos;

	private final Vector2d currentPos;

	private final Vector2f displVec;

	private boolean inWindow = false;

	private boolean leftButtonPressed = false;
	private boolean middleButtonPressed = false;
	private boolean rightButtonPressed = false;

	private boolean grabbed = false;
	private Window win;
	
	private double scrollOffset;

	public MouseInput() {
		previousPos = new Vector2d(0, 0);
		currentPos = new Vector2d(0, 0);
		displVec = new Vector2f();
	}

	public void clearPos(int x, int y) {
		currentPos.set(x, y);
		displVec.set(0, 0);
		previousPos.set(x, y);
	}
	
	public void clearScroll() {
		scrollOffset = 0;
	}
	
	public double getScrollOffset() {
		return scrollOffset;
	}

	public boolean isGrabbed() {
		return grabbed;
	}

	public void setGrabbed(boolean grab) {
		if (win == null) {
			throw new IllegalStateException("init() must be called before setGrabbed");
		}
		if (grabbed != grab) {
			if (!grab) {
				glfwSetInputMode(win.getWindowHandle(), GLFW_CURSOR, GLFW_CURSOR_NORMAL);
			}
			else {
				glfwSetInputMode(win.getWindowHandle(), GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
			}
			grabbed = grab;
		}
	}

	public Vector2d getCurrentPos() {
		return currentPos;
	}

	public double getX() {
		return currentPos.x;
	}

	public double getY() {
		return currentPos.y;
	}

	public void init(Window window) {
		win = window;
		glfwSetCursorPosCallback(window.getWindowHandle(), (windowHandle, xpos, ypos) -> {
			currentPos.x = xpos;
			currentPos.y = ypos;
		});
		glfwSetCursorEnterCallback(window.getWindowHandle(), (windowHandle, entered) -> {
			inWindow = entered;
		});
		glfwSetMouseButtonCallback(window.getWindowHandle(), (windowHandle, button, action, mode) -> {

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
		glfwSetScrollCallback(window.getWindowHandle(), (windowHandle, xoffset, yoffset) -> {
			scrollOffset = yoffset;
		});
	}

	public Vector2f getDisplVec() {
		return displVec;
	}

	public void input(Window window) {
		displVec.x = 0;
		displVec.y = 0;
		if (inWindow) {
			double deltax = currentPos.x - previousPos.x;
			double deltay = currentPos.y - previousPos.y;
			if (deltax != 0) {
				displVec.y = (float) deltax;
			}
			if (deltay != 0) {
				displVec.x = (float) deltay;
			}
		}
		previousPos.x = currentPos.x;
		previousPos.y = currentPos.y;
		if (grabbed) {
			glfwSetCursorPos(window.getWindowHandle(), window.getWidth() >> 1, window.getHeight() >> 1);
			previousPos.x = window.getWidth() >> 1;
			previousPos.y = window.getHeight() >> 1;
		}
	}

	public boolean isLeftButtonPressed() {
		return leftButtonPressed;
	}
	
	public boolean isMiddleButtonPressed() {
		return middleButtonPressed;
	}

	public boolean isRightButtonPressed() {
		return rightButtonPressed;
	}
}