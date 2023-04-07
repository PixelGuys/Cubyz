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
	.contentSize = Vec2f{64*8, 64*4},
	.title = "Creative Inventory",
	.id = "creative_inventory",
};

const padding: f32 = 8;
var itemStacks: std.ArrayList(ItemStack) = undefined;
var items: std.ArrayList(Item) = undefined;

pub fn onOpen() Allocator.Error!void {
	itemStacks = std.ArrayList(ItemStack).init(main.globalAllocator);
	items = std.ArrayList(Item).init(main.globalAllocator);
	var itemIterator = main.items.iterator();
	while(itemIterator.next()) |item| {
		try itemStacks.append(.{});
		try items.append(Item{.baseItem = item.*});
	}

	var list = try VerticalList.init(.{padding, padding + 16}, 140, 0);
	var i: u32 = 0;
	while(i < items.items.len) {
		var row = try HorizontalList.init();
		for(0..8) |_| {
			if(i >= items.items.len) break;
			try row.add(try ItemSlot.init(.{0, 0}, &itemStacks.items[i]));
			i += 1;
		}
		try list.add(row);
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @splat(2, padding);
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
	itemStacks.deinit();
	items.deinit();
}

pub fn render() Allocator.Error!void {
	for(itemStacks.items, items.items) |*stack, item| {
		stack.item = item;
		stack.amount = 64;
	}
}