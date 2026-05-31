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
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;
var userList: []*main.server.User = &.{};
var entityCount: usize = 0;

fn kickbyConnection(conn: *main.network.Connection) void {
	conn.disconnect();
}

fn kickByPlayerIndex(playerIndex: usize) void {
	const command = std.fmt.allocPrint(main.globalAllocator.allocator, "kick @{d}", .{playerIndex}) catch unreachable;
	main.sync.client.executeCommand(.{.chatCommand = .{.message = command}});
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	if (main.server.world == null) blk: {
		entityCount = main.client.entity_manager.entities.len;
		if (entityCount == 0) {
			list.add(Label.init(.{0, 0}, 200, "No other players", .left));
			break :blk;
		}

		for (main.client.entity_manager.entities.items()) |ent| {
			if (ent.playerIndex == null) continue;
			const row = HorizontalList.init();

			const string = std.fmt.allocPrint(main.stackAllocator.allocator, "{f}", .{std.fmt.alt(ent, .formatWithPlayerIndex)}) catch unreachable;
			defer main.stackAllocator.free(string);
			row.add(Label.init(.{0, 0}, 200, string, .left));
			row.add(Button.initText(.{0, 0}, 100, "Kick", .initWithInt(kickByPlayerIndex, ent.playerIndex.?)));
			list.add(row);
		}
	} else {
		main.server.connectionManager.mutex.lock();
		defer main.server.connectionManager.mutex.unlock();
		std.debug.assert(userList.len == 0);
		userList = main.globalAllocator.alloc(*main.server.User, main.server.connectionManager.connections.items.len);
		for (main.server.connectionManager.connections.items, 0..) |connection, i| {
			userList[i] = connection.user.?;
			userList[i].increaseRefCount();
			if (userList[i].id == main.game.Player.id and connection.isConnected()) continue;
			const row = HorizontalList.init();
			if (connection.handShakeState.load(.monotonic) == .complete) {
				const string = std.fmt.allocPrint(main.stackAllocator.allocator, "{f}", .{connection.user.?}) catch unreachable;
				defer main.stackAllocator.free(string);
				row.add(Label.init(.{0, 0}, 200, string, .left));
				row.add(Button.initText(.{0, 0}, 100, "Kick", .initWithPtr(kickbyConnection, connection)));
			} else {
				const ip = std.fmt.allocPrint(main.stackAllocator.allocator, "{f}", .{connection.remoteAddress}) catch unreachable;
				defer main.stackAllocator.free(ip);
				row.add(Label.init(.{0, 0}, 200, ip, .left));
				row.add(Button.initText(.{0, 0}, 100, "Cancel", .initWithPtr(kickbyConnection, connection)));
			}
			list.add(row);
		}
		if (userList.len == 1) {
			list.add(Label.init(.{0, 0}, 200, "No other players", .left));
		}
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (main.server.world != null) {
		for (userList) |user| {
			user.decreaseRefCount();
		}
		main.globalAllocator.free(userList);
		userList = &.{};
	}
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	if (main.server.world == null) {
		if (main.client.entity_manager.entities.len != entityCount) {
			onClose();
			onOpen();
		}
	} else {
		main.server.connectionManager.mutex.lock();
		const serverListLen = main.server.connectionManager.connections.items.len;
		main.server.connectionManager.mutex.unlock();
		if (userList.len != serverListLen) {
			onClose();
			onOpen();
		}
	}
}
