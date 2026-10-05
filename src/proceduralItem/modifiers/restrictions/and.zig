const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const ProceduralItem = main.items.ProceduralItem;
const ZonElement = main.ZonElement;

const And = struct {
	children: []ModifierRestriction,
};

pub fn satisfied(self: *const And, proceduralItem: *const ProceduralItem, x: i32, y: i32) bool {
	for (self.children) |child| {
		if (!child.satisfied(proceduralItem, x, y)) return false;
	}
	return true;
}

pub fn printCheckedGrid(self: *const And, givenGrid: [25]?main.items.BaseItemIndex, x: i32, y: i32) [25]main.items.Checked {
	var checkedGrid: [25]main.items.Checked = @splat(.notChecked);
	for (0..25) |i| {
		var newTag: main.items.Checked = .always;
		for (self.children) |child| {
			const searchedCheckedGrid = child.printCheckedGrid(givenGrid, x, y)[i];
			switch (searchedCheckedGrid) {
				.invalidTag => {
					newTag = .invalidTag;
					break;
				},
				.validTag => if (newTag != .invalidTag) {
					newTag = .validTag;
				},
				.notChecked => if ((newTag != .validTag) and (newTag != .invalidTag)) {
					newTag = .invalidTag;
				},
				.always => if (newTag == .always) {
					newTag = .always;
				},
			}
		}
		checkedGrid[i] = newTag;
	}
	return checkedGrid;
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
