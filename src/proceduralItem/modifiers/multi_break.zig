const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;
const Vec3i = @Vector(3, i32);

pub const Data = packed struct(u128) { width: i32,  depth: i32, pad: u64 = undefined };

pub const priority = 1000;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.width = @max(1, zon.get(i32, "width", 1)), .depth = @max(1, zon.get(i32, "depth", 1))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.width = @max(data1.width, data2.width), .depth = @max(data1.depth, data2.depth)};
}

pub fn changeMiningArea(data: Data) Vec3i {
	return Vec3i{data.width, data.width, data.depth};
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.print("#800000**Multi-Break**#808080 *Breaks in a {d:.0}x{d:.0}x{d:.0} area **", .{data.width*2-1, data.width*2-1, data.depth});
}
