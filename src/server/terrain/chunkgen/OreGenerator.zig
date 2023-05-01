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

pub const id = "cubyz:ore";

pub const priority = 32768;

pub const generatorSeed = 0x88773787bc9e0105;

var ores: []main.blocks.Ore = undefined;

// TODO: Idea:
// Add a RotationMode that allows you to overlay the ore texture onto a regular block to get more ore-in-stone-types for free.

pub fn init(parameters: JsonElement) void {
	_ = parameters;
	ores = main.blocks.ores.items;
}

pub fn deinit() void {

}

// Works basically similar to cave generation, but considers a lot less chunks and has a few other differences.
pub fn generate(worldSeed: u64, chunk: *main.chunk.Chunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) Allocator.Error!void {
	_ = caveMap;
	_ = biomeMap;
	if(chunk.pos.voxelSize != 1) return;
	const cx = chunk.pos.wx >> main.chunk.chunkShift;
	const cy = chunk.pos.wy >> main.chunk.chunkShift;
	const cz = chunk.pos.wz >> main.chunk.chunkShift;
	// Generate caves from all nearby chunks:
	var x = cx - 1;
	while(x < cx + 1) : (x +%= 1) {
		var y = cy - 1;
		while(y < cy + 1) : (y +%= 1) {
			var z = cz - 1;
			while(z < cz + 1) : (z +%= 1) {
				var seed = random.initSeed3D(worldSeed, .{x, y, z});
				considerCoordinates(x, y, z, cx, cy, cz, chunk, seed);
			}
		}
	}
}

fn considerCoordinates(x: i32, y: i32, z: i32, cx: i32, cy: i32, cz: i32, chunk: *main.chunk.Chunk, startSeed: u64) void {
	for(ores) |ore| {
		if(ore.maxHeight <= y << main.chunk.chunkShift) continue;
		// Compose the seeds from some random stats of the ore. They generally shouldn't be the same for two different ores.
		var seed = startSeed ^ @bitCast(u32, ore.maxHeight) ^ @bitCast(u32, ore.size) ^ @bitCast(u32, main.blocks.Block.hardness(.{.typ = ore.blockType, .data = 0}));
		random.scrambleSeed(&seed);
		// Determine how many veins of this type start in this chunk. The number depends on parameters set for the specific ore:
		const veins = @floatToInt(u32, random.nextFloat(&seed)*ore.veins*2);
		for(0..veins) |_| {
			// Choose some in world coordinates to start generating:
			const relX = @intToFloat(f32, x-cx << main.chunk.chunkShift) + random.nextFloat(&seed)*@intToFloat(f32, main.chunk.chunkSize);
			const relY = @intToFloat(f32, y-cy << main.chunk.chunkShift) + random.nextFloat(&seed)*@intToFloat(f32, main.chunk.chunkSize);
			const relZ = @intToFloat(f32, z-cz << main.chunk.chunkShift) + random.nextFloat(&seed)*@intToFloat(f32, main.chunk.chunkSize);
			// Choose a random volume and create a radius from that:
			const size = (random.nextFloat(&seed) + 0.5)*ore.size;
			const expectedVolume = 2*size/ore.density; // Double the volume, because later the density is actually halfed.
			const radius = std.math.cbrt(expectedVolume*3/4/std.math.pi);
			var xMin = @floatToInt(i32, relX - radius);
			var xMax = @floatToInt(i32, @ceil(relX + radius));
			var zMin = @floatToInt(i32, relZ - radius);
			var zMax = @floatToInt(i32, @ceil(relZ + radius));
			xMin = @max(xMin, 0);
			xMax = @min(xMax, chunk.width);
			zMin = @max(zMin, 0);
			zMax = @min(zMax, chunk.width);

			var veinSeed = random.nextInt(u64, &seed);
			var curX = xMin;
			while(curX < xMax) : (curX += 1) {
				const distToCenterX = (@intToFloat(f32, curX) - relX)/radius;

				var curZ = zMin;
				while(curZ < zMax) : (curZ += 1) {
					const distToCenterZ = (@intToFloat(f32, curZ) - relZ)/radius;
					const xzDistSqr = distToCenterX*distToCenterX + distToCenterZ*distToCenterZ;
					if(xzDistSqr > 1) continue;
					const yDistance = radius*@sqrt(1 - xzDistSqr);
					var yMin = @floatToInt(i32, relY - yDistance);
					var yMax = @floatToInt(i32, @ceil(relY + yDistance));
					yMin = @max(yMin, 0);
					yMax = @min(yMax, chunk.width);
					var curY = yMin;
					while(curY < yMax) : (curY += 1) {
						const distToCenterY = (@intToFloat(f32, curY) - relY)/radius;
						const distSqr = xzDistSqr + distToCenterY*distToCenterY;
						if(distSqr < 1) {
							// Add some roughness. The ore density gets smaller at the edges:
							if((1 - distSqr)*ore.density >= random.nextFloat(&veinSeed)) {
								if(ore.canCreateVeinInBlock(chunk.getBlock(curX, curY, curZ).typ)) {
									chunk.updateBlockInGeneration(curX, curY, curZ, .{.typ = ore.blockType, .data = 0}); // TODO: Use natural standard.
								}
							}
						}
					}
				}
			}
		}
	}
}