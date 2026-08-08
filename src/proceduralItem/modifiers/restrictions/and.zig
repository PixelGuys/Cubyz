const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;
const ModifierRestrictionOutput = main.items.ModifierRestrictionOutput;

const And = struct {
	children: []ModifierRestriction,
};

pub fn satisfied(self: *const And, proceduralItem: *const ProceduralItem, x: i32, y: i32) ModifierRestrictionOutput {
	var combinedIsSatisfied = true;
	var combinedtotalCountedItems: usize = 0;
	var combinedTotalItemsChecked: usize = 0;
	var combinedModifierPower: f32 = 0;
	for (self.children) |child| {
		const childValues: ModifierRestrictionOutput = child.satisfied(proceduralItem, x, y);
		if (!childValues.ifSatisfied) combinedIsSatisfied = false;
		combinedtotalCountedItems += childValues.totalCountedItems;
		combinedTotalItemsChecked += childValues.totalItemsChecked;
		combinedModifierPower = std.math.hypot(combinedModifierPower, childValues.modifierPower);
	}
	return .{
		.ifSatisfied = combinedIsSatisfied,
		.totalItemsChecked = combinedTotalItemsChecked,
		.totalCountedItems = combinedtotalCountedItems,
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
