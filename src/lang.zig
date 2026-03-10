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
	restriction,
	stat,
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
		.restriction => translateHelper("ui", "restrictions", string),
		.stat => translateHelper("ui", "stats", string),
		.tag => translateHelper("assets", "tags", string),
		.tool => translateHelper("assets", "tools", string),
		.world_preset => translateHelper("assets", "world_presets", string),
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
	const fmt = translate(category, string);
	var iterator = std.mem.splitAny(u8, fmt, "{}");

	var outputList = main.List(u8).init(allocator);
	defer outputList.deinit();

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
					outputList.appendSlice(str);
				},
				.int => |int| {
					outputList.print("{d}", .{int});
				},
				.float => |float| {
					switch (float.precision) {
						inline else => |comptimePrecision| {
							outputList.print(@tagName(comptimePrecision), .{float.value});
						},
					}
				},
				.tag => |tag| {
					outputList.appendSlice(translate(.tag, tag.getName()));
				},
			}
		} else {
			outputList.appendSlice(slice);
		}
		isPlaceholder = !isPlaceholder;
	}

	return outputList.toOwnedSlice();
}
