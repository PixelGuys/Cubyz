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

fn parsePattern(allocator: NeverFailingAllocator, pattern: []const u8, keys: *const std.StringHashMap([]const u8)) !main.List(Segment) {
	var arenaAllocator: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer arenaAllocator.deinit();
	const arena = arenaAllocator.allocator();
	var segments: main.List(Segment) = .init(arena);
	var idx: usize = 0;
	while(idx < pattern.len) {
		if(pattern[idx] == '{') {
			idx += 1;
			const endIndex = std.mem.indexOfScalarPos(u8, pattern, idx, '}') orelse return error.UnclosedBrackets;
			if(idx == endIndex) return error.EmptyBrackets;
			const symbol = pattern[idx..endIndex];
			if(keys.get(symbol)) |literal| {
				if(segments.items.len > 0 and segments.items[segments.items.len - 1] == .literal) {
					const value = segments.pop();
					segments.append(.{.literal = std.mem.concat(arena.allocator, u8, &.{value.literal, literal}) catch unreachable});
				} else {
					segments.append(.{.literal = literal});
				}
			} else {
				segments.append(.{.symbol = symbol});
			}
			idx = endIndex + 1;
		} else {
			const endIndex = std.mem.indexOfScalarPos(u8, pattern, idx, '{') orelse pattern.len;
			if(segments.items.len > 0 and segments.items[segments.items.len - 1] == .literal) {
				const value = segments.pop();
				segments.append(.{.literal = std.mem.concat(arena.allocator, u8, &.{value.literal, pattern[idx..endIndex]}) catch unreachable});
			} else {
				segments.append(.{.literal = pattern[idx..endIndex]});
			}
			idx = endIndex;
		}
	}
	var newSegments: main.List(Segment) = .init(allocator);
	for(segments.items) |segment| {
		switch(segment) {
			.literal => |literal| {
				newSegments.append(.{.literal = allocator.dupe(u8, literal)});
			},
			.symbol => |symbol| {
				newSegments.append(.{.symbol = allocator.dupe(u8, symbol)});
			},
		}
	}
	return newSegments;
}

fn matchWithKeys(allocator: NeverFailingAllocator, target: []const u8, pattern: []const Segment, keys: *const std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
	var idx: usize = 0;
	idx = 0;
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
						return error.NoMatch;
					}
					break :blk std.mem.indexOfPos(u8, target, idx, nextSegment.literal) orelse {
						return error.NoMatch;
					};
				} else target.len;
				newKeys.put(allocator.dupe(u8, symbol), allocator.dupe(u8, target[idx..endIndex])) catch unreachable;
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

fn parseRecipeItem(allocator: NeverFailingAllocator, zon: ZonElement, keys: *const std.StringHashMap([]const u8)) !main.List(ItemKeyPair) {
	var arenaAllocator: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer arenaAllocator.deinit();
	const arena = arenaAllocator.allocator();
	var id = zon.as([]const u8, "");
	id = std.mem.trim(u8, id, &std.ascii.whitespace);
	var amount: u16 = 1;
	if(std.mem.indexOfScalar(u8, id, ' ')) |index| blk: {
		amount = std.fmt.parseInt(u16, id[0..index], 0) catch break :blk;
		id = id[index + 1 ..];
		id = std.mem.trim(u8, id, &std.ascii.whitespace);
	}
	var itemPairs: main.List(ItemKeyPair) = .initCapacity(allocator, 1);
	const pattern = try parsePattern(arena, id, keys);
	if(id.len > 0 and pattern.items.len == 1 and pattern.items[0] == .literal) {
		const item = BaseItemIndex.fromId(pattern.items[0].literal) orelse return itemPairs;
		itemPairs.append(.{
			.item = .{
				.item = .{.baseItem = item},
				.amount = amount,
			},
			.keys = keys.clone() catch unreachable,
		});
	} else {
		var iter = items.iterator();
		while(iter.next()) |item| {
			if(matchWithKeys(allocator, item.id(), pattern.items, keys) catch null) |newKeys| {
				itemPairs.append(.{
					.item = .{
						.item = .{.baseItem = item.*},
						.amount = amount,
					},
					.keys = newKeys,
				});
			}
		}
	}
	return itemPairs;
}

fn generateItemCombos(allocator: NeverFailingAllocator, recipe: []ZonElement) !main.List([]ItemStack) {
	var arenaAllocator: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer arenaAllocator.deinit();
	var arena = arenaAllocator.allocator();
	var emptyKeys: std.StringHashMap([]const u8) = .init(arena.allocator);
	const startingParsedItems = try parseRecipeItem(arena, recipe[0], &emptyKeys);
	var inputCombos: main.List([]ItemStack) = .initCapacity(arena, startingParsedItems.items.len);
	var keyList: main.List(std.StringHashMap([]const u8)) = .initCapacity(arena, startingParsedItems.items.len);
	for(startingParsedItems.items) |item| {
		const inputs = arena.alloc(ItemStack, recipe.len);
		inputs[0] = item.item;
		inputCombos.append(inputs);
		keyList.append(item.keys);
	}
	for(1.., recipe[1..]) |i, itemZon| {
		var newKeyList: main.List(std.StringHashMap([]const u8)) = .init(arena);
		var newInputCombos: main.List([]ItemStack) = .init(arena);

		for(keyList.items, inputCombos.items) |*keys, inputs| {
			const parsedItems = try parseRecipeItem(arena, itemZon, keys);
			for(parsedItems.items) |item| {
				const newInputs = arena.dupe(ItemStack, inputs);
				newInputs[i] = item.item;
				newInputCombos.append(newInputs);
				newKeyList.append(item.keys);
			}
		}
		keyList = newKeyList;
		inputCombos = newInputCombos;
	}
	var newInputCombos: main.List([]ItemStack) = .initCapacity(allocator, inputCombos.items.len);
	for(inputCombos.items) |inputCombo| {
		newInputCombos.append(allocator.dupe(ItemStack, inputCombo));
	}
	return newInputCombos;
}

pub fn parseRecipe(zon: ZonElement, list: *main.List(Recipe)) !void {
	var arenaAllocator: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer arenaAllocator.deinit();
	const arena = arenaAllocator.allocator();
	const inputs = zon.getChild("inputs").toSlice();
	const recipeItems = arena.alloc(ZonElement, inputs.len + 1);
	@memcpy(recipeItems[0..inputs.len], inputs);
	recipeItems[inputs.len] = zon.getChild("output");

	const itemCombos = try generateItemCombos(arena, recipeItems);
	const reversible = zon.get(bool, "reversible", false);
	for(itemCombos.items) |itemCombo| {
		if(reversible and itemCombo.len != 2) {
			return error.InvalidReversibleRecipe;
		}
		const parsedInputs = itemCombo[0 .. itemCombo.len - 1];
		const output = itemCombo[itemCombo.len - 1];
		const recipe = Recipe{
			.sourceItems = main.stackAllocator.alloc(BaseItemIndex, parsedInputs.len),
			.sourceAmounts = main.stackAllocator.alloc(u16, parsedInputs.len),
			.resultItem = output.item.?.baseItem,
			.resultAmount = output.amount,
		};
		for(parsedInputs, 0..) |input, i| {
			recipe.sourceItems[i] = input.item.?.baseItem;
			recipe.sourceAmounts[i] = input.amount;
		}
		list.append(recipe);
		if(reversible) {
			var reversedRecipe = Recipe{
				.sourceItems = main.stackAllocator.alloc(BaseItemIndex, 1),
				.sourceAmounts = main.stackAllocator.alloc(u16, 1),
				.resultItem = recipe.sourceItems[0],
				.resultAmount = recipe.sourceAmounts[0],
			};
			reversedRecipe.sourceItems[0] = recipe.resultItem;
			reversedRecipe.sourceAmounts[0] = recipe.resultAmount;
			list.append(reversedRecipe);
		}
	}
}
