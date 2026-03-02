const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;

const ZonMapEntry = std.StringHashMapUnmanaged(ZonElement).Entry;

const Category = enum {
	block,
	item,
	label,
	language,
	modifier,
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

inline fn standardTranslate(sectionName: []const u8, catrgoryName: []const u8, string: []const u8) []const u8 {
	const zon = languageZon.getChild(sectionName).getChild(catrgoryName);
	const translated = zon.get(?[]const u8, string, null);
	return translated orelse blk: {
		std.log.err("Couldn't find translation for {s} '{s}' in {s}", .{catrgoryName[0..(catrgoryName.len - 1)], string, main.settings.language});
		break :blk string;
	};
}

pub fn translate(category: Category, string: []const u8) []const u8 {
	if (string.len == 0) return string;
	return switch (category) {
		.block => standardTranslate("assets", "blocks", string),
		.item => standardTranslate("assets", "items", string),
		.label => standardTranslate("ui", "labels", string),
		.language => blk: {
			for (languages) |entry| {
				if (std.mem.eql(u8, entry.key_ptr.*, string)) {
					const zon = entry.value_ptr.*;
					const translated = zon.get(?[]const u8, "language", null);
					break :blk translated orelse ret: {
						std.log.err("Couldn't find name for language {s}", .{string});
						break :ret string;
					};
				}
			}
			unreachable;
		},
		.modifier => standardTranslate("ui", "modifiers", string),
		.tag => standardTranslate("assets", "tags", string),
		.tool => standardTranslate("assets", "tools", string),
		.world_preset => standardTranslate("assets", "world_presets", string),
	};
}

// lang.translateGame("ui", "buttonMultiplayer"): []u8 (everything fallbacks to "unknown" if not found for convenience)
// lang.translateTag(.metal) : ?[]u8
// lang.translateItem("cubyz:iron_ore"): ?[]u8
