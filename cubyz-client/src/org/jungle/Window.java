package org.jungle;

import static org.lwjgl.glfw.GLFW.*;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.NULL;

import java.nio.IntBuffer;
import java.util.Objects;

import org.joml.Matrix4f;
import org.joml.Vector4f;
import org.jungle.game.GameOptions;
import org.jungle.viewport.FullViewportManager;
import org.jungle.viewport.ViewportManager;
import org.lwjgl.PointerBuffer;
import org.lwjgl.glfw.GLFWErrorCallback;
import org.lwjgl.glfw.GLFWVidMode;
import org.lwjgl.opengl.GL;
import org.lwjgl.system.MemoryStack;

public class Window {

	private long handle;
	private int width, height;
	private boolean resized;
	private Matrix4f projectionMatrix;
	private GameOptions opt;
	private boolean fullscreen = false;
	private ViewportManager manager = new FullViewportManager();
	
	private Vector4f clearColor;
	
	public ViewportManager getViewportManager() {
		return manager;
	}
	
	public void setViewportManager(ViewportManager viewport) {
		Objects.requireNonNull(viewport, "viewport manager");
		manager = viewport;
	}
	
	public Vector4f getClearColor() {
		return clearColor;
	}
	
	public Matrix4f getProjectionMatrix() {
		return projectionMatrix;
	}
	
	public void setProjectionMatrix(Matrix4f projectionMatrix) {
		this.projectionMatrix = projectionMatrix;
	}

	public void setClearColor(Vector4f clearColor) {
		this.clearColor = clearColor;
		glClearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
	}
	
	public GameOptions getOptions() {
		return opt;
	}

	public boolean isResized() {
		return resized;
	}
	
	public long getWindowHandle() {
		return handle;
	}
	
	public boolean shouldClose() {
		return glfwWindowShouldClose(handle);
	}

	public void setResized(boolean resized) {
		this.resized = resized;
	}

	public int getWidth() {
		return width;
	}

	public int getHeight() {
		return height;
	}
	
	public void setSize(int width, int height) {
		glfwSetWindowSize(handle, width, height);
	}
	
	public void setTitle(String title) {
		glfwSetWindowTitle(handle, title);
	}
	
	public boolean isFullscreen() {
		return fullscreen;
	}
	
	int oldX, oldY, oldW, oldH;
	public void setFullscreen(boolean fullscreen) {
		if (fullscreen != this.fullscreen) {
			this.fullscreen = fullscreen;
			if (fullscreen) {
				MemoryStack stack = stackPush();
				IntBuffer x = stack.mallocInt(1);
				IntBuffer y = stack.mallocInt(1);
				IntBuffer width = stack.mallocInt(1);
				IntBuffer height = stack.mallocInt(1);
				glfwGetWindowPos(handle, x, y);
				glfwGetWindowSize(handle, width, height);
				oldX = x.get(0);
				oldY = y.get(0);
				oldW = width.get(0);
				oldH = height.get(0);
				stack.close();
				glfwSetWindowMonitor(handle, glfwGetPrimaryMonitor(), 0, 0, 1920, 1080, GLFW_DONT_CARE);
			} else {
				glfwSetWindowMonitor(handle, NULL, oldX, oldY, oldW, oldH, GLFW_DONT_CARE);
				glfwSetWindowAttrib(handle, GLFW_DECORATED, GLFW_TRUE);
			}
		}
	}
	
	public void setOptions(GameOptions opt) {
		this.opt = opt;
		glfwMakeContextCurrent(handle);
		if (opt.showTriangles) {
            glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
		} else {
			glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
		}
		if (opt.antialiasing) {
		    glfwWindowHint(GLFW_SAMPLES, 2);
		} else {
			glfwWindowHint(GLFW_SAMPLES, 0);
		}
		if (opt.cullFace) {
			glEnable(GL_CULL_FACE);
			glCullFace(GL_BACK);
		} else {
			glDisable(GL_CULL_FACE);
		}
		if (opt.blending) {
			glEnable(GL_BLEND);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		} else {
			glDisable(GL_BLEND);
		}
		setFullscreen(opt.fullscreen);
	}
	
	private static boolean inited;

	private void init(GameOptions opt, long monitorID) {
		if (!inited) {
			GLFWErrorCallback.createPrint(System.err).set();
			if (!glfwInit())
				throw new IllegalStateException("Unable to initialize GLFW");
			inited = true;
		}
		glfwDefaultWindowHints();
		glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE); // the window will be resizable
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
	    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 7);
	    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
	    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

		handle = glfwCreateWindow(640, 480, "Cubyz", monitorID, NULL);
		if (handle == NULL) {
			int err = glfwGetError(PointerBuffer.allocateDirect(1));
			if (err == 65543) { // we want a too much recent version
				handle = glfwCreateWindow(640, 480, "Cubyz", monitorID, NULL);
				if (handle == NULL) {
					throw new RuntimeException("Failed to create the GLFW window (code = " + err + ")");
				}
			} else {
				throw new RuntimeException("Failed to create the GLFW window (code = " + err + ")");
			}
		}
		try (MemoryStack stack = stackPush()) {
			IntBuffer pWidth = stack.mallocInt(1); // int*
			IntBuffer pHeight = stack.mallocInt(1); // int*

			// Get the window size passed to glfwCreateWindow
			glfwGetWindowSize(handle, pWidth, pHeight);

			// Get the resolution of the primary monitor
			GLFWVidMode vidmode = glfwGetVideoMode(glfwGetPrimaryMonitor());

			// Center the window
			glfwSetWindowPos(handle, (vidmode.width() - pWidth.get(0)) >> 1, (vidmode.height() - pHeight.get(0)) >> 1);
		} // the stack frame is popped automatically

		glfwSetCharCallback(handle, (window, codePoint) -> {
			Keyboard.pushCodePoint((char) codePoint);
		});
		
		glfwSetKeyCallback(handle, (window, key, scancode, action, mods) -> {
			if (action == GLFW_PRESS) {
				Keyboard.setKeyPressed(key, true);
			}
			if (action == GLFW_RELEASE) {
				Keyboard.setKeyPressed(key, false);
			}
			Keyboard.setKeyMods(mods);
		});
		
		glfwSetFramebufferSizeCallback(handle, (window, width, height) -> {
		    Window.this.width = width;
		    Window.this.height = height;
		    Window.this.setResized(true);
		});
		
		glfwMakeContextCurrent(handle);
		GL.createCapabilities();
		if (clearColor == null) {
			setClearColor(new Vector4f(0.f, 0.f, 0.f, 0.f));
		}
		
		glEnable(GL_DEPTH_TEST);
		glEnable(GL_STENCIL_TEST);
		setOptions(opt);
	}
	
	public void init(GameOptions opt) {
		init(opt, NULL);
	}
	
	public void restoreState() {
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_STENCIL_TEST);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        if (opt.cullFace) {
            glEnable(GL_CULL_FACE);
            glCullFace(GL_BACK);
        }
        if (opt.blending) {
			glEnable(GL_BLEND);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }
	}
	
	public void show() {
		glfwShowWindow(handle);
	}
	
	public void update() {
		
	}
	
	public void render() {
		glfwMakeContextCurrent(handle);
		glfwSwapBuffers(handle);
		glfwPollEvents();
	}
	
}
