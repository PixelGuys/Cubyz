const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const OnTopOf = struct {
	tag: main.Tag,
};

pub fn satisfied(self: *const OnTopOf, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	var isOnTopOfTag: bool = false;

	if (proceduralItem.checkForTagAt(x, y, self.tag) orelse false) isOnTopOfTag = true;

	return isOnTopOfTag;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const OnTopOf {
	const result = allocator.create(OnTopOf);
	result.* = .{
		.tag = main.Tag.find(zon.get([]const u8, "tag", "not specified")),
	};
	return result;
}

pub fn printTooltip(self: *const OnTopOf, outString: *main.List(u8)) void {
	outString.print("on top of .{s}", .{self.tag.getName()});
}
