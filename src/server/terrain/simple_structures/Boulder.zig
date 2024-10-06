const std = @import("std");

const main = @import("root");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pub const id = "cubyz:boulder";

pub const generationMode = .floor;

const Boulder = @This();

blockType: u16,
size: f32,
sizeVariation: f32,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *Boulder {
	const self = arenaAllocator.create(Boulder);
	self.* = .{
		.blockType = main.blocks.getByID(parameters.get([]const u8, "block", "cubyz:stone")),
		.size = parameters.get(f32, "size", 4),
		.sizeVariation = parameters.get(f32, "size_variation", 1),
	};
	return self;
}

pub fn generate(self: *Boulder, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64, _: bool) void {
	_ = caveMap;
	const radius = self.size + self.sizeVariation*(random.nextFloat(seed)*2 - 1);
	// My basic idea is to use a point cloud and a potential function to achieve somewhat smooth boulders without being a sphere.
	const numberOfPoints = 4;
	var pointCloud: [numberOfPoints]Vec3f = undefined;
	for(&pointCloud) |*point| {
		point.* = Vec3f {
			(random.nextFloat(seed) - 0.5)*radius/2,
			(random.nextFloat(seed) - 0.5)*radius/2,
			(random.nextFloat(seed) - 0.5)*radius/2,
		};
	}
	// My potential functions is ¹⁄ₙ Σ (radius/2)²/(x⃗ - x⃗ₚₒᵢₙₜ)²
	// This ensures that the entire boulder is inside of a square with sidelength 2*radius.
	const maxRadius: i32 = @intFromFloat(@ceil(radius));
	var px = chunk.startIndex(x - maxRadius);
	while(px < x + maxRadius) : (px += chunk.super.pos.voxelSize) {
		var py = chunk.startIndex(y - maxRadius);
		while(py < y + maxRadius) : (py += chunk.super.pos.voxelSize) {
			var pz = chunk.startIndex(z - maxRadius);
			while(pz < z + maxRadius) : (pz += chunk.super.pos.voxelSize) {
				if(!chunk.liesInChunk(px, py, pz)) continue;
				var potential: f32 = 0;
				for(&pointCloud) |point| {
					const delta = @as(Vec3f, @floatFromInt(Vec3i{px, py, pz} - Vec3i{x, y, z})) - point;
					const distSqr = vec.dot(delta, delta);
					potential += 1/distSqr;
				}
				potential *= radius*radius/4/numberOfPoints;
				if(potential >= 1) {
					chunk.updateBlockInGeneration(px, py, pz, .{.typ = self.blockType, .data = 0}); // TODO: Natural standard.
				}
			}
		}
	}
}
