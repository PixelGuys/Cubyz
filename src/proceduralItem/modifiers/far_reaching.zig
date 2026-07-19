const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { multStrength: f32, flatStrength: f32, pad: u64 = undefined };

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.multStrength = @max(0, zon.get(f32, "multStrength") orelse 0),
		.flatStrength = @max(0, zon.get(f32, "flatStrength") orelse 0),
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{
		.multStrength = std.math.hypot(data1.multStrength, data2.multStrength),
		.flatStrength = std.math.hypot(data1.flatStrength, data2.flatStrength),
	};
}

pub fn changeBlockRange(data: Data) struct {f32, f32} {
	return .{data.flatStrength, data.multStrength};
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	if (data.multStrength != 0 and data.flatStrength != 0) outString.print("#00f870**Far Reaching**#808080 *Increases range by **{d:.0}%** and **+{d:.0}**", .{data.multStrength*100, data.flatStrength});
	if (data.multStrength != 0 and data.flatStrength == 0) outString.print("#00f870**Far Reaching**#808080 *Increases range by **{d:.0}%**", .{data.multStrength*100});
	if (data.multStrength == 0 and data.flatStrength != 0) outString.print("#00f870**Far Reaching**#808080 *Increases range by **+{d:.0}**", .{data.flatStrength});
	if (data.multStrength == 0 and data.flatStrength == 0) outString.print("#ff0000**Far Reaching did not find any multStrength and Flatstrength**", .{});
}
