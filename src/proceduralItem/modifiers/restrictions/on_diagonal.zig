const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const OnDiagonal = struct {
	tag: main.Tag,
	amount: usize,
};

pub fn satisfied(self: *const OnDiagonal, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	const gridSize: usize = proceduralItem.materialGrid.len - 1;
	const rangeChecked: i32 = gridSize;
	const lowBound = 0;
	const highBound = rangeChecked*2 + 1;
	for (lowBound..highBound) |i| {
		const iterator: i32 = @intCast(i);
		const checkedX: i32 = x + (iterator - rangeChecked);
		const checkedY: i32 = y + (iterator - rangeChecked);
		if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
	}
	for (lowBound..highBound) |i| {
		const iterator: i32 = @intCast(i);
		const checkedX: i32 = x + (iterator - rangeChecked);
		const checkedY: i32 = y + (iterator - rangeChecked);
		if (i != 0) { // prevents double counting
			if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
		}
	}

	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const OnDiagonal {
	const result = allocator.create(OnDiagonal);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag") orelse blk: {
			std.log.err("Missing tag field for on diagonal restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount") orelse 8,
	};
	return result;
}

pub fn printTooltip(self: *const OnDiagonal, outString: *main.ListManaged(u8)) void {
	outString.print("{} .{s} {s}", .{self.amount, self.tag.getName(), "on diagonal axis"});
}
