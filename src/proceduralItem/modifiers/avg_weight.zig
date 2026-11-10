const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { strength: f32, pad: u96 = undefined };

pub const priority = 1;

fn getModifierName(data: Data) []const u8 {
	if (data.strength >= 1) {
		return "#d4ffe8**Inconsequental**";
	} else {
		return "#5e1c00**Biased**";
	}
}

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.strength = zon.get(f32, "strength") orelse 0,
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if (std.math.sign(data1.strength) != std.math.sign(data2.strength)) return null;
	return .{.strength = data1.strength*data2.strength};
}

pub fn getItemAvgWeight(weight: f32, data: Data) f32 {
	return weight*data.strength;
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	if (data.strength == 0) {
		outString.print("#d4ffe8**Inconsequental** #808080(does not affect averages in procedural tool calculations)", .{});
	} else {
		outString.print("{s} #808080(has a weight of **{d:.0} in procedural tool calculations)", .{getModifierName(data), data.strength*100});
	}
}
