const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const Assets = main.assets.Assets;
const Tag = main.Tag;

pub const MusicTrack = struct {
	pub const Mood = struct {
		anxiety: f32 = 0.3,
		energy: f32 = 0.3,
		sanity: f32 = 0.7,

		pub fn distanceTo(self: Mood, other: Mood) f32 {
			const da = self.anxiety - other.anxiety;
			const de = self.energy - other.energy;
			const ds = self.sanity - other.sanity;
			return @sqrt(da*da + de*de + ds*ds);
		}
	};

	id: []const u8,
	tags: []const Tag,
	moodTarget: Mood,
	moodTolerance: f32,
	weight: f32,

	pub fn init(id: []const u8, zon: ZonElement) MusicTrack {
		return MusicTrack{
			.id = main.worldArena.dupe(u8, id),
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

fn register(id: []const u8, zon: ZonElement) void {
	tracks.append(main.worldArena, MusicTrack.init(id, zon));
	std.log.debug("Registered music track: '{s}'", .{id});
}

pub fn registerTracks(tracksZon: *Assets.ZonHashMap) void {
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
