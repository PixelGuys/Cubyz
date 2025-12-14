const std = @import("std");

const main = @import("main");
const terrain = main.server.terrain;
const Vec3i = main.vec.Vec3i;
const GenerationMode = terrain.biomes.SimpleStructureModel.GenerationMode;
const CaveMapView = terrain.CaveMap.CaveMapView;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const sbb = terrain.structure_building_blocks;
const Blueprint = main.blueprint.Blueprint;
const ZonElement = main.ZonElement;
const Neighbor = main.chunk.Neighbor;
const ServerChunk = main.chunk.ServerChunk;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const id = "cubyz:sbb";
pub const generationMode = .floor;

const SbbGen = @This();

structureRef: *const sbb.StructureBuildingBlock,
placeMode: Blueprint.PasteMode,
rotation: sbb.Rotation,

pub fn getHash(self: SbbGen) u64 {
	return std.hash.Wyhash.hash(@intFromEnum(self.placeMode), self.structureRef.id);
}

pub fn loadModel(parameters: ZonElement) ?*SbbGen {
	const structureId = parameters.get(?[]const u8, "structure", null) orelse {
		std.log.err("Error loading generator 'cubyz:sbb' structure field is mandatory.", .{});
		return null;
	};
	const structureRef = sbb.getByStringId(structureId) orelse {
		std.log.err("Could not find blueprint with id {s}. Structure will not be added.", .{structureId});
		return null;
	};
	const rotationParam = parameters.getChild("rotation");
	const rotation = sbb.Rotation.fromZon(rotationParam) catch |err| blk: {
		switch(err) {
			error.UnknownString => std.log.err("Error loading generator 'cubyz:sbb' structure '{s}': Specified unknown rotation '{s}'", .{structureId, rotationParam.as([]const u8, "")}),
			error.UnknownType => std.log.err("Error loading generator 'cubyz:sbb' structure '{s}': Unsupported type of rotation field '{s}'", .{structureId, @tagName(rotationParam)}),
		}
		break :blk .random;
	};
	const self = main.worldArena.create(SbbGen);
	self.* = .{
		.structureRef = structureRef,
		.placeMode = std.meta.stringToEnum(Blueprint.PasteMode, parameters.get([]const u8, "placeMode", "degradable")) orelse Blueprint.PasteMode.degradable,
		.rotation = rotation,
	};
	return self;
}

pub fn generate(self: *SbbGen, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *ServerChunk, _: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	placeSbb(self, self.structureRef, Vec3i{x, y, z}, Neighbor.dirUp, self.rotation.getInitialRotation(seed), chunk, seed);
}

fn placeSbb(self: *SbbGen, structure: *const sbb.StructureBuildingBlock, placementPosition: Vec3i, placementDirection: Neighbor, rotation: sbb.Rotation, chunk: *ServerChunk, seed: *u64) void {
	const blueprints = &(structure.getBlueprints(seed).* orelse return);

	const origin = blueprints[0].originBlock;
	const blueprintRotation = rotation.apply(alignDirections(origin.direction(), placementDirection) catch |err| {
		std.log.err("Could not align directions for structure '{s}' for directions '{s}'' and '{s}', error: {s}", .{structure.id, @tagName(origin.direction()), @tagName(placementDirection), @errorName(err)});
		return;
	});
	const rotated = &blueprints[@intFromEnum(blueprintRotation)];
	const rotatedOrigin = rotated.originBlock.pos();
	const pastePosition = placementPosition - rotatedOrigin - placementDirection.relPos();

	rotated.blueprint.pasteInGeneration(pastePosition, chunk, self.placeMode);

	for(rotated.childBlocks) |childBlock| {
		const child = structure.getChildStructure(childBlock) orelse continue;
		const childRotation = rotation.getChildRotation(seed, child.rotation, childBlock.direction());
		placeSbb(self, child, pastePosition + childBlock.pos(), childBlock.direction(), childRotation, chunk, seed);
	}
}

fn alignDirections(input: Neighbor, desired: Neighbor) !sbb.Rotation.FixedRotation {
	comptime var alignTable: [6][6]error{NotPossibleToAlign}!sbb.Rotation.FixedRotation = undefined;
	comptime for(Neighbor.iterable) |in| {
		for(Neighbor.iterable) |out| blk: {
			var current = in;
			for(0..4) |i| {
				if(current == out) {
					alignTable[in.toInt()][out.toInt()] = @enumFromInt(i);
					break :blk;
				}
				current = current.rotateZ();
			}
			alignTable[in.toInt()][out.toInt()] = error.NotPossibleToAlign;
		}
	};
	const runtimeTable = alignTable;
	return runtimeTable[input.toInt()][desired.toInt()];
}
