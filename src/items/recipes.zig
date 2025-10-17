const std = @import("std");
const main = @import("main");
const items = main.items;
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const Tag = main.Tag;
const Recipe = items.Recipe;
const BaseItemIndex = items.BaseItemIndex;
const Block = main.blocks.Block;

const Segment = union(enum) {literal: []const u8, symbol: []const u8};

fn parsePattern(allocator: NeverFailingAllocator, pattern: []const u8) ![]const Segment {
	var segments: main.List(Segment) = .init(allocator);
	defer segments.deinit();
	var idx: usize = 0;
	while(idx < pattern.len) {
		if(pattern[idx] == '{') {
			if(segments.items.len > 0 and segments.items[segments.items.len - 1] == .symbol) {
				return error.AmbiguousSymbols;
			}
			idx += 1;
			const endIndex = std.mem.indexOfScalarPos(u8, pattern, idx, '}') orelse return error.UnclosedBraces;
			if(idx == endIndex) return error.EmptyBraces;
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
	pattern: []const Segment,
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

fn matchWithKeys(allocator: NeverFailingAllocator, target: []const u8, pattern: []const Segment, keys: *const std.StringHashMap([]const u8)) ![]const std.StringHashMap([]const u8) {
	var idx: usize = 0;
	var newKeys = keys.clone() catch unreachable;
	errdefer newKeys.deinit();

	for(0.., pattern) |i, segment| {
		switch(segment) {
			.literal => |literal| {
				if(!std.mem.startsWith(u8, target[idx..], literal)) {
					return error.NoMatch;
				}
				idx += literal.len;
			},
			.symbol => |symbol| {
				var endIndices: main.List(usize) = .init(allocator);
				defer endIndices.deinit();
				if(newKeys.get(symbol)) |value| {
					if(!std.mem.startsWith(u8, target[idx..], value)) {
						return error.NoMatch;
					}
					idx += value.len;
				} else {
					if(i + 1 < pattern.len) {
						const nextSegment = pattern[i + 1];
						var nextIndex = idx;
						while(std.mem.indexOfPos(u8, target, nextIndex, nextSegment.literal)) |endIndex| {
							endIndices.append(endIndex);
							nextIndex = endIndex + 1;
						}
					} else {
						endIndices.append(target.len);
					}
					if(endIndices.items.len == 0) {
						return error.NoMatch;
					}
					if(endIndices.items.len == 1) {
						newKeys.put(symbol, target[idx..endIndices.items[0]]) catch unreachable;
						idx = endIndices.items[0];
					} else {
						defer newKeys.deinit();
						var newKeyPairs: main.List(std.StringHashMap([]const u8)) = .init(allocator);
						defer newKeyPairs.deinit();
						for(endIndices.items) |endIndex| {
							newKeys.put(symbol, target[idx..endIndex]) catch unreachable;
							if(matchWithKeys(allocator, target[endIndex..], pattern[i + 1 ..], &newKeys) catch null) |newKeyMatches| {
								newKeyPairs.appendSlice(newKeyMatches);
								allocator.free(newKeyMatches);
							}
						}
						if(newKeyPairs.items.len == 0) return error.NoMatch;
						return newKeyPairs.toOwnedSlice();
					}
				}
			},
		}
	}
	if(idx == target.len) {
		var newKeyPairs = allocator.alloc(std.StringHashMap([]const u8), 1);
		newKeyPairs[0] = newKeys;
		return newKeyPairs;
	} else {
		return error.NoMatch;
	}
}

const ItemWithAmount = struct {
	item: BaseItemIndex,
	amount: u16,
};

const ItemKeyPair = struct {item: ItemWithAmount, keys: std.StringHashMap([]const u8)};

fn findRecipeItemOptions(allocator: NeverFailingAllocator, itemStackPattern: ItemStackPattern, keys: *const std.StringHashMap([]const u8)) ![]const ItemKeyPair {
	const pattern = itemStackPattern.pattern;
	const amount = itemStackPattern.amount;

	if(pattern.len == 1 and pattern[0] == .literal) {
		const item = BaseItemIndex.fromId(pattern[0].literal) orelse return error.ItemNotFound;
		return allocator.dupe(ItemKeyPair, &.{.{
			.item = .{
				.item = item,
				.amount = amount,
			},
			.keys = keys.clone() catch unreachable,
		}});
	}
	var itemPairs: main.List(ItemKeyPair) = .initCapacity(allocator, 1);
	defer itemPairs.deinit();
	var iter = items.iterator();
	while(iter.next()) |item| {
		const newKeyMatches = matchWithKeys(allocator, item.id(), pattern, keys) catch continue;
		for(newKeyMatches) |match| {
			itemPairs.append(.{
				.item = .{
					.item = item.*,
					.amount = amount,
				},
				.keys = match,
			});
		}
	}
	return itemPairs.toOwnedSlice();
}

fn generateItemCombos(allocator: NeverFailingAllocator, recipe: []const ZonElement) ![]const []const ItemWithAmount {
	const arena = main.stackAllocator.createArena();
	defer main.stackAllocator.destroyArena(arena);

	var inputCombos: main.List([]const ItemWithAmount) = .initCapacity(arena, 1);
	inputCombos.append(arena.alloc(ItemWithAmount, recipe.len));
	var keyList: main.List(std.StringHashMap([]const u8)) = .initCapacity(arena, 1);
	keyList.append(.init(arena.allocator));
	for(0.., recipe[0..]) |i, itemZon| {
		const pattern = try parseItemZon(arena, itemZon);
		var newKeyList: main.List(std.StringHashMap([]const u8)) = .init(arena);
		var newInputCombos: main.List([]const ItemWithAmount) = .init(arena);

		for(keyList.items, inputCombos.items) |*keys, inputs| {
			const parsedItems = try findRecipeItemOptions(arena, pattern, keys);
			for(parsedItems) |item| {
				const newInputs = arena.dupe(ItemWithAmount, inputs);
				newInputs[i] = item.item;
				newInputCombos.append(newInputs);
				newKeyList.append(item.keys);
			}
		}
		keyList = newKeyList;
		inputCombos = newInputCombos;
	}
	const newInputCombos = allocator.alloc([]const ItemWithAmount, inputCombos.items.len);
	for(inputCombos.items, 0..) |inputCombo, i| {
		newInputCombos[i] = allocator.dupe(ItemWithAmount, inputCombo);
	}
	return newInputCombos;
}

pub fn addRecipe(allocator: NeverFailingAllocator, itemCombo: []const ItemWithAmount, list: *main.List(Recipe)) void {
	const inputs = itemCombo[0 .. itemCombo.len - 1];
	const output = itemCombo[itemCombo.len - 1];
	const recipe = Recipe{
		.sourceItems = allocator.alloc(BaseItemIndex, inputs.len),
		.sourceAmounts = allocator.alloc(u16, inputs.len),
		.resultItem = output.item,
		.resultAmount = output.amount,
	};
	for(inputs, 0..) |input, i| {
		recipe.sourceItems[i] = input.item;
		recipe.sourceAmounts[i] = input.amount;
	}
	list.append(recipe);
}

pub fn parseRecipe(allocator: NeverFailingAllocator, zon: ZonElement, list: *main.List(Recipe)) !void {
	const arena = main.stackAllocator.createArena();
	defer main.stackAllocator.destroyArena(arena);

	const inputs = zon.getChild("inputs").toSlice();
	const recipeItems = std.mem.concat(arena.allocator, ZonElement, &.{inputs, &.{zon.getChild("output")}}) catch unreachable;

	const reversible = zon.get(bool, "reversible", false);
	if(reversible and recipeItems.len != 2) {
		return error.InvalidReversibleRecipe;
	}

	const itemCombos = try generateItemCombos(arena, recipeItems);
	for(itemCombos) |itemCombo| {
		addRecipe(allocator, itemCombo, list);
		if(reversible) {
			addRecipe(allocator, &.{itemCombo[1], itemCombo[0]}, list);
		}
	}
}

test "pattern parsing" {
	try std.testing.expectError(error.AmbiguousSymbols, parsePattern(main.heap.testingAllocator, "cubyz:{a}{b}"));
	try std.testing.expectError(error.EmptyBraces, parsePattern(main.heap.testingAllocator, "{}"));
	try std.testing.expectError(error.UnclosedBraces, parsePattern(main.heap.testingAllocator, "cubyz:{foo"));

	const pattern = try parsePattern(main.heap.testingAllocator, "foo:{bar}/{baz}");
	defer main.heap.testingAllocator.free(pattern);
	const expected: []const Segment = &.{.{.literal = "foo:"}, .{.symbol = "bar"}, .{.literal = "/"}, .{.symbol = "baz"}};

	// Can't use expectEqualSlices because segments contain strings.
	try std.testing.expectEqualDeep(expected, pattern);
}

test "pattern matching" {
	const pattern = try parsePattern(main.heap.testingAllocator, "foo:{bar}/{baz}");
	defer main.heap.testingAllocator.free(pattern);

	var keys: std.StringHashMap([]const u8) = .init(main.heap.testingAllocator.allocator);
	defer keys.deinit();

	try std.testing.expectError(error.NoMatch, matchWithKeys(main.heap.testingAllocator, "foo:1", pattern, &keys));

	const newKeys = try matchWithKeys(main.heap.testingAllocator, "foo:1/2/3", pattern, &keys);
	defer {
		for(newKeys) |*keySet| {
			@constCast(keySet).deinit();
		}
		main.heap.testingAllocator.free(newKeys);
	}

	try std.testing.expectEqual(2, newKeys.len);
	try std.testing.expectEqualStrings("1", newKeys[0].get("bar").?);
	try std.testing.expectEqualStrings("2/3", newKeys[0].get("baz").?);
	try std.testing.expectEqualStrings("1/2", newKeys[1].get("bar").?);
	try std.testing.expectEqualStrings("3", newKeys[1].get("baz").?);
}

test "pattern matching with keys" {
	const pattern = try parsePattern(main.heap.testingAllocator, "foo:{bar}/{baz}");
	defer main.heap.testingAllocator.free(pattern);

	var keys: std.StringHashMap([]const u8) = .init(main.heap.testingAllocator.allocator);
	defer keys.deinit();
	keys.put("bar", "1/2") catch unreachable;

	const newKeys = try matchWithKeys(main.heap.testingAllocator, "foo:1/2/3", pattern, &keys);
	defer {
		for(newKeys) |*keySet| {
			@constCast(keySet).deinit();
		}
		main.heap.testingAllocator.free(newKeys);
	}

	try std.testing.expectEqual(1, newKeys.len);
	try std.testing.expectEqualStrings("1/2", newKeys[0].get("bar").?);
	try std.testing.expectEqualStrings("3", newKeys[0].get("baz").?);
}
