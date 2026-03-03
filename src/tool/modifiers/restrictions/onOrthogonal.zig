const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const Encased = struct {
	tag: main.Tag,
	amount: usize,
	range: usize,
};

pub fn satisfied(self: *const Encased, tool: *const Tool, x: i32, y: i32) bool {
	var count: usize = 0;
	const lowBound = 0;
	const highBound = self.range*2 + 1;
	for (lowBound..highBound) |dx| {
		const checkedX = x + @as(i32, @intCast(dx - self.range));
		const checkedY = y + @as(i32,(@intCast(0 - self.range)));
		if ((tool.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
	}
	for (lowBound..highBound) |dy| {
		const checkedX = x + @as(i32, @intCast(0 - self.range));
		const checkedY = y + @as(i32,(@intCast(dy - self.range)));
		if (!(dy == 0)) {
			if ((tool.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
		}
	}
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Encased {
	const result = allocator.create(Encased);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag", "not specified")),
		.amount = zon.get(usize, "amount", 8),
		.range = zon.get(usize, "range", 5),
	};
	return result;
}

pub fn printTooltip(self: *const Encased, outString: *main.List(u8)) void {
	if (self.range < 5) {
		outString.print("{} .{s} {s} {}", .{self.amount, self.tag.getName(),"in orthoganal range", self.range});
	} else {
		outString.print("{} .{s} {s}", .{self.amount, self.tag.getName(),"on orthoganal axis"});
	}
}
