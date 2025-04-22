const std = @import("std");

const main = @import("main");
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
	var totalWeight: f32 = 0;

	var weightedEntries: ListUnmanaged(struct {block: Block, weight: f32}) = .{};
	defer weightedEntries.deinit(main.stackAllocator);

	while(specifiers.next()) |specifier| {
		var iterator = std.mem.splitScalar(u8, specifier, '%');

		var weight: f32 = undefined;
		var block = main.blocks.parseBlock(iterator.rest());

		const first = iterator.first();

		weight = std.fmt.parseFloat(f32, first) catch blk: {
			// To distinguish somehow between mistyped numeric values and actual block IDs we check for addon name separator.
			if(!std.mem.containsAtLeastScalar(u8, first, 1, ':')) return error.PatternSyntaxError;
			block = main.blocks.parseBlock(first);
			break :blk 1.0;
		};
		totalWeight += weight;
		weightedEntries.append(main.stackAllocator, .{.block = block, .weight = weight});
	}

	const entries = allocator.alloc(Entry, weightedEntries.items.len);
	for(weightedEntries.items, 0..) |entry, i| {
		entries[i] = .{.block = entry.block, .chance = entry.weight/totalWeight};
	}

	return .{.blocks = .init(allocator, entries)};
}

pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
	self.blocks.deinit(allocator);
	allocator.free(self.blocks.items);
}
