const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 64},
	.hasBackground = true,
	.closeable = false,
};

const padding: f32 = 8;
const width: f32 = 280;

const State = enum(u8) { connecting, connected, failed, cancelled };

var connectionManager: ?*ConnectionManager = null;
var ip: []const u8 = "";
var connectFuture: ?std.Io.Future(void) = null;
var handshakeZon: main.ZonElement = undefined;
var state: std.atomic.Value(State) = .init(.connecting);
var errorMessage: []const u8 = "";
var statusLabel: *Label = undefined;

fn connectFromNewThread() void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	handshakeZon = main.game.testWorld.init(ip, connectionManager.?) catch |err| {
		if (err == error.Canceled) {
			state.store(.cancelled, .release);
		} else {
			errorMessage = @errorName(err);
			state.store(.failed, .release);
		}
		return;
	};
	state.store(.connected, .release);
}

pub fn start(_ip: []const u8, manager: *ConnectionManager) void {
	ip = main.globalAllocator.dupe(u8, _ip);
	connectionManager = manager;
	state = .init(.connecting);
	gui.openModalWindow("connecting");
	connectFuture = main.io.concurrent(connectFromNewThread, .{}) catch |err| blk: {
		std.log.err("Error spawning connect task: {s}. Doing it in the current thread instead.", .{@errorName(err)});
		connectFromNewThread();
		break :blk null;
	};
}

fn cancel() void {
	if (connectFuture) |*future| {
		_ = future.cancel(main.io);
		connectFuture = null;
	}
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, width, 16);
	statusLabel = Label.init(.{0, 0}, width, "Connecting...", .center);
	list.add(statusLabel);
	list.add(Button.initText(.{0, 0}, 100, "Cancel", .{.onAction = .init(cancel)}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	std.debug.assert(connectFuture == null);
	if (ip.len != 0) {
		main.globalAllocator.free(ip);
		ip = "";
	}
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	stateSwitch: switch (state.load(.acquire)) {
		.connecting => {},
		.connected => {
			if (connectFuture) |*future| {
				_ = future.await(main.io);
				connectFuture = null;
			}
			main.game.testWorld.finishHandshake(handshakeZon) catch |err| {
				errorMessage = @errorName(err);
				state.store(.failed, .release);
				continue :stateSwitch .failed;
			};
			connectionManager.?.world = &main.game.testWorld;
			gui.closeWindowFromRef(&window);
			main.game.world = &main.game.testWorld;
			main.globalAllocator.free(settings.lastUsedIPAddress);
			settings.lastUsedIPAddress = main.globalAllocator.dupe(u8, ip);
			settings.save();
			for (gui.openWindows.items) |openWindow| {
				gui.closeWindowFromRef(openWindow);
			}
			gui.openHud();
		},
		.failed => {
			if (connectFuture) |*future| {
				_ = future.await(main.io);
				connectFuture = null;
			}
			gui.closeWindowFromRef(&window);
			gui.windowlist.multiplayer_join.restoreConnection(connectionManager.?);
			main.gui.windowlist.notification.raiseNotification("Encountered error while opening world: {s}", .{errorMessage});
			errorMessage = "";
		},
		.cancelled => {
			gui.closeWindowFromRef(&window);
			gui.windowlist.multiplayer_join.restoreConnection(connectionManager.?);
		},
	}
}
