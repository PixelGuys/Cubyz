const std = @import("std");

const main = @import("main.zig");
const ZonElement = @import("zon.zig").ZonElement;
const Palette = @import("assets.zig").Palette;

var ARENA_ALLOCATOR = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
const MIGRATION_ALLOCATOR = ARENA_ALLOCATOR.allocator();

var BLOCK_MIGRATIONS: std.StringHashMap([]const u8) = .init(MIGRATION_ALLOCATOR.allocator);
var ITEM_MIGRATIONS: std.StringHashMap([]const u8) = .init(MIGRATION_ALLOCATOR.allocator);
var BIOME_MIGRATIONS: std.StringHashMap([]const u8) = .init(MIGRATION_ALLOCATOR.allocator);


pub fn registerBlockMigrations(migrations: *std.StringHashMap(ZonElement)) void {
	std.log.info("Registering {} block migrations", .{migrations.count()});

	var migrationIterator = migrations.iterator();
	while (migrationIterator.next()) |migration| {
		register(&BLOCK_MIGRATIONS, "block", migration.key_ptr.*, migration.value_ptr.*);
	}
}

pub fn registerItemMigrations(migrations: *std.StringHashMap(ZonElement)) void {
	std.log.info("Registering {} item migrations", .{migrations.count()});

	var migrationIterator = migrations.iterator();
	while (migrationIterator.next()) |migration| {
		register(&ITEM_MIGRATIONS, "item", migration.key_ptr.*, migration.value_ptr.*);
	}
}

pub fn registerBiomeMigrations(migrations: *std.StringHashMap(ZonElement)) void {
	std.log.info("Registering {} biome migrations", .{migrations.count()});

	var migrationIterator = migrations.iterator();
	while (migrationIterator.next()) |migration| {
		register(&BIOME_MIGRATIONS, "biome", migration.key_ptr.*, migration.value_ptr.*);
	}
}

fn register(
	collection: * std.StringHashMap([]const u8),
	assetType: []const u8,
	name: []const u8,
	migrationZon: ZonElement,
) void {
	if ((migrationZon != .object or migrationZon.object.count() == 0)){
		return;
	}

	var migrationZonIterator = migrationZon.object.iterator();
	while (migrationZonIterator.next()) |migration| {
		const old = MIGRATION_ALLOCATOR.dupe(u8, migration.key_ptr.*);
		const new = MIGRATION_ALLOCATOR.dupe(u8, migration.value_ptr.stringOwned);
		collection.put(old, new) catch |e| {
			MIGRATION_ALLOCATOR.free(old);
			MIGRATION_ALLOCATOR.free(new);
			std.log.err(
				"Couldn't register {s} migration from {s}: `{s}` -> `{s}, error: {s}",
				.{assetType, name, old, new,  @errorName(e)}
			);
		};

		std.log.info(
			"Registered {s} migration from {s}: `{s}` -> `{s}`",
			.{assetType, name, old, new}
		);
	}
}

pub fn applyBlockPaletteMigrations(palette: *Palette) void {
	std.log.info("Applying {} migrations to block palette", .{BLOCK_MIGRATIONS.count()});

	for (palette.palette.items, 0..) |assetName, i| {
		const newAssetName = BLOCK_MIGRATIONS.get(assetName) orelse continue;
		palette.replaceEntry(i, newAssetName);
		std.log.info(
			"Migrated block {s} -> {s}",
			.{assetName, newAssetName}
		);
	}
}

pub fn reset() void {
	BLOCK_MIGRATIONS.clearAndFree();
	ITEM_MIGRATIONS.clearAndFree();
	BIOME_MIGRATIONS.clearAndFree();
}

pub fn deinit() void {
	ARENA_ALLOCATOR.deinit();
}
