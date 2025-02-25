const std = @import("std");

const main = @import("root");
const Tool = main.items.Tool;

pub const priority = 1;

pub fn combineModifiers(strength1: f32, strength2: f32) f32 {
	return strength1 + strength2;
}

pub fn changeToolParameters(tool: *Tool, strength: f32) void {
	tool.maxDurability *= 1 + strength;
}

pub fn printTooltip(outString: *main.List(u8), strength: f32) void {
	outString.writer().print("#500090**Durable#808080 *Increases durability by §**{d:.0}%", .{strength*100}) catch unreachable;
}
