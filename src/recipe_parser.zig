const std = @import("std");
const main = @import("main");
const items = main.items;
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ItemStack = items.ItemStack;
const Tag = main.Tag;
const Recipe = items.Recipe;
const BaseItemIndex = items.BaseItemIndex;
const Block = main.blocks.Block;

const Segment = union(enum) {literal: []const u8, symbol: []const u8};

fn parsePattern(allocator: NeverFailingAllocator, pattern: []const u8, keys: *const std.StringHashMap([]const u8)) !main.List(Segment) {
	var segments: main.List(Segment) = .init(allocator);
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
				defer allocator.free(value.literal);
					segments.append(.{.literal = std.mem.concat(allocator.allocator, u8, &.{value.literal, literal}) catch unreachable});
				} else {
					segments.append(.{.literal = allocator.dupe(u8, literal)});
				}
			} else {
				segments.append(.{.symbol = allocator.dupe(u8, symbol)});
			}
			idx = endIndex + 1;
		} else {
			const endIndex = std.mem.indexOfScalarPos(u8, pattern, idx, '{') orelse pattern.len;
			if(segments.items.len > 0 and segments.items[segments.items.len - 1] == .literal) {
				const value = segments.pop();
				defer allocator.free(value.literal);
				segments.append(.{.literal = std.mem.concat(allocator.allocator, u8, &.{value.literal, pattern[idx..endIndex]}) catch unreachable});
			} else {
				segments.append(.{.literal = allocator.dupe(u8, pattern[idx..endIndex])});
			}
			idx = endIndex;
		}
	}
	return segments;
}

fn matchWithKeys(allocator: NeverFailingAllocator, target: []const u8, pattern: []const Segment, keys: *const std.StringHashMap([]const u8)) ?std.StringHashMap([]const u8) {
	var idx: usize = 0;
	idx = 0;
	var newKeys = keys.clone() catch unreachable;
	for(0.., pattern) |i, segment| {
		switch(segment) {
			.literal => |literal| {
				if(literal.len + idx > target.len or !std.mem.eql(u8, target[idx .. idx + literal.len], literal)) {
					newKeys.deinit();
					return null;
				}
				idx += literal.len;
			},
			.symbol => |symbol| {
				const endIndex: usize = if(i + 1 < pattern.len) blk: {
					const nextSegment = pattern[i + 1];
					if(nextSegment == .symbol) {
						newKeys.deinit();
						return null;
					}
					break :blk std.mem.indexOfPos(u8, target, idx, nextSegment.literal) orelse {
						newKeys.deinit();
						return null;
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
		newKeys.deinit();
		return null;
	}
}

const ItemKeyPair = struct {item: ItemStack, keys: std.StringHashMap([]const u8)};

fn parseRecipeItem(allocator: NeverFailingAllocator, zon: ZonElement, keys: *const std.StringHashMap([]const u8)) !main.List(ItemKeyPair) {
	var id = zon.as([]const u8, "");
	id = std.mem.trim(u8, id, &std.ascii.whitespace);
	var amount: u16 = 1;
	if(std.mem.indexOfScalar(u8, id, ' ')) |index| blk: {
		amount = std.fmt.parseInt(u16, id[0..index], 0) catch break :blk;
		id = id[index + 1 ..];
		id = std.mem.trim(u8, id, &std.ascii.whitespace);
	}
	var itemPairs: main.List(ItemKeyPair) = .initCapacity(allocator, 1);
	var iterator = std.mem.splitScalar(u8, id, '.');
	id = iterator.next().?;
	var tags: main.List(Tag) = .init(allocator);
	defer tags.deinit();
	while(iterator.next()) |tagString| {
		tags.append(Tag.get(tagString) orelse return error.TagNotFound);
	}

	var pattern = try parsePattern(allocator, id, keys);
	defer {
		for(pattern.items) |segment| {
			switch (segment) {
				.literal => |literal| allocator.free(literal),
				.symbol => |symbol| allocator.free(symbol),
			}
		}
		pattern.deinit();
	}
	if(id.len > 0 and pattern.items.len == 1 and pattern.items[0] == .literal) {
		const item = BaseItemIndex.fromId(pattern.items[0].literal) orelse return itemPairs;
		for(tags.items) |tag| {
			if(!item.hasTag(tag) and !(item.block() != null and (Block{.typ = item.block().?, .data = 0}).hasTag(tag))) return itemPairs;
		}
		itemPairs.append(.{
			.item = .{
				.item = .{.baseItem = item},
				.amount = amount,
			},
			.keys = keys.clone() catch unreachable,
		});
	} else {
		if(std.mem.eql(u8, "{mod}:branch/leafy/{type}", id)) {
			var iter = keys.iterator();
			while(iter.next()) |item| {
				std.log.info("{s}: {s}", .{item.key_ptr.*, item.value_ptr.*});
			}
		}

		var iter = items.iterator();
		loop: while(iter.next()) |item| {
			for(tags.items) |tag| {
				if(!item.hasTag(tag) and !(item.block() != null and (Block{.typ = item.block().?, .data = 0}).hasTag(tag))) {
					continue :loop;
				}
			}
			if(matchWithKeys(allocator, item.id(), pattern.items, keys)) |newKeys| {
				itemPairs.append(.{
					.item = .{
						.item = .{.baseItem = item.*},
						.amount = amount,
					},
					.keys = newKeys,
				});
			} else if(id.len == 0) {
				itemPairs.append(.{
					.item = .{
						.item = .{.baseItem = item.*},
						.amount = amount,
					},
					.keys = keys.clone() catch unreachable,
				});
			}
		}
	}
	return itemPairs;
}

fn generateItemCombos(allocator: NeverFailingAllocator, recipe: []ZonElement) !main.List([]ItemStack) {
	var remainingItems = recipe;
	var emptyKeys: std.StringHashMap([]const u8) = .init(allocator.allocator);
	defer emptyKeys.deinit();
	const startingParsedItems = try parseRecipeItem(allocator, remainingItems[0], &emptyKeys);
	defer startingParsedItems.deinit();
	var inputCombos: main.List([]ItemStack) = .initCapacity(allocator, startingParsedItems.items.len);
	errdefer {
		for(inputCombos.items) |combo| {
			allocator.free(combo);
		}
		inputCombos.deinit();
	}
	var keyList: main.List(std.StringHashMap([]const u8)) = .initCapacity(allocator, startingParsedItems.items.len);
	defer {
		for(keyList.items) |*keys| {
			keys.deinit();
		}
		keyList.deinit();
	}
	for(startingParsedItems.items) |item| {
		const inputs = allocator.alloc(ItemStack, recipe.len);
		inputs[0] = item.item;
		inputCombos.append(inputs);
		keyList.append(item.keys);
	}
	while(remainingItems.len > 1) {
		remainingItems = remainingItems[1..];
		const startIndex = inputCombos.items[0].len - remainingItems.len;
		var newKeyList: main.List(std.StringHashMap([]const u8)) = .init(allocator);
		var newInputCombos: main.List([]ItemStack) = .init(allocator);

		for(keyList.items, inputCombos.items) |*keys, inputs| {
			const parsedItems = try parseRecipeItem(allocator, remainingItems[0], keys);
			defer parsedItems.deinit();
			for(parsedItems.items) |item| {
				const newInputs = allocator.dupe(ItemStack, inputs);
				newInputs[startIndex] = item.item;
				newInputCombos.append(newInputs);
				newKeyList.append(item.keys);
			}
		}

		for(keyList.items) |*keys| {
			keys.deinit();
		}
		keyList.deinit();
		keyList = newKeyList;
		for(inputCombos.items) |combo| {
			allocator.free(combo);
		}
		inputCombos.deinit();
		inputCombos = newInputCombos;
	}
	return inputCombos;
}

pub fn parseRecipe(allocator: NeverFailingAllocator, zon: ZonElement, list: *main.List(Recipe)) !void {
	const inputs = zon.getChild("inputs").toSlice();
	const recipeItems = allocator.alloc(ZonElement, inputs.len + 1);
	@memmove(recipeItems[0..inputs.len], inputs);
	recipeItems[inputs.len] = zon.getChild("output");
	defer allocator.free(recipeItems);

	const itemCombos = try generateItemCombos(allocator, recipeItems);
	defer itemCombos.deinit();
	for(itemCombos.items) |itemCombo| {
		defer allocator.free(itemCombo);
		const parsedInputs = itemCombo[0 .. itemCombo.len - 1];
		const output = itemCombo[itemCombo.len - 1];
		const recipe = Recipe{
			.sourceItems = list.allocator.alloc(BaseItemIndex, parsedInputs.len),
			.sourceAmounts = list.allocator.alloc(u16, parsedInputs.len),
			.resultItem = output.item.?.baseItem,
			.resultAmount = output.amount,
		};
		for(parsedInputs, 0..) |input, i| {
			recipe.sourceItems[i] = input.item.?.baseItem;
			recipe.sourceAmounts[i] = input.amount;
		}
		list.append(recipe);
		if(zon.get(bool, "reversible", false)) {
			if(recipe.sourceItems.len == 1) {
				var reversedRecipe = Recipe{
					.sourceItems = list.allocator.alloc(BaseItemIndex, 1),
					.sourceAmounts = list.allocator.alloc(u16, 1),
					.resultItem = recipe.sourceItems[0],
					.resultAmount = recipe.sourceAmounts[0],
				};
				reversedRecipe.sourceItems[0] = recipe.resultItem;
				reversedRecipe.sourceAmounts[0] = recipe.resultAmount;
				list.append(reversedRecipe);
			} else {
				return error.InvalidReversibleRecipe;
			}
		}
	}
}
