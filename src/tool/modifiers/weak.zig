const std = @import("std");

const main = @import("root");
const Tool = main.items.Tool;

pub const priority = 1;

pub fn combineModifiers(strength1: f32, strength2: f32) f32 {
	return 1 - (1 - std.math.clamp(strength1, 0, 1))*(1 - std.math.clamp(strength2, 0, 1));
}

pub fn changeToolParameters(tool: *Tool, strength: f32) void {
	tool.power *= 1 - std.math.clamp(strength, 0, 1);
}

pub fn printTooltip(outString: *main.List(u8), strength: f32) void {
	outString.writer().print("#fcb5e3**Weak**#808080 *Decreases power by **{d:.0}%", .{std.math.clamp(strength, 0, 1)*100}) catch unreachable;
}
