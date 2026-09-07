const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const Encased = struct {
	tag: main.Tag,
	amount: usize,
};

pub fn satisfied(self: *const Encased, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	for ([_]i32{-1, 0, 1}) |dx| {
		for ([_]i32{-1, 0, 1}) |dy| {
			if ((ProceduralItem.getItemAt(x + dx, y + dy, proceduralItem.craftingGrid) orelse continue).hasTag(self.tag)) count += 1;
		}
	}
	return count >= self.amount;
}

pub fn printCheckedGrid(self: *const Encased, givenGrid: [25]?main.items.BaseItemIndex, x: i32, y: i32) [25]main.items.Checked {
	var checkedGrid: [25]main.items.Checked = @splat(.notChecked);
	for ([_]i32{-1, 0, 1}) |dx| {
		for ([_]i32{-1, 0, 1}) |dy| {
			ProceduralItem.getCheckedAt(x + dx, y + dy, givenGrid, self.tag, &checkedGrid);
		}
	}
	return checkedGrid;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Encased {
	const result = allocator.create(Encased);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag") orelse blk: {
			std.log.err("Missing tag field for encased restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount") orelse 8,
	};
	return result;
}

pub fn printTooltip(self: *const Encased, outString: *main.ListManaged(u8)) void {
	outString.print("encased in {} .{s}", .{self.amount, self.tag.getName()});
}
