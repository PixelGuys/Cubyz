const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub fn generateMapFragment(map: *MapFragment, worldSeed: u64) Allocator.Error!void {
	const scaledSize = MapFragment.mapSize;
	const mapSize = scaledSize*map.pos.voxelSize;
	const biomeSize = MapFragment.biomeSize;
	const biomePositions = try terrain.ClimateMap.getBiomeMap(main.threadAllocator, map.pos.wx - biomeSize, map.pos.wz - biomeSize, mapSize + 3*biomeSize, mapSize + 3*biomeSize);
	defer biomePositions.deinit(main.threadAllocator);
	var seed = worldSeed;
	random.scrambleSeed(&seed);
	seed = @bitCast(u32, (random.nextInt(i32, &seed) | 1)*%map.pos.wx ^ (random.nextInt(i32, &seed) | 1)*%map.pos.wz);
	random.scrambleSeed(&seed);
	
	const scaledBiomeSize = biomeSize/map.pos.voxelSize;
	const xOffsetMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer xOffsetMap.deinit(main.threadAllocator);
	const zOffsetMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer zOffsetMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, biomeSize/2, worldSeed ^ 675396758496549, xOffsetMap, map.pos.voxelSize);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, biomeSize/2, worldSeed ^ 543864367373859, zOffsetMap, map.pos.voxelSize);

	// A ridgid noise map to generate interesting mountains.
	const mountainMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer mountainMap.deinit(main.threadAllocator);
	try RandomlyWeightedFractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, 64, worldSeed ^ 6758947592930535, mountainMap, map.pos.voxelSize);

	// A smooth map for smaller hills.
	const hillMap = try PerlinNoise.generateSmoothNoise(main.threadAllocator, map.pos.wx, map.pos.wz, mapSize, mapSize, 128, 32, worldSeed ^ 157839765839495820, map.pos.voxelSize, 0.5);
	defer hillMap.deinit(main.threadAllocator);

	// A fractal map to generate high-detail roughness.
	const roughMap = try Array2D(f32).init(main.threadAllocator, scaledSize, scaledSize);
	defer roughMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx, map.pos.wz, 64, worldSeed ^ 954936678493, roughMap, map.pos.voxelSize);

	for(0..map.heightMap.len) |x| {
		for(0..map.heightMap.len) |z| {
			// Do the biome interpolation:
			var totalWeight: f32 = 0;
			var height: f32 = 0;
			var roughness: f32 = 0;
			var hills: f32 = 0;
			var mountains: f32 = 0;
			var xBiome = (x + scaledBiomeSize/2)/scaledBiomeSize;
			var zBiome = (z + scaledBiomeSize/2)/scaledBiomeSize;
			const wx = @intCast(i32, x)*map.pos.voxelSize + map.pos.wx;
			const wz = @intCast(i32, z)*map.pos.voxelSize + map.pos.wz;
			var hasOneWithMaxNormLT1 = false;
			var x0 = xBiome;
			while(x0 <= xBiome + 2) : (x0 += 1) {
				var z0 = zBiome;
				while(z0 <= zBiome + 2) : (z0 += 1) {
					const biomePoint = biomePositions.get(x0, z0);
					var dist = @sqrt(biomePoint.distSquare(@intToFloat(f32, wx), @intToFloat(f32, wz)));
					dist /= @intToFloat(f32, biomeSize);
					const maxNorm = biomePoint.maxNorm(@intToFloat(f32, wx), @intToFloat(f32, wz))/@intToFloat(f32, biomeSize);
					if(maxNorm < 1) hasOneWithMaxNormLT1 = true;
					// There are cases where this point is further away than 1 unit from all nearby biomes. For that case the euclidian distance function is interpolated to the max-norm for higher distances.
					if(dist > 0.9 and maxNorm < 1) {
						if(dist < 1) { // interpolate to the maxNorm:
							dist = (1 - dist)/(1 - 0.9)*dist + (dist - 0.9)/(1 - 0.9)*maxNorm;
						} else {
							dist = maxNorm;
						}
						std.debug.assert(dist < 1);
					}
					if(dist <= 1) {
						var weight = 1 - dist;
						// smooth the interpolation with the s-curve:
						weight = weight*weight*(3 - 2*weight);
						height += biomePoint.height*weight;
						roughness += biomePoint.biome.roughness*weight;
						hills += biomePoint.biome.hills*weight;
						mountains += biomePoint.biome.mountains*weight;
						totalWeight += weight;
					}
				}
			}
			if(!hasOneWithMaxNormLT1) {
				x0 = xBiome;
				while(x0 <= xBiome + 2) : (x0 += 1) {
					var z0 = zBiome;
					while(z0 <= zBiome + 2) : (z0 += 1) {
						const biomePoint = biomePositions.get(x0, z0);
						var dist = @sqrt(biomePoint.distSquare(@intToFloat(f32, wx), @intToFloat(f32, wz)));
						dist /= @intToFloat(f32, biomeSize);
						const maxNorm = biomePoint.maxNorm(@intToFloat(f32, wx), @intToFloat(f32, wz))/@intToFloat(f32, biomeSize);
						std.log.info("{}, {} | {}, {} : {} {}", .{biomePoint.x, biomePoint.z, wx, wz, dist, maxNorm});
					}
				}
			}
			// Norm the result:
			std.debug.assert(hasOneWithMaxNormLT1);
			std.debug.assert(totalWeight != 0);
			height /= totalWeight;
			roughness /= totalWeight;
			hills /= totalWeight;
			mountains /= totalWeight;
			height += (roughMap.get(x, z) - 0.5)*2*roughness;
			height += (hillMap.get(x, z) - 0.5)*2*hills;
			height += (mountainMap.get(x, z) - 0.5)*2*mountains;
			map.heightMap[x][z] = height;
			map.minHeight = @min(map.minHeight, @floatToInt(i32, height));
			map.minHeight = @max(map.minHeight, 0);
			map.maxHeight = @max(map.maxHeight, @floatToInt(i32, height));


			// Select a biome. The shape of the biome is randomized by applying noise (fractal noise and white noise) to the coordinates.
			const updatedX = @intToFloat(f32, wx) + (@intToFloat(f32, random.nextInt(u3, &seed)) - 3.5)*@intToFloat(f32, biomeSize)/128 + (xOffsetMap.get(x, z) - 0.5)*biomeSize/2;
			const updatedZ = @intToFloat(f32, wz) + (@intToFloat(f32, random.nextInt(u3, &seed)) - 3.5)*@intToFloat(f32, biomeSize)/128 + (zOffsetMap.get(x, z) - 0.5)*biomeSize/2;
			xBiome = @floatToInt(usize, ((updatedX - @intToFloat(f32, map.pos.wx))/@intToFloat(f32, map.pos.voxelSize) + @intToFloat(f32, scaledBiomeSize/2))/@intToFloat(f32, scaledBiomeSize));
			zBiome = @floatToInt(usize, ((updatedZ - @intToFloat(f32, map.pos.wz))/@intToFloat(f32, map.pos.voxelSize) + @intToFloat(f32, scaledBiomeSize/2))/@intToFloat(f32, scaledBiomeSize));
			var shortestDist: f32 = std.math.floatMax(f32);
			var shortestBiomePoint: terrain.ClimateMap.BiomePoint = undefined;
			x0 = xBiome;
			while(x0 <= xBiome + 2) : (x0 += 1) {
				var z0 = zBiome;
				while(z0 <= zBiome + 2) : (z0 += 1) {
					const distSquare = biomePositions.get(x0, z0).distSquare(updatedX, updatedZ);
					if(distSquare < shortestDist) {
						shortestDist = distSquare;
						shortestBiomePoint = biomePositions.get(x0, z0);
					}
				}
			}
			map.biomeMap[x][z] = shortestBiomePoint.getFittingReplacement(@floatToInt(i32, height + random.nextFloat(&seed)*4 - 2));
		}
	}
}