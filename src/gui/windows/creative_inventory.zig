const std = @import("std");
const Allocator = std.mem.Allocator;

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
	.id = "creative_inventory",
};

const padding: f32 = 8;
var items: std.ArrayList(Item) = undefined;

pub fn tryAddingItems(_: usize, _: *ItemStack, _: u16) void {
	return;
}

pub fn tryTakingItems(index: usize, destination: *ItemStack, amount: u16) void {
	if(destination.item != null and !std.meta.eql(destination.item.?, items.items[index])) return;
	destination.item = items.items[index];
	_ = destination.add(amount);
}

pub fn trySwappingItems(_: usize, _: *ItemStack) void {
	return;
}

const vtable = ItemSlot.VTable {
	.tryAddingItems = &tryAddingItems,
	.tryTakingItems = &tryTakingItems,
	.trySwappingItems = &trySwappingItems,
};

pub fn onOpen() Allocator.Error!void {
	items = std.ArrayList(Item).init(main.globalAllocator);
	var itemIterator = main.items.iterator();
	while(itemIterator.next()) |item| {
		try items.append(Item{.baseItem = item.*});
	}

	var list = try VerticalList.init(.{padding, padding + 16}, 140, 0);
	var i: u32 = 0;
	while(i < items.items.len) {
		var row = try HorizontalList.init();
		for(0..8) |_| {
			if(i >= items.items.len) break;
			const item = items.items[i];
			try row.add(try ItemSlot.init(.{0, 0}, .{.item = item, .amount = item.stackSize()}, &vtable, i));
			i += 1;
		}
		try list.add(row);
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