const std = @import("std");

pub const gui = @import("gui");
pub const server = @import("server");

pub const audio = @import("audio.zig");
pub const assets = @import("assets.zig");
pub const blocks = @import("blocks.zig");
pub const chunk = @import("chunk.zig");
pub const entity = @import("entity.zig");
pub const files = @import("files.zig");
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

pub const List = @import("utils/list.zig").List;
pub const ListUnmanaged = @import("utils/list.zig").ListUnmanaged;

const file_monitor = utils.file_monitor;

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

pub threadlocal var stackAllocator: utils.NeverFailingAllocator = undefined;
pub threadlocal var seed: u64 = undefined;
var global_gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
var handled_gpa = utils.ErrorHandlingAllocator.init(global_gpa.allocator());
pub const globalAllocator: utils.NeverFailingAllocator = handled_gpa.allocator();
pub var threadPool: utils.ThreadPool = undefined;

fn cacheStringImpl(comptime len: usize, comptime str: [len]u8) []const u8 {
	return str[0..len];
}

fn cacheString(comptime str: []const u8) []const u8 {
	return cacheStringImpl(str.len, str[0..].*);
}
var logFile: ?std.fs.File = undefined;
var supportsANSIColors: bool = undefined;
// overwrite the log function:
pub const std_options: std.Options = .{
	.log_level = .debug,
	.logFn = struct {pub fn logFn(
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
		const colorReset = "\x1b[0m\n";
		const filePrefix = "[" ++ comptime level.asText() ++ "]" ++ ": ";
		const fileSuffix = "\n";
		comptime var formatString: []const u8 = "";
		comptime var i: usize = 0;
		comptime var mode: usize = 0;
		comptime var sections: usize = 0;
		comptime var sectionString: []const u8 = "";
		comptime var sectionResults: []const []const u8 = &.{};
		comptime var sectionId: []const usize = &.{};
		inline while(i < format.len) : (i += 1) {
			if(mode == 0) {
				if(format[i] == '{') {
					if(format[i + 1] == '{') {
						sectionString = sectionString ++ "{{";
						i += 1;
						continue;
					} else {
						mode = 1;
						formatString = formatString ++ "{s}{";
						sectionResults = sectionResults ++ &[_][]const u8{sectionString};
						sectionString = "";
						sectionId = sectionId ++ &[_]usize {sections};
						sections += 1;
						continue;
					}
				} else {
					sectionString = sectionString ++ format[i..i+1];
				}
			} else {
				formatString = formatString ++ format[i..i+1];
				if(format[i] == '}') {
					sections += 1;
					mode = 0;
				}
			}
		}
		formatString = formatString ++ "{s}";
		sectionResults = sectionResults ++ &[_][]const u8{sectionString};
		sectionId = sectionId ++ &[_]usize {sections};
		sections += 1;
		formatString = comptime cacheString("{s}" ++ formatString ++ "{s}");

		comptime var types: []const type = &.{};
		comptime var i_1: usize = 0;
		comptime var i_2: usize = 0;
		inline while(types.len != sections) {
			if(i_2 < sectionResults.len) {
				if(types.len == sectionId[i_2]) {
					types = types ++ &[_]type{[]const u8};
					i_2 += 1;
					continue;
				}
			}
			const TI = @typeInfo(@TypeOf(args[i_1]));
			if(@TypeOf(args[i_1]) == comptime_int) {
				types = types ++ &[_]type{i64};
			} else if(@TypeOf(args[i_1]) == comptime_float) {
				types = types ++ &[_]type{f64};
			} else if(TI == .Pointer and TI.Pointer.size == .Slice and TI.Pointer.child == u8) {
				types = types ++ &[_]type{[]const u8};
			} else if(TI == .Int and TI.Int.bits <= 64) {
				if(TI.Int.signedness == .signed) {
					types = types ++ &[_]type{i64};
				} else {
					types = types ++ &[_]type{u64};
				}
			} else {
				types = types ++ &[_]type{@TypeOf(args[i_1])};
			}
			i_1 += 1;
		}
		types = &[_]type{[]const u8} ++ types ++ &[_]type{[]const u8};

		const ArgsType = std.meta.Tuple(types);
		comptime var comptimeTuple: ArgsType = undefined;
		comptime var len: usize = 0;
		i_1 = 0;
		i_2 = 0;
		inline while(len != sections) : (len += 1) {
			if(i_2 < sectionResults.len) {
				if(len == sectionId[i_2]) {
					comptimeTuple[len+1] = sectionResults[i_2];
					i_2 += 1;
					continue;
				}
			}
			i_1 += 1;
		}
		comptimeTuple[0] = filePrefix;
		comptimeTuple[comptimeTuple.len - 1] = fileSuffix;
		var resultArgs: ArgsType = comptimeTuple;
		len = 0;
		i_1 = 0;
		i_2 = 0;
		inline while(len != sections) : (len += 1) {
			if(i_2 < sectionResults.len) {
				if(len == sectionId[i_2]) {
					i_2 += 1;
					continue;
				}
			}
			resultArgs[len+1] = args[i_1];
			i_1 += 1;
		}

		logToFile(formatString, resultArgs);

		if(supportsANSIColors) {
			resultArgs[0] = color;
			resultArgs[resultArgs.len - 1] = colorReset;
		}
		logToStdErr(formatString, resultArgs);
	}}.logFn,
};

fn initLogging() void {
	logFile = null;
	std.fs.cwd().makePath("logs") catch |err| {
		std.log.err("Couldn't create logs folder: {s}", .{@errorName(err)});
		return;
	};
	logFile = std.fs.cwd().createFile("logs/latest.log", .{}) catch |err| {
		std.log.err("Couldn't create logs/latest.log: {s}", .{@errorName(err)});
		return;
	};
	supportsANSIColors = std.io.getStdOut().supportsAnsiEscapeCodes();
}

fn deinitLogging() void {
	if(logFile) |_logFile| {
		_logFile.close();
		logFile = null;
	}
}

fn logToFile(comptime format: []const u8, args: anytype) void {
	var buf: [65536]u8 = undefined;
	var fba = std.heap.FixedBufferAllocator.init(&buf);
	const allocator = fba.allocator();

	const string = std.fmt.allocPrint(allocator, format, args) catch format;
	defer allocator.free(string);
	(logFile orelse return).writeAll(string) catch {};
}

fn logToStdErr(comptime format: []const u8, args: anytype) void {
	var buf: [65536]u8 = undefined;
	var fba = std.heap.FixedBufferAllocator.init(&buf);
	const allocator = fba.allocator();

	const string = std.fmt.allocPrint(allocator, format, args) catch format;
	defer allocator.free(string);
	nosuspend std.io.getStdErr().writeAll(string) catch {};
}



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

var nextKeypressListener: ?*const fn(c_int, c_int, c_int) void = null;
pub fn setNextKeypressListener(listener: ?*const fn(c_int, c_int, c_int) void) !void {
	if(nextKeypressListener != null) return error.AlreadyUsed;
	nextKeypressListener = listener;
}
fn escape() void {
	if(game.world == null) return;
	gui.toggleGameMenu();
}
fn ungrabMouse() void {
	if(Window.grabbed) {
		gui.toggleGameMenu();
	}
}
fn openInventory() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("inventory");
}
fn openWorkbench() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("workbench");
}
fn openCreativeInventory() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("creative_inventory");
}
fn takeBackgroundImageFn() void {
	if(game.world == null) return;
	renderer.MenuBackGround.takeBackgroundImage();
}
fn toggleDebugOverlay() void {
	gui.toggleWindow("debug");
}
fn togglePerformanceOverlay() void {
	gui.toggleWindow("performance_graph");
}
fn toggleGPUPerformanceOverlay() void {
	gui.toggleWindow("gpu_performance_measuring");
}
fn toggleNetworkDebugOverlay() void {
	gui.toggleWindow("debug_network");
}

pub const KeyBoard = struct {
	pub var keys = [_]Key {
		// Gameplay:
		Key{.name = "forward", .key = c.GLFW_KEY_W},
		Key{.name = "left", .key = c.GLFW_KEY_A},
		Key{.name = "backward", .key = c.GLFW_KEY_S},
		Key{.name = "right", .key = c.GLFW_KEY_D},
		Key{.name = "sprint", .key = c.GLFW_KEY_LEFT_CONTROL},
		Key{.name = "jump", .key = c.GLFW_KEY_SPACE},
		Key{.name = "fall", .key = c.GLFW_KEY_LEFT_SHIFT},
		Key{.name = "fullscreen", .key = c.GLFW_KEY_F11, .releaseAction = &Window.toggleFullscreen},
		Key{.name = "placeBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .pressAction = &game.Player.placeBlock}, // TODO: Add GLFW_REPEAT behavior to mouse buttons.
		Key{.name = "breakBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &game.Player.breakBlock}, // TODO: Add GLFW_REPEAT behavior to mouse buttons.

		Key{.name = "takeBackgroundImage", .key = c.GLFW_KEY_PRINT_SCREEN, .releaseAction = &takeBackgroundImageFn},

		// Gui:
		Key{.name = "escape", .key = c.GLFW_KEY_ESCAPE, .releaseAction = &escape},
		Key{.name = "openInventory", .key = c.GLFW_KEY_I, .releaseAction = &openInventory},
		Key{.name = "openWorkbench", .key = c.GLFW_KEY_K, .releaseAction = &openWorkbench}, // TODO: Remove
		Key{.name = "openCreativeInventory(aka cheat inventory)", .key = c.GLFW_KEY_C, .releaseAction = &openCreativeInventory},
		Key{.name = "mainGuiButton", .mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &gui.mainButtonPressed, .releaseAction = &gui.mainButtonReleased},
		Key{.name = "secondaryGuiButton", .mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .pressAction = &gui.secondaryButtonPressed, .releaseAction = &gui.secondaryButtonReleased},
		// text:
		Key{.name = "textCursorLeft", .key = c.GLFW_KEY_LEFT, .repeatAction = &gui.textCallbacks.left},
		Key{.name = "textCursorRight", .key = c.GLFW_KEY_RIGHT, .repeatAction = &gui.textCallbacks.right},
		Key{.name = "textCursorDown", .key = c.GLFW_KEY_DOWN, .repeatAction = &gui.textCallbacks.down},
		Key{.name = "textCursorUp", .key = c.GLFW_KEY_UP, .repeatAction = &gui.textCallbacks.up},
		Key{.name = "textGotoStart", .key = c.GLFW_KEY_HOME, .repeatAction = &gui.textCallbacks.gotoStart},
		Key{.name = "textGotoEnd", .key = c.GLFW_KEY_END, .repeatAction = &gui.textCallbacks.gotoEnd},
		Key{.name = "textDeleteLeft", .key = c.GLFW_KEY_BACKSPACE, .repeatAction = &gui.textCallbacks.deleteLeft},
		Key{.name = "textDeleteRight", .key = c.GLFW_KEY_DELETE, .repeatAction = &gui.textCallbacks.deleteRight},
		Key{.name = "textCopy", .key = c.GLFW_KEY_C, .repeatAction = &gui.textCallbacks.copy},
		Key{.name = "textPaste", .key = c.GLFW_KEY_V, .repeatAction = &gui.textCallbacks.paste},
		Key{.name = "textCut", .key = c.GLFW_KEY_X, .repeatAction = &gui.textCallbacks.cut},
		Key{.name = "textNewline", .key = c.GLFW_KEY_ENTER, .repeatAction = &gui.textCallbacks.newline},

		// debug:
		Key{.name = "debugOverlay", .key = c.GLFW_KEY_F3, .releaseAction = &toggleDebugOverlay},
		Key{.name = "performanceOverlay", .key = c.GLFW_KEY_F4, .releaseAction = &togglePerformanceOverlay},
		Key{.name = "gpuPerformanceOverlay", .key = c.GLFW_KEY_F5, .releaseAction = &toggleGPUPerformanceOverlay},
		Key{.name = "networkDebugOverlay", .key = c.GLFW_KEY_F6, .releaseAction = &toggleNetworkDebugOverlay},
	};

	pub fn key(name: []const u8) *const Key { // TODO: Maybe I should use a hashmap here?
		for(&keys) |*_key| {
			if(std.mem.eql(u8, name, _key.name)) {
				return _key;
			}
		}
		std.log.err("Couldn't find keyboard key with name {s}", .{name});
		return &Key{.name = ""};
	}
};

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
		fn keyCallback(_: ?*c.GLFWwindow, glfw_key: c_int, scancode: c_int, action: c_int, _mods: c_int) callconv(.C) void {
			const mods: Key.Modifiers = @bitCast(@as(u6, @intCast(_mods)));
			if(action == c.GLFW_PRESS) {
				for(&KeyBoard.keys) |*key| {
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
				for(&KeyBoard.keys) |*key| {
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
				for(&KeyBoard.keys) |*key| {
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
				gui.textCallbacks.char(@intCast(codepoint));
			}
		}

		fn framebufferSize(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
			std.log.info("Framebuffer: {}, {}", .{newWidth, newHeight});
			width = @intCast(newWidth);
			height = @intCast(newHeight);
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
				@floatCast(x),
				@floatCast(y),
			};
			if(grabbed and !ignoreDataAfterRecentGrab) {
				deltas[deltaBufferPosition] += (newPos - currentPos)*@as(Vec2f, @splat(settings.mouseSensitivity));
				var averagedDelta: Vec2f = Vec2f{0, 0};
				for(deltas) |delta| {
					averagedDelta += delta;
				}
				averagedDelta /= @splat(deltasLen);
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
				for(&KeyBoard.keys) |*key| {
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
				for(&KeyBoard.keys) |*key| {
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
		c.glfwSwapInterval(@intFromBool(settings.vsync));
	}

	pub fn getClipboardString() []const u8 {
		return std.mem.span(c.glfwGetClipboardString(window));
	}

	pub fn setClipboardString(string: []const u8) void {
		const nullTerminatedString = stackAllocator.dupeZ(u8, string);
		defer stackAllocator.free(nullTerminatedString);
		c.glfwSetClipboardString(window, nullTerminatedString.ptr);
	}

	fn init() void {
		_ = c.glfwSetErrorCallback(GLFWCallbacks.errorCallback);

		if(c.glfwInit() == 0) {
			@panic("Failed to initialize GLFW");
		}

		if(@import("builtin").mode == .Debug) {
			c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
		}
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

pub var lastFrameTime = std.atomic.Value(f64).init(0);

pub fn main() void {
	seed = @bitCast(std.time.milliTimestamp());
	defer if(global_gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};
	var sta = utils.StackAllocator.init(globalAllocator, 1 << 23);
	defer sta.deinit();
	stackAllocator = sta.allocator();

	initLogging();
	defer deinitLogging();

	threadPool = utils.ThreadPool.init(globalAllocator, @max(1, (std.Thread.getCpuCount() catch 4) -| 1));
	defer threadPool.deinit();

	file_monitor.init();
	defer file_monitor.deinit();

	settings.init();
	defer settings.deinit();

	Window.init();
	defer Window.deinit();

	graphics.init();
	defer graphics.deinit();

	audio.init() catch std.log.err("Failed to initialize audio. Continuing the game without sounds.", .{});
	defer audio.deinit();

	gui.init();
	defer gui.deinit();

	chunk.init();
	defer chunk.deinit();

	rotation.init();
	defer rotation.deinit();

	models.init();
	defer models.deinit();

	items.globalInit();
	defer items.deinit();

	itemdrop.ItemDropRenderer.init();
	defer itemdrop.ItemDropRenderer.deinit();

	assets.init();
	defer assets.deinit();

	blocks.meshes.init();
	defer blocks.meshes.deinit();

	renderer.init();
	defer renderer.deinit();

	network.init();

	entity.ClientEntityManager.init();
	defer entity.ClientEntityManager.deinit();

	if(settings.playerName.len == 0) {
		gui.openWindow("change_name");
	} else {
		gui.openWindow("main");
	}

	server.terrain.initGenerators();
	defer server.terrain.deinitGenerators();

	c.glCullFace(c.GL_BACK);
	c.glEnable(c.GL_BLEND);
	c.glEnable(c.GL_DEPTH_CLAMP);
	c.glDepthFunc(c.GL_LESS);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	Window.GLFWCallbacks.framebufferSize(undefined, Window.width, Window.height);
	var lastTime = std.time.nanoTimestamp();

	if(settings.developerAutoEnterWorld.len != 0) {
		// Speed up the dev process by entering the world directly.
		gui.windowlist.save_selection.openWorld(settings.developerAutoEnterWorld);
	}

	while(c.glfwWindowShouldClose(Window.window) == 0) {
		c.glfwSwapBuffers(Window.window);
		// Clear may also wait on vsync, so it's done before handling events:
		gui.windowlist.gpu_performance_measuring.startQuery(.screenbuffer_clear);
		c.glClearColor(0.5, 1, 1, 1);
		c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
		gui.windowlist.gpu_performance_measuring.stopQuery();

		Window.handleEvents();
		file_monitor.handleEvents();

		const newTime = std.time.nanoTimestamp();
		const deltaTime = @as(f64, @floatFromInt(newTime -% lastTime))/1e9;
		if(@import("builtin").os.tag == .linux and deltaTime > 5) { // On linux a process that runs 10 seconds or longer on the GPU will get stopped. This allows detecting an infinite loop on the GPU.
			std.log.err("Frame got too long with {} seconds. Infinite loop on GPU?", .{deltaTime});
			std.posix.exit(1);
		}
		lastFrameTime.store(deltaTime, .monotonic);
		lastTime = newTime;
		if(game.world != null) { // Update the game
			game.update(deltaTime);
		}
		c.glEnable(c.GL_CULL_FACE);
		c.glEnable(c.GL_DEPTH_TEST);
		renderer.render(game.Player.getPosBlocking());

		{ // Render the GUI
			gui.windowlist.gpu_performance_measuring.startQuery(.gui);
			c.glDisable(c.GL_CULL_FACE);
			c.glDisable(c.GL_DEPTH_TEST);
			gui.updateAndRenderGui();
			gui.windowlist.gpu_performance_measuring.stopQuery();
		}
	}

	// Make sure that threadPool is done before freeing any data
	threadPool.clear();

	if(game.world) |world| {
		world.deinit();
		game.world = null;
	}
}

test "abc" {
	_ = @import("json.zig");
}