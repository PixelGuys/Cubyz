const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const Assets = main.assets.Assets;
const Tag = main.Tag;
const Mood = main.mood.Mood;

pub const MusicTrack = struct {
	id: []const u8,
	audioId: []const u8,
	tags: []const Tag,
	moodTarget: Mood,
	moodTolerance: f32,
	weight: f32,

	pub fn init(id: []const u8, zon: ZonElement) ?MusicTrack {
		const file = zon.get([]const u8, "file") orelse {
			std.log.err("Music track {s} is missing a 'file' field.", .{id});
			return null;
		};
		const colonIndex = std.mem.indexOfScalar(u8, id, ':') orelse {
			std.log.err("Invalid music track id: {s}. Must be addon:name", .{id});
			return null;
		};
		const addon = id[0..colonIndex];
		return MusicTrack{
			.id = main.worldArena.dupe(u8, id),
			.audioId = main.worldArena.print("{s}:{s}", .{addon, file}),
			.tags = Tag.loadTagsFromZon(main.worldArena, zon.getChild("tags")),
			.moodTarget = .{
				.anxiety = zon.getChild("moodTarget").get(f32, "anxiety") orelse 0.3,
				.energy = zon.getChild("moodTarget").get(f32, "energy") orelse 0.3,
				.sanity = zon.getChild("moodTarget").get(f32, "sanity") orelse 0.7,
			},
			.moodTolerance = zon.get(f32, "moodTolerance") orelse 0.5,
			.weight = zon.get(f32, "weight") orelse 1.0,
		};
	}
};

var finishedLoading: bool = false;
var tracks: main.List(MusicTrack) = .empty;
var tracksById: std.StringHashMapUnmanaged(*MusicTrack) = .{};
pub var anyTag: Tag = undefined;

fn register(id: []const u8, zon: ZonElement) void {
	const track = MusicTrack.init(id, zon) orelse return;
	tracks.append(main.worldArena, track);
	std.log.debug("Registered music track: '{s}'", .{id});
}

pub fn registerTracks(tracksZon: *Assets.ZonHashMap) void {
	anyTag = Tag.find("any");
	var iterator = tracksZon.iterator();
	while (iterator.next()) |entry| {
		register(entry.key_ptr.*, entry.value_ptr.*);
	}
	finishLoading();
}

fn compareMusicTracks(_: void, lhs: MusicTrack, rhs: MusicTrack) bool {
	return std.ascii.orderIgnoreCase(lhs.id, rhs.id) == .gt;
}

pub fn finishLoading() void {
	std.debug.assert(!finishedLoading);
	finishedLoading = true;

	std.mem.sort(MusicTrack, tracks.items, {}, compareMusicTracks);
	tracksById.ensureTotalCapacity(main.worldArena.allocator, @intCast(tracks.items.len)) catch unreachable;
	for (tracks.items) |*track| {
		tracksById.putAssumeCapacity(track.id, track);
	}
}

pub fn getById(id: []const u8) ?*MusicTrack {
	std.debug.assert(finishedLoading);
	return tracksById.get(id);
}

pub fn getSlice() []MusicTrack {
	return tracks.items;
}

pub fn reset() void {
	finishedLoading = false;
	tracks = .empty;
	tracksById = .{};
}
