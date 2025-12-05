const std = @import("std");

const main = @import("main");
const ZonElement = @import("zon.zig").ZonElement;
const Palette = @import("assets.zig").Palette;
const Assets = main.assets.Assets;

var blockMigrations: std.StringHashMapUnmanaged([]const u8) = .{};
var itemMigrations: std.StringHashMapUnmanaged([]const u8) = .{};
var biomeMigrations: std.StringHashMapUnmanaged([]const u8) = .{};

const MigrationType = enum {
	block,
	item,
	biome,
};

pub fn registerAll(comptime typ: MigrationType, migrations: *Assets.AddonNameToZonMap) void {
	std.log.info("Registering {s} migrations for {} addons", .{@tagName(typ), migrations.count()});
	const collection = switch(typ) {
		.block => &blockMigrations,
		.item => &itemMigrations,
		.biome => &biomeMigrations,
	};
	var migrationIterator = migrations.iterator();
	while(migrationIterator.next()) |migration| {
		register(typ, collection, migration.key_ptr.*, migration.value_ptr.*);
	}
}

fn register(
	comptime typ: MigrationType,
	collection: *std.StringHashMapUnmanaged([]const u8),
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

		const oldAssetId = std.fmt.allocPrint(main.worldArena.allocator, "{s}:{s}", .{addonName, oldZon}) catch unreachable;
		const result = collection.getOrPut(main.worldArena.allocator, oldAssetId) catch unreachable;

		if(result.found_existing) {
			std.log.err("Skipping name collision in {s} migration: '{s}' -> '{s}:{s}'", .{@tagName(typ), oldAssetId, addonName, newZon});
			const existingMigration = collection.get(oldAssetId) orelse unreachable;
			std.log.err("Already mapped to '{s}'", .{existingMigration});

			main.worldArena.free(oldAssetId);
		} else {
			const newAssetId = std.fmt.allocPrint(main.worldArena.allocator, "{s}:{s}", .{addonName, newZon}) catch unreachable;

			result.key_ptr.* = oldAssetId;
			result.value_ptr.* = newAssetId;
			std.log.info("Registered {s} migration: '{s}' -> '{s}'", .{@tagName(typ), oldAssetId, newAssetId});
		}
	}
}

pub fn applySingle(comptime typ: MigrationType, assetName: []const u8) []const u8 {
	const migrations = switch(typ) {
		.block => blockMigrations,
		.item => itemMigrations,
		.biome => biomeMigrations,
	};

	const newAssetName = migrations.get(assetName) orelse return assetName;
	std.log.info("Migrating {s} {s} -> {s}", .{@tagName(typ), assetName, newAssetName});
	return newAssetName;
}

pub fn apply(comptime typ: MigrationType, palette: *Palette) void {
	const migrations = switch(typ) {
		.block => blockMigrations,
		.item => itemMigrations,
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
	biomeMigrations = .{};
	blockMigrations = .{};
	itemMigrations = .{};
}
