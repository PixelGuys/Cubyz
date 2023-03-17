const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

var components: [1]GuiComponent = undefined;
pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:multiplayer",
	.title = "Multiplayer",
	.onOpenFn = &onOpen,
	.onCloseFn = &onClose,
	.components = &components,
};

const padding: f32 = 8;

var connection: ?*ConnectionManager = null;
var ipAddress: []const u8 = "";
var thread: ?std.Thread = null;
const width: f32 = 420;

fn flawedDiscoverIpAddress() !void {
	connection = try ConnectionManager.init(12347, true); // TODO: default port
	ipAddress = try std.fmt.allocPrint(main.globalAllocator, "{}", .{connection.?.externalAddress});
	components[0].impl.verticalList.children.items[1].impl.label.deinit();
	const labelComponent = try Label.init(undefined, width, ipAddress, .center);
	components[0].impl.verticalList.children.items[1].impl.label = labelComponent.impl.label;
}

fn discoverIpAddress() void {
	flawedDiscoverIpAddress() catch |err| {
		std.log.err("Encountered error {s} while discovering the ip address for multiplayer.", .{@errorName(err)});
	};
}

fn discoverIpAddressFromNewThread() void {
	var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
	main.threadAllocator = gpa.allocator();
	defer if(gpa.deinit()) {
		@panic("Memory leak");
	};

	discoverIpAddress();
}

fn join() void {
	if(thread) |_thread| {
		_thread.join();
		thread = null;
	}
	if(ipAddress.len != 0) {
		main.globalAllocator.free(ipAddress);
		ipAddress = "";
	}
	if(connection) |_connection| {
		_connection.world = &main.game.testWorld;
		main.game.testWorld.init(settings.lastUsedIPAddress, _connection) catch |err| {
			std.log.err("Encountered error while opening world: {s}", .{@errorName(err)});
		};
		main.game.world = &main.game.testWorld;
		connection = null;
	} else {
		std.log.err("No connection found. Cannot connect.", .{});
	}
	for(gui.openWindows.items) |openWindow| {
		gui.closeWindow(openWindow);
	}
}

fn copyIp() void {
	main.Window.setClipboardString(ipAddress);
}

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init();
	try list.add(try Label.init(.{0, 16}, width, "Please send your IP to the host of the game and enter the host's IP below.", .center));
	//                                            255.255.255.255:?65536 (longest possible ip address)
	try list.add(try Label.init(.{0, 16}, width, "                      ", .center));
	try list.add(try Button.init(.{0, 16}, 100, "Copy IP", &copyIp));
	try list.add(try TextInput.init(.{0, 16}, width, 32, settings.lastUsedIPAddress));
	try list.add(try Button.init(.{0, 16}, 100, "Join", &join));
	components[0] = list.toComponent(.{padding, padding});
	window.contentSize = components[0].size + @splat(2, @as(f32, 2*padding));
	gui.updateWindowPositions();

	thread = std.Thread.spawn(.{}, discoverIpAddressFromNewThread, .{}) catch |err| blk: {
		std.log.err("Error spawning thread: {s}. Doing it in the current thread instead.", .{@errorName(err)});
		discoverIpAddress();
		break :blk null;
	};
}

pub fn onClose() void {
	if(thread) |_thread| {
		_thread.join();
		thread = null;
	}
	if(connection) |_connection| {
		_connection.deinit();
		connection = null;
	}
	if(ipAddress.len != 0) {
		main.globalAllocator.free(ipAddress);
		ipAddress = "";
	}

	for(&components) |*comp| {
		comp.deinit();
	}
}