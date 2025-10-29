const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

pub fn satisfied(_: *const anyopaque, _: *const Tool, _: i32, _: i32) bool {
	return true;
}

pub fn loadFromZon(_: NeverFailingAllocator, _: ZonElement) *const anyopaque {
	return undefined;
}

pub fn printTooltip(_: *const anyopaque, outString: *main.List(u8)) void {
	outString.appendSlice("always");
}
