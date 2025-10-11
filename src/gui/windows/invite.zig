const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

var ipAddressLabel: *Label = undefined;
var ipAddressEntry: *TextInput = undefined;
var ipObfuscated: bool = true;

const padding: f32 = 8;

var ipAddress: []const u8 = "";
var gotIpAddress: std.atomic.Value(bool) = .init(false);
var thread: ?std.Thread = null;
const width: f32 = 420;

fn discoverIpAddress() void {
	main.server.connectionManager.makeOnline();
	ipAddress = std.fmt.allocPrint(main.globalAllocator.allocator, "{f}", .{main.server.connectionManager.externalAddress}) catch unreachable;
	gotIpAddress.store(true, .release);
}

fn discoverIpAddressFromNewThread() void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	discoverIpAddress();
}

fn invite(_: usize) void {
	if(thread) |_thread| {
		_thread.join();
		thread = null;
	}
	const user = main.server.User.initAndIncreaseRefCount(main.server.connectionManager, ipAddressEntry.currentString.items) catch |err| {
		if(err != error.AlreadyConnected) {
			std.log.err("Cannot connect user: {s}", .{@errorName(err)});
		}
		return;
	};
	user.decreaseRefCount();
}

fn copyIp(_: usize) void {
	main.Window.setClipboardString(ipAddress);
}

fn revealIp(_: usize) void {
	ipObfuscated = false;
	ipAddressLabel.updateText(ipAddress);
	ipAddressEntry.obfuscated = ipObfuscated;
	ipAddressEntry.updateObfuscation();
}

fn makePublic(public: bool) void {
	main.server.connectionManager.allowNewConnections.store(public, .monotonic);
}

pub fn onOpen() void {
	ipObfuscated = settings.streamerModeEnabled;
	const list = VerticalList.init(.{padding, 16 + padding}, 260, 16);
	list.add(Label.init(.{0, 0}, width, "Please send your IP to the player who wants to join and enter their IP below.", .center));
	ipAddressLabel = Label.init(.{0, 0}, width, "", .center);
	list.add(ipAddressLabel);
	const buttonRow = HorizontalList.init();
	buttonRow.add(Button.initText(.{0, 0}, 100, "Reveal", .{.callback = &revealIp}));
	buttonRow.add(Button.initText(.{0, 0}, 100, "Copy IP", .{.callback = &copyIp}));
	buttonRow.finish(.{0, 0}, .left);
	list.add(buttonRow);
	ipAddressEntry = TextInput.init(.{0, 0}, width, 32, settings.lastUsedIPAddress, .{.callback = &invite}, .{});
	ipAddressEntry.obfuscated = ipObfuscated;
	list.add(ipAddressEntry);
	list.add(Button.initText(.{0, 0}, 100, "Invite", .{.callback = &invite}));
	list.add(Button.initText(.{0, 0}, 100, "Manage Players", gui.openWindowCallback("manage_players")));
	list.add(CheckBox.init(.{0, 0}, width, "Allow anyone to join (requires a publicly visible IP address+port which may need some configuration in your router)", main.server.connectionManager.allowNewConnections.load(.monotonic), &makePublic));
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
		if(ipObfuscated) {
			var obfuscatedText = main.List(u8).init(main.globalAllocator);
			defer obfuscatedText.deinit();
			var i: usize = 0;
			while(i < ipAddress.len) : (i += 1) {
				obfuscatedText.appendSlice("•"); // \u2022
			}
			ipAddressLabel.updateText(obfuscatedText.items);
		} else {
			ipAddressLabel.updateText(ipAddress);
		}
	}
}
