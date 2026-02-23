const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const sdf = main.server.terrain.sdf;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const id = "cubyz:cylinder";

minRadius: f32,
maxRadius: f32,
minHalfHeight: f32,
maxHalfHeight: f32,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	result.minHalfHeight = zon.get(f32, "minHeight", 32)/2;
	result.maxHalfHeight = zon.get(f32, "maxfHeight", result.minHalfHeight*2)/2;
	return result;
}

pub fn generate(self: *@This(), output: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, _seed: u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void {
	var seed = _seed;
	const radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(&seed);
	const halfHeight = self.minHalfHeight + (self.maxHalfHeight - self.minHalfHeight)*main.random.nextFloat(&seed);

	const relPosF32: Vec3f = @floatFromInt(relPos);
	const dimVector: Vec3f = @floatFromInt(@Vector(3, u32){output.width*voxelSize, output.depth*voxelSize, output.height*voxelSize});
	const min = @max(@as(Vec3f, @splat(0)), relPosF32 - Vec3f{radius, radius, halfHeight} - @as(Vec3f, @splat(perimeter)));
	const max = @min(dimVector, relPosF32 + Vec3f{radius, radius, halfHeight} + @as(Vec3f, @splat(perimeter)));

	const minInt: @Vector(3, u31) = @intFromFloat(min);
	const maxInt: Vec3i = @intFromFloat(@ceil(max));

	var x = minInt[0] & ~(voxelSize - 1);
	while (x < maxInt[0]) : (x += voxelSize) {
		var y = minInt[1] & ~(voxelSize - 1);
		while (y < maxInt[1]) : (y += voxelSize) {
			var z = minInt[2] & ~(voxelSize - 1);
			while (z < maxInt[2]) : (z += voxelSize) {
				const circleSdf: f32 = vec.length(@as(Vec2f, @floatFromInt(Vec2i{x, y} - vec.xy(relPos)))) - radius;
				const heightSdf: f32 = @as(f32, @floatFromInt(@abs(z - relPos[2]))) - halfHeight;
				const fullSdf = vec.length(@max(Vec2f{heightSdf, circleSdf}, Vec2f{0, 0})) + @min(0, @max(circleSdf, heightSdf));
				if (fullSdf > perimeter) continue;

				const out = output.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);
				out.* = sdf.smoothUnion(fullSdf, out.*, interpolationSmoothness.get(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift));
			}
		}
	}
}
