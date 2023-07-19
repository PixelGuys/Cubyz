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

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

pub threadlocal var threadAllocator: std.mem.Allocator = undefined;
pub threadlocal var seed: u64 = undefined;
var global_gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
pub const globalAllocator: std.mem.Allocator = global_gpa.allocator();
pub var threadPool: utils.ThreadPool = undefined;

fn cacheStringImpl(comptime len: usize, comptime str: [len]u8) []const u8 {
	return str[0..len];
}

fn cacheString(comptime str: []const u8) []const u8 {
	return cacheStringImpl(str.len, str[0..].*);
}
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
		const colorReset = "\x1b[0m";
		const filePrefix = "[" ++ comptime level.asText() ++ "]" ++ ": ";
		const fileSuffix = "";
		//const advancedFormat = "{s}" ++ format ++ "{s}\n";
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
		formatString = comptime cacheString("{s}" ++ formatString ++ "{s}\n");

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
			} else if(TI == .Pointer) {
				if(TI.Pointer.size == .Many and TI.Pointer.child == u8) {
					types = types ++ &[_]type{[]const u8};
				} else if(TI.Pointer.size == .Slice and TI.Pointer.child == u8) {
					types = types ++ &[_]type{[]const u8};
				} else {
					types = types ++ &[_]type{@TypeOf(args[i_1])};
				}
			} else if(TI == .Int) {
				if(TI.Int.bits <= 64) {
					if(TI.Int.signedness == .signed) {
						types = types ++ &[_]type{i64};
					} else {
						types = types ++ &[_]type{u64};
					}
				} else {
					types = types ++ &[_]type{@TypeOf(args[i_1])};
				}
			} else {
				types = types ++ &[_]type{@TypeOf(args[i_1])};
			}
			i_1 += 1;
		}
		types = &[_]type{[]const u8} ++ types ++ &[_]type{[]const u8};
		// @compileLog(types);

		comptime var comptimeTuple: std.meta.Tuple(types) = undefined;
		comptime std.debug.assert(std.meta.Tuple(types) == std.meta.Tuple(types));
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
		var resultArgs: std.meta.Tuple(types) = comptimeTuple;
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
		//@compileLog(format, formatString, args, resultArgs);


		{
			resultArgs[0] = filePrefix;
			resultArgs[resultArgs.len - 1] = fileSuffix;
			logToFile(formatString, resultArgs);
		}
		{
			resultArgs[0] = color;
			resultArgs[resultArgs.len - 1] = colorReset;
			logToStdErr(formatString, resultArgs);
		}
	}
};

fn logToFile(comptime format: []const u8, args: anytype) void {
	var stackFallbackAllocator: std.heap.StackFallbackAllocator(65536) = undefined;
	stackFallbackAllocator.fallback_allocator = threadAllocator;
	const allocator = stackFallbackAllocator.get();

	const string = std.fmt.allocPrint(allocator, format, args) catch return;
	defer allocator.free(string);
	logFile.writeAll(string) catch {};
}

fn logToStdErr(comptime format: []const u8, args: anytype) void {
	var stackFallbackAllocator: std.heap.StackFallbackAllocator(65536) = undefined;
	stackFallbackAllocator.fallback_allocator = threadAllocator;
	const allocator = stackFallbackAllocator.get();
	
	const string = std.fmt.allocPrint(allocator, format, args) catch return;
	defer allocator.free(string);
	nosuspend std.io.getStdErr().writeAll(string) catch {};
}



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
fn ungrabMouse() void {
	Window.setMouseGrabbed(false);
}
fn openInventory() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("inventory") catch |err| {
		std.log.err("Got error while opening the inventory: {s}", .{@errorName(err)});
	};
}
fn openWorkbench() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("workbench") catch |err| {
		std.log.err("Got error while opening the inventory: {s}", .{@errorName(err)});
	};
}
fn openCreativeInventory() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("creative_inventory") catch |err| {
		std.log.err("Got error while opening the inventory: {s}", .{@errorName(err)});
	};
}
fn takeBackgroundImageFn() void {
	if(game.world == null) return;
	renderer.MenuBackGround.takeBackgroundImage() catch |err| {
		std.log.err("Got error while recording the background image: {s}", .{@errorName(err)});
	};
}
fn toggleDebugOverlay() void {
	gui.toggleWindow("debug") catch |err| {
		std.log.err("Got error while opening the debug overlay: {s}", .{@errorName(err)});
	};
}
fn togglePerformanceOverlay() void {
	gui.toggleWindow("performance_graph") catch |err| {
		std.log.err("Got error while opening the performance_graph overlay: {s}", .{@errorName(err)});
	};
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

	takeBackgroundImage: Key = Key{.key = c.GLFW_KEY_PRINT_SCREEN, .releaseAction = &takeBackgroundImageFn},

	// Gui:
	escape: Key = Key{.key = c.GLFW_KEY_ESCAPE, .releaseAction = &ungrabMouse},
	openInventory: Key = Key{.key = c.GLFW_KEY_I, .releaseAction = &openInventory},
	openWorkbench: Key = Key{.key = c.GLFW_KEY_K, .releaseAction = &openWorkbench}, // TODO: Remove
	@"openCreativeInventory(aka cheat inventory)": Key = Key{.key = c.GLFW_KEY_C, .releaseAction = &openCreativeInventory},
	mainGuiButton: Key = Key{.mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &gui.mainButtonPressed, .releaseAction = &gui.mainButtonReleased},
	secondaryGuiButton: Key = Key{.mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .pressAction = &gui.secondaryButtonPressed, .releaseAction = &gui.secondaryButtonReleased},
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

	// debug:
	debugOverlay: Key = Key{.key = c.GLFW_KEY_F3, .releaseAction = &toggleDebugOverlay},
	performanceOverlay: Key = Key{.key = c.GLFW_KEY_F4, .releaseAction = &togglePerformanceOverlay},
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
		fn keyCallback(_: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, _mods: c_int) callconv(.C) void {
			const mods: Key.Modifiers = @bitCast(@as(u6, @intCast(_mods)));
			if(action == c.GLFW_PRESS) {
				inline for(@typeInfo(@TypeOf(keyboard)).Struct.fields) |field| {
					if(key == @field(keyboard, field.name).key) {
						if(key != c.GLFW_KEY_UNKNOWN or scancode == @field(keyboard, field.name).scancode) {
							@field(keyboard, field.name).pressed = true;
							if(@field(keyboard, field.name).pressAction) |pressAction| {
								pressAction();
							}
							if(@field(keyboard, field.name).repeatAction) |repeatAction| {
								repeatAction(mods);
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
								repeatAction(mods);
							}
						}
					}
				}
			}
		}
		fn charCallback(_: ?*c.GLFWwindow, codepoint: c_uint) callconv(.C) void {
			if(!grabbed) {
				gui.textCallbacks.char(@intCast(codepoint)) catch |err| {
					std.log.err("Error while calling char callback: {s}", .{@errorName(err)});
				};
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
			scrollOffset += @floatCast(yOffset);
		}
		fn glDebugOutput(_: c_uint, _: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
			if(severity == c.GL_DEBUG_SEVERITY_HIGH) { // TODO: Capture the stack traces.
				std.log.err("OpenGL {}:{s}", .{severity, message[0..@intCast(length)]});
			} else if(severity == c.GL_DEBUG_SEVERITY_MEDIUM) {
				std.log.warn("OpenGL {}:{s}", .{severity, message[0..@intCast(length)]});
			} else if(severity == c.GL_DEBUG_SEVERITY_LOW) {
				std.log.info("OpenGL {}:{s}", .{severity, message[0..@intCast(length)]});
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

pub var lastFrameTime = std.atomic.Atomic(f64).init(0);

pub fn main() !void {
	seed = @bitCast(std.time.milliTimestamp());
	var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
	threadAllocator = gpa.allocator();
	defer if(gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};
	defer if(global_gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};

	// init logging.
	try std.fs.cwd().makePath("logs");
	logFile = std.fs.cwd().createFile("logs/latest.log", .{}) catch unreachable;
	defer logFile.close();

	threadPool = try utils.ThreadPool.init(globalAllocator, 1 + ((std.Thread.getCpuCount() catch 4) -| 2));
	defer threadPool.deinit();

	try settings.init();
	defer settings.deinit();

	try Window.init();
	defer Window.deinit();

	try graphics.init();
	defer graphics.deinit();

	try audio.init();
	defer audio.deinit();

	try gui.init();
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

	try network.init();

	try renderer.RenderStructure.init();
	defer renderer.RenderStructure.deinit();

	try entity.ClientEntityManager.init();
	defer entity.ClientEntityManager.deinit();

	if(settings.playerName.len == 0) {
		try gui.openWindow("change_name");
	} else {
		try gui.openWindow("main");
	}

	try server.terrain.initGenerators();
	defer server.terrain.deinitGenerators();

	c.glCullFace(c.GL_BACK);
	c.glEnable(c.GL_BLEND);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	Window.GLFWCallbacks.framebufferSize(undefined, Window.width, Window.height);
	var lastTime = std.time.nanoTimestamp();

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
		var newTime = std.time.nanoTimestamp();
		var deltaTime = @as(f64, @floatFromInt(newTime -% lastTime))/1e9;
		lastFrameTime.store(deltaTime, .Monotonic);
		lastTime = newTime;
		if(game.world != null) { // Update the game
			try game.update(deltaTime);
		}
		c.glEnable(c.GL_CULL_FACE);
		c.glEnable(c.GL_DEPTH_TEST);
		try renderer.render(game.Player.getPosBlocking());

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