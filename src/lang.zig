const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;

const ZonMapEntry = std.StringHashMapUnmanaged(ZonElement).Entry;

const Category = enum {
	biome,
	block,
	item,
	language,
	particle,
	sbb,
	tag,
	tool,
	world_preset,
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

fn load(languageId: []const u8) !void {
	for (languages) |entry| {
		if (std.mem.eql(u8, entry.key_ptr.*, languageId)) {
			languageZon = entry.value_ptr.*;
			return;
		}
	}
	return error.LanguageNotFound;
}

pub fn translate(category: Category, string: []const u8) []const u8 {
	if (category == .item) {
		const zon = languageZon.getChild("assets").getChild("items");
		const translated = zon.get([]const u8, string, string);
		if (std.mem.eql(u8, translated, string)) {
			std.log.err("Couldn't find translation for item {s} in {s}", .{string, main.settings.language});
		}
		return translated;
	}
	if (category == .language) {
		const zon = languageZon.getChild("assets").getChild("languages");
		return zon.get([]const u8, string, string);
	}
	if (category == .tag) {
		const zon = languageZon.getChild("assets").getChild("tags");
		const translated = zon.get([]const u8, string, string);
		if (std.mem.eql(u8, translated, string)) {
			std.log.err("Couldn't find translation for tag {s} in {s}", .{string, main.settings.language});
		}
		return translated;
	}
	return "temp";
}

// lang.translateGame("ui", "buttonMultiplayer"): []u8 (everything fallbacks to "unknown" if not found for convenience)
// lang.translateTag(.metal) : ?[]u8
// lang.translateItem("cubyz:iron_ore"): ?[]u8
