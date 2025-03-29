const std = @import("std");

const main = @import("main");
const terrain = main.server.terrain;
const GenerationMode = terrain.biomes.SimpleStructureModel.GenerationMode;
const CaveMapView = terrain.CaveMap.CaveMapView;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const sbb = terrain.structure_building_blocks;
const Blueprint = main.blueprint.Blueprint;
const ZonElement = main.ZonElement;
const Neighbor = main.chunk.Neighbor;
const ServerChunk = main.chunk.ServerChunk;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const parseBlock = main.blocks.parseBlock;
const hashInt = main.utils.hashInt;
const hashCombine = main.utils.hashCombine;

pub const id = "cubyz:sbb";
pub const generationMode = .floor;

const SubstitutionMap = std.AutoHashMapUnmanaged(u16, u16);

const SBBGen = @This();

structure: []const u8,
structureRef: *const sbb.StructureBuildingBlock,
placeMode: Blueprint.PasteMode,
substitutions: ?SubstitutionMap = null,

pub fn getHash(self: SBBGen) u64 {
	var result = std.hash.Wyhash.hash(@intFromEnum(self.placeMode), self.structure);
	if(self.substitutions) |substitutions| {
		var iterator = substitutions.iterator();
		while(iterator.next()) |entry| {
			result = hashCombine(result, hashCombine(hashInt(entry.key_ptr.*), hashInt(entry.value_ptr.*)));
		}
	}
	return result;
}

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *SBBGen {
	const structureId = parameters.get(?[]const u8, "structure", null) orelse unreachable;
	const structureRef = sbb.getByStringId(structureId) orelse  {
		std.log.err("Could not find structure building block with id '{s}'", .{structureId});
		unreachable;
	};
	const self = arenaAllocator.create(SBBGen);
	self.* = .{
		.structure = structureId,
		.structureRef = structureRef,
		.placeMode = std.meta.stringToEnum(Blueprint.PasteMode, parameters.get([]const u8, "placeMode", "replaceAir")) orelse Blueprint.PasteMode.replaceAir,
		.substitutions = loadSubstitutions(arenaAllocator, parameters.getChild("substitutions")),
	};
	return self;
}

fn loadSubstitutions(allocator: NeverFailingAllocator, zon: ZonElement) ?SubstitutionMap {
	if(zon != .array) {
		if(zon != .null) std.log.err("Expected array of substitutions, got {s}", .{@tagName(zon)});
		return null;
	}
	if(zon.array.items.len == 0) return null;

	var substitutions: SubstitutionMap = .{};

	for(zon.array.items, 0..) |item, i| {
		const old = item.get(?[]const u8, "old", null);
		if(old == null) {
			std.log.err("Substitution {d} does not have an 'old' field, it will be ignored.", .{i});
			continue;
		}
		const new = item.get(?[]const u8, "new", null);
		if(new == null) {
			std.log.err("Substitution {d} does not have a 'new' field, it will be ignored.", .{i});
			continue;
		}
		const key = parseBlock(old.?).typ;
		const value = parseBlock(new.?).typ;

		const entry = substitutions.getOrPut(allocator.allocator, key) catch unreachable;
		if(entry.found_existing) {
			std.log.err("Duplicated substitution for '{s}'.", .{old.?});
			continue;
		}
		entry.value_ptr.* = value;
	}
	return substitutions;
}

pub fn generate(self: *SBBGen, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *ServerChunk, _: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	placeSbb(self, self.structureRef, x, y, z - 1, Neighbor.dirUp, chunk, seed);
}

fn placeSbb(self: *SBBGen, structure: *const sbb.StructureBuildingBlock, x: i32, y: i32, z: i32, placementDirection: Neighbor, chunk: *ServerChunk, seed: *u64) void {
	const origin = structure.blueprints[0].originBlock;
	const rotationCount = alignDirections(origin.direction(), placementDirection) catch |err| {
		std.log.err("Could not align directions {s} and {s} error: {s}", .{@tagName(origin.direction()), @tagName(placementDirection), @errorName(err)});
		return;
	};
	const rotated = structure.blueprints[rotationCount];
	const rotatedOrigin = rotated.originBlock;

	const pasteX: i32 = x - rotatedOrigin.x - placementDirection.relX();
	const pasteY: i32 = y - rotatedOrigin.y - placementDirection.relY();
	const pasteZ: i32 = z - rotatedOrigin.z - placementDirection.relZ();

	rotated.blueprint.pasteInGeneration(.{pasteX, pasteY, pasteZ}, chunk, self.placeMode, self.substitutions);

	for(rotated.childBlocks) |childBlock| {
		const child = structure.pickChild(childBlock, seed);
		placeSbb(self, child, pasteX + childBlock.x, pasteY + childBlock.y, pasteZ + childBlock.z, childBlock.direction(), chunk, seed);
	}
}

fn alignDirections(input: Neighbor, desired: Neighbor) !usize {
	var current = input;
	for(0..4) |i| {
		if(current == desired) return i;
		current = current.rotateZ();
	}
	return error.NotPossibleToAlign;
}
