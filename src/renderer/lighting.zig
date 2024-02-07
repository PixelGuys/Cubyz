const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const blocks = main.blocks;
const chunk = main.chunk;
const chunk_meshing = @import("chunk_meshing.zig");
const mesh_storage = @import("mesh_storage.zig");

const Channel = enum(u8) {
	sun_red = 0,
	sun_green = 1,
	sun_blue = 2,
	red = 3,
	green = 4,
	blue = 5,

	pub fn shift(self: Channel) u5 {
		switch(self) {
			.red, .sun_red => return 16,
			.green, .sun_green => return 8,
			.blue, .sun_blue => return 0,
		}
	}

	pub fn isSun(self: Channel) bool {
		switch(self) {
			.sun_red, .sun_green, .sun_blue => return true,
			.red, .green, .blue => return false,
		}
	}
};

var memoryPool: std.heap.MemoryPool(ChannelChunk) = undefined;
var memoryPoolMutex: std.Thread.Mutex = .{};

pub fn init() void {
	memoryPool = std.heap.MemoryPool(ChannelChunk).init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	memoryPool.deinit();
}

pub const ChannelChunk = struct {
	data: [chunk.chunkVolume]Atomic(u8),
	mutex: std.Thread.Mutex,
	ch: *chunk.Chunk,
	channel: Channel,

	pub fn init(ch: *chunk.Chunk, channel: Channel) *ChannelChunk {
		memoryPoolMutex.lock();
		const self = memoryPool.create() catch unreachable;
		memoryPoolMutex.unlock();
		self.mutex = .{};
		self.ch = ch;
		self.channel = channel;
		@memset(&self.data, Atomic(u8).init(0));
		return self;
	}

	pub fn deinit(self: *ChannelChunk) void {
		memoryPoolMutex.lock();
		memoryPool.destroy(self);
		memoryPoolMutex.unlock();
	}

	const Entry = struct {
		x: u5,
		y: u5,
		z: u5,
		value: u8,
		sourceDir: u3,
	};

	const PositionEntry = struct {
		x: u5,
		y: u5,
		z: u5,
	};

	const ChunkEntries = struct {
		mesh: ?*chunk_meshing.ChunkMesh,
		entries: main.ListUnmanaged(PositionEntry),
	};

	fn propagateDirect(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry)) void {
		var neighborLists: [6]main.ListUnmanaged(Entry) = .{.{}} ** 6;
		defer {
			for(&neighborLists) |*list| {
				list.deinit(lightQueue.allocator);
			}
		}

		self.mutex.lock();
		while(lightQueue.dequeue()) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			if(entry.value <= self.data[index].load(.Unordered)) continue;
			self.data[index].store(entry.value, .Unordered);
			for(chunk.Neighbors.iterable) |neighbor| {
				if(neighbor == entry.sourceDir) continue;
				const nx = entry.x + chunk.Neighbors.relX[neighbor];
				const ny = entry.y + chunk.Neighbors.relY[neighbor];
				const nz = entry.z + chunk.Neighbors.relZ[neighbor];
				var result: Entry = .{.x = @intCast(nx & chunk.chunkMask), .y = @intCast(ny & chunk.chunkMask), .z = @intCast(nz & chunk.chunkMask), .value = entry.value, .sourceDir = neighbor ^ 1};
				if(!self.channel.isSun() or neighbor != chunk.Neighbors.dirDown or result.value != 255) {
					result.value -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				if(result.value == 0) continue;
				if(nx < 0 or nx >= chunk.chunkSize or ny < 0 or ny >= chunk.chunkSize or nz < 0 or nz >= chunk.chunkSize) {
					neighborLists[neighbor].append(lightQueue.allocator, result);
					continue;
				}
				const neighborIndex = chunk.getIndex(nx, ny, nz);
				var absorption: u8 = @intCast(self.ch.blocks[neighborIndex].absorption() >> self.channel.shift() & 255);
				absorption *|= @intCast(self.ch.pos.voxelSize);
				result.value -|= absorption;
				if(result.value != 0) lightQueue.enqueue(result);
			}
		}
		self.mutex.unlock();
		if(mesh_storage.getMeshAndIncreaseRefCount(self.ch.pos)) |mesh| {
			mesh.scheduleLightRefreshAndDecreaseRefCount();
		}

		for(0..6) |neighbor| {
			if(neighborLists[neighbor].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
			defer neighborMesh.decreaseRefCount();
			neighborMesh.lightingData[@intFromEnum(self.channel)].propagateFromNeighbor(lightQueue, neighborLists[neighbor].items);
		}
	}

	fn propagateDestructive(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), constructiveEntries: *main.ListUnmanaged(ChunkEntries), isFirstBlock: bool) main.ListUnmanaged(PositionEntry) {
		var neighborLists: [6]main.ListUnmanaged(Entry) = .{.{}} ** 6;
		var constructiveList: main.ListUnmanaged(PositionEntry) = .{};
		defer {
			for(&neighborLists) |*list| {
				list.deinit(lightQueue.allocator);
			}
		}
		var isFirstIteration: bool = isFirstBlock;

		self.mutex.lock();
		while(lightQueue.dequeue()) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			if(entry.value != self.data[index].load(.Unordered)) {
				if(self.data[index].load(.Unordered) != 0) {
					constructiveList.append(lightQueue.allocator, .{.x = entry.x, .y = entry.y, .z = entry.z});
				}
				continue;
			}
			if(entry.value == 0 and !isFirstIteration) continue;
			isFirstIteration = false;
			self.data[index].store(0, .Unordered);
			for(chunk.Neighbors.iterable) |neighbor| {
				if(neighbor == entry.sourceDir) continue;
				const nx = entry.x + chunk.Neighbors.relX[neighbor];
				const ny = entry.y + chunk.Neighbors.relY[neighbor];
				const nz = entry.z + chunk.Neighbors.relZ[neighbor];
				var result: Entry = .{.x = @intCast(nx & chunk.chunkMask), .y = @intCast(ny & chunk.chunkMask), .z = @intCast(nz & chunk.chunkMask), .value = entry.value, .sourceDir = neighbor ^ 1};
				if(!self.channel.isSun() or neighbor != chunk.Neighbors.dirDown or result.value != 255) {
					result.value -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				if(nx < 0 or nx >= chunk.chunkSize or ny < 0 or ny >= chunk.chunkSize or nz < 0 or nz >= chunk.chunkSize) {
					neighborLists[neighbor].append(lightQueue.allocator, result);
					continue;
				}
				const neighborIndex = chunk.getIndex(nx, ny, nz);
				var absorption: u8 = @intCast(self.ch.blocks[neighborIndex].absorption() >> self.channel.shift() & 255);
				absorption *|= @intCast(self.ch.pos.voxelSize);
				result.value -|= absorption;
				lightQueue.enqueue(result);
			}
		}
		self.mutex.unlock();
		if(mesh_storage.getMeshAndIncreaseRefCount(self.ch.pos)) |mesh| {
			mesh.scheduleLightRefreshAndDecreaseRefCount();
		}

		for(0..6) |neighbor| {
			if(neighborLists[neighbor].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
			constructiveEntries.append(lightQueue.allocator, .{
				.mesh = neighborMesh,
				.entries = neighborMesh.lightingData[@intFromEnum(self.channel)].propagateDestructiveFromNeighbor(lightQueue, neighborLists[neighbor].items, constructiveEntries),
			});
		}

		return constructiveList;
	}

	fn propagateFromNeighbor(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lights: []const Entry) void {
		std.debug.assert(lightQueue.startIndex == lightQueue.endIndex);
		for(lights) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			var result = entry;
			var absorption: u8 = @intCast(self.ch.blocks[index].absorption() >> self.channel.shift() & 255);
			absorption *|= @intCast(self.ch.pos.voxelSize);
			result.value -|= absorption;
			if(result.value != 0) lightQueue.enqueue(result);
		}
		self.propagateDirect(lightQueue);
	}

	fn propagateDestructiveFromNeighbor(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lights: []const Entry, constructiveEntries: *main.ListUnmanaged(ChunkEntries)) main.ListUnmanaged(PositionEntry) {
		std.debug.assert(lightQueue.startIndex == lightQueue.endIndex);
		for(lights) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			var result = entry;
			var absorption: u8 = @intCast(self.ch.blocks[index].absorption() >> self.channel.shift() & 255);
			absorption *|= @intCast(self.ch.pos.voxelSize);
			result.value -|= absorption;
			lightQueue.enqueue(result);
		}
		return self.propagateDestructive(lightQueue, constructiveEntries, false);
	}

	pub fn propagateLights(self: *ChannelChunk, lights: []const [3]u8, comptime checkNeighbors: bool) void {
		const buf = main.stackAllocator.alloc(u8, 1 << 16);
		defer main.stackAllocator.free(buf);
		var bufferFallback = main.utils.BufferFallbackAllocator.init(buf, main.globalAllocator);
		var arena = main.utils.NeverFailingArenaAllocator.init(bufferFallback.allocator());
		defer arena.deinit();
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(arena.allocator(), 1 << 10);
		defer lightQueue.deinit();
		for(lights) |pos| {
			const index = chunk.getIndex(pos[0], pos[1], pos[2]);
			if(self.channel.isSun()) {
				lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = 255, .sourceDir = 6});
			} else {
				lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = @intCast(self.ch.blocks[index].light() >> self.channel.shift() & 255), .sourceDir = 6});
			}
		}
		if(checkNeighbors) {
			for(0..6) |neighbor| {
				const x3: i32 = if(neighbor & 1 == 0) chunk.chunkMask else 0;
				var x1: i32 = 0;
				while(x1 < chunk.chunkSize): (x1 += 1) {
					var x2: i32 = 0;
					while(x2 < chunk.chunkSize): (x2 += 1) {
						var x: i32 = undefined;
						var y: i32 = undefined;
						var z: i32 = undefined;
						if(chunk.Neighbors.relX[neighbor] != 0) {
							x = x3;
							y = x1;
							z = x2;
						} else if(chunk.Neighbors.relY[neighbor] != 0) {
							x = x1;
							y = x3;
							z = x2;
						} else {
							x = x2;
							y = x1;
							z = x3;
						}
						const otherX = x+%chunk.Neighbors.relX[neighbor] & chunk.chunkMask;
						const otherY = y+%chunk.Neighbors.relY[neighbor] & chunk.chunkMask;
						const otherZ = z+%chunk.Neighbors.relZ[neighbor] & chunk.chunkMask;
						const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
						defer neighborMesh.decreaseRefCount();
						const neighborLightChunk = neighborMesh.lightingData[@intFromEnum(self.channel)];
						const index = chunk.getIndex(x, y, z);
						const neighborIndex = chunk.getIndex(otherX, otherY, otherZ);
						var value: u8 = neighborLightChunk.data[neighborIndex].load(.Unordered);
						if(!self.channel.isSun() or neighbor != chunk.Neighbors.dirUp or value != 255) {
							value -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
						}
						if(value == 0) continue;
						var absorption: u8 = @intCast(self.ch.blocks[index].absorption() >> self.channel.shift() & 255);
						absorption *|= @intCast(self.ch.pos.voxelSize);
						value -|= absorption;
						if(value != 0) lightQueue.enqueue(.{.x = @intCast(x), .y = @intCast(y), .z = @intCast(z), .value = value, .sourceDir = @intCast(neighbor)});
					}
				}
			}
		}
		self.propagateDirect(&lightQueue);
	}

	pub fn propagateLightsDestructive(self: *ChannelChunk, lights: []const [3]u8) void {
		const buf = main.stackAllocator.alloc(u8, 1 << 16);
		defer main.stackAllocator.free(buf);
		var bufferFallback = main.utils.BufferFallbackAllocator.init(buf, main.globalAllocator);
		var arena = main.utils.NeverFailingArenaAllocator.init(bufferFallback.allocator());
		defer arena.deinit();
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(arena.allocator(), 1 << 10);
		defer lightQueue.deinit();
		for(lights) |pos| {
			const index = chunk.getIndex(pos[0], pos[1], pos[2]);
			lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = self.data[index].load(.Unordered), .sourceDir = 6});
		}
		var constructiveEntries: main.ListUnmanaged(ChunkEntries) = .{};
		defer constructiveEntries.deinit(arena.allocator());
		constructiveEntries.append(arena.allocator(), .{
			.mesh = null,
			.entries = self.propagateDestructive(&lightQueue, &constructiveEntries, true),
		});
		for(constructiveEntries.items) |entries| {
			const mesh = entries.mesh;
			defer if(mesh) |_mesh| _mesh.decreaseRefCount();
			var entryList = entries.entries;
			defer entryList.deinit(arena.allocator());
			const channelChunk = if(mesh) |_mesh| _mesh.lightingData[@intFromEnum(self.channel)] else self;
			for(entryList.items) |entry| {
				const index = chunk.getIndex(entry.x, entry.y, entry.z);
				const value = channelChunk.data[index].load(.Unordered);
				if(value == 0) continue;
				channelChunk.data[index].store(0, .Unordered);
				lightQueue.enqueue(.{.x = entry.x, .y = entry.y, .z = entry.z, .value = value, .sourceDir = 6});
			}
			channelChunk.propagateDirect(&lightQueue);
		}
	}
};
