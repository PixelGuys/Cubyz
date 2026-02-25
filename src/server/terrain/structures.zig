const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ServerChunk = main.chunk.ServerChunk;
const terrain = main.server.terrain;
const Biome = main.server.terrain.biomes;

pub const SimpleStructureModel = struct { // MARK: SimpleStructureModel
	pub const GenerationMode = enum {
		floor,
		ceiling,
		floor_and_ceiling,
		air,
		underground,
		water_surface,
	};
	const VTable = struct {
		loadModel: *const fn (parameters: ZonElement) ?*anyopaque,
		generate: *const fn (self: *anyopaque, generationMode: GenerationMode, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView, seed: *u64, isCeiling: bool) void,
		hashFunction: *const fn (self: *anyopaque) u64,
		generationMode: GenerationMode,
	};

	vtable: VTable,
	data: *anyopaque,
	chance: f32,
	priority: f32,
	generationMode: GenerationMode,

	pub fn initModel(parameters: ZonElement) ?SimpleStructureModel {
		const id = parameters.get([]const u8, "id", "");
		const vtable = modelRegistry.get(id) orelse {
			std.log.err("Couldn't find structure model with id {s}", .{id});
			return null;
		};
		const vtableModel = vtable.loadModel(parameters) orelse {
			std.log.err("Error occurred while loading structure with id '{s}'. Dropping model from biome.", .{id});
			return null;
		};
		return SimpleStructureModel{
			.vtable = vtable,
			.data = vtableModel,
			.chance = parameters.get(f32, "chance", 0.1),
			.priority = parameters.get(f32, "priority", 1),
			.generationMode = std.meta.stringToEnum(GenerationMode, parameters.get([]const u8, "generationMode", "")) orelse vtable.generationMode,
		};
	}

	pub fn generate(self: SimpleStructureModel, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView, seed: *u64, isCeiling: bool) void {
		self.vtable.generate(self.data, self.generationMode, x, y, z, chunk, caveMap, biomeMap, seed, isCeiling);
	}

	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};

	pub fn registerGenerator(comptime Generator: type) void {
		var self: VTable = undefined;
		self.loadModel = main.meta.castFunctionReturnToOptionalAnyopaque(Generator.loadModel);
		self.generate = main.meta.castFunctionSelfToAnyopaque(Generator.generate);
		self.hashFunction = main.meta.castFunctionSelfToAnyopaque(struct {
			fn hash(ptr: *Generator) u64 {
				return Biome.hashGeneric(ptr.*);
			}
		}.hash);
		self.generationMode = Generator.generationMode;
		modelRegistry.put(main.globalArena.allocator, Generator.id, self) catch unreachable;
	}

	fn getHash(self: SimpleStructureModel) u64 {
		return self.vtable.hashFunction(self.data);
	}
};

pub const StructureTable = struct {
	id: []const u8,
	biomeTags: [][]const u8,
	structures: []SimpleStructureModel = &.{},
	paletteId: u32,

	pub fn init(self: *StructureTable, id: []const u8, paletteId: u32, zon: ZonElement) void {
		const biome_tags = zon.getChild("biomeTags");
		var tags_list = main.ListUnmanaged([]const u8){};
		for (biome_tags.toSlice()) |tag| {
			tags_list.append(main.globalAllocator, tag.toString(main.globalAllocator));
		}

		self.* = .{
			.id = main.globalAllocator.dupe(u8, id),
			.paletteId = paletteId,
			.biomeTags = tags_list.items,
		};

		const structures = zon.getChild("structures");
		var structure_list = main.ListUnmanaged(SimpleStructureModel){};
		var total_chance: f32 = 0;
		defer structure_list.deinit(main.stackAllocator);

		for (structures.toSlice()) |elem| {
			if (SimpleStructureModel.initModel(elem)) |model| {
				structure_list.append(main.stackAllocator, model);
				total_chance += model.chance;
			}
		}
		if (total_chance > 1) {
			for (structure_list.items) |*model| {
				model.chance /= total_chance;
			}
		}
		self.structures = main.globalAllocator.dupe(SimpleStructureModel, structure_list.items);
	}
};

var structureTables: main.List(StructureTable) = undefined;
var structureTablesById: std.StringHashMap(StructureTable) = undefined;
pub fn init() void {
	structureTables = .init(main.globalAllocator);
	structureTablesById = .init(main.globalAllocator.allocator);
	for (structureTables.items) |structureTable| {
		structureTablesById.put(structureTable.id, structureTable) catch unreachable;
	}
}

pub fn register(id: []const u8, paletteId: u32, zon: ZonElement) void {
	var structure_table: StructureTable = undefined;
	structure_table.init(id, paletteId, zon);
	structureTables.append(structure_table);
}
pub fn hasRegistered(id: []const u8) bool {
	for (structureTables.items) |entry| {
		if (std.mem.eql(u8, id, entry.id)) {
			return true;
		}
	}
	return false;
}

pub fn getById(id: []const u8) *const StructureTable {
	return structureTablesById.get(id) orelse {
		std.log.err("Couldn't find structure table with id {s}. Replacing it with some other Structure table.", .{id});
		return &structureTables[0];
	};
}
pub fn getSlice() []StructureTable {
	return structureTables.items;
}

pub fn deinit() void {
	SimpleStructureModel.modelRegistry.clearAndFree(main.globalAllocator.allocator);
}
