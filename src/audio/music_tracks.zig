const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const Assets = main.assets.Assets;
const Tag = main.Tag;

pub const MusicTrack = struct {
	pub const Mood = struct {
		anxiety: f32,
		energy: f32,
		sanity: f32,

		pub fn loadFromZon(zon: ZonElement, isCave: ?bool) Mood {
			return .{
				.anxiety = zon.get(f32, "anxiety") orelse if (isCave orelse false) 0.7 else 0.3,
				.energy = zon.get(f32, "energy") orelse 0.3,
				.sanity = zon.get(f32, "sanity") orelse 0.7,
			};
		}

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
	chance: f32,

	pub fn init(id: []const u8, zon: ZonElement) MusicTrack {
		return MusicTrack{
			.id = main.worldArena.dupe(u8, id),
			.tags = Tag.loadTagsFromZon(main.worldArena, zon.getChild("tags")),
			.moodTarget = .loadFromZon(zon.getChild("moodTarget"), null),
			.moodTolerance = zon.get(f32, "moodTolerance") orelse 0.5,
			.chance = zon.get(f32, "chance") orelse 1.0,
		};
	}
};

var tracks: main.List(MusicTrack) = .empty;

fn register(id: []const u8, zon: ZonElement) void {
	tracks.appendAssumeCapacity(MusicTrack.init(id, zon));
	std.log.debug("Registered music track: '{s}'", .{id});
}

pub fn registerTracks(tracksZon: *Assets.ZonHashMap) void {
	tracks.ensureCapacity(main.worldArena, tracksZon.count());
	var iterator = tracksZon.iterator();
	while (iterator.next()) |entry| {
		register(entry.key_ptr.*, entry.value_ptr.*);
	}
}

pub fn getSlice() []const MusicTrack {
	return tracks.items;
}

pub fn reset() void {
	tracks = .empty;
}
