const main = @import("main");

pub const Category = enum {
	biomes,
	blocks,
	items,
	languages,
	particles,
	sbb,
	tags,
	tools,
	world_presets,
};

pub fn setLanguage(newLanguageId: []const u8) void {
	main.settings.language = newLanguageId;
}

pub fn translate(category: Category, string: []const u8) []const u8 {
	_ = category;
	_ = string;
	return "temp";
}

// lang.translateGame("ui", "buttonMultiplayer"): []u8 (everything fallbacks to "unknown" if not found for convenience)
// lang.translateTag(.metal) : ?[]u8
// lang.translateProperty(.dry): ?[]u8
// lang.translateItem("cubyz:iron_ore"): ?[]u8
