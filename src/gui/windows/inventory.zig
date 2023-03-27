const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Player = main.game.Player;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const ItemSlot = GuiComponent.ItemSlot;

var components: [1]GuiComponent = undefined;
pub var window = GuiWindow {
	.contentSize = Vec2f{64*8, 64*4},
	.title = "Inventory",
	.id = "cubyz:inventory",
	.components = &components,
};

const padding: f32 = 8;

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, padding + 16}, 300, 0);
	// TODO: Crafting.
	// Inventory:
	for(1..4) |y| {
		var row = try HorizontalList.init();
		for(0..8) |x| {
			try row.add(try ItemSlot.init(.{0, 0}, &Player.inventory__SEND_CHANGES_TO_SERVER.items[y*8 + x]));
		}
		try list.add(row);
	}
	list.finish(.center);
	components[0] = list.toComponent();
	window.contentSize = components[0].pos() + components[0].size() + @splat(2, padding);
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(&components) |*comp| {
		comp.deinit();
	}
}