const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const blocks = main.blocks;
const chunk = main.chunk;
const chunk_meshing = @import("chunk_meshing.zig");
const mesh_storage = @import("mesh_storage.zig");

var memoryPool: std.heap.MemoryPool(ChannelChunk) = undefined;
var memoryPoolMutex: std.Thread.Mutex = .{};

pub fn init() void {
	memoryPool = std.heap.MemoryPool(ChannelChunk).init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	memoryPool.deinit();
}

fn extractColor(in: u32) [3]u8 {
	return .{
		@truncate(in >> 16),
		@truncate(in >> 8),
		@truncate(in),
	};
}

pub const ChannelChunk = struct {
	data: main.utils.PaletteCompressedRegion([3]u8, chunk.chunkVolume),
	mutex: std.Thread.Mutex,
	ch: *chunk.Chunk,
	isSun: bool,

	pub fn init(ch: *chunk.Chunk, isSun: bool) *ChannelChunk {
		memoryPoolMutex.lock();
		const self = memoryPool.create() catch unreachable;
		memoryPoolMutex.unlock();
		self.mutex = .{};
		self.ch = ch;
		self.isSun = isSun;
		self.data.init();
		return self;
	}

	pub fn deinit(self: *ChannelChunk) void {
		self.data.deinit();
		memoryPoolMutex.lock();
		memoryPool.destroy(self);
		memoryPoolMutex.unlock();
	}

	const Entry = struct {
		x: u5,
		y: u5,
		z: u5,
		value: [3]u8,
		sourceDir: u3,
		activeValue: u3,
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

	pub fn getValue(self: *ChannelChunk, x: i32, y: i32, z: i32) [3]u8 {
		self.mutex.lock();
		defer self.mutex.unlock();
		const index = chunk.getIndex(x, y, z);
		return self.data.getValue(index);
	}

	fn calculateIncomingOcclusion(result: *[3]u8, block: blocks.Block, voxelSize: u31, neighbor: usize) void {
		if(block.typ == 0) return;
		if(main.models.models.items[blocks.meshes.model(block)].isNeighborOccluded[neighbor]) {
			var absorption: [3]u8 = extractColor(block.absorption());
			absorption[0] *|= @intCast(voxelSize);
			absorption[1] *|= @intCast(voxelSize);
			absorption[2] *|= @intCast(voxelSize);
			result[0] -|= absorption[0];
			result[1] -|= absorption[1];
			result[2] -|= absorption[2];
		}
	}

	fn calculateOutgoingOcclusion(result: *[3]u8, block: blocks.Block, voxelSize: u31, neighbor: usize) void {
		if(block.typ == 0) return;
		const model = &main.models.models.items[blocks.meshes.model(block)];
		if(model.isNeighborOccluded[neighbor] and !model.isNeighborOccluded[neighbor ^ 1]) { // Avoid calculating the absorption twice.
			var absorption: [3]u8 = extractColor(block.absorption());
			absorption[0] *|= @intCast(voxelSize);
			absorption[1] *|= @intCast(voxelSize);
			absorption[2] *|= @intCast(voxelSize);
			result[0] -|= absorption[0];
			result[1] -|= absorption[1];
			result[2] -|= absorption[2];
		}
	}

	fn propagateDirect(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry)) void {
		var neighborLists: [6]main.ListUnmanaged(Entry) = .{.{}} ** 6;
		defer {
			for(&neighborLists) |*list| {
				list.deinit(main.stackAllocator);
			}
		}

		self.mutex.lock();
		while(lightQueue.dequeue()) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			const oldValue: [3]u8 = self.data.getValue(index);
			const newValue: [3]u8 = .{
				@max(entry.value[0], oldValue[0]),
				@max(entry.value[1], oldValue[1]),
				@max(entry.value[2], oldValue[2]),
			};
			if(newValue[0] == oldValue[0] and newValue[1] == oldValue[1] and newValue[2] == oldValue[2]) continue;
			self.data.setValue(index, newValue);
			for(chunk.Neighbors.iterable) |neighbor| {
				if(neighbor == entry.sourceDir) continue;
				const nx = entry.x + chunk.Neighbors.relX[neighbor];
				const ny = entry.y + chunk.Neighbors.relY[neighbor];
				const nz = entry.z + chunk.Neighbors.relZ[neighbor];
				var result: Entry = .{.x = @intCast(nx & chunk.chunkMask), .y = @intCast(ny & chunk.chunkMask), .z = @intCast(nz & chunk.chunkMask), .value = newValue, .sourceDir = neighbor ^ 1, .activeValue = 0b111};
				if(!self.isSun or neighbor != chunk.Neighbors.dirDown or result.value[0] != 255 or result.value[1] != 255 or result.value[2] != 255) {
					result.value[0] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[1] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[2] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				calculateOutgoingOcclusion(&result.value, self.ch.data.getValue(index), self.ch.pos.voxelSize, neighbor);
				if(result.value[0] == 0 and result.value[1] == 0 and result.value[2] == 0) continue;
				if(nx < 0 or nx >= chunk.chunkSize or ny < 0 or ny >= chunk.chunkSize or nz < 0 or nz >= chunk.chunkSize) {
					neighborLists[neighbor].append(main.stackAllocator, result);
					continue;
				}
				const neighborIndex = chunk.getIndex(nx, ny, nz);
				calculateIncomingOcclusion(&result.value, self.ch.data.getValue(neighborIndex), self.ch.pos.voxelSize, neighbor ^ 1);
				if(result.value[0] != 0 or result.value[1] != 0 or result.value[2] != 0) lightQueue.enqueue(result);
			}
		}
		self.data.optimizeLayout();
		self.mutex.unlock();
		if(mesh_storage.getMeshAndIncreaseRefCount(self.ch.pos)) |mesh| {
			mesh.scheduleLightRefreshAndDecreaseRefCount();
		}

		for(0..6) |neighbor| {
			if(neighborLists[neighbor].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
			defer neighborMesh.decreaseRefCount();
			neighborMesh.lightingData[@intFromBool(self.isSun)].propagateFromNeighbor(lightQueue, neighborLists[neighbor].items);
		}
	}

	fn propagateDestructive(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), constructiveEntries: *main.ListUnmanaged(ChunkEntries), isFirstBlock: bool) main.ListUnmanaged(PositionEntry) {
		var neighborLists: [6]main.ListUnmanaged(Entry) = .{.{}} ** 6;
		var constructiveList: main.ListUnmanaged(PositionEntry) = .{};
		defer {
			for(&neighborLists) |*list| {
				list.deinit(main.stackAllocator);
			}
		}
		var isFirstIteration: bool = isFirstBlock;

		self.mutex.lock();
		while(lightQueue.dequeue()) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			const oldValue: [3]u8 = self.data.getValue(index);
			var activeValue: @Vector(3, bool) = @bitCast(entry.activeValue);
			var append: bool = false;
			if(activeValue[0] and entry.value[0] != oldValue[0]) {
				if(oldValue[0] != 0) append = true;
				activeValue[0] = false;
			}
			if(activeValue[1] and entry.value[1] != oldValue[1]) {
				if(oldValue[1] != 0) append = true;
				activeValue[1] = false;
			}
			if(activeValue[2] and entry.value[2] != oldValue[2]) {
				if(oldValue[2] != 0) append = true;
				activeValue[2] = false;
			}
			if(append) {
				constructiveList.append(main.stackAllocator, .{.x = entry.x, .y = entry.y, .z = entry.z});
			}
			if(entry.value[0] == 0) activeValue[0] = false;
			if(entry.value[1] == 0) activeValue[1] = false;
			if(entry.value[2] == 0) activeValue[2] = false;
			if(isFirstIteration) activeValue = .{true, true, true};
			if(!@reduce(.Or, activeValue)) {
				continue;
			}
			isFirstIteration = false;
			var insertValue: [3]u8 = oldValue;
			if(activeValue[0]) insertValue[0] = 0;
			if(activeValue[1]) insertValue[1] = 0;
			if(activeValue[2]) insertValue[2] = 0;
			self.data.setValue(index, insertValue);
			for(chunk.Neighbors.iterable) |neighbor| {
				if(neighbor == entry.sourceDir) continue;
				const nx = entry.x + chunk.Neighbors.relX[neighbor];
				const ny = entry.y + chunk.Neighbors.relY[neighbor];
				const nz = entry.z + chunk.Neighbors.relZ[neighbor];
				var result: Entry = .{.x = @intCast(nx & chunk.chunkMask), .y = @intCast(ny & chunk.chunkMask), .z = @intCast(nz & chunk.chunkMask), .value = entry.value, .sourceDir = neighbor ^ 1, .activeValue = @bitCast(activeValue)};
				if(!self.isSun or neighbor != chunk.Neighbors.dirDown or result.value[0] != 255 or result.value[1] != 255 or result.value[2] != 255) {
					result.value[0] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[1] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[2] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				calculateOutgoingOcclusion(&result.value, self.ch.data.getValue(index), self.ch.pos.voxelSize, neighbor);
				if(nx < 0 or nx >= chunk.chunkSize or ny < 0 or ny >= chunk.chunkSize or nz < 0 or nz >= chunk.chunkSize) {
					neighborLists[neighbor].append(main.stackAllocator, result);
					continue;
				}
				const neighborIndex = chunk.getIndex(nx, ny, nz);
				calculateIncomingOcclusion(&result.value, self.ch.data.getValue(neighborIndex), self.ch.pos.voxelSize, neighbor ^ 1);
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
			constructiveEntries.append(main.stackAllocator, .{
				.mesh = neighborMesh,
				.entries = neighborMesh.lightingData[@intFromBool(self.isSun)].propagateDestructiveFromNeighbor(lightQueue, neighborLists[neighbor].items, constructiveEntries),
			});
		}

		return constructiveList;
	}

	fn propagateFromNeighbor(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lights: []const Entry) void {
		std.debug.assert(lightQueue.startIndex == lightQueue.endIndex);
		for(lights) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			var result = entry;
			calculateIncomingOcclusion(&result.value, self.ch.data.getValue(index), self.ch.pos.voxelSize, entry.sourceDir);
			if(result.value[0] != 0 or result.value[1] != 0 or result.value[2] != 0) lightQueue.enqueue(result);
		}
		self.propagateDirect(lightQueue);
	}

	fn propagateDestructiveFromNeighbor(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lights: []const Entry, constructiveEntries: *main.ListUnmanaged(ChunkEntries)) main.ListUnmanaged(PositionEntry) {
		std.debug.assert(lightQueue.startIndex == lightQueue.endIndex);
		for(lights) |entry| {
			const index = chunk.getIndex(entry.x, entry.y, entry.z);
			var result = entry;
			calculateIncomingOcclusion(&result.value, self.ch.data.getValue(index), self.ch.pos.voxelSize, entry.sourceDir);
			lightQueue.enqueue(result);
		}
		return self.propagateDestructive(lightQueue, constructiveEntries, false);
	}

	pub fn propagateLights(self: *ChannelChunk, lights: []const [3]u8, comptime checkNeighbors: bool) void {
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(main.stackAllocator, 1 << 12);
		defer lightQueue.deinit();
		for(lights) |pos| {
			const index = chunk.getIndex(pos[0], pos[1], pos[2]);
			if(self.isSun) {
				lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = .{255, 255, 255}, .sourceDir = 6, .activeValue = 0b111});
			} else {
				lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = extractColor(self.ch.data.getValue(index).light()), .sourceDir = 6, .activeValue = 0b111});
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
						const neighborLightChunk = neighborMesh.lightingData[@intFromBool(self.isSun)];
						neighborLightChunk.mutex.lock();
						defer neighborLightChunk.mutex.unlock();
						const index = chunk.getIndex(x, y, z);
						const neighborIndex = chunk.getIndex(otherX, otherY, otherZ);
						var value: [3]u8 = neighborLightChunk.data.getValue(neighborIndex);
						if(!self.isSun or neighbor != chunk.Neighbors.dirUp or value[0] != 255 or value[1] != 255 or value[2] != 255) {
							value[0] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
							value[1] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
							value[2] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
						}
						calculateOutgoingOcclusion(&value, self.ch.data.getValue(neighborIndex), self.ch.pos.voxelSize, neighbor);
						if(value[0] == 0 and value[1] == 0 and value[2] == 0) continue;
						calculateIncomingOcclusion(&value, self.ch.data.getValue(index), self.ch.pos.voxelSize, neighbor ^ 1);
						if(value[0] != 0 or value[1] != 0 or value[2] != 0) lightQueue.enqueue(.{.x = @intCast(x), .y = @intCast(y), .z = @intCast(z), .value = value, .sourceDir = @intCast(neighbor), .activeValue = 0b111});
					}
				}
			}
		}
		self.propagateDirect(&lightQueue);
	}

	pub fn propagateUniformSun(self: *ChannelChunk) void {
		std.debug.assert(self.isSun);
		self.mutex.lock();
		if(self.data.paletteLength != 1) {
			self.data.deinit();
			self.data.init();
		}
		self.data.palette[0] = .{255, 255, 255};
		self.mutex.unlock();
		const val = 255 -| 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(main.stackAllocator, 1 << 12);
		defer lightQueue.deinit();
		for(chunk.Neighbors.iterable) |neighbor| {
			if(neighbor == chunk.Neighbors.dirUp) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.ch.pos, self.ch.pos.voxelSize, @intCast(neighbor)) orelse continue;
			defer neighborMesh.decreaseRefCount();
			var list: [chunk.chunkSize*chunk.chunkSize]Entry = undefined;
			for(0..chunk.chunkSize) |x| {
				for(0..chunk.chunkSize) |y| {
					const entry = &list[x*chunk.chunkSize + y];
					switch(chunk.Neighbors.vectorComponent[neighbor]) {
						.x => {
							entry.x = if(chunk.Neighbors.isPositive[neighbor]) 0 else chunk.chunkSize - 1;
							entry.y = @intCast(x);
							entry.z = @intCast(y);
							entry.value = .{val, val, val};
						},
						.y => {
							entry.y = if(chunk.Neighbors.isPositive[neighbor]) 0 else chunk.chunkSize - 1;
							entry.x = @intCast(x);
							entry.z = @intCast(y);
							entry.value = .{val, val, val};
						},
						.z => {
							entry.z = if(chunk.Neighbors.isPositive[neighbor]) 0 else chunk.chunkSize - 1;
							entry.x = @intCast(x);
							entry.y = @intCast(y);
							entry.value = .{255, 255, 255};
						},
					}
					entry.activeValue = 0b111;
					entry.sourceDir = neighbor ^ 1;
				}
			}
			neighborMesh.lightingData[1].propagateFromNeighbor(&lightQueue, &list);
		}
	}

	pub fn propagateLightsDestructive(self: *ChannelChunk, lights: []const [3]u8) void {
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(main.stackAllocator, 1 << 12);
		defer lightQueue.deinit();
		self.mutex.lock();
		for(lights) |pos| {
			const index = chunk.getIndex(pos[0], pos[1], pos[2]);
			lightQueue.enqueue(.{.x = @intCast(pos[0]), .y = @intCast(pos[1]), .z = @intCast(pos[2]), .value = self.data.getValue(index), .sourceDir = 6, .activeValue = 0b111});
		}
		self.mutex.unlock();
		var constructiveEntries: main.ListUnmanaged(ChunkEntries) = .{};
		defer constructiveEntries.deinit(main.stackAllocator);
		constructiveEntries.append(main.stackAllocator, .{
			.mesh = null,
			.entries = self.propagateDestructive(&lightQueue, &constructiveEntries, true),
		});
		for(constructiveEntries.items) |entries| {
			const mesh = entries.mesh;
			defer if(mesh) |_mesh| _mesh.decreaseRefCount();
			var entryList = entries.entries;
			defer entryList.deinit(main.stackAllocator);
			const channelChunk = if(mesh) |_mesh| _mesh.lightingData[@intFromBool(self.isSun)] else self;
			channelChunk.mutex.lock();
			for(entryList.items) |entry| {
				const index = chunk.getIndex(entry.x, entry.y, entry.z);
				const value = channelChunk.data.getValue(index);
				if(value[0] == 0 and value[1] == 0 and value[2] == 0) continue;
				channelChunk.data.setValue(index, .{0, 0, 0});
				lightQueue.enqueue(.{.x = entry.x, .y = entry.y, .z = entry.z, .value = value, .sourceDir = 6, .activeValue = 0b111});
			}
			channelChunk.mutex.unlock();
			channelChunk.propagateDirect(&lightQueue);
		}
	}
};
