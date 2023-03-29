const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Player = main.game.Player;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const HorizontalList = GuiComponent.HorizontalList;
const ItemSlot = GuiComponent.ItemSlot;

pub var window = GuiWindow {
	.contentSize = Vec2f{64*8, 64},
	.title = "Hotbar",
	.id = "cubyz:hotbar",
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
};

pub fn onOpen() Allocator.Error!void {
	var list = try HorizontalList.init();
	for(0..8) |i| {
		try list.add(try ItemSlot.init(.{0, 0}, &Player.inventory__SEND_CHANGES_TO_SERVER.items[i]));
	}
	list.finish(.{0, 0}, .center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.size();
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}