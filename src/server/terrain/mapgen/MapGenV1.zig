const std = @import("std");

const main = @import("root");
const Array2D = main.utils.Array2D;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const MapFragment = terrain.SurfaceMap.MapFragment;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;

pub const id = "cubyz:mapgen_v1";

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

/// Assumes the 2 points are at tᵢ = (0, 1)
fn interpolationWeights(t: f32, interpolation: terrain.biomes.Interpolation) [2]f32 {
	switch (interpolation) {
		.none => {
			if(t < 0.5) {
				return [2]f32 {1, 0};
			} else {
				return [2]f32 {0, 1};
			}
		},
		.linear => {
			return [2]f32 {1 - t, t};
		},
		.square => {
			if(t < 0.5) {
				const tSqr = 2*t*t;
				return [2]f32 {1 - tSqr, tSqr};
			} else {
				const tSqr = 2*(1 - t)*(1 - t);
				return [2]f32 {tSqr, 1 - tSqr};
			}
		},
	}
}

pub fn generateMapFragment(map: *MapFragment, worldSeed: u64) void {
	const scaledSize = MapFragment.mapSize;
	const mapSize = scaledSize*map.pos.voxelSize;
	const biomeSize = MapFragment.biomeSize;
	const offset = 8;
	const biomePositions = terrain.ClimateMap.getBiomeMap(main.stackAllocator, map.pos.wx -% offset*biomeSize, map.pos.wy -% offset*biomeSize, mapSize + 2*offset*biomeSize, mapSize + 2*offset*biomeSize);
	defer biomePositions.deinit(main.stackAllocator);
	var seed = random.initSeed2D(worldSeed, .{map.pos.wx, map.pos.wy});
	random.scrambleSeed(&seed);
	seed ^= seed >> 16;
	
	const xOffsetMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer xOffsetMap.deinit(main.stackAllocator);
	const yOffsetMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer yOffsetMap.deinit(main.stackAllocator);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, biomeSize*4, worldSeed ^ 675396758496549, xOffsetMap, map.pos.voxelSize);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, biomeSize*4, worldSeed ^ 543864367373859, yOffsetMap, map.pos.voxelSize);

	// A ridgid noise map to generate interesting mountains.
	const mountainMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer mountainMap.deinit(main.stackAllocator);
	RandomlyWeightedFractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wy, 256, worldSeed ^ 6758947592930535, mountainMap, map.pos.voxelSize);

	// A smooth map for smaller hills.
	const hillMap = PerlinNoise.generateSmoothNoise(main.globalAllocator, map.pos.wx, map.pos.wy, mapSize, mapSize, 128, 32, worldSeed ^ 157839765839495820, map.pos.voxelSize, 0.5);
	defer hillMap.deinit(main.globalAllocator);

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
			const offsetX = (xOffsetMap.get(x, y) - 0.5)*biomeSize*4;
			const offsetY = (yOffsetMap.get(x, y) - 0.5)*biomeSize*4;
			var updatedX = wx + offsetX;
			var updatedY = wy + offsetY;
			var xBiome: i32 = @intFromFloat(@floor((updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize));
			var yBiome: i32 = @intFromFloat(@floor((updatedY - @as(f32, @floatFromInt(map.pos.wy)))/biomeSize));
			const relXBiome = (0.5 + offsetX + @as(f32, @floatFromInt(x*map.pos.voxelSize -% xBiome*biomeSize)))/biomeSize;
			xBiome += offset;
			const relYBiome = (0.5 + offsetY + @as(f32, @floatFromInt(y*map.pos.voxelSize -% yBiome*biomeSize)))/biomeSize;
			yBiome += offset;
			var closestBiome: *const terrain.biomes.Biome = undefined;
			if(relXBiome < 0.5) {
				if(relYBiome < 0.5) {
					closestBiome = biomePositions.get(@intCast(xBiome), @intCast(yBiome)).biome;
				} else {
					closestBiome = biomePositions.get(@intCast(xBiome), @intCast(yBiome + 1)).biome;
				}
			} else {
				if(relYBiome < 0.5) {
					closestBiome = biomePositions.get(@intCast(xBiome + 1), @intCast(yBiome)).biome;
				} else {
					closestBiome = biomePositions.get(@intCast(xBiome + 1), @intCast(yBiome + 1)).biome;
				}
			}
			const coefficientsX = interpolationWeights(relXBiome, closestBiome.interpolation);
			const coefficientsY = interpolationWeights(relYBiome, closestBiome.interpolation);
			for(0..2) |dx| {
				for(0..2) |dy| {
					const biomeMapX = @as(usize, @intCast(xBiome)) + dx;
					const biomeMapY = @as(usize, @intCast(yBiome)) + dy;
					const weight = coefficientsX[dx]*coefficientsY[dy];
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
			updatedX += random.nextFloatSigned(&seed)*3.5*biomeSize/32;
			updatedY += random.nextFloatSigned(&seed)*3.5*biomeSize/32;
			xBiome = @intFromFloat(@round((updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize));
			xBiome += offset;
			yBiome = @intFromFloat(@round((updatedY - @as(f32, @floatFromInt(map.pos.wy)))/biomeSize));
			yBiome += offset;
			const biomePoint = biomePositions.get(@intCast(xBiome), @intCast(yBiome));
			map.biomeMap[x][y] = biomePoint.biome;
		}
	}
}