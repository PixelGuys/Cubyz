const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { strength: f32, pad: u96 = undefined };

pub const priority = 1000;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = @max(1, zon.get(f32, "strength", 1))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.strength = @min(data1.strength, data2.strength)};
}

pub fn hasModifier() bool {
	return true;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.print("#800000**Multi-Break**#808080 *Breaks in a 3x3 plane **{d:.0}", .{data.strength});
}
