const std = @import("std");

const main = @import("main");
const Tool = main.items.Tool;

pub const Data = packed struct(u128) {strength: f32, tag: main.blocks.BlockTag, pad: u64 = undefined};

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = std.math.clamp(zon.get(f32, "strength", 0), 0, 1), .tag = .find(zon.get([]const u8, "tag", "incorrect"))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if(data1.tag != data2.tag) return null;
	return .{.strength = 1.0 - 1.0/std.math.hypot(1.0/(1.0 - data1.strength), 1.0/(1.0 - data2.strength)), .tag = data1.tag};
}

pub fn changeToolParameters(_: *Tool, _: Data) void {}

pub fn changeBlockDamage(damage: f32, block: main.blocks.Block, data: Data) f32 {
	for(block.blockTags()) |tag| {
		if(tag == data.tag) return damage*(1 - data.strength);
	}
	return damage;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.writer().print("#a00050**Bad at**#808080 *Decreases damage by **{d:.0}%** on \n***#a00050{s}#808080*** blocks", .{data.strength*100, data.tag.getName()}) catch unreachable;
}
