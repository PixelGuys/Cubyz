const std = @import("std");

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const InterpolatableCaveBiomeMapView = terrain.CaveBiomeMap.InterpolatableCaveBiomeMapView;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:fractal_cave";

pub const priority = 65536;

pub const generatorSeed = 0xb898ec9ce9d2ef37;

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
const maxCaveHeight = 128;
const caveHeightWithMaxDensity = -512;
const maxCaveDensity = 1.0/32.0;

// TODO: Should probably use fixed point arithmetic to avoid crashes at the world border.

pub fn generate(map: *CaveMapFragment, worldSeed: u64) void {
	if(map.pos.voxelSize > 2) return;

	const biomeMap: InterpolatableCaveBiomeMapView = InterpolatableCaveBiomeMapView.init(main.stackAllocator, map.pos, CaveMapFragment.width*map.pos.voxelSize, CaveMapFragment.width*map.pos.voxelSize + maxCaveHeight*3);
	defer biomeMap.deinit();
	// Generate caves from all nearby chunks:
	var wx = map.pos.wx -% range;
	while(wx -% map.pos.wx -% CaveMapFragment.width*map.pos.voxelSize -% range < 0) : (wx +%= chunkSize) {
		var wy = map.pos.wy -% 2*range;
		while(wy -% map.pos.wy -% CaveMapFragment.width*map.pos.voxelSize -% range < 0) : (wy +%= chunkSize) {
			var wz = map.pos.wz -% 2*range;
			while(wz -% map.pos.wz -% CaveMapFragment.height*map.pos.voxelSize -% range < 0) : (wz +%= chunkSize) {
				var seed: u64 = random.initSeed3D(worldSeed, .{wx, wy, wz});
				considerCoordinates(wx, wy, wz, map, &biomeMap, &seed, worldSeed);
			}
		}
	}
}

fn generateSphere_(seed: *u64, map: *CaveMapFragment, relPos: Vec3f, radius: f32, comptime addTerrain: bool) void {
	const relX = relPos[0];
	const relY = relPos[1];
	const relZ = relPos[2];
	var xMin = @as(i32, @intFromFloat(relX - radius)) - 1;
	xMin = @max(xMin, 0);
	var xMax = @as(i32, @intFromFloat(relX + radius)) + 1;
	xMax = @min(xMax, CaveMapFragment.width*map.pos.voxelSize);
	var yMin = @as(i32, @intFromFloat(relY - radius)) - 1;
	yMin = @max(yMin, 0);
	var yMax = @as(i32, @intFromFloat(relY + radius)) + 1;
	yMax = @min(yMax, CaveMapFragment.width*map.pos.voxelSize);
	if(xMin >= xMax or yMin >= yMax or relZ - radius + 1 >= @as(f32, @floatFromInt(CaveMapFragment.height*map.pos.voxelSize)) or relZ + radius + 1 < 0) {
		return;
	}
	// Go through all blocks within range of the sphere center and remove them.
	var curX = xMin;
	while(curX < xMax) : (curX += map.pos.voxelSize) {
		const distToCenterX = (@as(f32, @floatFromInt(curX)) - relX)/radius;
		var curY = yMin;
		while(curY < yMax) : (curY += map.pos.voxelSize) {
			const distToCenterY = (@as(f32, @floatFromInt(curY)) - relY)/radius;
			const xyDistanceSquared = distToCenterX*distToCenterX + distToCenterY*distToCenterY;
			var zMin: i32 = @intFromFloat(relZ);
			var zMax: i32 = @intFromFloat(relZ);
			if(xyDistanceSquared < 0.9*0.9) {
				const zDistance = radius*@sqrt(0.9*0.9 - xyDistanceSquared);
				zMin = @intFromFloat(relZ - zDistance);
				zMax = @intFromFloat(relZ + zDistance);
				if(addTerrain) {
					map.addRange(curX, curY, zMin, zMax); // Add the center range in a single call.
				} else {
					map.removeRange(curX, curY, zMin, zMax); // Remove the center range in a single call.
				}
			}
			// Add some roughness at the upper cave walls:
			var curZ: i32 = zMax;
			while(curZ <= CaveMapFragment.height*map.pos.voxelSize) : (curZ += map.pos.voxelSize) {
				const distToCenterZ = (@as(f32, @floatFromInt(curZ)) - relZ)/radius;
				const distToCenter = distToCenterZ*distToCenterZ + xyDistanceSquared;
				if(distToCenter < 1) {
					// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
					if(random.nextIntBounded(u8, seed, 6) != 0) {
						if(addTerrain) {
							map.addRange(curX, curY, curZ, curZ + 1);
						} else {
							map.removeRange(curX, curY, curZ, curZ + 1);
						}
					}
				} else break;
			}
			// Add some roughness at the lower cave walls:
			curZ = zMin;
			while(curZ >= 0) : (curZ -= map.pos.voxelSize) {
				const distToCenterZ = (@as(f32, @floatFromInt(curZ)) - relZ)/radius;
				const distToCenter = distToCenterZ*distToCenterZ + xyDistanceSquared;
				if(distToCenter < 1) {
					// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
					if(random.nextIntBounded(u8, seed, 6) != 0) {
						if(addTerrain) {
							map.addRange(curX, curY, curZ, curZ + 1);
						} else {
							map.removeRange(curX, curY, curZ, curZ + 1);
						}
					}
				} else break;
			}
		}
	}
}

fn generateSphere(seed: *u64, map: *CaveMapFragment, relPos: Vec3f, radius: f32) void {
	if(radius < 0) {
		generateSphere_(seed, map, relPos, -radius, true);
	} else {
		generateSphere_(seed, map, relPos, radius, false);
	}
}

fn generateCaveBetween(_seed: u64, map: *CaveMapFragment, startRelPos: Vec3f, endRelPos: Vec3f, bias: Vec3f, startRadius: f32, endRadius: f32, randomness: f32) void {
	// Check if the segment can cross this chunk:
	const maxHeight = @max(@abs(startRadius), @abs(endRadius));
	const distance = vec.length(startRelPos - endRelPos);
	const maxFractalShift = distance*randomness;
	const safetyInterval = maxHeight + maxFractalShift;
	const min: Vec3i = @intFromFloat(@min(startRelPos, endRelPos) - @as(Vec3f, @splat(safetyInterval)));
	const max: Vec3i = @intFromFloat(@max(startRelPos, endRelPos) + @as(Vec3f, @splat(safetyInterval)));
	// Only divide further if the cave may go through the considered chunk.
	if(min[0] >= CaveMapFragment.width*map.pos.voxelSize or max[0] < 0) return;
	if(min[1] >= CaveMapFragment.width*map.pos.voxelSize or max[1] < 0) return;
	if(min[2] >= CaveMapFragment.height*map.pos.voxelSize or max[2] < 0) return;

	var seed = _seed;
	random.scrambleSeed(&seed);
	if(distance < @as(f32, @floatFromInt(map.pos.voxelSize))) {
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

fn generateCaveBetweenAndCheckBiomeProperties(_seed: u64, map: *CaveMapFragment, biomeMap: *const InterpolatableCaveBiomeMapView, startRelPos: Vec3f, endRelPos: Vec3f, bias: Vec3f, startRadius: f32, endRadius: f32, randomness: f32) void {
	// Check if the segment can cross this chunk:
	const maxHeight = @max(@abs(startRadius), @abs(endRadius));
	const distance = vec.length(startRelPos - endRelPos);
	const maxFractalShift = distance*randomness;
	const safetyInterval = maxHeight + maxFractalShift;
	const min: Vec3i = @intFromFloat(@min(startRelPos, endRelPos) - @as(Vec3f, @splat(safetyInterval)));
	const max: Vec3i = @intFromFloat(@max(startRelPos, endRelPos) + @as(Vec3f, @splat(safetyInterval)));
	// Only divide further if the cave may go through the considered chunk.
	if(min[0] >= CaveMapFragment.width*map.pos.voxelSize or max[0] < 0) return;
	if(min[1] >= CaveMapFragment.width*map.pos.voxelSize or max[1] < 0) return;
	if(min[2] >= CaveMapFragment.height*map.pos.voxelSize or max[2] < 0) return;

	const startRadiusFactor = biomeMap.getRoughBiome(map.pos.wx +% @as(i32, @intFromFloat(startRelPos[0])), map.pos.wy +% @as(i32, @intFromFloat(startRelPos[1])), map.pos.wz +% @as(i32, @intFromFloat(startRelPos[2])), false, undefined, false).caveRadiusFactor;
	const endRadiusFactor = biomeMap.getRoughBiome(map.pos.wx +% @as(i32, @intFromFloat(endRelPos[0])), map.pos.wy +% @as(i32, @intFromFloat(endRelPos[1])), map.pos.wz +% @as(i32, @intFromFloat(endRelPos[2])), false, undefined, false).caveRadiusFactor;
	generateCaveBetween(_seed, map, startRelPos, endRelPos, bias, startRadius*startRadiusFactor, endRadius*endRadiusFactor, randomness);
}

fn generateBranchingCaveBetween(_seed: u64, map: *CaveMapFragment, biomeMap: *const InterpolatableCaveBiomeMapView, startRelPos: Vec3f, endRelPos: Vec3f, bias: Vec3f, startRadius: f32, endRadius: f32, seedPos: Vec3f, branchLength: f32, randomness: f32, isStart: bool, isEnd: bool) void {
	const distance = vec.length(startRelPos - endRelPos);
	var seed = _seed;
	random.scrambleSeed(&seed);
	if(distance < 32) {
		// No more branches below that level to avoid crowded caves.
		generateCaveBetweenAndCheckBiomeProperties(random.nextInt(u64, &seed), map, biomeMap, startRelPos, endRelPos, bias, startRadius, endRadius, randomness);
		// Small chance to branch off:
		if(!isStart and random.nextFloat(&seed) < branchChance and branchLength > 8) {
			var newEndPos = startRelPos + Vec3f{
				branchLength*random.nextFloatSigned(&seed),
				branchLength*random.nextFloatSigned(&seed),
				branchLength*random.nextFloatSigned(&seed),
			};
			const distanceToSeedPoint = vec.length(newEndPos - seedPos);
			// Reduce distance to avoid cutoffs:
			if(distanceToSeedPoint > range - chunkSize) {
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
	if(!isStart and !isEnd and distance < maxSplitLength and random.nextFloat(&seed) < splittingChance) {
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

fn considerCoordinates(wx: i32, wy: i32, wz: i32, map: *CaveMapFragment, biomeMap: *const InterpolatableCaveBiomeMapView, seed: *u64, worldSeed: u64) void {
	// Choose some in world coordinates to start generating:
	const startWorldPos = Vec3f{
		@floatFromInt(wx +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wx),
		@floatFromInt(wy +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wy),
		@floatFromInt(wz +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wz),
	};

	// At z = caveHeightWithMaxDensity blocks the chance is saturated, while at maxCaveHeight the chance gets 0:
	if(random.nextFloat(seed) >= maxCaveDensity*@min(1, @as(f32, @floatFromInt(maxCaveHeight -% wz))/(maxCaveHeight - caveHeightWithMaxDensity))) return;

	var starters = 1 + random.nextIntBounded(u8, seed, 4);
	while(starters != 0) : (starters -= 1) {
		const endX = wx +% random.nextIntBounded(u31, seed, 2*range - 3*chunkSize) -% range +% chunkSize & ~@as(i32, chunkSize - 1);
		const endY = wy +% random.nextIntBounded(u31, seed, 2*range - 3*chunkSize) -% range +% chunkSize & ~@as(i32, chunkSize - 1);
		const endZ = wz +% random.nextIntBounded(u31, seed, 2*range - 3*chunkSize) -% range +% chunkSize & ~@as(i32, chunkSize - 1);
		seed.* = random.initSeed3D(worldSeed, .{endX, endY, endZ}); // Every chunk has the same start/destination position, to increase cave connectivity.
		const endWorldPos = Vec3f{
			@floatFromInt(endX +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wx),
			@floatFromInt(endY +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wy),
			@floatFromInt(endZ +% random.nextIntBounded(u8, seed, chunkSize) -% map.pos.wz),
		};
		const startRadius: f32 = random.nextFloat(seed)*maxInitialRadius + 2*minRadius;
		const endRadius: f32 = random.nextFloat(seed)*maxInitialRadius + 2*minRadius;
		const caveLength = vec.length(startWorldPos - endWorldPos);
		generateBranchingCaveBetween(random.nextInt(u64, seed), map, biomeMap, startWorldPos, endWorldPos, Vec3f{
			caveLength*random.nextFloatSigned(seed)/2,
			caveLength*random.nextFloatSigned(seed)/2,
			caveLength*random.nextFloatSigned(seed)/4,
		}, startRadius, endRadius, @floatFromInt(Vec3i{wx -% map.pos.wx, wy -% map.pos.wy, wz -% map.pos.wz}), initialBranchLength, 0.1, true, true);
	}
}
