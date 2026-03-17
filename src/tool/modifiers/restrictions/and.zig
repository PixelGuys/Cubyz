const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const And = struct {
	children: []ModifierRestriction,
};

pub fn satisfied(self: *const And, tool: *const Tool, x: i32, y: i32) bool {
	for(self.children) |child| {
		if(!child.satisfied(tool, x, y)) return false;
	}
	return true;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const And {
	const result = allocator.create(And);
	const childrenZon = zon.getChild("children").toSlice();
	result.children = allocator.alloc(ModifierRestriction, childrenZon.len);
	for(result.children, childrenZon) |*child, childZon| {
		child.* = ModifierRestriction.loadFromZon(allocator, childZon);
	}
	return result;
}

pub fn printTooltip(self: *const And, outString: *main.List(u8)) void {
	outString.append('(');
	for(self.children, 0..) |child, i| {
		if(i != 0) outString.appendSlice(" and ");
		child.printTooltip(outString);
	}
	outString.append(')');
}
