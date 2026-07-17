const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { multStrength: f32, flatStrength: f32, pad: u64 = undefined };

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.multStrength = std.math.clamp(zon.get(f32, "multStrength") orelse 0, 0, 1),
		.flatStrength = @max(0, zon.get(f32, "flatStrength") orelse 0),
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{
		.multStrength = 1.0 - 1.0/(1.0 + std.math.hypot(1.0/(1.0 - data1.multStrength) - 1.0, 1.0/(1.0 - data2.multStrength) - 1.0)),
		.flatStrength = 1.0 - 1.0/(1.0 + std.math.hypot(1.0/(1.0 - data1.flatStrength) - 1.0, 1.0/(1.0 - data2.flatStrength) - 1.0)),
		};
}

pub fn changeProceduralItemParameters(proceduralItem: *ProceduralItem, data: Data) void {
	proceduralItem.setProperty(.swingSpeed, @max(proceduralItem.getProperty(.damage) - data.flatStrength, 0)*(1 - data.multStrength));
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	outString.print("#ffcc30**Heavy**#808080 *Decreases swing speed by **{d:.0}%** and **-{d:.0}**", .{data.multStrength*100, data.flatStrength});
}
