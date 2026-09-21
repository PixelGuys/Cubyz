const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:fractal_cave";

pub const priority = 131072;

pub const generatorSeed = 0xb898ec9ce9d2ef37;

pub const defaultState = .enabled;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

const chunkShift = 5;
const chunkSize = 1 << chunkShift;
const range = 8*chunkSize;
const initialBranchLength = 64;
const splittingChance = 0.4;
const splitFactor = 1.0;
const zSplitReduction = 0.5; // To reduce splitting in z-direction.
const maxSplitLength = 128;
const branchChance = 0.4;
const minRadius = 2.0;
const maxInitialRadius = 5;
const heightVariance = 0.15;

// TODO: Should probably use fixed point arithmetic to avoid crashes at the world border.

pub fn generate(map: *CaveMapFragment, worldSeed: u64) void {
	if (map.pos.voxelSize > 2) return;

	const biomeMap = CaveBiomeMapView.init(main.stackAllocator, map.pos, CaveMapFragment.width*map.pos.voxelSize, CaveMapFragment.width*map.pos.voxelSize + range*3/2);
	defer biomeMap.deinit();
	// Generate caves from all nearby chunks:
	var wz = map.pos.wz -% 2*range;
	while (wz -% map.pos.wz -% CaveMapFragment.height*map.pos.voxelSize -% range < 0) : (wz +%= chunkSize) {
		const caveLayer = terrain.cave_layers.getLayer(wz);

		var wx = map.pos.wx -% range;
		while (wx -% map.pos.wx -% CaveMapFragment.width*map.pos.voxelSize -% range < 0) : (wx +%= chunkSize) {
			var wy = map.pos.wy -% 2*range;
			while (wy -% map.pos.wy -% CaveMapFragment.width*map.pos.voxelSize -% range < 0) : (wy +%= chunkSize) {
				var seed: u64 = random.initSeed3D(worldSeed, .{wx, wy, wz});
				considerCoordinates(wx, wy, wz, map, &biomeMap, caveLayer, &seed, worldSeed);
			}
		}
	}
}

fn getSphereBounds(center: Vec3f, radius: f32, maxExtent: Vec3i) struct { Vec3i, Vec3i } {
	// the call to this in `generateSphere_` doesn't leak through to this function.
	@setFloatMode(.optimized);
	const vecRadius: Vec3f = @splat(radius);
	const vec3iOne: Vec3i = @splat(1);

	const minBound = @as(Vec3i, @trunc(center - vecRadius)) - vec3iOne;
	const maxBound = @as(Vec3i, @trunc(center + vecRadius)) + vec3iOne;

	return .{
		@max(minBound, @as(Vec3i, @splat(0))),
		@min(maxBound, maxExtent),
	};
}

fn generateSphere_(seed: *u64, map: *CaveMapFragment, relPos: Vec3f, radius: f32, comptime terrainModifier: CaveMapFragment.TerrainModifier) void {
	@setFloatMode(.optimized);

	// Makes walls rough by adding a 1-in-roughnessChance chance that blocks
	// remain unchanged.
	const roughnessChance = 6;
	const voxelSize = map.pos.voxelSize;
	const scaledWidth = CaveMapFragment.width*voxelSize;
	const scaledHeight = CaveMapFragment.height*voxelSize;

	const minDist, const maxDist = getSphereBounds(relPos, radius, .{scaledWidth, scaledWidth, scaledHeight});
	if (@reduce(.Or, minDist >= maxDist)) return;

	const relX, const relY, const relZ = relPos;
	const minXDist, const minYDist, _ = minDist;
	const maxXDist, const maxYDist, _ = maxDist;

	const radiusSquare = radius*radius;
	const thresholdXY = 0.9*0.9*radiusSquare;

	// Go through all blocks within range of the sphere center and remove them.
	var curX = minXDist;
	while (curX < maxXDist) : (curX += voxelSize) {
		const dx = @as(f32, @floatFromInt(curX)) - relX;

		var curY = minYDist;
		while (curY < maxYDist) : (curY += voxelSize) {
			const dy = @as(f32, @floatFromInt(curY)) - relY;
			const xySumSquare = @mulAdd(f32, dy, dy, dx*dx);

			var zMin: i32 = @trunc(relZ);
			var zMax: i32 = @trunc(relZ);
			if (xySumSquare < thresholdXY) {
				const zDistance = @sqrt(thresholdXY - xySumSquare);
				zMin = @trunc(relZ - zDistance);
				zMax = @trunc(relZ + zDistance);
				map.modifyTerrain(terrainModifier, curX, curY, zMin, zMax);
			}

			// My rather poor attempt at explaining to whatever poor soul wants to
			// understand this:
			//
			// (x - r_x)^2 + (y - r_y)^2 + (z - r_z)^2 = r^2
			// we already know x and y, so:
			// (z - r_z)^2 = r^2 - xySumSquare
			// z = r_z +- sqrt(r^2 - xySumSquare)
			// where +z is the upper-bound, and -z is the lower-bound
			//
			// this calculation allows us to avoid checking per-iteration if a voxel is
			// within the sphere that we were doing before
			if (xySumSquare >= radiusSquare) continue;
			const outerZDistance = @sqrt(radiusSquare - xySumSquare);
			const outerZMax: i32 = @min(@as(i32, @trunc(relZ + outerZDistance)), scaledHeight);
			const outerZMin: i32 = @max(@as(i32, @trunc(relZ - outerZDistance)), 0);

			// Add some roughness to the upper cave walls:
			var curZ: i32 = zMax;
			while (curZ <= outerZMax) : (curZ += voxelSize) {
				if (random.nextIntBounded(u8, seed, roughnessChance) != 0) {
					map.modifyTerrain(terrainModifier, curX, curY, curZ, curZ + 1);
				}
			}

			// Add some roughness to the lower cave walls:
			curZ = zMin;
			while (curZ >= outerZMin) : (curZ -= voxelSize) {
				if (random.nextIntBounded(u8, seed, roughnessChance) != 0) {
					map.modifyTerrain(terrainModifier, curX, curY, curZ, curZ + 1);
				}
			}
		}
	}
}

fn generateSphere(seed: *u64, map: *CaveMapFragment, relPos: Vec3f, radius: f32) void {
	if (radius < 0) {
		generateSphere_(seed, map, relPos, -radius, .add);
	} else {
		generateSphere_(seed, map, relPos, radius, .remove);
	}
}

fn generateCaveBetween(_seed: u64, map: *CaveMapFragment, startRelPos: Vec3f, endRelPos: Vec3f, bias: Vec3f, startRadius: f32, endRadius: f32, randomness: f32) void {
	// Check if the segment can cross this chunk:
	const maxHeight = @max(@abs(startRadius), @abs(endRadius));
	const distance = vec.length(startRelPos - endRelPos);
	const maxFractalShift = distance*randomness;
	const safetyInterval = maxHeight + maxFractalShift;
	const min: Vec3i = @trunc(@min(startRelPos, endRelPos) - @as(Vec3f, @splat(safetyInterval)));
	const max: Vec3i = @trunc(@max(startRelPos, endRelPos) + @as(Vec3f, @splat(safetyInterval)));
	// Only divide further if the cave may go through the considered chunk.
	if (min[0] >= CaveMapFragment.width*map.pos.voxelSize or max[0] < 0) return;
	if (min[1] >= CaveMapFragment.width*map.pos.voxelSize or max[1] < 0) return;
	if (min[2] >= CaveMapFragment.height*map.pos.voxelSize or max[2] < 0) return;

	var seed = _seed;
	random.scrambleSeed(&seed);
	if (distance < @as(f32, @floatFromInt(map.pos.voxelSize))) {
		generateSphere(&seed, map, startRelPos, startRadius);
	} else { // Otherwise go to the next fractal level:
		const mid = (startRelPos + endRelPos)/@as(Vec3f, @splat(2)) + @as(Vec3f, @splat(maxFractalShift))*Vec3f{
			random.nextFloatSigned(&seed),
			random.nextFloatSigned(&seed),
			random.nextFloatSigned(&seed),
		} + bias/@as(Vec3f, @splat(4));
		var midRadius = (startRadius + endRadius)/2 + maxFractalShift*random.nextFloatSigned(&seed)*heightVariance;
		midRadius = std.math.sign(midRadius)*@max(@abs(midRadius), minRadius);
		generateCaveBetween(random.nextInt(u64, &seed), map, startRelPos, mid, bias/@as(Vec3f, @splat(4)), startRadius, midRadius, randomness);
		generateCaveBetween(random.nextInt(u64, &seed), map, mid, endRelPos, bias/@as(Vec3f, @splat(4)), midRadius, endRadius, randomness);
	}
}

fn generateCaveBetweenAndCheckBiomeProperties(_seed: u64, map: *CaveMapFragment, biomeMap: *const CaveBiomeMapView, startRelPos: Vec3f, endRelPos: Vec3f, bias: Vec3f, startRadius: f32, endRadius: f32, randomness: f32) void {
	// Check if the segment can cross this chunk:
	const maxHeight = @max(@abs(startRadius), @abs(endRadius));
	const distance = vec.length(startRelPos - endRelPos);
	const maxFractalShift = distance*randomness;
	const safetyInterval = maxHeight + maxFractalShift;
	const min: Vec3i = @trunc(@min(startRelPos, endRelPos) - @as(Vec3f, @splat(safetyInterval)));
	const max: Vec3i = @trunc(@max(startRelPos, endRelPos) + @as(Vec3f, @splat(safetyInterval)));
	// Only divide further if the cave may go through the considered chunk.
	if (min[0] >= CaveMapFragment.width*map.pos.voxelSize or max[0] < 0) return;
	if (min[1] >= CaveMapFragment.width*map.pos.voxelSize or max[1] < 0) return;
	if (min[2] >= CaveMapFragment.height*map.pos.voxelSize or max[2] < 0) return;

	const startRadiusFactor = biomeMap.getRoughBiome(map.pos.wx +% @as(i32, @trunc(startRelPos[0])), map.pos.wy +% @as(i32, @trunc(startRelPos[1])), map.pos.wz +% @as(i32, @trunc(startRelPos[2])), false, undefined, false).caveRadiusFactor;
	const endRadiusFactor = biomeMap.getRoughBiome(map.pos.wx +% @as(i32, @trunc(endRelPos[0])), map.pos.wy +% @as(i32, @trunc(endRelPos[1])), map.pos.wz +% @as(i32, @trunc(endRelPos[2])), false, undefined, false).caveRadiusFactor;
	generateCaveBetween(_seed, map, startRelPos, endRelPos, bias, startRadius*startRadiusFactor, endRadius*endRadiusFactor, randomness);
}

fn generateBranchingCaveBetween(_seed: u64, map: *CaveMapFragment, biomeMap: *const CaveBiomeMapView, startRelPos: Vec3f, endRelPos: Vec3f, bias: Vec3f, startRadius: f32, endRadius: f32, seedPos: Vec3f, branchLength: f32, randomness: f32, isStart: bool, isEnd: bool) void {
	const distance = vec.length(startRelPos - endRelPos);
	var seed = _seed;
	random.scrambleSeed(&seed);
	if (distance < 32) {
		// No more branches below that level to avoid crowded caves.
		generateCaveBetweenAndCheckBiomeProperties(random.nextInt(u64, &seed), map, biomeMap, startRelPos, endRelPos, bias, startRadius, endRadius, randomness);
		// Small chance to branch off:
		if (!isStart and random.nextFloat(&seed) < branchChance and branchLength > 8) {
			var newEndPos = startRelPos + Vec3f{
				branchLength*random.nextFloatSigned(&seed),
				branchLength*random.nextFloatSigned(&seed),
				branchLength*random.nextFloatSigned(&seed),
			};
			const distanceToSeedPoint = vec.length(newEndPos - seedPos);
			// Reduce distance to avoid cutoffs:
			if (distanceToSeedPoint > range - chunkSize) {
				newEndPos = seedPos + (newEndPos - seedPos)*@as(Vec3f, @splat((range - chunkSize)/distanceToSeedPoint));
			}
			const newStartRadius = (startRadius - minRadius)*random.nextFloat(&seed) + minRadius;
			const newBias = Vec3f{
				branchLength*random.nextFloatSigned(&seed),
				branchLength*random.nextFloatSigned(&seed),
				branchLength*random.nextFloatSigned(&seed)/2,
			};
			generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, startRelPos, newEndPos, newBias, newStartRadius, minRadius, seedPos, branchLength/2, @min(0.5/@sqrt(3.0) - 0.01, randomness + randomness*random.nextFloat(&seed)*random.nextFloat(&seed)), true, true);
		}
		return;
	}

	const maxFractalShift = distance*randomness;
	const weight: f32 = 0.25 + random.nextFloat(&seed)*0.5; // Do slightly random subdivision instead of binary subdivision, to avoid regular patterns.

	const w1 = (1 - weight)*(1 - weight);
	const w2 = weight*weight;
	// Small chance to generate a split:
	if (!isStart and !isEnd and distance < maxSplitLength and random.nextFloat(&seed) < splittingChance) {
		// Find a random direction perpendicular to the current cave direction:
		var splitXY: f32 = random.nextFloat(&seed) - 0.5;
		var splitZ: f32 = zSplitReduction*(random.nextFloat(&seed) - 0.5);
		// Normalize
		const length = @sqrt(splitXY*splitXY + splitZ*splitZ);
		splitXY /= length;
		splitZ /= length;
		// Calculate bias offsets:
		const biasLength = vec.length(bias);
		const offsetX = splitXY*splitFactor*distance*bias[1]/biasLength;
		const offsetY = splitXY*splitFactor*distance*bias[0]/biasLength;
		const offsetZ = splitZ*splitFactor*distance;

		const newBias1 = bias + Vec3f{offsetX, offsetY, offsetZ};
		const newBias2 = bias - Vec3f{offsetX, offsetY, offsetZ};

		const mid1 = startRelPos*@as(Vec3f, @splat(weight)) + endRelPos*@as(Vec3f, @splat(1 - weight)) + @as(Vec3f, @splat(maxFractalShift))*Vec3f{
			random.nextFloatSigned(&seed),
			random.nextFloatSigned(&seed),
			random.nextFloatSigned(&seed),
		} + newBias1*@as(Vec3f, @splat(weight*(1 - weight)));
		const mid2 = startRelPos*@as(Vec3f, @splat(weight)) + endRelPos*@as(Vec3f, @splat(1 - weight)) + @as(Vec3f, @splat(maxFractalShift))*Vec3f{
			random.nextFloatSigned(&seed),
			random.nextFloatSigned(&seed),
			random.nextFloatSigned(&seed),
		} + newBias2*@as(Vec3f, @splat(weight*(1 - weight)));

		var midRadius = @max(minRadius, (startRadius + endRadius)/2 + maxFractalShift*random.nextFloatSigned(&seed)*heightVariance);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, startRelPos, mid1, newBias1*@as(Vec3f, @splat(w1)), startRadius, midRadius, seedPos, branchLength, randomness, isStart, false);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, mid1, endRelPos, newBias1*@as(Vec3f, @splat(w2)), midRadius, endRadius, seedPos, branchLength, randomness, false, isEnd);
		// Do some tweaking to the radius before making the second part:
		const newStartRadius = (startRadius - minRadius)*random.nextFloat(&seed) + minRadius;
		const newEndRadius = (endRadius - minRadius)*random.nextFloat(&seed) + minRadius;
		midRadius = @max(minRadius, (newStartRadius + newEndRadius)/2 + maxFractalShift*random.nextFloatSigned(&seed)*heightVariance);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, startRelPos, mid2, newBias2*@as(Vec3f, @splat(w1)), newStartRadius, midRadius, seedPos, branchLength, randomness, isStart, false);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, mid2, endRelPos, newBias2*@as(Vec3f, @splat(w2)), midRadius, newEndRadius, seedPos, branchLength, randomness, false, isEnd);
		return;
	}
	const mid = startRelPos*@as(Vec3f, @splat(weight)) + endRelPos*@as(Vec3f, @splat(1 - weight)) + @as(Vec3f, @splat(maxFractalShift))*Vec3f{
		random.nextFloatSigned(&seed),
		random.nextFloatSigned(&seed),
		random.nextFloatSigned(&seed),
	} + bias*@as(Vec3f, @splat(weight*(1 - weight)));
	const midRadius = @max(minRadius, (startRadius + endRadius)/2 + maxFractalShift*random.nextFloatSigned(&seed)*heightVariance);
	generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, startRelPos, mid, bias*@as(Vec3f, @splat(w1)), startRadius, midRadius, seedPos, branchLength, randomness, isStart, false);
	generateBranchingCaveBetween(random.nextInt(u64, &seed), map, biomeMap, mid, endRelPos, bias*@as(Vec3f, @splat(w2)), midRadius, endRadius, seedPos, branchLength, randomness, false, isEnd);
}

fn considerCoordinates(wx: i32, wy: i32, wz: i32, map: *CaveMapFragment, biomeMap: *const CaveBiomeMapView, caveLayer: terrain.cave_layers.CaveLayer, seed: *u64, worldSeed: u64) void {
	// Choose some in world coordinates to start generating:
	const startRelPos = Vec3f{
		@floatFromInt(wx +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wx),
		@floatFromInt(wy +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wy),
		@floatFromInt(wz +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wz),
	};

	if (random.nextFloat(seed) >= caveLayer.caveDensity) return;

	var starters = 1 + random.nextIntBounded(u8, seed, 4);
	while (starters != 0) : (starters -= 1) {
		const endX = wx +% random.nextIntBounded(u31, seed, 2*range - 3*chunkSize) -% range +% chunkSize & ~@as(i32, chunkSize - 1);
		const endY = wy +% random.nextIntBounded(u31, seed, 2*range - 3*chunkSize) -% range +% chunkSize & ~@as(i32, chunkSize - 1);
		const endZ = wz +% random.nextIntBounded(u31, seed, 2*range - 3*chunkSize) -% range +% chunkSize & ~@as(i32, chunkSize - 1);
		seed.* = random.initSeed3D(worldSeed, .{endX, endY, endZ}); // Every chunk has the same start/destination position, to increase cave connectivity.
		const endRelPos = Vec3f{
			@floatFromInt(endX +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wx),
			@floatFromInt(endY +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wy),
			@floatFromInt(endZ +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wz),
		};
		const startRadius: f32 = random.nextFloat(seed)*maxInitialRadius + 2*minRadius;
		const endRadius: f32 = random.nextFloat(seed)*maxInitialRadius + 2*minRadius;
		const caveLength = vec.length(startRelPos - endRelPos);
		generateBranchingCaveBetween(random.nextInt(u64, seed), map, biomeMap, startRelPos, endRelPos, Vec3f{
			caveLength*random.nextFloatSigned(seed)/2,
			caveLength*random.nextFloatSigned(seed)/2,
			caveLength*random.nextFloatSigned(seed)/4,
		}, startRadius, endRadius, @floatFromInt(Vec3i{wx -% map.pos.wx, wy -% map.pos.wy, wz -% map.pos.wz}), initialBranchLength, 0.1, true, true);
	}
}
