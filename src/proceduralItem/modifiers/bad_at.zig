const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { multStrength: f32, tag: main.Tag, flatStrength: f32, pad: u32 = undefined };

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.multStrength = std.math.clamp(zon.get(f32, "strength") orelse 0, 0, 1),
		.tag = .find(zon.get([]const u8, "tag") orelse "incorrect"),
		.flatStrength = @min(zon.get(f32, "strength") orelse 0, 0),
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if (data1.tag != data2.tag) return null;
	return .{
		.multStrength = 1.0 - 1.0/(1.0 + std.math.hypot(1.0/(1.0 - data1.multStrength) - 1.0, 1.0/(1.0 - data2.multStrength) - 1.0)),
		.tag = data1.tag,
		.flatStrength = 1.0 - 1.0/(1.0 + std.math.hypot(1.0/(1.0 - data1.flatStrength) - 1.0, 1.0/(1.0 - data2.flatStrength) - 1.0)),
	};
}

pub fn changeBlockDamage(damage: f32, block: main.blocks.Block, data: Data) f32 {
	for (block.tags()) |tag| {
		if (tag == data.tag) return @max(damage - data.flatStrength, 0)*(1 - data.multStrength);
	}
	return damage;
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	switch (data) {
		data.multStrength != 0 and data.flatStrength != 0 => outString.print("#a00050**Bad at**#808080 *Decreases damage by **{d:.0}%** and **-{d:.0}** on \n***#a00050{s}#808080*** blocks", .{data.multStrength*100, data.flatStrength, data.tag.getName()}),
		data.multStrength != 0 and data.flatStrength == 0 => outString.print("#a00050**Bad at**#808080 *Decreases damage by **{d:.0}%** on \n***#a00050{s}#808080*** blocks", .{data.multStrength*100, data.tag.getName()}),
		data.multStrength == 0 and data.flatStrength != 0 => outString.print("#a00050**Bad at**#808080 *Decreases damage by **-{d:.0}** on \n***#a00050{s}#808080*** blocks", .{data.flatStrength, data.tag.getName()}),
		data.multStrength == 0 and data.flatStrength == 0 => outString.print("#ff0000**Bad at did not find any multStrength and Flatstrength**", .{}),
	}
}
