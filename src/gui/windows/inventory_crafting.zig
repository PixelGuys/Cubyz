const std = @import("std");

const main = @import("root");
const items = main.items;
const BaseItem = items.BaseItem;
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

pub var arrowTexture: Texture = undefined;
var recipeResult: ItemStack = undefined;

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

fn tryTakingItems(recipeIndex: usize, destination: *ItemStack, _: u16) void {
	const recipe = items.recipes()[recipeIndex];
	const resultItem = recipe.resultItem;
	if(!destination.canAddAll(resultItem.item.?, resultItem.amount)) return;
	for(recipe.sourceItems, recipe.sourceAmounts) |item, _amount| {
		var amount = _amount;
		for(main.game.Player.inventory__SEND_CHANGES_TO_SERVER.items) |*itemStack| {
			if(itemStack.item) |invItem| {
				if(invItem == .baseItem and invItem.baseItem == item) {
					if(amount >= itemStack.amount) {
						amount -= itemStack.amount;
						itemStack.clear();
					} else {
						itemStack.amount -= @intCast(amount);
						amount = 0;
					}
					if(amount == 0) break;
				}
			}
		}
		if(amount != 0) {
			std.log.warn("Congratulations, you just managed to cheat {}*{s}, thanks to my lazy coding. Have fun with that :D", .{amount, item.id});
		}
	}
	std.debug.assert(destination.add(resultItem.item.?, resultItem.amount) == resultItem.amount);
}

fn findAvailableRecipes(list: *VerticalList) bool {
	const oldAmounts = main.stackAllocator.dupe(u32, itemAmount.items);
	defer main.stackAllocator.free(oldAmounts);
	for(itemAmount.items) |*amount| {
		amount.* = 0;
	}
	// Figure out what items are available in the inventory:
	for(main.game.Player.inventory__SEND_CHANGES_TO_SERVER.items) |itemStack| {
		addItemStackToAvailable(itemStack);
	}
	addItemStackToAvailable(gui.inventory.carriedItemStack);
	if(std.mem.eql(u32, oldAmounts, itemAmount.items)) return false;
	// Remove no longer present items:
	var i: u32 = 0;
	while(i < availableItems.items.len) : (i += 1) {
		if(itemAmount.items[i] == 0) {
			_ = itemAmount.swapRemove(i);
			_ = availableItems.swapRemove(i);
		}
	}
	// Find all recipes the player can make:
	outer: for(items.recipes(), 0..) |*recipe, recipeIndex| {
		middle: for(recipe.sourceItems, recipe.sourceAmounts) |sourceItem, sourceAmount| {
			for(availableItems.items, itemAmount.items) |availableItem, availableAmount| {
				if(availableItem == sourceItem and availableAmount >= sourceAmount) {
					continue :middle;
				}
			}
			continue :outer; // Ingredient not found.
		}
		// All ingredients found: Add it to the list.
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
				columnList.add(ItemSlot.init(.{0, 0}, .{.item = .{.baseItem = recipe.sourceItems[i]}, .amount = recipe.sourceAmounts[i]}, &.{}, 0, .immutable, .immutable));
				i += 1;
			}
			columnList.finish(.center);
			rowList.add(columnList);
		}
		rowList.add(Icon.init(.{8, 0}, .{32, 32}, arrowTexture, false));
		const itemSlot = ItemSlot.init(.{8, 0}, recipe.resultItem, &.{.tryTakingItems = &tryTakingItems}, recipeIndex, .craftingResult, .takeOnly);
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
	gui.updateWindowPositions();
}

pub fn onOpen() void {
	availableItems = main.List(*BaseItem).init(main.globalAllocator);
	itemAmount = main.List(u32).init(main.globalAllocator);
	refresh();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
	availableItems.deinit();
	itemAmount.deinit();
}

pub fn update() void {
	refresh();
}