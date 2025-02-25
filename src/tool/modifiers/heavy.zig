const std = @import("std");

const main = @import("root");
const Tool = main.items.Tool;

pub const priority = 1;

pub fn combineModifiers(strength1: f32, strength2: f32) f32 {
	return @max(0, strength1) + @max(0, strength2);
}

pub fn changeToolParameters(tool: *Tool, strength: f32) void {
	tool.swingTime *= 1 + @max(0, strength);
}

pub fn printTooltip(outString: *main.List(u8), strength: f32) void {
	outString.writer().print("#ffcc30**Heavy**#808080 *Increases swing time by **{d:.0}%", .{@max(0, strength)*100}) catch unreachable;
}
