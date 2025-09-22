const std = @import("std");
const main = @import("main");
const items = main.items;
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const ItemStack = items.ItemStack;
const Tag = main.Tag;
const Recipe = items.Recipe;
const BaseItemIndex = items.BaseItemIndex;
const Block = main.blocks.Block;

const Segment = union(enum) {literal: []const u8, symbol: []const u8};

fn parsePattern(allocator: NeverFailingAllocator, pattern: []const u8) ![]Segment {
	var segments: main.List(Segment) = .init(allocator);
	defer segments.deinit();
	var idx: usize = 0;
	while(idx < pattern.len) {
		if(pattern[idx] == '{') {
			idx += 1;
			const endIndex = std.mem.indexOfScalarPos(u8, pattern, idx, '}') orelse return error.UnclosedBraces;
			if(idx == endIndex) return error.EmptyBrackets;
			const symbol = pattern[idx..endIndex];
			segments.append(.{.symbol = symbol});
			idx = endIndex + 1;
		} else {
			const endIndex = std.mem.indexOfScalarPos(u8, pattern, idx, '{') orelse pattern.len;
			segments.append(.{.literal = pattern[idx..endIndex]});
			idx = endIndex;
		}
	}
	return segments.toOwnedSlice();
}

const ItemStackPattern = struct {
	amount: u16,
	pattern: []Segment,
};

fn parseItemZon(allocator: NeverFailingAllocator, zon: ZonElement) !ItemStackPattern {
	var id = zon.as([]const u8, "");
	var amount: u16 = 1;
	if(std.mem.indexOfScalar(u8, id, ' ')) |index| blk: {
		amount = std.fmt.parseInt(u16, id[0..index], 0) catch break :blk;
		id = id[index + 1 ..];
	}
	const pattern = try parsePattern(allocator, id);
	return .{
		.amount = amount,
		.pattern = pattern,
	};
}

fn matchWithKeys(allocator: NeverFailingAllocator, target: []const u8, pattern: []const Segment, keys: *const std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
	var idx: usize = 0;
	var newKeys = keys.clone() catch unreachable;
	errdefer newKeys.deinit();

	for(0.., pattern) |i, segment| {
		switch(segment) {
			.literal => |literal| {
				if(literal.len + idx > target.len or !std.mem.eql(u8, target[idx .. idx + literal.len], literal)) {
					return error.NoMatch;
				}
				idx += literal.len;
			},
			.symbol => |symbol| {
				const endIndex: usize = if(i + 1 < pattern.len) blk: {
					const nextSegment = pattern[i + 1];
					if(nextSegment == .symbol) {
						return error.AmbiguousSymbols;
					}
					break :blk std.mem.indexOfPos(u8, target, idx, nextSegment.literal) orelse {
						return error.NoMatch;
					};
				} else target.len;
				if(newKeys.get(symbol)) |value| {
					if(!std.mem.eql(u8, target[idx..endIndex], value)) {
						return error.NoMatch;
					}
				} else {
					newKeys.put(allocator.dupe(u8, symbol), allocator.dupe(u8, target[idx..endIndex])) catch unreachable;
				}
				idx = endIndex;
			},
		}
	}
	if(idx == target.len) {
		return newKeys;
	} else {
		return error.NoMatch;
	}
}

const ItemKeyPair = struct {item: ItemStack, keys: std.StringHashMap([]const u8)};

fn findRecipeItemOptions(allocator: NeverFailingAllocator, itemStackPattern: ItemStackPattern, keys: *const std.StringHashMap([]const u8)) ![]ItemKeyPair {
	const pattern = itemStackPattern.pattern;
	const amount = itemStackPattern.amount;

	var itemPairs: main.List(ItemKeyPair) = .initCapacity(allocator, 1);
	defer itemPairs.deinit();
	if(pattern.len == 1 and pattern[0] == .literal) {
		const item = BaseItemIndex.fromId(pattern[0].literal) orelse return error.ItemNotFound;
		return allocator.dupe(ItemKeyPair, &.{.{
			.item = .{
				.item = .{.baseItem = item},
				.amount = amount,
			},
			.keys = keys.clone() catch unreachable,
		}});
	} else {
		var iter = items.iterator();
		while(iter.next()) |item| {
			const newKeys = matchWithKeys(allocator, item.id(), pattern, keys) catch |err| {
				if(err != error.NoMatch) {
					return err;
				} else {
					continue;
				}
			};
			itemPairs.append(.{
				.item = .{
					.item = .{.baseItem = item.*},
					.amount = amount,
				},
				.keys = newKeys,
			});
		}
	}
	return itemPairs.toOwnedSlice();
}

fn generateItemCombos(allocator: NeverFailingAllocator, recipe: []ZonElement) ![][]ItemStack {
	var arenaAllocator: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer arenaAllocator.deinit();
	var arena = arenaAllocator.allocator();

	var inputCombos: main.List([]ItemStack) = .initCapacity(arena, 1);
	inputCombos.append(arena.alloc(ItemStack, recipe.len));
	var keyList: main.List(std.StringHashMap([]const u8)) = .initCapacity(arena, 1);
	keyList.append(.init(arena.allocator));
	for(0.., recipe[0..]) |i, itemZon| {
		const pattern = try parseItemZon(arena, itemZon);
		var newKeyList: main.List(std.StringHashMap([]const u8)) = .init(arena);
		var newInputCombos: main.List([]ItemStack) = .init(arena);

		for(keyList.items, inputCombos.items) |*keys, inputs| {
			const parsedItems = try findRecipeItemOptions(arena, pattern, keys);
			for(parsedItems) |item| {
				const newInputs = arena.dupe(ItemStack, inputs);
				newInputs[i] = item.item;
				newInputCombos.append(newInputs);
				newKeyList.append(item.keys);
			}
		}
		keyList = newKeyList;
		inputCombos = newInputCombos;
	}
	const newInputCombos = allocator.alloc([]ItemStack, inputCombos.items.len);
	for(inputCombos.items, 0..) |inputCombo, i| {
		newInputCombos[i] = allocator.dupe(ItemStack, inputCombo);
	}
	return newInputCombos;
}

pub fn addRecipe(itemCombo: []const ItemStack, list: *main.List(Recipe)) void {
	const inputs = itemCombo[0 .. itemCombo.len - 1];
	const output = itemCombo[itemCombo.len - 1];
	const recipe = Recipe{
		.sourceItems = main.globalAllocator.alloc(BaseItemIndex, inputs.len),
		.sourceAmounts = main.globalAllocator.alloc(u16, inputs.len),
		.resultItem = output.item.?.baseItem,
		.resultAmount = output.amount,
	};
	for(inputs, 0..) |input, i| {
		recipe.sourceItems[i] = input.item.?.baseItem;
		recipe.sourceAmounts[i] = input.amount;
	}
	list.append(recipe);
}

pub fn parseRecipe(zon: ZonElement, list: *main.List(Recipe)) !void {
	var arenaAllocator: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer arenaAllocator.deinit();
	const arena = arenaAllocator.allocator();

	const inputs = zon.getChild("inputs").toSlice();
	const recipeItems = std.mem.concat(arena.allocator, ZonElement, &.{inputs, &.{zon.getChild("output")}}) catch unreachable;

	const reversible = zon.get(bool, "reversible", false);
	if(reversible and recipeItems.len != 2) {
		return error.InvalidReversibleRecipe;
	}

	const itemCombos = try generateItemCombos(arena, recipeItems);
	for(itemCombos) |itemCombo| {
		addRecipe(itemCombo, list);
		if(reversible) {
			addRecipe(&.{itemCombo[1], itemCombo[0]}, list);
		}
	}
}
