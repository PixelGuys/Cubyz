const std = @import("std");

const main = @import("root");
const Tool = main.items.Tool;

pub const priority = 1000;

pub fn combineModifiers(strength1: f32, strength2: f32) f32 {
	return @max(1, @min(strength1, strength2));
}

pub fn changeToolParameters(tool: *Tool, strength: f32) void {
	tool.maxDurability = @max(1, strength);
}

pub fn printTooltip(outString: *main.List(u8), strength: f32) void {
	outString.writer().print("#800000**Single-use**#808080 *Sets durability to **{d:.0}", .{@max(1, strength)}) catch unreachable;
}
