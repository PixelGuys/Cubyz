const std = @import("std");

const main = @import("main");
const ZonElement = @import("zon.zig").ZonElement;
const Palette = @import("assets.zig").Palette;

var arenaAllocator = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const migrationAllocator = arenaAllocator.allocator();

var blockMigrations: std.StringHashMap([]const u8) = .init(migrationAllocator.allocator);
var biomeMigrations: std.StringHashMap([]const u8) = .init(migrationAllocator.allocator);

const MigrationType = enum {
	block,
	biome,
};

pub fn registerAll(comptime typ: MigrationType, migrations: *std.StringHashMap(ZonElement)) void {
	std.log.info("Registering {} {s} migrations", .{migrations.count(), @tagName(typ)});
	const collection = switch(typ) {
		.block => &blockMigrations,
		.biome => &biomeMigrations,
	};
	var migrationIterator = migrations.iterator();
	while(migrationIterator.next()) |migration| {
		register(typ, collection, migration.key_ptr.*, migration.value_ptr.*);
	}
}

fn register(
	comptime typ: MigrationType,
	collection: *std.StringHashMap([]const u8),
	addonName: []const u8,
	migrationZon: ZonElement,
) void {
	if(migrationZon != .array) {
		if(migrationZon == .object and migrationZon.object.count() == 0) {
			std.log.warn("Skipping empty {s} migration data structure from addon {s}", .{@tagName(typ), addonName});
			return;
		}
		std.log.err("Skipping incorrect {s} migration data structure from addon {s}", .{@tagName(typ), addonName});
		return;
	}
	if(migrationZon.array.items.len == 0) {
		std.log.warn("Skipping empty {s} migration data structure from addon {s}", .{@tagName(typ), addonName});
		return;
	}

	for(migrationZon.array.items) |migration| {
		const oldZonOpt = migration.get(?[]const u8, "old", null);
		const newZonOpt = migration.get(?[]const u8, "new", null);

		if(oldZonOpt == null or newZonOpt == null) {
			std.log.err("Skipping incomplete migration in {s} migrations: '{s}:{s}' -> '{s}:{s}'", .{@tagName(typ), addonName, oldZonOpt orelse "<null>", addonName, newZonOpt orelse "<null>"});
			continue;
		}

		const oldZon = oldZonOpt orelse unreachable;
		const newZon = newZonOpt orelse unreachable;

		if(std.mem.eql(u8, oldZon, newZon)) {
			std.log.err("Skipping identity migration in {s} migrations: '{s}:{s}' -> '{s}:{s}'", .{@tagName(typ), addonName, oldZon, addonName, newZon});
			continue;
		}

		const oldAssetId = std.fmt.allocPrint(migrationAllocator.allocator, "{s}:{s}", .{addonName, oldZon}) catch unreachable;
		const result = collection.getOrPut(oldAssetId) catch unreachable;

		if(result.found_existing) {
			std.log.err("Skipping name collision in {s} migration: '{s}' -> '{s}:{s}'", .{@tagName(typ), oldAssetId, addonName, newZon});
			const existingMigration = collection.get(oldAssetId) orelse unreachable;
			std.log.err("Already mapped to '{s}'", .{existingMigration});

			migrationAllocator.free(oldAssetId);
		} else {
			const newAssetId = std.fmt.allocPrint(migrationAllocator.allocator, "{s}:{s}", .{addonName, newZon}) catch unreachable;

			result.key_ptr.* = oldAssetId;
			result.value_ptr.* = newAssetId;
			std.log.info("Registered {s} migration: '{s}' -> '{s}'", .{@tagName(typ), oldAssetId, newAssetId});
		}
	}
}

pub fn apply(comptime typ: MigrationType, palette: *Palette) void {
	const migrations = switch(typ) {
		.block => blockMigrations,
		.biome => biomeMigrations,
	};
	std.log.info("Applying {} migrations to {s} palette", .{migrations.count(), @tagName(typ)});

	for(palette.palette.items, 0..) |assetName, i| {
		const newAssetName = migrations.get(assetName) orelse continue;
		std.log.info("Migrating {s} {s} -> {s}", .{@tagName(typ), assetName, newAssetName});
		palette.replaceEntry(i, newAssetName);
	}
}

pub fn reset() void {
	blockMigrations.clearAndFree();
	biomeMigrations.clearAndFree();
	_ = arenaAllocator.reset(.free_all);
}

pub fn deinit() void {
	arenaAllocator.deinit();
}
