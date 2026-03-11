const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ServerChunk = main.chunk.ServerChunk;
const terrain = main.server.terrain;
const Biome = main.server.terrain.biomes;
const Tag = main.Tag;

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
	tags: []const Tag,
	structures: []const SimpleStructureModel = &.{},
	chance: ?f32,
	pub fn init(id: []const u8, zon: ZonElement) StructureTable {
		var structureTable: StructureTable = .{
			.id = main.worldArena.dupe(u8, id),
			.tags = Tag.loadTagsFromZon(main.worldArena, zon.getChild("tags")),
			.chance = zon.get(f32, "chance", null),
		};

		var structureList = main.ListUnmanaged(SimpleStructureModel){};
		defer structureList.deinit(main.stackAllocator);

		const structures = zon.getChild("structures");
		var totalChance: f32 = 0;

		for (structures.toSlice()) |elem| {
			if (SimpleStructureModel.initModel(elem)) |model| {
				structureList.append(main.stackAllocator, model);
				totalChance += model.chance;
			}
		}
		if (structureTable.chance) |chance| {
			for (structureTable.structures) |*structure| {
				structure.chance /= chance;
			}
		}
		structureTable.structures = main.worldArena.dupe(SimpleStructureModel, structureList.items);
		return structureTable;
	}
};

var finishedLoading: bool = false;
var structureTables: main.ListUnmanaged(StructureTable) = .{};
var structureTablesById: std.StringHashMapUnmanaged(*StructureTable) = .{};

pub fn register(id: []const u8, zon: ZonElement) void {
	const structureTable = StructureTable.init(id, zon);
	structureTables.append(main.worldArena, structureTable);
	std.log.debug("Registered structure table: '{s}'", .{id});
}

pub fn hasRegistered(id: []const u8) bool {
	if (structureTables.items.len == 0) return false;
	for (structureTables.items) |entry| {
		if (std.mem.eql(u8, id, entry.id)) {
			return true;
		}
	}
	return false;
}

fn compareStructureTables(_: void, lhs: StructureTable, rhs: StructureTable) bool {
	return std.ascii.orderIgnoreCase(lhs.id, rhs.id) == .gt;
}

pub fn finishLoading() void {
	std.debug.assert(!finishedLoading);
	finishedLoading = true;

	std.mem.sort(StructureTable, structureTables.items, {}, compareStructureTables);
	structureTablesById.ensureTotalCapacity(main.worldArena.allocator, @intCast(structureTables.items.len)) catch unreachable;
	for (structureTables.items) |*structureTable| {
		structureTablesById.putAssumeCapacity(structureTable.id, structureTable);
	}
}

pub fn getById(id: []const u8) *StructureTable {
	std.debug.assert(finishedLoading);
	return structureTablesById.get(id) orelse {
		std.log.err("Could not find structure table by id {s}. Replacing it with some other structure table.", .{id});
		return &structureTables.items[0];
	};
}

pub fn getSlice() []StructureTable {
	return structureTables.items;
}

pub fn reset() void {
	finishedLoading = false;
	structureTables = .{};
	structureTablesById = .{};
}
