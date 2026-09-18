const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const OnOrthogonal = struct {
	tag: main.Tag,
	amount: usize,
};

pub fn satisfied(self: *const OnOrthogonal, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	const gridSize: usize = proceduralItem.materialGrid.len - 1;
	const rangeChecked: i32 = @intCast(gridSize);
	const lowBound = 0;
	const highBound = rangeChecked*2 + 1;
	for (lowBound..highBound) |dx| {
		const iterator: i32 = @intCast(dx);
		const checkedX = x + (iterator - rangeChecked);
		const checkedY = y + (0 - rangeChecked);
		if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
	}
	for (lowBound..highBound) |dy| {
		const iterator: i32 = @intCast(dy);
		const checkedX = x + (0 - rangeChecked);
		const checkedY = y + (iterator - rangeChecked);
		if (dy != 0) { // prevents double counting
			if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
		}
	}
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const OnOrthogonal {
	const result = allocator.create(OnOrthogonal);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag") orelse blk: {
			std.log.err("Missing tag field for on diagonal restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount") orelse 8,
	};
	return result;
}

pub fn printTooltip(self: *const OnOrthogonal, outString: *main.ListManaged(u8)) void {
	outString.print("{} .{s} {s}", .{self.amount, self.tag.getName(), "on orthoganal axis"});
}
