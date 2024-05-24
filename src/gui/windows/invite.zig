const std = @import("std");

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

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
};

var ipAddressLabel: *Label = undefined;
var ipAddressEntry: *TextInput = undefined;

const padding: f32 = 8;

var ipAddress: []const u8 = "";
var gotIpAddress: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var thread: ?std.Thread = null;
const width: f32 = 420;

fn discoverIpAddress() void {
	main.server.connectionManager.makeOnline();
	ipAddress = std.fmt.allocPrint(main.globalAllocator.allocator, "{}", .{main.server.connectionManager.externalAddress}) catch unreachable;
	gotIpAddress.store(true, .release);
}

fn discoverIpAddressFromNewThread() void {
	var sta = main.utils.StackAllocator.init(main.globalAllocator, 1 << 23);
	defer sta.deinit();
	main.stackAllocator = sta.allocator();

	discoverIpAddress();
}

fn invite(_: usize) void {
	if(thread) |_thread| {
		_thread.join();
		thread = null;
	}
	_ = main.server.User.init(main.server.connectionManager, ipAddressEntry.currentString.items) catch |err| {
		std.log.err("Cannot connect user: {s}", .{@errorName(err)});
	};
}

fn copyIp(_: usize) void {
	main.Window.setClipboardString(ipAddress);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, "Please send your IP to the player who wants to join and enter their IP below.", .center));
	//                                           255.255.255.255:?65536 (longest possible ip address)
	ipAddressLabel = Label.init(.{0, 0}, width, "                      ", .center);
	list.add(ipAddressLabel);
	list.add(Button.initText(.{0, 0}, 100, "Copy IP", .{.callback = &copyIp}));
	ipAddressEntry = TextInput.init(.{0, 0}, width, 32, settings.lastUsedIPAddress, .{.callback = &invite});
	list.add(ipAddressEntry);
	list.add(Button.initText(.{0, 0}, 100, "Invite", .{.callback = &invite}));
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