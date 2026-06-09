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
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{64*8, 64*4},
	.scale = 0.75,
};

const padding: f32 = 8;
const numRows = 4;

var itemSlots: []*ItemSlot = undefined;

pub fn init() void {}

pub fn deinit() void {}

pub fn onOpen() void {
	itemSlots = main.globalAllocator.alloc(*ItemSlot, items.accessory_slots.getTotalSlotCount());

	const accessories = main.entity.components.@"cubyz:accessories".client.getAccessories(Player.super.id) orelse return;
	const list = HorizontalList.init();
	var currentColumn = VerticalList.init(.{0, 0}, 300, 0);
	var index: u32 = 0;
	var columnList = main.utils.list.ListUnmanaged(*VerticalList).initCapacity(main.stackAllocator, items.accessory_slots.getTotalSlotCount()/numRows);
	defer columnList.deinit(main.stackAllocator);
	for (items.accessory_slots.getAccessorySlots()) |*accessorySlot| {
		for (0..accessorySlot.count) |_| {
			const slot = ItemSlot.init(.{0, 0}, accessories.*, @intCast(index), if (accessorySlot.getTexture()) |texture| .{.custom = texture} else .default, .normal);
			itemSlots[index] = slot;
			currentColumn.add(slot);
			if (currentColumn.children.items.len == numRows) {
				columnList.append(main.stackAllocator, currentColumn);
				currentColumn = VerticalList.init(.{0, 0}, 300, 0);
			}
			index += 1;
		}
	}
	if (currentColumn.children.items.len > 0) {
		columnList.append(main.stackAllocator, currentColumn);
	} else {
		currentColumn.deinit();
	}
	var iterator = std.mem.reverseIterator(columnList.items);
	while (iterator.next()) |column| {
		list.add(column);
	}
	list.finish(.{padding, padding + 16}, .right);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	window.contentSize[0] = @max(window.contentSize[0], window.getMinWindowWidth());
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
	main.globalAllocator.free(itemSlots);
}
