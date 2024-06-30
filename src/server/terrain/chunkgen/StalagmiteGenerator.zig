const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const vec = main.vec;

pub const id = "cubyz:stalagmite";

pub const priority = 16384;

pub const generatorSeed = 0x2ba5bef20d6153a5;

const surfaceDist = 2; // How far away stalagmite can spawn from the wall.

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

pub fn generate(worldSeed: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	if(chunk.super.pos.voxelSize > 2) return;
	const size = chunk.super.width;
	// Generate caves from all nearby chunks:
	var x = chunk.super.pos.wx -% main.chunk.chunkSize;
	while(x != chunk.super.pos.wx +% size +% main.chunk.chunkSize) : (x +%= main.chunk.chunkSize) {
		var y = chunk.super.pos.wy -% main.chunk.chunkSize;
		while(y != chunk.super.pos.wy +% size +% main.chunk.chunkSize) : (y +%= main.chunk.chunkSize) {
			var z = chunk.super.pos.wz -% main.chunk.chunkSize;
			while(z != chunk.super.pos.wz +% size +% main.chunk.chunkSize) : (z +%= main.chunk.chunkSize) {
				var seed = random.initSeed3D(worldSeed, .{x, y, z});
				considerCoordinates(x, y, z, chunk, caveMap, biomeMap, &seed);
			}
		}
	}
}

fn distSqr(x: f32, y: f32, z: f32) f32 {
	return x*x + y*y + z*z;
}

fn considerStalagmite(x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, stalagmiteBlock: u16, seed: *u64) void {
	const relX: f32 = @as(f32, @floatFromInt(x -% chunk.super.pos.wx)) + main.random.nextFloat(seed);
	const relY: f32 = @as(f32, @floatFromInt(y -% chunk.super.pos.wy)) + main.random.nextFloat(seed);
	const relZ: f32 = @as(f32, @floatFromInt(z -% chunk.super.pos.wz)) + main.random.nextFloat(seed);

	const iRelX: i32 = x -% chunk.super.pos.wx;
	const iRelY: i32 = y -% chunk.super.pos.wy;
	const iRelZ: i32 = z -% chunk.super.pos.wz;
	
	var length = 12 + random.nextFloat(seed) * random.nextFloat(seed) * 36;
	const tiny = random.nextFloat(seed) < 0.9;
	if (tiny) {
		length = 5 + random.nextFloat(seed)*3;
	}
	// Choose a direction:

	const distanceAbove = @abs(caveMap.findTerrainChangeAbove(iRelX, iRelY, iRelZ) - iRelZ);
	const distanceBelow = @abs(caveMap.findTerrainChangeBelow(iRelX, iRelY, iRelZ) - iRelZ);

	if (distanceAbove == distanceBelow) {
		return;
	}

	const delZ: f32 = if (distanceAbove < distanceBelow) 1 else -1;
	var j: f32 = 0;
	while(j < length) {
		const z2 = relZ + delZ*j;
		var size: f32 = 0;
		size = 18*(length - j)/length/4;
		if (tiny)
			size /= 3;
		const xMin: i32 = @intFromFloat(relX - size);
		const xMax: i32 = @intFromFloat(relX + size);
		const yMin: i32 = @intFromFloat(relY - size);
		const yMax: i32 = @intFromFloat(relY + size);
		const zMin: i32 = @intFromFloat(z2 - size);
		const zMax: i32 = @intFromFloat(z2 + size);
		var x3: i32 = xMin;
		while(x3 <= xMax) : (x3 += 1) {
			var y3: i32 = yMin;
			while(y3 <= yMax) : (y3 += 1) {
				var z3: i32 = zMin;
				while(z3 <= zMax) : (z3 += 1) {
					const dist = distSqr(@as(f32, @floatFromInt(x3)) - relX, @as(f32, @floatFromInt(y3)) - relY, @as(f32, @floatFromInt(z3)) - z2);
					if(dist < size*size) {
						if(x3 >= 0 and x3 < chunk.super.width and y3 >= 0 and y3 < chunk.super.width and z3 >= 0 and z3 < chunk.super.width) {
							const block: main.blocks.Block = chunk.getBlock(x3, y3, z3);
							if(block.typ == 0 or block.degradable() or block.blockClass() == .fluid) {
								chunk.updateBlockInGeneration(x3, y3, z3, .{.typ = stalagmiteBlock, .data = 0}); // TODO: Use natural standard.
							}
						}
					}
				}
			}
		}
		if(size > 2) size = 2;
		j += size/2; // Make sure there are no stalagmite bits floating in the air.
		if(size < 0.5) break; // Also preventing floating stalagmite bits.
	}
}

fn considerCoordinates(x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView, seed: *u64) void {
	const oldSeed = seed.*;
	const biome = biomeMap.getBiomeAndSeed(x +% main.chunk.chunkSize/2 -% chunk.super.pos.wx, y +% main.chunk.chunkSize/2 -% chunk.super.pos.wy, z +% main.chunk.chunkSize/2 -% chunk.super.pos.wz, true, seed);
	const stalagmiteSpawns = biome.stalagmites;
	random.scrambleSeed(seed);
	
	// Spawn the stalagmites using the old position specific seed:
	seed.* = oldSeed;
	for(0..stalagmiteSpawns) |_| {
		// Choose some in world coordinates to start generating:
		const worldX = x + random.nextIntBounded(u31, seed, main.chunk.chunkSize);
		const worldY = y + random.nextIntBounded(u31, seed, main.chunk.chunkSize);
		const worldZ = z + random.nextIntBounded(u31, seed, main.chunk.chunkSize);
		const relX = worldX -% chunk.super.pos.wx;
		const relY = worldY -% chunk.super.pos.wy;
		const relZ = worldZ -% chunk.super.pos.wz;
		if(caveMap.isSolid(relX, relY, relZ)) { // Only start stalagmite in solid blocks
			// Only start stalagmite when they are close to the surface (±SURFACE_DIST blocks)
			if(
				(worldZ - z >= surfaceDist and !caveMap.isSolid(relX, relY, relZ - surfaceDist))
				or (worldZ - z < main.chunk.chunkSize - surfaceDist and !caveMap.isSolid(relX, relY, relZ + surfaceDist))
			) {
				// Generate the stalagmite:
				considerStalagmite(worldX, worldY, worldZ, chunk, caveMap, biome.stalagmiteBlock, seed);
			}
		}
	}
}
