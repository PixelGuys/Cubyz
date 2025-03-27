const std = @import("std");

const main = @import("main");
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

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

var ipAddressLabel: *Label = undefined;
var ipAddressEntry: *TextInput = undefined;

const padding: f32 = 8;

var connection: ?*ConnectionManager = null;
var ipAddress: []const u8 = "";
var gotIpAddress: std.atomic.Value(bool) = .init(false);
var thread: ?std.Thread = null;
const width: f32 = 420;

fn discoverIpAddress() void {
	connection = ConnectionManager.init(main.settings.defaultPort, true) catch |err| {
		std.log.err("Could not open Connection: {s}", .{@errorName(err)});
		ipAddress = main.globalAllocator.dupe(u8, @errorName(err));
		return;
	};
	ipAddress = std.fmt.allocPrint(main.globalAllocator.allocator, "{}", .{connection.?.externalAddress}) catch unreachable;
	gotIpAddress.store(true, .release);
}

fn discoverIpAddressFromNewThread() void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	discoverIpAddress();
}

fn join(_: usize) void {
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
		main.game.world = &main.game.testWorld;
		std.log.info("Connecting to server: {s}", .{ipAddressEntry.currentString.items});
		main.game.testWorld.init(ipAddressEntry.currentString.items, _connection) catch |err| {
			const formattedError = std.fmt.allocPrint(main.stackAllocator.allocator, "Encountered error while opening world: {s}", .{@errorName(err)}) catch unreachable;
			defer main.stackAllocator.free(formattedError);
			std.log.err("{s}", .{formattedError});
			main.gui.windowlist.notification.raiseNotification(formattedError);
			main.game.world = null;
			_connection.world = null;
			return;
		};
		main.globalAllocator.free(settings.lastUsedIPAddress);
		settings.lastUsedIPAddress = main.globalAllocator.dupe(u8, ipAddressEntry.currentString.items);
		settings.save();
		connection = null;
	} else {
		std.log.err("No connection found. Cannot connect.", .{});
		main.gui.windowlist.notification.raiseNotification("No connection found. Cannot connect.");
	}
	for(gui.openWindows.items) |openWindow| {
		gui.closeWindowFromRef(openWindow);
	}
	gui.openHud();
}

fn copyIp(_: usize) void {
	main.Window.setClipboardString(ipAddress);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, "Please send your IP to the host of the game and enter the host's IP below.", .center));
	//                                               255.255.255.255:?65536 (longest possible ip address)
	ipAddressLabel = Label.init(.{0, 0}, width, "                      ", .center);
	list.add(ipAddressLabel);
	list.add(Button.initText(.{0, 0}, 100, "Copy IP", .{.callback = &copyIp}));
	ipAddressEntry = TextInput.init(.{0, 0}, width, 32, settings.lastUsedIPAddress, .{.callback = &join});
	list.add(ipAddressEntry);
	list.add(Button.initText(.{0, 0}, 100, "Join", .{.callback = &join}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
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

	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	if(gotIpAddress.load(.acquire)) {
		gotIpAddress.store(false, .monotonic);
		ipAddressLabel.updateText(ipAddress);
	}
}
