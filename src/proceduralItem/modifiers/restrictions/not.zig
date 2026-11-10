const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const Not = struct {
	child: ModifierRestriction,
};

pub fn satisfied(self: *const Not, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	return !self.child.satisfied(proceduralItem, x, y);
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const Not {
	const result = allocator.create(Not);
	result.* = .{
		.child = ModifierRestriction.loadFromZon(allocator, zon.getChild("child")),
	};
	return result;
}

pub fn printTooltip(self: *const Not, outString: *main.ListManaged(u8), options: main.items.ModifierRestriction.PrintOptions) void {
	var newOptions = options;
	newOptions.negated = !options.negated;
	self.child.printTooltip(outString, newOptions);
}
