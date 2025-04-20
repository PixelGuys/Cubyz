const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const Encased = struct {
	item: []const u8, // TODO: Use item tags instead
	amount: usize,
};

pub fn satisfied(self: *const Encased, tool: *const Tool, x: i32, y: i32) bool {
	var count: usize = 0;
	for([_]i32{-1, 0, 1}) |dx| {
		for([_]i32{-1, 0, 1}) |dy| {
			if(std.mem.eql(u8, (tool.getItemAt(x + dx, y + dy) orelse continue).id, self.item)) count += 1;
		}
	}
	std.log.debug("{} {}", .{count, self.amount});
	return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Encased {
	const result = allocator.create(Encased);
	result.* = .{
		.item = zon.get([]const u8, "item", "not specified"),
		.amount = zon.get(usize, "amount", 8),
	};
	return result;
}
