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

pub const Window = @import("graphics/Window.zig");

pub const List = @import("utils/list.zig").List;
pub const ListUnmanaged = @import("utils/list.zig").ListUnmanaged;

const file_monitor = utils.file_monitor;

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

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
	const c = Window.c;
	pub var keys = [_]Window.Key {
		// Gameplay:
		.{.name = "forward", .key = c.GLFW_KEY_W},
		.{.name = "left", .key = c.GLFW_KEY_A},
		.{.name = "backward", .key = c.GLFW_KEY_S},
		.{.name = "right", .key = c.GLFW_KEY_D},
		.{.name = "sprint", .key = c.GLFW_KEY_LEFT_CONTROL},
		.{.name = "jump", .key = c.GLFW_KEY_SPACE},
		.{.name = "fall", .key = c.GLFW_KEY_LEFT_SHIFT},
		.{.name = "fullscreen", .key = c.GLFW_KEY_F11, .releaseAction = &Window.toggleFullscreen},
		.{.name = "placeBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .pressAction = &game.Player.placeBlock}, // TODO: Add GLFW_REPEAT behavior to mouse buttons.
		.{.name = "breakBlock", .mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &game.Player.breakBlock}, // TODO: Add GLFW_REPEAT behavior to mouse buttons.

		.{.name = "takeBackgroundImage", .key = c.GLFW_KEY_PRINT_SCREEN, .releaseAction = &takeBackgroundImageFn},

		// Gui:
		.{.name = "escape", .key = c.GLFW_KEY_ESCAPE, .releaseAction = &escape},
		.{.name = "openInventory", .key = c.GLFW_KEY_I, .releaseAction = &openInventory},
		.{.name = "openWorkbench", .key = c.GLFW_KEY_K, .releaseAction = &openWorkbench}, // TODO: Remove
		.{.name = "openCreativeInventory(aka cheat inventory)", .key = c.GLFW_KEY_C, .releaseAction = &openCreativeInventory},
		.{.name = "mainGuiButton", .mouseButton = c.GLFW_MOUSE_BUTTON_LEFT, .pressAction = &gui.mainButtonPressed, .releaseAction = &gui.mainButtonReleased},
		.{.name = "secondaryGuiButton", .mouseButton = c.GLFW_MOUSE_BUTTON_RIGHT, .pressAction = &gui.secondaryButtonPressed, .releaseAction = &gui.secondaryButtonReleased},
		// text:
		.{.name = "textCursorLeft", .key = c.GLFW_KEY_LEFT, .repeatAction = &gui.textCallbacks.left},
		.{.name = "textCursorRight", .key = c.GLFW_KEY_RIGHT, .repeatAction = &gui.textCallbacks.right},
		.{.name = "textCursorDown", .key = c.GLFW_KEY_DOWN, .repeatAction = &gui.textCallbacks.down},
		.{.name = "textCursorUp", .key = c.GLFW_KEY_UP, .repeatAction = &gui.textCallbacks.up},
		.{.name = "textGotoStart", .key = c.GLFW_KEY_HOME, .repeatAction = &gui.textCallbacks.gotoStart},
		.{.name = "textGotoEnd", .key = c.GLFW_KEY_END, .repeatAction = &gui.textCallbacks.gotoEnd},
		.{.name = "textDeleteLeft", .key = c.GLFW_KEY_BACKSPACE, .repeatAction = &gui.textCallbacks.deleteLeft},
		.{.name = "textDeleteRight", .key = c.GLFW_KEY_DELETE, .repeatAction = &gui.textCallbacks.deleteRight},
		.{.name = "textCopy", .key = c.GLFW_KEY_C, .repeatAction = &gui.textCallbacks.copy},
		.{.name = "textPaste", .key = c.GLFW_KEY_V, .repeatAction = &gui.textCallbacks.paste},
		.{.name = "textCut", .key = c.GLFW_KEY_X, .repeatAction = &gui.textCallbacks.cut},
		.{.name = "textNewline", .key = c.GLFW_KEY_ENTER, .repeatAction = &gui.textCallbacks.newline},

		// debug:
		.{.name = "debugOverlay", .key = c.GLFW_KEY_F3, .releaseAction = &toggleDebugOverlay},
		.{.name = "performanceOverlay", .key = c.GLFW_KEY_F4, .releaseAction = &togglePerformanceOverlay},
		.{.name = "gpuPerformanceOverlay", .key = c.GLFW_KEY_F5, .releaseAction = &toggleGPUPerformanceOverlay},
		.{.name = "networkDebugOverlay", .key = c.GLFW_KEY_F6, .releaseAction = &toggleNetworkDebugOverlay},
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

	const c = Window.c;

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
		if(settings.developerGPUInfiniteLoopDetection and deltaTime > 5) { // On linux a process that runs 10 seconds or longer on the GPU will get stopped. This allows detecting an infinite loop on the GPU.
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

	if(game.world) |world| {
		world.deinit();
		game.world = null;
	}
}

test "abc" {
	_ = @import("json.zig");
}
