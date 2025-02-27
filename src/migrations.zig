const std = @import("std");

const main = @import("main.zig");
const ZonElement = @import("zon.zig").ZonElement;
const Palette = @import("assets.zig").Palette;

var ARENA_ALLOCATOR = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
const ALLOCATOR = ARENA_ALLOCATOR.allocator();

var BLOCK_MIGRATIONS: main.List(Migration) = .init(ALLOCATOR);
var ITEM_MIGRATIONS: main.List(Migration) = .init(ALLOCATOR);
var BIOME_MIGRATIONS: main.List(Migration) = .init(ALLOCATOR);
var RECIPE_MIGRATIONS: main.List(Migration) = .init(ALLOCATOR);

// Register a migration from a ZonElement into the migration list based on asset field.
pub fn register(name: []const u8, zon: ZonElement) void {
	const asset_type = MigratedAsset.fromString(zon.get([]const u8, "asset", "none"));
	switch (asset_type) {
		.block => {
			registerMigration(&BLOCK_MIGRATIONS, zon, name, "block");
		},
		.item => {
			registerMigration(&ITEM_MIGRATIONS, zon, name, "item");
		},
		.biome => {
			registerMigration(&BIOME_MIGRATIONS, zon, name, "biome");
		},
		.recipe => {
			registerMigration(&RECIPE_MIGRATIONS, zon, name, "recipe");
		},
		.none => {
			std.log.err("Detected noop migration {s} -> {s}. Skipping", .{ zon.get([]const u8, "old", ""), zon.get([]const u8, "new", "") });
		},
	}
}

fn registerMigration(
	migrations: *main.List(Migration),
	zon: ZonElement,
	name: []const u8,
	description: []const u8,
) void {
	const typ = MigrationType.fromString(zon.get([]const u8, "typ", "noop"));
	const old = zon.get([]const u8, "old", "");
	const new = zon.get([]const u8, "new", "");
	migrations.append(Migration{ .name = name, .typ = typ, .old = old, .new = new });

	std.log.info("Registered {s} migration [{s}] {s} -> {s}", .{ description, name, old, new });
}

pub fn applyBlockPaletteMigrations(palette: *Palette) void {
	std.log.info("Applying {} migrations to block palette", .{BLOCK_MIGRATIONS.items.len});
	var reversePalette: std.StringHashMap(u16) = .init(ALLOCATOR.allocator);
	{
		for (palette.palette.items, 0..) |block, i| {
			// I don't see a recoverable situation where this would fail.
			reversePalette.put(block, @intCast(i)) catch continue;
		}
	}

	for (BLOCK_MIGRATIONS.items) |migration| {
		if (migration.typ == .rename) {
			// Migration is not necessary when block is not present in the palette.
			const block_id = reversePalette.get(migration.old) orelse continue;
			// I don't see a recoverable situation where this would fail.
			reversePalette.put(migration.new, block_id) catch continue;
			_ = reversePalette.remove(migration.old);
			// Since palette stores u8 arrays, we have to free content of the u8 array
			// before we replace our pointer to that u8 array.
			palette.palette.allocator.free(palette.palette.items[@intCast(block_id)]);

			palette.palette.replace(
				@intCast(block_id),
				palette.palette.allocator.dupe(u8, migration.new)
			);
			std.log.info("Migrated {s} -> {s} (block ID: {})", .{ migration.old, migration.new, block_id });
		}
	}
}

const MigrationType = enum {
	rename,
	noop,

	fn fromString(string: []const u8) MigrationType {
		return std.meta.stringToEnum(MigrationType, string) orelse {
			std.log.err("Couldn't migration type {s}. Replacing it with noop", .{string});
			return .noop;
		};
	}
};

const MigratedAsset = enum {
	block,
	item,
	biome,
	recipe,
	none,

	fn fromString(string: []const u8) MigratedAsset {
		return std.meta.stringToEnum(MigratedAsset, string) orelse {
			std.log.err("Couldn't migrate asset {s}. Replacing it with none", .{string});
			return .none;
		};
	}
};

const Migration = struct {
	name: []const u8,
	typ: MigrationType,
	old: []const u8,
	new: []const u8,
};

pub fn reset() void {
	BLOCK_MIGRATIONS.clearAndFree();
	ITEM_MIGRATIONS.clearAndFree();
	BIOME_MIGRATIONS.clearAndFree();
	RECIPE_MIGRATIONS.clearAndFree();
}

pub fn deinit() void {
	ARENA_ALLOCATOR.deinit();
}
