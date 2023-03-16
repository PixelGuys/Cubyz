const std = @import("std");

const gui = @import("gui");

pub const assets = @import("assets.zig");
pub const blocks = @import("blocks.zig");
pub const chunk = @import("chunk.zig");
pub const entity = @import("entity.zig");
pub const game = @import("game.zig");
pub const graphics = @import("graphics.zig");
pub const itemdrop = @import("itemdrop.zig");
pub const items = @import("items.zig");
pub const JsonElement = @import("json.zig").JsonElement;
pub const models = @import("models.zig");
pub const network = @import("network.zig");
pub const random = @import("random.zig");
pub const renderer = @import("renderer.zig");
pub const rotation = @import("rotation.zig");
pub const settings = @import("settings.zig");
pub const utils = @import("utils.zig");
pub const vec = @import("vec.zig");

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

pub threadlocal var threadAllocator: std.mem.Allocator = undefined;
pub threadlocal var seed: u64 = undefined;
pub var globalAllocator: std.mem.Allocator = undefined;
pub var threadPool: utils.ThreadPool = undefined;

var logFile: std.fs.File = undefined;
// overwrite the log function:
pub const std_options = struct {
	pub const log_level = .debug;
	pub fn logFn(
		comptime level: std.log.Level,
		comptime _: @Type(.EnumLiteral),
		comptime format: []const u8,
		args: anytype,
	) void {
		const color = comptime switch (level) {
			std.log.Level.err => "\x1b[31m",
			std.log.Level.info => "",
			std.log.Level.warn => "\x1b[33m",
			std.log.Level.debug => "\x1b[37;44m",
		};

		std.debug.getStderrMutex().lock();
		defer std.debug.getStderrMutex().unlock();

		logFile.writer().print("[" ++ level.asText() ++ "]" ++ ": " ++ format ++ "\n", args) catch {};

		nosuspend std.io.getStdErr().writer().print(color ++ format ++ "\x1b[0m\n", args) catch {};
	}
};



pub const Key = struct {
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

var nextKeypressListener: ?*const fn(c_int, c_int, c_int) void = null;
pub fn setNextKeypressListener(listener: ?*const fn(c_int, c_int, c_int) void) !void {
	if(nextKeypressListener != null) return error.AlreadyUsed;
	nextKeypressListener = listener;
}
pub var keyboard: struct {
	// Gameplay:
	forward: Key = Key{.key = c.GLFW_KEY_W},
	left: Key = Key{.key = c.GLFW_KEY_A},
	backward: Key = Key{.key = c.GLFW_KEY_S},
	right: Key = Key{.key = c.GLFW_KEY_D},
	sprint: Key = Key{.key = c.GLFW_KEY_LEFT_CONTROL},
	jump: Key = Key{.key = c.GLFW_KEY_SPACE},
	fall: Key = Key{.key = c.GLFW_KEY_LEFT_SHIFT},
	fullscreen: Key = Key{.key = c.GLFW_KEY_F11, .releaseAction = &Window.toggleFullscreen},

	// Gui:
	mainGuiButton: Key = Key{.mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &gui.mainButtonPressed, .releaseAction = &gui.mainButtonReleased},
	rightMouseButton: Key = Key{.mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT},
	middleMouseButton: Key = Key{.mouseButton = c.GLFW_MOUSE_BUTTON_MIDDLE},
	// text:
	textCursorLeft: Key = Key{.key = c.GLFW_KEY_LEFT, .repeatAction = &gui.textCallbacks.left},
	textCursorRight: Key = Key{.key = c.GLFW_KEY_RIGHT, .repeatAction = &gui.textCallbacks.right},
	textCursorDown: Key = Key{.key = c.GLFW_KEY_DOWN, .repeatAction = &gui.textCallbacks.down},
	textCursorUp: Key = Key{.key = c.GLFW_KEY_UP, .repeatAction = &gui.textCallbacks.up},
	textGotoStart: Key = Key{.key = c.GLFW_KEY_HOME, .repeatAction = &gui.textCallbacks.gotoStart},
	textGotoEnd: Key = Key{.key = c.GLFW_KEY_END, .repeatAction = &gui.textCallbacks.gotoEnd},
	textDeleteLeft: Key = Key{.key = c.GLFW_KEY_BACKSPACE, .repeatAction = &gui.textCallbacks.deleteLeft},
	textDeleteRight: Key = Key{.key = c.GLFW_KEY_DELETE, .repeatAction = &gui.textCallbacks.deleteRight},
	textCopy: Key = Key{.key = c.GLFW_KEY_C, .repeatAction = &gui.textCallbacks.copy},
	textPaste: Key = Key{.key = c.GLFW_KEY_V, .repeatAction = &gui.textCallbacks.paste},
	textCut: Key = Key{.key = c.GLFW_KEY_X, .repeatAction = &gui.textCallbacks.cut},
	textNewline: Key = Key{.key = c.GLFW_KEY_ENTER, .repeatAction = &gui.textCallbacks.newline},
} = .{};

pub const Window = struct {
	var isFullscreen: bool = false;
	pub var width: u31 = 1280;
	pub var height: u31 = 720;
	var window: *c.GLFWwindow = undefined;
	pub var grabbed: bool = false;
	pub var scrollOffset: f32 = 0;
	const GLFWCallbacks = struct {
		fn errorCallback(errorCode: c_int, description: [*c]const u8) callconv(.C) void {
			std.log.err("GLFW Error({}): {s}", .{errorCode, description});
		}
		fn keyCallback(_: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
			if(action == c.GLFW_PRESS) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(key == @field(keyboard, field.name).key) {
						if(key != c.GLFW_KEY_UNKNOWN or scancode == @field(keyboard, field.name).scancode) {
							@field(keyboard, field.name).pressed = true;
							if(@field(keyboard, field.name).pressAction) |pressAction| {
								pressAction();
							}
							if(@field(keyboard, field.name).repeatAction) |repeatAction| {
								repeatAction(@bitCast(Key.Modifiers, @intCast(u6, mods)));
							}
						}
					}
				}
				if(nextKeypressListener) |listener| {
					listener(key, -1, scancode);
					nextKeypressListener = null;
				}
			} else if(action == c.GLFW_RELEASE) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(key == @field(keyboard, field.name).key) {
						if(key != c.GLFW_KEY_UNKNOWN or scancode == @field(keyboard, field.name).scancode) {
							@field(keyboard, field.name).pressed = false;
							if(@field(keyboard, field.name).releaseAction) |releaseAction| {
								releaseAction();
							}
						}
					}
				}
			} else if(action == c.GLFW_REPEAT) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(key == @field(keyboard, field.name).key) {
						if(key != c.GLFW_KEY_UNKNOWN or scancode == @field(keyboard, field.name).scancode) {
							if(@field(keyboard, field.name).repeatAction) |repeatAction| {
								repeatAction(@bitCast(Key.Modifiers, @intCast(u6, mods)));
							}
						}
					}
				}
			}
		}
		fn charCallback(_: ?*c.GLFWwindow, codepoint: c_uint) callconv(.C) void {
			if(gui.selectedTextInput) |textInput| {
				textInput.inputCharacter(@intCast(u21, codepoint)) catch |err| {
					std.log.err("Error while adding character to textInput: {s}", .{@errorName(err)});
				};
			}
		}

		fn framebufferSize(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
			std.log.info("Framebuffer: {}, {}", .{newWidth, newHeight});
			width = @intCast(u31, newWidth);
			height = @intCast(u31, newHeight);
			renderer.updateViewport(width, height, settings.fov);
			gui.updateGuiScale();
			gui.updateWindowPositions();
		}
		// Mouse deltas are averaged over multiple frames using a circular buffer:
		const deltasLen: u2 = 3;
		var deltas: [deltasLen]Vec2f = [_]Vec2f{Vec2f{0, 0}} ** 3;
		var deltaBufferPosition: u2 = 0;
		var currentPos: Vec2f = Vec2f{0, 0};
		var ignoreDataAfterRecentGrab: bool = true;
		fn cursorPosition(_: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
			const newPos = Vec2f {
				@floatCast(f32, x),
				@floatCast(f32, y),
			};
			if(grabbed and !ignoreDataAfterRecentGrab) {
				deltas[deltaBufferPosition] += (newPos - currentPos)*@splat(2, settings.mouseSensitivity);
				var averagedDelta: Vec2f = Vec2f{0, 0};
				for(deltas) |delta| {
					averagedDelta += delta;
				}
				averagedDelta /= @splat(2, @as(f32, deltasLen));
				game.camera.moveRotation(averagedDelta[0]*0.0089, averagedDelta[1]*0.0089);
				deltaBufferPosition = (deltaBufferPosition + 1)%deltasLen;
				deltas[deltaBufferPosition] = Vec2f{0, 0};
			}
			ignoreDataAfterRecentGrab = false;
			currentPos = newPos;
		}
		fn mouseButton(_: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
			_ = mods;
			if(action == c.GLFW_PRESS) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(button == @field(keyboard, field.name).mouseButton) {
						@field(keyboard, field.name).pressed = true;
						if(@field(keyboard, field.name).pressAction) |pressAction| {
							pressAction();
						}
					}
				}
				if(nextKeypressListener) |listener| {
					listener(c.GLFW_KEY_UNKNOWN, button, 0);
					nextKeypressListener = null;
				}
			} else if(action == c.GLFW_RELEASE) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(button == @field(keyboard, field.name).mouseButton) {
						@field(keyboard, field.name).pressed = false;
						if(@field(keyboard, field.name).releaseAction) |releaseAction| {
							releaseAction();
						}
					}
				}
			}
		}
		fn scroll(_ : ?*c.GLFWwindow, xOffset: f64, yOffset: f64) callconv(.C) void {
			_ = xOffset;
			scrollOffset += @floatCast(f32, yOffset);
		}
		fn glDebugOutput(_: c_uint, _: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
			if(severity == c.GL_DEBUG_SEVERITY_HIGH) { // TODO: Capture the stack traces.
				std.log.err("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
			} else if(severity == c.GL_DEBUG_SEVERITY_MEDIUM) {
				std.log.warn("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
			} else if(severity == c.GL_DEBUG_SEVERITY_LOW) {
				std.log.info("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
			}
		}
	};

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
		return Vec2f{@intToFloat(f32, width), @intToFloat(f32, height)};
	}

	pub fn reloadSettings() void {
		c.glfwSwapInterval(@boolToInt(settings.vsync));
	}

	pub fn getClipboardString() []const u8 {
		return std.mem.span(c.glfwGetClipboardString(window));
	}

	pub fn setClipboardString(string: []const u8) void {
		const nullTerminatedString = threadAllocator.dupeZ(u8, string) catch return;
		defer threadAllocator.free(nullTerminatedString);
		c.glfwSetClipboardString(window, nullTerminatedString.ptr);
	}

	fn init() !void {
		_ = c.glfwSetErrorCallback(GLFWCallbacks.errorCallback);

		if(c.glfwInit() == 0) {
			return error.GLFWFailed;
		}

		if(@import("builtin").mode == .Debug) {
			c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
		}
		c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
		c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);

		window = c.glfwCreateWindow(width, height, "Cubyz", null, null) orelse return error.GLFWFailed;

		_ = c.glfwSetKeyCallback(window, GLFWCallbacks.keyCallback);
		_ = c.glfwSetCharCallback(window, GLFWCallbacks.charCallback);
		_ = c.glfwSetFramebufferSizeCallback(window, GLFWCallbacks.framebufferSize);
		_ = c.glfwSetCursorPosCallback(window, GLFWCallbacks.cursorPosition);
		_ = c.glfwSetMouseButtonCallback(window, GLFWCallbacks.mouseButton);
		_ = c.glfwSetScrollCallback(window, GLFWCallbacks.scroll);

		c.glfwMakeContextCurrent(window);

		if(c.gladLoadGL() == 0) {
			return error.GLADFailed;
		}
		reloadSettings();

		if(@import("builtin").mode == .Debug) {
			c.glEnable(c.GL_DEBUG_OUTPUT);
			c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
			c.glDebugMessageCallback(GLFWCallbacks.glDebugOutput, null);
			c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);
		}
	}

	fn deinit() void {
		c.glfwDestroyWindow(window);
		c.glfwTerminate();
	}

	fn handleEvents() void {
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
};

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
	threadAllocator = gpa.allocator();
	defer if(gpa.deinit()) {
		std.log.err("Memory leak", .{});
	};
	var global_gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
	globalAllocator = global_gpa.allocator();
	defer if(global_gpa.deinit()) {
		std.log.err("Memory leak", .{});
	};

	// init logging.
	try std.fs.cwd().makePath("logs");
	logFile = std.fs.cwd().createFile("logs/latest.log", .{}) catch unreachable;
	defer logFile.close();

	var poolgpa = std.heap.GeneralPurposeAllocator(.{}){};
	defer if(poolgpa.deinit()) {
		@panic("Memory leak");
	};
	threadPool = try utils.ThreadPool.init(poolgpa.allocator(), 1 + ((std.Thread.getCpuCount() catch 4) -| 3));
	defer threadPool.deinit();

	try settings.init();
	defer settings.deinit();

	try Window.init();
	defer Window.deinit();

	try graphics.init();
	defer graphics.deinit();

	try gui.init(globalAllocator);
	defer gui.deinit();

	try rotation.init();
	defer rotation.deinit();

	try models.init();
	defer models.deinit();

	items.globalInit();
	defer items.deinit();

	try itemdrop.ItemDropRenderer.init();
	defer itemdrop.ItemDropRenderer.deinit();

	try assets.init();
	defer assets.deinit();

	blocks.meshes.init();
	defer blocks.meshes.deinit();

	try chunk.meshing.init();
	defer chunk.meshing.deinit();

	try renderer.init();
	defer renderer.deinit();

	network.init();

	try renderer.RenderStructure.init();
	defer renderer.RenderStructure.deinit();

	try entity.ClientEntityManager.init();
	defer entity.ClientEntityManager.deinit();

	if(settings.playerName.len == 0) {
		try gui.openWindow("cubyz:change_name");
	} else {
		try gui.openWindow("cubyz:hotbar");
		try gui.openWindow("cubyz:hotbar2");
		try gui.openWindow("cubyz:hotbar3");
		try gui.openWindow("cubyz:healthbar");
		try gui.openWindow("cubyz:main");
	}

	c.glCullFace(c.GL_BACK);
	c.glEnable(c.GL_BLEND);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	Window.GLFWCallbacks.framebufferSize(undefined, Window.width, Window.height);
	var lastTime = std.time.milliTimestamp();

	while(c.glfwWindowShouldClose(Window.window) == 0) {
		{ // Check opengl errors:
			const err = c.glGetError();
			if(err != 0) {
				std.log.err("Got opengl error: {}", .{err});
			}
		}
		c.glfwSwapBuffers(Window.window);
		Window.handleEvents();
		c.glClearColor(0.5, 1, 1, 1);
		c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
		var newTime = std.time.milliTimestamp();
		var deltaTime = @intToFloat(f64, newTime -% lastTime)/1000.0;
		lastTime = newTime;
		if(game.world != null) { // Render the game
			try game.update(deltaTime);
			c.glEnable(c.GL_CULL_FACE);
			c.glEnable(c.GL_DEPTH_TEST);
			try renderer.render(game.Player.getPosBlocking());
		}

		{ // Render the GUI
			c.glDisable(c.GL_CULL_FACE);
			c.glDisable(c.GL_DEPTH_TEST);
			try gui.updateAndRenderGui();
		}
	}
	if(game.world) |world| {
		world.deinit();
		game.world = null;
	}
}

test "abc" {
	_ = @import("json.zig");
}