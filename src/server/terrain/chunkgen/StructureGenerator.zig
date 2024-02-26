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

pub fn generate(worldSeed: u64, chunk: *main.chunk.Chunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	if(chunk.pos.voxelSize < 4) {
		// Uses a blue noise pattern for all structure that shouldn't touch.
		const blueNoise = noise.BlueNoise.getRegionData(main.stackAllocator, chunk.pos.wx - 8, chunk.pos.wy - 8, chunk.width + 16, chunk.width + 16);
		defer main.stackAllocator.free(blueNoise);
		for(blueNoise) |coordinatePair| {
			const px = @as(i32, @intCast(coordinatePair >> 16)) - 8; // TODO: Maybe add a blue-noise iterator or something like that?
			const py = @as(i32, @intCast(coordinatePair & 0xffff)) - 8;
			const wpx = chunk.pos.wx + px;
			const wpy = chunk.pos.wy + py;

			var pz : i32 = -32;
			while(pz < chunk.width) : (pz += 32) {
				const wpz = chunk.pos.wz + pz;
				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, wpz});
				var relZ = pz + 16;
				if(caveMap.isSolid(px, py, relZ)) {
					relZ = caveMap.findTerrainChangeAbove(px, py, relZ);
				} else {
					relZ = caveMap.findTerrainChangeBelow(px, py, relZ) + chunk.pos.voxelSize;
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
		while(px < chunk.width + 16) : (px += chunk.pos.voxelSize) {
			var py: i32 = 0;
			while(py < chunk.width + 16) : (py += chunk.pos.voxelSize) {
				const wpx = px - 8 + chunk.pos.wx;
				const wpy = py - 8 + chunk.pos.wy;

				const relZ = @as(i32, @intFromFloat(biomeMap.getSurfaceHeight(wpx, wpy))) - chunk.pos.wz;
				if(relZ < -32 or relZ >= chunk.width + 32) continue;

				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, relZ});
				var randomValue = random.nextFloat(&seed);
				const biome = biomeMap.getBiome(px, py, relZ);
				for(biome.vegetationModels) |model| { // TODO: Could probably use an alias table here.
					var adaptedChance = model.chance;
					// Increase chance if there are less spawn points considered. Messes up positions, but at that distance density matters more.
					adaptedChance = 1 - std.math.pow(f32, 1 - adaptedChance, @as(f32, @floatFromInt(chunk.pos.voxelSize*chunk.pos.voxelSize)));
					if(randomValue < adaptedChance) {
						model.generate(px - 8, py - 8, relZ, chunk, caveMap, &seed);
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