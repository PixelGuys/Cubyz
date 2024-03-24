const std = @import("std");

const main = @import("root");
const Item = main.items.Item;
const ItemStack = main.items.ItemStack;
const Player = main.game.Player;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const ItemSlot = GuiComponent.ItemSlot;

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
	},
	.contentSize = Vec2f{64*8, 64*4},
};

const padding: f32 = 8;
var items: main.List(Item) = undefined;

pub fn tryTakingItems(index: usize, destination: *ItemStack, _: u16) void {
	trySwappingItems(index, destination);
}
pub fn trySwappingItems(index: usize, destination: *ItemStack) void {
	destination.clear(); // Always replace the destination.
	destination.item = items.items[index];
	destination.amount = destination.item.?.stackSize();
}

pub fn onOpen() void {
	items = main.List(Item).init(main.globalAllocator);
	var itemIterator = main.items.iterator();
	while(itemIterator.next()) |item| {
		items.append(Item{.baseItem = item.*});
	}

	const list = VerticalList.init(.{padding, padding + 16}, 140, 0);
	var i: u32 = 0;
	while(i < items.items.len) {
		const row = HorizontalList.init();
		for(0..8) |_| {
			if(i >= items.items.len) break;
			const item = items.items[i];
			row.add(ItemSlot.init(.{0, 0}, .{.item = item, .amount = 1}, &.{.tryTakingItems = &tryTakingItems, .trySwappingItems = &trySwappingItems}, i, .default, .takeOnly));
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
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
	items.deinit();
}