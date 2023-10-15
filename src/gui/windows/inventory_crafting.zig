const std = @import("std");
const Allocator = std.mem.Allocator;

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
const CraftingResultSlot = GuiComponent.CraftingResultSlot;
const ImmutableItemSlot = GuiComponent.ImmutableItemSlot;

const inventory = @import("inventory.zig");

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .lower, .otherAttachmentPoint = .upper} },
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
	},
	.contentSize = Vec2f{64*8, 64*4},
	.id = "inventory_crafting",
};

const padding: f32 = 8;

var availableItems: std.ArrayList(*BaseItem) = undefined;
var itemAmount: std.ArrayList(u32) = undefined;

pub var arrowTexture: Texture = undefined;
var recipeResult: ItemStack = undefined;

pub fn init() !void {
	arrowTexture = try Texture.initFromFile("assets/cubyz/ui/inventory/crafting_arrow.png");
}

pub fn deinit() void {
	arrowTexture.deinit();
}

fn addItemStackToAvailable(itemStack: ItemStack) Allocator.Error!void {
	if(itemStack.item) |item| {
		if(item == .baseItem) {
			const baseItem = item.baseItem;
			for(availableItems.items, 0..) |alreadyPresent, i| {
				if(baseItem == alreadyPresent) {
					itemAmount.items[i] += itemStack.amount;
					return;
				}
			}
			try availableItems.append(baseItem);
			try itemAmount.append(itemStack.amount);
		}
	}
}

fn onTake(recipeIndex: usize) void {
	const recipe = items.recipes()[recipeIndex];
	for(recipe.sourceItems, recipe.sourceAmounts) |item, _amount| {
		var amount: u32 = _amount;
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
}

fn findAvailableRecipes(list: *VerticalList) Allocator.Error!bool {
	const oldAmounts = try main.threadAllocator.dupe(u32, itemAmount.items);
	defer main.threadAllocator.free(oldAmounts);
	for(itemAmount.items) |*amount| {
		amount.* = 0;
	}
	// Figure out what items are available in the inventory:
	for(main.game.Player.inventory__SEND_CHANGES_TO_SERVER.items) |itemStack| {
		try addItemStackToAvailable(itemStack);
	}
	try addItemStackToAvailable(gui.inventory.carriedItemStack);
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
		var rowList = try HorizontalList.init();
		const maxColumns: u32 = 4;
		const itemsPerColumn = recipe.sourceItems.len/maxColumns;
		const remainder = recipe.sourceItems.len%maxColumns;
		i = 0;
		for(0..maxColumns) |col| {
			var itemsThisColumn = itemsPerColumn;
			if(col < remainder) itemsThisColumn += 1;
			var columnList = try VerticalList.init(.{0, 0}, std.math.inf(f32), 0);
			for(0..itemsThisColumn) |_| {
				try columnList.add(try ImmutableItemSlot.init(.{0, 0}, recipe.sourceItems[i], recipe.sourceAmounts[i]));
				i += 1;
			}
			columnList.finish(.center);
			try rowList.add(columnList);
		}
		try rowList.add(try Icon.init(.{8, 0}, .{32, 32}, arrowTexture, false));
		const itemSlot = try CraftingResultSlot.init(.{8, 0}, recipe.resultItem, .{.callback = &onTake, .arg = recipeIndex});
		try rowList.add(itemSlot);
		rowList.finish(.{0, 0}, .center);
		try list.add(rowList);
	}
	return true;
}

fn refresh() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, padding + 16}, 300, 8);
	if(!try findAvailableRecipes(list)) {
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

pub fn onOpen() Allocator.Error!void {
	availableItems = std.ArrayList(*BaseItem).init(main.globalAllocator);
	itemAmount = std.ArrayList(u32).init(main.globalAllocator);
	try refresh();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
	availableItems.deinit();
	itemAmount.deinit();
}

pub fn update() Allocator.Error!void {
	try refresh();
}