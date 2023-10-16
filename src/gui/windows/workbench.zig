const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const items = main.items;
const BaseItem = items.BaseItem;
const ItemStack = items.ItemStack;
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
const CraftingResultSlot = GuiComponent.CraftingResultSlot;
const ImmutableItemSlot = GuiComponent.ImmutableItemSlot;

const inventory = @import("inventory.zig");
const inventory_crafting = @import("inventory_crafting.zig");

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower} },
	},
	.contentSize = Vec2f{64*8, 64*4},
	.id = "workbench",
};

const padding: f32 = 8;

var availableItems: [25]?*const BaseItem = undefined;

var craftingGrid: [25]ItemStack = undefined;

var craftingResult: *CraftingResultSlot = undefined;

var seed: u32 = undefined;

var itemSlots: [25]*ItemSlot = undefined;

pub fn tryAddingItems(index: usize, source: *ItemStack, amount: u16) void {
	if(source.item == null) return;
	if(source.item.? != .baseItem) return;
	if(source.item.?.baseItem.material == null) return;
	const destination = &craftingGrid[index];
	if(destination.item != null and !std.meta.eql(source.item, destination.item)) return;
	destination.item = source.item;
	const actual = destination.add(amount);
	source.amount -= actual;
	if(source.amount == 0) source.item = null;
}

pub fn tryTakingItems(index: usize, destination: *ItemStack, _amount: u16) void {
	var amount = _amount;
	const source = &craftingGrid[index];
	if(destination.item != null and !std.meta.eql(source.item, destination.item)) return;
	if(source.item == null) return;
	amount = @min(amount, source.amount);
	destination.item = source.item;
	const actual = destination.add(amount);
	source.amount -= actual;
	if(source.amount == 0) source.item = null;
}

pub fn trySwappingItems(index: usize, source: *ItemStack) void {
	const destination = &craftingGrid[index];
	const swap = destination.*;
	destination.* = source.*;
	source.* = swap;
}

const vtable = ItemSlot.VTable {
	.tryAddingItems = &tryAddingItems,
	.tryTakingItems = &tryTakingItems,
	.trySwappingItems = &trySwappingItems,
};

fn onTake(_: usize) void {
	for(&craftingGrid) |*itemStack| {
		if(itemStack.item != null and itemStack.item.? == .baseItem and itemStack.item.?.baseItem.material != null) {
			_ = itemStack.add(@as(i32, -1));
		}
	}
	craftingResult.itemStack = .{};
	@memset(&availableItems, null);
	// Create a new seed, so the player won't craft the exact same item twice:
	seed = @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));
}

fn changedItems() bool {
	var result: bool = false;
	for(&craftingGrid, &availableItems) |itemStack, *oldItem| {
		var newItem: ?*const BaseItem = null;
		if(itemStack.item != null and itemStack.item.? == .baseItem and itemStack.item.?.baseItem.material != null) {
			newItem = itemStack.item.?.baseItem;
		}
		if(newItem != oldItem.*) {
			oldItem.* = newItem;
			result = true;
		}
	}
	return result;
}

fn isEmpty() bool {
	for(availableItems) |item| {
		if(item != null) return false;
	}
	return true;
}

fn refresh() Allocator.Error!void {
	if(!changedItems()) return;
	craftingResult.itemStack.clear();
	if(isEmpty()) return;
	craftingResult.itemStack.item = Item{.tool = try Tool.initFromCraftingGrid(availableItems, seed)};
	craftingResult.itemStack.amount = 1;
}

pub fn onOpen() Allocator.Error!void {
	seed = @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));
	@memset(&availableItems, null);
	@memset(&craftingGrid, .{});
	var list = try HorizontalList.init();
	{ // crafting grid
		var grid = try VerticalList.init(.{0, 0}, 300, 0);
		// Inventory:
		for(0..5) |y| {
			var row = try HorizontalList.init();
			for(0..5) |x| {
				const index = x + y*5;
				const slot = try ItemSlot.init(.{0, 0}, craftingGrid[index], &vtable, index);
				itemSlots[index] = slot;
				try row.add(slot);
			}
			try grid.add(row);
		}
		grid.finish(.center);
		try list.add(grid);
	}
	try list.add(try Icon.init(.{8, 0}, .{32, 32}, inventory_crafting.arrowTexture, false));
	craftingResult = try CraftingResultSlot.init(.{8, 0}, .{}, .{.callback = &onTake});
	try list.add(craftingResult);
	list.finish(.{padding, padding + 16}, .center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
	try refresh();
}

pub fn onClose() void {
	craftingResult.itemStack.clear();
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
	availableItems = undefined;
	for(&craftingGrid) |*itemStack| {
		if(!itemStack.empty()) {
			itemStack.amount = main.game.Player.inventory__SEND_CHANGES_TO_SERVER.addItem(itemStack.item.?, itemStack.amount);
			if(!itemStack.empty()) {
				main.network.Protocols.genericUpdate.itemStackDrop(main.game.world.?.conn, itemStack.*, .{0, 0, 0}, main.game.camera.direction, 20) catch |err| {
					std.log.err("Error while dropping itemStack: {s}", .{@errorName(err)});
				};
				itemStack.clear();
			}
		}
	}
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER) catch |err| { // TODO(post-java): Add better options to the protocol.
		std.log.err("Got error while trying to send inventory data: {s}", .{@errorName(err)});
	};
	craftingGrid = undefined;
}

pub fn update() Allocator.Error!void {
	for(&itemSlots, &craftingGrid) |slot, stack| {
		try slot.updateItemStack(stack);
	}
	try refresh();
}