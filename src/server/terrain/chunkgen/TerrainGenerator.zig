const std = @import("std");

const main = @import("root");
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const CaveBiomeMap = terrain.CaveBiomeMap;
const Biome = terrain.biomes.Biome;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:terrain";

pub const priority = 1024; // Within Cubyz the first to be executed, but mods might want to come before that for whatever reason.

pub const generatorSeed = 0x65c7f9fdc0641f94;

var water: u16 = undefined;

pub fn init(parameters: JsonElement) void {
	_ = parameters;
	water = main.blocks.getByID("cubyz:water");
}

pub fn deinit() void {

}

pub fn generate(worldSeed: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	const voxelSizeShift = @ctz(chunk.super.pos.voxelSize);
	var x: u31 = 0;
	while(x < chunk.super.width) : (x += chunk.super.pos.voxelSize) {
		var y: u31 = 0;
		while(y < chunk.super.width) : (y += chunk.super.pos.voxelSize) {
			const heightData = caveMap.getHeightData(x, y);
			var makeSurfaceStructure = true;
			var z: i32 = chunk.super.width - chunk.super.pos.voxelSize;
			while(z >= 0) : (z -= chunk.super.pos.voxelSize) {
				const mask = @as(u64, 1) << @intCast(z >> voxelSizeShift);
				if(heightData & mask != 0) {
					var seed: u64 = 0;
					const biome = biomeMap.getBiomeAndSeed(x, y, z, true, &seed);
					
					if(makeSurfaceStructure) {
						const surfaceBlock = caveMap.findTerrainChangeAbove(x, y, z) - chunk.super.pos.voxelSize;
						var bseed: u64 = random.initSeed3D(worldSeed, .{chunk.super.pos.wx + x, chunk.super.pos.wy + y, chunk.super.pos.wz + z});
						// Add the biomes surface structure:
						z = @min(z + chunk.super.pos.voxelSize, biome.structure.addSubTerranian(chunk, surfaceBlock, caveMap.findTerrainChangeBelow(x, y, z), x, y, &bseed));
						makeSurfaceStructure = false;
					} else {
						var typ = biome.stoneBlockType;
						for (biome.stripes) |stripe| {
							const pos: Vec3d = .{
								@as(f64, @floatFromInt(x + chunk.super.pos.wx)),
								@as(f64, @floatFromInt(y + chunk.super.pos.wy)),
								@as(f64, @floatFromInt(z + chunk.super.pos.wz))
							};
							var d: f64 = 0;
							if (stripe.direction) |direction| {
								d = vec.dot(direction, pos);
							} else {
								const dx = main.random.nextDoubleSigned(&seed);
								const dy = main.random.nextDoubleSigned(&seed);
								const dz = main.random.nextDoubleSigned(&seed);
								const dir: Vec3d = .{dx, dy, dz};
								d = vec.dot(vec.normalize(dir), pos);
							}

							const distance = (stripe.maxDistance - stripe.minDistance) * main.random.nextDouble(&seed) + stripe.minDistance;

							const offset = (stripe.maxOffset - stripe.minOffset) * main.random.nextDouble(&seed) + stripe.minOffset;

							const width = (stripe.maxWidth - stripe.minWidth) * main.random.nextDouble(&seed) + stripe.minWidth;

							if (@mod(d + offset, distance) < width) {
								typ = stripe.block;
								break;
							}
						}
						chunk.updateBlockInGeneration(x, y, z, .{.typ = typ, .data = 0}); // TODO: Natural standard.
					}
				} else {
					if(z + chunk.super.pos.wz < 0 and z + chunk.super.pos.wz >= biomeMap.getSurfaceHeight(x + chunk.super.pos.wx, y + chunk.super.pos.wy) - (chunk.super.pos.voxelSize - 1)) {
						chunk.updateBlockInGeneration(x, y, z, .{.typ = water, .data = 0}); // TODO: Natural standard.
					} else {
						chunk.updateBlockInGeneration(x, y, z, .{.typ = 0, .data = 0});
					}
					makeSurfaceStructure = true;
				}
			}
		}
	}
}
