const std = @import("std");

const build_options = @import("build_options");

const main = @import("main");
const Array2D = main.utils.Array2D;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const ClimateMapFragment = terrain.ClimateMap.ClimateMapFragment;
const BiomeSample = terrain.ClimateMap.BiomeSample;
const Biome = terrain.biomes.Biome;
const TreeNode = terrain.biomes.TreeNode;
const vec = main.vec;
const Vec2i = vec.Vec2i;
const Vec2f = vec.Vec2f;

const NeverFailingAllocator = main.heap.NeverFailingAllocator;

// Generates the climate map using a fluidynamics simulation, with a circular heat distribution.

pub const id = "cubyz:noise_based_voronoi";

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn generateMapFragment(map: *ClimateMapFragment, worldSeed: u64) void {
	var seed: u64 = worldSeed;

	const generator = GenerationStructure.init(main.stackAllocator, map.pos.wx, map.pos.wy, ClimateMapFragment.mapSize, ClimateMapFragment.mapSize, terrain.biomes.byTypeBiomes, seed);
	defer generator.deinit(main.stackAllocator);

	generator.toMap(map, ClimateMapFragment.mapSize, ClimateMapFragment.mapSize, worldSeed);

	// TODO: Remove debug image:
	if(!build_options.isTaggedRelease) {
		const image = main.graphics.Image.init(main.stackAllocator, @intCast(map.map.len), @intCast(map.map[0].len));
		defer image.deinit(main.stackAllocator);
		var x: u31 = 0;
		while(x < map.map.len) : (x += 1) {
			var y: u31 = 0;
			while(y < map.map[0].len) : (y += 1) {
				const bp = map.map[x][y];
				seed = std.hash.Adler32.hash(bp.biome.id) ^ 4371741;
				image.setRGB(x, y, @bitCast(0xff000000 | main.random.nextInt(u32, &seed)));
			}
		}
		image.exportToFile("test.png") catch {};
	}
}

const BiomePoint = struct {
	biome: *const Biome,
	height: f32,
	pos: Vec2i = .{0, 0},
	weight: f32 = 1,
	radius: f32,

	fn voronoiDistanceFunction(self: @This(), pos: Vec2i) f32 {
		const len: f32 = @sqrt(@as(f32, @floatFromInt(vec.lengthSquare(self.pos -% pos))));
		const result = len*self.weight;
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
	wy: i32,
	biomesSortedByX: []BiomePoint,
	maxBiomeRadius: i32,

	fn getStartCoordinate(minX: i32, biomesSortedByX: []BiomePoint) usize {
		// TODO: Should this be vectorized by storing the x-coordinate in a seperate []u8?
		var start: usize = 0;
		var end: usize = biomesSortedByX.len;
		while(end - start > 16) {
			const mid = (start + end)/2 - 1;
			if(biomesSortedByX[mid].pos[0] -% minX < 0) {
				start = mid + 1;
			} else {
				end = mid + 1;
			}
		}
		return start;
	}

	fn checkIfBiomeIsValid(x: i32, y: i32, biomeRadius: f32, biomesSortedByX: []BiomePoint, chunkLocalMaxBiomeRadius: i32) bool {
		const ceiledBiomeRadius: i32 = @intFromFloat(@ceil(biomeRadius));
		const minX = x -% ceiledBiomeRadius -% chunkLocalMaxBiomeRadius;
		const maxX = x +% ceiledBiomeRadius +% chunkLocalMaxBiomeRadius;
		const i: usize = getStartCoordinate(minX, biomesSortedByX);
		for(biomesSortedByX[i..]) |other| {
			if(other.pos[0] -% maxX >= 0) break;
			const minDistance = (biomeRadius + other.radius)*0.85;

			if(@as(f32, @floatFromInt(vec.lengthSquare(other.pos -% Vec2i{x, y}))) < minDistance*minDistance) {
				return false;
			}
		}
		return true;
	}

	pub fn init(allocator: NeverFailingAllocator, tree: *TreeNode, worldSeed: u64, wx: i32, wy: i32, neighbors: []const *const Chunk) *Chunk {
		var chunkLocalMaxBiomeRadius: i32 = 0;
		var seed = random.initSeed2D(worldSeed, .{wx, wy});
		var selectedBiomes: main.utils.SortedList(BiomePoint) = .{};
		var rejections: usize = 0;
		outer: while(rejections < 100) {
			const x = random.nextIntBounded(u31, &seed, chunkSize) + wx;
			const y = random.nextIntBounded(u31, &seed, chunkSize) + wy;
			var biomeSeed: u64 = worldSeed;
			const drawnBiome = tree.getBiome(&biomeSeed, x, y, 0);
			const radius = drawnBiome.radius + drawnBiome.radiusVariation*random.nextFloatSigned(&seed);
			if(!checkIfBiomeIsValid(x, y, radius, selectedBiomes.items(), chunkLocalMaxBiomeRadius)) {
				rejections += 1;
				continue :outer;
			}
			for(neighbors) |otherChunk| {
				if(!checkIfBiomeIsValid(x, y, radius, otherChunk.biomesSortedByX, otherChunk.maxBiomeRadius)) {
					rejections += 1;
					continue :outer;
				}
			}
			rejections = 0;
			chunkLocalMaxBiomeRadius = @max(chunkLocalMaxBiomeRadius, @as(i32, @intFromFloat(@ceil(radius))));
			selectedBiomes.insertSorted(allocator, .{
				.biome = drawnBiome,
				.pos = .{x, y},
				.height = random.nextFloat(&seed)*@as(f32, @floatFromInt(drawnBiome.maxHeight - drawnBiome.minHeight)) + @as(f32, @floatFromInt(drawnBiome.minHeight)),
				.weight = 1.0/@sqrt(std.math.pi*radius*radius),
				.radius = radius,
			});
		}

		const self = allocator.create(Chunk);
		self.* = .{
			.wx = wx,
			.wy = wy,
			.biomesSortedByX = selectedBiomes.toOwnedSlice(allocator),
			.maxBiomeRadius = chunkLocalMaxBiomeRadius,
		};
		return self;
	}

	pub fn deinit(self: *Chunk, allocator: NeverFailingAllocator) void {
		allocator.free(self.biomesSortedByX);
		allocator.destroy(self);
	}
};

const GenerationStructure = struct {
	chunks: Array2D(*Chunk) = undefined, // Implemented as slices into the original array!

	pub fn init(allocator: NeverFailingAllocator, wx: i32, wy: i32, width: u31, height: u31, tree: *TreeNode, worldSeed: u64) GenerationStructure {
		const self: GenerationStructure = .{
			.chunks = Array2D(*Chunk).init(allocator, 8 + @divExact(width, chunkSize), 8 + @divExact(height, chunkSize)),
		};
		// Generate chunks in an interleaved pattern:
		const offset: [4][2]u31 = .{
			.{0, 0},
			.{0, 1},
			.{1, 0},
			.{1, 1},
		};
		const neighborOffsets: [4][]const [2]i32 = .{
			&.{},
			&.{.{0, -1}, .{0, 1}},
			&.{.{-1, 0}, .{1, 0}, .{-1, -1}, .{1, -1}, .{-1, 1}, .{1, 1}},
			&.{.{0, -1}, .{0, 1}, .{-1, 0}, .{1, 0}, .{-1, -1}, .{1, -1}, .{-1, 1}, .{1, 1}},
		};
		for(0..4) |i| {
			var x: u31 = offset[i][0];
			while(x < self.chunks.width) : (x += 2) {
				var y: u31 = offset[i][1];
				while(y < self.chunks.height) : (y += 2) {
					var neighbors: [8]*const Chunk = undefined;
					var j: usize = 0;
					for(neighborOffsets[i]) |neighborOffset| {
						const nx = x + neighborOffset[0];
						if(nx < 0 or @as(usize, @intCast(nx)) >= self.chunks.width) continue;
						const ny = y + neighborOffset[1];
						if(ny < 0 or @as(usize, @intCast(ny)) >= self.chunks.height) continue;
						neighbors[j] = self.chunks.get(@intCast(nx), @intCast(ny));
						j += 1;
					}
					self.chunks.ptr(x, y).* = Chunk.init(allocator, tree, worldSeed, wx +% x*chunkSize -% 4*chunkSize, wy +% y*chunkSize -% 4*chunkSize, neighbors[0..j]);
				}
			}
		}
		return self;
	}

	pub fn deinit(self: GenerationStructure, allocator: NeverFailingAllocator) void {
		for(self.chunks.mem) |chunk| {
			chunk.deinit(allocator);
		}
		self.chunks.deinit(allocator);
	}

	fn smoothInterpolation(x: f32) f32 {
		return x*x*(3 - 2*x);
	}

	fn findClosestBiomeTo(self: GenerationStructure, wx: i32, wy: i32, relX: i32, relY: i32, worldSeed: u64) BiomeSample {
		const x = wx +% relX*terrain.SurfaceMap.MapFragment.biomeSize;
		const y = wy +% relY*terrain.SurfaceMap.MapFragment.biomeSize;
		var closestDist = std.math.floatMax(f32);
		var secondClosestDist = std.math.floatMax(f32);
		var closestBiomePoint: BiomePoint = undefined;
		var height: f32 = 0;
		var roughness: f32 = 0;
		var hills: f32 = 0;
		var mountains: f32 = 0;
		var totalWeight: f32 = 0;
		const cellX: i32 = @divFloor(relX, (chunkSize/terrain.SurfaceMap.MapFragment.biomeSize));
		const cellY: i32 = @divFloor(relY, (chunkSize/terrain.SurfaceMap.MapFragment.biomeSize));
		// Note that at a small loss of details we can assume that all BiomePoints are within ±1 chunks of the current one.
		var candidateList: main.List(struct {point: *BiomePoint, weight: f32}) = .init(main.stackAllocator);
		defer candidateList.deinit();
		var dx: i32 = 3;
		while(dx <= 5) : (dx += 1) {
			const totalX = cellX + dx;
			if(totalX < 0 or totalX >= self.chunks.width) continue;
			var dy: i32 = 3;
			while(dy <= 5) : (dy += 1) {
				const totalY = cellY + dy;
				if(totalY < 0 or totalY >= self.chunks.height) continue;
				const chunk = self.chunks.get(@intCast(totalX), @intCast(totalY));
				const minX = x -% 3*chunk.maxBiomeRadius;
				const maxX = x +% 3*chunk.maxBiomeRadius;
				const list = chunk.biomesSortedByX[Chunk.getStartCoordinate(minX, chunk.biomesSortedByX)..];
				for(list) |*biomePoint| {
					if(biomePoint.pos[0] -% maxX >= 0) break;
					candidateList.append(.{.point = biomePoint, .weight = 1});
				}
			}
		}
		// Interpolate between all pairs of biomes.
		var i: usize = 0;
		outer: while(i < candidateList.items.len) {
			const dist = candidateList.items[i].point.voronoiDistanceFunction(.{x, y});
			var j = i + 1;
			while(j < candidateList.items.len) {
				const dist2 = candidateList.items[j].point.voronoiDistanceFunction(.{x, y});
				const totalDist = dist + dist2;
				const interpolationStrength = 0.5;
				const centerPos = totalDist*0.5;
				const interpolationStart = centerPos - interpolationStrength*0.5;
				const interpolationEnd = centerPos + interpolationStrength*0.5;
				if(dist < interpolationStart) {
					_ = candidateList.swapRemove(j);
					continue;
				}
				if(dist > interpolationEnd) {
					_ = candidateList.swapRemove(i);
					continue :outer;
				}
				const interp = smoothInterpolation((dist - interpolationStart)/(interpolationEnd - interpolationStart));
				candidateList.items[i].weight *= 1 - interp;
				candidateList.items[j].weight *= interp;
				j += 1;
			}
			i += 1;
		}
		for(candidateList.items) |candidate| {
			const weight = candidate.weight;
			height += candidate.point.height*weight;
			totalWeight += weight;
		}
		for(candidateList.items) |candidate| {
			const weight = blk: {
				if(!candidate.point.biome.smoothBeaches) break :blk candidate.weight;
				const maxHeight = @abs(height);
				const noiseHeightInfluence = candidate.point.biome.roughness + candidate.point.biome.hills + candidate.point.biome.mountains;
				break :blk candidate.weight*@min(maxHeight, noiseHeightInfluence)/noiseHeightInfluence;
			};
			roughness += candidate.point.biome.roughness*weight;
			hills += candidate.point.biome.hills*weight;
			mountains += candidate.point.biome.mountains*weight;
		}
		for(candidateList.items) |candidate| {
			var dist = candidate.point.voronoiDistanceFunction(.{x, y});
			if(@as(f32, @floatFromInt(candidate.point.biome.maxHeightLimit)) < height/totalWeight) {
				dist += 10.0;
			}
			if(@as(f32, @floatFromInt(candidate.point.biome.minHeightLimit)) > height/totalWeight) {
				dist += 10.0;
			}
			if(dist < closestDist) {
				secondClosestDist = closestDist;
				closestDist = dist;
				closestBiomePoint = candidate.point.*;
			}
		}
		std.debug.assert(totalWeight > 0);
		std.debug.assert(closestDist != std.math.floatMax(f32));
		return .{
			.biome = closestBiomePoint.biome,
			.height = height/totalWeight,
			.roughness = roughness/totalWeight,
			.hills = hills/totalWeight,
			.mountains = mountains/totalWeight,
			.seed = random.initSeed2D(worldSeed, closestBiomePoint.pos),
		};
	}

	fn drawCircleOnTheMap(map: *ClimateMapFragment, biome: *const Biome, biomeRadius: f32, wx: i32, wy: i32, width: u31, height: u31, pos: Vec2i, comptime skipMismatched: bool, parentBiome: *const Biome) !void {
		const relPos = @as(Vec2f, @floatFromInt(pos -% Vec2i{wx, wy}))/@as(Vec2f, @splat(terrain.SurfaceMap.MapFragment.biomeSize));
		const relRadius = biomeRadius/terrain.SurfaceMap.MapFragment.biomeSize;
		const min = @floor(@max(Vec2f{0, 0}, relPos - @as(Vec2f, @splat(relRadius))));
		const max = @ceil(@min(@as(Vec2f, @floatFromInt(Vec2i{width, height}))/@as(Vec2f, @splat(terrain.SurfaceMap.MapFragment.biomeSize)), relPos + @as(Vec2f, @splat(relRadius))));
		if(skipMismatched) {
			var x: f32 = min[0];
			while(x < max[0]) : (x += 1) {
				var y: f32 = min[1];
				while(y < max[1]) : (y += 1) {
					const distSquare = vec.lengthSquare(Vec2f{x, y} - relPos);
					if(distSquare < relRadius*relRadius) {
						if((&map.map)[@intFromFloat(x)][@intFromFloat(y)].biome != parentBiome) {
							return error.biomeMismatch;
						}
					}
				}
			}
		}
		var x: f32 = min[0];
		while(x < max[0]) : (x += 1) {
			var y: f32 = min[1];
			while(y < max[1]) : (y += 1) {
				const distSquare = vec.lengthSquare(Vec2f{x, y} - relPos);
				if(distSquare < relRadius*relRadius) {
					const entry = &map.map[@intFromFloat(x)][@intFromFloat(y)];
					var seed = entry.seed;
					const newHeight = @as(f32, @floatFromInt(biome.minHeight)) + @as(f32, @floatFromInt(biome.maxHeight - biome.minHeight))*random.nextFloat(&seed);
					entry.* = .{
						.biome = biome,
						.roughness = std.math.lerp(biome.roughness, entry.roughness, biome.keepOriginalTerrain),
						.hills = std.math.lerp(biome.hills, entry.hills, biome.keepOriginalTerrain),
						.mountains = std.math.lerp(biome.mountains, entry.mountains, biome.keepOriginalTerrain),
						.height = std.math.lerp(newHeight, entry.height, biome.keepOriginalTerrain),
						.seed = entry.seed,
					};
				}
			}
		}
	}

	fn addSubBiomesOf(biome: BiomePoint, map: *ClimateMapFragment, extraBiomes: *main.List(BiomePoint), wx: i32, wy: i32, width: u31, height: u31, worldSeed: u64, comptime radius: enum {known, unknown}) void {
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
		var fails: usize = 0;
		while(i < biomeCount) : (i += 1) {
			if(biomeCount - i < random.nextFloat(&seed)) break;
			const subBiome = biome.biome.subBiomes.sample(&seed).*;
			const subRadius = subBiome.radius + subBiome.radiusVariation*random.nextFloatSigned(&seed);
			var maxCenterOffset: f32 = biome.radius - subRadius;
			if(radius == .unknown) {
				maxCenterOffset += biome.radius/2;
			}
			if(maxCenterOffset < 0) {
				maxCenterOffset = 0;
			}
			const point = biome.pos +% @as(Vec2i, @intFromFloat(random.nextPointInUnitCircle(&seed)*@as(Vec2f, @splat(maxCenterOffset))));
			drawCircleOnTheMap(map, subBiome, subRadius, wx, wy, width, height, point, radius == .unknown, biome.biome) catch if(radius == .unknown) {
				fails += 1;
				if(fails < @as(usize, @intFromFloat(biomeCount))) {
					i -= 1;
				}
			};
			extraBiomes.append(.{
				.biome = subBiome,
				.pos = point,
				.height = random.nextFloat(&seed)*@as(f32, @floatFromInt(subBiome.maxHeight - subBiome.minHeight)) + @as(f32, @floatFromInt(subBiome.minHeight)),
				.weight = 1.0/(std.math.pi*subRadius*subRadius),
				.radius = subRadius,
			});
		}
	}

	fn addTransitionBiomes(comptime size: usize, comptime margin: usize, map: *[size][size]BiomeSample) void {
		const neighborData = main.stackAllocator.create([16][size][size]u15);
		defer main.stackAllocator.free(neighborData);
		for(0..size) |x| {
			for(0..size) |y| {
				neighborData[0][x][y] = @bitCast(map[x][y].biome.properties);
			}
		}
		for(1..neighborData.len) |i| {
			for(1..size - 1) |x| {
				for(1..size - 1) |y| {
					neighborData[i][x][y] = neighborData[i - 1][x][y] | neighborData[i - 1][x - 1][y] | neighborData[i - 1][x + 1][y] | neighborData[i - 1][x][y - 1] | neighborData[i - 1][x][y + 1];
				}
			}
		}
		for(margin..size - margin) |x| {
			for(margin..size - margin) |y| {
				const point = map[x][y];
				if(point.biome.transitionBiomes.len == 0) {
					std.debug.assert(!std.mem.eql(u8, "cubyz:ocean", point.biome.id));
					continue;
				}
				var seed = point.seed;
				for(point.biome.transitionBiomes) |transitionBiome| {
					const biomeMask: u15 = @bitCast(transitionBiome.propertyMask);
					const neighborMask = neighborData[@min(neighborData.len - 1, transitionBiome.width)][x][y];
					// Check if all triplets have a matching entry:
					var result = biomeMask & neighborMask;
					result = (result | result >> 1 | result >> 2);
					if(result & Biome.GenerationProperties.mask == Biome.GenerationProperties.mask) {
						if(random.nextFloat(&seed) < transitionBiome.chance) {
							const newHeight = @as(f32, @floatFromInt(transitionBiome.biome.minHeight)) + @as(f32, @floatFromInt(transitionBiome.biome.maxHeight - transitionBiome.biome.minHeight))*random.nextFloat(&seed);
							map[x][y] = .{
								.biome = transitionBiome.biome,
								.roughness = std.math.lerp(transitionBiome.biome.roughness, map[x][y].roughness, transitionBiome.biome.keepOriginalTerrain),
								.hills = std.math.lerp(transitionBiome.biome.hills, map[x][y].hills, transitionBiome.biome.keepOriginalTerrain),
								.mountains = std.math.lerp(transitionBiome.biome.mountains, map[x][y].mountains, transitionBiome.biome.keepOriginalTerrain),
								.height = std.math.lerp(newHeight, map[x][y].height, transitionBiome.biome.keepOriginalTerrain),
								.seed = map[x][y].seed,
							};
							break;
						}
					}
				}
			}
		}
	}

	pub fn toMap(self: GenerationStructure, map: *ClimateMapFragment, width: u31, height: u31, worldSeed: u64) void {
		const margin: u31 = chunkSize >> terrain.SurfaceMap.MapFragment.biomeShift;
		var preMap: [ClimateMapFragment.mapEntrysSize + 2*margin][ClimateMapFragment.mapEntrysSize + 2*margin]BiomeSample = undefined;
		var x: i32 = -@as(i32, margin);
		while(x < width/terrain.SurfaceMap.MapFragment.biomeSize + margin) : (x += 1) {
			var y: i32 = -@as(i32, margin);
			while(y < height/terrain.SurfaceMap.MapFragment.biomeSize + margin) : (y += 1) {
				preMap[@intCast(x + margin)][@intCast(y + margin)] = self.findClosestBiomeTo(map.pos.wx, map.pos.wy, x, y, worldSeed);
			}
		}
		addTransitionBiomes(ClimateMapFragment.mapEntrysSize + 2*margin, margin, &preMap);
		for(0..ClimateMapFragment.mapEntrysSize) |_x| {
			@memcpy(&map.map[_x], preMap[_x + margin][margin..][0..ClimateMapFragment.mapEntrysSize]);
		}

		// Add some sub-biomes:
		var extraBiomes = main.List(BiomePoint).init(main.stackAllocator);
		defer extraBiomes.deinit();
		for(self.chunks.mem) |chunk| {
			for(chunk.biomesSortedByX) |biome| {
				addSubBiomesOf(biome, map, &extraBiomes, map.pos.wx, map.pos.wy, width, height, worldSeed, .unknown);
			}
		}
		// Add some sub-sub(-sub)*-biomes
		while(extraBiomes.popOrNull()) |biomePoint| {
			addSubBiomesOf(biomePoint, map, &extraBiomes, map.pos.wx, map.pos.wy, width, height, worldSeed, .known);
		}
	}
};
