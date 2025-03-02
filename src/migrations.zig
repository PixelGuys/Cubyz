const std = @import("std");

const main = @import("main.zig");
const ZonElement = @import("zon.zig").ZonElement;
const Palette = @import("assets.zig").Palette;

var arenaAllocator = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
const migrationAllocator = arenaAllocator.allocator();

var blockMigrations: std.StringHashMap([]const u8) = .init(migrationAllocator.allocator);

pub fn registerBlockMigrations(migrations: *std.StringHashMap(ZonElement)) void {
	std.log.info("Registering {} block migrations", .{migrations.count()});

	var migrationIterator = migrations.iterator();
	while(migrationIterator.next()) |migration| {
		register(&blockMigrations, "block", migration.key_ptr.*, migration.value_ptr.*);
	}
}

fn register(
	collection: *std.StringHashMap([]const u8),
	assetType: []const u8,
	name: []const u8,
	migrationZon: ZonElement,
) void {
	if((migrationZon != .object or migrationZon.object.count() == 0)) {
		return;
	}

	var migrationZonIterator = migrationZon.object.iterator();
	while(migrationZonIterator.next()) |migration| {
		if(collection.contains(migration.key_ptr.*)) {
			std.log.err("Skipping name collision in {s} migration from {s}: `{s}` -> `{s}`", .{assetType, name, migration.key_ptr.*, migration.value_ptr.stringOwned});
			const existingMigration = collection.get(migration.key_ptr.*) orelse unreachable;
			std.log.err("Mind existing {s} migration from {s}: `{s}` -> `{s}`", .{assetType, name, migration.key_ptr.*, existingMigration});
			continue;
		}
		const old = migrationAllocator.dupe(u8, migration.key_ptr.*);
		const new = migrationAllocator.dupe(u8, migration.value_ptr.stringOwned);

		collection.put(old, new) catch unreachable;

		std.log.info("Registered {s} migration from {s}: `{s}` -> `{s}`", .{assetType, name, old, new});
	}
}

pub fn applyBlockPaletteMigrations(palette: *Palette) void {
	std.log.info("Applying {} migrations to block palette", .{blockMigrations.count()});

	for(palette.palette.items, 0..) |assetName, i| {
		const newAssetName = blockMigrations.get(assetName) orelse continue;
		std.log.info("Migrating block {s} -> {s}", .{assetName, newAssetName});
		palette.replaceEntry(i, newAssetName);
	}
}

pub fn reset() void {
	blockMigrations.clearAndFree();
	_ = arenaAllocator.reset(.free_all);
}

pub fn deinit() void {
	arenaAllocator.deinit();
}
