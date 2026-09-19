const std = @import("std");

const main = @import("main");
const ProceduralItem = main.items.ProceduralItem;

pub const Data = packed struct(u128) { strength: f32, targetProperty: main.items.ProceduralItemProperty, pad: u88 = undefined };

pub const priority = 1;

fn getModifierName(data: Data) []const u8 {
	if (data.strength >= 0) {
		switch (data.targetProperty) {
			.damage => return "#f84a00**Powerful**",
			.swingSpeed => return "#9fffde**Light**",
			.maxDurability => return "#500090**Durable**",
		}
	} else {
		switch (data.targetProperty) {
			.damage => return "#fcb5e3**Weak**",
			.swingSpeed => return "#ccddff**Fragile**",
			.maxDurability => return "#ffcc30**Heavy**",
		}
	}
}

pub fn loadData(zon: main.ZonElement) Data {
	return .{
		.strength = zon.get(f32, "strength") orelse 0,
		.targetProperty = main.items.ProceduralItemProperty.fromString(zon.get([]const u8, "targetProperty") orelse "missing .targetProperty field") orelse blk: {
			std.log.err("replacing with .damage", .{});
			break :blk .damage;
		},
	};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	if (data1.targetProperty != data2.targetProperty) return null;
	return .{
		.strength = std.math.hypot(data1.strength, data2.strength),
		.targetProperty = data1.targetProperty,
	};
}

pub fn changeProceduralItemParameters(proceduralItem: *ProceduralItem, data: Data) void {
	proceduralItem.setProperty(data.targetProperty, proceduralItem.getProperty(data.targetProperty)*(1 + data.strength));
}

pub fn printTooltip(outString: *main.ListManaged(u8), data: Data) void {
	if (data.strength >= 0) {
		outString.print("{s}  #30ca64*Increases#808080 {} by #30ca64+**{d:.0}%", .{getModifierName(data), data.targetProperty, data.strength*100});
	} else {
		outString.print("{s}  #fd3535*Decreases#808080 {} by #fd3535**{d:.0}%", .{getModifierName(data), data.targetProperty, data.strength*100});
	}
}
