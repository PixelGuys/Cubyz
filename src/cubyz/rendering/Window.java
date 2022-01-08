package cubyz.rendering;

import static org.lwjgl.glfw.GLFW.*;
import static org.lwjgl.opengl.GL13.*;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.NULL;

import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.nio.IntBuffer;

import javax.swing.JOptionPane;

import org.joml.Matrix4f;
import org.joml.Vector4f;
import org.lwjgl.PointerBuffer;
import org.lwjgl.glfw.GLFWErrorCallback;
import org.lwjgl.glfw.GLFWVidMode;
import org.lwjgl.opengl.GL;
import org.lwjgl.opengl.GL11;
import org.lwjgl.system.Library;
import org.lwjgl.system.MemoryStack;

import cubyz.utils.Logger;
import cubyz.client.Cubyz;
import cubyz.gui.input.Keyboard;
import cubyz.gui.menu.DebugOverlay;

public abstract class Window {

	private static long handle;
	private static int width = 1280, height = 720;
	private static boolean resized = true;
	private static final Matrix4f projectionMatrix = new Matrix4f();
	private static boolean fullscreen = false;
	private static FrameBuffer buffer;
	private static boolean focused = false;
	private static boolean vsync = true;
	private static int antiAlias = 0;
	
	private static Vector4f clearColor;
	
	static {
		try {
			Library.initialize(); // initialize LWJGL libraries to be able to catch any potential errors (like missing library)
		} catch (UnsatisfiedLinkError e) {
			Logger.crash("Missing LWJGL libraries for " + 
					System.getProperty("os.name") + " on " + System.getProperty("os.arch"));
			JOptionPane.showMessageDialog(null, "Missing LWJGL libraries for " + 
					System.getProperty("os.name") + " on " + System.getProperty("os.arch"), "Error", JOptionPane.ERROR_MESSAGE);
			System.exit(1);
		}
	}
	
	public static Vector4f getClearColor() {
		return clearColor;
	}
	
	public static Matrix4f getProjectionMatrix() {
		return projectionMatrix;
	}

	public static void setClearColor(Vector4f clearColor) {
		Window.clearColor = clearColor;
		glClearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
	}

	public static boolean isResized() {
		return resized;
	}
	
	public static long getWindowHandle() {
		return handle;
	}
	
	public static boolean shouldClose() {
		return glfwWindowShouldClose(handle);
	}

	public static void setResized(boolean resized) {
		Window.resized = resized;
	}

	public static int getWidth() {
		return width;
	}

	public static int getHeight() {
		return height;
	}
	
	public static void setSize(int width, int height) {
		glfwSetWindowSize(handle, width, height);
	}
	
	public static void setTitle(String title) {
		glfwSetWindowTitle(handle, title);
	}
	
	public static boolean isFullscreen() {
		return fullscreen;
	}
	
	private static int oldX, oldY, oldW, oldH;
	public static void setFullscreen(boolean fullscreen) {
		if (fullscreen != Window.fullscreen) {
			Window.fullscreen = fullscreen;
			if (fullscreen) {
				try (MemoryStack stack = stackPush()) {
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
				}
				GraphicsDevice gd = GraphicsEnvironment.getLocalGraphicsEnvironment().getDefaultScreenDevice();
				int width = gd.getDisplayMode().getWidth();
				int height = gd.getDisplayMode().getHeight();
				glfwSetWindowMonitor(handle, glfwGetPrimaryMonitor(), 0, 0, width, height, GLFW_DONT_CARE);
			} else {
				glfwSetWindowMonitor(handle, NULL, oldX, oldY, oldW, oldH, GLFW_DONT_CARE);
				glfwSetWindowAttrib(handle, GLFW_DECORATED, GLFW_TRUE);
			}
		}
	}
	
	public static int[] getPosition() {
		int[] pos = new int[2];
		try (MemoryStack stack = stackPush()) {
			IntBuffer x = stack.mallocInt(1);
			IntBuffer y = stack.mallocInt(1);
			glfwGetWindowPos(handle, x, y);
			pos[0] = x.get(0);
			pos[1] = y.get(0);
		}
		return pos;
	}
	
	private static boolean inited;

	private static void init(long monitorID) {
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
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
		glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_ANY_PROFILE);
		glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE); // allow to use newer versions (if available) at the price of having deprecated features possibly removed
		glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);

		handle = glfwCreateWindow(width, height, "Cubyz", monitorID, NULL);
		if (handle == NULL) {
			int err = glfwGetError(PointerBuffer.allocateDirect(1));
			if (err == 65543 || err == 65540) { // we want a too much recent version
				Logger.warning("A legacy version of OpenGL will be used as 3.3 is unavailable!");
				glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
				glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
				glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_ANY_PROFILE);
				glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_FALSE);
				// so let's use the minimum version
				handle = glfwCreateWindow(width, height, "Cubyz", monitorID, NULL);
				if (handle == NULL) {
					throw new RuntimeException("Failed to create the GLFW window (code = " + err + ")");
				}
			} else {
				throw new RuntimeException("Failed to create the GLFW window (code = " + err + ")");
			}
		}
		try (MemoryStack stack = stackPush()) {
			IntBuffer pWidth = stack.mallocInt(1);
			IntBuffer pHeight = stack.mallocInt(1);

			// Get the window size passed to glfwCreateWindow
			glfwGetWindowSize(handle, pWidth, pHeight);

			// Get the resolution of the primary monitor
			GLFWVidMode vidmode = glfwGetVideoMode(glfwGetPrimaryMonitor());

			// Center the window
			glfwSetWindowPos(handle, (vidmode.width() - pWidth.get(0)) >> 1, (vidmode.height() - pHeight.get(0)) >> 1);
		} // the stack frame is popped automatically

		glfwSetCharCallback(handle, (window, codePoint) -> {
			Keyboard.pushChar((char) codePoint);
		});
		
		glfwSetKeyCallback(handle, (window, key, scancode, action, mods) -> {
			Keyboard.glfwKeyCallback(key, scancode, action, mods);
		});
		
		glfwSetFramebufferSizeCallback(handle, (window, width, height) -> {
			Window.width = width;
			Window.height = height;
			Window.setResized(true);
			Cubyz.gameUI.updateGUIScale();
		});
		
		glfwSetWindowFocusCallback(handle, (window, focused) -> {
			Window.focused = focused;
		});
		
		glfwMakeContextCurrent(handle);
		GL.createCapabilities();
		if (clearColor == null) {
			setClearColor(new Vector4f(0.f, 0.f, 0.f, 0.f));
		}
		
		Logger.info("OpenGL Version: " + GL11.glGetString(GL11.GL_VERSION));
		show();
		restoreState();
	}
	
	public static void setVSyncEnabled(boolean vsync) {
		glfwMakeContextCurrent(handle);
		glfwSwapInterval(vsync ? 1 : 0);
		Window.vsync = vsync;
	}
	
	public static boolean isVSyncEnabled() {
		return vsync;
	}
	
	public static void init() {
		init(NULL);
	}
	
	/**
	 * Alongside rendering to the screen, will also write to the buffer.
	 * @param buffer
	 */
	public static void setRenderTarget(FrameBuffer buffer) {
		if (buffer == null) {
			Window.buffer.unbind();
		} else {
			buffer.bind();
		}
		Window.buffer = buffer;
	}
	
	public static int getAntialiasSamples() {
		return antiAlias;
	}
	
	public static boolean isAntialiasEnabled() {
		return antiAlias != 0;
	}
	
	public static boolean isFocused() {
		return focused;
	}
	
	public static FrameBuffer getRenderTarget() {
		return buffer;
	}
	
	public static boolean hasRenderTarget() {
		return buffer != null;
	}
	
	// Used to restore state, as NanoVG can touch some OpenGL parameters
	public static void restoreState() {
		glEnable(GL_DEPTH_TEST);
		glEnable(GL_CULL_FACE);
		glCullFace(GL_BACK);
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		// TODO use OpenGL multisampling: https://www.khronos.org/opengl/wiki/Multisampling or GLFW_SAMPLES
	}
	
	public static void show() {
		glfwShowWindow(handle);
	}
	
	private static long lastTime = System.nanoTime();
	public static void render() {
		glfwMakeContextCurrent(handle);
		glfwSwapBuffers(handle);
		glfwPollEvents();
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
		long newTime = System.nanoTime();
		float deltaTime = (newTime - lastTime)/1e6f;
		DebugOverlay.addFrameTime(deltaTime);
		lastTime = newTime;
	}
	
}
