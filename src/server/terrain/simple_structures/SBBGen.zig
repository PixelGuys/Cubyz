const std = @import("std");

const main = @import("root");
const GenerationMode = main.server.terrain.biomes.SimpleStructureModel.GenerationMode;
const CaveMapView = main.server.terrain.CaveMap.CaveMapView;
const CaveBiomeMapView = main.server.terrain.CaveBiomeMap.CaveBiomeMapView;
const sbb = main.structure_building_blocks;
const Blueprint = main.blueprint.Blueprint;
const SubstitutionMap = main.blueprint.SubstitutionMap;
const ZonElement = main.ZonElement;
const Neighbor = main.chunk.Neighbor;
const ServerChunk = main.chunk.ServerChunk;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const parseBlock = main.blocks.parseBlock;
const hashInt = main.utils.hashInt;
const hashCombine = main.utils.hashCombine;
const StructureInfo = main.structure_building_blocks.StructureInfo;

pub var structures: ?std.StringHashMap(ZonElement) = null;

pub const id = "cubyz:sbb";
pub const generationMode = .floor;

const SBBGen = @This();

structure: []const u8,
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
	const self = arenaAllocator.create(SBBGen);
	self.* = .{
		.structure = parameters.get(?[]const u8, "structure", null) orelse unreachable,
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
	if(sbb.getByStringId(self.structure)) |structure| {
		placeSbb(self, structure, x, y, z - 1, Neighbor.dirUp, chunk, seed);
	} else {
		std.log.err("Could not find structure building block with id '{s}'", .{self.structure});
		return;
	}
}

fn placeSbb(self: *SBBGen, structure: *sbb.StructureBuildingBlock, x: i32, y: i32, z: i32, placementDirection: Neighbor, chunk: *ServerChunk, seed: *u64) void {
	const origin = structure.blueprint[0].info.originBlock;
	const rotationCount = alignDirections(origin.direction(), placementDirection) catch |err| {
		std.log.err("Could not align directions {s} and {s} error: {s}", .{@tagName(origin.direction()), @tagName(placementDirection), @errorName(err)});
		return;
	};
	const rotated = structure.blueprint[rotationCount];
	const rotatedOrigin = rotated.info.originBlock;

	const pasteX: i32 = x - rotatedOrigin.x - placementDirection.relX();
	const pasteY: i32 = y - rotatedOrigin.y - placementDirection.relY();
	const pasteZ: i32 = z - rotatedOrigin.z - placementDirection.relZ();

	rotated.blueprint.pasteInGeneration(.{pasteX, pasteY, pasteZ}, chunk, self.placeMode, self.substitutions);

	for(rotated.info.childrenBlocks.items) |childBlock| {
		const childNullable = structure.children.pickChild(childBlock.block, seed);
		if(childNullable) |child| {
			placeSbb(self, child.structure, pasteX + childBlock.x, pasteY + childBlock.y, pasteZ + childBlock.z, childBlock.direction(), chunk, seed);
		}
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
