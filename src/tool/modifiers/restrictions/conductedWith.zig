const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec2i = vec.Vec2i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const Encased = struct {
	sourceTag: main.Tag,
	conductorTag: main.Tag,
	amount: usize,
};

fn getIndexInCheckArray(relativePosition: Vec2i, checkRange: comptime_int) usize {
	const checkLength = checkRange*2 + 1;

	const arrayIndexX = relativePosition[0] + checkRange;
	const arrayIndexY = relativePosition[1] + checkRange;
	return @as(usize, @intCast((arrayIndexX*checkLength + arrayIndexY)));
}

pub fn satisfied(self: *const Encased, tool: *const Tool, x: i32, y: i32) bool {
	var count: usize = 0;
	count = 0;
	// init array to mark already searched blocks.
	const checkRange = 5;
	const checkLength = checkRange*2 + 1;
	var checked: [checkLength*checkLength]bool = undefined;
	for (0..checkLength*checkLength) |i| {
		checked[i] = false;
	}

	// queue for breadth-first search
	var queue = main.utils.CircularBufferQueue(Vec2i).init(main.stackAllocator, 32);
	defer queue.deinit();

	queue.pushBack(Vec2i{1, 0});
	queue.pushBack(Vec2i{-1, 0});
	queue.pushBack(Vec2i{0, 1});
	queue.pushBack(Vec2i{0, -1});
	checked[getIndexInCheckArray(Vec2i{0, 0}, checkRange)] = true;

	while (queue.popFront()) |value| {
		if ((tool.getItemAt(x + value[0], y + value[1]) orelse continue).hasTag(self.sourceTag)) {

			// mark as checked
			if (checked[getIndexInCheckArray(value, checkRange)]) continue;
			count += 1;
			checked[getIndexInCheckArray(value, checkRange)] = true;
			if ((tool.getItemAt(x + value[0], y + value[1]) orelse continue).hasTag(self.conductorTag)) {

				// mark as checked
				if (checked[getIndexInCheckArray(value, checkRange)]) continue;
				checked[getIndexInCheckArray(value, checkRange)] = true;
				queue.pushBack(Vec2i{1 + value[0], 0 + value[1]});
				queue.pushBack(Vec2i{-1 + value[0], 0 + value[1]});
				queue.pushBack(Vec2i{0 + value[0], 1 + value[1]});
				queue.pushBack(Vec2i{0 + value[0], -1 + value[1]});
			}
		}
		if ((tool.getItemAt(x + value[0], y + value[1]) orelse continue).hasTag(self.conductorTag)) {

			// mark as checked
			if (checked[getIndexInCheckArray(value, checkRange)]) continue;
			checked[getIndexInCheckArray(value, checkRange)] = true;
			queue.pushBack(Vec2i{1 + value[0], 0 + value[1]});
			queue.pushBack(Vec2i{-1 + value[0], 0 + value[1]});
			queue.pushBack(Vec2i{0 + value[0], 1 + value[1]});
			queue.pushBack(Vec2i{0 + value[0], -1 + value[1]});
		}
	}
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Encased {
	const result = allocator.create(Encased);
	result.* = .{
		.sourceTag = main.Tag.find(zon.get([]const u8, "sourceTag", "not specified")),
		.conductorTag = main.Tag.find(zon.get([]const u8, "conductorTag", "not specified")),
		.amount = zon.get(usize, "amount", 8),
	};
	return result;
}

pub fn printTooltip(self: *const Encased, outString: *main.List(u8)) void {
	outString.print("conducted with .{s} .{s} {} .{s}", .{self.conductorTag.getName(), "to", self.amount, self.sourceTag.getName()});
}
