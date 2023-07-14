const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const RandomList = main.utils.RandomList;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:fractal_cave";

pub const priority = 65536;

pub const generatorSeed = 0xb898ec9ce9d2ef37;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

const chunkShift = 5;
const chunkSize = 1 << chunkShift;
const range = 8;
const initialBranchLength = 64;
const splittingChance = 0.4;
const splitFactor = 1.0;
const ySplitReduction = 0.5; // To reduce splitting in y-direction.
const maxSplitLength = 128;
const branchChance = 0.4;
const minRadius = 2.0;
const maxInitialRadius = 5;
const heightVariance = 0.15;
const maxCaveHeight = 128;
const caveHeightWithMaxDensity = -512;
const maxCaveDensity = 1.0/32.0;

// TODO: Should probably use fixed point arithmetic to avoid crashes at the world border.

pub fn generate(map: *CaveMapFragment, worldSeed: u64) Allocator.Error!void {
	if(map.pos.voxelSize > 2) return;
	const cx = map.pos.wx >> chunkShift;
	const cy = map.pos.wy >> chunkShift;
	const cz = map.pos.wz >> chunkShift;
	// Generate caves from all nearby chunks:
	var x = cx -% range;
	while(x -% cx -% CaveMapFragment.width*map.pos.voxelSize/chunkSize -% range < 0) : (x += 1) {
		var y = cy -% range;
		while(y -% cy -% CaveMapFragment.height*map.pos.voxelSize/chunkSize -% range < 0) : (y += 1) {
			var z = cz -% range;
			while(z -% cz -% CaveMapFragment.width*map.pos.voxelSize/chunkSize -% range < 0) : (z += 1) {
				var seed: u64 = random.initSeed3D(worldSeed, .{x, y, z});
				considerCoordinates(x, y, z, map, &seed, worldSeed);
			}
		}
	}
}

fn generateSphere(seed: *u64, map: *CaveMapFragment, worldPos: Vec3d, radius: f64) void {
	const relX = worldPos[0] - @as(f64, @floatFromInt(map.pos.wx));
	const relY = worldPos[1] - @as(f64, @floatFromInt(map.pos.wy));
	const relZ = worldPos[2] - @as(f64, @floatFromInt(map.pos.wz));
	var xMin = @as(i32, @intFromFloat(relX - radius)) - 1;
	xMin = @max(xMin, 0);
	var xMax = @as(i32, @intFromFloat(relX + radius)) + 1;
	xMax = @min(xMax, CaveMapFragment.width*map.pos.voxelSize);
	var zMin = @as(i32, @intFromFloat(relZ - radius)) - 1;
	zMin = @max(zMin, 0);
	var zMax = @as(i32, @intFromFloat(relZ + radius)) + 1;
	zMax = @min(zMax, CaveMapFragment.width*map.pos.voxelSize);
	if(xMin >= xMax or zMin >= zMax or relY - radius + 1 >= @as(f64, @floatFromInt(CaveMapFragment.height*map.pos.voxelSize)) or relY + radius + 1 < 0) {
		return;
	}
	// Go through all blocks within range of the sphere center and remove them.
	var curX = xMin;
	while(curX < xMax) : (curX += map.pos.voxelSize) {
		const distToCenterX = (@as(f64, @floatFromInt(curX)) - relX)/radius;
		var curZ = zMin;
		while(curZ < zMax) : (curZ += map.pos.voxelSize) {
			const distToCenterZ = (@as(f64, @floatFromInt(curZ)) - relZ)/radius;
			const xzDistaceSquared = distToCenterX*distToCenterX + distToCenterZ*distToCenterZ;
			var yMin: i32 = @intFromFloat(relY);
			var yMax: i32 = @intFromFloat(relY);
			if(xzDistaceSquared < 0.9*0.9) {
				const yDistance = radius*@sqrt(0.9*0.9 - xzDistaceSquared);
				yMin = @intFromFloat(relY - yDistance);
				yMax = @intFromFloat(relY + yDistance);
				map.removeRange(curX, curZ, yMin, yMax); // Remove the center range in a single call.
			}
			// Add some roughness at the upper cave walls:
			var curY: i32 = yMax;
			while(curY <= CaveMapFragment.height*map.pos.voxelSize) : (curY += map.pos.voxelSize) {
				const distToCenterY = (@as(f64, @floatFromInt(curY)) - relY)/radius;
				const distToCenter = distToCenterY*distToCenterY + xzDistaceSquared;
				if(distToCenter < 1) {
					// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
					if(random.nextIntBounded(u8, seed, 6) != 0) {
						map.removeRange(curX, curZ, curY, curY + 1);
					}
				} else break;
			}
			// Add some roughness at the lower cave walls:
			curY = yMin;
			while(curY >= 0) : (curY -= map.pos.voxelSize) {
				const distToCenterY = (@as(f64, @floatFromInt(curY)) - relY)/radius;
				const distToCenter = distToCenterX*distToCenterX + distToCenterY*distToCenterY + distToCenterZ*distToCenterZ;
				if(distToCenter < 1) {
					// Add a small roughness parameter to make walls look a bit rough by filling only 5/6 of the blocks at the walls with air:
					if(random.nextIntBounded(u8, seed, 6) != 0) {
						map.removeRange(curX, curZ, curY, curY + 1);
					}
				} else break;
			}
		}
	}
}

fn generateCaveBetween(_seed: u64, map: *CaveMapFragment, startWorldPos: Vec3d, endWorldPos: Vec3d, bias: Vec3d, startRadius: f64, endRadius: f64, randomness: f64) void {
	// Check if the segment can cross this chunk:
	const maxHeight = @max(startRadius, endRadius);
	const distance = vec.length(startWorldPos - endWorldPos);
	const maxFractalShift = distance*randomness;
	const safetyInterval = maxHeight + maxFractalShift;
	const min = vec.intFromFloat(i32, @min(startWorldPos, endWorldPos) - @as(Vec3d, @splat(safetyInterval)));
	const max = vec.intFromFloat(i32, @max(startWorldPos, endWorldPos) + @as(Vec3d, @splat(safetyInterval)));
	// Only divide further if the cave may go through ther considered chunk.
	if(min[0] >= map.pos.wx +% CaveMapFragment.width*map.pos.voxelSize or max[0] < map.pos.wx) return;
	if(min[1] >= map.pos.wy +% CaveMapFragment.height*map.pos.voxelSize or max[1] < map.pos.wy) return;
	if(min[2] >= map.pos.wz +% CaveMapFragment.width*map.pos.voxelSize or max[2] < map.pos.wz) return;

	var seed = _seed;
	random.scrambleSeed(&seed);
	if(distance < @as(f64, @floatFromInt(map.pos.voxelSize))) {
		generateSphere(&seed, map, startWorldPos, startRadius);
	} else { // Otherwise go to the next fractal level:
		const mid = (startWorldPos + endWorldPos)/@as(Vec3d, @splat(2)) + @as(Vec3d, @splat(maxFractalShift))*Vec3d{
			@floatCast(random.nextFloatSigned(&seed)),
			@floatCast(random.nextFloatSigned(&seed)),
			@floatCast(random.nextFloatSigned(&seed)),
		} + bias/@as(Vec3d, @splat(4));
		var midRadius = (startRadius + endRadius)/2 + maxFractalShift*@as(f64, @floatCast(random.nextFloatSigned(&seed)))*heightVariance;
		midRadius = @max(midRadius, minRadius);
		generateCaveBetween(random.nextInt(u64, &seed), map, startWorldPos, mid, bias/@as(Vec3d, @splat(4)), startRadius, midRadius, randomness);
		generateCaveBetween(random.nextInt(u64, &seed), map, mid, endWorldPos, bias/@as(Vec3d, @splat(4)), midRadius, endRadius, randomness);
	}
}

fn generateBranchingCaveBetween(_seed: u64, map: *CaveMapFragment, startWorldPos: Vec3d, endWorldPos: Vec3d, bias: Vec3d, startRadius: f64, endRadius: f64, centerWorldPos: Vec3i, branchLength: f64, randomness: f64, isStart: bool, isEnd: bool) void {
	const distance = vec.length(startWorldPos - endWorldPos);
	var seed = _seed;
	random.scrambleSeed(&seed);
	if(distance < 32) {
		// No more branches below that level to avoid crowded caves.
		generateCaveBetween(random.nextInt(u64, &seed), map, startWorldPos, endWorldPos, bias, startRadius, endRadius, randomness);
		// Small chance to branch off:
		if(!isStart and random.nextFloat(&seed) < branchChance and branchLength > 8) {
			var newEndPos = startWorldPos + Vec3d {
				branchLength*@as(f64, @floatCast(random.nextFloatSigned(&seed))),
				branchLength*@as(f64, @floatCast(random.nextFloatSigned(&seed))),
				branchLength*@as(f64, @floatCast(random.nextFloatSigned(&seed))),
			};
			const distanceToSeedPoint = vec.length(startWorldPos - newEndPos);
			// Reduce distance to avoid cutoffs:
			if(distanceToSeedPoint > (range - 1)*chunkSize) {
				newEndPos = vec.floatFromInt(f64, centerWorldPos) + (newEndPos - vec.floatFromInt(f64, centerWorldPos))*@as(Vec3d, @splat(((range - 1)*chunkSize)/distanceToSeedPoint));
			}
			const newStartRadius = (startRadius - minRadius)*@as(f64, @floatCast(random.nextFloat(&seed))) + minRadius;
			const newBias = Vec3d {
				branchLength*@as(f64, @floatCast(random.nextFloatSigned(&seed))),
				branchLength*@as(f64, @floatCast(random.nextFloatSigned(&seed)/2)),
				branchLength*@as(f64, @floatCast(random.nextFloatSigned(&seed))),
			};
			generateBranchingCaveBetween(random.nextInt(u64, &seed), map, startWorldPos, newEndPos, newBias, newStartRadius, minRadius, centerWorldPos, branchLength/2, @min(0.5, randomness + randomness*@as(f64, @floatCast(random.nextFloat(&seed)*random.nextFloat(&seed)))), true, true);
		}
		return;
	}

	const maxFractalShift = distance*randomness;
	const weight: f64 = @floatCast(0.25 + random.nextFloat(&seed)*0.5); // Do slightly random subdivision instead of binary subdivision, to avoid regular patterns.

	const w1 = (1 - weight)*(1 - weight);
	const w2 = weight*weight;
	// Small chance to generate a split:
	if(!isStart and !isEnd and distance < maxSplitLength and random.nextFloat(&seed) < splittingChance) {
		// Find a random direction perpendicular to the current cave direction:
		var splitXZ: f64 = @floatCast(random.nextFloat(&seed) - 0.5);
		var splitY: f64 = @floatCast(ySplitReduction*(random.nextFloat(&seed) - 0.5));
		// Normalize
		const length = @sqrt(splitXZ*splitXZ + splitY*splitY);
		splitXZ /= length;
		splitY /= length;
		// Calculate bias offsets:
		const biasLength = vec.length(bias);
		const offsetY = splitY*splitFactor*distance;
		const offsetX = splitXZ*splitFactor*distance * bias[2]/biasLength;
		const offsetZ = splitXZ*splitFactor*distance * bias[0]/biasLength;

		const newBias1 = bias + Vec3d{offsetX, offsetY, offsetZ};
		const newBias2 = bias - Vec3d{offsetX, offsetY, offsetZ};

		const mid1 = startWorldPos*@as(Vec3d, @splat(weight)) + endWorldPos*@as(Vec3d, @splat(1 - weight)) + @as(Vec3d, @splat(maxFractalShift))*Vec3d{
			@floatCast(random.nextFloatSigned(&seed)),
			@floatCast(random.nextFloatSigned(&seed)),
			@floatCast(random.nextFloatSigned(&seed)),
		} + newBias1*@as(Vec3d, @splat(weight*(1 - weight)));
		const mid2 = startWorldPos*@as(Vec3d, @splat(weight)) + endWorldPos*@as(Vec3d, @splat(1 - weight)) + @as(Vec3d, @splat(maxFractalShift))*Vec3d{
			@floatCast(random.nextFloatSigned(&seed)),
			@floatCast(random.nextFloatSigned(&seed)),
			@floatCast(random.nextFloatSigned(&seed)),
		} + newBias2*@as(Vec3d, @splat(weight*(1 - weight)));

		var midRadius = @max(minRadius, (startRadius + endRadius)/2 + maxFractalShift*@as(f64, @floatCast(random.nextFloatSigned(&seed)))*heightVariance);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, startWorldPos, mid1, newBias1*@as(Vec3d, @splat(w1)), startRadius, midRadius, centerWorldPos, branchLength, randomness, isStart, false);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, mid1, endWorldPos, newBias1*@as(Vec3d, @splat(w2)), midRadius, endRadius, centerWorldPos, branchLength, randomness, false, isEnd);
		// Do some tweaking to the radius before making the second part:
		const newStartRadius = (startRadius - minRadius)*@as(f64, @floatCast(random.nextFloat(&seed))) + minRadius;
		const newEndRadius = (endRadius - minRadius)*@as(f64, @floatCast(random.nextFloat(&seed))) + minRadius;
		midRadius = @max(minRadius, (newStartRadius + newEndRadius)/2 + maxFractalShift*@as(f64, @floatCast(random.nextFloatSigned(&seed)))*heightVariance);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, startWorldPos, mid2, newBias2*@as(Vec3d, @splat(w1)), newStartRadius, midRadius, centerWorldPos, branchLength, randomness, isStart, false);
		generateBranchingCaveBetween(random.nextInt(u64, &seed), map, mid2, endWorldPos, newBias2*@as(Vec3d, @splat(w2)), midRadius, newEndRadius, centerWorldPos, branchLength, randomness, false, isEnd);
		return;
	}
	const mid = startWorldPos*@as(Vec3d, @splat(weight)) + endWorldPos*@as(Vec3d, @splat(1 - weight)) + @as(Vec3d, @splat(maxFractalShift))*Vec3d{
		@floatCast(random.nextFloatSigned(&seed)),
		@floatCast(random.nextFloatSigned(&seed)),
		@floatCast(random.nextFloatSigned(&seed)),
	} + bias*@as(Vec3d, @splat(weight*(1 - weight)));
	const midRadius = @max(minRadius, (startRadius + endRadius)/2 + maxFractalShift*@as(f64, @floatCast(random.nextFloatSigned(&seed)))*heightVariance);
	generateBranchingCaveBetween(random.nextInt(u64, &seed), map, startWorldPos, mid, bias*@as(Vec3d, @splat(w1)), startRadius, midRadius, centerWorldPos, branchLength, randomness, isStart, false);
	generateBranchingCaveBetween(random.nextInt(u64, &seed), map, mid, endWorldPos, bias*@as(Vec3d, @splat(w2)), midRadius, endRadius, centerWorldPos, branchLength, randomness, false, isEnd);

}

fn considerCoordinates(x: i32, y: i32, z: i32, map: *CaveMapFragment, seed: *u64, worldSeed: u64) void {
	// Choose some in world coordinates to start generating:
	const startWorldPos = Vec3d {
		@floatFromInt((x << chunkShift) + random.nextIntBounded(u8, seed, chunkSize)),
		@floatFromInt((y << chunkShift) + random.nextIntBounded(u8, seed, chunkSize)),
		@floatFromInt((z << chunkShift) + random.nextIntBounded(u8, seed, chunkSize)),
	};

	// At y = caveHeightWithMaxDensity blocks the chance is saturated, while at maxCaveHeight the chance gets 0:
	if(random.nextFloat(seed) >= maxCaveDensity*@min(1, @as(f32, @floatCast((maxCaveHeight - startWorldPos[1])/(maxCaveHeight - caveHeightWithMaxDensity))))) return;

	var starters = 1 + random.nextIntBounded(u8, seed, 4);
	while(starters != 0) : (starters -= 1) {
		const endX = x + random.nextIntBounded(u8, seed, 2*range - 2) - range - 1;
		const endY = y + random.nextIntBounded(u8, seed, 2*range - 2) - range - 1;
		const endZ = z + random.nextIntBounded(u8, seed, 2*range - 2) - range - 1;
		seed.* = random.initSeed3D(worldSeed, .{endX, endY, endZ}); // Every chunk has the same start/destination position, to increase cave connectivity.
		const endWorldPos = Vec3d {
			@floatFromInt((endX << chunkShift) + random.nextIntBounded(u8, seed, chunkSize)),
			@floatFromInt((endY << chunkShift) + random.nextIntBounded(u8, seed, chunkSize)),
			@floatFromInt((endZ << chunkShift) + random.nextIntBounded(u8, seed, chunkSize)),
		};
		const startRadius: f64 = @floatCast(random.nextFloat(seed)*maxInitialRadius + 2*minRadius);
		const endRadius: f64 = @floatCast(random.nextFloat(seed)*maxInitialRadius + 2*minRadius);
		const caveLength = vec.length(startWorldPos - endWorldPos);
		generateBranchingCaveBetween(random.nextInt(u64, seed), map, startWorldPos, endWorldPos, Vec3d {
			caveLength*@as(f64, @floatCast(random.nextFloatSigned(seed)/2)),
			caveLength*@as(f64, @floatCast(random.nextFloatSigned(seed)/4)),
			caveLength*@as(f64, @floatCast(random.nextFloatSigned(seed)/2)),
		}, startRadius, endRadius, Vec3i{x << chunkShift, y << chunkShift, z << chunkShift}, initialBranchLength, 0.1, true, true);
	}
}