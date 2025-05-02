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

pub fn getHash(self: SbbGen) u64 {
	return std.hash.Wyhash.hash(@intFromEnum(self.placeMode), self.structureRef.id);
}

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *SbbGen {
	const structureId = parameters.get(?[]const u8, "structure", null) orelse unreachable;
	const structureRef = sbb.getByStringId(structureId) orelse {
		std.log.err("Could not find structure building block with id '{s}'", .{structureId});
		unreachable;
	};
	const self = arenaAllocator.create(SbbGen);
	self.* = .{
		.structureRef = structureRef,
		.placeMode = std.meta.stringToEnum(Blueprint.PasteMode, parameters.get([]const u8, "placeMode", "degradable")) orelse Blueprint.PasteMode.degradable,
	};
	return self;
}

pub fn generate(self: *SbbGen, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *ServerChunk, _: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	placeSbb(self, self.structureRef, Vec3i{x, y, z}, Neighbor.dirUp, chunk, seed);
}

fn placeSbb(self: *SbbGen, structure: *const sbb.StructureBuildingBlock, placementPosition: Vec3i, placementDirection: Neighbor, chunk: *ServerChunk, seed: *u64) void {
	const origin = structure.blueprints[0].originBlock;
	const rotationCount = alignDirections(origin.direction(), placementDirection) catch |err| {
		std.log.err("Could not align directions for structure '{s}' for directions '{s}'' and '{s}', error: {s}", .{structure.id, @tagName(origin.direction()), @tagName(placementDirection), @errorName(err)});
		return;
	};
	const rotated = &structure.blueprints[rotationCount];
	const rotatedOrigin = rotated.originBlock.pos();
	const pastePosition = placementPosition - rotatedOrigin - placementDirection.relPos();

	rotated.blueprint.pasteInGeneration(pastePosition, chunk, self.placeMode);

	for(rotated.childBlocks) |childBlock| {
		const child = structure.pickChild(childBlock, seed);
		placeSbb(self, child, pastePosition + childBlock.pos(), childBlock.direction(), chunk, seed);
	}
}

fn alignDirections(input: Neighbor, desired: Neighbor) !usize {
	const Rotation = enum(u3) {
		@"0" = 0,
		@"90" = 1,
		@"180" = 2,
		@"270" = 3,
		NotPossibleToAlign = 4,
	};
	comptime var alignTable: [6][6]Rotation = undefined;
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
			alignTable[in.toInt()][out.toInt()] = Rotation.NotPossibleToAlign;
		}
	};
	switch(alignTable[input.toInt()][desired.toInt()]) {
		.NotPossibleToAlign => return error.NotPossibleToAlign,
		else => |v| return @intFromEnum(v),
	}
}
