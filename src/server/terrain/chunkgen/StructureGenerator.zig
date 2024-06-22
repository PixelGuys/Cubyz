const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const noise = terrain.noise;
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

pub fn generate(worldSeed: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	if(chunk.super.pos.voxelSize < 8) {
		// Uses a blue noise pattern for all structure that shouldn't touch.
		const blueNoise = noise.BlueNoise.getRegionData(main.stackAllocator, chunk.super.pos.wx -% 16, chunk.super.pos.wy -% 16, chunk.super.width + 32, chunk.super.width + 32);
		defer main.stackAllocator.free(blueNoise);
		for(blueNoise) |coordinatePair| {
			const px = @as(i32, @intCast(coordinatePair >> 16)) - 16; // TODO: Maybe add a blue-noise iterator or something like that?
			const py = @as(i32, @intCast(coordinatePair & 0xffff)) - 16;
			const wpx = chunk.super.pos.wx +% px;
			const wpy = chunk.super.pos.wy +% py;

			var pz : i32 = -32;
			while(pz < chunk.super.width + 32) : (pz += 32) {
				const wpz = chunk.super.pos.wz +% pz;
				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, wpz});
				var relZ = pz + 16;
				if(caveMap.isSolid(px, py, relZ)) {
					relZ = caveMap.findTerrainChangeAbove(px, py, relZ);
				} else {
					relZ = caveMap.findTerrainChangeBelow(px, py, relZ) + chunk.super.pos.voxelSize;
				}
				if(relZ < pz or relZ >= pz + 32) continue;
				const biome = biomeMap.getBiome(px, py, relZ);
				var randomValue = random.nextFloat(&seed);
				for(biome.vegetationModels) |model| { // TODO: Could probably use an alias table here.
					const adaptedChance = model.chance*16;
					if(randomValue < adaptedChance) {
						model.generate(px, py, relZ, chunk, caveMap, &seed);
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
		while(px < chunk.super.width + 32) : (px += chunk.super.pos.voxelSize) {
			var py: i32 = 0;
			while(py < chunk.super.width + 32) : (py += chunk.super.pos.voxelSize) {
				const wpx = px -% 16 +% chunk.super.pos.wx;
				const wpy = py -% 16 +% chunk.super.pos.wy;

				const relZ = biomeMap.getSurfaceHeight(wpx, wpy) -% chunk.super.pos.wz;
				if(relZ < -32 or relZ >= chunk.super.width + 32) continue;

				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, relZ});
				var randomValue = random.nextFloat(&seed);
				const biome = biomeMap.getBiome(px, py, relZ);
				for(biome.vegetationModels) |model| { // TODO: Could probably use an alias table here.
					var adaptedChance = model.chance;
					// Increase chance if there are less spawn points considered. Messes up positions, but at that distance density matters more.
					adaptedChance = 1 - std.math.pow(f32, 1 - adaptedChance, @as(f32, @floatFromInt(chunk.super.pos.voxelSize*chunk.super.pos.voxelSize)));
					if(randomValue < adaptedChance) {
						model.generate(px - 16, py - 16, relZ, chunk, caveMap, &seed);
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