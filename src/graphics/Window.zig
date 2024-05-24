const std = @import("std");

const main = @import("root");
const vec = main.vec;
const Vec2f = vec.Vec2f;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

var isFullscreen: bool = false;
pub var width: u31 = 1280;
pub var height: u31 = 720;
pub var window: *c.GLFWwindow = undefined;
pub var grabbed: bool = false;
pub var scrollOffset: f32 = 0;

pub const Key = struct {
	name: []const u8,
	pressed: bool = false,
	key: c_int = c.GLFW_KEY_UNKNOWN,
	mouseButton: c_int = -1,
	scancode: c_int = 0,
	releaseAction: ?*const fn() void = null,
	pressAction: ?*const fn() void = null,
	repeatAction: ?*const fn(Modifiers) void = null,

	pub const Modifiers = packed struct(u6) {
		shift: bool = false,
		control: bool = false,
		alt: bool = false,
		super: bool = false,
		capsLock: bool = false,
		numLock: bool = false,
	};

	pub fn getName(self: Key) []const u8 {
		if(self.mouseButton == -1) {
			const cName = c.glfwGetKeyName(self.key, self.scancode);
			if(cName != null) return std.mem.span(cName);
			return switch(self.key) {
				c.GLFW_KEY_SPACE => "Space",
				c.GLFW_KEY_GRAVE_ACCENT => "Grave Accent",
				c.GLFW_KEY_ESCAPE => "Escape",
				c.GLFW_KEY_ENTER => "Enter",
				c.GLFW_KEY_TAB => "Tab",
				c.GLFW_KEY_BACKSPACE => "Backspace",
				c.GLFW_KEY_INSERT => "Insert",
				c.GLFW_KEY_DELETE => "Delete",
				c.GLFW_KEY_RIGHT => "Right",
				c.GLFW_KEY_LEFT => "Left",
				c.GLFW_KEY_DOWN => "Down",
				c.GLFW_KEY_UP => "Up",
				c.GLFW_KEY_PAGE_UP => "Page Up",
				c.GLFW_KEY_PAGE_DOWN => "Page Down",
				c.GLFW_KEY_HOME => "Home",
				c.GLFW_KEY_END => "End",
				c.GLFW_KEY_CAPS_LOCK => "Caps Lock",
				c.GLFW_KEY_SCROLL_LOCK => "Scroll Lock",
				c.GLFW_KEY_NUM_LOCK => "Num Lock",
				c.GLFW_KEY_PRINT_SCREEN => "Print Screen",
				c.GLFW_KEY_PAUSE => "Pause",
				c.GLFW_KEY_F1 => "F1",
				c.GLFW_KEY_F2 => "F2",
				c.GLFW_KEY_F3 => "F3",
				c.GLFW_KEY_F4 => "F4",
				c.GLFW_KEY_F5 => "F5",
				c.GLFW_KEY_F6 => "F6",
				c.GLFW_KEY_F7 => "F7",
				c.GLFW_KEY_F8 => "F8",
				c.GLFW_KEY_F9 => "F9",
				c.GLFW_KEY_F10 => "F10",
				c.GLFW_KEY_F11 => "F11",
				c.GLFW_KEY_F12 => "F12",
				c.GLFW_KEY_F13 => "F13",
				c.GLFW_KEY_F14 => "F14",
				c.GLFW_KEY_F15 => "F15",
				c.GLFW_KEY_F16 => "F16",
				c.GLFW_KEY_F17 => "F17",
				c.GLFW_KEY_F18 => "F18",
				c.GLFW_KEY_F19 => "F19",
				c.GLFW_KEY_F20 => "F20",
				c.GLFW_KEY_F21 => "F21",
				c.GLFW_KEY_F22 => "F22",
				c.GLFW_KEY_F23 => "F23",
				c.GLFW_KEY_F24 => "F24",
				c.GLFW_KEY_F25 => "F25",
				c.GLFW_KEY_KP_ENTER => "Keypad Enter",
				c.GLFW_KEY_LEFT_SHIFT => "Left Shift",
				c.GLFW_KEY_LEFT_CONTROL => "Left Control",
				c.GLFW_KEY_LEFT_ALT => "Left Alt",
				c.GLFW_KEY_LEFT_SUPER => "Left Super",
				c.GLFW_KEY_RIGHT_SHIFT => "Right Shift",
				c.GLFW_KEY_RIGHT_CONTROL => "Right Control",
				c.GLFW_KEY_RIGHT_ALT => "Right Alt",
				c.GLFW_KEY_RIGHT_SUPER => "Right Super",
				c.GLFW_KEY_MENU => "Menu",
				else => "Unknown Key",
			};
		} else {
			return switch(self.mouseButton) {
				c.GLFW_MOUSE_BUTTON_LEFT => "Left Button",
				c.GLFW_MOUSE_BUTTON_MIDDLE => "Middle Button",
				c.GLFW_MOUSE_BUTTON_RIGHT => "Right Button",
				else => "Other Mouse Button",
			};
		}
	}
};

pub const GLFWCallbacks = struct {
	fn errorCallback(errorCode: c_int, description: [*c]const u8) callconv(.C) void {
		std.log.err("GLFW Error({}): {s}", .{errorCode, description});
	}
	fn keyCallback(_: ?*c.GLFWwindow, glfw_key: c_int, scancode: c_int, action: c_int, _mods: c_int) callconv(.C) void {
		const mods: Key.Modifiers = @bitCast(@as(u6, @intCast(_mods)));
		if(action == c.GLFW_PRESS) {
			for(&main.KeyBoard.keys) |*key| {
				if(glfw_key == key.key) {
					if(glfw_key != c.GLFW_KEY_UNKNOWN or scancode == key.scancode) {
						key.pressed = true;
						if(key.pressAction) |pressAction| {
							pressAction();
						}
						if(key.repeatAction) |repeatAction| {
							repeatAction(mods);
						}
					}
				}
			}
			if(nextKeypressListener) |listener| {
				listener(glfw_key, -1, scancode);
				nextKeypressListener = null;
			}
		} else if(action == c.GLFW_RELEASE) {
			for(&main.KeyBoard.keys) |*key| {
				if(glfw_key == key.key) {
					if(glfw_key != c.GLFW_KEY_UNKNOWN or scancode == key.scancode) {
						key.pressed = false;
						if(key.releaseAction) |releaseAction| {
							releaseAction();
						}
					}
				}
			}
		} else if(action == c.GLFW_REPEAT) {
			for(&main.KeyBoard.keys) |*key| {
				if(glfw_key == key.key) {
					if(glfw_key != c.GLFW_KEY_UNKNOWN or scancode == key.scancode) {
						if(key.repeatAction) |repeatAction| {
							repeatAction(mods);
						}
					}
				}
			}
		}
	}
	fn charCallback(_: ?*c.GLFWwindow, codepoint: c_uint) callconv(.C) void {
		if(!grabbed) {
			main.gui.textCallbacks.char(@intCast(codepoint));
		}
	}

	pub fn framebufferSize(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
		std.log.info("Framebuffer: {}, {}", .{newWidth, newHeight});
		width = @intCast(newWidth);
		height = @intCast(newHeight);
		main.renderer.updateViewport(width, height, main.settings.fov);
		main.gui.updateGuiScale();
		main.gui.updateWindowPositions();
	}
	// Mouse deltas are averaged over multiple frames using a circular buffer:
	const deltasLen: u2 = 3;
	var deltas: [deltasLen]Vec2f = [_]Vec2f{Vec2f{0, 0}} ** 3;
	var deltaBufferPosition: u2 = 0;
	var currentPos: Vec2f = Vec2f{0, 0};
	var ignoreDataAfterRecentGrab: bool = true;
	fn cursorPosition(_: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
		const newPos = Vec2f {
			@floatCast(x),
			@floatCast(y),
		};
		if(grabbed and !ignoreDataAfterRecentGrab) {
			deltas[deltaBufferPosition] += (newPos - currentPos)*@as(Vec2f, @splat(main.settings.mouseSensitivity));
			var averagedDelta: Vec2f = Vec2f{0, 0};
			for(deltas) |delta| {
				averagedDelta += delta;
			}
			averagedDelta /= @splat(deltasLen);
			main.game.camera.moveRotation(averagedDelta[0]*0.0089, averagedDelta[1]*0.0089);
			deltaBufferPosition = (deltaBufferPosition + 1)%deltasLen;
			deltas[deltaBufferPosition] = Vec2f{0, 0};
		}
		ignoreDataAfterRecentGrab = false;
		currentPos = newPos;
	}
	fn mouseButton(_: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
		_ = mods;
		if(action == c.GLFW_PRESS) {
			for(&main.KeyBoard.keys) |*key| {
				if(button == key.mouseButton) {
					key.pressed = true;
					if(key.pressAction) |pressAction| {
						pressAction();
					}
				}
			}
			if(nextKeypressListener) |listener| {
				listener(c.GLFW_KEY_UNKNOWN, button, 0);
				nextKeypressListener = null;
			}
		} else if(action == c.GLFW_RELEASE) {
			for(&main.KeyBoard.keys) |*key| {
				if(button == key.mouseButton) {
					key.pressed = false;
					if(key.releaseAction) |releaseAction| {
						releaseAction();
					}
				}
			}
		}
	}
	fn scroll(_ : ?*c.GLFWwindow, xOffset: f64, yOffset: f64) callconv(.C) void {
		_ = xOffset;
		scrollOffset += @floatCast(yOffset);
	}
	fn glDebugOutput(source: c_uint, typ: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
		const sourceString: []const u8 = switch (source) {
			c.GL_DEBUG_SOURCE_API => "API",
			c.GL_DEBUG_SOURCE_APPLICATION => "Application",
			c.GL_DEBUG_SOURCE_OTHER => "Other",
			c.GL_DEBUG_SOURCE_SHADER_COMPILER => "Shader Compiler",
			c.GL_DEBUG_SOURCE_THIRD_PARTY => "Third Party",
			c.GL_DEBUG_SOURCE_WINDOW_SYSTEM => "Window System",
			else => "Unknown",
		};
		const typeString: []const u8 = switch (typ) {
			c.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR => "deprecated behavior",
			c.GL_DEBUG_TYPE_ERROR => "error",
			c.GL_DEBUG_TYPE_MARKER => "marker",
			c.GL_DEBUG_TYPE_OTHER => "other",
			c.GL_DEBUG_TYPE_PERFORMANCE => "performance",
			c.GL_DEBUG_TYPE_POP_GROUP => "pop group",
			c.GL_DEBUG_TYPE_PORTABILITY => "portability",
			c.GL_DEBUG_TYPE_PUSH_GROUP => "push group",
			c.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR => "undefined behavior",
			else => "unknown",
		};
		switch (severity) {
			c.GL_DEBUG_SEVERITY_HIGH => {
				std.log.err("OpenGL {s} {s}: {s}", .{sourceString, typeString, message[0..@intCast(length)]});
			},
			else => {
				std.log.warn("OpenGL {s} {s}: {s}", .{sourceString, typeString, message[0..@intCast(length)]});
			},
		}
	}
};

var nextKeypressListener: ?*const fn(c_int, c_int, c_int) void = null;
pub fn setNextKeypressListener(listener: ?*const fn(c_int, c_int, c_int) void) !void {
	if(nextKeypressListener != null) return error.AlreadyUsed;
	nextKeypressListener = listener;
}

pub fn setMouseGrabbed(grab: bool) void {
	if(grabbed != grab) {
		if(grab) {
			c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
			if (c.glfwRawMouseMotionSupported() != 0)
				c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
			GLFWCallbacks.ignoreDataAfterRecentGrab = true;
		} else {
			c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
		}
		grabbed = grab;
	}
}

pub fn getMousePosition() Vec2f {
	return GLFWCallbacks.currentPos;
}

pub fn getWindowSize() Vec2f {
	return Vec2f{@floatFromInt(width), @floatFromInt(height)};
}

pub fn reloadSettings() void {
	c.glfwSwapInterval(@intFromBool(main.settings.vsync));
}

pub fn getClipboardString() []const u8 {
	return std.mem.span(c.glfwGetClipboardString(window) orelse @as([*c]const u8, ""));
}

pub fn setClipboardString(string: []const u8) void {
	const nullTerminatedString = main.stackAllocator.dupeZ(u8, string);
	defer main.stackAllocator.free(nullTerminatedString);
	c.glfwSetClipboardString(window, nullTerminatedString.ptr);
}

pub fn init() void {
	_ = c.glfwSetErrorCallback(GLFWCallbacks.errorCallback);

	if(c.glfwInit() == 0) {
		@panic("Failed to initialize GLFW");
	}

	c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
	c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
	c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 6);

	window = c.glfwCreateWindow(width, height, "Cubyz", null, null) orelse @panic("Failed to create GLFW window");

	_ = c.glfwSetKeyCallback(window, GLFWCallbacks.keyCallback);
	_ = c.glfwSetCharCallback(window, GLFWCallbacks.charCallback);
	_ = c.glfwSetFramebufferSizeCallback(window, GLFWCallbacks.framebufferSize);
	_ = c.glfwSetCursorPosCallback(window, GLFWCallbacks.cursorPosition);
	_ = c.glfwSetMouseButtonCallback(window, GLFWCallbacks.mouseButton);
	_ = c.glfwSetScrollCallback(window, GLFWCallbacks.scroll);

	c.glfwMakeContextCurrent(window);

	if(c.gladLoadGL() == 0) {
		@panic("Failed to load OpenGL functions from GLAD");
	}
	reloadSettings();

	c.glEnable(c.GL_DEBUG_OUTPUT);
	c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
	c.glDebugMessageCallback(GLFWCallbacks.glDebugOutput, null);
	c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);
}

pub fn deinit() void {
	c.glfwDestroyWindow(window);
	c.glfwTerminate();
}

pub fn handleEvents() void {
	scrollOffset = 0;
	c.glfwPollEvents();
}

var oldX: c_int = 0;
var oldY: c_int = 0;
var oldWidth: c_int = 0;
var oldHeight: c_int = 0;
pub fn toggleFullscreen() void {
	isFullscreen = !isFullscreen;
	if (isFullscreen) {
		c.glfwGetWindowPos(window, &oldX, &oldY);
		c.glfwGetWindowSize(window, &oldWidth, &oldHeight);
		const monitor = c.glfwGetPrimaryMonitor();
		if(monitor == null) {
			isFullscreen = false;
			return;
		}
		const vidMode = c.glfwGetVideoMode(monitor).?;
		c.glfwSetWindowMonitor(window, monitor, 0, 0, vidMode[0].width, vidMode[0].height, c.GLFW_DONT_CARE);
	} else {
		c.glfwSetWindowMonitor(window, null, oldX, oldY, oldWidth, oldHeight, c.GLFW_DONT_CARE);
		c.glfwSetWindowAttrib(window, c.GLFW_DECORATED, c.GLFW_TRUE);
	}
}
