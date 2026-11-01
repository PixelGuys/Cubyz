const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

pub fn satisfied(_: *const anyopaque, _: *const ProceduralItem, _: i32, _: i32) bool {
	return true;
}

pub fn loadFromZon(_: NeverFailingAllocator, _: ZonElement) *const anyopaque {
	return undefined;
}

pub fn printTooltip(_: *const anyopaque, outString: *main.ListManaged(u8), options: main.items.ModifierRestriction.PrintOptions) void {
	if (options.negated) {
		outString.appendSlice("never");
	} else {
		outString.appendSlice("always");
	}
}
