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
	pub const BytesHashMap = std.StringHashMapUnmanaged([]const u8);
	pub const AddonNameToZonMap = std.StringHashMapUnmanaged(ZonElement);

	blocks: ZonHashMap,
	blockMigrations: AddonNameToZonMap,
	items: ZonHashMap,
	tools: ZonHashMap,
	biomes: ZonHashMap,
	biomeMigrations: AddonNameToZonMap,
	recipes: ZonHashMap,
	models: BytesHashMap,
	structureBuildingBlocks: ZonHashMap,
	blueprints: BytesHashMap,

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
			addon.readAllZon(allocator, "blocks", true, &self.blocks, &self.blockMigrations);
			addon.readAllZon(allocator, "items", true, &self.items, null);
			addon.readAllZon(allocator, "tools", true, &self.tools, null);
			addon.readAllZon(allocator, "biomes", true, &self.biomes, &self.biomeMigrations);
			addon.readAllZon(allocator, "recipes", false, &self.recipes, null);
			addon.readAllZon(allocator, "sbb", true, &self.structureBuildingBlocks, null);
			addon.readAllBlueprints(allocator, "sbb", &self.blueprints);
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

		pub fn readAllZon(addon: Addon, allocator: NeverFailingAllocator, assetType: []const u8, hasDefaults: bool, output: *ZonHashMap, migrations: ?*AddonNameToZonMap) void {
			var assetsDirectory = addon.dir.openDir(assetType, .{.iterate = true}) catch |err| {
				if(err != error.FileNotFound) {
					std.log.err("Could not open addon directory {s}: {s}", .{assetType, @errorName(err)});
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
				std.log.err("Got error while iterating addon directory {s}: {s}", .{assetType, @errorName(err)});
				break :blk null;
			}) |entry| {
				if(entry.kind != .file) continue;
				if(std.ascii.startsWithIgnoreCase(entry.basename, "_defaults")) continue;
				if(!std.ascii.endsWithIgnoreCase(entry.basename, ".zon")) continue;
				if(std.ascii.startsWithIgnoreCase(entry.path, "textures")) continue;
				if(std.ascii.eqlIgnoreCase(entry.basename, "_migrations.zig.zon")) continue;

				const id = createAssetStringID(allocator, addon.name, entry.path);

				const zon = files.Dir.init(assetsDirectory).readToZon(allocator, entry.path) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{assetType, entry.path, @errorName(err)});
					continue;
				};
				if(hasDefaults) {
					zon.join(defaultsStorage.get(entry.dir));
				}
				output.put(allocator.allocator, id, zon) catch unreachable;
			}
			if(migrations != null) blk: {
				const zon = files.Dir.init(assetsDirectory).readToZon(allocator, "_migrations.zig.zon") catch |err| {
					if(err != error.FileNotFound) std.log.err("Cannot read {s} migration file for addon {s}", .{assetType, addon.name});
					break :blk;
				};
				migrations.?.put(allocator.allocator, allocator.dupe(u8, addon.name), zon) catch unreachable;
			}
		}

		pub fn readAllBlueprints(addon: Addon, allocator: NeverFailingAllocator, subPath: []const u8, output: *BytesHashMap) void {
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

				const id = createAssetStringID(allocator, addon.name, entry.path);

				const data = files.Dir.init(assetsDirectory).read(allocator, entry.path) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.put(allocator.allocator, id, data) catch unreachable;
			}
		}

		pub fn readAllModels(addon: Addon, allocator: NeverFailingAllocator, output: *BytesHashMap) void {
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

				const id = createAssetStringID(allocator, addon.name, entry.path);

				const string = assetsDirectory.readFileAlloc(allocator.allocator, entry.path, std.math.maxInt(usize)) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.put(allocator.allocator, id, string) catch unreachable;
			}
		}
	};
};

fn createAssetStringID(
	externalAllocator: NeverFailingAllocator,
	addonName: []const u8,
	relativeFilePath: []const u8,
) []u8 {
	const baseNameEndIndex = if(std.ascii.endsWithIgnoreCase(relativeFilePath, ".zig.zon")) relativeFilePath.len - ".zig.zon".len else std.mem.lastIndexOfScalar(u8, relativeFilePath, '.') orelse relativeFilePath.len;
	const pathNoExtension: []const u8 = relativeFilePath[0..baseNameEndIndex];

	const assetId: []u8 = externalAllocator.alloc(u8, addonName.len + 1 + pathNoExtension.len);

	@memcpy(assetId[0..addonName.len], addonName);
	assetId[addonName.len] = ':';

	// Convert from windows to unix style separators.
	for(0..pathNoExtension.len) |i| {
		if(pathNoExtension[i] == '\\') {
			assetId[addonName.len + 1 + i] = '/';
		} else {
			assetId[addonName.len + 1 + i] = pathNoExtension[i];
		}
	}

	return assetId;
}

pub fn init() void {
	biomes_zig.init();
	blocks_zig.init();

	commonAssetArena = .init(main.globalAllocator);
	commonAssetAllocator = commonAssetArena.allocator();

	common = .init();
	common.read(commonAssetAllocator, "assets/");
	common.log(.common);
}

fn registerItem(assetFolder: []const u8, id: []const u8, zon: ZonElement) !void {
	var split = std.mem.splitScalar(u8, id, ':');
	const mod = split.first();
	var texturePath: []const u8 = &.{};
	defer main.stackAllocator.free(texturePath);
	var replacementTexturePath: []const u8 = &.{};
	defer main.stackAllocator.free(replacementTexturePath);
	if(zon.get(?[]const u8, "texture", null)) |texture| {
		texturePath = try std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/items/textures/{s}", .{assetFolder, mod, texture});
		replacementTexturePath = try std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/items/textures/{s}", .{mod, texture});
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
	// TODO: This must be gone in PixelGuys/Cubyz#1205
	const index = (items_zig.BaseItemIndex.fromId(stringId) orelse unreachable).index;
	const item = &items_zig.itemList[index];
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

pub fn loadWorldAssets(assetFolder: []const u8, blockPalette: *Palette, itemPalette: *Palette, toolPalette: *Palette, biomePalette: *Palette) !void { // MARK: loadWorldAssets()
	if(loadedAssets) return; // The assets already got loaded by the server.
	loadedAssets = true;

	var worldArena: NeverFailingArenaAllocator = .init(main.stackAllocator);
	defer worldArena.deinit();
	const worldAllocator = worldArena.allocator();

	var worldAssets = common.clone(worldAllocator);
	worldAssets.read(worldAllocator, assetFolder);

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

	for(toolPalette.palette.items) |id| {
		registerTool(assetFolder, id, worldAssets.tools.get(id) orelse .null);
	}

	// tools:
	iterator = worldAssets.tools.iterator();
	while(iterator.next()) |entry| {
		const id = entry.key_ptr.*;
		if(items_zig.hasRegisteredTool(id)) continue;
		registerTool(assetFolder, id, entry.value_ptr.*);
		toolPalette.add(id);
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
	main.Tag.resetTags();

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
