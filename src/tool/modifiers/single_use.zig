const std = @import("std");

const main = @import("main");
const Tool = main.items.Tool;

pub const Data = packed struct(u128) {strength: f32, pad: u96 = undefined};

pub const priority = 1000;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = @max(1, zon.get(f32, "strength", 1))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.strength = @min(data1.strength, data2.strength)};
}

pub fn changeToolParameters(tool: *Tool, data: Data) void {
	tool.maxDurability = data.strength;
}

pub fn changeBlockDamage(damage: f32, _: main.blocks.Block, _: Data) f32 {
	return damage;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.writer().print("#800000**Single-use**#808080 *Sets durability to **{d:.0}", .{data.strength}) catch unreachable;
}
