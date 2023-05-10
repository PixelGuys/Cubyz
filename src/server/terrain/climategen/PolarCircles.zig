const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const ClimateMapFragment = terrain.ClimateMap.ClimateMapFragment;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;
const Biome = terrain.biomes.Biome;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:polar_circles";

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

// Constants that define how the climate map is generated. TODO: Change these depending on the world.
const oceanThreshold: f32 = 0.5;
const mountainRatio: f32 = 0.8;
const mountainPower: f32 = 3;
const icePoint: f32 = -0.5;
const frostPoint: f32 = -0.35;
const hotPoint: f32 = 0.5;
const dryPoint: f32 = 0.35;
const wetPoint: f32 = 0.65;

const ringSize: f32 = 64;
const windSpeed: f32 = 1;
const windInfluence: f32 = 0.1;

pub fn generateMapFragment(map: *ClimateMapFragment, worldSeed: u64) Allocator.Error!void {
	const mapSize = ClimateMapFragment.mapSize;
	const biomeSize = terrain.SurfaceMap.MapFragment.biomeSize;
	// Create the surrounding height and wind maps needed for wind propagation:
	const heightMap = try Array2D(f32).init(main.threadAllocator, 3*mapSize/biomeSize, 3*mapSize/biomeSize);
	defer heightMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx -% mapSize, map.pos.wz -% mapSize, mapSize/16, worldSeed ^ 92786504683290654, heightMap, biomeSize);

	const windXMap = try Array2D(f32).init(main.threadAllocator, 3*mapSize/biomeSize, 3*mapSize/biomeSize);
	defer windXMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx -% mapSize, map.pos.wz -% mapSize, mapSize/8, worldSeed ^ 4382905640235972, windXMap, biomeSize);

	const windZMap = try Array2D(f32).init(main.threadAllocator, 3*mapSize/biomeSize, 3*mapSize/biomeSize);
	defer windZMap.deinit(main.threadAllocator);
	try FractalNoise.generateSparseFractalTerrain(map.pos.wx -% mapSize, map.pos.wz -% mapSize, mapSize/8, worldSeed ^ 532985472894530, windZMap, biomeSize);

	// Make non-ocean regions more flat:
	for(heightMap.mem) |*height| {
		if(height.* >= oceanThreshold) {
			height.* = oceanThreshold + (1 - oceanThreshold)*std.math.pow(f32, (height.* - oceanThreshold)/(1 - oceanThreshold), mountainPower);
		}
	}

	// Calculate the temperature and humidty for each point on the map. This is done by backtracing along the wind.
	// On mountains the water will often rain down, so wind that goes through a mountain will carry less.
	// Oceans carry water, so if the wind went through an ocean it picks up water.
	
	// Alongside that there is also an initial temperature and humidity distribution that mimics the earth.
	// How is that possible? Isn't Cubyz flat?
	// On the earth there are just two arctic poles. Cubyz takes the north pole and places it at (0, 0).
	// Then there are infinite poles with ring shapes and each ring will have an equal distance to the previous one.
	// That's not perfectly realistic, but it's ok in the sense that following a compass will lead to one arctic
	// and away from another.
	var biomeMap: [mapSize/biomeSize + 2][mapSize/biomeSize + 2]*const Biome = undefined;

	var x: i32 = -1;
	while(x < mapSize/biomeSize + 1) : (x += 1) {
		var z: i32 = -1;
		while(z < mapSize/biomeSize + 1) : (z += 1) {
			var seed: u64 = @intCast(u64, @bitCast(u32, x +% map.pos.wx))*%65784967549 +% @intCast(u64, @bitCast(u32, z +% map.pos.wz))*%6758934659 +% worldSeed;
			random.scrambleSeed(&seed);
			const xOffset = random.nextFloat(&seed) - 0.5;
			const zOffset = random.nextFloat(&seed) - 0.5;
			var humid = getInitialHumidity(map, @intToFloat(f32, x), @intToFloat(f32, z), heightMap.get(@intCast(usize, x + mapSize/biomeSize), @intCast(usize, z + mapSize/biomeSize)));
			var temp = getInitialTemperature(map, @intToFloat(f32, x), @intToFloat(f32, z), heightMap.get(@intCast(usize, x + mapSize/biomeSize), @intCast(usize, z + mapSize/biomeSize)));
			var humidInfluence = windInfluence;
			var tempInfluence = windInfluence;
			var nextX = @intToFloat(f32, x) + xOffset;
			var nextZ = @intToFloat(f32, z) + zOffset;
			for(0..50) |_| {
				const windX = windXMap.get(@intCast(usize, @floatToInt(i32, nextX) + mapSize/biomeSize), @intCast(usize, @floatToInt(i32, nextZ) + mapSize/biomeSize));
				const windZ = windZMap.get(@intCast(usize, @floatToInt(i32, nextX) + mapSize/biomeSize), @intCast(usize, @floatToInt(i32, nextZ) + mapSize/biomeSize));
				nextX += windX*windSpeed;
				nextZ += windZ*windSpeed;
				// Make sure the bounds are ok:
				if(nextX < -@intToFloat(f32, mapSize/biomeSize) or nextX > 2*@intToFloat(f32, mapSize/biomeSize) - 1) break;
				if(nextZ < -@intToFloat(f32, mapSize/biomeSize) or nextZ > 2*@intToFloat(f32, mapSize/biomeSize) - 1) break;
				// Find the local temperature and humidity:
				const localHeight = heightMap.get(@intCast(usize, @floatToInt(i32, nextX) + mapSize/biomeSize), @intCast(usize, @floatToInt(i32, nextZ) + mapSize/biomeSize));
				const localTemp =  getInitialTemperature(map, nextX, nextZ, localHeight);
				const localHumid =  getInitialHumidity(map, nextX, nextZ, localHeight);
				humid = (1 - humidInfluence)*humid + humidInfluence*localHumid;
				temp = (1 - tempInfluence)*temp + tempInfluence*localTemp;
				tempInfluence *= 0.9; // Distance reduction
				humidInfluence *= 0.9; // Distance reduction
				// Reduction from mountains:
				humidInfluence *= std.math.pow(f32, 1 - localHeight, 0.05);
			}
			// Insert the biome type:
			const typ = findClimate(heightMap.get(@intCast(usize, x + mapSize/biomeSize), @intCast(usize, z + mapSize/biomeSize)), humid, temp);
			biomeMap[@intCast(usize, x + 1)][@intCast(usize, z + 1)] = terrain.biomes.getRandomly(typ, &seed);
		}
	}
	x = 0;
	while(x < mapSize/biomeSize) : (x += 1) {
		var z: i32 = 0;
		while(z < mapSize/biomeSize) : (z += 1) {
			const biome = biomeMap[@intCast(usize, x + 1)][@intCast(usize, z + 1)];
			var maxMinHeight: i32 = std.math.minInt(i32);
			var minMaxHeight: i32 = std.math.maxInt(i32);
			var dx: i32 = -1;
			while(dx <= 1) : (dx += 1) {
				var dz: i32 = -1;
				while(dz <= 1) : (dz += 1) {
					maxMinHeight = @max(maxMinHeight, biomeMap[@intCast(usize, x + dx + 1)][@intCast(usize, z + dz + 1)].minHeight);
					minMaxHeight = @min(minMaxHeight, biomeMap[@intCast(usize, x + dx + 1)][@intCast(usize, z + dz + 1)].maxHeight);
				}
			}
			var seed: u64 = @intCast(u64, @bitCast(u32, x +% map.pos.wx))*%675893674893 +% @intCast(u64, @bitCast(u32, z +% map.pos.wz))*%2895478591 +% worldSeed;
			const xOffset = random.nextFloat(&seed) - 0.5;
			const zOffset = random.nextFloat(&seed) - 0.5;
			var height = random.nextFloat(&seed);
			if(maxMinHeight > biome.maxHeight - @divTrunc(biome.maxHeight - biome.minHeight, 4)) {
				height = height*0.25 + 0.75;
			}
			if(minMaxHeight < biome.minHeight + @divTrunc(biome.maxHeight - biome.minHeight, 4)) {
				height = height*0.25;
			}
			height = height*@intToFloat(f32, biome.maxHeight - biome.minHeight) + @intToFloat(f32, biome.minHeight);
			const wx = x*terrain.SurfaceMap.MapFragment.biomeSize +% map.pos.wx;
			const wz = z*terrain.SurfaceMap.MapFragment.biomeSize +% map.pos.wz;
			map.map[@intCast(usize, x)][@intCast(usize, z)] = .{
				.biome = biome,
				.x = wx +% @floatToInt(i32, xOffset*terrain.SurfaceMap.MapFragment.biomeSize),
				.z = wz +% @floatToInt(i32, zOffset*terrain.SurfaceMap.MapFragment.biomeSize),
				.height = height,
				.seed = random.nextInt(u64, &seed),
			};
		}
	}
}

fn getInitialHumidity(map: *ClimateMapFragment, x: f32, z: f32, height: f32) f32 {
	if(height < oceanThreshold) return 1;
	const wx = x + @intToFloat(f32, map.pos.wx >> terrain.SurfaceMap.MapFragment.biomeShift);
	const wz = z + @intToFloat(f32, map.pos.wz >> terrain.SurfaceMap.MapFragment.biomeShift);
	var distance = @sqrt(wx*wx + wz*wz);
	distance = @rem(distance, 1);
	// On earth there is high humidity at the equator and the poles and low humidty at around 30°.
	// Interpolating through this data resulted in this function:
	// 1 - 2916/125*x² - 16038/125*x⁴ + 268272/125*x⁶ - 629856/125*x⁸
	if(distance >= 0.5) distance -= 1;
	const @"x²" = distance*distance;
	const @"x⁴" = @"x²"*@"x²";
	const @"x⁶" = @"x⁴"*@"x²";
	const @"x⁸" = @"x⁴"*@"x⁴";
	const result = 1 - 2916.0/125.0*@"x²" - 16038.0/125.0*@"x⁴" + 268272.0/125.0*@"x⁶" - 629856.0/125.0*@"x⁸";
	return result*0.5 + 0.5;
}

fn getInitialTemperature(map: *ClimateMapFragment, x: f32, z: f32, height: f32) f32 {
	const wx = x + @intToFloat(f32, map.pos.wx >> terrain.SurfaceMap.MapFragment.biomeShift);
	const wz = z + @intToFloat(f32, map.pos.wz >> terrain.SurfaceMap.MapFragment.biomeShift);
	var temp = @rem(@sqrt(wx*wx + wz*wz)/ringSize, 1);
	// Uses a simple triangle function:
	if(temp > 0.5) temp = 1 - temp;
	temp = 4*temp - 1;
	return heightDependantTemperature(temp, height);
}

fn heightDependantTemperature(temperature: f32, height: f32) f32 {
	// On earth temperature changes by `6.5K/km`.
	// On a cubyz world the highest mountain will be `(1 - oceanThreshold)` units high.
	// If the highest possible height of a mountain is assumed to be 10km, the temperature change gets: `65K/(1 - oceanThreshold)*(height - oceanThreshold)`
	// Annual average temperature on earth range between -50°C and +30°C giving a difference of 80K
	// On cubyz average temperature range from -1 to 1 giving a difference of 2.
	// Therefor the total equation gets: `65K*2/80K/(1 - oceanThreshold)*(height - oceanThreshold)` = `1.625/(1 - oceanThreshold)*(height - oceanThreshold)`
	
	// Furthermore I assume that the average temperature is at 1km of height.
	return temperature - 1.625*(@max(0.0, height - oceanThreshold)/(1 - oceanThreshold) - 0.1); // TODO: #15644
}

fn findClimate(height: f32, humid: f32, temp: f32) Biome.Type {
	if (height < oceanThreshold) {
		if (temp <= frostPoint) {
			return .arctic_ocean;
		} else if (temp < hotPoint) {
			return .ocean;
		} else {
			return .warm_ocean;
		}
	} else if (height < (1.0 - oceanThreshold)*(1 - mountainRatio) + oceanThreshold) {
		if (temp <= frostPoint) {
			if (temp <= icePoint) {
				return .glacier;
			} else if (humid < wetPoint) {
				return .taiga;
			} else {
				return .tundra;
			}
		} else if (temp < hotPoint) {
			if (humid <= dryPoint) {
				return .grassland;
			} else if (humid < wetPoint) {
				return .forest;
			} else {
				return .swamp;
			}
		} else {
			if (humid <= dryPoint) {
				return .desert;
			} else if (humid < wetPoint) {
				return .shrubland;
			} else {
				return .rainforest;
			}
		}
	} else {
		if (temp <= frostPoint) {
			return .peak;
		} else {
			if (humid <= wetPoint) {
				return .mountain_grassland;
			} else {
				return .mountain_forest;
			}
		}
	}
}