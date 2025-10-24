const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ServerChunk = main.chunk.ServerChunk;
const terrain = main.server.terrain;
const Biome = main.server.terrain.biomes;
const Hash = main.utils.hash_zig;

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
		loadModel: *const fn(arena: NeverFailingAllocator, parameters: ZonElement) *anyopaque,
		generate: *const fn(self: *anyopaque, generationMode: GenerationMode, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView, seed: *u64, isCeiling: bool) void,
		hashFunction: *const fn(self: *anyopaque) u64,
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
		return SimpleStructureModel{
			.vtable = vtable,
			.data = vtable.loadModel(arenaAllocator.allocator(), parameters),
			.chance = parameters.get(f32, "chance", 0.1),
			.priority = parameters.get(f32, "priority", 1),
			.generationMode = std.meta.stringToEnum(GenerationMode, parameters.get([]const u8, "generationMode", "")) orelse vtable.generationMode,
		};
	}

	pub fn generate(self: SimpleStructureModel, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, biomeMap: terrain.CaveBiomeMap.CaveBiomeMapView, seed: *u64, isCeiling: bool) void {
		self.vtable.generate(self.data, self.generationMode, x, y, z, chunk, caveMap, biomeMap, seed, isCeiling);
	}

	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};
	var arenaAllocator: main.heap.NeverFailingArenaAllocator = .init(main.globalAllocator);

	pub fn reset() void {
		std.debug.assert(arenaAllocator.reset(.free_all));
	}

	pub fn registerGenerator(comptime Generator: type) void {
		var self: VTable = undefined;
		self.loadModel = main.utils.castFunctionReturnToAnyopaque(Generator.loadModel);
		self.generate = main.utils.castFunctionSelfToAnyopaque(Generator.generate);
		self.hashFunction = main.utils.castFunctionSelfToAnyopaque(struct {
			fn hash(ptr: *Generator) u64 {
				return Hash.hashGeneric(ptr.*);
			}
		}.hash);
		self.generationMode = Generator.generationMode;
		modelRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	fn getHash(self: SimpleStructureModel) u64 {
		return self.vtable.hashFunction(self.data);
	}
};

pub const StructureTable = struct {
	id: []const u8,
	biomeTags: [][]const u8,
	structures: []SimpleStructureModel = &.{},

	pub fn init(self: *StructureTable, id: []const u8, zon: ZonElement) void {
		self.* = .{
			.id = main.globalAllocator.dupe(u8, id),
			.biomeTags = zon.getChild("biomeTags"),
		};
		const structures = zon.getChild("structures");
		var structure_list = main.ListUnmanaged(SimpleStructureModel){};
		var total_chance: f32 = 0;
		defer structure_list.deinit(main.stackAllocator);

		for(structures.toSlice()) |elem| {
			if(SimpleStructureModel.initModel(elem)) |model| {
				structure_list.append(main.stackAllocator, model);
				total_chance += model.chance;
			}
		}
		if(total_chance > 1) {
			for(structure_list.items) |*model| {
				model.chance /= total_chance;
			}
		}
		self.structures = main.globalAllocator.dupe(SimpleStructureModel, structure_list.items);
	}
};

var structureTables: main.List(StructureTable) = undefined;
var structureTablesById: std.StringHashMap(*StructureTable) = undefined;
pub fn init() void {
	structureTables = .init(main.globalAllocator);
	structureTablesById = .init(main.globalAllocator.allocator);
	for(structureTables.items) |structureTable| {
		structureTablesById.put(structureTable.id, structureTable);
	}
}

pub fn getById(id: []const u8) *const StructureTable {
	return structureTablesById.get(id) orelse {
		std.log.err("Couldn't find structure table with id {s}. Replacing it with some other Structure table.", .{id});
		return &structureTables[0];
	};
}

pub fn deinit() void {
	SimpleStructureModel.modelRegistry.clearAndFree(main.globalAllocator.allocator);
}
