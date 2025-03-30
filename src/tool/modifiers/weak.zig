const std = @import("std");

const main = @import("main");
const Tool = main.items.Tool;

pub const Data = packed struct(u128) {strength: f32, pad: u96 = undefined};

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = std.math.clamp(zon.get(f32, "strength", 0), 0, 1)};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.strength = 1.0 - 1.0/std.math.hypot(1.0/(1.0 - data1.strength), 1.0/(1.0 - data2.strength))};
}

pub fn changeToolParameters(tool: *Tool, data: Data) void {
	tool.damage *= 1 - data.strength;
}

pub fn changeBlockDamage(damage: f32, _: main.blocks.Block, _: Data) f32 {
	return damage;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.writer().print("#fcb5e3**Weak**#808080 *Decreases damage by **{d:.0}%", .{data.strength*100}) catch unreachable;
}
