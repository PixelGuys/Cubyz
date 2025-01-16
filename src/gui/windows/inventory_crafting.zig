const std = @import("std");

const main = @import("root");
const items = main.items;
const BaseItem = items.BaseItem;
const Inventory = items.Inventory;
const ItemStack = items.ItemStack;
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

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .lower, .otherAttachmentPoint = .upper} },
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
	},
	.contentSize = Vec2f{64*8, 64*4},
	.scale = 0.75,
};

const padding: f32 = 8;

var availableItems: main.List(*BaseItem) = undefined;
var itemAmount: main.List(u32) = undefined;
var inventories: main.List(Inventory) = undefined;

pub var arrowTexture: Texture = undefined;

pub fn init() void {
	arrowTexture = Texture.initFromFile("assets/cubyz/ui/inventory/crafting_arrow.png");
}

pub fn deinit() void {
	arrowTexture.deinit();
}

fn addItemStackToAvailable(itemStack: ItemStack) void {
	if(itemStack.item) |item| {
		if(item == .baseItem) {
			const baseItem = item.baseItem;
			for(availableItems.items, 0..) |alreadyPresent, i| {
				if(baseItem == alreadyPresent) {
					itemAmount.items[i] += itemStack.amount;
					return;
				}
			}
			availableItems.append(baseItem);
			itemAmount.append(itemStack.amount);
		}
	}
}

fn findAvailableRecipes(list: *VerticalList) bool {
	const oldAmounts = main.stackAllocator.dupe(u32, itemAmount.items);
	defer main.stackAllocator.free(oldAmounts);
	for(itemAmount.items) |*amount| {
		amount.* = 0;
	}
	// Figure out what items are available in the inventory:
	for(0..main.game.Player.inventory.size()) |i| {
		addItemStackToAvailable(main.game.Player.inventory.getStack(i));
	}
	if(std.mem.eql(u32, oldAmounts, itemAmount.items)) return false;
	// Remove no longer present items:
	var i: u32 = 0;
	while(i < availableItems.items.len) : (i += 1) {
		if(itemAmount.items[i] == 0) {
			_ = itemAmount.swapRemove(i);
			_ = availableItems.swapRemove(i);
		}
	}
	for(inventories.items) |inv| {
		inv.deinit(main.globalAllocator);
	}
	inventories.clearRetainingCapacity();
	// Find all recipes the player can make:
	outer: for(items.recipes()) |*recipe| {
		middle: for(recipe.sourceItems, recipe.sourceAmounts) |sourceItem, sourceAmount| {
			for(availableItems.items, itemAmount.items) |availableItem, availableAmount| {
				if(availableItem == sourceItem and availableAmount >= sourceAmount) {
					continue :middle;
				}
			}
			continue :outer; // Ingredient not found.
		}
		// All ingredients found: Add it to the list.
		const inv = Inventory.init(main.globalAllocator, recipe.sourceItems.len + 1, .crafting, .other);
		inventories.append(inv);
		const rowList = HorizontalList.init();
		const maxColumns: u32 = 4;
		const itemsPerColumn = recipe.sourceItems.len/maxColumns;
		const remainder = recipe.sourceItems.len%maxColumns;
		i = 0;
		for(0..maxColumns) |col| {
			var itemsThisColumn = itemsPerColumn;
			if(col < remainder) itemsThisColumn += 1;
			const columnList = VerticalList.init(.{0, 0}, std.math.inf(f32), 0);
			for(0..itemsThisColumn) |_| {
				inv.fillAmountFromCreative(i, .{.baseItem = recipe.sourceItems[i]}, recipe.sourceAmounts[i]);
				columnList.add(ItemSlot.init(.{0, 0}, inv, i, .immutable, .immutable));
				i += 1;
			}
			columnList.finish(.center);
			rowList.add(columnList);
		}
		inv.fillAmountFromCreative(@intCast(recipe.sourceItems.len), recipe.resultItem.item, recipe.resultItem.amount);
		rowList.add(Icon.init(.{8, 0}, .{32, 32}, arrowTexture, false));
		const itemSlot = ItemSlot.init(.{8, 0}, inv, @intCast(recipe.sourceItems.len), .craftingResult, .takeOnly);
		rowList.add(itemSlot);
		rowList.finish(.{0, 0}, .center);
		list.add(rowList);
	}
	return true;
}

fn refresh() void {
	const list = VerticalList.init(.{padding, padding + 16}, 300, 8);
	if(!findAvailableRecipes(list)) {
		list.deinit();
		return;
	}
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	window.contentSize[0] = @max(window.contentSize[0], window.getMinWindowWidth());
	gui.updateWindowPositions();
}

pub fn onOpen() void {
	availableItems = .init(main.globalAllocator);
	itemAmount = .init(main.globalAllocator);
	inventories = .init(main.globalAllocator);
	refresh();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
	availableItems.deinit();
	itemAmount.deinit();
	for(inventories.items) |inv| {
		inv.deinit(main.globalAllocator);
	}
	inventories.deinit();
}

pub fn update() void {
	refresh();
}