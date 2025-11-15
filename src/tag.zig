const std = @import("std");

const main = @import("main");

var tagList: main.ListUnmanaged([]const u8) = .{};
var tagIds: std.StringHashMapUnmanaged(Tag) = .{};

pub const Tag = enum(u32) {
	air = 0,
	fluid = 1,
	sbbChild = 2,
	fluidPlaceable = 3,
	chiselable = 4,
	_,

	pub fn initTags() void {
		inline for(comptime std.meta.fieldNames(Tag)) |tag| {
			std.debug.assert(Tag.find(tag) == @field(Tag, tag));
		}
	}

	pub fn resetTags() void {
		tagList = .{};
		tagIds = .{};
	}

	pub fn get(tag: []const u8) ?Tag {
		return tagIds.get(tag);
	}

	pub fn find(tag: []const u8) Tag {
		if(tagIds.get(tag)) |res| return res;
		const result: Tag = @enumFromInt(tagList.items.len);
		const dupedTag = main.worldArena.dupe(u8, tag);
		tagList.append(main.worldArena, dupedTag);
		tagIds.put(main.worldArena.allocator, dupedTag, result) catch unreachable;
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
