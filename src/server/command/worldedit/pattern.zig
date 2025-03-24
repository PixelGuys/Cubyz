const std = @import("std");

const main = @import("root");
const AliasTable = main.utils.AliasTable;
const Block = main.blocks.Block;
const ListUnmanaged = main.ListUnmanaged;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

blocks: AliasTable(Entry),

const Entry = struct {
	block: Block,
	chance: f32,
};

pub fn initFromString(allocator: NeverFailingAllocator, source: []const u8) !@This() {
	var specifiers = std.mem.splitScalar(u8, source, ',');
	var totalWeight: f64 = 0;

	var weightedEntries: ListUnmanaged(struct {block: Block, weight: f64}) = .{};
	defer weightedEntries.deinit(main.stackAllocator);

	while(specifiers.next()) |specifier| {
		var iterator = std.mem.splitScalar(u8, specifier, '%');

		// This code first assumes that specifier has form `weight%addon:block` and only if parsing of weight fails it tries to parse it as `addon:block`.
		var weight: f64 = undefined;
		var block = main.blocks.parseBlock(iterator.rest());

		const first = iterator.first();

		weight = std.fmt.parseFloat(f64, first) catch blk: {
			// To distinguish somehow between mistyped numeric values and actual block IDs we check for addon name separator.
			if(!std.mem.containsAtLeastScalar(u8, first, 1, ":")) return error.PatternSyntaxError;
			block = main.blocks.parseBlock(first);
			break :blk 1.0;
		};
		totalWeight += weight;
		weightedEntries.append(main.stackAllocator, .{.block = block, .weight = weight});
	}

	const entries = allocator.alloc(Entry, weightedEntries.items.len);
	for(weightedEntries.items, 0..) |entry, i| {
		entries[i] = .{.block = entry.block, .chance = @as(f32, @floatFromInt(entry.weight))/@as(f32, @floatFromInt(totalWeight))};
	}

	return .{.blocks = .init(allocator, entries)};
}

pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
	self.blocks.deinit(allocator);
	allocator.free(self.blocks.items);
}
