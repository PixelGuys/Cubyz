const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const CaveMapView = terrain.CaveMap.CaveMapView;
const GenerationMode = terrain.biomes.SimpleStructureModel.GenerationMode;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const id = "cubyz:flower_patch";

pub const generationMode = .floor;

const FlowerPatch = @This();

block: main.blocks.Block,
width: f32,
variation: f32,
density: f32,

pub fn loadModel(parameters: ZonElement) *FlowerPatch {
	const self = main.worldArena.create(FlowerPatch);
	self.* = .{
		.block = main.blocks.parseBlock(parameters.get([]const u8, "block", "")),
		.width = parameters.get(f32, "width", 5),
		.variation = parameters.get(f32, "variation", 1),
		.density = parameters.get(f32, "density", 0.5),
	};
	return self;
}

pub fn generate(self: *FlowerPatch, mode: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMapView, caveBiomeMap: CaveBiomeMapView, seed: *u64, _: bool) void {
	const width = self.width + (random.nextFloat(seed) - 0.5)*self.variation;
	const orientation = 2*std.math.pi*random.nextFloat(seed);
	const ellipseParam = 1 + random.nextFloat(seed);

	// Orientation of the major and minor half axis of the ellipse.
	// For now simply use a minor axis 1/ellipseParam as big as the major.
	const xMain = @sin(orientation)/width;
	const yMain = @cos(orientation)/width;
	const xSecn = ellipseParam*@cos(orientation)/width;
	const ySecn = -ellipseParam*@sin(orientation)/width;

	const xMin = @max(0, x - @as(i32, @intFromFloat(@ceil(width))));
	const xMax = @min(chunk.super.width, x + @as(i32, @intFromFloat(@ceil(width))));
	const yMin = @max(0, y - @as(i32, @intFromFloat(@ceil(width))));
	const yMax = @min(chunk.super.width, y + @as(i32, @intFromFloat(@ceil(width))));

	var baseHeight = z;
	if(mode != .water_surface) {
		if(caveMap.isSolid(x, y, baseHeight)) {
			baseHeight = caveMap.findTerrainChangeAbove(x, y, baseHeight) - 1;
		} else {
			baseHeight = caveMap.findTerrainChangeBelow(x, y, baseHeight);
		}
	}

	var px = chunk.startIndex(xMin);
	while(px < xMax) : (px += 1) {
		var py = chunk.startIndex(yMin);
		while(py < yMax) : (py += 1) {
			const mainDist = xMain*@as(f32, @floatFromInt(x - px)) + yMain*@as(f32, @floatFromInt(y - py));
			const secnDist = xSecn*@as(f32, @floatFromInt(x - px)) + ySecn*@as(f32, @floatFromInt(y - py));
			const distSqr = mainDist*mainDist + secnDist*secnDist;
			if(distSqr <= 1) {
				if((1 - distSqr)*self.density < random.nextFloat(seed)) continue;
				var startHeight = z;

				if(mode == .water_surface) {
					if(caveBiomeMap.getSurfaceHeight(chunk.super.pos.wx + px, chunk.super.pos.wy + py) >= 0) continue;
					startHeight = z -% 1;
				} else {
					if(caveMap.isSolid(px, py, startHeight)) {
						startHeight = caveMap.findTerrainChangeAbove(px, py, startHeight) -% 1;
					} else {
						startHeight = caveMap.findTerrainChangeBelow(px, py, startHeight);
					}
				}

				startHeight = chunk.startIndex(startHeight + chunk.super.pos.voxelSize);
				if(@abs(startHeight -% baseHeight) > 5) continue;
				if(chunk.liesInChunk(px, py, startHeight)) {
					chunk.updateBlockInGeneration(px, py, startHeight, self.block);
				}
			}
		}
	}
}
