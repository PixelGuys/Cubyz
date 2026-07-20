const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;
const ModifierRestrictionOutput = main.items.ModifierRestrictionOutput;

const Encased = struct {
	tag: main.Tag,
	amount: usize,
};

pub fn satisfied(self: *const Encased, proceduralItem: *const ProceduralItem, x: i32, y: i32) ModifierRestrictionOutput {
	var count: usize = 0;
	for ([_]i32{-1, 0, 1}) |dx| {
		for ([_]i32{-1, 0, 1}) |dy| {
			if ((proceduralItem.getItemAt(x + dx, y + dy) orelse continue).hasTag(self.tag)) count += 1;
		}
	}
	return .{
		.ifSatisfied = count >= self.amount, 
		.totalItemsChecked = 9, 
		.totalCountedItems = count, 
		.modifierPower = 1,
	};
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Encased {
	const result = allocator.create(Encased);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag") orelse blk: {
			std.log.err("Missing tag field for encased restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount") orelse 0,
	};
	return result;
}

pub fn printTooltip(self: *const Encased, outString: *main.ListManaged(u8)) void {
	if (self.amount == 0) {
		outString.print("encased in .{s}", .{self.tag.getName()});
	} else {
		outString.print("encased in {} .{s}", .{self.amount, self.tag.getName()});
	}
}
