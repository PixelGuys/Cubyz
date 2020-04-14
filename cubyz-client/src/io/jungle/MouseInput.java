package io.jungle;

import org.joml.Vector2d;
import org.joml.Vector2f;
import static org.lwjgl.glfw.GLFW.*;

import java.awt.MouseInfo;
import java.awt.Robot;

public class MouseInput {

	private final Vector2d currentPos;

	private final Vector2f displVec;

	private boolean inWindow = false;

	private boolean leftButtonPressed = false;
	private boolean middleButtonPressed = false;
	private boolean rightButtonPressed = false;

	private boolean grabbed = false;
	private Window win;
	private Robot r;
	
	int lastScroll = 0, curScroll = 0, scrollOffset = 0;

	public MouseInput() {
		currentPos = new Vector2d(0, 0);
		displVec = new Vector2f(0, 0);
		try {
			r = new Robot();
		} catch(Exception e) {
			e.printStackTrace();
		}
	}

	public void clearPos(int x, int y) {
		currentPos.set(x, y);
		displVec.set(0, 0);
	}
	
	public double getScrollOffset() {
		return scrollOffset;
	}
	
	public void clearScroll() {
		int last = lastScroll;
		lastScroll = curScroll;
		scrollOffset = lastScroll-last;
		
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
			curScroll += yoffset;
		});
	}

	public Vector2f getDisplVec() {
		return displVec;
	}

	public void input(Window window) {
		int[] pos = window.getPosition();
//		System.out.println("Focused: " + window.isFocused());
//		System.out.println("Grabbed: " + grabbed);
		currentPos.x = MouseInfo.getPointerInfo().getLocation().getX() - pos[0];
		currentPos.y = MouseInfo.getPointerInfo().getLocation().getY() - pos[1];
		if(grabbed /*&& window.isFocused()*/) {
			displVec.y += currentPos.x - (window.getWidth() >> 1);
			displVec.x += currentPos.y - (window.getHeight() >> 1);
			r.mouseMove(pos[0] + (window.getWidth() >> 1), pos[1] + (window.getHeight() >> 1));
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