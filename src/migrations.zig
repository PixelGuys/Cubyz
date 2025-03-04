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
	if((migrationZon != .array or migrationZon.array.items.len == 0)) {
		std.log.err("Skipping incorrect {s} migration data structure from addon {s}", .{assetType, addonName});
		return;
	}

	for(migrationZon.array.items) |migration| {
		const oldZonOpt = migration.get(?[]const u8, "old", null);
		const newZonOpt = migration.get(?[]const u8, "new", null);

		if(oldZonOpt == null or newZonOpt == null) {
			std.log.err("Skipping incomplete migration in {s} migrations: '{s}:{s}' -> '{s}:{s}'", .{assetType, addonName, oldZonOpt orelse "<null>", addonName, newZonOpt orelse "<null>"});
			continue;
		}

		const oldZon = oldZonOpt orelse unreachable;
		const newZon = newZonOpt orelse unreachable;

		if(std.mem.eql(u8, oldZon, newZon)) {
			std.log.err("Skipping identity migration in {s} migrations: '{s}:{s}' -> '{s}:{s}'", .{assetType, addonName, oldZon, addonName, newZon});
			continue;
		}

		const oldAssetId = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}:{s}", .{addonName, oldZon}) catch unreachable;
		defer main.stackAllocator.free(oldAssetId);

		const result = collection.getOrPut(oldAssetId) catch unreachable;

		if(result.found_existing) {
			std.log.err("Skipping name collision in {s} migration: '{s}' -> '{s}:{s}'", .{assetType, oldAssetId, addonName, newZon});
			const existingMigration = collection.get(oldAssetId) orelse unreachable;
			std.log.err("Already mapped to '{s}'", .{existingMigration});
		} else {
			const newAssetId = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}:{s}", .{addonName, newZon}) catch unreachable;
			defer main.stackAllocator.free(newAssetId);

			result.key_ptr.* = migrationAllocator.dupe(u8, oldAssetId);
			result.value_ptr.* = migrationAllocator.dupe(u8, newAssetId);
			std.log.info("Registered {s} migration: '{s}' -> '{s}'", .{assetType, oldAssetId, newAssetId});
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
