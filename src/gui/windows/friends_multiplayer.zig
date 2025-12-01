const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const width: f32 = 490;
const padding: f32 = 8;

const maxIpLength = 24; // 255.255.255.255:?65536 (longest possible ip address)
const ipPlaceholder = &[_]u8{' '} ** maxIpLength;

var connection: ?*ConnectionManager = null;
var ipAddress: []const u8 = "";
var ipAddressLabel: *Label = undefined;
var ipAddressEntry: *TextInput = undefined;
var gotIpAddress: std.atomic.Value(bool) = .init(false);
var thread: ?std.Thread = null;

var joinButton: *Button = undefined;

fn discoverIpAddress() void {
	connection = ConnectionManager.init(main.settings.defaultPort, true) catch |err| {
		std.log.err("Could not initialize connection: {s}", .{@errorName(err)});
		ipAddress = main.globalAllocator.dupe(u8, @errorName(err));
		return;
	};
	ipAddress = std.fmt.allocPrint(main.globalAllocator.allocator, "{f}", .{connection.?.externalAddress}) catch unreachable;
	gotIpAddress.store(true, .release);
}

fn discoverIpAddressFromNewThread() void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	discoverIpAddress();
}

fn changeIpVisibility(hide: bool) void {
	if(hide) {
		// assume that IP address is always encoded as ASCII,
		// so length of the address is equals to the number of utf-8 characters
		ipAddressLabel.updateText(TextInput.obfuscatedStringBuffer[0 .. ipAddress.len*TextInput.obfuscationChar.len]);
		ipAddressEntry.obfuscate();
	} else {
		ipAddressLabel.updateText(ipAddress);
		ipAddressEntry.deobfuscate();
	}

	settings.hideIpAddresses = hide;
	settings.save();
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
		const address = ipAddressEntry.currentString.items;
		connection = null;

		if(main.game.join(address, _connection)) {
			main.globalAllocator.free(settings.lastUsedIPAddress);
			settings.lastUsedIPAddress = main.globalAllocator.dupe(u8, address);
			settings.save();
		} else {
			connection = _connection;
		}
	} else {
		std.log.err("No connection found. Cannot connect.", .{});
		main.gui.windowlist.notification.raiseNotification("No connection found. Cannot connect.");
	}
}

fn copyIp(_: usize) void {
	main.Window.setClipboardString(ipAddress);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, "Please send your IP to the host of the game and enter the host's IP below.", .center));
	list.add(CheckBox.init(.{0, 0}, width/2 + padding + 100, "Hide IP addresses", settings.hideIpAddresses, &changeIpVisibility));
	const ipBar = HorizontalList.init();
	ipAddressLabel = Label.init(.{padding/3, 0}, width/2 - padding/3, ipPlaceholder, .left);
	ipBar.add(ipAddressLabel);
	ipBar.add(Button.initText(.{padding, 0}, 100, "Copy IP", .{.callback = &copyIp}));
	ipBar.finish(.{0, 0}, .center);

	const inputBar = HorizontalList.init();
	ipAddressEntry = TextInput.init(.{0, 0}, width/2, 24, settings.lastUsedIPAddress, .{.callback = &join}, .{});
	inputBar.add(ipAddressEntry);
	joinButton = Button.initText(.{padding, 0}, 100, "Join", .{.callback = &join});
	inputBar.add(joinButton);
	inputBar.finish(.{0, 0}, .center);

	list.add(ipBar);
	list.add(inputBar);
	list.finish(.center);

	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();

	changeIpVisibility(settings.hideIpAddresses);

	if(thread == null) {
		thread = std.Thread.spawn(.{}, discoverIpAddressFromNewThread, .{}) catch |err| blk: {
			std.log.err("Error spawning thread: {s}. Doing it in the current thread instead.", .{@errorName(err)});
			discoverIpAddress();
			break :blk null;
		};
	}
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
	if(connection) |_connection| {
		_connection.deinit();
		connection = null;
	}
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	if(gotIpAddress.load(.acquire)) {
		gotIpAddress.store(false, .monotonic);

		if(settings.hideIpAddresses) {
			// assume that IP address is always encoded as ASCII,
			// so length of the address is equals to the number of utf-8 characters
			ipAddressLabel.updateText(TextInput.obfuscatedStringBuffer[0 .. ipAddress.len*TextInput.obfuscationChar.len]);
		} else {
			ipAddressLabel.updateText(ipAddress);
		}
	}

	const input = ipAddressEntry.currentString.items;
	joinButton.disabled = input.len == 0 or std.mem.indexOfAny(u8, input, " \n\r\t<>!@#$%^&*(){}=+/*~,;\"\'\\") != null;
}
