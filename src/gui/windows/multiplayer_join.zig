const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

var nameEntry: *TextInput = undefined;
var ipAddressLabel: *Label = undefined;
var ipAddressEntry: *TextInput = undefined;

const padding: f32 = 8;

var connection: ?*ConnectionManager = null;
var ipAddress: []const u8 = "";
var gotIpAddress: std.atomic.Value(bool) = .init(false);
var thread: ?std.Thread = null;
const width: f32 = 420;

fn discoverIpAddress() void {
	connection = ConnectionManager.init(main.settings.defaultPort, .{}) catch |err| {
		std.log.err("Could not open Connection: {s}", .{@errorName(err)});
		ipAddress = main.globalAllocator.dupe(u8, @errorName(err));
		return;
	};
	connection.?.makeOnline();
	ipAddress = main.globalAllocator.print("{f}", .{connection.?.externalAddress});
	gotIpAddress.store(true, .release);
}

fn discoverIpAddressFromNewThread() void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	discoverIpAddress();
}

fn applyName() void {
	if (nameEntry.currentString.items.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(nameEntry.currentString.items) > 50) {
		std.log.err("Name is too long with {}/{} characters. Limits are 50/500", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(nameEntry.currentString.items), nameEntry.currentString.items.len});
		return;
	}
	if (std.mem.eql(u8, nameEntry.currentString.items, settings.playerName)) return;
	main.globalAllocator.free(settings.playerName);
	settings.playerName = main.globalAllocator.dupe(u8, nameEntry.currentString.items);
	settings.save();
}

fn join() void {
	applyName();
	if (thread) |_thread| {
		_thread.join();
		thread = null;
	}
	if (ipAddress.len != 0) {
		main.globalAllocator.free(ipAddress);
		ipAddress = "";
	}
	if (connection) |_connection| {
		std.log.info("Connecting to server: {s}", .{ipAddressEntry.currentString.items});
		gui.windowlist.connecting.start(ipAddressEntry.currentString.items, _connection);
		connection = null;
	} else {
		std.log.err("No connection found. Cannot connect.", .{});
		main.gui.windowlist.notification.raiseNotification("No connection found. Cannot connect.", .{});
	}
}

pub fn restoreConnection(manager: *ConnectionManager) void {
	connection = manager;
}

fn copyIp() void {
	main.Window.setClipboardString(ipAddress);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, "Please send your IP to the host of the game and enter the host's IP below.", .center));
	//                                               255.255.255.255:?65536 (longest possible ip address)
	ipAddressLabel = Label.init(.{0, 0}, width, "                      ", .center);
	list.add(ipAddressLabel);
	list.add(Button.initText(.{0, 0}, 100, "Copy IP", .{.onAction = .init(copyIp)}));
	ipAddressEntry = TextInput.init(.{0, 0}, width, 32, settings.lastUsedIPAddress, .{.onNewline = .init(join)});
	ipAddressEntry.obfuscated = main.settings.streamerMode;
	list.add(ipAddressEntry);
	const nameLabel = Label.init(.{0, 0}, 48, "Name:", .left);
	nameEntry = TextInput.init(.{0, 0}, width - 48, 32, settings.playerName, .{.onNewline = .init(applyName)});
	const nameRow = HorizontalList.init();
	nameRow.add(nameLabel);
	nameRow.add(nameEntry);
	nameRow.finish(.{0, 0}, .center);
	list.add(nameRow);
	list.add(Button.initText(.{0, 0}, 100, "Join", .{.onAction = .init(join)}));
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
	if (thread) |_thread| {
		_thread.join();
		thread = null;
	}
	if (connection) |_connection| {
		_connection.deinit();
		connection = null;
	}
	if (ipAddress.len != 0) {
		main.globalAllocator.free(ipAddress);
		ipAddress = "";
	}

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	if (gotIpAddress.load(.acquire)) {
		gotIpAddress.store(false, .monotonic);

		if (main.settings.streamerMode) {
			const obfuscatedIp = main.utils.obfuscateString(main.stackAllocator, ipAddress);
			defer main.stackAllocator.free(obfuscatedIp);
			ipAddressLabel.updateText(obfuscatedIp);
		} else {
			ipAddressLabel.updateText(ipAddress);
		}
	}
}
