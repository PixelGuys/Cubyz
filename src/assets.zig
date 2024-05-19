const std = @import("std");

const blocks_zig = @import("blocks.zig");
const items_zig = @import("items.zig");
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const biomes_zig = main.server.terrain.biomes;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

var arena: main.utils.NeverFailingArenaAllocator = undefined;
var arenaAllocator: NeverFailingAllocator = undefined;
var commonBlocks: std.StringHashMap(JsonElement) = undefined;
var commonBiomes: std.StringHashMap(JsonElement) = undefined;
var commonItems: std.StringHashMap(JsonElement) = undefined;
var commonRecipes: main.List([]const u8) = undefined;

/// Reads json files recursively from all subfolders.
pub fn readAllJsonFilesInAddons(externalAllocator: NeverFailingAllocator, addons: main.List(std.fs.Dir), addonNames: main.List([]const u8), subPath: []const u8, output: *std.StringHashMap(JsonElement)) void {
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
			if(entry.kind == .file and std.ascii.endsWithIgnoreCase(entry.basename, ".json") and !std.ascii.startsWithIgnoreCase(entry.path, "textures")) {
				const folderName = addonName;
				const id: []u8 = externalAllocator.alloc(u8, folderName.len + 1 + entry.path.len - 5);
				errdefer externalAllocator.free(id);
				@memcpy(id[0..folderName.len], folderName);
				id[folderName.len] = ':';
				for(0..entry.path.len-5) |i| {
					if(entry.path[i] == '\\') { // Convert windows path seperators
						id[folderName.len+1+i] = '/';
					} else {
						id[folderName.len+1+i] = entry.path[i];
					}
				}

				const file = dir.openFile(entry.path, .{}) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				defer file.close();
				const string = file.readToEndAlloc(main.stackAllocator.allocator, std.math.maxInt(usize)) catch unreachable;
				defer main.stackAllocator.free(string);
				output.put(id, JsonElement.parseFromString(externalAllocator, string)) catch unreachable;
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
				const file = dir.openFile(entry.path, .{}) catch |err| {
					std.log.err("Could not open {s}/{s}: {s}", .{subPath, entry.path, @errorName(err)});
					continue;
				};
				defer file.close();
				const string = file.readToEndAlloc(externalAllocator.allocator, std.math.maxInt(usize)) catch unreachable;
				output.append(string);
			}
		}
	}
}

pub fn readAssets(externalAllocator: NeverFailingAllocator, assetPath: []const u8, blocks: *std.StringHashMap(JsonElement), items: *std.StringHashMap(JsonElement), biomes: *std.StringHashMap(JsonElement), recipes: *main.List([]const u8)) void {
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

	readAllJsonFilesInAddons(externalAllocator, addons, addonNames, "blocks", blocks);
	readAllJsonFilesInAddons(externalAllocator, addons, addonNames, "items", items);
	readAllJsonFilesInAddons(externalAllocator, addons, addonNames, "biomes", biomes);
	readAllFilesInAddons(externalAllocator, addons, "recipes", recipes);
}

pub fn init() void {
	biomes_zig.init();
	blocks_zig.init();
	arena = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);
	arenaAllocator = arena.allocator();
	commonBlocks = std.StringHashMap(JsonElement).init(arenaAllocator.allocator);
	commonItems = std.StringHashMap(JsonElement).init(arenaAllocator.allocator);
	commonBiomes = std.StringHashMap(JsonElement).init(arenaAllocator.allocator);
	commonRecipes = main.List([]const u8).init(arenaAllocator);

	readAssets(arenaAllocator, "assets/", &commonBlocks, &commonItems, &commonBiomes, &commonRecipes);
}

fn registerItem(assetFolder: []const u8, id: []const u8, json: JsonElement) !*items_zig.BaseItem {
	var split = std.mem.split(u8, id, ":");
	const mod = split.first();
	var texturePath: []const u8 = &[0]u8{};
	var replacementTexturePath: []const u8 = &[0]u8{};
	var buf1: [4096]u8 = undefined;
	var buf2: [4096]u8 = undefined;
	if(json.get(?[]const u8, "texture", null)) |texture| {
		texturePath = try std.fmt.bufPrint(&buf1, "{s}/{s}/items/textures/{s}", .{assetFolder, mod, texture});
		replacementTexturePath = try std.fmt.bufPrint(&buf2, "assets/{s}/items/textures/{s}", .{mod, texture});
	}
	return items_zig.register(assetFolder, texturePath, replacementTexturePath, id, json);
}

fn registerBlock(assetFolder: []const u8, id: []const u8, json: JsonElement) !void {
	const block = blocks_zig.register(assetFolder, id, json);
	blocks_zig.meshes.register(assetFolder, id, json);

	if(json.get(bool, "hasItem", true)) {
		const item = try registerItem(assetFolder, id, json.getChild("item"));
		item.block = block;
	}
}

fn registerRecipesFromFile(file: []const u8) void {
	items_zig.registerRecipes(file);
}

pub const BlockPalette = struct {
	palette: main.List([]const u8),
	pub fn init(allocator: NeverFailingAllocator, json: JsonElement) !*BlockPalette {
		const self = allocator.create(BlockPalette);
		self.* = BlockPalette {
			.palette = main.List([]const u8).init(allocator),
		};
		errdefer self.deinit();
		if(json != .JsonObject or json.JsonObject.count() == 0) {
			self.palette.append(allocator.dupe(u8, "cubyz:air"));
		} else {
			const palette = main.stackAllocator.alloc(?[]const u8, json.JsonObject.count());
			defer main.stackAllocator.free(palette);
			for(palette) |*val| {
				val.* = null;
			}
			var iterator = json.JsonObject.iterator();
			while(iterator.next()) |entry| {
				palette[entry.value_ptr.as(usize, std.math.maxInt(usize))] = entry.key_ptr.*;
			}
			std.debug.assert(std.mem.eql(u8, palette[0].?, "cubyz:air"));
			for(palette) |val| {
				std.log.info("palette[{}]: {s}", .{self.palette.items.len, val.?});
				self.palette.append(allocator.dupe(u8, val orelse return error.MissingKeyInPalette));
			}
		}
		return self;
	}

	pub fn deinit(self: *BlockPalette) void {
		for(self.palette.items) |item| {
			self.palette.allocator.free(item);
		}
		const allocator = self.palette.allocator;
		self.palette.deinit();
		allocator.destroy(self);
	}

	pub fn add(self: *BlockPalette, id: []const u8) void {
		self.palette.append(self.palette.allocator.dupe(u8, id));
	}

	pub fn save(self: *BlockPalette, allocator: NeverFailingAllocator) JsonElement {
		const json = JsonElement.initObject(allocator);
		errdefer json.free(allocator);
		for(self.palette.items, 0..) |item, i| {
			json.put(item, i);
		}
		return json;
	}
};

var loadedAssets: bool = false;

pub fn loadWorldAssets(assetFolder: []const u8, palette: *BlockPalette) !void {
	if(loadedAssets) return; // The assets already got loaded by the server.
	loadedAssets = true;
	var blocks = commonBlocks.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer blocks.clearAndFree();
	var items = commonItems.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer items.clearAndFree();
	var biomes = commonBiomes.cloneWithAllocator(main.stackAllocator.allocator) catch unreachable;
	defer biomes.clearAndFree();
	var recipes = main.List([]const u8).init(main.stackAllocator);
	recipes.appendSlice(commonRecipes.items);
	defer recipes.clearAndFree();

	readAssets(arenaAllocator, assetFolder, &blocks, &items, &biomes, &recipes);
	errdefer unloadAssets();

	// blocks:
	var block: u32 = 0;
	for(palette.palette.items) |id| {
		const nullValue = blocks.get(id);
		var json: JsonElement = undefined;
		if(nullValue) |value| {
			json = value;
		} else {
			std.log.err("Missing block: {s}. Replacing it with default block.", .{id});
			json = .{.JsonNull={}};
		}
		try registerBlock(assetFolder, id, json);
		block += 1;
	}
	var iterator = blocks.iterator();
	while(iterator.next()) |entry| {
		if(blocks_zig.hasRegistered(entry.key_ptr.*)) continue;
		try registerBlock(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
		palette.add(entry.key_ptr.*);
		block += 1;
	}

	// items:
	iterator = items.iterator();
	while(iterator.next()) |entry| {
		_ = try registerItem(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
	}

	// block drops:
	blocks_zig.finishBlocks(blocks);

	for(recipes.items) |recipe| {
		registerRecipesFromFile(recipe);
	}

	// Biomes:
	iterator = biomes.iterator();
	while(iterator.next()) |entry| {
		biomes_zig.register(entry.key_ptr.*, entry.value_ptr.*);
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

pub fn unloadAssets() void {
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
