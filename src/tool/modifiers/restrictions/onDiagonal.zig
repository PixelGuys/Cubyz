const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ModifierRestriction = main.items.ModifierRestriction;
const Tool = main.items.Tool;
const ZonElement = main.ZonElement;

const OnDiagonal = struct {
    tag: main.Tag,
    amount: usize,
    range: usize,
};

pub fn satisfied(self: *const OnDiagonal, tool: *const Tool, x: i32, y: i32) bool {
    var count: usize = 0;
    const gridSize: usize = @sqrt(tool.craftingGrid.len);
    var rangeChecked: usize = 0;
    if (self.range > gridSize) {
        rangeChecked = gridSize;
    } else {
        if (self.range == 0) {
            rangeChecked = gridSize;
        } else {
            rangeChecked = self.range;
        }
    }
    const lowBound = 0;
    const highBound = rangeChecked * 2 + 1;
    for (lowBound..highBound) |dx| {
        const checkedX = x + @as(i32, @intCast(dx - rangeChecked));
        const checkedY = y + @as(i32, @intCast(dx - rangeChecked));
        if ((tool.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
    }
    for (lowBound..highBound) |dx| {
        const checkedX = x + @as(i32, @intCast(dx - rangeChecked));
        const checkedY = y - @as(i32, (@intCast(dx - rangeChecked)));
        if (!(dx == 0)) {
            if ((tool.getItemAt(checkedX, checkedY) orelse continue).hasTag(self.tag)) count += 1;
        }
    }
    return count >= self.amount;
}

pub fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) *const OnDiagonal {
    const result = allocator.create(OnDiagonal);
    result.* = .{
        .tag = main.Tag.find(zon.get([]const u8, "tag", "not specified")),
        .amount = zon.get(usize, "amount", 8),
        .range = zon.get(usize, "range", 0),
    };
    return result;
}

pub fn printTooltip(self: *const OnDiagonal, outString: *main.List(u8)) void {
    if (self.range == 0) {
        outString.print("{} .{s} {s}", .{ self.amount, self.tag.getName(), "on diagonal axis" });
    } else {
        outString.print("{} .{s} {s} {}", .{ self.amount, self.tag.getName(), "in diagonal range", self.range });
    }
}
