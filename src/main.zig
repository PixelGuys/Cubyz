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
pub const ZonElement = @import("zon.zig").ZonElement;

pub const Window = @import("graphics/Window.zig");

pub const List = @import("utils/list.zig").List;
pub const ListUnmanaged = @import("utils/list.zig").ListUnmanaged;
pub const VirtualList = @import("utils/list.zig").VirtualList;

const file_monitor = utils.file_monitor;

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

pub threadlocal var stackAllocator: utils.NeverFailingAllocator = undefined;
pub threadlocal var seed: u64 = undefined;
var global_gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=true}){};
var handled_gpa = utils.ErrorHandlingAllocator.init(global_gpa.allocator());
pub const globalAllocator: utils.NeverFailingAllocator = handled_gpa.allocator();
pub var threadPool: *utils.ThreadPool = undefined;

fn cacheStringImpl(comptime len: usize, comptime str: [len]u8) []const u8 {
	return str[0..len];
}

fn cacheString(comptime str: []const u8) []const u8 {
	return cacheStringImpl(str.len, str[0..].*);
}
var logFile: ?std.fs.File = undefined;
var logFileTs: ?std.fs.File = undefined;
var supportsANSIColors: bool = undefined;
var openingErrorWindow: bool = false;
// overwrite the log function:
pub const std_options: std.Options = .{ // MARK: std_options
	.log_level = .debug,
	.logFn = struct {pub fn logFn(
		comptime level: std.log.Level,
		comptime _: @Type(.enum_literal),
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
			} else if(TI == .pointer and TI.pointer.size == .Slice and TI.pointer.child == u8) {
				types = types ++ &[_]type{[]const u8};
			} else if(TI == .int and TI.int.bits <= 64) {
				if(TI.int.signedness == .signed) {
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
		if(level == .err and !openingErrorWindow) {
			openingErrorWindow = true;
			gui.openWindow("error_prompt");
			openingErrorWindow = false;
		}
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

	const _timestamp = std.time.timestamp();

	const _path_str = std.fmt.allocPrint(stackAllocator.allocator, "logs/ts_{}.log", .{_timestamp}) catch unreachable;
	defer stackAllocator.free(_path_str);

	logFileTs = std.fs.cwd().createFile(_path_str, .{}) catch |err| {
		std.log.err("Couldn't create {s}: {s}", .{_path_str, @errorName(err)});
		return;
	};

	supportsANSIColors = std.io.getStdOut().supportsAnsiEscapeCodes();
}

fn deinitLogging() void {
	if (logFile) |_logFile| {
		_logFile.close();
		logFile = null;
	}

	if (logFileTs) |_logFileTs| {
		_logFileTs.close();
		logFileTs = null;
	}
}

fn logToFile(comptime format: []const u8, args: anytype) void {
	var buf: [65536]u8 = undefined;
	var fba = std.heap.FixedBufferAllocator.init(&buf);
	const allocator = fba.allocator();

	const string = std.fmt.allocPrint(allocator, format, args) catch format;
	defer allocator.free(string);
	(logFile orelse return).writeAll(string) catch {};
	(logFileTs orelse return).writeAll(string) catch {};
}

fn logToStdErr(comptime format: []const u8, args: anytype) void {
	var buf: [65536]u8 = undefined;
	var fba = std.heap.FixedBufferAllocator.init(&buf);
	const allocator = fba.allocator();

	const string = std.fmt.allocPrint(allocator, format, args) catch format;
	defer allocator.free(string);
	nosuspend std.io.getStdErr().writeAll(string) catch {};
}

// MARK: Callbacks
fn escape() void {
	if(gui.selectedTextInput != null) {
		gui.selectedTextInput = null;
		return;
	}
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
	gui.toggleGameMenu();
	gui.openWindow("inventory");
}
fn openWorkbench() void {
	if(game.world == null) return;
	gui.toggleGameMenu();
	gui.openWindow("workbench");
}
fn openCreativeInventory() void {
	if(game.world == null) return;
	if(!game.Player.isCreative()) return;
	gui.toggleGameMenu();
	gui.openWindow("creative_inventory");
}
fn openSharedInventoryTesting() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("shared_inventory_testing");
}
fn openChat() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("chat");
	gui.windowlist.chat.input.select();
}
fn openCommand() void {
	openChat();
	gui.windowlist.chat.input.clear();
	gui.windowlist.chat.input.inputCharacter('/');
}
fn takeBackgroundImageFn() void {
	if(game.world == null) return;
	renderer.MenuBackGround.takeBackgroundImage();
}
fn toggleHideGui() void {
	gui.hideGui = !gui.hideGui;
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
fn toggleAdvancedNetworkDebugOverlay() void {
	gui.toggleWindow("debug_network_advanced");
}
fn cycleHotbarSlot(i: comptime_int) *const fn() void {
	return &struct {
		fn set() void {
			game.Player.selectedSlot = @intCast(@mod(@as(i33, game.Player.selectedSlot) + i, 12));
		}
	}.set;
}
fn setHotbarSlot(i: comptime_int) *const fn() void {
	return &struct {
		fn set() void {
			game.Player.selectedSlot = i - 1;
		}
	}.set;
}

pub const KeyBoard = struct { // MARK: KeyBoard
	const c = Window.c;
	pub var keys = [_]Window.Key {
		// Gameplay:
		.{.name = "forward", .key = c.GLFW_KEY_W, .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_Y, .positive = false}},
		.{.name = "left", .key = c.GLFW_KEY_A, .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_X, .positive = false}},
		.{.name = "backward", .key = c.GLFW_KEY_S, .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_Y, .positive = true}},
		.{.name = "right", .key = c.GLFW_KEY_D, .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_X, .positive = true}},
		.{.name = "sprint", .key = c.GLFW_KEY_LEFT_CONTROL, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_LEFT_THUMB},
		.{.name = "jump", .key = c.GLFW_KEY_SPACE, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_A},
		.{.name = "crouch", .key = c.GLFW_KEY_LEFT_SHIFT, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_RIGHT_THUMB},
		.{.name = "fly", .key = c.GLFW_KEY_F, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_DPAD_DOWN, .pressAction = &game.flyToggle},
		.{.name = "ghost", .key = c.GLFW_KEY_G, .pressAction = &game.ghostToggle},
		.{.name = "hyperSpeed", .key = c.GLFW_KEY_H, .pressAction = &game.hyperSpeedToggle},
		.{.name = "fall", .key = c.GLFW_KEY_LEFT_SHIFT, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_RIGHT_THUMB},
		.{.name = "shift", .key = c.GLFW_KEY_LEFT_SHIFT, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_RIGHT_THUMB},
		.{.name = "placeBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_TRIGGER}, .pressAction = &game.pressPlace, .releaseAction = &game.releasePlace, .notifyRequirement = .inGame},
		.{.name = "breakBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_TRIGGER}, .pressAction = &game.pressBreak, .releaseAction = &game.releaseBreak, .notifyRequirement = .inGame},
		.{.name = "acquireSelectedBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_MIDDLE, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_DPAD_LEFT, .pressAction = &game.pressAcquireSelectedBlock, .notifyRequirement = .inGame},

		.{.name = "takeBackgroundImage", .key = c.GLFW_KEY_PRINT_SCREEN, .pressAction = &takeBackgroundImageFn},
		.{.name = "fullscreen", .key = c.GLFW_KEY_F11, .pressAction = &Window.toggleFullscreen},

		// Gui:
		.{.name = "escape", .key = c.GLFW_KEY_ESCAPE, .pressAction = &escape, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_B},
		.{.name = "openInventory", .key = c.GLFW_KEY_E, .pressAction = &openInventory, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_X},
		.{.name = "openCreativeInventory(aka cheat inventory)", .key = c.GLFW_KEY_C, .pressAction = &openCreativeInventory, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_Y},
		.{.name = "openChat", .key = c.GLFW_KEY_T, .releaseAction = &openChat},
		.{.name = "openCommand", .key = c.GLFW_KEY_SLASH, .releaseAction = &openCommand},
		.{.name = "mainGuiButton", .mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &gui.mainButtonPressed, .releaseAction = &gui.mainButtonReleased, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_A, .notifyRequirement = .inMenu},
		.{.name = "secondaryGuiButton", .mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .pressAction = &gui.secondaryButtonPressed, .releaseAction = &gui.secondaryButtonReleased, .gamepadButton = c.GLFW_GAMEPAD_BUTTON_Y, .notifyRequirement = .inMenu},
		// gamepad gui.
		.{.name = "scrollUp", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_Y, .positive = false}},
		.{.name = "scrollDown", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_Y, .positive = true}},
		.{.name = "uiUp", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_Y, .positive = false}},
		.{.name = "uiLeft", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_X, .positive = false}},
		.{.name = "uiDown",  .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_Y, .positive = true}},
		.{.name = "uiRight", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_X, .positive = true}},
		// text:
		.{.name = "textCursorLeft", .key = c.GLFW_KEY_LEFT, .repeatAction = &gui.textCallbacks.left},
		.{.name = "textCursorRight", .key = c.GLFW_KEY_RIGHT, .repeatAction = &gui.textCallbacks.right},
		.{.name = "textCursorDown", .key = c.GLFW_KEY_DOWN, .repeatAction = &gui.textCallbacks.down},
		.{.name = "textCursorUp", .key = c.GLFW_KEY_UP, .repeatAction = &gui.textCallbacks.up},
		.{.name = "textGotoStart", .key = c.GLFW_KEY_HOME, .repeatAction = &gui.textCallbacks.gotoStart},
		.{.name = "textGotoEnd", .key = c.GLFW_KEY_END, .repeatAction = &gui.textCallbacks.gotoEnd},
		.{.name = "textDeleteLeft", .key = c.GLFW_KEY_BACKSPACE, .repeatAction = &gui.textCallbacks.deleteLeft},
		.{.name = "textDeleteRight", .key = c.GLFW_KEY_DELETE, .repeatAction = &gui.textCallbacks.deleteRight},
		.{.name = "textSelectAll", .key = c.GLFW_KEY_A, .repeatAction = &gui.textCallbacks.selectAll},
		.{.name = "textCopy", .key = c.GLFW_KEY_C, .repeatAction = &gui.textCallbacks.copy},
		.{.name = "textPaste", .key = c.GLFW_KEY_V, .repeatAction = &gui.textCallbacks.paste},
		.{.name = "textCut", .key = c.GLFW_KEY_X, .repeatAction = &gui.textCallbacks.cut},
		.{.name = "textNewline", .key = c.GLFW_KEY_ENTER, .repeatAction = &gui.textCallbacks.newline},

		// Hotbar shortcuts:
		.{.name = "Hotbar 1", .key = c.GLFW_KEY_1, .pressAction = setHotbarSlot(1)},
		.{.name = "Hotbar 2", .key = c.GLFW_KEY_2, .pressAction = setHotbarSlot(2)},
		.{.name = "Hotbar 3", .key = c.GLFW_KEY_3, .pressAction = setHotbarSlot(3)},
		.{.name = "Hotbar 4", .key = c.GLFW_KEY_4, .pressAction = setHotbarSlot(4)},
		.{.name = "Hotbar 5", .key = c.GLFW_KEY_5, .pressAction = setHotbarSlot(5)},
		.{.name = "Hotbar 6", .key = c.GLFW_KEY_6, .pressAction = setHotbarSlot(6)},
		.{.name = "Hotbar 7", .key = c.GLFW_KEY_7, .pressAction = setHotbarSlot(7)},
		.{.name = "Hotbar 8", .key = c.GLFW_KEY_8, .pressAction = setHotbarSlot(8)},
		.{.name = "Hotbar 9", .key = c.GLFW_KEY_9, .pressAction = setHotbarSlot(9)},
		.{.name = "Hotbar 10", .key = c.GLFW_KEY_0, .pressAction = setHotbarSlot(10)},
		.{.name = "Hotbar 11", .key = c.GLFW_KEY_MINUS, .pressAction = setHotbarSlot(11)},
		.{.name = "Hotbar 12", .key = c.GLFW_KEY_EQUAL, .pressAction = setHotbarSlot(12)},
		.{.name = "Hotbar left", .gamepadButton = c.GLFW_GAMEPAD_BUTTON_LEFT_BUMPER, .pressAction = cycleHotbarSlot(-1)},
		.{.name = "Hotbar right", .gamepadButton = c.GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER, .pressAction = cycleHotbarSlot(1)},
		.{.name = "cameraLeft", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_X, .positive = false}},
		.{.name = "cameraRight", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_X, .positive = true}},
		.{.name = "cameraUp", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_Y, .positive = false}},
		.{.name = "cameraDown", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_RIGHT_Y, .positive = true}},
		// debug:
		.{.name = "hideMenu", .key = c.GLFW_KEY_F1, .pressAction = &toggleHideGui},
		.{.name = "debugOverlay", .key = c.GLFW_KEY_F3, .pressAction = &toggleDebugOverlay},
		.{.name = "performanceOverlay", .key = c.GLFW_KEY_F4, .pressAction = &togglePerformanceOverlay},
		.{.name = "gpuPerformanceOverlay", .key = c.GLFW_KEY_F5, .pressAction = &toggleGPUPerformanceOverlay},
		.{.name = "networkDebugOverlay", .key = c.GLFW_KEY_F6, .pressAction = &toggleNetworkDebugOverlay},
		.{.name = "advancedNetworkDebugOverlay", .key = c.GLFW_KEY_F7, .pressAction = &toggleAdvancedNetworkDebugOverlay},

		.{.name = "shared_inventory_testing", .key = c.GLFW_KEY_O, .pressAction = &openSharedInventoryTesting},
	};

	pub fn key(name: []const u8) *const Window.Key { // TODO: Maybe I should use a hashmap here?
		for(&keys) |*_key| {
			if(std.mem.eql(u8, name, _key.name)) {
				return _key;
			}
		}
		std.log.err("Couldn't find keyboard key with name {s}", .{name});
		return &.{.name = ""};
	}
};

/// Records gpu time per frame.
pub var lastFrameTime = std.atomic.Value(f64).init(0);
/// Measures time between different frames' beginnings.
pub var lastDeltaTime = std.atomic.Value(f64).init(0);

var shouldExitToMenu = std.atomic.Value(bool).init(false);
pub fn exitToMenu(_: usize) void {
	shouldExitToMenu.store(true, .monotonic);
}


fn isValidIdentifierName(str: []const u8) bool { // TODO: Remove after #480
	if(str.len == 0) return false;
	if(!std.ascii.isAlphabetic(str[0]) and str[0] != '_') return false;
	for(str[1..]) |c| {
		if(!std.ascii.isAlphanumeric(c) and c != '_') return false;
	}
	return true;
}

fn isHiddenOrParentHiddenPosix(path: []const u8) bool {
	var iter = std.fs.path.componentIterator(path) catch |err| {
		std.log.err("Cannot iterate on path {s}: {s}!", .{path, @errorName(err)});
		return false;
	};
	while (iter.next()) |component| {
		if (std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
			continue;
		}
		if (component.name.len > 0 and component.name[0] == '.') {
			return true;
		}
	}
	return false;
}
pub fn convertJsonToZon(jsonPath: []const u8) void { // TODO: Remove after #480
	if (isHiddenOrParentHiddenPosix(jsonPath)) {
		std.log.info("NOT converting {s}.", .{jsonPath});
		return;
	}
	std.log.info("Converting {s}:", .{jsonPath});
	const jsonString = files.read(stackAllocator, jsonPath) catch |err| {
		std.log.err("Could convert file {s}: {s}", .{jsonPath, @errorName(err)});
		return;
	};
	defer stackAllocator.free(jsonString);
	var zonString = List(u8).init(stackAllocator);
	defer zonString.deinit();
	std.log.debug("{s}", .{jsonString});

	var i: usize = 0;
	while(i < jsonString.len) : (i += 1) {
		switch(jsonString[i]) {
			'\"' => {
				var j = i + 1;
				while(j < jsonString.len and jsonString[j] != '"') : (j += 1) {}
				const string = jsonString[i+1..j];
				if(isValidIdentifierName(string)) {
					zonString.append('.');
					zonString.appendSlice(string);
				} else {
					zonString.append('"');
					zonString.appendSlice(string);
					zonString.append('"');
				}
				i = j;
			},
			'[', '{' => {
				zonString.append('.');
				zonString.append('{');
			},
			']', '}' => {
				zonString.append('}');
			},
			':' => {
				zonString.append('=');
			},
			else => |c| {
				zonString.append(c);
			},
		}
	}
	const zonPath = std.fmt.allocPrint(stackAllocator.allocator, "{s}.zig.zon", .{jsonPath[0..std.mem.lastIndexOfScalar(u8, jsonPath, '.') orelse unreachable]}) catch unreachable;
	defer stackAllocator.free(zonPath);
	std.log.info("Outputting to {s}:", .{zonPath});
	std.log.debug("{s}", .{zonString.items});
	files.write(zonPath, zonString.items) catch |err| {
		std.log.err("Got error while writing to file: {s}", .{@errorName(err)});
		return;
	};
	std.log.info("Deleting file {s}", .{jsonPath});
	std.fs.cwd().deleteFile(jsonPath) catch |err| {
		std.log.err("Got error while deleting file: {s}", .{@errorName(err)});
		return;
	};
}

pub fn main() void { // MARK: main()
	seed = @bitCast(std.time.milliTimestamp());
	defer if(global_gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};
	var sta = utils.StackAllocator.init(globalAllocator, 1 << 23);
	defer sta.deinit();
	stackAllocator = sta.allocator();

	initLogging();
	defer deinitLogging();

	if(std.fs.cwd().openFile("settings.json", .{})) |file| blk: { // TODO: Remove after #480
		file.close();
		std.log.warn("Detected old game client. Converting all .json files to .zig.zon", .{});
		var dir = std.fs.cwd().openDir(".", .{.iterate = true}) catch |err| {
			std.log.err("Could not open game directory to convert json files: {s}. Conversion aborted", .{@errorName(err)});
			break :blk;
		};
		defer dir.close();

		var walker = dir.walk(stackAllocator.allocator) catch unreachable;
		defer walker.deinit();
		while(walker.next() catch |err| {
			std.log.err("Got error while iterating through json files directory: {s}", .{@errorName(err)});
			break :blk;
		}) |entry| {
			if(entry.kind == .file and (std.ascii.endsWithIgnoreCase(entry.basename, ".json") or std.mem.eql(u8, entry.basename, "world.dat")) and !std.ascii.startsWithIgnoreCase(entry.path, "compiler") and !std.ascii.startsWithIgnoreCase(entry.path, ".zig-cache") and !std.ascii.startsWithIgnoreCase(entry.path, ".vscode")) {
				convertJsonToZon(entry.path);
			}
		}
	} else |_| {}

	gui.initWindowList();
	defer gui.deinitWindowList();

	files.init();
	defer files.deinit();

	settings.init();
	defer settings.deinit();

	threadPool = utils.ThreadPool.init(globalAllocator, settings.cpuThreads orelse @max(1, (std.Thread.getCpuCount() catch 4) -| 1));
	defer threadPool.deinit();

	file_monitor.init();
	defer file_monitor.deinit();

	Window.init();
	defer Window.deinit();

	graphics.init();
	defer graphics.deinit();

	audio.init() catch std.log.err("Failed to initialize audio. Continuing the game without sounds.", .{});
	defer audio.deinit();

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

	gui.init();
	defer gui.deinit();

	if(settings.playerName.len == 0) {
		gui.openWindow("change_name");
	} else {
		gui.openWindow("main");
	}

	server.terrain.initGenerators();
	defer server.terrain.deinitGenerators();

	const c = Window.c;

	c.glCullFace(c.GL_BACK);
	c.glEnable(c.GL_BLEND);
	c.glEnable(c.GL_DEPTH_CLAMP);
	c.glDepthFunc(c.GL_LESS);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	Window.GLFWCallbacks.framebufferSize(undefined, Window.width, Window.height);
	var lastBeginRendering = std.time.nanoTimestamp();

	if(settings.developerAutoEnterWorld.len != 0) {
		// Speed up the dev process by entering the world directly.
		gui.windowlist.save_selection.openWorld(settings.developerAutoEnterWorld);
	}

	audio.setMusic("cubyz:cubyz");

	while(c.glfwWindowShouldClose(Window.window) == 0) {
		const isHidden = c.glfwGetWindowAttrib(Window.window, c.GLFW_ICONIFIED) == c.GLFW_TRUE;
		if(!isHidden) {
			c.glfwSwapBuffers(Window.window);
			// Clear may also wait on vsync, so it's done before handling events:
			gui.windowlist.gpu_performance_measuring.startQuery(.screenbuffer_clear);
			c.glClearColor(0.5, 1, 1, 1);
			c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
			gui.windowlist.gpu_performance_measuring.stopQuery();
		} else {
			std.time.sleep(16_000_000);
		}

		const endRendering = std.time.nanoTimestamp();
		const frameTime = @as(f64, @floatFromInt(endRendering -% lastBeginRendering))/1e9;
		if(settings.developerGPUInfiniteLoopDetection and frameTime > 5) { // On linux a process that runs 10 seconds or longer on the GPU will get stopped. This allows detecting an infinite loop on the GPU.
			std.log.err("Frame got too long with {} seconds. Infinite loop on GPU?", .{frameTime});
			std.posix.exit(1);
		}
		lastFrameTime.store(frameTime, .monotonic);

		if(settings.fpsCap) |fpsCap| {
			const minFrameTime = @divFloor(1000*1000*1000, fpsCap);
			const sleep = @min(minFrameTime, @max(0, minFrameTime - (endRendering -% lastBeginRendering)));
			std.time.sleep(sleep);
		}
		const begin = std.time.nanoTimestamp();
		const deltaTime = @as(f64, @floatFromInt(begin -% lastBeginRendering))/1e9;
		lastDeltaTime.store(deltaTime, .monotonic);
		lastBeginRendering = begin;

		Window.handleEvents(deltaTime);

		file_monitor.handleEvents();

		if(game.world != null) { // Update the game
			game.update(deltaTime);
		}

		if(!isHidden) {
			c.glEnable(c.GL_CULL_FACE);
			c.glEnable(c.GL_DEPTH_TEST);
			renderer.render(game.Player.getEyePosBlocking());
			// Render the GUI
			gui.windowlist.gpu_performance_measuring.startQuery(.gui);
			c.glDisable(c.GL_CULL_FACE);
			c.glDisable(c.GL_DEPTH_TEST);
			gui.updateAndRenderGui();
			gui.windowlist.gpu_performance_measuring.stopQuery();
		}

		if(shouldExitToMenu.load(.monotonic)) {
			shouldExitToMenu.store(false, .monotonic);
			if(game.world) |world| {
				world.deinit();
				game.world = null;
			}
			gui.openWindow("main");
			audio.setMusic("cubyz:cubyz");
		}
	}

	if(game.world) |world| {
		world.deinit();
		game.world = null;
	}
}

test "abc" {
	_ = @import("json.zig");
	_ = @import("zon.zig");
}
