const std = @import("std");

const main = @import("main");
const Array3D = main.utils.Array3D;
const sdf = main.server.terrain.sdf;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const id = "cubyz:octahedron";

minRadius: f32,
maxRadius: f32,

pub fn init(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.minRadius = zon.get(f32, "minRadius", 16);
	result.maxRadius = zon.get(f32, "maxRadius", result.minRadius);
	return result;
}

pub fn calculateProjectedPointValue(a: f32, b: f32, c: f32, radius: f32) f32 {
	// First find a clamped point on the plane of the ocahedron
	const calculatedValue: f32 = (a*2 - b - c + radius)/3;
	return @max(calculatedValue, 0);
}

pub fn calculateReProjectedPointValue(a: f32, b: f32, c: f32 , radius: f32) f32 {
	// First find a clamped point on the plane of the ocahedron
	const calculatedValue: f32 = sign(a)*(a*(sign(b)+sign(c)) - b - c + radius)/(1+(sign(b)+sign(c)));
	return @max(calculatedValue, 0);
}

fn sign(x: f32) f32 {
    return if (x > 0) 1
        else if (x < 0) -1
        else 0;
}

pub fn generate(self: *@This(), output: main.utils.Array3D(f32), interpolationSmoothness: main.utils.Array3D(f32), relPos: Vec3i, _seed: u64, perimeter: f32, voxelSize: u31, voxelSizeShift: u5) void {
	var seed = _seed;
	const radius = self.minRadius + (self.maxRadius - self.minRadius)*main.random.nextFloat(&seed);

	const relPosF32: Vec3f = @floatFromInt(relPos);
	const dimVector: Vec3f = @floatFromInt(@Vector(3, u32){output.width*voxelSize, output.depth*voxelSize, output.height*voxelSize});
	const min = @max(@as(Vec3f, @splat(0)), relPosF32 - @as(Vec3f, @splat(radius + perimeter)));
	const max = @min(dimVector, relPosF32 + @as(Vec3f, @splat(radius + perimeter)));

	const minInt: @Vector(3, u31) = @intFromFloat(min);
	const maxInt: Vec3i = @intFromFloat(@ceil(max));

	var x = minInt[0] & ~(voxelSize - 1);
	while (x < maxInt[0]) : (x += voxelSize) {
		var y = minInt[1] & ~(voxelSize - 1);
		while (y < maxInt[1]) : (y += voxelSize) {
			var z = minInt[2] & ~(voxelSize - 1);
			while (z < maxInt[2]) : (z += voxelSize) {
				const InputX: f32 = (@floatFromInt(x - relPos[0]));
				const InputY: f32 = (@floatFromInt(y - relPos[1]));
				const InputZ: f32 = (@floatFromInt(z - relPos[2]));
				const AdjustedInputX: f32 = @abs(InputX);
				const AdjustedInputY: f32 = @abs(InputY);
				const AdjustedInputZ: f32 = @abs(InputZ);
				const pointX: f32 = calculateProjectedPointValue(AdjustedInputX ,AdjustedInputY ,AdjustedInputZ, radius);
				const pointY: f32 = calculateProjectedPointValue(AdjustedInputY ,AdjustedInputX ,AdjustedInputZ, radius);
				const pointZ: f32 = calculateProjectedPointValue(AdjustedInputZ ,AdjustedInputX ,AdjustedInputY, radius);
				
				var distanceSquare: f32 = 0;

				if ((pointX == 0) or (pointY == 0) or (pointZ == 0)) {
					// projects to the nearest line if on one of the axial planes
					const point2X: f32 = calculateProjectedPointValue(pointX ,pointY ,pointZ, radius);
					const point2Y: f32 = calculateProjectedPointValue(pointY ,pointX ,pointZ, radius);
					const point2Z: f32 = calculateProjectedPointValue(pointZ ,pointX ,pointY, radius);
					if (((pointX == 0) and (pointY == 0)) or ((pointX == 0) or (pointZ == 0)) or ((pointY == 0) or (pointZ == 0))) {
					// projects to the nearest point if on one of the axial lines
						const point3X: f32 = calculateProjectedPointValue(point2X ,point2Y ,point2Z, radius);
						const point3Y: f32 = calculateProjectedPointValue(point2Y ,point2X ,point2Z, radius);
						const point3Z: f32 = calculateProjectedPointValue(point2Z ,point2X ,point2Y, radius);
						distanceSquare = (AdjustedInputX-point3X)*(AdjustedInputX-point3X) + (AdjustedInputY-point3Y)*(AdjustedInputY-point3Y) + (AdjustedInputZ-point3Z)*(AdjustedInputZ-point3Z);					
					} else {
						distanceSquare = (AdjustedInputX-point2X)*(AdjustedInputX-point2X) + (AdjustedInputY-point2Y)*(AdjustedInputY-point2Y) + (AdjustedInputZ-point2Z)*(AdjustedInputZ-point2Z);
					}
				} else {
					distanceSquare = (AdjustedInputX-pointX)*(AdjustedInputX-pointX) + (AdjustedInputY-pointY)*(AdjustedInputY-pointY) + (AdjustedInputZ-pointZ)*(AdjustedInputZ-pointZ);
				}

				const octahedronSdf = @sqrt(distanceSquare) - radius;

				const out = output.ptr(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift);
				out.* = sdf.smoothUnion(octahedronSdf, out.*, interpolationSmoothness.get(x >> voxelSizeShift, y >> voxelSizeShift, z >> voxelSizeShift));
			}
		}
	}
}
