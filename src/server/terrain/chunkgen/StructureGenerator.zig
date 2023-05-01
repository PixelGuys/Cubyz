const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const RandomList = main.utils.RandomList;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMapFragment = terrain.CaveMap.CaveMapFragment;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:vegetation";

pub const priority = 131072;

pub const generatorSeed = 0x2026b65487da9226;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

pub fn generate(worldSeed: u64, chunk: *main.chunk.Chunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) Allocator.Error!void {
	if(chunk.pos.voxelSize < 4) {
		// Uses a blue noise pattern for all structure that shouldn't touch.
		const blueNoise = try noise.BlueNoise.getRegionData(main.threadAllocator, chunk.pos.wx - 8, chunk.pos.wz - 8, chunk.width + 16, chunk.width + 16);
		defer main.threadAllocator.free(blueNoise);
		for(blueNoise) |coordinatePair| {
			const px = @intCast(i32, coordinatePair >> 16) - 8;
			const pz = @intCast(i32, coordinatePair & 0xffff) - 8;
			const wpx = chunk.pos.wx + px;
			const wpz = chunk.pos.wz + pz;

			var py : i32 = -32;
			while(py < chunk.width) : (py += 32) {
				const wpy = chunk.pos.wy + py;
				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, wpz});
				var relY = py + 16;
				if(caveMap.isSolid(px, relY, pz)) {
					relY = caveMap.findTerrainChangeAbove(px, pz, relY);
				} else {
					relY = caveMap.findTerrainChangeBelow(px, pz, relY) + chunk.pos.voxelSize;
				}
				if(relY < py or relY >= py + 32) continue;
				const biome = biomeMap.getBiome(px, relY, pz);
				var randomValue = random.nextFloat(&seed);
				for(biome.vegetationModels) |model| {
					const adaptedChance = model.chance*16;
					if(randomValue < adaptedChance) {
						try model.generate(px, relY, pz, chunk, caveMap, &seed);
						break;
					} else {
						// Make sure that after the first one was considered all others get the correct chances.
						randomValue = (randomValue - adaptedChance)/(1 - adaptedChance);
					}
				}
			}
		}
	} else { // TODO: Make this case work with cave-structures. Low priority because caves aren't even generated this far out.
		var px: i32 = 0;
		while(px < chunk.width + 16) : (px += chunk.pos.voxelSize) {
			var pz: i32 = 0;
			while(pz < chunk.width + 16) : (pz += chunk.pos.voxelSize) {
				const wpx = px - 8 + chunk.pos.wx;
				const wpz = pz - 8 + chunk.pos.wz;

				const relY = @floatToInt(i32, biomeMap.getSurfaceHeight(wpx, wpz)) - chunk.pos.wy;
				if(relY < -32 or relY >= chunk.width + 32) continue;

				var seed = random.initSeed3D(worldSeed, .{wpx, relY, wpz});
				var randomValue = random.nextFloat(&seed);
				const biome = biomeMap.getBiome(px, relY, pz);
				for(biome.vegetationModels) |model| {
					var adaptedChance = model.chance;
					// Increase chance if there are less spawn points considered. Messes up positions, but at that distance density matters more.
					adaptedChance = 1 - std.math.pow(f32, 1 - adaptedChance, @intToFloat(f32, chunk.pos.voxelSize*chunk.pos.voxelSize));
					if(randomValue < adaptedChance) {
						try model.generate(px - 8, relY, pz - 8, chunk, caveMap, &seed);
						break;
					} else {
						// Make sure that after the first one was considered all others get the correct chances.
						randomValue = (randomValue - adaptedChance)/(1 - adaptedChance);
					}
				}
			}
		}
	}
}