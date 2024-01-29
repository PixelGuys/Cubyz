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
	const biomePositions = terrain.ClimateMap.getBiomeMap(main.stackAllocator, map.pos.wx - offset*biomeSize, map.pos.wz - offset*biomeSize, mapSize + 2*offset*biomeSize, mapSize + 2*offset*biomeSize);
	defer biomePositions.deinit(main.stackAllocator);
	var seed = random.initSeed2D(worldSeed, .{map.pos.wx, map.pos.wz});
	random.scrambleSeed(&seed);
	seed ^= seed >> 16;
	
	const xOffsetMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer xOffsetMap.deinit(main.stackAllocator);
	const zOffsetMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer zOffsetMap.deinit(main.stackAllocator);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, biomeSize*4, worldSeed ^ 675396758496549, xOffsetMap, map.pos.voxelSize);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, biomeSize*4, worldSeed ^ 543864367373859, zOffsetMap, map.pos.voxelSize);

	// A ridgid noise map to generate interesting mountains.
	const mountainMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer mountainMap.deinit(main.stackAllocator);
	RandomlyWeightedFractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, 64, worldSeed ^ 6758947592930535, mountainMap, map.pos.voxelSize);

	// A smooth map for smaller hills.
	const hillMap = PerlinNoise.generateSmoothNoise(main.globalAllocator, map.pos.wx, map.pos.wz, mapSize, mapSize, 128, 32, worldSeed ^ 157839765839495820, map.pos.voxelSize, 0.5);
	defer hillMap.deinit(main.globalAllocator);

	// A fractal map to generate high-detail roughness.
	const roughMap = Array2D(f32).init(main.stackAllocator, scaledSize, scaledSize);
	defer roughMap.deinit(main.stackAllocator);
	FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, 64, worldSeed ^ 954936678493, roughMap, map.pos.voxelSize);

	var x: u31 = 0;
	while(x < map.heightMap.len) : (x += 1) {
		var z: u31 = 0;
		while(z < map.heightMap.len) : (z += 1) {
			// Do the biome interpolation:
			var height: f32 = 0;
			var roughness: f32 = 0;
			var hills: f32 = 0;
			var mountains: f32 = 0;
			const wx: f32 = @floatFromInt(x*map.pos.voxelSize + map.pos.wx);
			const wz: f32 = @floatFromInt(z*map.pos.voxelSize + map.pos.wz);
			var updatedX = wx + (xOffsetMap.get(x, z) - 0.5)*biomeSize*4;
			var updatedZ = wz + (zOffsetMap.get(x, z) - 0.5)*biomeSize*4;
			var xBiome: i32 = @intFromFloat(@floor((updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize));
			var zBiome: i32 = @intFromFloat(@floor((updatedZ - @as(f32, @floatFromInt(map.pos.wz)))/biomeSize));
			const relXBiome = (0.5 + updatedX - @as(f32, @floatFromInt(map.pos.wx +% xBiome*biomeSize)))/biomeSize;
			xBiome += offset;
			const relZBiome = (0.5 + updatedZ - @as(f32, @floatFromInt(map.pos.wz +% zBiome*biomeSize)))/biomeSize;
			zBiome += offset;
			var closestBiome: *const terrain.biomes.Biome = undefined;
			if(relXBiome < 0.5) {
				if(relZBiome < 0.5) {
					closestBiome = biomePositions.get(@intCast(xBiome), @intCast(zBiome)).biome;
				} else {
					closestBiome = biomePositions.get(@intCast(xBiome), @intCast(zBiome + 1)).biome;
				}
			} else {
				if(relZBiome < 0.5) {
					closestBiome = biomePositions.get(@intCast(xBiome + 1), @intCast(zBiome)).biome;
				} else {
					closestBiome = biomePositions.get(@intCast(xBiome + 1), @intCast(zBiome + 1)).biome;
				}
			}
			const coefficientsX = interpolationWeights(relXBiome, closestBiome.interpolation);
			const coefficientsZ = interpolationWeights(relZBiome, closestBiome.interpolation);
			for(0..2) |dx| {
				for(0..2) |dz| {
					const biomeMapX = @as(usize, @intCast(xBiome)) + dx;
					const biomeMapZ = @as(usize, @intCast(zBiome)) + dz;
					const weight = coefficientsX[dx]*coefficientsZ[dz];
					const biomeSample = biomePositions.get(biomeMapX, biomeMapZ);
					height += biomeSample.height*weight;
					roughness += biomeSample.roughness*weight;
					hills += biomeSample.hills*weight;
					mountains += biomeSample.mountains*weight;
				}
			}
			height += (roughMap.get(x, z) - 0.5)*2*roughness;
			height += (hillMap.get(x, z) - 0.5)*2*hills;
			height += (mountainMap.get(x, z) - 0.5)*2*mountains;
			map.heightMap[x][z] = height;
			map.minHeight = @min(map.minHeight, height);
			map.minHeight = @max(map.minHeight, 0);
			map.maxHeight = @max(map.maxHeight, height);


			// Select a biome. Also adding some white noise to make a smoother transition.
			updatedX += random.nextFloatSigned(&seed)*3.5*biomeSize/32;
			updatedZ += random.nextFloatSigned(&seed)*3.5*biomeSize/32;
			xBiome = @intFromFloat(@round((updatedX - @as(f32, @floatFromInt(map.pos.wx)))/biomeSize));
			xBiome += offset;
			zBiome = @intFromFloat(@round((updatedZ - @as(f32, @floatFromInt(map.pos.wz)))/biomeSize));
			zBiome += offset;
			const biomePoint = biomePositions.get(@intCast(xBiome), @intCast(zBiome));
			map.biomeMap[x][z] = biomePoint.biome;
		}
	}
}