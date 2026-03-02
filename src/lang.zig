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
	tag,
	tool,
	world_preset,
};

const languagesMap: *const std.StringHashMapUnmanaged(ZonElement) = main.assets.languages();

var languageZon: ZonElement = undefined;

pub fn init() void {
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
	var iterator = languagesMap.iterator();
	while (iterator.next()) |entry| {
		if (std.mem.eql(u8, entry.key_ptr.*, languageId)) {
			languageZon = entry.value_ptr.*;
			return;
		}
	}
	return error.LanguageNotFound;
}

fn translateHelper(sectionName: []const u8, catrgoryName: []const u8, string: []const u8) []const u8 {
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
		.block => translateHelper("assets", "blocks", string),
		.item => translateHelper("assets", "items", string),
		.label => translateHelper("ui", "labels", string),
		.language => blk: {
			var iterator = languagesMap.iterator();
			while (iterator.next()) |entry| {
				if (std.mem.eql(u8, entry.key_ptr.*, string)) {
					const zon = entry.value_ptr.*;
					const translated = zon.get(?[]const u8, "language", null);
					break :blk translated orelse blk2: {
						std.log.err("Couldn't find name for language {s}", .{string});
						break :blk2 string;
					};
				}
			}
			unreachable;
		},
		.modifier => translateHelper("ui", "modifiers", string),
		.other => translateHelper("ui", "other", string),
		.tag => translateHelper("assets", "tags", string),
		.tool => translateHelper("assets", "tools", string),
		.world_preset => translateHelper("assets", "world_presets", string),
	};
}
