const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;
const ModifierRestrictionOutput = main.items.ModifierRestrictionOutput;

const And = struct {
	child: ModifierRestriction,
};

pub fn satisfied(self: *const And, proceduralItem: *const ProceduralItem, x: i32, y: i32) ModifierRestrictionOutput {
	const childValues = self.child.satisfied(proceduralItem, x, y);
	const loopCount = childValues.totalCountedItems;
	var combinedModifierPower: f32 = 0;
	for (0..loopCount) |i| {
		_ = i;
		combinedModifierPower = std.math.hypot(combinedModifierPower, 1);
	}
	return .{
		.ifSatisfied = childValues.ifSatisfied, 
		.totalItemsChecked = childValues.totalItemsChecked, 
		.totalCountedItems = childValues.totalCountedItems, 
		.modifierPower = combinedModifierPower,
	};
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const And {
	const result = allocator.create(And);
	const childrenZon = zon.getChild("children").toSlice();
	result.children = allocator.alloc(ModifierRestriction, childrenZon.len);
	for (result.children, childrenZon) |*child, childZon| {
		child.* = ModifierRestriction.loadFromZon(allocator, childZon);
	}
	return result;
}

pub fn printTooltip(self: *const And, outString: *main.ListManaged(u8)) void {
	outString.append('(');
	for (self.children, 0..) |child, i| {
		if (i != 0) outString.appendSlice(" and ");
		child.printTooltip(outString);
	}
	outString.append(')');
}
