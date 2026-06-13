const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec2i = vec.Vec2i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const Arbritrary = struct {
	tag: main.Tag,
	amount: usize,
};

fn getIndexInCheckArray(relativePosition: Vec2i, checkRange: comptime_int) usize {
	const checkLength = checkRange*2 + 1;

	const arrayIndexX = relativePosition[0] + checkRange;
	const arrayIndexY = relativePosition[1] + checkRange;
	return @as(usize, @intCast((arrayIndexX*checkLength + arrayIndexY)));
}

pub fn satisfied(self: *const Arbritrary, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	for ([_]i32{-1, 0, 1}) |dx| {
		for ([_]i32{-1, 0, 1}) |dy| {
			if ((proceduralItem.getItemAt(x + dx, y + dy) orelse continue).hasTag(self.tag)) count += 1;
		}
	}
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Arbritrary {
	const result = allocator.create(Arbritrary);
	result.* = .{
		.tag = main.Tag.find(zon.get(?[]const u8, "tag", null) orelse blk: {
			std.log.err("Missing tag field for encased restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount", 8),
	};
	return result;
}

pub fn printTooltip(self: *const Arbritrary, outString: *main.ListManaged(u8)) void {
	outString.print("encased in {} .{s}", .{self.amount, self.tag.getName()});
}
