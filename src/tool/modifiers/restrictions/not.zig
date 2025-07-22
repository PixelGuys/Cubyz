const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const Not = struct {
	child: ModifierRestriction,
};

pub fn satisfied(self: *const Not, tool: *const Tool, x: i32, y: i32) bool {
	return !self.child.satisfied(tool, x, y);
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Not {
	const result = allocator.create(Not);
	result.* = .{
		.child = ModifierRestriction.loadFromZon(allocator, zon.getChild("child")),
	};
	return result;
}

pub fn printTooltip(self: *const Not, outString: *main.List(u8)) void {
	outString.appendSlice("not ");
	self.child.printTooltip(outString);
}
