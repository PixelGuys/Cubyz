const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const CaveMapView = terrain.CaveMap.CaveMapView;
const GenerationMode = terrain.structures.SimpleStructureModel.GenerationMode;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const SimpleTreeModel = terrain.structures.simple_structures.SimpleTreeModel;
const Neighbor = main.chunk.Neighbor;

pub const id = "cubyz:fallen_tree";

pub const generationMode = .floor;

const FallenTree = @This();

woodBlock: Block,
woodRotationModeType: SimpleTreeModel.RotationModeType = .unknown,
height0: u32,
deltaHeight: u31,

pub fn loadModel(parameters: ZonElement) ?*FallenTree {
	const self = main.worldArena.create(FallenTree);
	self.* = .{
		.woodBlock = main.blocks.parseBlock(parameters.get(?[]const u8, "log", null) orelse {
			std.log.err("Missing required 'log' field for cubyz:simple_tree rotation", .{});
			return null;
		}),
		.height0 = parameters.get(u32, "height", 6),
		.deltaHeight = parameters.get(u31, "height_variation", 3),
	};
	if (self.woodBlock.mode() == main.rotation.getByID("cubyz:branch")) self.woodRotationModeType = .branch;
	if (self.woodBlock.mode() == main.rotation.getByID("cubyz:log")) self.woodRotationModeType = .log;
	if (self.woodBlock.mode() == main.rotation.getByID("cubyz:direction")) self.woodRotationModeType = .direction;
	return self;
}

pub fn generateStump(self: *FallenTree, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk) void {
	if (chunk.liesInChunk(x, y, z)) {
		var block = SimpleTreeModel.initalOrientation(self.woodBlock, .dirUp, self.woodRotationModeType);
		block = SimpleTreeModel.addNeighbor(block, .dirUp, self.woodRotationModeType);
		chunk.updateBlockIfDegradable(x, y, z, block);
	}
}

pub fn generateFallen(self: *FallenTree, x: i32, y: i32, z: i32, length: u32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, seed: *u64) void {
	var d: ?Neighbor = null;

	for (0..4) |_| {
		const dir: Neighbor = @enumFromInt(main.random.nextIntBounded(u32, seed, 4) + 2);

		const dx: i32 = dir.relX();
		const dy: i32 = dir.relY();

		var works = true;
		for (0..length) |j| {
			const v: i32 = @intCast(j);
			if (caveMap.isSolid(x + dx*(v + 2), y + dy*(v + 2), z) or !caveMap.isSolid(x + dx*(v + 2), y + dy*(v + 2), z -% 1)) {
				works = false;
				break;
			}
		}

		if (works) {
			d = dir;
			break;
		}
	}

	if (d == null)
		return;

	const dx: i32 = d.?.relX();
	const dy: i32 = d.?.relY();

	for (0..length) |val| {
		const v: i32 = @intCast(val);
		if (chunk.liesInChunk(x + dx*(v + 2), y + dy*(v + 2), z)) {
			var block = SimpleTreeModel.initalOrientation(self.woodBlock, d.?, self.woodRotationModeType);
			block = SimpleTreeModel.addNeighbor(block, d.?, self.woodRotationModeType);
			chunk.updateBlockIfDegradable(x + dx*(v + 2), y + dy*(v + 2), z, block);
		}
	}
}

pub fn generate(self: *FallenTree, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	const height = self.height0 + random.nextIntBounded(u31, seed, self.deltaHeight);

	generateStump(self, x, y, z, chunk);

	generateFallen(self, x, y, z, height - 2, chunk, caveMap, seed);
}
