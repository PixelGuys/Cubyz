const std = @import("std");

const main = @import("main");
const Player = main.game.Player;
const items = main.items;
const ItemStack = items.ItemStack;
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

var itemSlots: []*ItemSlot = undefined;

pub fn init() void {
}

pub fn deinit() void {
}


pub fn onOpen() void {
	itemSlots = main.globalAllocator.alloc(*ItemSlot, items.accessory_slots.getTotalSlotCount());

	const accessories = main.entity.components.@"cubyz:accessories".client.getAccessories(Player.super.id) orelse return;
	const list = VerticalList.init(.{padding, padding + 16}, 300, 0);
	var index: u32 = 0;
	for (items.accessory_slots.getAccessorySlots()) |accessorySlot| {
		const row = HorizontalList.init();
		for (0..accessorySlot.count) |_| {
			const slot = ItemSlot.init(.{0, 0}, accessories.*, @intCast(index), .default, .normal);
			itemSlots[index] = slot;
			row.add(slot);
			index += 1;
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
	main.globalAllocator.free(itemSlots);
}
