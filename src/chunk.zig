const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const main = @import("main.zig");
const settings = @import("settings.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;
const Vec3d = vec.Vec3d;

pub const chunkShift: u5 = 5;
pub const chunkShift2: u5 = chunkShift*2;
pub const chunkSize: u31 = 1 << chunkShift;
pub const chunkSizeIterator: [chunkSize]u0 = undefined;
pub const chunkVolume: u31 = 1 << 3*chunkShift;
pub const chunkMask: i32 = chunkSize - 1;

/// Contains a bunch of constants used to describe neighboring blocks.
pub const Neighbor = enum(u3) { // MARK: Neighbor
	dirUp = 0,
	dirDown = 1,
	dirPosX = 2,
	dirNegX = 3,
	dirPosY = 4,
	dirNegY = 5,

	pub inline fn toInt(self: Neighbor) u3 {
		return @intFromEnum(self);
	}

	/// Index to relative position
	pub fn relX(self: Neighbor) i32 {
		const arr = [_]i32 {0, 0, 1, -1, 0, 0};
		return arr[@intFromEnum(self)];
	}
	/// Index to relative position
	pub fn relY(self: Neighbor) i32 {
		const arr = [_]i32 {0, 0, 0, 0, 1, -1};
		return arr[@intFromEnum(self)];
	}
	/// Index to relative position
	pub fn relZ(self: Neighbor) i32 {
		const arr = [_]i32 {1, -1, 0, 0, 0, 0};
		return arr[@intFromEnum(self)];
	}
	/// Index to bitMask for bitmap direction data
	pub inline fn bitMask(self: Neighbor) u6 {
		return @as(u6, 1) << @intFromEnum(self);
	}
	/// To iterate over all neighbors easily
	pub const iterable = [_]Neighbor {@enumFromInt(0), @enumFromInt(1), @enumFromInt(2), @enumFromInt(3), @enumFromInt(4), @enumFromInt(5)};
	/// Marks the two dimension that are orthogonal
	pub fn orthogonalComponents(self: Neighbor) Vec3i {
		const arr = [_]Vec3i {
			.{1, 1, 0},
			.{1, 1, 0},
			.{0, 1, 1},
			.{0, 1, 1},
			.{1, 0, 1},
			.{1, 0, 1},
		};
		return arr[@intFromEnum(self)];
	}
	pub fn textureX(self: Neighbor) Vec3i {
		const arr = [_]Vec3i {
			.{-1, 0, 0},
			.{1, 0, 0},
			.{0, 1, 0},
			.{0, -1, 0},
			.{-1, 0, 0},
			.{1, 0, 0},
		};
		return arr[@intFromEnum(self)];
	}
	pub fn textureY(self: Neighbor) Vec3i {
		const arr = [_]Vec3i {
			.{0, -1, 0},
			.{0, -1, 0},
			.{0, 0, 1},
			.{0, 0, 1},
			.{0, 0, 1},
			.{0, 0, 1},
		};
		return arr[@intFromEnum(self)];
	}

	pub inline fn reverse(self: Neighbor) Neighbor {
		return @enumFromInt(@intFromEnum(self) ^ 1);
	}

	pub inline fn isPositive(self: Neighbor) bool {
		return @intFromEnum(self) & 1 == 0;
	}
	const VectorComponentEnum = enum(u2){x = 0, y = 1, z = 2};
	pub fn vectorComponent(self: Neighbor) VectorComponentEnum {
		const arr = [_]VectorComponentEnum {.z, .z, .x, .x, .y, .y};
		return arr[@intFromEnum(self)];
	}

	pub fn extractDirectionComponent(self: Neighbor, in: anytype) @TypeOf(in[0]) {
		switch(self) {
			inline else => |val| {
				return in[@intFromEnum(val.vectorComponent())];
			}
		}
	}
};

/// Gets the index of a given position inside this chunk.
pub fn getIndex(x: i32, y: i32, z: i32) u32 {
	std.debug.assert((x & chunkMask) == x and (y & chunkMask) == y and (z & chunkMask) == z);
	return (@as(u32, @intCast(x)) << chunkShift2) | (@as(u32, @intCast(y)) << chunkShift) | @as(u32, @intCast(z));
}
/// Gets the x coordinate from a given index inside this chunk.
fn extractXFromIndex(index: usize) i32 {
	return @intCast(index >> chunkShift2 & chunkMask);
}
/// Gets the y coordinate from a given index inside this chunk.
fn extractYFromIndex(index: usize) i32 {
	return @intCast(index >> chunkShift & chunkMask);
}
/// Gets the z coordinate from a given index inside this chunk.
fn extractZFromIndex(index: usize) i32 {
	return @intCast(index & chunkMask);
}

var memoryPool: std.heap.MemoryPoolAligned(Chunk, @alignOf(Chunk)) = undefined;
var memoryPoolMutex: std.Thread.Mutex = .{};
var serverPool: std.heap.MemoryPoolAligned(ServerChunk, @alignOf(ServerChunk)) = undefined;
var serverPoolMutex: std.Thread.Mutex = .{};

pub fn init() void {
	memoryPool = .init(main.globalAllocator.allocator);
	serverPool = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	memoryPool.deinit();
	serverPool.deinit();
}

pub const ChunkPosition = struct { // MARK: ChunkPosition
	wx: i32,
	wy: i32,
	wz: i32,
	voxelSize: u31,
	
	pub fn hashCode(self: ChunkPosition) u32 {
		const shift: u5 = @truncate(@min(@ctz(self.wx), @ctz(self.wy), @ctz(self.wz)));
		return (((@as(u32, @bitCast(self.wx)) >> shift) *% 31 +% (@as(u32, @bitCast(self.wy)) >> shift)) *% 31 +% (@as(u32, @bitCast(self.wz)) >> shift)) *% 31 +% self.voxelSize; // TODO: Can I use one of zigs standard hash functions?
	}

	pub fn equals(self: ChunkPosition, other: anytype) bool {
		if(@typeInfo(@TypeOf(other)) == .optional) {
			if(other) |notNull| {
				return self.equals(notNull);
			}
			return false;
		} else if(@TypeOf(other.*) == ServerChunk) {
			return self.wx == other.super.pos.wx and self.wy == other.super.pos.wy and self.wz == other.super.pos.wz and self.voxelSize == other.super.pos.voxelSize;
		} else if(@typeInfo(@TypeOf(other)) == .pointer) {
			return self.wx == other.pos.wx and self.wy == other.pos.wy and self.wz == other.pos.wz and self.voxelSize == other.pos.voxelSize;
		} else @compileError("Unsupported");
	}

	pub fn getMinDistanceSquared(self: ChunkPosition, playerPosition: Vec3d) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(chunkSize, 2));
		var dx = @abs(@as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0]);
		var dy = @abs(@as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1]);
		var dz = @abs(@as(f64, @floatFromInt(self.wz)) + halfWidth - adjustedPosition[2]);
		dx = @max(0, dx - halfWidth);
		dy = @max(0, dy - halfWidth);
		dz = @max(0, dz - halfWidth);
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getMaxDistanceSquared(self: ChunkPosition, playerPosition: Vec3d) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(chunkSize, 2));
		var dx = @abs(@as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0]);
		var dy = @abs(@as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1]);
		var dz = @abs(@as(f64, @floatFromInt(self.wz)) + halfWidth - adjustedPosition[2]);
		dx = dx + halfWidth;
		dy = dy + halfWidth;
		dz = dz + halfWidth;
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getCenterDistanceSquared(self: ChunkPosition, playerPosition: Vec3d) f64 {
		const adjustedPosition = @mod(playerPosition + @as(Vec3d, @splat(1 << 31)), @as(Vec3d, @splat(1 << 32))) - @as(Vec3d, @splat(1 << 31));
		const halfWidth: f64 = @floatFromInt(self.voxelSize*@divExact(chunkSize, 2));
		const dx = @as(f64, @floatFromInt(self.wx)) + halfWidth - adjustedPosition[0];
		const dy = @as(f64, @floatFromInt(self.wy)) + halfWidth - adjustedPosition[1];
		const dz = @as(f64, @floatFromInt(self.wz)) + halfWidth - adjustedPosition[2];
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getPriority(self: ChunkPosition, playerPos: Vec3d) f32 {
		return -@as(f32, @floatCast(self.getMinDistanceSquared(playerPos)))/@as(f32, @floatFromInt(self.voxelSize*self.voxelSize)) + 2*@as(f32, @floatFromInt(std.math.log2_int(u31, self.voxelSize)*chunkSize*chunkSize));
	}
};

pub const Chunk = struct { // MARK: Chunk
	pos: ChunkPosition,
	data: main.utils.PaletteCompressedRegion(Block, chunkVolume) = undefined,

	width: u31,
	voxelSizeShift: u5,
	voxelSizeMask: i32,
	widthShift: u5,

	pub fn init(pos: ChunkPosition) *Chunk {
		memoryPoolMutex.lock();
		const self = memoryPool.create() catch unreachable;
		memoryPoolMutex.unlock();
		std.debug.assert((pos.voxelSize - 1 & pos.voxelSize) == 0);
		std.debug.assert(@mod(pos.wx, pos.voxelSize) == 0 and @mod(pos.wy, pos.voxelSize) == 0 and @mod(pos.wz, pos.voxelSize) == 0);
		const voxelSizeShift: u5 = @intCast(std.math.log2_int(u31, pos.voxelSize));
		self.* = Chunk {
			.pos = pos,
			.width = pos.voxelSize*chunkSize,
			.voxelSizeShift = voxelSizeShift,
			.voxelSizeMask = pos.voxelSize - 1,
			.widthShift = voxelSizeShift + chunkShift,
		};
		self.data.init();
		return self;
	}

	pub fn deinit(self: *Chunk) void {
		self.data.deinit();
		memoryPoolMutex.lock();
		memoryPool.destroy(@alignCast(self));
		memoryPoolMutex.unlock();
	}

	/// Updates a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlock(self: *Chunk, _x: i32, _y: i32, _z: i32, newBlock: Block) void {
		const x = _x >> self.voxelSizeShift;
		const y = _y >> self.voxelSizeShift;
		const z = _z >> self.voxelSizeShift;
		const index = getIndex(x, y, z);
		self.data.setValue(index, newBlock);
	}

	/// Gets a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn getBlock(self: *const Chunk, _x: i32, _y: i32, _z: i32) Block {
		const x = _x >> self.voxelSizeShift;
		const y = _y >> self.voxelSizeShift;
		const z = _z >> self.voxelSizeShift;
		const index = getIndex(x, y, z);
		return self.data.getValue(index);
	}
};

pub const ServerChunk = struct { // MARK: ServerChunk
	super: Chunk,

	wasChanged: bool = false,
	generated: bool = false,
	wasStored: bool = false,

	mutex: std.Thread.Mutex = .{},
	refCount: std.atomic.Value(u16),

	pub fn initAndIncreaseRefCount(pos: ChunkPosition) *ServerChunk {
		serverPoolMutex.lock();
		const self = serverPool.create() catch unreachable;
		serverPoolMutex.unlock();
		std.debug.assert((pos.voxelSize - 1 & pos.voxelSize) == 0);
		std.debug.assert(@mod(pos.wx, pos.voxelSize) == 0 and @mod(pos.wy, pos.voxelSize) == 0 and @mod(pos.wz, pos.voxelSize) == 0);
		const voxelSizeShift: u5 = @intCast(std.math.log2_int(u31, pos.voxelSize));
		self.* = ServerChunk {
			.super = .{
				.pos = pos,
				.width = pos.voxelSize*chunkSize,
				.voxelSizeShift = voxelSizeShift,
				.voxelSizeMask = pos.voxelSize - 1,
				.widthShift = voxelSizeShift + chunkShift,
			},
			.refCount = .init(1),
		};
		self.super.data.init();
		return self;
	}

	pub fn deinit(self: *ServerChunk) void {
		std.debug.assert(self.refCount.raw == 0);
		if(self.wasChanged) {
			self.save(main.server.world.?);
		}
		self.super.data.deinit();
		serverPoolMutex.lock();
		serverPool.destroy(@alignCast(self));
		serverPoolMutex.unlock();
	}

	pub fn setChanged(self: *ServerChunk) void {
		main.utils.assertLocked(&self.mutex);
		if(!self.wasChanged) {
			self.wasChanged = true;
			self.increaseRefCount();
			main.server.world.?.queueChunkUpdateAndDecreaseRefCount(self);
		}
	}

	pub fn increaseRefCount(self: *ServerChunk) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	pub fn decreaseRefCount(self: *ServerChunk) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 1) {
			self.deinit();
		}
	}

	/// Checks if the given relative coordinates lie within the bounds of this chunk.
	pub fn liesInChunk(self: *const ServerChunk, x: i32, y: i32, z: i32) bool {
		return x >= 0 and x < self.super.width
			and y >= 0 and y < self.super.width
			and z >= 0 and z < self.super.width;
	}

	/// This is useful to convert for loops to work for reduced resolution:
	/// Instead of using
	/// for(int x = start; x < end; x++)
	/// for(int x = chunk.startIndex(start); x < end; x += chunk.getVoxelSize())
	/// should be used to only activate those voxels that are used in Cubyz's downscaling technique.
	pub fn startIndex(self: *const ServerChunk, start: i32) i32 {
		return start+self.super.voxelSizeMask & ~self.super.voxelSizeMask; // Rounds up to the nearest valid voxel coordinate.
	}

	/// Gets a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn getBlock(self: *const ServerChunk, _x: i32, _y: i32, _z: i32) Block {
		main.utils.assertLocked(&self.mutex);
		const x = _x >> self.super.voxelSizeShift;
		const y = _y >> self.super.voxelSizeShift;
		const z = _z >> self.super.voxelSizeShift;
		const index = getIndex(x, y, z);
		return self.super.data.getValue(index);
	}

	/// Updates a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockAndSetChanged(self: *ServerChunk, _x: i32, _y: i32, _z: i32, newBlock: Block) void {
		main.utils.assertLocked(&self.mutex);
		const x = _x >> self.super.voxelSizeShift;
		const y = _y >> self.super.voxelSizeShift;
		const z = _z >> self.super.voxelSizeShift;
		const index = getIndex(x, y, z);
		self.super.data.setValue(index, newBlock);
		if(!self.wasChanged and self.super.pos.voxelSize == 1) {
			self.mutex.unlock();
			defer self.mutex.lock();
			// Store all the neighbor chunks as well:
			var dx: i32 = -@as(i32, chunkSize);
			while(dx <= chunkSize) : (dx += chunkSize) {
				var dy: i32 = -@as(i32, chunkSize);
				while(dy <= chunkSize) : (dy += chunkSize) {
					var dz: i32 = -@as(i32, chunkSize);
					while(dz <= chunkSize) : (dz += chunkSize) {
						if(dx == 0 and dy == 0 and dz == 0) continue;
						const ch = main.server.world.?.getOrGenerateChunkAndIncreaseRefCount(.{
							.wx = self.super.pos.wx +% dx,
							.wy = self.super.pos.wy +% dy,
							.wz = self.super.pos.wz +% dz,
							.voxelSize = 1
						});
						defer ch.decreaseRefCount();
						ch.mutex.lock();
						defer ch.mutex.unlock();
						if(!ch.wasStored) {
							ch.setChanged();
						}
					}
				}
			}
		}
		self.setChanged();
	}

	/// Updates a block if current value is air or the current block is degradable.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockIfDegradable(self: *ServerChunk, _x: i32, _y: i32, _z: i32, newBlock: Block) void {
		main.utils.assertLocked(&self.mutex);
		const x = _x >> self.super.voxelSizeShift;
		const y = _y >> self.super.voxelSizeShift;
		const z = _z >> self.super.voxelSizeShift;
		const index = getIndex(x, y, z);
		const oldBlock = self.super.data.getValue(index);
		if(oldBlock.typ == 0 or oldBlock.degradable()) {
			self.super.data.setValue(index, newBlock);
		}
	}

	/// Updates a block if it is inside this chunk. Should be used in generation to prevent accidently storing these as changes.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockInGeneration(self: *ServerChunk, _x: i32, _y: i32, _z: i32, newBlock: Block) void {
		main.utils.assertLocked(&self.mutex);
		const x = _x >> self.super.voxelSizeShift;
		const y = _y >> self.super.voxelSizeShift;
		const z = _z >> self.super.voxelSizeShift;
		const index = getIndex(x, y, z);
		self.super.data.setValue(index, newBlock);
	}

	/// Updates a block if it is inside this chunk. Should be used in generation to prevent accidently storing these as changes.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockColumnInGeneration(self: *ServerChunk, _x: i32, _y: i32, _zStartInclusive: i32, _zEndInclusive: i32, newBlock: Block) void {
		std.debug.assert(_zStartInclusive <= _zEndInclusive);
		main.utils.assertLocked(&self.mutex);
		const x = _x >> self.super.voxelSizeShift;
		const y = _y >> self.super.voxelSizeShift;
		const zStartInclusive = _zStartInclusive >> self.super.voxelSizeShift;
		const zEndInclusive = _zEndInclusive >> self.super.voxelSizeShift;
		const indexStart = getIndex(x, y, zStartInclusive);
		const indexEnd = getIndex(x, y, zEndInclusive) + 1;
		self.super.data.setValueInColumn(indexStart, indexEnd, newBlock);
	}

	pub fn updateFromLowerResolution(self: *ServerChunk, other: *ServerChunk) void {
		const xOffset = if(other.super.pos.wx != self.super.pos.wx) chunkSize/2 else 0; // Offsets of the lower resolution chunk in this chunk.
		const yOffset = if(other.super.pos.wy != self.super.pos.wy) chunkSize/2 else 0;
		const zOffset = if(other.super.pos.wz != self.super.pos.wz) chunkSize/2 else 0;
		self.mutex.lock();
		defer self.mutex.unlock();
		main.utils.assertLocked(&other.mutex);
		
		var x: u31 = 0;
		while(x < chunkSize/2): (x += 1) {
			var y: u31 = 0;
			while(y < chunkSize/2): (y += 1) {
				var z: u31 = 0;
				while(z < chunkSize/2): (z += 1) {
					// Count the neighbors for each subblock. An transparent block counts 5. A chunk border(unknown block) only counts 1.
					var neighborCount: [8]u31 = undefined;
					var octantBlocks: [8]Block = undefined;
					var maxCount: i32 = 0;
					var dx: u31 = 0;
					while(dx <= 1): (dx += 1) {
						var dy: u31 = 0;
						while(dy <= 1): (dy += 1) {
							var dz: u31 = 0;
							while(dz <= 1): (dz += 1) {
								const index = getIndex(x*2 + dx, y*2 + dy, z*2 + dz);
								const i = dx*4 + dz*2 + dy;
								octantBlocks[i] = other.super.data.getValue(index);
								octantBlocks[i].typ = octantBlocks[i].lodReplacement();
								if(octantBlocks[i].typ == 0) {
									neighborCount[i] = 0;
									continue; // I don't care about air blocks.
								}
								
								var count: u31 = 0;
								for(Neighbor.iterable) |n| {
									const nx = x*2 + dx + n.relX();
									const ny = y*2 + dy + n.relY();
									const nz = z*2 + dz + n.relZ();
									if((nx & chunkMask) == nx and (ny & chunkMask) == ny and (nz & chunkMask) == nz) { // If it's inside the chunk.
										const neighborIndex = getIndex(nx, ny, nz);
										if(other.super.data.getValue(neighborIndex).transparent()) {
											count += 5;
										}
									} else {
										count += 1;
									}
								}
								maxCount = @max(maxCount, count);
								neighborCount[i] = count;
							}
						}
					}
					// Uses a specific permutation here that keeps high resolution patterns in lower resolution.
					const permutationStart = (x & 1)*4 + (z & 1)*2 + (y & 1);
					var block = Block{.typ = 0, .data = 0};
					for(0..8) |i| {
						const appliedPermutation = permutationStart ^ i;
						if(neighborCount[appliedPermutation] >= maxCount - 1) { // Avoid pattern breaks at chunk borders.
							block = octantBlocks[appliedPermutation];
						}
					}
					// Update the block:
					const thisIndex = getIndex(x + xOffset, y + yOffset, z + zOffset);
					self.super.data.setValue(thisIndex, block);
				}
			}
		}

		self.setChanged();
	}

	pub fn save(self: *ServerChunk, world: *main.server.ServerWorld) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		if(!self.wasStored and self.super.pos.voxelSize == 1) {
			// Store the surrounding map pieces as well:
			self.mutex.unlock();
			defer self.mutex.lock();
			const mapStartX = self.super.pos.wx -% main.server.terrain.SurfaceMap.MapFragment.mapSize/2 & ~@as(i32, main.server.terrain.SurfaceMap.MapFragment.mapMask);
			const mapStartY = self.super.pos.wy -% main.server.terrain.SurfaceMap.MapFragment.mapSize/2 & ~@as(i32, main.server.terrain.SurfaceMap.MapFragment.mapMask);
			for(0..2) |dx| {
				for(0..2) |dy| {
					const mapX = mapStartX +% main.server.terrain.SurfaceMap.MapFragment.mapSize*@as(i32, @intCast(dx));
					const mapY = mapStartY +% main.server.terrain.SurfaceMap.MapFragment.mapSize*@as(i32, @intCast(dy));
					const map = main.server.terrain.SurfaceMap.getOrGenerateFragmentAndIncreaseRefCount(mapX, mapY, self.super.pos.voxelSize);
					defer map.decreaseRefCount();
					if(!map.wasStored.swap(true, .monotonic)) {
						map.save(null, .{});
					}
				}
			}
		}
		self.wasStored = true;
		if(self.wasChanged) {
			const pos = self.super.pos;
			const regionSize = pos.voxelSize*chunkSize*main.server.storage.RegionFile.regionSize;
			const regionMask: i32 = regionSize - 1;
			const region = main.server.storage.loadRegionFileAndIncreaseRefCount(pos.wx & ~regionMask, pos.wy & ~regionMask, pos.wz & ~regionMask, pos.voxelSize);
			defer region.decreaseRefCount();
			const data = main.server.storage.ChunkCompression.compressChunk(main.stackAllocator, &self.super);
			defer main.stackAllocator.free(data);
			region.storeChunk(
				data,
				@as(usize, @intCast(pos.wx -% region.pos.wx))/pos.voxelSize/chunkSize,
				@as(usize, @intCast(pos.wy -% region.pos.wy))/pos.voxelSize/chunkSize,
				@as(usize, @intCast(pos.wz -% region.pos.wz))/pos.voxelSize/chunkSize,
			);

			self.wasChanged = false;
			// Update the next lod chunk:
			if(pos.voxelSize != 1 << settings.highestLOD) {
				var nextPos = pos;
				nextPos.wx &= ~@as(i32, pos.voxelSize*chunkSize);
				nextPos.wy &= ~@as(i32, pos.voxelSize*chunkSize);
				nextPos.wz &= ~@as(i32, pos.voxelSize*chunkSize);
				nextPos.voxelSize *= 2;
				const nextHigherLod = world.getOrGenerateChunkAndIncreaseRefCount(nextPos);
				defer nextHigherLod.decreaseRefCount();
				nextHigherLod.updateFromLowerResolution(self);
			}
		}
	}
};