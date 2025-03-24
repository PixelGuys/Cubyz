const std = @import("std");

const blocks_zig = @import("blocks.zig");
const items_zig = @import("items.zig");
const migrations_zig = @import("migrations.zig");
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main.zig");
const biomes_zig = main.server.terrain.biomes;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

var arena: main.heap.NeverFailingArenaAllocator = undefined;
var arenaAllocator: NeverFailingAllocator = undefined;
var commonBlocks: std.StringHashMap(ZonElement) = undefined;
var commonBlockMigrations: std.StringHashMap(ZonElement) = undefined;
var commonItems: std.StringHashMap(ZonElement) = undefined;
var commonTools: std.StringHashMap(ZonElement) = undefined;
var commonBiomes: std.StringHashMap(ZonElement) = undefined;
var commonBiomeMigrations: std.StringHashMap(ZonElement) = undefined;
var commonRecipes: std.StringHashMap(ZonElement) = undefined;
var commonModels: std.StringHashMap([]const u8) = undefined;

pub fn init() void {
	biomes_zig.init();
	blocks_zig.init();

	arena = .init(main.globalAllocator);
	arenaAllocator = arena.allocator();
	commonBlocks = .init(arenaAllocator.allocator);
	commonBlockMigrations = .init(arenaAllocator.allocator);
	commonItems = .init(arenaAllocator.allocator);
	commonTools = .init(arenaAllocator.allocator);
	commonBiomes = .init(arenaAllocator.allocator);
	commonBiomeMigrations = .init(arenaAllocator.allocator);
	commonRecipes = .init(arenaAllocator.allocator);
	commonModels = .init(arenaAllocator.allocator);

	readAssets(
		arenaAllocator,
		"assets/",
		&commonBlocks,
		&commonBlockMigrations,
		&commonItems,
		&commonTools,
		&commonBiomes,
		&commonBlockMigrations,
		&commonRecipes,
		&commonModels,
	);

	std.log.info(
		"Finished assets init with {} blocks ({} migrations), {} items, {} tools. {} biomes ({} migrations), {} recipes",
		.{commonBlocks.count(), commonBlockMigrations.count(), commonItems.count(), commonTools.count(), commonBiomes.count(), commonBiomeMigrations.count(), commonRecipes.count()},
	);
}

fn readDefaultFile(allocator: NeverFailingAllocator, dir: std.fs.Dir) !ZonElement {
	if(main.files.Dir.init(dir).readToZon(allocator, "_defaults.zig.zon")) |zon| {
		return zon;
	} else |err| {
		if(err != error.FileNotFound) return err;
	}

	if(main.files.Dir.init(dir).readToZon(allocator, "_defaults.zon")) |zon| {
		return zon;
	} else |err| {
		if(err != error.FileNotFound) return err;
	}

	return .null;
}

/// Reads all asset `.zig.zon` files recursively from all sub folders.
///
/// Files red are stored in output hashmap with asset ID as key.
/// Asset ID are constructed as `{addonName}:{relativePathNoSuffix}`.
/// relativePathNoSuffix is always unix style path with all extensions removed.
pub fn readAllZonFilesInAddons(
	externalAllocator: NeverFailingAllocator,
	addons: main.List(std.fs.Dir),
	addonNames: main.List([]const u8),
	subPath: []const u8,
	defaults: bool,
	output: *std.StringHashMap(ZonElement),
	migrations: ?*std.StringHashMap(ZonElement),
) void {
	for(addons.items, addonNames.items) |addon, addonName| {
		var dir = addon.openDir(subPath, .{.iterate = true}) catch |err| {
			if(err != error.FileNotFound) {
				std.log.err("Could not open addon directory {s}: {s}", .{subPath, @errorName(err)});
			}
			continue;
		};
		defer dir.close();

		var defaultsArena: main.heap.NeverFailingArenaAllocator = .init(main.stackAllocator);
		defer defaultsArena.deinit();

		const defaultsArenaAllocator = defaultsArena.allocator();

		var defaultMap = std.StringHashMap(ZonElement).init(defaultsArenaAllocator.allocator);

		var walker = dir.walk(main.stackAllocator.allocator) catch unreachable;
		defer walker.deinit();

		while(walker.next() catch |err| blk: {
			std.log.err("Got error while iterating addon directory {s}: {s}", .{subPath, @errorName(err)});
			break :blk null;
		}) |entry| {
			if(entry.kind == .file and
				!std.ascii.startsWithIgnoreCase(entry.basename, "_defaults") and
				std.ascii.endsWithIgnoreCase(entry.basename, ".zon") and
				!std.ascii.startsWithIgnoreCase(entry.path, "textures") and
				!std.ascii.eqlIgnoreCase(entry.basename, "_migrations.zig.zon"))
			{
				const id = createAssetStringID(externalAllocator, addonName, entry.path);

				const zon = main.files.Dir.init(dir).readToZon(externalAllocator, entry.path) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};

				if(defaults) {
					const path = entry.dir.realpathAlloc(main.stackAllocator.allocator, ".") catch unreachable;
					defer main.stackAllocator.free(path);

					const result = defaultMap.getOrPut(path) catch unreachable;

					if(!result.found_existing) {
						result.key_ptr.* = defaultsArenaAllocator.dupe(u8, path);
						const default: ZonElement = readDefaultFile(defaultsArenaAllocator, entry.dir) catch |err| blk: {
							std.log.err("Failed to read default file: {s}", .{@errorName(err)});
							break :blk .null;
						};

						result.value_ptr.* = default;
					}

					zon.join(result.value_ptr.*);
				}
				output.put(id, zon) catch unreachable;
			}
		}
		if(migrations != null) blk: {
			const zon = main.files.Dir.init(dir).readToZon(externalAllocator, "_migrations.zig.zon") catch |err| {
				if(err != error.FileNotFound) std.log.err("Cannot read {s} migration file for addon {s}", .{subPath, addonName});
				break :blk;
			};
			migrations.?.put(externalAllocator.dupe(u8, addonName), zon) catch unreachable;
		}
	}
}
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
/// Reads obj files recursively from all subfolders.
pub fn readAllObjFilesInAddonsHashmap(
	externalAllocator: NeverFailingAllocator,
	addons: main.List(std.fs.Dir),
	addonNames: main.List([]const u8),
	subPath: []const u8,
	output: *std.StringHashMap([]const u8),
) void {
	for(addons.items, addonNames.items) |addon, addonName| {
		var dir = addon.openDir(subPath, .{.iterate = true}) catch |err| {
			if(err != error.FileNotFound) {
				std.log.err("Could not open addon directory {s}: {s}", .{subPath, @errorName(err)});
			}
			continue;
		};
		defer dir.close();

		var walker = dir.walk(main.stackAllocator.allocator) catch unreachable;
		defer walker.deinit();

		while(walker.next() catch |err| blk: {
			std.log.err("Got error while iterating addon directory {s}: {s}", .{subPath, @errorName(err)});
			break :blk null;
		}) |entry| {
			if(entry.kind == .file and std.ascii.endsWithIgnoreCase(entry.basename, ".obj")) {
				const id: []u8 = createAssetStringID(externalAllocator, addonName, entry.path);

				const string = dir.readFileAlloc(externalAllocator.allocator, entry.path, std.math.maxInt(usize)) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.put(id, string) catch unreachable;
			}
		}
	}
}

pub fn readAssets(
	externalAllocator: NeverFailingAllocator,
	assetPath: []const u8,
	blocks: *std.StringHashMap(ZonElement),
	blockMigrations: *std.StringHashMap(ZonElement),
	items: *std.StringHashMap(ZonElement),
	tools: *std.StringHashMap(ZonElement),
	biomes: *std.StringHashMap(ZonElement),
	biomeMigrations: *std.StringHashMap(ZonElement),
	recipes: *std.StringHashMap(ZonElement),
	models: *std.StringHashMap([]const u8),
) void {
	var addons = main.List(std.fs.Dir).init(main.stackAllocator);
	defer addons.deinit();
	var addonNames = main.List([]const u8).init(main.stackAllocator);
	defer addonNames.deinit();

	{ // Find all the sub-directories to the assets folder.
		var dir = std.fs.cwd().openDir(assetPath, .{.iterate = true}) catch |err| {
			std.log.err("Can't open asset path {s}: {s}", .{assetPath, @errorName(err)});
			return;
		};
		defer dir.close();
		var iterator = dir.iterate();
		while(iterator.next() catch |err| blk: {
			std.log.err("Got error while iterating over asset path {s}: {s}", .{assetPath, @errorName(err)});
			break :blk null;
		}) |addon| {
			if(addon.kind == .directory) {
				addons.append(dir.openDir(addon.name, .{}) catch |err| {
					std.log.err("Got error while reading addon {s} from {s}: {s}", .{addon.name, assetPath, @errorName(err)});
					continue;
				});
				addonNames.append(main.stackAllocator.dupe(u8, addon.name));
			}
		}
	}
	defer for(addons.items, addonNames.items) |*dir, addonName| {
		dir.close();
		main.stackAllocator.free(addonName);
	};

	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "blocks", true, blocks, blockMigrations);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "items", true, items, null);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "tools", true, tools, null);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "biomes", true, biomes, biomeMigrations);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "recipes", false, recipes, null);
	readAllObjFilesInAddonsHashmap(externalAllocator, addons, addonNames, "models", models);
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

	var blocks = commonBlocks.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer blocks.clearAndFree();
	var blockMigrations = commonBlockMigrations.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer blockMigrations.clearAndFree();
	var items = commonItems.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer items.clearAndFree();
	var tools = commonTools.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer tools.clearAndFree();
	var biomes = commonBiomes.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer biomes.clearAndFree();
	var biomeMigrations = commonBiomeMigrations.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer biomeMigrations.clearAndFree();
	var recipes = commonRecipes.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer recipes.clearAndFree();
	var models = commonModels.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer models.clearAndFree();

	readAssets(
		arenaAllocator,
		assetFolder,
		&blocks,
		&blockMigrations,
		&items,
		&tools,
		&biomes,
		&biomeMigrations,
		&recipes,
		&models,
	);
	errdefer unloadAssets();

	migrations_zig.registerAll(.block, &blockMigrations);
	migrations_zig.apply(.block, blockPalette);

	migrations_zig.registerAll(.biome, &biomeMigrations);
	migrations_zig.apply(.biome, biomePalette);

	// models:
	var modelIterator = models.iterator();
	while(modelIterator.next()) |entry| {
		_ = main.models.registerModel(entry.key_ptr.*, entry.value_ptr.*);
	}

	blocks_zig.meshes.registerBlockBreakingAnimation(assetFolder);

	// Blocks:
	// First blocks from the palette to enforce ID values.
	for(blockPalette.palette.items) |stringId| {
		try registerBlock(assetFolder, stringId, blocks.get(stringId) orelse .null);
	}

	// Then all the blocks that were missing in palette but are present in the game.
	var iterator = blocks.iterator();
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
		if(blocks.get(stringId)) |zon| {
			if(!zon.get(bool, "hasItem", true)) continue;
			try registerItem(assetFolder, stringId, zon.getChild("item"));
			if(items.get(stringId) != null) {
				std.log.err("Item {s} appears as standalone item and as block item.", .{stringId});
			}
			continue;
		}
		// Items not related to blocks should appear in items hash map.
		if(items.get(stringId)) |zon| {
			try registerItem(assetFolder, stringId, zon);
			continue;
		}
		std.log.err("Missing item: {s}. Replacing it with default item.", .{stringId});
		try registerItem(assetFolder, stringId, .null);
	}

	// Then missing block-items to keep backwards compatibility of ID order.
	for(blockPalette.palette.items) |stringId| {
		const zon = blocks.get(stringId) orelse .null;

		if(!zon.get(bool, "hasItem", true)) continue;
		if(items_zig.hasRegistered(stringId)) continue;

		try registerItem(assetFolder, stringId, zon.getChild("item"));
		itemPalette.add(stringId);
	}

	// And finally normal items.
	iterator = items.iterator();
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
		const zon = blocks.get(stringId) orelse .null;

		if(!zon.get(bool, "hasItem", true)) continue;
		std.debug.assert(items_zig.hasRegistered(stringId));

		try assignBlockItem(stringId);
	}

	// tools:
	iterator = tools.iterator();
	while(iterator.next()) |entry| {
		registerTool(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
	}

	// block drops:
	blocks_zig.finishBlocks(blocks);

	iterator = recipes.iterator();
	while(iterator.next()) |entry| {
		registerRecipesFromZon(entry.value_ptr.*);
	}

	// Biomes:
	var nextBiomeNumericId: u32 = 0;
	for(biomePalette.palette.items) |id| {
		registerBiome(nextBiomeNumericId, id, biomes.get(id) orelse .null);
		nextBiomeNumericId += 1;
	}
	iterator = biomes.iterator();
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

	std.log.info(
		"Finished registering assets with {} blocks ({} migrations), {} items {} tools. {} biomes ({} migrations), {} recipes and {} models",
		.{blocks.count(), blockMigrations.count(), items.count(), tools.count(), biomes.count(), biomeMigrations.count(), recipes.count(), models.count()},
	);
}

pub fn unloadAssets() void { // MARK: unloadAssets()
	if(!loadedAssets) return;
	loadedAssets = false;

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
	arena.deinit();
	biomes_zig.deinit();
	blocks_zig.deinit();
	migrations_zig.deinit();
}
