const std = @import("std");

const blocks_zig = @import("blocks.zig");
const items_zig = @import("items.zig");
const migrations_zig = @import("migrations.zig");
const blueprints_zig = @import("blueprint.zig");
const Blueprint = blueprints_zig.Blueprint;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const biomes_zig = main.server.terrain.biomes;
const sbb = main.server.terrain.structure_building_blocks;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const ListUnmanaged = main.ListUnmanaged;
const files = main.files;

var commonAssetArena: NeverFailingArenaAllocator = undefined;
var commonAssetAllocator: NeverFailingAllocator = undefined;
var common: Assets = undefined;

pub const Assets = struct {
	pub const ZonHashMap = std.StringHashMapUnmanaged(ZonElement);
	pub const RawHashMap = std.StringHashMapUnmanaged([]const u8);
	pub const AddonNameToZonMap = std.StringHashMapUnmanaged(ZonElement);

	blocks: ZonHashMap,
	blockMigrations: AddonNameToZonMap,
	items: ZonHashMap,
	tools: ZonHashMap,
	biomes: ZonHashMap,
	biomeMigrations: AddonNameToZonMap,
	recipes: ZonHashMap,
	models: RawHashMap,
	structureBuildingBlocks: ZonHashMap,
	blueprints: RawHashMap,

	fn init() Assets {
		return .{
			.blocks = .{},
			.blockMigrations = .{},
			.items = .{},
			.tools = .{},
			.biomes = .{},
			.biomeMigrations = .{},
			.recipes = .{},
			.models = .{},
			.structureBuildingBlocks = .{},
			.blueprints = .{},
		};
	}
	fn deinit(self: *Assets, allocator: NeverFailingAllocator) void {
		self.blocks.deinit(allocator.allocator);
		self.blockMigrations.deinit(allocator.allocator);
		self.items.deinit(allocator.allocator);
		self.tools.deinit(allocator.allocator);
		self.biomes.deinit(allocator.allocator);
		self.biomeMigrations.deinit(allocator.allocator);
		self.recipes.deinit(allocator.allocator);
		self.models.deinit(allocator.allocator);
		self.structureBuildingBlocks.deinit(allocator.allocator);
		self.blueprints.deinit(allocator.allocator);
	}
	fn clone(self: Assets, allocator: NeverFailingAllocator) Assets {
		return .{
			.blocks = self.blocks.clone(allocator.allocator) catch unreachable,
			.blockMigrations = self.blockMigrations.clone(allocator.allocator) catch unreachable,
			.items = self.items.clone(allocator.allocator) catch unreachable,
			.tools = self.tools.clone(allocator.allocator) catch unreachable,
			.biomes = self.biomes.clone(allocator.allocator) catch unreachable,
			.biomeMigrations = self.biomeMigrations.clone(allocator.allocator) catch unreachable,
			.recipes = self.recipes.clone(allocator.allocator) catch unreachable,
			.models = self.models.clone(allocator.allocator) catch unreachable,
			.structureBuildingBlocks = self.structureBuildingBlocks.clone(allocator.allocator) catch unreachable,
			.blueprints = self.blueprints.clone(allocator.allocator) catch unreachable,
		};
	}
	fn read(self: *Assets, allocator: NeverFailingAllocator, assetPath: []const u8) void {
		const addons = Addon.discoverAll(main.stackAllocator, assetPath);
		defer addons.deinit(main.stackAllocator);
		defer for(addons.items) |*addon| addon.deinit(main.stackAllocator);

		for(addons.items) |addon| {
			addon.readAllZon(allocator, .blocks, true, &self.blocks, &self.blockMigrations);
			addon.readAllZon(allocator, .items, true, &self.items, null);
			addon.readAllZon(allocator, .tools, true, &self.tools, null);
			addon.readAllZon(allocator, .biomes, true, &self.biomes, &self.biomeMigrations);
			addon.readAllZon(allocator, .recipes, false, &self.recipes, null);
			addon.readAllZon(allocator, .sbb, true, &self.structureBuildingBlocks, null);
			addon.readAllBlueprints(allocator, &self.blueprints);
			addon.readAllModels(allocator, &self.models);
		}
	}
	fn log(self: *Assets, typ: enum {common, world}) void {
		std.log.info(
			"Finished {s} assets reading with {} blocks ({} migrations), {} items, {} tools, {} biomes ({} migrations), {} recipes, {} structure building blocks and {} blueprints",
			.{@tagName(typ), self.blocks.count(), self.blockMigrations.count(), self.items.count(), self.tools.count(), self.biomes.count(), self.biomeMigrations.count(), self.recipes.count(), self.structureBuildingBlocks.count(), self.blueprints.count()},
		);
	}

	const Addon = struct {
		name: []const u8,
		dir: std.fs.Dir,

		fn discoverAll(allocator: NeverFailingAllocator, path: []const u8) main.ListUnmanaged(Addon) {
			var addons: main.ListUnmanaged(Addon) = .{};

			var dir = std.fs.cwd().openDir(path, .{.iterate = true}) catch |err| {
				std.log.err("Can't open asset path {s}: {s}", .{path, @errorName(err)});
				return addons;
			};
			defer dir.close();

			var iterator = dir.iterate();
			while(iterator.next() catch |err| blk: {
				std.log.err("Got error while iterating over asset path {s}: {s}", .{path, @errorName(err)});
				break :blk null;
			}) |addon| {
				if(addon.kind != .directory) continue;

				const directory = dir.openDir(addon.name, .{}) catch |err| {
					std.log.err("Got error while reading addon {s} from {s}: {s}", .{addon.name, path, @errorName(err)});
					continue;
				};
				addons.append(allocator, .{.name = allocator.dupe(u8, addon.name), .dir = directory});
			}
			return addons;
		}

		fn deinit(self: *Addon, allocator: NeverFailingAllocator) void {
			self.dir.close();
			allocator.free(self.name);
		}

		const Defaults = struct {
			localArena: NeverFailingArenaAllocator = undefined,
			localAllocator: NeverFailingAllocator = undefined,
			defaults: std.StringHashMapUnmanaged(ZonElement) = .{},

			fn init(self: *Defaults, allocator: NeverFailingAllocator) void {
				self.localArena = .init(allocator);
				self.localAllocator = self.localArena.allocator();
			}

			fn deinit(self: *Defaults) void {
				self.localArena.deinit();
			}

			fn get(self: *Defaults, dir: std.fs.Dir) ZonElement {
				const path = dir.realpathAlloc(main.stackAllocator.allocator, ".") catch unreachable;
				defer main.stackAllocator.free(path);

				const result = self.defaults.getOrPut(self.localAllocator.allocator, path) catch unreachable;

				if(!result.found_existing) {
					result.key_ptr.* = self.localAllocator.dupe(u8, path);
					const default: ZonElement = self.read(dir) catch |err| blk: {
						std.log.err("Failed to read default file: {s}", .{@errorName(err)});
						break :blk .null;
					};

					result.value_ptr.* = default;
				}

				return result.value_ptr.*;
			}

			fn read(self: *Defaults, dir: std.fs.Dir) !ZonElement {
				if(main.files.Dir.init(dir).readToZon(self.localAllocator, "_defaults.zig.zon")) |zon| {
					return zon;
				} else |err| {
					if(err != error.FileNotFound) return err;
				}

				if(main.files.Dir.init(dir).readToZon(self.localAllocator, "_defaults.zon")) |zon| {
					return zon;
				} else |err| {
					if(err != error.FileNotFound) return err;
				}

				return .null;
			}
		};

		const ZonAssets = enum {
			blocks,
			items,
			tools,
			biomes,
			recipes,
			sbb,
		};

		pub fn readAllZon(addon: Addon, allocator: NeverFailingAllocator, assetType: ZonAssets, hasDefaults: bool, output: *ZonHashMap, migrations: ?*AddonNameToZonMap) void {
			const subPath = @tagName(assetType);
			var assetsDirectory = addon.dir.openDir(subPath, .{.iterate = true}) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Could not open addon directory {s}: {s}", .{subPath, @errorName(err)});
				}
				return;
			};
			defer assetsDirectory.close();

			var defaultsStorage: Defaults = .{};
			defaultsStorage.init(main.stackAllocator);
			defer defaultsStorage.deinit();

			var walker = assetsDirectory.walk(main.stackAllocator.allocator) catch unreachable;
			defer walker.deinit();

			while(walker.next() catch |err| blk: {
				std.log.err("Got error while iterating addon directory {s}: {s}", .{subPath, @errorName(err)});
				break :blk null;
			}) |entry| {
				if(entry.kind != .file) continue;
				if(std.ascii.startsWithIgnoreCase(entry.basename, "_defaults")) continue;
				if(!std.ascii.endsWithIgnoreCase(entry.basename, ".zon")) continue;
				if(std.ascii.startsWithIgnoreCase(entry.path, "textures")) continue;
				if(std.ascii.eqlIgnoreCase(entry.basename, "_migrations.zig.zon")) continue;

				const id = ID.initFromPath(allocator, addon.name, entry.path) catch |err| {
					std.log.err("Could not create ID for asset '{s}/{s}' from addon '{s}' due to error '{s}'. Asset will not be loaded.", .{@tagName(assetType), entry.path, addon.name, @errorName(err)});
					continue;
				};

				const zon = files.Dir.init(assetsDirectory).readToZon(allocator, entry.path) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				if(hasDefaults) {
					zon.join(defaultsStorage.get(entry.dir));
				}
				output.put(allocator.allocator, id.string, zon) catch unreachable;
			}
			if(migrations != null) blk: {
				const zon = files.Dir.init(assetsDirectory).readToZon(allocator, "_migrations.zig.zon") catch |err| {
					if(err != error.FileNotFound) std.log.err("Cannot read {s} migration file for addon {s}", .{subPath, addon.name});
					break :blk;
				};
				migrations.?.put(allocator.allocator, allocator.dupe(u8, addon.name), zon) catch unreachable;
			}
		}

		pub fn readAllBlueprints(addon: Addon, allocator: NeverFailingAllocator, output: *RawHashMap) void {
			const subPath = "blueprints";
			var assetsDirectory = addon.dir.openDir(subPath, .{.iterate = true}) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Could not open addon directory {s}: {s}", .{subPath, @errorName(err)});
				}
				return;
			};
			defer assetsDirectory.close();

			var walker = assetsDirectory.walk(main.stackAllocator.allocator) catch unreachable;
			defer walker.deinit();

			while(walker.next() catch |err| blk: {
				std.log.err("Got error while iterating addon directory {s}: {s}", .{subPath, @errorName(err)});
				break :blk null;
			}) |entry| {
				if(entry.kind != .file) continue;
				if(std.ascii.startsWithIgnoreCase(entry.basename, "_defaults")) continue;
				if(!std.ascii.endsWithIgnoreCase(entry.basename, ".blp")) continue;
				if(std.ascii.startsWithIgnoreCase(entry.basename, "_migrations")) continue;

				const id = ID.initFromPath(allocator, addon.name, entry.path) catch |err| {
					std.log.err("Could not create ID for blueprint '{s}' from addon '{s}' due to error '{s}'. Asset will not be loaded.", .{entry.path, addon.name, @errorName(err)});
					continue;
				};

				const data = files.Dir.init(assetsDirectory).read(allocator, entry.path) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.put(allocator.allocator, id.string, data) catch unreachable;
			}
		}

		pub fn readAllModels(addon: Addon, allocator: NeverFailingAllocator, output: *RawHashMap) void {
			const subPath = "models";
			var assetsDirectory = addon.dir.openDir(subPath, .{.iterate = true}) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Could not open addon directory {s}: {s}", .{subPath, @errorName(err)});
				}
				return;
			};
			defer assetsDirectory.close();
			var walker = assetsDirectory.walk(main.stackAllocator.allocator) catch unreachable;
			defer walker.deinit();

			while(walker.next() catch |err| blk: {
				std.log.err("Got error while iterating addon directory {s}: {s}", .{subPath, @errorName(err)});
				break :blk null;
			}) |entry| {
				if(entry.kind != .file) continue;
				if(!std.ascii.endsWithIgnoreCase(entry.basename, ".obj")) continue;

				const id = ID.initFromPath(allocator, addon.name, entry.path) catch |err| {
					std.log.err("Could not create ID for model '{s}' from addon '{s}' due to error '{s}'. Asset will not be loaded.", .{entry.path, addon.name, @errorName(err)});
					continue;
				};

				const string = assetsDirectory.readFileAlloc(allocator.allocator, entry.path, std.math.maxInt(usize)) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.put(allocator.allocator, id.string, string) catch unreachable;
			}
		}
	};
};

pub fn init() void {
	biomes_zig.init();
	blocks_zig.init();

	commonAssetArena = .init(main.globalAllocator);
	commonAssetAllocator = commonAssetArena.allocator();

	common = .init();
	common.read(commonAssetAllocator, "assets/");
	common.log(.common);
}

pub const ID = struct {
	string: []const u8,

	pub const HashContext = struct {
		pub fn hash(_: HashContext, a: ID) u64 {
			var h = std.hash.Wyhash.init(0);
			h.update(a.string);
			return h.final();
		}
		pub fn eql(_: HashContext, a: ID, b: ID) bool {
			return std.meta.eql(a.string, b.string);
		}
	};

	pub const IdToIdMap = std.HashMapUnmanaged(ID, ID, ID.HashContext, 80);
	pub fn IdToIndexMap(comptime IndexT: type) type {
		return std.HashMapUnmanaged(ID, IndexT, ID.HashContext, 80);
	}
	pub fn IndexToIdMap(comptime IndexT: type) type {
		return std.HashMapUnmanaged(IndexT, ID, std.hash_map.AutoContext(IndexT), 80);
	}
	/// Initialize ID from addon name and path to the asset. String will be checked against ID rules.
	fn initFromPath(
		allocator: NeverFailingAllocator,
		addon: []const u8,
		relativeFilePath: []const u8,
	) !ID {
		std.debug.assert(relativeFilePath.len != 0);

		const posixPath = main.stackAllocator.dupe(u8, relativeFilePath);
		defer main.stackAllocator.free(posixPath);

		std.mem.replaceScalar(u8, posixPath, '\\', '/');
		std.debug.assert(posixPath.len != 0);

		var pathSplit = std.mem.splitBackwardsScalar(u8, posixPath, '/');
		const fileName = pathSplit.first();
		std.debug.assert(fileName.len != 0);

		const fileNameExtensionIndex = std.mem.indexOfScalar(u8, fileName, '.') orelse fileName.len;
		const extension = fileName[fileNameExtensionIndex..];

		return try initFromComponents(allocator, addon, posixPath[0 .. posixPath.len - extension.len], "");
	}
	/// Initialize ID from insanitary string. String will be checked against ID rules.
	pub fn initFromString(allocator: NeverFailingAllocator, string: []const u8) !ID {
		var split = std.mem.splitScalar(u8, string, ':');
		const addon = split.first();
		if(addon.len == 0) return error.EmptyAddonName;

		const path = split.next() orelse return error.MissingAssetId;
		if(path.len == 0) return error.EmptyAssetId;

		const params = split.rest();

		return try initFromComponents(allocator, addon, path, params);
	}
	/// Initialize ID from sanitized string. String **won't** be checked against ID rules.
	pub fn initFromSanitizedString(allocator: NeverFailingAllocator, id: []const u8) ID {
		return .{.string = allocator.dupe(u8, id)};
	}
	/// Initialize ID from ID components. Components will be checked against corresponding ID rules.
	pub fn initFromComponents(allocator: NeverFailingAllocator, addon: []const u8, path: []const u8, params: []const u8) !ID {
		const sizeGuess = addon.len + 1 + path.len + if(params.len > 0) 1 + params.len else 0;
		var writer = main.utils.BinaryWriter.initCapacity(allocator, sizeGuess);
		errdefer writer.deinit();

		for(addon) |c| {
			const char: u8 = c;
			if(!isValidIdChar(char)) {
				std.log.warn("Character '{s}' in addon name '{s}' is not allowed in asset ID.", .{[_]u8{char}, addon});
				return error.InvalidAddonName;
			}
			if(std.ascii.isUpper(char)) {
				writer.writeInt(u8, std.ascii.toLower(char));
				std.log.warn("Detected upper case character '{s}' in addon name '{s}'. Asset IDs are case insensitive, it will be case folded.", .{[_]u8{char}, addon});
				continue;
			}
			writer.writeInt(u8, char);
		}
		writer.writeInt(u8, ':');

		var pathSplit = std.mem.splitBackwardsScalar(u8, path, '/');
		const name = pathSplit.first();
		if(name.len == 0) {
			std.log.warn("Empty asset name is not allowed. ('{s}' in '{s}')", .{path, addon});
			return error.EmptyAssetName;
		}
		const directory = pathSplit.rest();

		if(directory.len != 0) {
			for(directory) |c| {
				const char: u8 = c;
				if(char != '/' and !isValidIdChar(char)) {
					std.log.warn("Character '{s}' present in asset path '{s}' is not allowed in asset ID.", .{[_]u8{char}, path});
					return error.InvalidAssetPath;
				}
				if(std.ascii.isUpper(char)) {
					writer.writeInt(u8, std.ascii.toLower(char));
					std.log.warn("Detected upper case character '{s}' in asset path '{s}'. Asset IDs are case insensitive, it will be case folded.", .{[_]u8{char}, path});
					continue;
				}
				writer.writeInt(u8, char);
			}
			writer.writeInt(u8, '/');
		}
		for(name) |c| {
			const char: u8 = c;
			if(!isValidIdChar(char)) {
				std.log.warn("Character '{s}' in asset name '{s}' is not allowed in asset ID.", .{[_]u8{char}, addon});
				return error.InvalidAssetName;
			}
			if(std.ascii.isUpper(char)) {
				writer.writeInt(u8, std.ascii.toLower(char));
				std.log.warn("Detected upper case character '{s}' in asset name '{s}'. Asset IDs are case insensitive, it will be case folded.", .{[_]u8{char}, name});
				continue;
			}
			writer.writeInt(u8, char);
		}
		if(params.len != 0) {
			writer.writeInt(u8, ':');
			writer.writeSlice(params);
		}

		return .{.string = writer.data.items};
	}
	/// Initialize ID from ID components. Components **won't** be checked against corresponding ID rules.
	pub fn initFromSanitizedComponents(allocator: NeverFailingAllocator, addon: []const u8, path: []const u8, params: []const u8) ID {
		const sizeGuess = addon.len + 1 + path.len + if(params.len > 0) 1 + params.len else 0;
		var writer = main.utils.BinaryWriter.initCapacity(allocator, sizeGuess);

		writer.writeSlice(addon);
		writer.writeInt(u8, ':');
		writer.writeSlice(path);
		if(params.len != 0) {
			writer.writeInt(u8, ':');
			writer.writeSlice(params);
		}

		return .{.string = writer.data.items};
	}

	pub fn isValidIdChar(c: u8) bool {
		return std.ascii.isAlphanumeric(c) or c == '_';
	}

	pub fn deinit(self: ID, allocator: NeverFailingAllocator) void {
		allocator.free(self.string);
	}
	// Name of the addon without asset ID and params.
	pub fn addonName(self: ID) ![]const u8 {
		const index = std.mem.indexOfScalar(u8, self.string, ':') orelse return error.InvalidAddonName;
		return self.string[0..index];
	}
	// Asset ID with addon name and without params.
	pub fn assetId(self: ID) ![]const u8 {
		const first = try self.addonName();
		const offset = first.len + 1;
		const rest = self.string[offset..];
		if(rest.len == 0) return error.InvalidAssetId;

		const index = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
		return self.string[0 .. offset + index];
	}
	// Asset name without addon name and without params.
	pub fn assetName(self: ID) ![]const u8 {
		const first = try self.addonName();
		const offset = first.len + 1;
		const rest = self.string[offset..];
		if(rest.len == 0) return error.InvalidAssetName;

		const index = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
		return self.string[offset .. offset + index];
	}
	// Parameters string without addon name and asset ID.
	pub fn paramsString(self: ID) ![]const u8 {
		const first = try self.assetId();
		const offset = first.len + 1;
		// Handles the case when there is no `:` for params and case where there is `:` but no params after it.
		if(offset >= self.string.len) return "";
		return self.string[offset..];
	}
};

const IDTest = struct {
	var testingAllocator = main.heap.ErrorHandlingAllocator.init(std.testing.allocator);
	var allocator = testingAllocator.allocator();
	var _stackAllocator: NeverFailingAllocator = undefined;

	pub fn init() void {
		_stackAllocator = main.stackAllocator;
		main.stackAllocator = allocator;
	}
	pub fn deinit() void {
		main.stackAllocator = _stackAllocator;
		_stackAllocator = undefined;
		std.debug.print("Success\n", .{});
	}
};

test "ID.initFromPath directory+directory+file+extension" {
	IDTest.init();
	defer IDTest.deinit();

	const id = try ID.initFromPath(IDTest.allocator, "cubyz", "mountain/tall_mountain/slope6.zig.zon");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("mountain/tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromPath directory+file+extension" {
	IDTest.init();
	defer IDTest.deinit();

	const id = try ID.initFromPath(IDTest.allocator, "cubyz", "tall_mountain/slope6.zig.zon");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromPath file+extension" {
	IDTest.init();
	defer IDTest.deinit();

	const id = try ID.initFromPath(IDTest.allocator, "cubyz", "slope6.zig.zon");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromPath file" {
	IDTest.init();
	defer IDTest.deinit();

	const id = try ID.initFromPath(IDTest.allocator, "cubyz", "tall_mountain/slope6");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromString directory+directory+file" {
	IDTest.init();
	defer IDTest.deinit();

	const string = "cubyz:mountain/tall_mountain/slope6";
	const id = try ID.initFromString(IDTest.allocator, string);
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings(string, id.string);
	try std.testing.expect(&string[0] != &id.string[0]);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("mountain/tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromString directory+file" {
	IDTest.init();
	defer IDTest.deinit();

	const string = "cubyz:tall_mountain/slope6";
	const id = try ID.initFromString(IDTest.allocator, string);
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings(string, id.string);
	try std.testing.expect(&string[0] != &id.string[0]);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromString file" {
	IDTest.init();
	defer IDTest.deinit();

	const string = "cubyz:slope6";
	const id = try ID.initFromString(IDTest.allocator, string);
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings(string, id.string);
	try std.testing.expect(&string[0] != &id.string[0]);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromString with params" {
	IDTest.init();
	defer IDTest.deinit();

	const string = "cubyz:cloth/cyan:0b111111";
	const id = try ID.initFromString(IDTest.allocator, string);
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings(string, id.string);
	try std.testing.expect(&string[0] != &id.string[0]);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("cloth/cyan", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:cloth/cyan", try id.assetId());
	try std.testing.expectEqualStrings("0b111111", try id.paramsString());
}

test "ID.initFromString almost with params" {
	IDTest.init();
	defer IDTest.deinit();

	const id = try ID.initFromString(IDTest.allocator, "cubyz:cloth/cyan:");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:cloth/cyan", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("cloth/cyan", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:cloth/cyan", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromString violation: empty" {
	IDTest.init();
	defer IDTest.deinit();
	try std.testing.expectError(error.EmptyAddonName, ID.initFromString(IDTest.allocator, ""));
}

test "ID.initFromString violation: empty id" {
	IDTest.init();
	defer IDTest.deinit();
	try std.testing.expectError(error.EmptyAssetId, ID.initFromString(IDTest.allocator, "cubyz:"));
}

test "ID.initFromString violation: empty asset name" {
	IDTest.init();
	defer IDTest.deinit();
	try std.testing.expectError(error.EmptyAssetName, ID.initFromString(IDTest.allocator, "cubyz:foo/"));
}

test "ID.initFromString violation: char not allowed in addon name" {
	IDTest.init();
	defer IDTest.deinit();
	try std.testing.expectError(error.InvalidAddonName, ID.initFromString(IDTest.allocator, "cubyz!:bar"));
}

test "ID.initFromString violation: char not allowed in asset path" {
	IDTest.init();
	defer IDTest.deinit();
	try std.testing.expectError(error.InvalidAssetPath, ID.initFromString(IDTest.allocator, "cubyz:foo!/bar"));
}

test "ID.initFromString violation: char not allowed in asset name" {
	IDTest.init();
	defer IDTest.deinit();
	try std.testing.expectError(error.InvalidAssetName, ID.initFromString(IDTest.allocator, "cubyz:foo/bar!"));
}

test "ID.initFromSanitizedComponents directory+directory+file" {
	IDTest.init();
	defer IDTest.deinit();

	const id = ID.initFromSanitizedComponents(IDTest.allocator, "cubyz", "mountain/tall_mountain/slope6", "");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("mountain/tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromSanitizedComponents directory+directory+file+params" {
	IDTest.init();
	defer IDTest.deinit();

	const id = ID.initFromSanitizedComponents(IDTest.allocator, "cubyz", "mountain/tall_mountain/slope6", "foo");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6:foo", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("mountain/tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:mountain/tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("foo", try id.paramsString());
}

test "ID.initFromSanitizedComponents directory+file" {
	IDTest.init();
	defer IDTest.deinit();

	const id = ID.initFromSanitizedComponents(IDTest.allocator, "cubyz", "tall_mountain/slope6", "");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("tall_mountain/slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:tall_mountain/slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromSanitizedComponents file" {
	IDTest.init();
	defer IDTest.deinit();

	const id = ID.initFromSanitizedComponents(IDTest.allocator, "cubyz", "slope6", "");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromSanitizedString file" {
	IDTest.init();
	defer IDTest.deinit();

	const id = ID.initFromSanitizedString(IDTest.allocator, "cubyz:slope6");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:slope6", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:slope6", try id.assetId());
	try std.testing.expectEqualStrings("", try id.paramsString());
}

test "ID.initFromSanitizedString file with params" {
	IDTest.init();
	defer IDTest.deinit();

	const id = ID.initFromSanitizedString(IDTest.allocator, "cubyz:slope6:foo");
	defer id.deinit(IDTest.allocator);

	try std.testing.expectEqualStrings("cubyz:slope6:foo", id.string);
	try std.testing.expectEqualStrings("cubyz", try id.addonName());
	try std.testing.expectEqualStrings("slope6", try id.assetName());
	try std.testing.expectEqualStrings("cubyz:slope6", try id.assetId());
	try std.testing.expectEqualStrings("foo", try id.paramsString());
}

test "ID.HashContext" {
	IDTest.init();
	defer IDTest.deinit();

	const id0 = ID.initFromSanitizedString(IDTest.allocator, "cubyz:stone");
	defer id0.deinit(IDTest.allocator);

	const id1 = ID.initFromSanitizedString(IDTest.allocator, "cubyz:grass");
	defer id1.deinit(IDTest.allocator);

	var map: ID.IdToIdMap = .{};
	defer map.deinit(IDTest.allocator.allocator);

	try map.put(IDTest.allocator.allocator, id0, id1);
	try map.put(IDTest.allocator.allocator, id1, id0);

	try std.testing.expectEqualStrings(map.get(id0).?.string, id1.string);
	try std.testing.expectEqualStrings(map.get(id1).?.string, id0.string);
}

fn registerItem(assetFolder: []const u8, id: []const u8, zon: ZonElement) !void {
	var split = std.mem.splitScalar(u8, id, ':');
	const mod = split.first();
	var texturePath: []const u8 = &[0]u8{};
	var replacementTexturePath: []const u8 = &[0]u8{};
	var buf1: [4096]u8 = undefined;
	var buf2: [4096]u8 = undefined;
	if(zon.get(?[]const u8, "texture", null)) |texture| {
		texturePath = try std.fmt.bufPrint(&buf1, "{s}/{s}/items/textures/{s}", .{assetFolder, mod, texture});
		replacementTexturePath = try std.fmt.bufPrint(&buf2, "assets/{s}/items/textures/{s}", .{mod, texture});
	}
	_ = items_zig.register(assetFolder, texturePath, replacementTexturePath, id, zon);
}

fn registerTool(assetFolder: []const u8, id: []const u8, zon: ZonElement) void {
	items_zig.registerTool(assetFolder, id, zon);
}

fn registerBlock(assetFolder: []const u8, id: []const u8, zon: ZonElement) !void {
	if(zon == .null) std.log.err("Missing block: {s}. Replacing it with default block.", .{id});

	_ = blocks_zig.register(assetFolder, id, zon);
	blocks_zig.meshes.register(assetFolder, id, zon);
}

fn assignBlockItem(stringId: []const u8) !void {
	const block = blocks_zig.getTypeById(stringId);
	const item = items_zig.getByID(stringId) orelse unreachable;
	item.block = block;
}

fn registerBiome(numericId: u32, stringId: []const u8, zon: ZonElement) void {
	if(zon == .null) std.log.err("Missing biome: {s}. Replacing it with default biome.", .{stringId});
	biomes_zig.register(stringId, numericId, zon);
}

fn registerRecipesFromZon(zon: ZonElement) void {
	items_zig.registerRecipes(zon);
}

pub const Palette = struct { // MARK: Palette
	palette: main.List([]const u8),

	pub fn init(allocator: NeverFailingAllocator, zon: ZonElement, firstElement: ?[]const u8) !*Palette {
		const self = switch(zon) {
			.object => try loadFromZonLegacy(allocator, zon),
			.array, .null => try loadFromZon(allocator, zon),
			else => return error.InvalidPaletteFormat,
		};

		if(firstElement) |elem| {
			if(self.palette.items.len == 0) {
				self.palette.append(allocator.dupe(u8, elem));
			}
			if(!std.mem.eql(u8, self.palette.items[0], elem)) {
				return error.FistItemMismatch;
			}
		}
		return self;
	}
	fn loadFromZon(allocator: NeverFailingAllocator, zon: ZonElement) !*Palette {
		const items = zon.toSlice();

		const self = allocator.create(Palette);
		self.* = Palette{
			.palette = .initCapacity(allocator, items.len),
		};
		errdefer self.deinit();

		for(items) |name| {
			const stringId = name.as(?[]const u8, null) orelse return error.InvalidPaletteFormat;
			self.palette.appendAssumeCapacity(allocator.dupe(u8, stringId));
		}
		return self;
	}
	fn loadFromZonLegacy(allocator: NeverFailingAllocator, zon: ZonElement) !*Palette {
		// Using zon.object.count() here has the implication that array can not be sparse.
		const paletteLength = zon.object.count();
		const translationPalette = main.stackAllocator.alloc(?[]const u8, paletteLength);
		defer main.stackAllocator.free(translationPalette);

		@memset(translationPalette, null);

		var iterator = zon.object.iterator();
		while(iterator.next()) |entry| {
			const numericId = entry.value_ptr.as(?usize, null) orelse return error.InvalidPaletteFormat;
			const name = entry.key_ptr.*;

			if(numericId >= translationPalette.len) {
				std.log.err("ID {} ('{s}') out of range. This can be caused by palette having missing block IDs.", .{numericId, name});
				return error.SparsePaletteNotAllowed;
			}
			translationPalette[numericId] = name;
		}

		const self = allocator.create(Palette);
		self.* = Palette{
			.palette = .initCapacity(allocator, paletteLength),
		};
		errdefer self.deinit();

		for(translationPalette) |val| {
			self.palette.appendAssumeCapacity(allocator.dupe(u8, val orelse return error.MissingKeyInPalette));
			std.log.info("palette[{}]: {s}", .{self.palette.items.len, val.?});
		}
		return self;
	}

	pub fn deinit(self: *Palette) void {
		for(self.palette.items) |item| {
			self.palette.allocator.free(item);
		}
		const allocator = self.palette.allocator;
		self.palette.deinit();
		allocator.destroy(self);
	}

	pub fn add(self: *Palette, id: []const u8) void {
		self.palette.append(self.palette.allocator.dupe(u8, id));
	}

	pub fn storeToZon(self: *Palette, allocator: NeverFailingAllocator) ZonElement {
		const zon = ZonElement.initArray(allocator);

		zon.array.ensureCapacity(self.palette.items.len);

		for(self.palette.items) |item| {
			zon.append(item);
		}
		return zon;
	}

	pub fn size(self: *Palette) usize {
		return self.palette.items.len;
	}

	pub fn replaceEntry(self: *Palette, entryIndex: usize, newEntry: []const u8) void {
		self.palette.allocator.free(self.palette.items[entryIndex]);
		self.palette.items[entryIndex] = self.palette.allocator.dupe(u8, newEntry);
	}
};

var loadedAssets: bool = false;

pub fn loadWorldAssets(assetFolder: []const u8, blockPalette: *Palette, itemPalette: *Palette, biomePalette: *Palette) !void { // MARK: loadWorldAssets()
	if(loadedAssets) return; // The assets already got loaded by the server.
	loadedAssets = true;

	var worldArena: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer worldArena.deinit();
	const worldAllocator = worldArena.allocator();

	var worldAssets = common.clone(worldAllocator);
	worldAssets.read(worldAllocator, "assets/");

	errdefer unloadAssets();

	migrations_zig.registerAll(.block, &worldAssets.blockMigrations);
	migrations_zig.apply(.block, blockPalette);

	migrations_zig.registerAll(.biome, &worldAssets.biomeMigrations);
	migrations_zig.apply(.biome, biomePalette);

	// models:
	var modelIterator = worldAssets.models.iterator();
	while(modelIterator.next()) |entry| {
		_ = main.models.registerModel(entry.key_ptr.*, entry.value_ptr.*);
	}

	blocks_zig.meshes.registerBlockBreakingAnimation(assetFolder);

	// Blocks:
	// First blocks from the palette to enforce ID values.
	for(blockPalette.palette.items) |stringId| {
		try registerBlock(assetFolder, stringId, worldAssets.blocks.get(stringId) orelse .null);
	}

	// Then all the blocks that were missing in palette but are present in the game.
	var iterator = worldAssets.blocks.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		const zon = entry.value_ptr.*;

		if(blocks_zig.hasRegistered(stringId)) continue;

		try registerBlock(assetFolder, stringId, zon);
		blockPalette.add(stringId);
	}

	// Items:
	// First from the palette to enforce ID values.
	for(itemPalette.palette.items) |stringId| {
		std.debug.assert(!items_zig.hasRegistered(stringId));

		// Some items are created automatically from blocks.
		if(worldAssets.blocks.get(stringId)) |zon| {
			if(!zon.get(bool, "hasItem", true)) continue;
			try registerItem(assetFolder, stringId, zon.getChild("item"));
			if(worldAssets.items.get(stringId) != null) {
				std.log.err("Item {s} appears as standalone item and as block item.", .{stringId});
			}
			continue;
		}
		// Items not related to blocks should appear in items hash map.
		if(worldAssets.items.get(stringId)) |zon| {
			try registerItem(assetFolder, stringId, zon);
			continue;
		}
		std.log.err("Missing item: {s}. Replacing it with default item.", .{stringId});
		try registerItem(assetFolder, stringId, .null);
	}

	// Then missing block-items to keep backwards compatibility of ID order.
	for(blockPalette.palette.items) |stringId| {
		const zon = worldAssets.blocks.get(stringId) orelse .null;

		if(!zon.get(bool, "hasItem", true)) continue;
		if(items_zig.hasRegistered(stringId)) continue;

		try registerItem(assetFolder, stringId, zon.getChild("item"));
		itemPalette.add(stringId);
	}

	// And finally normal items.
	iterator = worldAssets.items.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		const zon = entry.value_ptr.*;

		if(items_zig.hasRegistered(stringId)) continue;
		std.debug.assert(zon != .null);

		try registerItem(assetFolder, stringId, zon);
		itemPalette.add(stringId);
	}

	// After we have registered all items and all blocks, we can assign block references to those that come from blocks.
	for(blockPalette.palette.items) |stringId| {
		const zon = worldAssets.blocks.get(stringId) orelse .null;

		if(!zon.get(bool, "hasItem", true)) continue;
		std.debug.assert(items_zig.hasRegistered(stringId));

		try assignBlockItem(stringId);
	}

	// tools:
	iterator = worldAssets.tools.iterator();
	while(iterator.next()) |entry| {
		registerTool(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
	}

	// block drops:
	blocks_zig.finishBlocks(worldAssets.blocks);

	iterator = worldAssets.recipes.iterator();
	while(iterator.next()) |entry| {
		registerRecipesFromZon(entry.value_ptr.*);
	}

	try sbb.registerBlueprints(&worldAssets.blueprints);
	try sbb.registerSBB(&worldAssets.structureBuildingBlocks);

	// Biomes:
	var nextBiomeNumericId: u32 = 0;
	for(biomePalette.palette.items) |id| {
		registerBiome(nextBiomeNumericId, id, worldAssets.biomes.get(id) orelse .null);
		nextBiomeNumericId += 1;
	}
	iterator = worldAssets.biomes.iterator();
	while(iterator.next()) |entry| {
		if(biomes_zig.hasRegistered(entry.key_ptr.*)) continue;
		registerBiome(nextBiomeNumericId, entry.key_ptr.*, entry.value_ptr.*);
		biomePalette.add(entry.key_ptr.*);
		nextBiomeNumericId += 1;
	}
	biomes_zig.finishLoading();

	// Register paths for asset hot reloading:
	var dir = std.fs.cwd().openDir("assets", .{.iterate = true}) catch |err| {
		std.log.err("Can't open asset path {s}: {s}", .{"assets", @errorName(err)});
		return;
	};
	defer dir.close();
	var dirIterator = dir.iterate();
	while(dirIterator.next() catch |err| blk: {
		std.log.err("Got error while iterating over asset path {s}: {s}", .{"assets", @errorName(err)});
		break :blk null;
	}) |addon| {
		if(addon.kind == .directory) {
			const path = std.fmt.allocPrintZ(main.stackAllocator.allocator, "assets/{s}/blocks/textures", .{addon.name}) catch unreachable;
			defer main.stackAllocator.free(path);
			std.fs.cwd().access(path, .{}) catch continue;
			main.utils.file_monitor.listenToPath(path, main.blocks.meshes.reloadTextures, 0);
		}
	}

	worldAssets.log(.world);
}

pub fn unloadAssets() void { // MARK: unloadAssets()
	if(!loadedAssets) return;
	loadedAssets = false;

	sbb.reset();
	blocks_zig.reset();
	items_zig.reset();
	biomes_zig.reset();
	migrations_zig.reset();
	main.models.reset();
	main.rotation.reset();

	// Remove paths from asset hot reloading:
	var dir = std.fs.cwd().openDir("assets", .{.iterate = true}) catch |err| {
		std.log.err("Can't open asset path {s}: {s}", .{"assets", @errorName(err)});
		return;
	};
	defer dir.close();
	var dirIterator = dir.iterate();
	while(dirIterator.next() catch |err| blk: {
		std.log.err("Got error while iterating over asset path {s}: {s}", .{"assets", @errorName(err)});
		break :blk null;
	}) |addon| {
		if(addon.kind == .directory) {
			const path = std.fmt.allocPrintZ(main.stackAllocator.allocator, "assets/{s}/blocks/textures", .{addon.name}) catch unreachable;
			defer main.stackAllocator.free(path);
			std.fs.cwd().access(path, .{}) catch continue;
			main.utils.file_monitor.removePath(path);
		}
	}
}

pub fn deinit() void {
	commonAssetArena.deinit();
	biomes_zig.deinit();
	blocks_zig.deinit();
	migrations_zig.deinit();
}
