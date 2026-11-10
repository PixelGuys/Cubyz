const std = @import("std");

const main = @import("main");
const Array2D = main.utils.Array2D;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const MapFragment = terrain.SurfaceMap.MapFragment;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec2i = vec.Vec2i;

pub const id = "cubyz:mapgen_v1";

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

fn interpolationWeights(bary: [3]f32, interpolation: terrain.biomes.Interpolation) [3]f32 {
	switch (interpolation) {
		.none => {
			if (bary[0] > bary[1]) {
				if (bary[0] > bary[2]) return .{1, 0, 0};
			} else {
				if (bary[1] > bary[2]) return .{0, 1, 0};
			}
			return .{0, 0, 1};
		},
		.linear => {
			return bary;
		},
		.square => {
			var result: [3]f32 = undefined;
			var total: f32 = 0;
			for (0..3) |i| {
				result[i] = bary[i]*bary[i];
				total += bary[i]*bary[i];
			}
			for (0..3) |i| {
				result[i] /= total;
			}
			return result;
		},
	}
}

fn getNearestNeighborsInHexGrid(in: Vec2f) [3]Vec2i {
	var gridNearest: Vec2i = @round(in);
	var offset = in - @as(Vec2f, @floatFromInt(gridNearest));
	if (@mod(gridNearest[0], 2) == 1) {
		gridNearest[1] = @round(in[1] - 0.5);
		offset[1] = in[1] - 0.5 - @as(f32, @floatFromInt(gridNearest[1]));
	}

	var result: [3]Vec2i = undefined;
	result[0] = gridNearest;

	if (offset[0] < 0) {
		result[1][0] = gridNearest[0] - 1;
	} else {
		result[1][0] = gridNearest[0] + 1;
	}
	if (@abs(offset[0]) < 2*@abs(offset[1])) { // We got two from the same y row
		result[1][1] = @round(in[1] - @as(f32, if (@mod(result[1][0], 2) == 1) 0.5 else 0));
		result[2] = gridNearest + Vec2i{0, if (offset[1] < 0) -1 else 1};
	} else { // We got two from the other y row
		result[1][1] = @round(in[1] - @as(f32, if (@mod(result[1][0], 2) == 1) 0.5 else 0));
		const offset2 = in[1] - @as(f32, if (@mod(result[1][0], 2) == 1) 0.5 else 0) - @as(f32, @floatFromInt(result[1][1]));
		result[2] = result[1] + Vec2i{0, if (offset2 < 0) -1 else 1};
	}

	return result;
}

fn computeBarycentricCoordinates(in: [3]Vec2i, pos: Vec2f) [3]f32 {
	var real: [3]Vec2f = undefined;
	for (in, 0..) |point, i| {
		real[i] = @floatFromInt(point);
		if (@mod(point[0], 2) == 1) real[i][1] += 0.5;
	}
	// taken from https://gamedev.stackexchange.com/a/23745
	const v0 = real[1] - real[0];
	const v1 = real[2] - real[0];
	const v2 = pos - real[0];
	const d00 = vec.dot(v0, v0);
	const d01 = vec.dot(v0, v1);
	const d11 = vec.dot(v1, v1);
	const d20 = vec.dot(v2, v0);
	const d21 = vec.dot(v2, v1);
	const denom = d00*d11 - d01*d01;
	var result: [3]f32 = undefined;
	result[1] = (d11*d20 - d01*d21)/denom;
	result[2] = (d00*d21 - d01*d20)/denom;
	result[0] = 1.0 - result[1] - result[2];
	return result;
}

pub fn generateMapFragment(map: *MapFragment, worldSeed: u64) void {
	const scaledSize = MapFragment.mapSize;
	const mapSize = scaledSize*map.pos.voxelSize;
	const biomeSize = MapFragment.biomeSize;
	const offset = 32;
	std.debug.assert(offset%2 == 0);
	const biomePositions = terrain.ClimateMap.getBiomeMap(main.stackAllocator, map.pos.wx -% offset*biomeSize, map.pos.wy -% offset*biomeSize, mapSize + 2*offset*biomeSize, mapSize + 2*offset*biomeSize);
	defer biomePositions.deinit(main.stackAllocator);
	var seed = random.initSeed2D(worldSeed, .{map.pos.wx, map.pos.wy});
	random.scrambleSeed(&seed);
	seed ^= seed >> 16;

	const offsetScale = biomeSize*16;
	const xOffsetMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer xOffsetMap.deinit(main.stackAllocator);
	const yOffsetMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer yOffsetMap.deinit(main.stackAllocator);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, offsetScale, worldSeed ^ 675396758496549, xOffsetMap, map.pos.voxelSize);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, offsetScale, worldSeed ^ 543864367373859, yOffsetMap, map.pos.voxelSize);

	// A ridgid noise map to generate interesting mountains.
	const mountainMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer mountainMap.deinit(main.stackAllocator);
	RandomlyWeightedFractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, 256, worldSeed ^ 6758947592930535, mountainMap, map.pos.voxelSize);

	// A smooth map for smaller hills.
	const hillMap = PerlinNoise.generateSmoothNoise(main.stackAllocator, map.pos.wx, map.pos.wy, mapSize, mapSize, 128, 32, worldSeed ^ 157839765839495820, map.pos.voxelSize, 0.5);
	defer hillMap.deinit(main.stackAllocator);

	// A fractal map to generate high-detail roughness.
	const roughMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer roughMap.deinit(main.stackAllocator);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, 64, worldSeed ^ 954936678493, roughMap, map.pos.voxelSize);

	var x: u31 = 0;
	while (x < map.heightMap.len) : (x += 1) {
		var y: u31 = 0;
		while (y < map.heightMap.len) : (y += 1) {
			// Do the biome interpolation:
			var height: f32 = 0;
			var roughness: f32 = 0;
			var hills: f32 = 0;
			var mountains: f32 = 0;
			const wx: f32 = @floatFromInt(x*map.pos.voxelSize + map.pos.wx);
			const wy: f32 = @floatFromInt(y*map.pos.voxelSize + map.pos.wy);
			const offsetX = (xOffsetMap.get(x, y) - 0.5)*offsetScale;
			const offsetY = (yOffsetMap.get(x, y) - 0.5)*offsetScale;
			const updatedX = wx + offsetX;
			const updatedY = wy + offsetY;
			const rawXBiome = (updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize;
			const rawYBiome = (updatedY - @as(f32, @floatFromInt(map.pos.wy)))/biomeSize;

			const points = getNearestNeighborsInHexGrid(.{rawXBiome, rawYBiome});
			const barycentricCoordinates: [3]f32 = computeBarycentricCoordinates(points, .{rawXBiome, rawYBiome});
			var weights: [3]f32 = @splat(0);
			var totalWeight: f32 = 0;
			for (points, 0..) |point, i| {
				const biomeSample = biomePositions.get(@intCast(point[0] + offset), @intCast(point[1] + offset));
				const weight = biomeSample.biome.interpolationWeight*barycentricCoordinates[i];
				for (interpolationWeights(barycentricCoordinates, biomeSample.biome.interpolation), 0..) |interp, j| {
					weights[j] += interp*weight;
				}
				totalWeight += weight;
			}

			for (points, 0..) |point, i| {
				const weight = weights[i]/totalWeight;
				const biomeSample = biomePositions.get(@intCast(point[0] + offset), @intCast(point[1] + offset));
				height += biomeSample.height*weight;
				roughness += biomeSample.roughness*weight;
				hills += biomeSample.hills*weight;
				mountains += biomeSample.mountains*weight;
			}
			height += (roughMap.get(x, y) - 0.5)*2*roughness;
			height += (hillMap.get(x, y) - 0.5)*2*hills;
			height += (mountainMap.get(x, y) - 0.5)*2*mountains;
			map.heightMap[x][y] = @trunc(height);
			map.minHeight = @min(map.minHeight, @as(i32, @trunc(height)));
			map.minHeight = @max(map.minHeight, 0);
			map.maxHeight = @max(map.maxHeight, @as(i32, @trunc(height)));

			var closestDist: f32 = std.math.floatMax(f32);
			var closestPoint: Vec2i = undefined;
			for (points) |point| {
				var pointFloat: Vec2f = @floatFromInt(point);
				if (@mod(point[0], 2) == 1) pointFloat[1] += 0.5;
				const dist = vec.lengthSquare(pointFloat - Vec2f{rawXBiome, rawYBiome});
				if (dist < closestDist) {
					closestDist = dist;
					closestPoint = point;
				}
			}
			const biomePoint = biomePositions.get(@intCast(closestPoint[0] + offset), @intCast(closestPoint[1] + offset));
			map.biomeMap[x][y] = biomePoint.biome;
		}
	}
}
