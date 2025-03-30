const std = @import("std");

const main = @import("main");
const Tool = main.items.Tool;

pub const Data = packed struct(u128) {strength: f32, pad: u96 = undefined};

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = @max(0, zon.get(f32, "strength", 0))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.strength = std.math.hypot(data1.strength, data2.strength)};
}

pub fn changeToolParameters(tool: *Tool, data: Data) void {
	tool.damage *= 1 + data.strength;
}

pub fn changeBlockDamage(damage: f32, _: main.blocks.Block, _: Data) f32 {
	return damage;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.writer().print("#f84a00**Powerful**#808080 *Increases damage by **{d:.0}%", .{data.strength*100}) catch unreachable;
}
