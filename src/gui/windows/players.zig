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
var entityCount: u32 = 0;

fn kickPerConn(conn: *main.network.Connection) void {
	conn.disconnect();
}

fn kickPerIndex(playerIndex: usize) void {
	const command = std.fmt.allocPrint(main.globalAllocator.allocator, "kick @{d}", .{playerIndex}) catch unreachable;
	main.sync.ClientSide.executeCommand(.{.chatCommand = .{.message = command}});
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	blk: {
		entityCount = main.client.entity_manager.entities.len;
		if (entityCount == 0) {
			list.add(Label.init(.{0, 0}, 200, "No other players", .left));
			break :blk;
		}

		for (main.client.entity_manager.entities.items()) |ent| {
			if (ent.name.len == 0 or ent.playerIndex == null) continue;
			const row = HorizontalList.init();

			const string = std.fmt.allocPrint(main.stackAllocator.allocator, "{f}", .{std.fmt.alt(ent, .formatWithPlayerIndex)}) catch unreachable;
			defer main.stackAllocator.free(string);
			row.add(Label.init(.{0, 0}, 200, string, .left));
			row.add(Button.initText(.{0, 0}, 100, "Kick", .initWithInt(kickPerIndex, ent.playerIndex.?)));
			list.add(row);
		}
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	if (main.client.entity_manager.entities.len != entityCount) {
		onClose();
		onOpen();
	}
}
