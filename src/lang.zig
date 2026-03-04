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
	other,
	restriction,
	tag,
	tool,
	world_preset,
};

pub var numbersFirst = true;

const languagesMap: *const std.StringHashMapUnmanaged(ZonElement) = main.assets.languages();

var languageZon: ZonElement = undefined;

pub fn init() void {
	load(main.settings.language) catch {
		std.log.err("Couldn't find language {s}. Switching to english...", .{main.settings.language});
		setLanguage("cubyz:en_us") catch unreachable;
	};
}

pub fn setLanguage(newLanguageId: []const u8) !void {
	main.settings.language = main.globalAllocator.dupe(u8, newLanguageId);
	main.settings.save();
}

fn load(languageId: []const u8) !void {
	languageZon = languagesMap.get(languageId) orelse return error.LanguageNotFound;
	numbersFirst = languageZon.get(bool, "numbersFirst", true);
}

fn translateHelper(sectionName: []const u8, catrgoryName: []const u8, string: []const u8) []const u8 {
	const zon = languageZon.getChild(sectionName).getChild(catrgoryName);
	const translated = zon.get(?[]const u8, string, null);
	return translated orelse blk: {
		// uncomment when english is complete
		// std.log.err("Couldn't find translation for '{s}'. Searched at '{s}/{s}/{s}/{s}'", .{
		// string,
		// main.settings.language,
		// sectionName,
		// catrgoryName,
		// string,
		// });
		break :blk string;
	};
}

pub fn translate(category: Category, string: []const u8) []const u8 {
	if (string.len == 0) return string;
	return switch (category) {
		.block => translateHelper("assets", "blocks", string),
		.item => translateHelper("assets", "items", string),
		.label => translateHelper("ui", "labels", string),
		.language => blk: {
			const zon = languagesMap.get(string) orelse unreachable;
			break :blk zon.get(?[]const u8, "language", null) orelse blk2: {
				std.log.err("Couldn't find name for language {s}", .{string});
				break :blk2 string;
			};
		},
		.modifier => translateHelper("ui", "modifiers", string),
		.other => translateHelper("ui", "others", string),
		.restriction => translateHelper("ui", "restrictions", string),
		.tag => translateHelper("assets", "tags", string),
		.tool => translateHelper("assets", "tools", string),
		.world_preset => translateHelper("assets", "world_presets", string),
	};
}
