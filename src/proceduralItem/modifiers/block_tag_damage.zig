const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { strength: f32, tag: main.Tag, pad: u64 = undefined };

pub const priority = 1;

fn getModifierName(data: Data) []const u8 {
	if (data.strength >= 0) {
		return "#80ff40**Good at**";
	} else {
		return "#a00050**Bad at**";
	}
}

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.strength = @max(zon.get(f32, "strength") orelse 0, -1),
		.tag = .find(zon.get([]const u8, "tag") orelse "incorrect"),
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if (data1.tag != data2.tag) return null;
	if (std.math.sign(data1.strength) != std.math.sign(data2.strength)) return null;
	if (data1.strength >= 0) {
		return .{.strength = std.math.hypot(data1.strength, data2.strength), .tag = data1.tag};
	} else {
		return .{.strength = -(1.0 - 1.0/(1.0 + std.math.hypot(1.0/(1.0 + data1.strength) - 1.0, 1.0/(1.0 + data2.strength) - 1.0))), .tag = data1.tag};
	}
}

pub fn changeBlockDamage(damage: f32, block: main.blocks.Block, data: Data) f32 {
	for (block.tags()) |tag| {
		if (tag == data.tag) return damage*(1 - data.strength);
	}
	return damage;
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	if (data.strength >= 0) {
		outString.print("{s} **{s}** #808080(#30ca64+**{d:.0}%#808080 damage against {s})", .{getModifierName(data), data.tag.getName(), data.strength*100, data.tag.getName()});
	} else {
		outString.print("{s} **{s}** #808080(#fd3535**{d:.0}%#808080 damage against {s})", .{getModifierName(data), data.tag.getName(), data.strength*100, data.tag.getName()});
	}
}
