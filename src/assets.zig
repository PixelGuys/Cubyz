const std = @import("std");

const blocks_zig = @import("blocks.zig");
const items_zig = @import("items.zig");
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main.zig");
const biomes_zig = main.server.terrain.biomes;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

var arena: main.utils.NeverFailingArenaAllocator = undefined;
var arenaAllocator: NeverFailingAllocator = undefined;
var commonBlocks: std.StringHashMap(ZonElement) = undefined;
var commonBiomes: std.StringHashMap(ZonElement) = undefined;
var commonItems: std.StringHashMap(ZonElement) = undefined;
var commonRecipes: std.StringHashMap(ZonElement) = undefined;
var commonModels: std.StringHashMap([]const u8) = undefined;

fn readDefaultFile(allocator: NeverFailingAllocator, dir: std.fs.Dir) !ZonElement {
	if (dir.openFile("_defaults.zig.zon", .{})) |val| {
		const string = try val.readToEndAlloc(main.stackAllocator.allocator, std.math.maxInt(usize));
		defer main.stackAllocator.free(string);

		return ZonElement.parseFromString(allocator, string);
	} else |err| {
		if (err != error.FileNotFound) {
			return err;
		}
	}

	if (dir.openFile("_defaults.zon", .{})) |val| {
		const string = try val.readToEndAlloc(main.stackAllocator.allocator, std.math.maxInt(usize));
		defer main.stackAllocator.free(string);

		return ZonElement.parseFromString(allocator, string);
	} else |err| {
		if (err != error.FileNotFound) {
			return err;
		}
	}

	return .null;
}

/// Reads .zig.zon files recursively from all subfolders.
pub fn readAllZonFilesInAddons(externalAllocator: NeverFailingAllocator, addons: main.List(std.fs.Dir), addonNames: main.List([]const u8), subPath: []const u8, defaults: bool, output: *std.StringHashMap(ZonElement)) void {
	for(addons.items, addonNames.items) |addon, addonName| {
		var dir = addon.openDir(subPath, .{.iterate = true}) catch |err| {
			if(err != error.FileNotFound) {
				std.log.err("Could not open addon directory {s}: {s}", .{subPath, @errorName(err)});
			}
			continue;
		};
		defer dir.close();

		var defaultsArena: main.utils.NeverFailingArenaAllocator = .init(main.stackAllocator);
		defer defaultsArena.deinit();

		const defaultsArenaAllocator = defaultsArena.allocator();

		var defaultMap = std.StringHashMap(ZonElement).init(defaultsArenaAllocator.allocator);

		var walker = dir.walk(main.stackAllocator.allocator) catch unreachable;
		defer walker.deinit();

		while(walker.next() catch |err| blk: {
			std.log.err("Got error while iterating addon directory {s}: {s}", .{subPath, @errorName(err)});
			break :blk null;
		}) |entry| {
			if(entry.kind == .file and !std.ascii.startsWithIgnoreCase(entry.basename, "_defaults") and std.ascii.endsWithIgnoreCase(entry.basename, ".zon") and !std.ascii.startsWithIgnoreCase(entry.path, "textures")) {
				const fileSuffixLen = if(std.ascii.endsWithIgnoreCase(entry.basename, ".zig.zon")) ".zig.zon".len else ".zon".len;
				const folderName = addonName;
				const id: []u8 = externalAllocator.alloc(u8, folderName.len + 1 + entry.path.len - fileSuffixLen);
				errdefer externalAllocator.free(id);
				@memcpy(id[0..folderName.len], folderName);
				id[folderName.len] = ':';
				for(0..entry.path.len - fileSuffixLen) |i| {
					if(entry.path[i] == '\\') { // Convert windows path seperators
						id[folderName.len+1+i] = '/';
					} else {
						id[folderName.len+1+i] = entry.path[i];
					}
				}

				const string = dir.readFileAlloc(main.stackAllocator.allocator, entry.path, std.math.maxInt(usize)) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				defer main.stackAllocator.free(string);

				const zon = ZonElement.parseFromString(externalAllocator, string);
				if (defaults) {
					const path = entry.dir.realpathAlloc(main.stackAllocator.allocator, ".") catch unreachable;
					defer main.stackAllocator.free(path);

					const result = defaultMap.getOrPut(path) catch unreachable;

					if (!result.found_existing) {
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
	}
}
/// Reads text files recursively from all subfolders.
pub fn readAllFilesInAddons(externalAllocator: NeverFailingAllocator, addons: main.List(std.fs.Dir), subPath: []const u8, output: *main.List([]const u8)) void {
	for(addons.items) |addon| {
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
			if(entry.kind == .file) {
				const string = dir.readFileAlloc(externalAllocator.allocator, entry.path, std.math.maxInt(usize)) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.append(string);
			}
		}
	}
}
/// Reads obj files recursively from all subfolders.
pub fn readAllObjFilesInAddonsHashmap(externalAllocator: NeverFailingAllocator, addons: main.List(std.fs.Dir), addonNames: main.List([]const u8), subPath: []const u8, output: *std.StringHashMap([]const u8)) void {
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
				const folderName = addonName;
				const id: []u8 = externalAllocator.alloc(u8, folderName.len + 1 + entry.path.len - 4);
				errdefer externalAllocator.free(id);
				@memcpy(id[0..folderName.len], folderName);
				id[folderName.len] = ':';
				for(0..entry.path.len-4) |i| {
					if(entry.path[i] == '\\') { // Convert windows path seperators
						id[folderName.len+1+i] = '/';
					} else {
						id[folderName.len+1+i] = entry.path[i];
					}
				}

				const string = dir.readFileAlloc(externalAllocator.allocator, entry.path, std.math.maxInt(usize)) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				output.put(id, string) catch unreachable;
			}
		}
	}
}

pub fn readAssets(externalAllocator: NeverFailingAllocator, assetPath: []const u8, blocks: *std.StringHashMap(ZonElement), items: *std.StringHashMap(ZonElement), biomes: *std.StringHashMap(ZonElement), recipes: *std.StringHashMap(ZonElement), models: *std.StringHashMap([]const u8)) void {
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

	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "blocks", true, blocks);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "items", true, items);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "biomes", true, biomes);
	readAllZonFilesInAddons(externalAllocator, addons, addonNames, "recipes", false, recipes);
	readAllObjFilesInAddonsHashmap(externalAllocator, addons, addonNames, "models", models);
}

pub fn init() void {
	biomes_zig.init();
	blocks_zig.init();
	arena = .init(main.globalAllocator);
	arenaAllocator = arena.allocator();
	commonBlocks = .init(arenaAllocator.allocator);
	commonItems = .init(arenaAllocator.allocator);
	commonBiomes = .init(arenaAllocator.allocator);
	commonRecipes = .init(arenaAllocator.allocator);
	commonModels = .init(arenaAllocator.allocator);

	readAssets(arenaAllocator, "assets/", &commonBlocks, &commonItems, &commonBiomes, &commonRecipes, &commonModels);
}

fn registerItem(assetFolder: []const u8, id: []const u8, zon: ZonElement) !*items_zig.BaseItem {
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
	return items_zig.register(assetFolder, texturePath, replacementTexturePath, id, zon);
}

fn registerBlock(assetFolder: []const u8, id: []const u8, zon: ZonElement) !void {
	const block = blocks_zig.register(assetFolder, id, zon);
	blocks_zig.meshes.register(assetFolder, id, zon);

	if(zon.get(bool, "hasItem", true)) {
		const item = try registerItem(assetFolder, id, zon.getChild("item"));
		item.block = block;
	}
}

fn registerRecipesFromZon(zon: ZonElement) void {
	items_zig.registerRecipes(zon);
}

pub const Palette = struct { // MARK: Palette
	palette: main.List([]const u8),
	pub fn init(allocator: NeverFailingAllocator, zon: ZonElement, firstElement: ?[]const u8) !*Palette {
		const self = allocator.create(Palette);
		self.* = Palette {
			.palette = .init(allocator),
		};
		errdefer self.deinit();
		if(zon != .object or zon.object.count() == 0) {
			if(firstElement) |elem| self.palette.append(allocator.dupe(u8, elem));
		} else {
			const palette = main.stackAllocator.alloc(?[]const u8, zon.object.count());
			defer main.stackAllocator.free(palette);
			for(palette) |*val| {
				val.* = null;
			}
			var iterator = zon.object.iterator();
			while(iterator.next()) |entry| {
				palette[entry.value_ptr.as(usize, std.math.maxInt(usize))] = entry.key_ptr.*;
			}
			if(firstElement) |elem| std.debug.assert(std.mem.eql(u8, palette[0].?, elem));
			for(palette) |val| {
				std.log.info("palette[{}]: {s}", .{self.palette.items.len, val.?});
				self.palette.append(allocator.dupe(u8, val orelse return error.MissingKeyInPalette));
			}
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

	pub fn save(self: *Palette, allocator: NeverFailingAllocator) ZonElement {
		const zon = ZonElement.initObject(allocator);
		errdefer zon.free(allocator);
		for(self.palette.items, 0..) |item, i| {
			zon.put(item, i);
		}
		return zon;
	}
};

var loadedAssets: bool = false;

pub fn loadWorldAssets(assetFolder: []const u8, blockPalette: *Palette, biomePalette: *Palette) !void { // MARK: loadWorldAssets()
	if(loadedAssets) return; // The assets already got loaded by the server.
	loadedAssets = true;
	var blocks = commonBlocks.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer blocks.clearAndFree();
	var items = commonItems.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer items.clearAndFree();
	var biomes = commonBiomes.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer biomes.clearAndFree();
	var recipes = commonRecipes.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer recipes.clearAndFree();
	var models = commonModels.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer models.clearAndFree();

	readAssets(arenaAllocator, assetFolder, &blocks, &items, &biomes, &recipes, &models);
	errdefer unloadAssets();

	var modelIterator = models.iterator();
	while (modelIterator.next()) |entry| {
		_ = main.models.registerModel(entry.key_ptr.*,  entry.value_ptr.*);
	}

	// blocks:
	blocks_zig.meshes.registerBlockBreakingAnimation(assetFolder);
	for(blockPalette.palette.items) |id| {
		const nullValue = blocks.get(id);
		var zon: ZonElement = undefined;
		if(nullValue) |value| {
			zon = value;
		} else {
			std.log.err("Missing block: {s}. Replacing it with default block.", .{id});
			zon = .null;
		}
		try registerBlock(assetFolder, id, zon);
	}
	var iterator = blocks.iterator();
	while(iterator.next()) |entry| {
		if(blocks_zig.hasRegistered(entry.key_ptr.*)) continue;
		try registerBlock(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
		blockPalette.add(entry.key_ptr.*);
	}

	// items:
	iterator = items.iterator();
	while(iterator.next()) |entry| {
		_ = try registerItem(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
	}

	// block drops:
	blocks_zig.finishBlocks(blocks);

	iterator = recipes.iterator();
	while(iterator.next()) |entry| {
		registerRecipesFromZon(entry.value_ptr.*);
	}

	// Biomes:
	var i: u32 = 0;
	for(biomePalette.palette.items) |id| {
		const nullValue = biomes.get(id);
		var zon: ZonElement = undefined;
		if(nullValue) |value| {
			zon = value;
		} else {
			std.log.err("Missing biomes: {s}. Replacing it with default biomes.", .{id});
			zon = .null;
		}
		biomes_zig.register(id, i, zon);
		i += 1;
	}
	iterator = biomes.iterator();
	while(iterator.next()) |entry| {
		if(biomes_zig.hasRegistered(entry.key_ptr.*)) continue;
		biomes_zig.register(entry.key_ptr.*, i, entry.value_ptr.*);
		biomePalette.add(entry.key_ptr.*);
		i += 1;
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
}

pub fn unloadAssets() void { // MARK: unloadAssets()
	if(!loadedAssets) return;
	loadedAssets = false;
	blocks_zig.reset();
	items_zig.reset();
	biomes_zig.reset();

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
}
