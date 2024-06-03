const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pub const id = "cubyz:lake";

const Lake = @This();

liquid: u16,
size: f32,
depth: f32,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: JsonElement) *Lake {
	const self = arenaAllocator.create(Lake);
	self.* = .{
		.liquid = main.blocks.getByID(parameters.get([]const u8, "liquid", "cubyz:water")),
		.size = parameters.get(f32, "size", 12),
		.depth = parameters.get(f32, "depth", 2),
	};
	return self;
}

pub fn generate(self: *Lake, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) void {
	_ = caveMap;

	const radius = self.size;
	// My basic idea is to use a point cloud and a potential function to achieve somewhat smooth lakes without being a sphere.
	const numberOfPoints = 4;
	var pointCloud: [numberOfPoints]Vec3f = undefined;
	for(&pointCloud) |*point| {
		point.* = Vec3f {
			(random.nextFloat(seed) - 0.5)*radius/2,
			(random.nextFloat(seed) - 0.5)*radius/2,
			(random.nextFloat(seed) - 0.5)*radius/2,
		};
	}

	const fx: f32 = @floatFromInt(x);
	const fy: f32 = @floatFromInt(y);
	const fz: f32 = @floatFromInt(z);

	// My potential functions is ¹⁄ₙ Σ (radius/2)²/(x⃗ - x⃗ₚₒᵢₙₜ)²
	// This ensures that the entire lake is inside of a square with sidelength 2*radius.
	const maxRadius: i32 = @intFromFloat(@ceil(radius));
	const maxHeight: i32 = @intFromFloat(@ceil(self.depth));
	const scale: f32 = @as(f32, @floatFromInt(maxHeight)) / @as(f32, @floatFromInt(maxRadius));

	var px = chunk.startIndex(x - maxRadius);
	while(px < x + maxRadius) : (px += chunk.super.pos.voxelSize) {
		var py = chunk.startIndex(y - maxRadius);
		while(py < y + maxRadius) : (py += chunk.super.pos.voxelSize) {
			var pz = chunk.startIndex(z - maxHeight);
			while(pz < z + maxHeight) : (pz += chunk.super.pos.voxelSize) {
				if(!chunk.liesInChunk(px, py, pz)) continue;
				var potential: f32 = 0;

				const fpx: f32 = @floatFromInt(px);
				const fpy: f32 = @floatFromInt(py);
				const fpz: f32 = @floatFromInt(pz);

				for(&pointCloud) |point| {
					const cfpz: f32 = @min(fpz, fz + point[2]);
					const delta = Vec3f{fpx, fpy, cfpz / scale} - Vec3f{fx, fy, fz / scale} - @as(Vec3f, .{point[0], point[1], point[2] / scale});
					const distSqr = vec.dot(delta, delta);
					potential += 1/distSqr;
				}
				potential *= radius*radius/4/numberOfPoints;
				if(potential >= 1 and z > pz) {
					chunk.updateBlockInGeneration(px, py, pz, .{.typ = self.liquid, .data = 0}); // TODO: Natural standard.
				} else if (potential >= 0.7 and z > pz and chunk.getBlock(px, py, pz).typ == 0) {
					u16 typ = chunk.
					chunk.updateBlockInGeneration(px, py, pz, .{.typ = main.blocks.getByID("cubyz:stone"), .data = 0});
				} else if (potential >= 1 and chunk.getBlock(px, py, pz).typ != 0) {
					chunk.updateBlockInGeneration(px, py, pz, .{.typ = 0, .data = 0});
				}
			}
		}
	}
}
