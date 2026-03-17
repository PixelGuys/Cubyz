const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const OnOrthogonal = struct {
	tag: main.Tag,
	amount: usize,
	range: usize,
};

pub fn satisfied(self: *const OnOrthogonal, tool: *const Tool, x: i32, y: i32) bool {
	var count: usize = 0;
	const gridSize: usize = tool.craftingGrid.len;
	const rangeChecked = @min(self.range orelse gridSize, gridSize);
	const lowBound = 0;
	const highBound = rangeChecked*2 + 1;
	for (lowBound..highBound) |dx| {
		const checkedX = x + @as(i32, @intCast(dx - rangeChecked));
		const checkedY = y + @as(i32, @intCast(0 - rangeChecked));
		if ((tool.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
	}
	for (lowBound..highBound) |dy| {
		const checkedX = x + @as(i32, @intCast(0 - rangeChecked));
		const checkedY = y + @as(i32, @intCast(dy - rangeChecked));
		if (dy != 0) {
			if ((tool.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
		}
	}
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const OnOrthogonal {
	const result = allocator.create(OnOrthogonal);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag", null)),
		.amount = zon.get(usize, "amount", 8),
		.range = zon.get(usize, "range", 0),
	};
	return result;
}

pub fn printTooltip(self: *const OnOrthogonal, outString: *main.List(u8)) void {
	if (self.range == 0) {
		outString.print("{} .{s} {s}", .{self.amount, self.tag.getName(), "on orthoganal axis"});
	} else {
		outString.print("{} .{s} {s} {}", .{self.amount, self.tag.getName(), "in orthoganal range", self.range});
	}
}
