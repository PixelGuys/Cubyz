const std = @import("std");

const main = @import("main");
const ZonElement = @import("zon.zig").ZonElement;
const Palette = @import("assets.zig").Palette;
const Assets = main.assets.Assets;
const ID = main.assets.ID;

var arenaAllocator = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const migrationAllocator = arenaAllocator.allocator();

var blockMigrations: ID.IdToIdMap = .{};
var biomeMigrations: ID.IdToIdMap = .{};

const MigrationType = enum {
	block,
	biome,
};

pub fn registerAll(comptime typ: MigrationType, migrations: *Assets.AddonNameToZonMap) void {
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
	collection: *ID.IdToIdMap,
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
		// We must allow for migrating IDs that do not conform to the ID rules to ones that do.
		const oldId = ID.initFromSanitizedComponents(migrationAllocator, addonName, oldZon, "");
		const result = collection.getOrPut(migrationAllocator.allocator, oldId) catch unreachable;

		if(result.found_existing) {
			std.log.err("Skipping name collision in {s} migration: '{s}' -> '{s}:{s}'", .{@tagName(typ), oldId.string, addonName, newZon});
			const existingMigration = collection.get(oldId) orelse unreachable;
			std.log.err("Already mapped to '{s}'", .{existingMigration.string});

			oldId.deinit(migrationAllocator);
		} else {
			const newId = ID.initFromComponents(migrationAllocator, addonName, newZon, "") catch |err| {
				std.log.err("Skipping {s} migration: '{s}' -> '{s}:{s}' as new ID does not conform to ID rules. ({s})", .{@tagName(typ), oldId.string, addonName, newZon, @errorName(err)});
				continue;
			};

			result.key_ptr.* = oldId;
			result.value_ptr.* = newId;
			std.log.info("Registered {s} migration: '{s}' -> '{s}'", .{@tagName(typ), oldId.string, newId.string});
		}
	}
}

pub fn apply(comptime typ: MigrationType, palette: *Palette) void {
	const migrations = switch(typ) {
		.block => blockMigrations,
		.biome => biomeMigrations,
	};
	std.log.info("Applying {} migrations to {s} palette", .{migrations.count(), @tagName(typ)});

	for(palette.palette.items, 0..) |oldId, i| {
		const newId = migrations.get(oldId) orelse continue;
		std.log.info("Migrating {s} {s} -> {s}", .{@tagName(typ), oldId.string, newId.string});
		palette.replaceEntry(i, newId);
	}
}

pub fn reset() void {
	blockMigrations.clearAndFree(migrationAllocator.allocator);
	biomeMigrations.clearAndFree(migrationAllocator.allocator);
	_ = arenaAllocator.reset(.free_all);
}

pub fn deinit() void {
	arenaAllocator.deinit();
}
