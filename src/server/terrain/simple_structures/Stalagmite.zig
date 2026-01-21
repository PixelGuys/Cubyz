const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const CaveMapView = terrain.CaveMap.CaveMapView;
const GenerationMode = terrain.biomes.SimpleStructureModel.GenerationMode;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const id = "cubyz:stalagmite";

pub const generationMode = .floor_and_ceiling;

const Stalagmite = @This();

block: main.blocks.Block,
size: f32,
sizeVariation: f32,
slope: f32,
pointiness: f32,

pub fn loadModel(parameters: ZonElement) ?*Stalagmite {
	const self = main.worldArena.create(Stalagmite);
	self.* = .{
		.block = main.blocks.parseBlock(parameters.get([]const u8, "block", "cubyz:stalagmite")),
		.size = parameters.get(f32, "size", 12),
		.sizeVariation = parameters.get(f32, "size_variation", 8),
		.slope = parameters.get(f32, "slope", 4.0),
		.pointiness = std.math.clamp(parameters.get(f32, "pointiness", 0), 0, 1),
	};
	return self;
}

pub fn generate(self: *Stalagmite, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, _: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	const relX: f32 = @as(f32, @floatFromInt(x)) + main.random.nextFloat(seed)*0.6 - 0.3;
	const relY: f32 = @as(f32, @floatFromInt(y)) + main.random.nextFloat(seed)*0.6 - 0.3;
	const relZ: f32 = @as(f32, @floatFromInt(z)) + main.random.nextFloat(seed)*0.6 - 0.3;

	const height = self.size + random.nextFloat(seed)*self.sizeVariation;

	const baseRadius = height/self.slope;

	const xMin: i32 = @intFromFloat(@floor(relX - baseRadius));
	const xMax: i32 = @intFromFloat(@ceil(relX + baseRadius));
	const yMin: i32 = @intFromFloat(@floor(relY - baseRadius));
	const yMax: i32 = @intFromFloat(@ceil(relY + baseRadius));
	var x3: i32 = xMin;
	while(x3 <= xMax) : (x3 += 1) {
		var y3: i32 = yMin;
		while(y3 <= yMax) : (y3 += 1) {
			const distSquare = vec.lengthSquare(Vec2f{@as(f32, @floatFromInt(x3)) - relX, @as(f32, @floatFromInt(y3)) - relY});
			if(distSquare >= baseRadius*baseRadius) continue;
			const scale = 1 - @sqrt(distSquare)/baseRadius;
			const columnHeight = std.math.lerp(scale, scale*scale, self.pointiness)*height;
			if(x3 >= 0 and x3 < chunk.super.width and y3 >= 0 and y3 < chunk.super.width) {
				const zMin: i32 = @intFromFloat(@round(relZ - columnHeight));
				const zMax: i32 = @intFromFloat(@round(relZ + columnHeight));
				var z3: i32 = zMin;
				while(z3 <= zMax) : (z3 += 1) {
					if(z3 >= 0 and z3 < chunk.super.width) {
						const block: main.blocks.Block = chunk.getBlock(x3, y3, z3);
						if(block.typ == 0 or block.degradable()) {
							chunk.updateBlockInGeneration(x3, y3, z3, self.block);
						}
					}
				}
			}
		}
	}
}
