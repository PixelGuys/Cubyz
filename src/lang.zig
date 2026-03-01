const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;

const ZonMapEntry = std.StringHashMapUnmanaged(ZonElement).Entry;

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

var languages: []ZonMapEntry = &.{};

var languageZon: ZonElement = undefined;

pub fn init() void {
	var languagesMap = main.assets.languages();
	var entryList: main.ListUnmanaged(ZonMapEntry) = .initCapacity(main.globalArena, languagesMap.count());
	var iterator = languagesMap.iterator();
	while (iterator.next()) |entry| {
		entryList.appendAssumeCapacity(entry);
	}
	languages = entryList.items;
	
	load(main.settings.language) catch {
		std.log.err("Couldn't find language {s}. Switching to english...", .{main.settings.language});
		setLanguage("cubyz:en_us") catch unreachable;
	};
}

pub fn setLanguage(newLanguageId: []const u8) !void {
	try load(newLanguageId);
	main.globalAllocator.free(main.settings.language);
	main.settings.language = main.globalAllocator.dupe(u8, newLanguageId);
	main.settings.save();
}

pub fn load(languageId: []const u8) !void {
	for (languages) |entry| {
		std.log.info("{s}", .{entry.key_ptr.*});
		if (std.mem.eql(u8, entry.key_ptr.*, languageId)) {
			languageZon = entry.value_ptr.*;
			return;
		}
	}
	return error.LanguageNotFound;
}

pub fn translate(category: Category, string: []const u8) []const u8 {
	if (category == .languages) {

	}
	_ = string;
	return "temp";
}

// lang.translateGame("ui", "buttonMultiplayer"): []u8 (everything fallbacks to "unknown" if not found for convenience)
// lang.translateTag(.metal) : ?[]u8
// lang.translateProperty(.dry): ?[]u8
// lang.translateItem("cubyz:iron_ore"): ?[]u8
