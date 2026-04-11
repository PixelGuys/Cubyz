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

pub fn printTooltip(_: *const anyopaque, outString: *main.List(u8)) void {
	outString.appendSlice("always");
}
