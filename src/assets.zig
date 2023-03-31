const std = @import("std");
const Allocator = std.mem.Allocator;

const blocks_zig = @import("blocks.zig");
const items_zig = @import("items.zig");
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");

var arena: std.heap.ArenaAllocator = undefined;
var arenaAllocator: Allocator = undefined;
var commonBlocks: std.StringHashMap(JsonElement) = undefined;
var commonBiomes: std.StringHashMap(JsonElement) = undefined;
var commonItems: std.StringHashMap(JsonElement) = undefined;
var commonRecipes: std.ArrayList([]const u8) = undefined;

/// Reads json files recursively from all subfolders.
pub fn readAllJsonFilesInAddons(externalAllocator: Allocator, addons: std.ArrayList(std.fs.Dir), addonNames: std.ArrayList([]const u8), subPath: []const u8, output: *std.StringHashMap(JsonElement)) !void {
	for(addons.items, addonNames.items) |addon, addonName| {
		var dir: std.fs.IterableDir = addon.openIterableDir(subPath, .{}) catch |err| {
			if(err == error.FileNotFound) continue;
			return err;
		};
		defer dir.close();

		var walker = try dir.walk(main.threadAllocator);
		defer walker.deinit();

		while(try walker.next()) |entry| {
			if(entry.kind == .File and std.ascii.endsWithIgnoreCase(entry.basename, ".json")) {
				const folderName = addonName;
				var id: []u8 = try externalAllocator.alloc(u8, folderName.len + 1 + entry.path.len - 5);
				std.mem.copy(u8, id[0..], folderName);
				id[folderName.len] = ':';
				std.mem.copy(u8, id[folderName.len+1..], entry.path[0..entry.path.len-5]);

				var file = try dir.dir.openFile(entry.path, .{});
				defer file.close();
				const string = try file.readToEndAlloc(main.threadAllocator, std.math.maxInt(usize));
				defer main.threadAllocator.free(string);
				try output.put(id, JsonElement.parseFromString(externalAllocator, string));
			}
		}
	}
}
/// Reads text files recursively from all subfolders.
pub fn readAllFilesInAddons(externalAllocator: Allocator, addons: std.ArrayList(std.fs.Dir), subPath: []const u8, output: *std.ArrayList([]const u8)) !void {
	for(addons.items) |addon| {
		var dir: std.fs.IterableDir = addon.openIterableDir(subPath, .{}) catch |err| {
			if(err == error.FileNotFound) continue;
			return err;
		};
		defer dir.close();

		var walker = try dir.walk(main.threadAllocator);
		defer walker.deinit();

		while(try walker.next()) |entry| {
			if(entry.kind == .File) {
				var file = try dir.dir.openFile(entry.path, .{});
				defer file.close();
				const string = try file.readToEndAlloc(externalAllocator, std.math.maxInt(usize));
				try output.append(string);
			}
		}
	}
}

pub fn readAssets(externalAllocator: Allocator, assetPath: []const u8, blocks: *std.StringHashMap(JsonElement), items: *std.StringHashMap(JsonElement), biomes: *std.StringHashMap(JsonElement), recipes: *std.ArrayList([]const u8)) !void {
	var addons = std.ArrayList(std.fs.Dir).init(main.threadAllocator);
	defer addons.deinit();
	var addonNames = std.ArrayList([]const u8).init(main.threadAllocator);
	defer addonNames.deinit();
	
	{ // Find all the sub-directories to the assets folder.
		var dir = try std.fs.cwd().openIterableDir(assetPath, .{});
		defer dir.close();
		var iterator = dir.iterate();
		while(try iterator.next()) |addon| {
			if(addon.kind == .Directory) {
				try addons.append(try dir.dir.openDir(addon.name, .{}));
				try addonNames.append(try main.threadAllocator.dupe(u8, addon.name));
			}
		}
	}
	defer for(addons.items, addonNames.items) |*dir, addonName| {
		dir.close();
		main.threadAllocator.free(addonName);
	};

	try readAllJsonFilesInAddons(externalAllocator, addons, addonNames, "blocks", blocks);
	try readAllJsonFilesInAddons(externalAllocator, addons, addonNames, "items", items);
	try readAllJsonFilesInAddons(externalAllocator, addons, addonNames, "biomes", biomes);
	try readAllFilesInAddons(externalAllocator, addons, "recipes", recipes);
}

pub fn init() !void {
	arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	arenaAllocator = arena.allocator();
	commonBlocks = std.StringHashMap(JsonElement).init(arenaAllocator);
	commonItems = std.StringHashMap(JsonElement).init(arenaAllocator);
	commonBiomes = std.StringHashMap(JsonElement).init(arenaAllocator);
	commonRecipes = std.ArrayList([]const u8).init(arenaAllocator);

	try readAssets(arenaAllocator, "assets/", &commonBlocks, &commonItems, &commonBiomes, &commonRecipes);
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
	return try items_zig.register(assetFolder, texturePath, replacementTexturePath, id, json);
}

fn registerBlock(assetFolder: []const u8, id: []const u8, json: JsonElement) !void {
	const block = try blocks_zig.register(assetFolder, id, json); // TODO: Modded block registries
	try blocks_zig.meshes.register(assetFolder, id, json);

	if(json.get(bool, "hasItem", true)) {
		const item = try registerItem(assetFolder, id, json.getChild("item"));
		item.block = block;
	}
//		TODO:
//		// Ores:
//		JsonObject oreProperties = json.getObject("ore");
//		if (oreProperties != null) {
//			// Extract the ids:
//			String[] oreIDs = oreProperties.getArrayNoNull("sources").getStrings();
//			float veins = oreProperties.getFloat("veins", 0);
//			float size = oreProperties.getFloat("size", 0);
//			int height = oreProperties.getInt("height", 0);
//			float density = oreProperties.getFloat("density", 0.5f);
//			Ore ore = new Ore(block, new int[oreIDs.length], height, veins, size, density);
//			ores.add(ore);
//			oreRegistry.register(ore);
//			oreContainers.add(oreIDs);
//		}
}

fn registerRecipesFromFile(file: []const u8) !void {
	try items_zig.registerRecipes(file);
}

pub const BlockPalette = struct {
	palette: std.ArrayList([]const u8),
	pub fn init(allocator: Allocator, json: JsonElement) !*BlockPalette {
		var self = try allocator.create(BlockPalette);
		self.* = BlockPalette {
			.palette = std.ArrayList([]const u8).init(allocator),
		};
		errdefer self.deinit();
		if(json != .JsonObject or json.JsonObject.count() == 0) {
			try self.palette.append(try allocator.dupe(u8, "cubyz:air"));
		} else {
			var palette = try main.threadAllocator.alloc(?[]const u8, json.JsonObject.count());
			defer main.threadAllocator.free(palette);
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
				try self.palette.append(try allocator.dupe(u8, val orelse return error.MissingKeyInPalette));
			}
		}
		return self;
	}

	pub fn deinit(self: *BlockPalette) void {
		for(self.palette.items) |item| {
			self.palette.allocator.free(item);
		}
		var allocator = self.palette.allocator;
		self.palette.deinit();
		allocator.destroy(self);
	}

	pub fn add(self: *BlockPalette, id: []const u8) !void {
		try self.palette.append(try self.palette.allocator.dupe(u8, id));
	}

	pub fn save(self: *BlockPalette, allocator: Allocator) !JsonElement {
		var json = JsonElement{
			.JsonObject = std.StringHashMap(JsonElement).init(allocator),
		};
		errdefer json.free(allocator);
		for(self.palette.items, 0..) |item, i| {
			json.JsonObject.put(try allocator.dupe(u8, item), JsonElement{.JsonInt = @intCast(i64, i)});
		}
		return json;
	}
};

pub fn loadWorldAssets(assetFolder: []const u8, palette: *BlockPalette) !void {
	var blocks = try commonBlocks.cloneWithAllocator(main.threadAllocator);
	defer blocks.clearAndFree();
	var items = try commonItems.cloneWithAllocator(main.threadAllocator);
	defer items.clearAndFree();
	var biomes = try commonBiomes.cloneWithAllocator(main.threadAllocator);
	defer biomes.clearAndFree();
	var recipes = std.ArrayList([]const u8).init(main.threadAllocator);
	try recipes.appendSlice(commonRecipes.items);
	defer recipes.clearAndFree();

	try readAssets(arenaAllocator, assetFolder, &blocks, &items, &biomes, &recipes);

	// blocks:
	var block: u32 = 0;
	for(palette.palette.items) |id| {
		var nullValue = blocks.get(id);
		var json: JsonElement = undefined;
		if(nullValue) |value| {
			json = value;
		} else {
			std.log.err("Missing block: {s}. Replacing it with default block.", .{id});
			var map: *std.StringHashMap(JsonElement) = try main.threadAllocator.create(std.StringHashMap(JsonElement));
			map.* = std.StringHashMap(JsonElement).init(main.threadAllocator);
			json = JsonElement{.JsonObject=map};
		}
		defer if(nullValue == null) json.free(main.threadAllocator);
		try registerBlock(assetFolder, id, json);
		block += 1;
	}
	var iterator = blocks.iterator();
	while(iterator.next()) |entry| {
		if(blocks_zig.hasRegistered(entry.key_ptr.*)) continue;
		try registerBlock(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
		try palette.add(entry.key_ptr.*);
		block += 1;
	}

	// items:
	iterator = items.iterator();
	while(iterator.next()) |entry| {
		_ = try registerItem(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
	}

	// block drops:
	try blocks_zig.registerBlockDrops(blocks);

	for(recipes.items) |recipe| {
		try registerRecipesFromFile(recipe);
	}

//	public void registerBlocks(Registry<DataOrientedRegistry> registries, NoIDRegistry<Ore> oreRegistry, BlockPalette palette) {
//		HashMap<Resource, JsonObject> perWorldBlocks = new HashMap<>(commonBlocks);
//		readAllJsonObjects("blocks", (json, id) -> {
//			perWorldBlocks.put(id, json);
//		});
//		int block = 0;
//		for(Map.Entry<Resource, JsonObject> entry : perWorldBlocks.entrySet()) {
//			registerBlock(block, entry.getKey(), entry.getValue(), registries, oreRegistry);
//			block++;
//		}
//	}
}

pub fn deinit() void {
	arena.deinit();
}


//TODO:
//	public static final ArrayList<File> addons = new ArrayList<>();
//	private static final ArrayList<Item> items = new ArrayList<>();
//
//	private static final ArrayList<Ore> ores = new ArrayList<>();
//	private static final ArrayList<String[]> oreContainers = new ArrayList<>();
//
//	private static String assetPath;
//	
//	@Override
//	public void init() {
//		init(CubyzRegistries.ITEM_REGISTRY);
//	}
//	public void init(Registry<Item> itemRegistry) {
//		if(Constants.getGameSide() == Side.CLIENT) {
//			ResourcePack pack = new ResourcePack();
//			pack.name = "Add-Ons Resource Pack"; // used for path like: testaddon/models/thing.json
//			pack.path = new File("assets");
//			ResourceManager.packs.add(pack);
//			for (File addon : AddonsMod.addons) {
//				pack = new ResourcePack();
//				pack.name = "Add-On: " + Utilities.capitalize(addon.getName()); // used for languages like: lang/en_US.lang
//				pack.path = addon;
//				ResourceManager.packs.add(pack);
//			}
//		}
//		registerMissingStuff(itemRegistry);
//		readRecipes(commonRecipes);
//	}
//
//	public void registerItems(Registry<Item> registry, String texturePathPrefix) {
//		readAllJsonObjects("items", (json, id) -> {
//			Item item;
//			if (json.map.containsKey("food")) {
//				item = new Consumable(id, json);
//			} else {
//				item = new Item(id, json);
//			}
//			item.setTexture(texturePathPrefix + id.getMod() + "/items/textures/" + json.getString("texture", "default.png"));
//			registry.register(item);
//		});
//		// Register the block items:
//		registry.registerAll(items);
//	}
//	
//	@Override
//	public void registerItems(Registry<Item> registry) {
//		registerItems(registry, "assets/");
//	}
//
//	public void readBlocks() {
//		readAllJsonObjects("blocks", (json, id) -> {
//			commonBlocks.put(id, json);
//		});
//	}
//
//	private void registerBlock(int block, Resource id, JsonObject json, Registry<DataOrientedRegistry>  registries, NoIDRegistry<Ore> oreRegistry) {
//		for(DataOrientedRegistry reg : registries.registered(new DataOrientedRegistry[0])) {
//			reg.register(assetPath, id, json);
//		}
//
//		// Ores:
//		JsonObject oreProperties = json.getObject("ore");
//		if (oreProperties != null) {
//			// Extract the ids:
//			String[] oreIDs = oreProperties.getArrayNoNull("sources").getStrings();
//			float veins = oreProperties.getFloat("veins", 0);
//			float size = oreProperties.getFloat("size", 0);
//			int height = oreProperties.getInt("height", 0);
//			float density = oreProperties.getFloat("density", 0.5f);
//			Ore ore = new Ore(block, new int[oreIDs.length], height, veins, size, density);
//			ores.add(ore);
//			oreRegistry.register(ore);
//			oreContainers.add(oreIDs);
//		}
//
//		// Block drops:
//		String[] blockDrops = json.getArrayNoNull("drops").getStrings();
//		ItemBlock self = null;
//		if(json.getBool("hasItem", true)) {
//			self = new ItemBlock(block, json.getObjectOrNew("item"));
//			items.add(self); // Add each block as an item, so it gets displayed in the creative inventory.
//		}
//		for (String blockDrop : blockDrops) {
//			blockDrop = blockDrop.trim();
//			String[] data = blockDrop.split("\\s+");
//			float amount = 1;
//			String name = data[0];
//			if (data.length == 2) {
//				amount = Float.parseFloat(data[0]);
//				name = data[1];
//			}
//			if (name.equals("auto")) {
//				if(self == null) {
//					Logger.error("Block "+id+" tried to drop itself(\"auto\"), but hasItem is false.");
//				} else {
//					Blocks.addBlockDrop(block, new BlockDrop(self, amount));
//				}
//			} else if (!name.equals("none")) {
//				missingDropsBlock.add(block);
//				missingDropsAmount.add(amount);
//				missingDropsItem.add(name);
//			}
//		}
//
//		// block entities:
//		if (json.has("blockEntity")) {
//			try {
//				Blocks.setBlockEntity(block, Class.forName(json.getString("blockEntity", "")).asSubclass(BlockEntity.class));
//			} catch (ClassNotFoundException e) {
//				Logger.error(e);
//			}
//		}
//	}
//	
//	public void registerBlocks(Registry<DataOrientedRegistry> registries, NoIDRegistry<Ore> oreRegistry, BlockPalette palette) {
//		HashMap<Resource, JsonObject> perWorldBlocks = new HashMap<>(commonBlocks);
//		readAllJsonObjects("blocks", (json, id) -> {
//			perWorldBlocks.put(id, json);
//		});
//		int block = 0;
//		for(; block < palette.size(); block++) {
//			Resource id = palette.getResource(block);
//			JsonObject json = perWorldBlocks.remove(id);
//			if(json == null) {
//				Logger.error("Missing block: " + id + ". Replacing it with default block.");
//				json = new JsonObject();
//			}
//			registerBlock(block, id, json, registries, oreRegistry);
//		}
//		for(Map.Entry<Resource, JsonObject> entry : perWorldBlocks.entrySet()) {
//			palette.addResource(entry.getKey());
//			registerBlock(block, entry.getKey(), entry.getValue(), registries, oreRegistry);
//			block++;
//		}
//	}
//
//
//	public void registerBiomes(BiomeRegistry reg) {
//		commonBiomes.forEach((id, json) -> {
//			Biome biome = new Biome(id, json);
//			reg.register(biome);
//		});
//		readAllJsonObjects("biomes", (json, id) -> {
//			Biome biome = new Biome(id, json);
//			reg.register(biome);
//		});
//	}
//	
//	/**
//	 * Takes care of all missing references.
//	 */
//	public void registerMissingStuff(Registry<Item> itemRegistry) {
//		for(int i = 0; i < missingDropsBlock.size; i++) {
//			Blocks.addBlockDrop(missingDropsBlock.array[i], new BlockDrop(itemRegistry.getByID(missingDropsItem.get(i)), missingDropsAmount.get(i)));
//		}
//		for(int i = 0; i < ores.size(); i++) {
//			for(int j = 0; j < oreContainers.get(i).length; j++) {
//				ores.get(i).sources[j] = Blocks.getByID(oreContainers.get(i)[j]);
//				if (ores.get(i).sources[j] == 0) {
//					Logger.error("Couldn't find source block "+oreContainers.get(i)[j]+" for ore "+Blocks.id(ores.get(i).block));
//				}
//			}
//		}
//		ores.clear();
//		oreContainers.clear();
//		missingDropsBlock.clear();
//		missingDropsItem.clear();
//		missingDropsAmount.clear();
//	}
//}