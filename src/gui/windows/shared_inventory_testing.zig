const std = @import("std");

const main = @import("main");
const items = main.items;
const BaseItem = items.BaseItem;
const Inventory = items.Inventory;
const Item = items.Item;
const Tool = items.Tool;
const Player = main.game.Player;
const Texture = main.graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const Icon = GuiComponent.Icon;
const ItemSlot = GuiComponent.ItemSlot;

const inventory = @import("inventory.zig");
const inventory_crafting = @import("inventory_crafting.zig");

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{32*7, 32*7},
	.scale = 0.75,
};

const padding: f32 = 8;

var inv: Inventory = undefined;

pub fn onOpen() void {
	inv = Inventory.init(main.globalAllocator, 49, .normal, .sharedTestingInventory);
	const list = VerticalList.init(.{padding, padding + 16}, 128, 0);
	var i: u32 = 0;
	for(0..7) |_| {
		const row = HorizontalList.init();
		for(0..7) |_| {
			if(i >= inv.size()) break;
			row.add(ItemSlot.init(.{0, 0}, inv, i, .default, .normal));
			i += 1;
		}
		list.add(row);
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	inv.deinit(main.globalAllocator);
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
}
