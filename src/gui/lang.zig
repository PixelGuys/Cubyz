const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;

const Category = enum {
	block,
	item,
	label,
	language,
	modifier,
	restriction,
	stat,
	tag,
	tool,
	world_preset,
};

var languageZon: ZonElement = undefined;

const languagesMap = main.assets.languages;

pub fn init() void {
	languageZon = languagesMap().get(main.settings.language) orelse blk: {
		std.log.err("Couldn't find language {s}. Switching to English...", .{main.settings.language});
		main.settings.language = "cubyz:english";
		main.settings.save();
		break :blk languagesMap().get(main.settings.language).?;
	};
}

fn lookupTranslation(sectionName: []const u8, catrgoryName: []const u8, string: []const u8) []const u8 {
	const zon = languageZon.getChild(sectionName).getChild(catrgoryName);
	const translated = zon.get(?[]const u8, string, null);
	return translated orelse blk: {
		std.log.warn("Couldn't find translation for '{s}'. Searched at '{s}/{s}/{s}/{s}'", .{
			string,
			main.settings.language,
			sectionName,
			catrgoryName,
			string,
		});
		break :blk string;
	};
}

pub fn translate(category: Category, string: []const u8) []const u8 {
	if (string.len == 0) return string;
	return switch (category) {
		.block => lookupTranslation("assets", "blocks", string),
		.item => lookupTranslation("assets", "items", string),
		.label => lookupTranslation("ui", "labels", string),
		.language => blk: {
			const zon = languagesMap().get(string) orelse unreachable;
			break :blk zon.get(?[]const u8, "language", null) orelse blk2: {
				std.log.err("Couldn't find name for language {s}", .{string});
				break :blk2 string;
			};
		},
		.modifier => lookupTranslation("ui", "modifiers", string),
		.restriction => lookupTranslation("ui", "restrictions", string),
		.stat => lookupTranslation("ui", "stats", string),
		.tag => lookupTranslation("assets", "tags", string),
		.tool => lookupTranslation("assets", "tools", string),
		.world_preset => lookupTranslation("assets", "world_presets", string),
	};
}

const Precision = enum {
	@"{d:.0}",
	@"{d:.1}",
	@"{d:.2}",
	@"{d:.3}",
	@"{d}",
};

const FormatArg = union(enum) {
	string: []const u8,
	int: i128,
	float: struct { value: f128, precision: Precision },
	tag: main.Tag,

	pub fn fromString(_string: []const u8) FormatArg {
		return .{.string = _string};
	}
	pub fn fromInt(_int: i128) FormatArg {
		return .{.int = _int};
	}
	pub fn fromFloat(_float: f128, precision: Precision) FormatArg {
		return .{.float = .{.value = _float, .precision = precision}};
	}
	pub fn fromTag(_tag: main.Tag) FormatArg {
		return .{.tag = _tag};
	}
};

pub fn format(allocator: main.heap.NeverFailingAllocator, category: Category, string: []const u8, args: []const FormatArg) []const u8 {
	var outString = main.List(u8).init(allocator);
	defer outString.deinit();

	formatToList(&outString, category, string, args);

	return outString.toOwnedSlice();
}

pub fn formatToList(outString: *main.List(u8), category: Category, string: []const u8, args: []const FormatArg) void {
	const fmt = translate(category, string);
	var iterator = std.mem.splitAny(u8, fmt, "{}");

	var isPlaceholder = false;
	while (iterator.next()) |slice| {
		if (isPlaceholder) {
			const index = std.fmt.parseInt(usize, slice, 10) catch |err| blk: {
				std.log.err("{} when trying to parse {s} to usize. Using index 0...", .{err, slice});
				break :blk 0;
			};
			const arg = args[index];
			switch (arg) {
				.string => |str| {
					outString.appendSlice(str);
				},
				.int => |int| {
					outString.print("{d}", .{int});
				},
				.float => |float| {
					switch (float.precision) {
						inline else => |comptimePrecision| {
							outString.print(@tagName(comptimePrecision), .{float.value});
						},
					}
				},
				.tag => |tag| {
					outString.appendSlice(translate(.tag, tag.getName()));
				},
			}
		} else {
			outString.appendSlice(slice);
		}
		isPlaceholder = !isPlaceholder;
	}
}
