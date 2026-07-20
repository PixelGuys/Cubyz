const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;
const ModifierRestrictionOutput = main.items.ModifierRestrictionOutput;

const ForEach = struct {
	child: ModifierRestriction,
};

pub fn satisfied(self: *const ForEach, proceduralItem: *const ProceduralItem, x: i32, y: i32) ModifierRestrictionOutput {
	const childValues = self.child.satisfied(proceduralItem, x, y);
	const loopCount = childValues.totalCountedItems;
	var combinedModifierPower: f32 = 0;
	std.log.debug("loop count {}", .{loopCount});
	for (0..loopCount) |i| {
		_ = i;
		combinedModifierPower = std.math.hypot(combinedModifierPower, 1);
	}
	std.log.debug("restrictionPower {}", .{combinedModifierPower});
	return .{
		.ifSatisfied = childValues.ifSatisfied, 
		.totalItemsChecked = childValues.totalItemsChecked, 
		.totalCountedItems = childValues.totalCountedItems, 
		.modifierPower = combinedModifierPower,
	};
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const ForEach {
	const result = allocator.create(ForEach);
	result.* = .{
		.child = ModifierRestriction.loadFromZon(allocator, zon.getChild("child")),
	};
	return result;
}

pub fn printTooltip(self: *const ForEach, outString: *main.ListManaged(u8)) void {
	outString.appendSlice("for each ");
	self.child.printTooltip(outString);
}
