const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const On_diagonal = struct {
	tag: main.Tag,
	amount: usize,
	range: ?usize,
};

pub fn satisfied(self: *const On_diagonal, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	const gridSize: usize = proceduralItem.materialGrid.len;
	const rangeChecked = @min(self.range orelse (gridSize-1), (gridSize-1));
	const lowBound = 0;
	const highBound = rangeChecked*2 + 1;
	for (lowBound..highBound) |dx| {
		const checkedX = x + @as(i32, @intCast(dx - rangeChecked));
		const checkedY = y + @as(i32, @intCast(dx - rangeChecked));
		if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
	}
	for (lowBound..highBound) |dx| {
		const checkedX = x + @as(i32, @intCast(dx - rangeChecked));
		const checkedY = y - @as(i32, (@intCast(dx - rangeChecked)));
		if (dx != 0) {
			if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
		}
	}

	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const On_diagonal {
	const result = allocator.create(On_diagonal);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag", "not specified")),
		.amount = zon.get(usize, "amount", 8),
		.range = zon.get(?usize, "range", null),
	};
	return result;
}

pub fn printTooltip(self: *const On_diagonal, outString: *main.List(u8)) void {
	if (self.range == null) {
		outString.print("{} .{s} {s}", .{self.amount, self.tag.getName(), "on diagonal axis"});
	} else {
		outString.print("{} .{s} {s} {?}", .{self.amount, self.tag.getName(), "in diagonal range", self.range});
	}
}
