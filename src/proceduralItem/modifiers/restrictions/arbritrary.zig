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
	checkArray: ZonElement,
	outputString: []const u8
};

fn getIndexInCheckArray(relativePosition: Vec2i, gridsize: comptime_int) usize {
	const centerOffset = @floor(gridsize/2);

	const arrayIndexX = relativePosition[0] + centerOffset;
	const arrayIndexY = relativePosition[1] + centerOffset;
	return @as(usize, @intCast((arrayIndexX*gridsize + arrayIndexY)));
}

pub fn satisfied(self: *const Arbritrary, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	const arraySize = @sqrt(self.checkArray.len);
	if (arraySize%1 != 0) {
		std.log.err("array size is not a perfect square: not counting arbitrary restriction: {}", .{self.tag});
		return false;
	}

	var slotInfos: [self.checkArray.len]bool = @splat(false);
	for (self.checkArray.toSlice(), 0..) |zonDisabled, i| {
		slotInfos[i] = (zonDisabled.as(usize) orelse 0) != 0;
	}
	
	for ([_]i32{-1, 0, 1}) |dx| {
		for ([_]i32{-1, 0, 1}) |dy| {
			const relativePosition: Vec2i = .{dx, dy};
			if (!slotInfos[getIndexInCheckArray(relativePosition, arraySize)]) continue;
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
		.checkArray = zon.getChild("checkArray"),
		.outputString = main.Tag.find(zon.get(?[]const u8, "outputString", null) orelse blk: {
			std.log.err("Missing field for the output string.", .{});
			break :blk "not specified";
		}),
	};
	return result;
}

pub fn printTooltip(self: *const Arbritrary, outString: *main.ListManaged(u8)) void {
	outString.print("{}", .{self.outputString});
}
