const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const sdf = main.server.terrain.sdf;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const id = "cubyz:partial_sphere";

minRadius: f32,
maxRadius: f32,
cutPercentage: f32,
cutDirection: Vec3f,
cutDirectionRandomness: f32,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	result.cutPercentage = zon.get(f32, "cutPercentage", 0.5);
	result.cutDirection = vec.normalize(zon.get(Vec3f, "cutDirection", .{0, 0, -1}));
	result.cutDirectionRandomness = zon.get(f32, "cutDirectionRandomness", 0);
	return result;
}

pub fn generate(self: *@This(), output: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, _seed: u64, _perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void {
	const perimeter = _perimeter + @as(f32, @floatFromInt(voxelSize));
	var seed = _seed;
	const radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(&seed);

	var relPosF32: Vec3f = @floatFromInt(relPos);
	const cutDirection = vec.normalize(self.cutDirection + main.random.nextFloatVectorSigned(3, &seed)*@as(Vec3f, @splat(self.cutDirectionRandomness)));
	relPosF32 += cutDirection*@as(Vec3f, @splat(self.cutPercentage/2*radius));
	const dimVector: Vec3f = @floatFromInt(@Vector(3, u32){output.width*voxelSize, output.depth*voxelSize, output.height*voxelSize});
	const min = @max(@as(Vec3f, @splat(0)), relPosF32 - @as(Vec3f, @splat(radius + perimeter)));
	const max = @min(dimVector, relPosF32 + @as(Vec3f, @splat(radius + perimeter)));

	const minInt: @Vector(3, u31) = @intFromFloat(min);
	const maxInt: Vec3i = @intFromFloat(@ceil(max));

	var x = minInt[0] & ~(voxelSize - 1);
	while(x < maxInt[0]) : (x += voxelSize) {
		var y = minInt[1] & ~(voxelSize - 1);
		while(y < maxInt[1]) : (y += voxelSize) {
			var z = minInt[2] & ~(voxelSize - 1);
			while(z < maxInt[2]) : (z += voxelSize) {
				const centerDistance = @as(Vec3f, @floatFromInt(Vec3i{x, y, z})) - relPosF32;
				const distanceSquare: f32 = vec.lengthSquare(centerDistance);
				if(distanceSquare > (radius + perimeter)*(radius + perimeter)) continue;

				const directionDistance = vec.dot(cutDirection, centerDistance) - radius + self.cutPercentage*radius*2;
				if(directionDistance > perimeter) continue;

				const sphereSdf = @sqrt(distanceSquare) - radius;
				const fullSdf: f32 = sdf.intersection(sphereSdf, directionDistance);

				const out = output.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);
				out.* = sdf.smoothUnion(fullSdf, out.*, interpolationSmoothness.get(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift));
			}
		}
	}
}
