const std = @import("std");

pub const gui = @import("gui/gui.zig");
pub const server = @import("server/server.zig");

pub const audio = @import("audio.zig");
pub const assets = @import("assets.zig");
pub const block_entity = @import("block_entity.zig");
pub const blocks = @import("blocks.zig");
pub const blueprint = @import("blueprint.zig");
pub const chunk = @import("chunk.zig");
pub const entity = @import("entity.zig");
pub const files = @import("files.zig");
pub const game = @import("game.zig");
pub const graphics = @import("graphics.zig");
pub const itemdrop = @import("itemdrop.zig");
pub const items = @import("items.zig");
pub const JsonElement = @import("json.zig").JsonElement;
pub const migrations = @import("migrations.zig");
pub const models = @import("models.zig");
pub const network = @import("network.zig");
pub const physics = @import("physics.zig");
pub const random = @import("random.zig");
pub const renderer = @import("renderer.zig");
pub const rotation = @import("rotation.zig");
pub const settings = @import("settings.zig");
pub const particles = @import("particles.zig");
const tag = @import("tag.zig");
pub const Tag = tag.Tag;
pub const utils = @import("utils.zig");
pub const vec = @import("vec.zig");
pub const ZonElement = @import("zon.zig").ZonElement;

pub const Window = @import("graphics/Window.zig");

pub const heap = @import("utils/heap.zig");

pub const List = @import("utils/list.zig").List;
pub const ListUnmanaged = @import("utils/list.zig").ListUnmanaged;
pub const MultiArray = @import("utils/list.zig").MultiArray;

const file_monitor = utils.file_monitor;

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

pub threadlocal var stackAllocator: heap.NeverFailingAllocator = undefined;
pub threadlocal var seed: u64 = undefined;
threadlocal var stackAllocatorBase: heap.StackAllocator = undefined;
var global_gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe = true}){};
var handled_gpa = heap.ErrorHandlingAllocator.init(global_gpa.allocator());
pub const globalAllocator: heap.NeverFailingAllocator = handled_gpa.allocator();
pub var threadPool: *utils.ThreadPool = undefined;

pub fn initThreadLocals() void {
	seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
	stackAllocatorBase = heap.StackAllocator.init(globalAllocator, 1 << 23);
	stackAllocator = stackAllocatorBase.allocator();
	heap.GarbageCollection.addThread();
}

pub fn deinitThreadLocals() void {
	stackAllocatorBase.deinit();
	heap.GarbageCollection.removeThread();
}

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
	.logFn = struct {
		pub fn logFn(
			comptime level: std.log.Level,
			comptime _: @Type(.enum_literal),
			comptime format: []const u8,
			args: anytype,
		) void {
			const color = comptime switch(level) {
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
							sectionId = sectionId ++ &[_]usize{sections};
							sections += 1;
							continue;
						}
					} else {
						sectionString = sectionString ++ format[i .. i + 1];
					}
				} else {
					formatString = formatString ++ format[i .. i + 1];
					if(format[i] == '}') {
						sections += 1;
						mode = 0;
					}
				}
			}
			formatString = formatString ++ "{s}";
			sectionResults = sectionResults ++ &[_][]const u8{sectionString};
			sectionId = sectionId ++ &[_]usize{sections};
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
				} else if(TI == .pointer and TI.pointer.size == .slice and TI.pointer.child == u8) {
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
						comptimeTuple[len + 1] = sectionResults[i_2];
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
				resultArgs[len + 1] = args[i_1];
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
		}
	}.logFn,
};

fn initLogging() void {
	logFile = null;
	files.cwd().makePath("logs") catch |err| {
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

	supportsANSIColors = std.fs.File.stdout().supportsAnsiEscapeCodes();
}

fn deinitLogging() void {
	if(logFile) |_logFile| {
		_logFile.close();
		logFile = null;
	}

	if(logFileTs) |_logFileTs| {
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
	const writer = std.debug.lockStderrWriter(&.{});
	defer std.debug.unlockStderrWriter();
	nosuspend writer.writeAll(string) catch {};
}

// MARK: Callbacks
fn escape() void {
	if(gui.selectedTextInput != null) {
		gui.setSelectedTextInput(null);
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
fn openCreativeInventory() void {
	if(game.world == null) return;
	if(!game.Player.isCreative()) return;
	gui.toggleGameMenu();
	gui.openWindow("creative_inventory");
}
fn openChat() void {
	if(game.world == null) return;
	ungrabMouse();
	gui.openWindow("chat");
	gui.windowlist.chat.input.select();
}
fn openCommand() void {
	if(game.world == null) return;
	openChat();
	gui.windowlist.chat.input.clear();
	gui.windowlist.chat.input.inputCharacter('/');
}
fn takeBackgroundImageFn() void {
	if(game.world == null) return;

	const oldHideGui = gui.hideGui;
	gui.hideGui = true;
	const oldShowItem = itemdrop.ItemDisplayManager.showItem;
	itemdrop.ItemDisplayManager.showItem = false;

	renderer.MenuBackGround.takeBackgroundImage();

	gui.hideGui = oldHideGui;
	itemdrop.ItemDisplayManager.showItem = oldShowItem;
}
fn toggleHideGui() void {
	gui.hideGui = !gui.hideGui;
}
fn toggleHideDisplayItem() void {
	itemdrop.ItemDisplayManager.showItem = !itemdrop.ItemDisplayManager.showItem;
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
	pub var keys = [_]Window.Key{
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
		.{.name = "uiDown", .gamepadAxis = .{.axis = c.GLFW_GAMEPAD_AXIS_LEFT_Y, .positive = true}},
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
		.{.name = "textSelectAll", .key = c.GLFW_KEY_A, .repeatAction = &gui.textCallbacks.selectAll, .requiredModifiers = .{.control = true}},
		.{.name = "textCopy", .key = c.GLFW_KEY_C, .repeatAction = &gui.textCallbacks.copy, .requiredModifiers = .{.control = true}},
		.{.name = "textPaste", .key = c.GLFW_KEY_V, .repeatAction = &gui.textCallbacks.paste, .requiredModifiers = .{.control = true}},
		.{.name = "textCut", .key = c.GLFW_KEY_X, .repeatAction = &gui.textCallbacks.cut, .requiredModifiers = .{.control = true}},
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
		.{.name = "hideDisplayItem", .key = c.GLFW_KEY_F2, .pressAction = &toggleHideDisplayItem},
		.{.name = "debugOverlay", .key = c.GLFW_KEY_F3, .pressAction = &toggleDebugOverlay},
		.{.name = "performanceOverlay", .key = c.GLFW_KEY_F4, .pressAction = &togglePerformanceOverlay},
		.{.name = "gpuPerformanceOverlay", .key = c.GLFW_KEY_F5, .pressAction = &toggleGPUPerformanceOverlay},
		.{.name = "networkDebugOverlay", .key = c.GLFW_KEY_F6, .pressAction = &toggleNetworkDebugOverlay},
		.{.name = "advancedNetworkDebugOverlay", .key = c.GLFW_KEY_F7, .pressAction = &toggleAdvancedNetworkDebugOverlay},
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
	while(iter.next()) |component| {
		if(std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
			continue;
		}
		if(component.name.len > 0 and component.name[0] == '.') {
			return true;
		}
	}
	return false;
}
pub fn convertJsonToZon(jsonPath: []const u8) void { // TODO: Remove after #480
	if(isHiddenOrParentHiddenPosix(jsonPath)) {
		std.log.info("NOT converting {s}.", .{jsonPath});
		return;
	}
	std.log.info("Converting {s}:", .{jsonPath});
	const jsonString = files.cubyzDir().read(stackAllocator, jsonPath) catch |err| {
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
				const string = jsonString[i + 1 .. j];
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
	const zonPath = std.fmt.allocPrint(stackAllocator.allocator, "{s}.zig.zon", .{jsonPath[0 .. std.mem.lastIndexOfScalar(u8, jsonPath, '.') orelse unreachable]}) catch unreachable;
	defer stackAllocator.free(zonPath);
	std.log.info("Outputting to {s}:", .{zonPath});
	std.log.debug("{s}", .{zonString.items});
	files.cubyzDir().write(zonPath, zonString.items) catch |err| {
		std.log.err("Got error while writing to file: {s}", .{@errorName(err)});
		return;
	};
	std.log.info("Deleting file {s}", .{jsonPath});
	files.cubyzDir().deleteFile(jsonPath) catch |err| {
		std.log.err("Got error while deleting file: {s}", .{@errorName(err)});
		return;
	};
}

pub fn main() void { // MARK: main()
	defer if(global_gpa.deinit() == .leak) {
		std.log.err("Memory leak", .{});
	};
	defer heap.GarbageCollection.assertAllThreadsStopped();
	initThreadLocals();
	defer deinitThreadLocals();

	initLogging();
	defer deinitLogging();

	if(files.cwd().openFile("settings.json")) |file| blk: { // TODO: Remove after #480
		file.close();
		std.log.warn("Detected old game client. Converting all .json files to .zig.zon", .{});
		var dir = files.cwd().openIterableDir(".") catch |err| {
			std.log.err("Could not open game directory to convert json files: {s}. Conversion aborted", .{@errorName(err)});
			break :blk;
		};
		defer dir.close();

		var walker = dir.walk(stackAllocator);
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

	std.log.info("Starting game client with version {s}", .{settings.version.version});

	gui.initWindowList();
	defer gui.deinitWindowList();

	settings.launchConfig.init();
	defer settings.launchConfig.deinit();

	files.init();
	defer files.deinit();

	// Background image migration, should be removed after version 0 (#480)
	if(files.cwd().hasDir("assets/backgrounds")) moveBlueprints: {
		std.fs.rename(std.fs.cwd(), "assets/backgrounds", files.cubyzDir().dir, "backgrounds") catch |err| {
			const notification = std.fmt.allocPrint(stackAllocator.allocator, "Encountered error while moving backgrounds: {s}\nYou may have to move your assets/backgrounds manually to {s}/backgrounds", .{@errorName(err), files.cubyzDirStr()}) catch unreachable;
			defer stackAllocator.free(notification);
			gui.windowlist.notification.raiseNotification(notification);
			break :moveBlueprints;
		};
		std.log.info("Moved backgrounds to {s}/backgrounds", .{files.cubyzDirStr()});
	}

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

	utils.initDynamicIntArrayStorage();
	defer utils.deinitDynamicIntArrayStorage();

	chunk.init();
	defer chunk.deinit();

	rotation.init();
	defer rotation.deinit();

	block_entity.init();
	defer block_entity.deinit();

	blocks.tickFunctions = .init();
	defer blocks.tickFunctions.deinit();

	blocks.touchFunctions = .init();
	defer blocks.touchFunctions.deinit();

	models.init();
	defer models.deinit();

	items.globalInit();
	defer items.deinit();

	itemdrop.ItemDropRenderer.init();
	defer itemdrop.ItemDropRenderer.deinit();

	tag.init();
	defer tag.deinit();

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

	particles.ParticleManager.init();
	defer particles.ParticleManager.deinit();

	if(settings.playerName.len == 0) {
		gui.openWindow("change_name");
	} else {
		gui.openWindow("main");
	}

	// Save migration, should be removed after version 0 (#480)
	if(files.cwd().hasDir("saves")) moveSaves: {
		std.fs.rename(std.fs.cwd(), "saves", files.cubyzDir().dir, "saves") catch |err| {
			const notification = std.fmt.allocPrint(stackAllocator.allocator, "Encountered error while moving saves: {s}\nYou may have to move your saves manually to {s}/saves", .{@errorName(err), files.cubyzDirStr()}) catch unreachable;
			defer stackAllocator.free(notification);
			gui.windowlist.notification.raiseNotification(notification);
			break :moveSaves;
		};
		const notification = std.fmt.allocPrint(stackAllocator.allocator, "Your saves have been moved from saves to {s}/saves", .{files.cubyzDirStr()}) catch unreachable;
		defer stackAllocator.free(notification);
		gui.windowlist.notification.raiseNotification(notification);
	}

	// Blueprint migration, should be removed after version 0 (#480)
	if(files.cwd().hasDir("blueprints")) moveBlueprints: {
		std.fs.rename(std.fs.cwd(), "blueprints", files.cubyzDir().dir, "blueprints") catch |err| {
			std.log.err("Encountered error while moving blueprints: {s}\nYou may have to move your blueprints manually to {s}/blueprints", .{@errorName(err), files.cubyzDirStr()});
			break :moveBlueprints;
		};
		std.log.info("Moved blueprints to {s}/blueprints", .{files.cubyzDirStr()});
	}

	server.terrain.globalInit();
	defer server.terrain.globalDeinit();

	const c = Window.c;

	Window.GLFWCallbacks.framebufferSize(undefined, Window.width, Window.height);
	var lastBeginRendering = std.time.nanoTimestamp();

	if(settings.developerAutoEnterWorld.len != 0) {
		// Speed up the dev process by entering the world directly.
		gui.windowlist.save_selection.openWorld(settings.developerAutoEnterWorld);
	}

	audio.setMusic("cubyz:cubyz");

	while(c.glfwWindowShouldClose(Window.window) == 0) {
		heap.GarbageCollection.syncPoint();
		const isHidden = c.glfwGetWindowAttrib(Window.window, c.GLFW_ICONIFIED) == c.GLFW_TRUE;
		if(!isHidden) {
			c.glfwSwapBuffers(Window.window);
			// Clear may also wait on vsync, so it's done before handling events:
			gui.windowlist.gpu_performance_measuring.startQuery(.screenbuffer_clear);
			c.glDepthFunc(c.GL_LESS);
			c.glDepthMask(c.GL_TRUE);
			c.glDisable(c.GL_SCISSOR_TEST);
			c.glClearColor(0.5, 1, 1, 1);
			c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
			gui.windowlist.gpu_performance_measuring.stopQuery();
		} else {
			std.Thread.sleep(16_000_000);
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
			std.Thread.sleep(sleep);
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
			renderer.render(game.Player.getEyePosBlocking(), deltaTime);
			// Render the GUI
			gui.windowlist.gpu_performance_measuring.startQuery(.gui);
			gui.updateAndRenderGui();
			gui.windowlist.gpu_performance_measuring.stopQuery();
		}

		if(shouldExitToMenu.load(.monotonic)) {
			shouldExitToMenu.store(false, .monotonic);
			Window.setMouseGrabbed(false);
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

/// std.testing.refAllDeclsRecursive, but ignores C imports (by name)
pub fn refAllDeclsRecursiveExceptCImports(comptime T: type) void {
	if(!@import("builtin").is_test) return;
	inline for(comptime std.meta.declarations(T)) |decl| blk: {
		if(comptime std.mem.eql(u8, decl.name, "c")) continue;
		if(comptime std.mem.eql(u8, decl.name, "hbft")) break :blk;
		if(comptime std.mem.eql(u8, decl.name, "stb_image")) break :blk;
		// TODO: Remove this after Zig removes Managed hashmap PixelGuys/Cubyz#308
		if(comptime std.mem.eql(u8, decl.name, "Managed")) continue;
		if(@TypeOf(@field(T, decl.name)) == type) {
			switch(@typeInfo(@field(T, decl.name))) {
				.@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursiveExceptCImports(@field(T, decl.name)),
				else => {},
			}
		}
		_ = &@field(T, decl.name);
	}
}

test "abc" {
	@setEvalBranchQuota(1000000);
	refAllDeclsRecursiveExceptCImports(@This());
	_ = @import("json.zig");
	_ = @import("zon.zig");
}
