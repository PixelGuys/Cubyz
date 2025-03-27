const std = @import("std");

const main = @import("main");
const Tool = main.items.Tool;

pub const Data = packed struct(u128) {strength: f32, tag: main.blocks.BlockTag, pad: u64 = undefined};

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = @max(0, zon.get(f32, "strength", 0)), .tag = .find(zon.get([]const u8, "tag", "incorrect"))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if(data1.tag != data2.tag) return null;
	return .{.strength = std.math.hypot(data1.strength, data2.strength), .tag = data1.tag};
}

pub fn changeToolParameters(_: *Tool, _: Data) void {}

pub fn changeBlockDamage(damage: f32, block: main.blocks.Block, data: Data) f32 {
	for(block.blockTags()) |tag| {
		if(tag == data.tag) return damage*(1 + data.strength);
	}
	return damage;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.writer().print("#80ff40**Good at**#808080 *Increases damage by **{d:.0}%** on \n***#80ff40{s}#808080*** blocks", .{data.strength*100, data.tag.getName()}) catch unreachable;
}
