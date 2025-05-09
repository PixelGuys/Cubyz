const std = @import("std");

const main = @import("main");

var arena: main.heap.NeverFailingArenaAllocator = .init(main.globalAllocator);
const allocator = arena.allocator();
var tagList: main.List([]const u8) = .init(allocator);
var tagIds: std.StringHashMap(Tag) = .init(allocator.allocator);

pub fn init() void {
	loadDefaults();
}

pub fn deinit() void {
	arena.deinit();
}

fn loadDefaults() void {
	inline for(comptime std.meta.fieldNames(Tag)) |tag| {
		std.debug.assert(Tag.find(tag) == @field(Tag, tag));
	}
}

pub const Tag = enum(u32) {
	air = 0,
	fluid = 1,
	sbbChild = 2,
	_,

	pub fn resetTags() void {
		tagList.clearAndFree();
		tagIds.clearAndFree();
		_ = arena.reset(.free_all);
		loadDefaults();
	}

	pub fn findNoClobber(tag: []const u8) ?Tag {
		return tagIds.get(tag);
	}

	pub fn find(tag: []const u8) Tag {
		if(tagIds.get(tag)) |res| return res;
		const result: Tag = @enumFromInt(tagList.items.len);
		const dupedTag = allocator.dupe(u8, tag);
		tagList.append(dupedTag);
		tagIds.put(dupedTag, result) catch unreachable;
		return result;
	}

	pub fn loadTagsFromZon(_allocator: main.heap.NeverFailingAllocator, zon: main.ZonElement) []Tag {
		const result = _allocator.alloc(Tag, zon.toSlice().len);
		for(zon.toSlice(), 0..) |tagZon, i| {
			result[i] = Tag.find(tagZon.as([]const u8, "incorrect"));
		}
		return result;
	}

	pub fn getName(tag: Tag) []const u8 {
		return tagList.items[@intFromEnum(tag)];
	}
};
