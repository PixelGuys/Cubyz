const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { strength: f32, pad: u96 = undefined };

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = std.math.clamp(zon.get(f32, "strength") orelse 0, 0, 1)};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.strength = std.math.hypot(data1.strength, data2.strength)};
}

pub fn changeProceduralItemParameters(proceduralItem: *ProceduralItem, data: Data, restrictionPower: f32) void {
	proceduralItem.setProperty(.swingSpeed, proceduralItem.getProperty(.swingSpeed)*(1 + data.strength*restrictionPower));
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	outString.print("#9fffde**Light**#808080 *Increases swing speed by **{d:.0}%", .{data.strength*100});
}
