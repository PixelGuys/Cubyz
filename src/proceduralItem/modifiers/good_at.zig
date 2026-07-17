const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { multStrength: f32, tag: main.Tag, flatStrength: f32, pad: u32 = undefined };

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.multStrength = @max(0, zon.get(f32, "multStrength") orelse 0),
		.tag = .find(zon.get([]const u8, "tag") orelse "incorrect"),
		.flatStrength = @max(0, zon.get(f32, "flatStrength") orelse 0),
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if (data1.tag != data2.tag) return null;
	return .{
		.multStrength = std.math.hypot(data1.multStrength, data2.multStrength),
		.tag = data1.tag,
		.flatStrength = std.math.hypot(data1.flatStrength, data2.flatStrength),
		};
}

pub fn changeBlockDamage(damage: f32, block: main.blocks.Block, data: Data) f32 {
	for (block.tags()) |tag| {
		if (tag == data.tag) return (damage + data.flatStrength)*(1 + data.multStrength);
	}
	return damage;
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	outString.print("#80ff40**Good at**#808080 *Increases damage by **{d:.0}%** and **+{d:.0}** on \n***#80ff40{s}#808080*** blocks", .{data.multStrength*100, data.flatStrength, data.tag.getName()});
}
