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
	checkArray: ZonElement,
	outputString: []const u8,
};

fn getIndexInCheckArray(relativePosition: Vec2i, gridsize: i32) usize {
	const centerOffset = @divFloor(gridsize, 2);

	const arrayIndexX = relativePosition[0] + centerOffset;
	const arrayIndexY = relativePosition[1] + centerOffset;
	return @as(usize, @intCast((arrayIndexX*gridsize + arrayIndexY)));
}

pub fn satisfied(self: *const Arbritrary, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	std.log.default_level("AAAAAAAAAAAAAAAA: total array size is {}", .{self.checkArray.toSlice().len});
	const arraySizeCheck: f32 = @sqrt(@floatFromInt(self.checkArray.toSlice().len));
	if (@mod(arraySizeCheck, 1.0) != 0) {
		std.log.err("array size is not a perfect square: not counting arbitrary restriction: side length is {}", .{arraySizeCheck});
		return false;
	}
	if (@mod(arraySizeCheck, 2.0) != 1) {
		std.log.err("array size is not odd: not counting arbitrary restriction: {}", .{arraySizeCheck});
		return false;
	}
	const arraySizeSideLength: i32 = @intFromFloat(arraySizeCheck);

	var slotInfos = main.utils.CircularBufferQueue(bool).init(main.stackAllocator, 32);
	defer slotInfos.deinit();
	for (self.checkArray.toSlice()) |zonValue| {
		if (zonValue.as(usize) == null) continue;
		slotInfos.pushBack(((zonValue.as(usize) orelse 0) != 0));
	}
	
	const arrayBounds = @divFloor(arraySizeSideLength, 2);
	var dx = -arrayBounds;
	var dy = arrayBounds; // writen like this so that the array is read in reading order left to right, top to bottom
	std.log.default_level("full item test | {}", .{arrayBounds});
	while (dx <= arrayBounds) : (dx += 1) {
		while (dy >= -arrayBounds) : (dy -= 1) {
			if (!(slotInfos.popFront() orelse false)) continue;
			std.log.default_level("Starting tag test {} | {}", .{dx, dy});
			if ((proceduralItem.getItemAt(x + dx, y + dy) orelse continue).hasTag(self.tag)) continue;
			std.log.default_level("counted item {} | {}", .{dx, dy});
			count += 1;
		}
	}

	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Arbritrary {
	const result = allocator.create(Arbritrary);
	std.log.default_level("loaded array size {}", .{zon.getChild("checkArray").toSlice().len});
	result.* = .{
		.tag = main.Tag.find(zon.get(?[]const u8, "tag", null) orelse blk: {
			std.log.err("Missing tag field for encased restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount", 1),
		.checkArray = zon.getChild("checkArray"),
		.outputString = (zon.get(?[]const u8, "outputString", null) orelse blk: {
			std.log.err("Missing field for the output string.", .{});
			break :blk "not specified";
		}),
	};
	return result;
}

pub fn printTooltip(self: *const Arbritrary, outString: *main.ListManaged(u8)) void {
	outString.print("{s}", .{self.outputString});
}
