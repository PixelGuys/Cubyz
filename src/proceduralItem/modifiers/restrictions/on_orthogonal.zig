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
	const gridSize: i32 = proceduralItem.materialGrid.len - 1;
	const lowBound = -gridSize;
	const highBound = gridSize;
	var i = lowBound;
	while (i <= highBound) : (i += 1) {
		const checkedX = x + (i - gridSize);
		const checkedY = y + (0 - gridSize);
		if ((proceduralItem.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
	}
	i = lowBound;
	while (i <= highBound) : (i += 1) {
		const checkedX = x + (0 - gridSize);
		const checkedY = y + (i - gridSize);
		if (i != 0) { // prevents double counting itself
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
	outString.print("if there is {} .{s} on orthogonal lines", .{self.amount, self.tag.getName()});
}
