const std = @import("std");

const main = @import("main");
const items = main.items;
const BaseItemIndex = items.BaseItemIndex;
const Inventory = items.Inventory;
const ItemStack = items.ItemStack;
const Player = main.game.Player;
const Texture = main.graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const Icon = GuiComponent.Icon;
const ItemSlot = GuiComponent.ItemSlot;

const inventory = @import("inventory.zig");

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .lower, .otherAttachmentPoint = .upper}},
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
	},
	.contentSize = Vec2f{64*8, 64*4},
	.scale = 0.75,
};

const padding: f32 = 8;

var availableItems: main.List(BaseItemIndex) = undefined;
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
	inline for(.{main.game.Player.hotbar, main.game.Player.mainInventory}) |inv| {
		for(0..inv.size()) |i| {
			addItemStackToAvailable(inv.getStack(i));
		}
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
		if(recipe.cachedInventory == null) {
			recipe.cachedInventory = Inventory.init(main.globalAllocator, recipe.sourceItems.len + 1, .crafting, .{.recipe = recipe}, .{});
		}
		const inv = recipe.cachedInventory.?;
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
				columnList.add(ItemSlot.init(.{0, 0}, inv, i, .immutable, .immutable));
				i += 1;
			}
			columnList.finish(.center);
			rowList.add(columnList);
		}
		rowList.add(Icon.init(.{8, 0}, .{32, 32}, arrowTexture, false));
		const itemSlot = ItemSlot.init(.{8, 0}, inv, @intCast(recipe.sourceItems.len), .craftingResult, .takeOnly);
		rowList.add(itemSlot);
		rowList.finish(.{0, 0}, .center);
		list.add(rowList);
	}
	return true;
}

fn refresh() void {
	const oldScrollState = if(window.rootComponent) |oldList| oldList.verticalList.scrollBar.currentState else 0;
	const list = VerticalList.init(.{padding, padding + 16}, 300, 8);
	const recipesChanged = findAvailableRecipes(list);
	if(!recipesChanged and window.rootComponent != null) {
		list.deinit();
		return;
	}
	if(window.rootComponent) |*comp| {
		main.heap.GarbageCollection.deferredFree(.{.ptr = comp.verticalList, .freeFunction = main.utils.castFunctionSelfToAnyopaque(VerticalList.deinit)});
	}
	if(list.children.items.len == 0) {
		list.add(Label.init(.{0, 0}, 120, "No craftable\nrecipes found", .center));
	}
	list.finish(.center);
	list.scrollBar.currentState = oldScrollState;
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
	inventories.deinit();
}

pub fn update() void {
	refresh();
}
