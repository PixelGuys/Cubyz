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
	addonName: []const u8,
	migrationZon: ZonElement,
) void {
	const localAllocator = main.stackAllocator;

	if((migrationZon != .object or migrationZon.object.count() == 0)) {
		return;
	}

	var migrationZonIterator = migrationZon.object.iterator();
	while(migrationZonIterator.next()) |migration| {
		const assetId = std.fmt.allocPrint(localAllocator.allocator, "{s}:{s}", .{addonName, migration.key_ptr.*}) catch unreachable;
		defer localAllocator.free(assetId);

		const newAssetId = std.fmt.allocPrint(localAllocator.allocator, "{s}:{s}", .{addonName, migration.value_ptr.stringOwned}) catch unreachable;
		defer localAllocator.free(newAssetId);

		const result = collection.getOrPut(assetId) catch unreachable;

		if(result.found_existing) {
			std.log.err("Skipping name collision in {s} migration from {s}: '{s}' -> '{s}'", .{assetType, addonName, assetId, newAssetId});
			const existingMigration = collection.get(assetId) orelse unreachable;
			std.log.err("Already mapped to '{s}'", .{existingMigration});
		} else {
			result.key_ptr.* = migrationAllocator.dupe(u8, assetId);
			result.value_ptr.* = migrationAllocator.dupe(u8, newAssetId);
			std.log.info("Registered {s} migration from {s}: '{s}' -> '{s}'", .{assetType, addonName, assetId, newAssetId});
		}
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
