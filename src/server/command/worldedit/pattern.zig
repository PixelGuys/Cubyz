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
	var totalWeight: usize = 0;

	var weightedEntries: ListUnmanaged(struct {block: Block, weight: usize}) = .{};
	defer weightedEntries.deinit(main.stackAllocator);

	while(specifiers.next()) |specifier| {
		var iterator = std.mem.splitScalar(u8, specifier, '%');

		const first = iterator.next();
		const second = iterator.next();

		if(iterator.peek() != null) {
			return error.PatternSyntaxError;
		}
		if(second) |blockId| {
			if(first) |weight| {
				const block = main.blocks.parseBlock(blockId);
				const blockWeight = try std.fmt.parseInt(usize, weight, 10);
				totalWeight += blockWeight;
				weightedEntries.append(main.stackAllocator, .{ .block = block, .weight = blockWeight });
				continue;

			} else return error.PatternSyntaxError;
		}
		if(first) |blockId| {
			const block = main.blocks.parseBlock(blockId);
			totalWeight += 1;
			weightedEntries.append(main.stackAllocator, .{ .block = block, .weight = 1 });

		} else return error.PatternSyntaxError;
	}

	const entries = allocator.alloc(Entry, weightedEntries.items.len);
	for(weightedEntries.items, 0..) |entry, i| {
		entries[i] = .{ .block = entry.block, .chance = @as(f32, @floatFromInt(entry.weight)) / @as(f32, @floatFromInt(totalWeight)) };
	}

	return .{ .blocks = .init(allocator, entries) };
}

pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
	self.blocks.deinit(allocator);
}