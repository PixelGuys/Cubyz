const std = @import("std");
const sign = std.math.sign;

const main = @import("main");
const Array3D = main.utils.Array3D;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const FractalNoise3D = terrain.noise.FractalNoise3D;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:sdf_cave";

pub const priority = 65536;

pub const generatorSeed = 0x76490367012869;

pub const defaultState = .enabled;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn deinit() void {}

const noiseScale = 16;
const interpolatedPart = 4;

const smoothness = 4;
const perimeter = interpolatedPart*2 + smoothness*4;

fn getValue(noise: Array3D(f32), outerSizeShift: u5, relX: u31, relY: u31, relZ: u31) f32 {
	return noise.get(relX >> outerSizeShift, relY >> outerSizeShift, relZ >> outerSizeShift);
}

fn generateSdf(map: *const CaveMapFragment, biomeMap: *const CaveBiomeMapView, additiveOutput: Array3D(f32), subtractiveOutput: Array3D(f32), interpolationSmoothness: Array3D(f32), voxelSize: u31, voxelSizeShift: u5, worldSeed: u64) void {
	@memset(subtractiveOutput.mem, 1000);
	@memset(additiveOutput.mem, 1000);
	const mapPos: Vec3i = .{map.pos.wx, map.pos.wy, map.pos.wz};
	const margin: Vec3i = @splat(256 + perimeter + terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeSize);
	const biomePoints = biomeMap.getCaveBiomesInRange(main.stackAllocator, mapPos -% margin, mapPos +% margin +% Vec3i{CaveMapFragment.width, CaveMapFragment.width, CaveMapFragment.height});
	defer main.stackAllocator.free(biomePoints);

	for (biomePoints) |biomePoint| {
		var seed = main.random.initSeed3D(worldSeed, biomePoint.worldPos);
		for (biomePoint.biome.caveSdfModels) |sdfModel| {
			switch (sdfModel.mode) {
				.additive => {
					sdfModel.generate(additiveOutput, biomeMap, interpolationSmoothness, mapPos, biomePoint.worldPos, &seed, perimeter, voxelSize, voxelSizeShift);
				},
				.subtractive => {
					sdfModel.generate(subtractiveOutput, biomeMap, interpolationSmoothness, mapPos, biomePoint.worldPos, &seed, perimeter, voxelSize, voxelSizeShift);
				},
			}
		}
	}
}

pub fn generate(map: *CaveMapFragment, worldSeed: u64) void {
	if (map.pos.voxelSize > 2) return;
	const biomeMap = CaveBiomeMapView.init(main.stackAllocator, map.pos, CaveMapFragment.width*map.pos.voxelSize, 0);
	defer biomeMap.deinit();
	const outerSize = @max(map.pos.voxelSize, interpolatedPart);
	const outerSizeShift = std.math.log2_int(u31, outerSize);

	const width = CaveMapFragment.width*map.pos.voxelSize/outerSize + 1;
	const height = CaveMapFragment.height*map.pos.voxelSize/outerSize + 1;

	const subtractiveOutput = Array3D(f32).init(main.stackAllocator, width, width, height);
	defer subtractiveOutput.deinit(main.stackAllocator);
	const additiveOutput = Array3D(f32).init(main.stackAllocator, width, width, height);
	defer additiveOutput.deinit(main.stackAllocator);
	const biomeSmoothness = Array3D(f32).init(main.stackAllocator, width, width, height);
	defer biomeSmoothness.deinit(main.stackAllocator);
	const biomeNoiseStrength = Array3D(f32).init(main.stackAllocator, width, width, height);
	defer biomeNoiseStrength.deinit(main.stackAllocator);
	biomeMap.bulkInterpolateValues(&.{"caveSmoothness", "caveNoiseStrength"}, map.pos.wx, map.pos.wy, map.pos.wz, outerSize, &.{biomeSmoothness, biomeNoiseStrength});
	generateSdf(map, &biomeMap, additiveOutput, subtractiveOutput, biomeSmoothness, outerSize, outerSizeShift, worldSeed);

	generateMap(map, subtractiveOutput, biomeNoiseStrength, worldSeed, .subtractive);
	generateMap(map, additiveOutput, biomeNoiseStrength, worldSeed, .additive);
}

const Mode = enum(u8) {
	additive = 0,
	subtractive = 1,

	fn modifyRange(comptime self: Mode, map: *CaveMapFragment, relX: i32, relY: i32, start: i32, end: i32) void {
		switch (self) {
			.additive => map.addRange(relX, relY, start, end),
			.subtractive => map.removeRange(relX, relY, start, end),
		}
	}
};

fn generateMap(map: *CaveMapFragment, output: Array3D(f32), biomeNoiseStrength: Array3D(f32), worldSeed: u64, comptime mode: Mode) void {
	const outerSize = @max(map.pos.voxelSize, interpolatedPart);
	const outerSizeShift = std.math.log2_int(u31, outerSize);
	const outerSizeFloat: f32 = @floatFromInt(outerSize);

	const noise = FractalNoise3D.generateAligned(main.stackAllocator, map.pos.wx, map.pos.wy, map.pos.wz, outerSize, CaveMapFragment.width*map.pos.voxelSize/outerSize + 1, CaveMapFragment.width*map.pos.voxelSize/outerSize + 1, CaveMapFragment.height*map.pos.voxelSize/outerSize + 1, worldSeed ^ 4329561871 ^ 112*@intFromEnum(mode), noiseScale);
	defer noise.deinit(main.stackAllocator);

	for (noise.mem, output.mem, biomeNoiseStrength.mem) |*val, sdfVal, noiseStrength| {
		val.* = val.*/noiseScale*noiseStrength + sdfVal;
	}

	var x: u31 = 0;
	while (x < map.pos.voxelSize*CaveMapFragment.width) : (x += outerSize) {
		var y: u31 = 0;
		while (y < map.pos.voxelSize*CaveMapFragment.width) : (y += outerSize) {
			var z: u31 = 0;
			while (z < map.pos.voxelSize*CaveMapFragment.height) : (z += outerSize) {
				const val000 = getValue(noise, outerSizeShift, x, y, z);
				const val001 = getValue(noise, outerSizeShift, x, y, z + outerSize);
				const val010 = getValue(noise, outerSizeShift, x, y + outerSize, z);
				const val011 = getValue(noise, outerSizeShift, x, y + outerSize, z + outerSize);
				const val100 = getValue(noise, outerSizeShift, x + outerSize, y, z);
				const val101 = getValue(noise, outerSizeShift, x + outerSize, y, z + outerSize);
				const val110 = getValue(noise, outerSizeShift, x + outerSize, y + outerSize, z);
				const val111 = getValue(noise, outerSizeShift, x + outerSize, y + outerSize, z + outerSize);
				// Test if they are all inside or all outside the cave to skip these cases:
				const measureForEquality = sign(val000) + sign(val001) + sign(val010) + sign(val011) + sign(val100) + sign(val101) + sign(val110) + sign(val111);
				if (measureForEquality == 8) {
					// No cave in here :)
					continue;
				}
				if (measureForEquality == -8) {
					// All cave in here :)
					var dx: u31 = 0;
					while (dx < outerSize) : (dx += map.pos.voxelSize) {
						var dy: u31 = 0;
						while (dy < outerSize) : (dy += map.pos.voxelSize) {
							mode.modifyRange(map, x + dx, y + dy, z, z + outerSize);
						}
					}
				} else {
					// Uses trilinear interpolation for the details.
					// Luckily due to the blocky nature of the game there is no visible artifacts from it.
					var dx: u31 = 0;
					while (dx < outerSize) : (dx += map.pos.voxelSize) {
						var dy: u31 = 0;
						while (dy < outerSize) : (dy += map.pos.voxelSize) {
							const ix = @as(f32, @floatFromInt(dx))/outerSizeFloat;
							const iy = @as(f32, @floatFromInt(dy))/outerSizeFloat;
							const lowerVal = ((1 - ix)*(1 - iy)*val000 + (1 - ix)*iy*val010 + ix*(1 - iy)*val100 + ix*iy*val110);
							const upperVal = ((1 - ix)*(1 - iy)*val001 + (1 - ix)*iy*val011 + ix*(1 - iy)*val101 + ix*iy*val111);
							// TODO: Determine the range that needs to be removed, and remove it in one go.
							if (upperVal*lowerVal > 0) { // All z values have the same sign → the entire column is the same.
								if (upperVal < 0) {
									// All cave in here :)
									mode.modifyRange(map, x + dx, y + dy, z, z + outerSize);
								} else {
									// No cave in here :)
								}
							} else {
								// Could be more efficient, but I'm lazy right now and I'll just go through the entire range:
								var dz: u31 = 0;
								while (dz < outerSize) : (dz += map.pos.voxelSize) {
									const iz = @as(f32, @floatFromInt(dz))/outerSizeFloat;
									const val = (1 - iz)*lowerVal + iz*upperVal;
									if (val < 0) {
										mode.modifyRange(map, x + dx, y + dy, z + dz, z + dz + map.pos.voxelSize);
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
