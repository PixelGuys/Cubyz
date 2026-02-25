const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const CaveMapView = terrain.CaveMap.CaveMapView;
const GenerationMode = terrain.structures.SimpleStructureModel.GenerationMode;
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
topSlope: f32,
baseSlope: f32,

pub fn loadModel(parameters: ZonElement) ?*Stalagmite {
	const self = main.worldArena.create(Stalagmite);
	const baseSlope = parameters.get(f32, "baseSlope", 4.0);
	self.* = .{
		.block = main.blocks.parseBlock(parameters.get([]const u8, "block", "cubyz:stalagmite")),
		.size = parameters.get(f32, "size", 12),
		.sizeVariation = parameters.get(f32, "size_variation", 8),
		.baseSlope = baseSlope,
		.topSlope = parameters.get(f32, "topSlope", baseSlope),
	};
	return self;
}

pub fn generate(self: *Stalagmite, _: GenerationMode, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, _: CaveMapView, _: CaveBiomeMapView, seed: *u64, _: bool) void {
	const relX: f32 = @as(f32, @floatFromInt(x)) + main.random.nextFloat(seed)*0.6 - 0.3;
	const relY: f32 = @as(f32, @floatFromInt(y)) + main.random.nextFloat(seed)*0.6 - 0.3;
	const relZ: f32 = @as(f32, @floatFromInt(z)) + main.random.nextFloat(seed)*0.6 - 0.3;

	const height = self.size + random.nextFloat(seed)*self.sizeVariation;

	// We want to ensure the following properties:
	// height(r = 0) = height
	// height'(r = 0) = -topSlope
	// height(r = baseRadius) = 0
	// height'(r = baseRadius) = -baseSlope
	// With height(r) = a·r² + b·r + c → height'(r) = 2a·r + b
	// c = height, b = -topSlope
	// 0 = a·baseRadius² + b·baseRadius + c
	// -baseSlope = 2a·baseRadius + b
	// → a·baseRadius = (-baseSlope - b)/2
	// This permits both positive and negative values for baseRadius, so we need to account for that during substitution:
	// = (-baseSlope - b)/2·±baseRadius + b·baseRadius + c
	// → baseRadius = -c/(±(-baseSlope - b)/2 + b)
	const c = height;
	const b = -self.topSlope;
	var baseRadius: f32 = undefined;
	var a: f32 = undefined;
	if (self.baseSlope == self.topSlope) {
		baseRadius = height/self.topSlope;
		a = 0;
	} else {
		baseRadius = -c/((-self.baseSlope - b)/2 + b);
		if (baseRadius < 0) {
			baseRadius = -c/(-(-self.baseSlope - b)/2 + b);
		}
		a = (-self.baseSlope - b)/(2*baseRadius);
	}

	const xMin: i32 = @intFromFloat(@floor(relX - baseRadius));
	const xMax: i32 = @intFromFloat(@ceil(relX + baseRadius));
	const yMin: i32 = @intFromFloat(@floor(relY - baseRadius));
	const yMax: i32 = @intFromFloat(@ceil(relY + baseRadius));
	var x3: i32 = xMin;
	while (x3 <= xMax) : (x3 += 1) {
		var y3: i32 = yMin;
		while (y3 <= yMax) : (y3 += 1) {
			const distSquare = vec.lengthSquare(Vec2f{@as(f32, @floatFromInt(x3)) - relX, @as(f32, @floatFromInt(y3)) - relY});
			if (distSquare >= baseRadius*baseRadius) continue;
			const r = @sqrt(distSquare);
			const columnHeight = a*r*r + b*r + c;
			if (x3 >= 0 and x3 < chunk.super.width and y3 >= 0 and y3 < chunk.super.width) {
				const zMin: i32 = @intFromFloat(@round(relZ - columnHeight));
				const zMax: i32 = @intFromFloat(@round(relZ + columnHeight));
				var z3: i32 = zMin;
				while (z3 <= zMax) : (z3 += 1) {
					if (z3 >= 0 and z3 < chunk.super.width) {
						const block: main.blocks.Block = chunk.getBlock(x3, y3, z3);
						if (block.typ == 0 or block.degradable()) {
							chunk.updateBlockInGeneration(x3, y3, z3, self.block);
						}
					}
				}
			}
		}
	}
}
