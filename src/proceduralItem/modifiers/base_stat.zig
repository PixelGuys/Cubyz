const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { strength: f32, targetProperty: main.items.ProceduralItemProperty, pad: u64 = undefined };

pub const priority = 1;

fn getModifierName(data: Data) []const u8 {
	if (data.strength >= 0) {
		switch (data.targetProperty) {
			.damage => return "#f84a00**Powerful**",
			.maxDurability => return "#500090**Durable**",
			.swingSpeed => return "#9fffde**Light**",
		}
	} else {
		switch (data.targetProperty) {
			.damage => return "#fcb5e3**Weak**",
			.maxDurability => return "#ccddff**Fragile**",
			.swingSpeed => return "#ffcc30**Heavy**",
		}
	}
}

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.strength = zon.get(f32, "strength") orelse 0,
		.targetProperty = main.items.ProceduralItemProperty.fromString(zon.get([]const u8, "targetProperty") orelse "|missing targetProperty field|") orelse blk: {
			std.log.err("Could not find tagProperty {s}. Replacing it with .damage", .{zon.get([]const u8, "targetProperty") orelse "|missing targetProperty field|"});
			break :blk .damage;
		},
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if (data1.targetProperty != data2.targetProperty) return null;
	return .{
		.strength = std.math.sign(data1.strength + data2.strength)*@sqrt(@abs(data1.strength*@abs(data1.strength) + data2.strength*@abs(data2.strength))),
		.targetProperty = data1.targetProperty,
	};
}

pub fn changeProceduralItemParameters(proceduralItem: *ProceduralItem, data: Data) void {
	proceduralItem.setProperty(data.targetProperty, proceduralItem.getProperty(data.targetProperty)*(1 + getAdjustedStrength(data.strength)));
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	if (data.strength >= 0) {
		outString.print("{s} #808080(#30ca64+**{d:.0}% #808080{s})", .{getModifierName(data), getAdjustedStrength(data.strength)*100, @tagName(data.targetProperty)});
	} else {
		outString.print("{s} #808080(#fd3535-**{d:.0}% #808080{s})", .{getModifierName(data), getAdjustedStrength(data.strength)*100, @tagName(data.targetProperty)});
	}
}

fn getAdjustedStrength(strength: f32) f32 {
	// used to make sure negative numbers cannot go below -100%
	return (@max(strength, 0) + 1)/(@min(strength, 0) + 1) - 1;
}