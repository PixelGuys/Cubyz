const std = @import("std");

const main = @import("main");
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

pub const defaultState = .enabled;

var air: main.blocks.Block = undefined;
var stone: main.blocks.Block = undefined;
var water: main.blocks.Block = undefined;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
	air = main.blocks.parseBlock("cubyz:air");
	stone = main.blocks.parseBlock("cubyz:slate/smooth");
	water = main.blocks.parseBlock("cubyz:water");
}

fn getOceanHeight(biome: *const Biome, chunk: *main.chunk.ServerChunk, airBlockBelow: i32) i32 {
	if (!biome.isOceanRelative) {
		return biome.oceanHeight -% chunk.super.pos.wz;
	}
	const snapped: i32 = @divFloor(airBlockBelow +% chunk.super.pos.wz, @as(i32, @intCast(biome.relativeOceanGap)))*@as(i32, @intCast(biome.relativeOceanGap)) -% chunk.super.pos.wz;
	if (snapped + biome.relativeOceanOffset > airBlockBelow) {
		return snapped -% @as(i32, @intCast(biome.relativeOceanGap)) +% @as(i32, @intCast(biome.relativeOceanOffset)) +% biome.oceanHeight;
	}
	return snapped + biome.relativeOceanOffset +% biome.oceanHeight;
}

fn isOceanEdge(chunk: *main.chunk.ServerChunk, relPos: Vec3i, biome: *const Biome, biomeOceanHeight: i32, biomeMap: CaveBiomeMap.CaveBiomeMapView, caveMap: CaveMap.CaveMapView) bool {
	const neighborAirBlockBelow = caveMap.findTerrainChangeBelow(relPos[0], relPos[1], relPos[2]) + chunk.super.pos.voxelSize;
	const neighborBiome = if (neighborAirBlockBelow -% 1 >= -32) biomeMap.getBiome(relPos[0], relPos[1], neighborAirBlockBelow -% 1) else biomeMap.getBiome(relPos[0], relPos[1], relPos[2]);
	const liquidMatches = biome.liquidBlock == neighborBiome.liquidBlock;
	const neighborOceanHeight = getOceanHeight(neighborBiome, chunk, neighborAirBlockBelow);
	const neighborValidDepth = neighborOceanHeight -% neighborAirBlockBelow <= neighborBiome.oceanHeight;
	if (!liquidMatches or neighborOceanHeight != biomeOceanHeight or (biome.isOceanRelative and neighborBiome.isOceanRelative and !neighborValidDepth)) {
		return true;
	}
	return false;
}

pub fn generate(worldSeed: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void {
	if (chunk.super.pos.voxelSize >= 8) {
		var maxHeight: i32 = 0;
		var minHeight: i32 = std.math.maxInt(i32);
		var dx: i32 = -1;
		while (dx < main.chunk.chunkSize + 1) : (dx += 1) {
			var dy: i32 = -1;
			while (dy < main.chunk.chunkSize + 1) : (dy += 1) {
				const height = biomeMap.getSurfaceHeight(chunk.super.pos.wx +% dx*chunk.super.pos.voxelSize, chunk.super.pos.wy +% dy*chunk.super.pos.voxelSize);
				maxHeight = @max(maxHeight, height);
				minHeight = @min(minHeight, height - chunk.super.pos.voxelSize);
			}
		}
		if (minHeight > chunk.super.pos.wz +| chunk.super.width) {
			chunk.super.data.fillUniform(stone);
			return;
		}
		if (maxHeight < chunk.super.pos.wz) {
			chunk.super.data.fillUniform(air);
			return;
		}
	}
	const voxelSizeShift = @ctz(chunk.super.pos.voxelSize);
	var x: u31 = 0;
	while (x < chunk.super.width) : (x += chunk.super.pos.voxelSize) {
		var y: u31 = 0;
		while (y < chunk.super.width) : (y += chunk.super.pos.voxelSize) {
			const heightData = caveMap.getHeightData(x, y);
			var zBiome: i32 = 0;
			while (zBiome < chunk.super.width) {
				var biomeHeight: i32 = chunk.super.width - zBiome;
				var baseSeed: u64 = undefined;
				const biome = biomeMap.getBiomeColumnAndSeed(x, y, zBiome, true, &baseSeed, &biomeHeight);
				defer zBiome = chunk.startIndex(zBiome + biomeHeight - 1 + chunk.super.pos.voxelSize);
				var z: i32 = @min(chunk.super.width - chunk.super.pos.voxelSize, chunk.startIndex(zBiome + biomeHeight - 1));
				while (z >= zBiome) : (z -= chunk.super.pos.voxelSize) {
					const cardinalDirections = [_]Vec3i{
						Vec3i{1, 0, 0},
						Vec3i{-1, 0, 0},
						Vec3i{0, 1, 0},
						Vec3i{0, -1, 0},
					};
					const mask = @as(u64, 1) << @intCast(z >> voxelSizeShift);
					if (heightData & mask != 0) {
						const surfaceBlock = caveMap.findTerrainChangeAbove(x, y, z) - chunk.super.pos.voxelSize;
						var maxUp: i32 = 0;
						var maxDown: i32 = 0;
						for (cardinalDirections) |direction| {
							const move = direction*@as(Vec3i, @splat(@intCast(chunk.super.pos.voxelSize)));
							if (caveMap.isSolid(x + move[0], y + move[1], z + move[2])) {
								const diff = caveMap.findTerrainChangeAbove(x + move[0], y + move[1], z + move[2]) - chunk.super.pos.voxelSize - surfaceBlock;
								maxUp = @max(maxUp, diff >> chunk.super.voxelSizeShift);
							} else {
								const diff = caveMap.findTerrainChangeBelow(x + move[0], y + move[1], z + move[2]) - surfaceBlock;
								maxDown = @max(maxDown, -diff >> chunk.super.voxelSizeShift);
							}
						}
						const slope = @min(maxUp, maxDown);

						const soilCreep: f32 = biome.soilCreep;
						var bseed: u64 = random.initSeed3D(worldSeed, .{chunk.super.pos.wx + x, chunk.super.pos.wy + y, chunk.super.pos.wz + z});
						const airBlockBelow = caveMap.findTerrainChangeBelow(x, y, z);
						// Add the biomes surface structure:
						z = @min(z + chunk.super.pos.voxelSize, biome.structure.addSubTerranian(chunk, surfaceBlock, @max(airBlockBelow, zBiome - 1), slope, soilCreep, x, y, &bseed));
						z -= chunk.super.pos.voxelSize;
						if (z < zBiome) break;
						if (z > airBlockBelow) {
							const zMin = @max(airBlockBelow + 1, zBiome);
							if (biome.stripes.len == 0) {
								chunk.updateBlockColumnInGeneration(x, y, zMin, z, biome.stoneBlock);
								z = zMin;
							} else {
								while (z >= zMin) : (z -= chunk.super.pos.voxelSize) {
									var block = biome.stoneBlock;
									var seed = baseSeed;
									for (biome.stripes) |stripe| {
										const pos: Vec3d = .{
											@as(f64, @floatFromInt(x + chunk.super.pos.wx)),
											@as(f64, @floatFromInt(y + chunk.super.pos.wy)),
											@as(f64, @floatFromInt(z + chunk.super.pos.wz)),
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

										const distance = (stripe.maxDistance - stripe.minDistance)*main.random.nextDouble(&seed) + stripe.minDistance;

										const offset = (stripe.maxOffset - stripe.minOffset)*main.random.nextDouble(&seed) + stripe.minOffset;

										const width = (stripe.maxWidth - stripe.minWidth)*main.random.nextDouble(&seed) + stripe.minWidth;

										if (@mod(d + offset, distance) < width) {
											block = stripe.block;
											break;
										}
									}
									chunk.updateBlockInGeneration(x, y, z, block);
								}
								z += chunk.super.pos.voxelSize;
							}
						}
					} else {
						const surface = biomeMap.getSurfaceHeight(x + chunk.super.pos.wx, y + chunk.super.pos.wy) - (chunk.super.pos.voxelSize - 1) -% chunk.super.pos.wz;
						const airVolumeStart = caveMap.findTerrainChangeBelow(x, y, z) + chunk.super.pos.voxelSize;
						const zStart = @max(airVolumeStart, zBiome);
						var airBlockBelow = surface;
						if (biome.isOceanRelative) {
							airBlockBelow = airVolumeStart;
						}
						const oceanHeight = getOceanHeight(biome, chunk, airBlockBelow);
						const oceanSurfaceDifference = oceanHeight -% airBlockBelow;
						if (z < airBlockBelow or zStart >= oceanHeight or (biome.isOceanRelative and oceanSurfaceDifference > biome.oceanHeight)) {
							chunk.updateBlockColumnInGeneration(x, y, zStart, z, .{.typ = 0, .data = 0});
						} else {
							if (z >= oceanHeight) {
								chunk.updateBlockColumnInGeneration(x, y, oceanHeight, z, .{.typ = 0, .data = 0});
								z = oceanHeight -% chunk.super.pos.voxelSize;
							}
							var blockToPlace = biome.liquidBlock;
							for (cardinalDirections) |cardinalDirection| {
								const neighborCoords = Vec3i{x, y, z} + cardinalDirection;
								if (isOceanEdge(chunk, neighborCoords, biome, oceanHeight, biomeMap, caveMap)) {
									blockToPlace = biome.stoneBlock;
									var bseed: u64 = random.initSeed3D(worldSeed, .{chunk.super.pos.wx + x, chunk.super.pos.wy + y, chunk.super.pos.wz + z});
									z = @min(z + chunk.super.pos.voxelSize, biome.structure.addSubTerranian(chunk, oceanHeight -% 1, @max(airBlockBelow, zBiome - 1), 0, 1, x, y, &bseed));
									z -= chunk.super.pos.voxelSize;
									break;
								}
							}
							if (zStart <= z) {
								chunk.updateBlockColumnInGeneration(x, y, zStart, z, blockToPlace);
							}
						}
						z = zStart;
					}
				}
			}
		}
	}
}
