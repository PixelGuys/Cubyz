const std = @import("std");

const main = @import("main");
const ConnectionManager = main.network.ConnectionManager;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;
const TextInput = GuiComponent.TextInput;
const VerticalList = GuiComponent.VerticalList;
const HorizontalList = GuiComponent.HorizontalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;
var userList: []*main.server.User = &.{};

fn kick(conn: *main.network.Connection) void {
	conn.disconnect();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	{
		main.server.connectionManager.mutex.lock();
		defer main.server.connectionManager.mutex.unlock();
		std.debug.assert(userList.len == 0);
		userList = main.globalAllocator.alloc(*main.server.User, main.server.connectionManager.connections.items.len);
		for(main.server.connectionManager.connections.items, 0..) |connection, i| {
			userList[i] = connection.user.?;
			userList[i].increaseRefCount();
			const row = HorizontalList.init();
			if(connection.user.?.name.len != 0) {
				row.add(Label.init(.{0, 0}, 200, connection.user.?.name, .left));
				row.add(Button.initText(.{0, 0}, 100, "Kick", .{.callback = @ptrCast(&kick), .arg = @intFromPtr(connection)}));
			} else {
				const ip = std.fmt.allocPrint(main.stackAllocator.allocator, "{}", .{connection.remoteAddress}) catch unreachable;
				defer main.stackAllocator.free(ip);
				row.add(Label.init(.{0, 0}, 200, ip, .left));
				row.add(Button.initText(.{0, 0}, 100, "Cancel", .{.callback = @ptrCast(&kick), .arg = @intFromPtr(connection)}));
			}
			list.add(row);
		}
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(userList) |user| {
		user.decreaseRefCount();
	}
	main.globalAllocator.free(userList);
	userList = &.{};
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	main.server.connectionManager.mutex.lock();
	const serverListLen = main.server.connectionManager.connections.items.len;
	main.server.connectionManager.mutex.unlock();
	if(userList.len != serverListLen) {
		onClose();
		onOpen();
	}
}
