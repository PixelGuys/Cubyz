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

pub const id = "cubyz:mapgen_v1";

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

/// Assumes the 2 points are at tᵢ = (0, 1)
fn interpolationWeights(t: f32, interpolation: terrain.biomes.Interpolation) Vec2f {
	switch(interpolation) {
		.none => {
			if(t < 0.5) {
				return .{1, 0};
			} else {
				return .{0, 1};
			}
		},
		.linear => {
			return .{1 - t, t};
		},
		.square => {
			if(t < 0.5) {
				const tSqr = 2*t*t;
				return .{1 - tSqr, tSqr};
			} else {
				const tSqr = 2*(1 - t)*(1 - t);
				return .{tSqr, 1 - tSqr};
			}
		},
	}
}

pub fn generateMapFragment(map: *MapFragment, worldSeed: u64) void {
	const scaledSize = MapFragment.mapSize;
	const mapSize = scaledSize*map.pos.voxelSize;
	const biomeSize = MapFragment.biomeSize;
	const offset = 32;
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
	while(x < map.heightMap.len) : (x += 1) {
		var y: u31 = 0;
		while(y < map.heightMap.len) : (y += 1) {
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
			const xBiome: i32 = @as(i32, @intFromFloat(@floor(rawXBiome))) + offset;
			const yBiome: i32 = @as(i32, @intFromFloat(@floor(rawYBiome))) + offset;
			const relXBiome = rawXBiome - @floor(rawXBiome);
			const relYBiome = rawYBiome - @floor(rawYBiome);
			const interpolationCoefficientsX = interpolationWeights(relXBiome, .square);
			const interpolationCoefficientsY = interpolationWeights(relYBiome, .square);
			var coefficientsX: vec.Vec2f = .{0, 0};
			var coefficientsY: vec.Vec2f = .{0, 0};
			var totalWeight: f32 = 0;
			for(0..2) |dx| {
				for(0..2) |dy| {
					const biomeMapX = @as(usize, @intCast(xBiome)) + dx;
					const biomeMapY = @as(usize, @intCast(yBiome)) + dy;
					const biomeSample = biomePositions.get(biomeMapX, biomeMapY);
					const weight = @as([2]f32, interpolationCoefficientsX)[dx]*@as([2]f32, interpolationCoefficientsY)[dy]*biomeSample.biome.interpolationWeight;
					coefficientsX += interpolationWeights(relXBiome, biomeSample.biome.interpolation)*@as(Vec2f, @splat(weight));
					coefficientsY += interpolationWeights(relYBiome, biomeSample.biome.interpolation)*@as(Vec2f, @splat(weight));
					totalWeight += weight;
				}
			}
			coefficientsX /= @splat(totalWeight);
			coefficientsY /= @splat(totalWeight);
			for(0..2) |dx| {
				for(0..2) |dy| {
					const biomeMapX = @as(usize, @intCast(xBiome)) + dx;
					const biomeMapY = @as(usize, @intCast(yBiome)) + dy;
					const weight = @as([2]f32, coefficientsX)[dx]*@as([2]f32, coefficientsY)[dy];
					const biomeSample = biomePositions.get(biomeMapX, biomeMapY);
					height += biomeSample.height*weight;
					roughness += biomeSample.roughness*weight;
					hills += biomeSample.hills*weight;
					mountains += biomeSample.mountains*weight;
				}
			}
			height += (roughMap.get(x, y) - 0.5)*2*roughness;
			height += (hillMap.get(x, y) - 0.5)*2*hills;
			height += (mountainMap.get(x, y) - 0.5)*2*mountains;
			map.heightMap[x][y] = @intFromFloat(height);
			map.minHeight = @min(map.minHeight, @as(i32, @intFromFloat(height)));
			map.minHeight = @max(map.minHeight, 0);
			map.maxHeight = @max(map.maxHeight, @as(i32, @intFromFloat(height)));

			// Select a biome. Also adding some white noise to make a smoother transition.
			const roundedXBiome = @as(i32, @intFromFloat(@round(rawXBiome))) + offset;
			const roundedYBiome = @as(i32, @intFromFloat(@round(rawYBiome))) + offset;
			const biomePoint = biomePositions.get(@intCast(roundedXBiome), @intCast(roundedYBiome));
			map.biomeMap[x][y] = biomePoint.biome;
		}
	}
}
