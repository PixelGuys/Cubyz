const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const sdf = main.server.terrain.sdf;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const id = "cubyz:rectangular_cuboid";

minRadii: Vec3f,
maxRadii: Vec3f,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadii = zon.get(Vec3f, "minSideLengths", @splat(32))/@as(Vec3f, @splat(2));
	result.maxRadii = zon.get(Vec3f, "maxSideLengths", result.minRadii*@as(Vec3f, @splat(2)))/@as(Vec3f, @splat(2));
	return result;
}

pub fn generate(self: *@This(), output: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, _seed: u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void {
	var seed = _seed;
	const radii = self.minRadii + (self.maxRadii - self.minRadii)*main.random.nextFloatVector(3, &seed);

	const relPosF32: Vec3f = @floatFromInt(relPos);
	const dimVector: Vec3f = @floatFromInt(@Vector(3, u32){output.width*voxelSize, output.depth*voxelSize, output.height*voxelSize});
	const min = @max(@as(Vec3f, @splat(0)), relPosF32 - radii - @as(Vec3f, @splat(perimeter)));
	const max = @min(dimVector, relPosF32 + radii + @as(Vec3f, @splat(perimeter)));

	const minInt: @Vector(3, u31) = @intFromFloat(min);
	const maxInt: Vec3i = @intFromFloat(@ceil(max));

	var x = minInt[0] & ~(voxelSize - 1);
	while (x < maxInt[0]) : (x += voxelSize) {
		var y = minInt[1] & ~(voxelSize - 1);
		while (y < maxInt[1]) : (y += voxelSize) {
			var z = minInt[2] & ~(voxelSize - 1);
			while (z < maxInt[2]) : (z += voxelSize) {
				const dimensionalSdf: Vec3f = @as(Vec3f, @floatFromInt(@abs(Vec3i{x, y, z} - relPos))) - radii;
				const fullSdf = vec.length(@max(dimensionalSdf, @as(Vec3f, @splat(0)))) + @min(0, @max(dimensionalSdf[0], dimensionalSdf[1], dimensionalSdf[2]));
				if (fullSdf > perimeter) continue;

				const out = output.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);
				out.* = sdf.smoothUnion(fullSdf, out.*, interpolationSmoothness.get(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift));
			}
		}
	}
}
