const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;
const ModifierRestrictionOutput = main.items.ModifierRestrictionOutput;

pub fn satisfied(_: *const anyopaque, _: *const ProceduralItem, _: i32, _: i32) ModifierRestrictionOutput {
	return .{
		.ifSatisfied = true,
		.totalItemsChecked = 0,
		.totalCountedItems = 0,
		.modifierPower = 1,
	};
}

pub fn loadFromZon(_: NeverFailingAllocator, _: ZonElement) *const anyopaque {
	return undefined;
}

pub fn printTooltip(_: *const anyopaque, outString: *main.ListManaged(u8)) void {
	outString.appendSlice("always");
}
