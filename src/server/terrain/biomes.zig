const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const blocks = main.blocks;
const Chunk = main.chunk.Chunk;
const JsonElement = main.JsonElement;
const RandomList = main.utils.RandomList;
const terrain = main.server.terrain;

const StructureModel = struct {
	const VTable = struct {
		loadModel: *const fn(arenaAllocator: Allocator, parameters: JsonElement) Allocator.Error!*anyopaque,
		generate: *const fn(self: *anyopaque, x: i32, y: i32, z: i32, chunk: *Chunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) Allocator.Error!void,
	};

	vtable: VTable,
	data: *anyopaque,
	chance: f32,

	pub fn initModel(parameters: JsonElement) !?StructureModel {
		const id = parameters.get([]const u8, "id", "");
		const vtable = modelRegistry.get(id) orelse {
			std.log.err("Couldn't find structure model with id {s}", .{id});
			return null;
		};
		return StructureModel {
			.vtable = vtable,
			.data = try vtable.loadModel(arena.allocator(), parameters),
			.chance = parameters.get(f32, "chance", 0.5),
		};
	}

	pub fn generate(self: StructureModel, x: i32, y: i32, z: i32, chunk: *Chunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) Allocator.Error!void {
		try self.vtable.generate(self.data, x, y, z, chunk, caveMap, seed);
	}


	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};
	var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(main.globalAllocator);

	pub fn reset() void {
		std.debug.assert(arena.reset(.free_all));
	}

	pub fn registerGenerator(comptime Generator: type) !void {
		var self: VTable = undefined;
		self.loadModel = @ptrCast(@TypeOf(self.loadModel), &Generator.loadModel);
		self.generate = @ptrCast(@TypeOf(self.generate), &Generator.generate);
		try modelRegistry.put(main.globalAllocator, Generator.id, self);
	}
};

/// A climate region with special ground, plants and structures.
pub const Biome = struct {
	pub const Type = enum { // TODO: I should make this more general. There should be a way to define custom biome types.
		/// hot, wet, lowland
		rainforest,
		/// hot, medium, lowland
		shrubland,
		/// hot, dry, lowland
		desert,
		/// temperate, wet, lowland
		swamp,
		/// temperate, medium, lowland
		forest,
		/// temperate, dry, lowland
		grassland,
		/// cold, wet, lowland
		tundra,
		/// cold, medium, lowland
		taiga,
		/// cold, dry, lowland
		glacier,

		/// temperate, medium, highland
		mountain_forest,
		/// temperate, dry, highland
		mountain_grassland,
		/// cold, dry, highland
		peak,

		/// temperate ocean
		ocean,
		/// tropical ocean(TODO: coral reefs and stuff)
		warm_ocean,
		/// arctic ocean(ice sheets)
		arctic_ocean,

		/// underground caves
		cave,

		fn lowerTypes(typ: Type) []const Type {
			return switch(typ) {
				.rainforest, .shrubland, .desert => &[_]Type{.warm_ocean},
				.swamp, .forest, .grassland => &[_]Type{.ocean},
				.tundra, .taiga, .glacier => &[_]Type{.arctic_ocean},
				.mountain_forest => &[_]Type{.forest},
				.mountain_grassland => &[_]Type{.grassland},
				.peak => &[_]Type{.tundra},
				else => &[_]Type{},
			};
		}

		fn higherTypes(typ: Type) []const Type {
			return switch(typ) {
				.swamp, .rainforest, .forest, .taiga => &[_]Type{.mountain_forest},
				.shrubland, .grassland => &[_]Type{.mountain_grassland},
				.mountain_forest, .mountain_grassland, .desert, .tundra, .glacier => &[_]Type{.peak},
				.warm_ocean => &[_]Type{.rainforest, .shrubland, .desert},
				.ocean => &[_]Type{.swamp, .forest, .grassland},
				.arctic_ocean => &[_]Type{.glacier, .tundra},
				else => &[_]Type{},
			};
		}
	};

	typ: Type,
	minHeight: i32,
	maxHeight: i32,
	roughness: f32,
	hills: f32,
	mountains: f32,
	caves: f32,
	crystals: u32,
	stoneBlockType: u16,
	id: []const u8,
	structure: BlockStructure = undefined,
	/// Whether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	supportsRivers: bool, // TODO: Reimplement rivers.
	/// The first members in this array will get prioritized.
	vegetationModels: []StructureModel = &[0]StructureModel{},
	upperReplacements: []const *const Biome = &[0]*Biome{},
	lowerReplacements: []const *const Biome = &[0]*Biome{},
	preferredMusic: []const u8, // TODO: Support multiple possibilities that are chose based on time and danger.
	isValidPlayerSpawn: bool,
	chance: f64,

	pub fn init(self: *Biome, id: []const u8, json: JsonElement) !void {
		self.* = Biome {
			.typ = std.meta.stringToEnum(Type, json.get([]const u8, "type", "")) orelse blk: {
				std.log.warn("Couldn't find biome type {s}. Replacing it with grassland.", .{json.get([]const u8, "type", "")});
				break :blk Type.grassland;
			},
			.id = try main.globalAllocator.dupe(u8, id),
			.stoneBlockType = blocks.getByID(json.get([]const u8, "stoneBlock", "cubyz:stone")),
			.roughness = json.get(f32, "roughness", 0),
			.hills = json.get(f32, "hills", 0),
			.mountains = json.get(f32, "mountains", 0),
			.caves = json.get(f32, "caves", -0.375),
			.crystals = json.get(u32, "crystals", 0),
			.minHeight = json.get(i32, "minHeight", std.math.minInt(i32)),
			.maxHeight = json.get(i32, "maxHeight", std.math.maxInt(i32)),
			.supportsRivers = json.get(bool, "rivers", false),
			.preferredMusic = try main.globalAllocator.dupe(u8, json.get([]const u8, "music", "")),
			.isValidPlayerSpawn = json.get(bool, "validPlayerSpawn", false),
			.chance = json.get(f64, "chance", 1),
		};
		if(self.minHeight > self.maxHeight) {
			std.log.warn("Biome {s} has invalid height range ({}, {})", .{self.id, self.minHeight, self.maxHeight});
		}

		self.structure = try BlockStructure.init(main.globalAllocator, json.getChild("ground_structure"));
		
		const structures = json.getChild("structures");
		var vegetation = std.ArrayListUnmanaged(StructureModel){};
		defer vegetation.deinit(main.threadAllocator);
		for(structures.toSlice()) |elem| {
			if(try StructureModel.initModel(elem)) |model| {
				try vegetation.append(main.threadAllocator, model);
			}
		}
		self.vegetationModels = try main.globalAllocator.dupe(StructureModel, vegetation.items);
	}

	pub fn deinit(self: *Biome) void {
		self.structure.deinit(main.globalAllocator);
		main.globalAllocator.free(self.vegetationModels);
		main.globalAllocator.free(self.lowerReplacements);
		main.globalAllocator.free(self.upperReplacements);
		main.globalAllocator.free(self.preferredMusic);
		main.globalAllocator.free(self.id);
	}
};

/// Stores the vertical ground structure of a biome from top to bottom.
pub const BlockStructure = struct {
	pub const BlockStack = struct {
		blockType: u16 = 0,
		min: u31 = 0,
		max: u31 = 0,

		fn init(self: *BlockStack, string: []const u8) !void {
			var tokenIt = std.mem.tokenize(u8, string, &std.ascii.whitespace);
			const first = tokenIt.next() orelse return error.@"String is empty.";
			var blockId: []const u8 = first;
			if(tokenIt.next()) |second| {
				self.min = try std.fmt.parseInt(u31, first, 0);
				if(tokenIt.next()) |third| {
					const fourth = tokenIt.next() orelse return error.@"Expected 1, 2 or 4 parameters, found 3.";
					if(!std.mem.eql(u8, second, "to")) return error.@"Expected layout '<min> to <max> <block>'. Missing 'to'.";
					self.max = try std.fmt.parseInt(u31, third, 0);
					blockId = fourth;
					if(tokenIt.next() != null) return error.@"Found too many parameters. Expected 1, 2 or 4.";
					if(self.max < self.min) return error.@"The max value must be bigger than the min value.";
				} else {
					self.max = self.min;
					blockId = second;
				}
			} else {
				self.min = 1;
				self.max = 1;
			}
			self.blockType = blocks.getByID(blockId);
		}
	};
	structure: []BlockStack,

	pub fn init(allocator: Allocator, jsonArray: JsonElement) !BlockStructure {
		const blockStackDescriptions = jsonArray.toSlice();
		const self = BlockStructure {
			.structure = try allocator.alloc(BlockStack, blockStackDescriptions.len),
		};
		for(blockStackDescriptions, self.structure) |jsonString, *blockStack| {
			blockStack.init(jsonString.as([]const u8, "That's not a json string.")) catch |err| {
				std.log.warn("Couldn't parse blockStack '{s}': {s} Removing it.", .{jsonString.as([]const u8, "That's not a json string."), @errorName(err)});
				blockStack.* = .{};
			};
		}
		return self;
	}

	pub fn deinit(self: BlockStructure, allocator: Allocator) void {
		allocator.free(self.structure);
	}

	pub fn addSubTerranian(self: BlockStructure, chunk: *Chunk, startingDepth: i32, minDepth: i32, x: i32, z: i32, seed: *u64) i32 {
		var depth = startingDepth;
		for(self.structure) |blockStack| {
			const total = blockStack.min + main.random.nextIntBounded(u32, seed, @as(u32, 1) + blockStack.max - blockStack.min);
			for(0..total) |_| {
				const block = blocks.Block{.typ = blockStack.blockType, .data = undefined};
				// TODO: block = block.mode().getNaturalStandard(block);
				if(chunk.liesInChunk(x, depth, z)) {
					chunk.updateBlockInGeneration(x, depth, z, block);
				}
				depth -%= chunk.pos.voxelSize;
				if(depth -% minDepth <= 0)
					return depth +% chunk.pos.voxelSize;
			}
		}
		return depth +% chunk.pos.voxelSize;
	}
};

var finishedLoading: bool = false;
var biomes: std.ArrayList(Biome) = undefined;
var biomesById: std.StringHashMap(*const Biome) = undefined;
var byTypeBiomes: [@typeInfo(Biome.Type).Enum.fields.len]RandomList(*const Biome) = [_]RandomList(*const Biome){.{}} ** @typeInfo(Biome.Type).Enum.fields.len;

pub fn init() !void {
	biomes = std.ArrayList(Biome).init(main.globalAllocator);
	biomesById = std.StringHashMap(*const Biome).init(main.globalAllocator);
	const list = @import("structures/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		try StructureModel.registerGenerator(@field(list, decl.name));
	}
}

pub fn reset() void {
	StructureModel.reset();
	finishedLoading = false;
	for(biomes.items) |*biome| {
		biome.deinit();
	}
	biomes.clearRetainingCapacity();
	biomesById.clearRetainingCapacity();
	for(&byTypeBiomes) |*list| {
		list.reset();
	}
}

pub fn deinit() void {
	for(biomes.items) |*biome| {
		biome.deinit();
	}
	biomes.deinit();
	biomesById.deinit();
	for(&byTypeBiomes) |*list| {
		list.deinit(main.globalAllocator);
	}
	StructureModel.modelRegistry.clearAndFree(main.globalAllocator);
}

pub fn register(id: []const u8, json: JsonElement) !void {
	std.log.debug("Registered biome: {s}", .{id});
	std.debug.assert(!finishedLoading);
	try (try biomes.addOne()).init(id, json);
}

pub fn finishLoading() !void {
	std.debug.assert(!finishedLoading);
	finishedLoading = true;
	for(biomes.items) |*biome| {
		try biomesById.put(biome.id, biome);
		try byTypeBiomes[@enumToInt(biome.typ)].add(main.globalAllocator, biome);
	}
	// Get a list of replacement biomes for each biome:
	for(biomes.items) |*biome| {
		var replacements = std.ArrayListUnmanaged(*const Biome){};
		// Check lower replacements:
		// Check if there are replacement biomes of the same type:
		for(byTypeBiomes[@enumToInt(biome.typ)].items()) |replacement| {
			if(replacement.maxHeight > biome.minHeight and replacement.minHeight < biome.minHeight) {
				try replacements.append(main.globalAllocator, replacement);
			}
		}
		// If that doesn't work, check for the next lower height region:
		if(replacements.items.len == 0) {
			for(biome.typ.lowerTypes()) |typ| {
				for(byTypeBiomes[@enumToInt(typ)].items()) |replacement| {
					if(replacement.maxHeight > biome.minHeight and replacement.minHeight < biome.minHeight) {
						try replacements.append(main.globalAllocator, replacement);
					}
				}
			}
		}
		biome.lowerReplacements = try replacements.toOwnedSlice(main.globalAllocator);

		// Check upper replacements:
		// Check if there are replacement biomes of the same type:
		for(byTypeBiomes[@enumToInt(biome.typ)].items()) |replacement| {
			if(replacement.minHeight < biome.maxHeight and replacement.maxHeight > biome.maxHeight) {
				try replacements.append(main.globalAllocator, replacement);
			}
		}
		// If that doesn't work, check for the next higher height region:
		if(replacements.items.len == 0) {
			for(biome.typ.higherTypes()) |typ| {
				for(byTypeBiomes[@enumToInt(typ)].items()) |replacement| {
					if(replacement.minHeight < biome.maxHeight and replacement.maxHeight > biome.maxHeight) {
						try replacements.append(main.globalAllocator, replacement);
					}
				}
			}
		}
		biome.upperReplacements = try replacements.toOwnedSlice(main.globalAllocator);
	}
}

pub fn getById(id: []const u8) *const Biome {
	std.debug.assert(finishedLoading);
	return biomesById.get(id) orelse {
		std.log.warn("Couldn't find biome with id {s}. Replacing it with some other biome.", .{id});
		return &biomes.items[0];
	};
}

pub fn getRandomly(typ: Biome.Type, seed: *u64) *const Biome {
	return byTypeBiomes[@enumToInt(typ)].getRandomly(seed);
}

pub fn getBiomesOfType(typ: Biome.Type) []*const Biome {
	return byTypeBiomes[@enumToInt(typ)].items();
}