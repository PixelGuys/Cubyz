const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec2i = vec.Vec2i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const ConductedWith = struct {
	sourceTag: main.Tag,
	conductorTag: main.Tag,
	amount: usize,
};

fn addAdjactentSlotsToQueue(queue: *main.utils.CircularBufferQueue(Vec2i), x: i32, y: i32) void {
	queue.pushBack(Vec2i{x + 1, y});
	queue.pushBack(Vec2i{x - 1, y});
	queue.pushBack(Vec2i{x, y + 1});
	queue.pushBack(Vec2i{x, y - 1});
}

pub fn satisfied(self: *const ConductedWith, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var count: usize = 0;
	count = 0;
	// init array to mark already searched blocks.
	const gridSideLength: usize = @floor(@sqrt(@as(f32, @floatFromInt(proceduralItem.craftingGrid.len))));
	var slotsChecked: [gridSideLength][gridSideLength]bool = @splat(@splat(false));

	// queue for breadth-first search
	var queue = main.utils.CircularBufferQueue(Vec2i).init(main.stackAllocator, 32);
	defer queue.deinit();
	slotsChecked[@intCast(x)][@intCast(y)] = true;
	addAdjactentSlotsToQueue(&queue, x, y);
	while (queue.popFront()) |slotPos| {
		if (slotPos[0] < 0) continue;
		if (slotPos[0] > gridSideLength) continue;
		if (slotPos[1] < 0) continue;
		if (slotPos[1] > gridSideLength) continue;
		if ((slotPos[0] == x) and (slotPos[1] == y)) continue; // we ingore the tags of the parent item
		const xPos: usize = @intCast(slotPos[0]);
		const yPos: usize = @intCast(slotPos[1]);
		if (slotsChecked[xPos][yPos]) continue;
		slotsChecked[xPos][yPos] = true;
		const checkedItem = proceduralItem.getItemAt(slotPos[0], slotPos[1]) orelse continue;
		if (checkedItem.hasTag(self.sourceTag)) count += 1;
		if (checkedItem.hasTag(self.conductorTag)) addAdjactentSlotsToQueue(&queue, slotPos[0], slotPos[1]);
	}
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const ConductedWith {
	const result = allocator.create(ConductedWith);
	result.* = .{
		.sourceTag = main.Tag.find(zon.get([]const u8, "sourceTag") orelse blk: {
			std.log.err("Missing source tag field for conductedWith restriction.", .{});
			break :blk "not specified";
		}),
		.conductorTag = main.Tag.find(zon.get([]const u8, "conductorTag") orelse blk: {
			std.log.err("Missing conductor tag field for conductedWith restriction.", .{});
			break :blk "not specified";
		}),
		.amount = zon.get(usize, "amount") orelse 8,
	};
	return result;
}

pub fn printTooltip(self: *const ConductedWith, outString: *main.ListManaged(u8)) void {
	outString.print("conducted with {s} to {} .{s}", .{self.conductorTag.getName(), self.amount, self.sourceTag.getName()});
}
