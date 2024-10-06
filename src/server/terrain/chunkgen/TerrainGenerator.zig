const std = @import("std");

const main = @import("root");
const random = main.random;
const ZonElement = main.ZonElement;
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

pub fn init(parameters: ZonElement) void {
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
			var zBiome: i32 = 0;
			while(zBiome < chunk.super.width) {
				var biomeHeight: i32 = chunk.super.width - zBiome;
				var baseSeed: u64 = undefined;
				const biome = biomeMap.getBiomeColumnAndSeed(x, y, zBiome, true, &baseSeed, &biomeHeight);
				defer zBiome = chunk.startIndex(zBiome + biomeHeight - 1 + chunk.super.pos.voxelSize);
				var z: i32 = @min(chunk.super.width - chunk.super.pos.voxelSize, chunk.startIndex(zBiome + biomeHeight - 1));
				while(z >= zBiome) : (z -= chunk.super.pos.voxelSize) {
					const mask = @as(u64, 1) << @intCast(z >> voxelSizeShift);
					if(heightData & mask != 0) {
						const surfaceBlock = caveMap.findTerrainChangeAbove(x, y, z) - chunk.super.pos.voxelSize;
						var bseed: u64 = random.initSeed3D(worldSeed, .{chunk.super.pos.wx + x, chunk.super.pos.wy + y, chunk.super.pos.wz + z});
						const airBlockBelow = caveMap.findTerrainChangeBelow(x, y, z);
						// Add the biomes surface structure:
						z = @min(z + chunk.super.pos.voxelSize, biome.structure.addSubTerranian(chunk, surfaceBlock, @max(airBlockBelow, zBiome - 1), x, y, &bseed));
						z -= chunk.super.pos.voxelSize;
						if(z < zBiome) break;
						if(z > airBlockBelow) {
							const zMin = @max(airBlockBelow + 1, zBiome);
							if(biome.stripes.len == 0) {
								const typ = biome.stoneBlockType;
								chunk.updateBlockColumnInGeneration(x, y, zMin, z, .{.typ = typ, .data = 0}); // TODO: Natural standard.
								z = zMin;
							} else {
								while(z >= zMin) : (z -= chunk.super.pos.voxelSize) {
									var typ = biome.stoneBlockType;
									var seed = baseSeed;
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
								z += chunk.super.pos.voxelSize;
							}
						}
					} else {
						const surface = biomeMap.getSurfaceHeight(x + chunk.super.pos.wx, y + chunk.super.pos.wy) - (chunk.super.pos.voxelSize - 1) -% chunk.super.pos.wz;
						const oceanHeight = 0 -% chunk.super.pos.wz;
						const airVolumeStart = caveMap.findTerrainChangeBelow(x, y, z) + chunk.super.pos.voxelSize;
						const zStart = @max(airVolumeStart, zBiome);
						if(z < surface or zStart >= oceanHeight) {
							chunk.updateBlockColumnInGeneration(x, y, zStart, z, .{.typ = 0, .data = 0});
						} else {
							if(z >= oceanHeight) {
								chunk.updateBlockColumnInGeneration(x, y, oceanHeight, z, .{.typ = 0, .data = 0});
								z = oceanHeight - chunk.super.pos.voxelSize;
							}
							chunk.updateBlockColumnInGeneration(x, y, zStart, z, .{.typ = water, .data = 0}); // TODO: Natural standard.
						}
						z = zStart;
					}
				}
			}
		}
	}
}
