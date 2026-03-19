const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const sdf = main.server.terrain.sdf;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const id = "cubyz:torus";

minRadius: f32,
maxRadius: f32,
minThickness: f32,
maxThickness: f32,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	result.minThickness = zon.get(f32, "minThickness", 8);
	result.maxThickness = zon.get(f32, "maxRadius", result.minThickness);
	return result;
}

pub fn generate(self: *@This(), output: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, _seed: u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void {
	var seed = _seed;
	const radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(&seed);
	const thickness = self.minThickness + (self.maxThickness - self.minThickness)*main.random.nextFloat(&seed);

	const relPosF32: Vec3f = @floatFromInt(relPos);
	const dimVector: Vec3f = @floatFromInt(@Vector(3, u32){output.width*voxelSize, output.depth*voxelSize, output.height*voxelSize});
	const minXY = @max(@as(Vec3f, @splat(0)), relPosF32 - @as(Vec3f, @splat(radius + thickness + perimeter)));
	const maxXY = @min(dimVector, relPosF32 + @as(Vec3f, @splat(radius + thickness + perimeter)));
	const minZ = @max(@as(Vec3f, @splat(0)), relPosF32 - @as(Vec3f, @splat(thickness + perimeter)));
	const maxZ = @min(dimVector, relPosF32 + @as(Vec3f, @splat(thickness + perimeter)));

	const minIntXY: @Vector(3, u31) = @intFromFloat(minXY);
	const maxIntXY: Vec3i = @intFromFloat(@ceil(maxXY));
	const minIntZ: @Vector(3, u31) = @intFromFloat(minZ);
	const maxIntZ: Vec3i = @intFromFloat(@ceil(maxZ));

	var x = minIntXY[0] & ~(voxelSize - 1);
	while (x < maxIntXY[0]) : (x += voxelSize) {
		var y = minIntXY[1] & ~(voxelSize - 1);
		while (y < maxIntXY[1]) : (y += voxelSize) {
			var z = minIntZ[2] & ~(voxelSize - 1);
			while (z < maxIntZ[2]) : (z += voxelSize) {
				const xDifference: f32 = @floatFromInt(x - relPos[0]);
				const yDifference: f32 = @floatFromInt(y - relPos[1]);
				const zDifference: f32 = @floatFromInt(z - relPos[2]);
				const circularDistance: f32 = @sqrt(xDifference*xDifference + yDifference*yDifference);
				const adjustedDistance: f32 = circularDistance - radius;
				const radialDistance: f32 = @sqrt(adjustedDistance*adjustedDistance + zDifference*zDifference) - thickness;
				if (radialDistance - perimeter > 0) continue;

				const out = output.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);
				out.* = sdf.smoothUnion(radialDistance, out.*, interpolationSmoothness.get(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift));
			}
		}
	}
}
