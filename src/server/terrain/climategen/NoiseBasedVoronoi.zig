const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const random = main.random;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const ClimateMapFragment = terrain.ClimateMap.ClimateMapFragment;
const BiomeSample = terrain.ClimateMap.BiomeSample;
const Biome = terrain.biomes.Biome;
const TreeNode = terrain.biomes.TreeNode;
const vec = main.vec;
const Vec2i = vec.Vec2i;
const Vec2f = vec.Vec2f;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:noise_based_voronoi";

pub fn init(parameters: JsonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

pub fn generateMapFragment(map: *ClimateMapFragment, worldSeed: u64) Allocator.Error!void {
	var seed: u64 = worldSeed;

	const generator = try GenerationStructure.init(main.threadAllocator, map.pos.wx, map.pos.wz, ClimateMapFragment.mapSize, ClimateMapFragment.mapSize, terrain.biomes.byTypeBiomes, seed);
	defer generator.deinit(main.threadAllocator);

	try generator.toMap(map, ClimateMapFragment.mapSize, ClimateMapFragment.mapSize, worldSeed);

	// TODO: Remove debug image:
	const image = try main.graphics.Image.init(main.threadAllocator, @intCast(map.map.len), @intCast(map.map[0].len));
	defer image.deinit(main.threadAllocator);
	var x: u31 = 0;
	while(x < map.map.len) : (x += 1) {
		var z: u31 = 0;
		while(z < map.map[0].len) : (z += 1) {
			const bp = map.map[x][z];
			seed = std.hash.Adler32.hash(bp.biome.id) ^ 4371741;
			image.setRGB(x, z, @bitCast(0xff000000 | main.random.nextInt(u32, &seed)));
		}
	}
	try image.exportToFile("test.png");
}

const BiomePoint = struct {
	biome: *const Biome,
	height: f32,
	pos: Vec2f = .{0, 0},
	weight: f32 = 1,

	fn voronoiDistanceFunction(self: @This(), pos: Vec2f) f32 {
		const len = vec.lengthSquare(self.pos - pos);
		const result = len*self.weight;
		if(result > 1.0) {
			return result + (result - 1.0)/8192.0*len;
		}
		return result;
	}

	pub fn lessThan(lhs: @This(), rhs: @This()) bool {
		return lhs.pos[0] < rhs.pos[0];
	}
};

const maxBiomeRadius = 2048;

const chunkSize = maxBiomeRadius;
const Chunk = struct {

	wx: i32,
	wz: i32,
	biomesSortedByX: []BiomePoint,
	maxBiomeRadius: f32,

	fn getStartCoordinate(minX: f32, biomesSortedByX: []BiomePoint) usize {
		// TODO: Should this be vectorized by storing the x-coordinate in a seperate []u8?
		var start: usize = 0;
		var end: usize = biomesSortedByX.len;
		while(end - start > 16) {
			const mid = (start + end)/2 - 1;
			if(biomesSortedByX[mid].pos[0] < minX) {
				start = mid + 1;
			} else {
				end = mid + 1;
			}
		}
		return start;
	}

	fn checkIfBiomeIsValid(x: f32, y: f32, biomeRadius: f32, biomesSortedByX: []BiomePoint, chunkLocalMaxBiomeRadius: f32) bool {
		const minX = x - biomeRadius - chunkLocalMaxBiomeRadius;
		const maxX = x + biomeRadius + chunkLocalMaxBiomeRadius;
		const i: usize = getStartCoordinate(minX, biomesSortedByX);
		for(biomesSortedByX[i..]) |other| {
			if(other.pos[0] >= maxX) break;
			const minDistance = (biomeRadius + other.biome.radius)*0.85;

			if(vec.lengthSquare(other.pos - Vec2f{x, y}) < minDistance*minDistance) {
				return false;
			}
		}
		return true;
	}

	pub fn init(allocator: Allocator, tree: *TreeNode, worldSeed: u64, wx: i32, wz: i32) !*Chunk {
		var neighborBuffer: [8]*Chunk = undefined;
		var neighbors: std.ArrayListUnmanaged(*Chunk) = .{.items = neighborBuffer[0..0], .capacity = neighborBuffer.len};
		defer for(neighbors.items) |ch| {
			ch.deinit(allocator);
		};
		// Generate the chunks in an interleaved pattern, to allow seamless infinite generation.
		if(wx & chunkSize != 0) {
			neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx +% chunkSize, wz));
			neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx -% chunkSize, wz));
			if(wz & chunkSize != 0) {
				neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx +% chunkSize, wz +% chunkSize));
				neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx -% chunkSize, wz +% chunkSize));
				neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx +% chunkSize, wz -% chunkSize));
				neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx -% chunkSize, wz -% chunkSize));
				neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx, wz +% chunkSize));
				neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx, wz -% chunkSize));
			}
		} else if(wz & chunkSize != 0) {
			neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx, wz +% chunkSize));
			neighbors.appendAssumeCapacity(try Chunk.init(allocator, tree, worldSeed, wx, wz -% chunkSize));
		}

		var chunkLocalMaxBiomeRadius: f32 = 0;
		var seed = random.initSeed2D(worldSeed, .{wx, wz});
		var selectedBiomes: main.utils.SortedList(BiomePoint) = .{};
		var rejections: usize = 0;
		outer: while(rejections < 100) {
			const x = random.nextFloat(&seed)*chunkSize + @as(f32, @floatFromInt(wx));
			const y = random.nextFloat(&seed)*chunkSize + @as(f32, @floatFromInt(wz));
			var biomeSeed: u64 = 562478564;
			const drawnBiome = tree.getBiome(&biomeSeed, x, y);
			if(!checkIfBiomeIsValid(x, y, drawnBiome.radius, selectedBiomes.items(), chunkLocalMaxBiomeRadius)) {
				rejections += 1;
				continue :outer;
			}
			for(neighbors.items) |otherChunk| {
				if(!checkIfBiomeIsValid(x, y, drawnBiome.radius, otherChunk.biomesSortedByX, otherChunk.maxBiomeRadius)) {
					rejections += 1;
					continue :outer;
				}
			}
			rejections = 0;
			chunkLocalMaxBiomeRadius = @max(chunkLocalMaxBiomeRadius, drawnBiome.radius);
			try selectedBiomes.insertSorted(allocator, .{
				.biome = drawnBiome,
				.pos = .{x, y},
				.height = random.nextFloat(&seed)*@as(f32, @floatFromInt(drawnBiome.maxHeight - drawnBiome.minHeight)) + @as(f32, @floatFromInt(drawnBiome.minHeight)),
				.weight = 1.0/(std.math.pi*drawnBiome.radius*drawnBiome.radius),
			});
		}

		const self = try allocator.create(Chunk);
		self.* = .{
			.wx = wx,
			.wz = wz,
			.biomesSortedByX = try selectedBiomes.toOwnedSlice(allocator),
			.maxBiomeRadius = chunkLocalMaxBiomeRadius,
		};
		return self;
	}

	pub fn deinit(self: *Chunk, allocator: Allocator) void {
		allocator.free(self.biomesSortedByX);
		allocator.destroy(self);
	}
};

const GenerationStructure = struct {

	chunks: Array2D(*Chunk) = undefined, // Implemented as slices into the original array!
	
	pub fn init(allocator: Allocator, wx: i32, wz: i32, width: u31, height: u31, tree: *TreeNode, worldSeed: u64) !GenerationStructure {
		const self: GenerationStructure = .{
			.chunks = try Array2D(*Chunk).init(allocator, 2 + @divExact(width, chunkSize), 2 + @divExact(height, chunkSize)),
		};
		var x: u31 = 0;
		while(x < self.chunks.width) : (x += 1) {
			var z: u31 = 0;
			while(z < self.chunks.height) : (z += 1) {
				self.chunks.ptr(x, z).* = try Chunk.init(allocator, tree, worldSeed, wx +% x*chunkSize -% chunkSize, wz +% z*chunkSize -% chunkSize);
			}
		}
		return self;
	}

	pub fn deinit(self: GenerationStructure, allocator: Allocator) void {
		for(self.chunks.mem) |chunk| {
			chunk.deinit(allocator);
		}
		self.chunks.deinit(allocator);
	}

	fn findClosestBiomeTo(self: GenerationStructure, wx: i32, wz: i32, x: u31, z: u31) BiomeSample {
		const xf: f32 = @floatFromInt(wx +% x*terrain.SurfaceMap.MapFragment.biomeSize);
		const zf: f32 = @floatFromInt(wz +% z*terrain.SurfaceMap.MapFragment.biomeSize);
		var closestDist = std.math.floatMax(f32);
		var secondClosestDist = std.math.floatMax(f32);
		var closestBiomePoint: BiomePoint = undefined;
		var height: f32 = 0;
		var roughness: f32 = 0;
		var hills: f32 = 0;
		var mountains: f32 = 0;
		var totalWeight: f32 = 0;
		const cellX: i32 = x/(chunkSize/terrain.SurfaceMap.MapFragment.biomeSize);
		const cellZ: i32 = z/(chunkSize/terrain.SurfaceMap.MapFragment.biomeSize);
		// Note that at a small loss of details we can assume that all BiomePoints are withing ±1 chunks of the current one.
		var dx: i32 = 0;
		while(dx <= 2) : (dx += 1) {
			const totalX = cellX + dx;
			if(totalX < 0 or totalX >= self.chunks.width) continue;
			var dz: i32 = 0;
			while(dz <= 2) : (dz += 1) {
				const totalZ = cellZ + dz;
				if(totalZ < 0 or totalZ >= self.chunks.height) continue;
				const chunk = self.chunks.get(@intCast(totalX), @intCast(totalZ));
				const minX = xf - 3*chunk.maxBiomeRadius;
				const maxX = xf + 3*chunk.maxBiomeRadius;
				const list = chunk.biomesSortedByX[Chunk.getStartCoordinate(minX, chunk.biomesSortedByX)..];
				for(list) |biomePoint| {
					if(biomePoint.pos[0] >= maxX) break;
					const dist = biomePoint.voronoiDistanceFunction(.{xf, zf});
					var weight: f32 = @max(1.0 - @sqrt(dist), 0);
					weight *= weight;
					// The important bit is the ocean height, that's the only point where we actually need the transition point to be exact for beaches to occur.
					weight /= @abs(biomePoint.height - 16);
					height += biomePoint.height*weight;
					roughness += biomePoint.biome.roughness*weight;
					hills += biomePoint.biome.hills*weight;
					mountains += biomePoint.biome.mountains*weight;
					totalWeight += weight;

					if(dist < closestDist) {
						secondClosestDist = closestDist;
						closestDist = dist;
						closestBiomePoint = biomePoint;
					}
				}
			}
		}
		const diff = (secondClosestDist - closestDist)*1e-9; // Makes sure the total weight never gets 0.
		height += diff*closestBiomePoint.height;
		totalWeight += diff;
		std.debug.assert(closestDist != std.math.floatMax(f32));
		return .{
			.biome = closestBiomePoint.biome,
			.height = height/totalWeight,
			.roughness = roughness/totalWeight,
			.hills = hills/totalWeight,
			.mountains = mountains/totalWeight,
		};
	}

	fn drawCircleOnTheMap(map: *ClimateMapFragment, biome: *const Biome, wx: i32, wz: i32, width: u31, height: u31, pos: Vec2f) void {
		const relPos = (pos - @as(Vec2f, @floatFromInt(Vec2i{wx, wz})))/@as(Vec2f, @splat(terrain.SurfaceMap.MapFragment.biomeSize));
		const relRadius = biome.radius/terrain.SurfaceMap.MapFragment.biomeSize;
		const min = @floor(@max(Vec2f{0, 0}, relPos - @as(Vec2f, @splat(relRadius))));
		const max = @ceil(@min(@as(Vec2f, @floatFromInt(Vec2i{width, height}))/@as(Vec2f, @splat(terrain.SurfaceMap.MapFragment.biomeSize)), relPos + @as(Vec2f, @splat(relRadius))));
		var x: f32 = min[0];
		while(x < max[0]) : (x += 1) {
			var z: f32 = min[1];
			while(z < max[1]) : (z += 1) {
				const distSquare = vec.lengthSquare(Vec2f{x, z} - relPos);
				if(distSquare < relRadius*relRadius) {
					map.map[@intFromFloat(x)][@intFromFloat(z)] = .{
						.biome = biome,
						.roughness = biome.roughness,
						.hills = biome.hills,
						.mountains = biome.mountains,
						.height = (@as(f32, @floatFromInt(biome.minHeight)) + @as(f32, @floatFromInt(biome.maxHeight)))/2, // TODO: Randomize
					};
				}
			}
		}
	}

	fn addSubBiomesOf(biome: BiomePoint, map: *ClimateMapFragment, extraBiomes: *std.ArrayList(BiomePoint), wx: i32, wz: i32, width: u31, height: u31, worldSeed: u64) !void {
		var seed = random.initSeed2D(worldSeed, @bitCast(biome.pos));
		var biomeCount: f32 = undefined;
		if(biome.biome.subBiomeTotalChance > biome.biome.maxSubBiomeCount) {
			biomeCount = biome.biome.maxSubBiomeCount;
		} else if(biome.biome.subBiomeTotalChance > biome.biome.maxSubBiomeCount/2) {
			biomeCount = biome.biome.maxSubBiomeCount - (biome.biome.maxSubBiomeCount - biome.biome.subBiomeTotalChance*2)*random.nextFloat(&seed);
		} else {
			biomeCount = biome.biome.subBiomeTotalChance*2*random.nextFloat(&seed);
		}
		biomeCount = @min(biomeCount, biome.biome.maxSubBiomeCount);
		var i: f32 = 0;
		while(i < biomeCount) : (i += 1) {
			if(biomeCount - i < random.nextFloat(&seed)) break;
			const subBiome = biome.biome.subBiomes.sample(&seed).*;
			var maxCenterOffset: f32 = biome.biome.radius - subBiome.radius - 32;
			if(maxCenterOffset < 0) {
				std.log.warn("SubBiome {s} of {s} is too big", .{subBiome.id, biome.biome.id});
				maxCenterOffset = 0;
			}
			const point = biome.pos + random.nextPointInUnitCircle(&seed)*@as(Vec2f, @splat(maxCenterOffset));
			drawCircleOnTheMap(map, subBiome, wx, wz, width, height, point);
			try extraBiomes.append(.{
				.biome = subBiome,
				.pos = point,
				.height = random.nextFloat(&seed)*@as(f32, @floatFromInt(subBiome.maxHeight - subBiome.minHeight)) + @as(f32, @floatFromInt(subBiome.minHeight)),
				.weight = 1.0/(std.math.pi*subBiome.radius*subBiome.radius)
			});
		}
	}

	pub fn toMap(self: GenerationStructure, map: *ClimateMapFragment, width: u31, height: u31, worldSeed: u64) !void {
		var x: u31 = 0;
		while(x < width/terrain.SurfaceMap.MapFragment.biomeSize) : (x += 1) {
			var z: u31 = 0;
			while(z < height/terrain.SurfaceMap.MapFragment.biomeSize) : (z += 1) {
				map.map[x][z] = self.findClosestBiomeTo(map.pos.wx, map.pos.wz, x, z);
			}
		}

		// Add some sub-biomes:
		var extraBiomes = std.ArrayList(BiomePoint).init(main.threadAllocator);
		defer extraBiomes.deinit();
		for(self.chunks.mem) |chunk| {
			for(chunk.biomesSortedByX) |biome| {
				try addSubBiomesOf(biome, map, &extraBiomes, map.pos.wx, map.pos.wz, width, height, worldSeed);
			}
		}
		// Add some sub-sub(-sub)*-biomes
		while(extraBiomes.popOrNull()) |biomePoint| {
			try addSubBiomesOf(biomePoint, map, &extraBiomes, map.pos.wx, map.pos.wz, width, height, worldSeed);
		}
	}
};