const std = @import("std");

const main = @import("main");
const Player = main.game.Player;
const ItemStack = main.items.ItemStack;
const Vec2f = main.vec.Vec2f;
const Texture = main.graphics.Texture;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const ItemSlot = GuiComponent.ItemSlot;

const inventory = @import("inventory.zig");

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
	.contentSize = Vec2f{64*8, 64*4},
	.scale = 0.75,
};

const padding: f32 = 8;

var itemSlots: [20]*ItemSlot = undefined;

pub fn init() void {
}

pub fn deinit() void {
}


pub fn onOpen() void {
	const list = VerticalList.init(.{padding, padding + 16}, 300, 0);
	// Some miscellanious slots and buttons:
	// TODO: armor slots, backpack slot + stack-based backpack inventory, other items maybe?
	{
		const row = HorizontalList.init();
		blk: {
			row.add(GuiComponent.BagSlot.init(.{0, 0}, main.entity.components.@"cubyz:bag".client.getBag(main.game.Player.id) orelse break :blk));
		}
		row.add(Button.initIcon(.{32, 0}, .{32, 32}, craftingIcon, true, gui.openWindowCallback("inventory_crafting")));
		list.add(row);
	}
	for (0..2) |y| {
		const row = HorizontalList.init();
		for (0..10) |x| {
			const index: usize = 12 + y*10 + x;
			const slot = ItemSlot.init(.{0, 0}, Player.inventory, @intCast(index), .default, .normal);
			itemSlots[index - 12] = slot;
			row.add(slot);
		}
		list.add(row);
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
