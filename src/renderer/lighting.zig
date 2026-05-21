const std = @import("std");
const Atomic = std.atomic.Value;
const builtin = @import("builtin");

const main = @import("main");
const blocks = main.blocks;
const chunk = main.chunk;
const BlockPos = chunk.BlockPos;
const chunk_meshing = @import("chunk_meshing.zig");
const ChunkMesh = chunk_meshing.ChunkMesh;
const mesh_storage = @import("mesh_storage.zig");
const QuadIndex = main.models.QuadIndex;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

var memoryPool: main.heap.MemoryPool(ChannelChunk) = .init(main.globalArena);

const LightValue = packed struct(u32) {
	r: u8,
	g: u8,
	b: u8,
	pad: u8 = undefined,

	fn fromArray(arr: [3]u8) LightValue {
		return .{.r = arr[0], .g = arr[1], .b = arr[2]};
	}

	pub fn toArray(self: LightValue) [3]u8 {
		return .{self.r, self.g, self.b};
	}

	pub fn raw(self: LightValue) u32 {
		return @bitCast(self);
	}
};

fn extractColor(in: u32) [3]u8 {
	return .{
		@truncate(in >> 16),
		@truncate(in >> 8),
		@truncate(in),
	};
}

pub const ChannelChunk = struct {
	data: main.utils.PaletteCompressedRegion(LightValue, chunk.chunkVolume),
	mutex: main.utils.Mutex,
	ch: *chunk.Chunk,
	isSun: bool,

	pub fn init(ch: *chunk.Chunk, isSun: bool) *ChannelChunk {
		const self = memoryPool.create();
		self.mutex = .{};
		self.ch = ch;
		self.isSun = isSun;
		self.data.init();
		return self;
	}

	pub fn deinit(self: *ChannelChunk) void {
		self.data.deferredDeinit();
		memoryPool.destroy(self);
	}

	const Entry = struct {
		pos: BlockPos,
		value: [3]u8,
		sourceDir: u3,
		activeValue: u3,
	};

	const ChunkEntries = struct {
		mesh: ?*chunk_meshing.ChunkMesh,
		entries: main.ListUnmanaged(BlockPos),
	};

	pub fn getValue(self: *ChannelChunk, pos: BlockPos) LightValue {
		return self.data.getValue(pos.toIndex());
	}

	fn calculateIncomingOcclusion(result: *[3]u8, block: blocks.Block, voxelSize: u31, neighbor: chunk.Neighbor) void {
		if (block.typ == 0) return;
		if (blocks.meshes.model(block).model().isNeighborOccluded[neighbor.toInt()]) {
			var absorption: [3]u8 = extractColor(block.absorption());
			absorption[0] *|= @intCast(voxelSize);
			absorption[1] *|= @intCast(voxelSize);
			absorption[2] *|= @intCast(voxelSize);
			result[0] -|= absorption[0];
			result[1] -|= absorption[1];
			result[2] -|= absorption[2];
		}
	}

	fn calculateOutgoingOcclusion(result: *[3]u8, block: blocks.Block, voxelSize: u31, neighbor: chunk.Neighbor) void {
		if (block.typ == 0) return;
		const model = blocks.meshes.model(block).model();
		if (model.isNeighborOccluded[neighbor.toInt()] and !model.isNeighborOccluded[neighbor.reverse().toInt()]) { // Avoid calculating the absorption twice.
			var absorption: [3]u8 = extractColor(block.absorption());
			absorption[0] *|= @intCast(voxelSize);
			absorption[1] *|= @intCast(voxelSize);
			absorption[2] *|= @intCast(voxelSize);
			result[0] -|= absorption[0];
			result[1] -|= absorption[1];
			result[2] -|= absorption[2];
		}
	}

	fn propagateDirect(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		var neighborLists: [6]main.ListUnmanaged(Entry) = @splat(.{});
		defer {
			for (&neighborLists) |*list| {
				list.deinit(main.stackAllocator);
			}
		}

		self.mutex.lock();
		while (lightQueue.popFront()) |entry| {
			const pos = entry.pos;
			const oldValue: [3]u8 = self.data.getValue(pos.toIndex()).toArray();
			const newValue: [3]u8 = .{
				@max(entry.value[0], oldValue[0]),
				@max(entry.value[1], oldValue[1]),
				@max(entry.value[2], oldValue[2]),
			};
			if (newValue[0] == oldValue[0] and newValue[1] == oldValue[1] and newValue[2] == oldValue[2]) continue;
			self.data.setValue(pos.toIndex(), .fromArray(newValue));
			for (chunk.Neighbor.iterable) |neighbor| {
				if (neighbor.toInt() == entry.sourceDir) continue;
				const neighborPos, const chunkLocation = pos.neighbor(neighbor);
				var result: Entry = .{.pos = neighborPos, .value = newValue, .sourceDir = neighbor.reverse().toInt(), .activeValue = 0b111};
				if (!self.isSun or neighbor != .dirDown or result.value[0] != 255 or result.value[1] != 255 or result.value[2] != 255) {
					result.value[0] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[1] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[2] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				calculateOutgoingOcclusion(&result.value, self.ch.data.getValue(pos.toIndex()), self.ch.pos.voxelSize, neighbor);
				if (result.value[0] == 0 and result.value[1] == 0 and result.value[2] == 0) continue;
				if (chunkLocation == .inNeighborChunk) {
					neighborLists[neighbor.toInt()].append(main.stackAllocator, result);
					continue;
				}
				calculateIncomingOcclusion(&result.value, self.ch.data.getValue(neighborPos.toIndex()), self.ch.pos.voxelSize, neighbor.reverse());
				if (result.value[0] != 0 or result.value[1] != 0 or result.value[2] != 0) lightQueue.pushBack(result);
			}
		}
		self.data.optimizeLayout();
		self.mutex.unlock();
		self.addSelfToLightRefreshList(lightRefreshList);

		for (chunk.Neighbor.iterable) |neighbor| {
			if (neighborLists[neighbor.toInt()].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighbor(self.ch.pos, self.ch.pos.voxelSize, neighbor) orelse continue;
			neighborMesh.lightingData[@intFromBool(self.isSun)].propagateFromNeighbor(lightQueue, neighborLists[neighbor.toInt()].items, lightRefreshList);
		}
	}

	fn addSelfToLightRefreshList(self: *ChannelChunk, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		for (lightRefreshList.items) |other| {
			if (self.ch.pos.equals(other)) {
				return;
			}
		}
		lightRefreshList.append(self.ch.pos);
	}

	fn propagateDestructive(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), constructiveEntries: *main.ListUnmanaged(ChunkEntries), isFirstBlock: bool, lightRefreshList: *main.List(chunk.ChunkPosition)) main.ListUnmanaged(BlockPos) {
		var neighborLists: [6]main.ListUnmanaged(Entry) = @splat(.{});
		var constructiveList: main.ListUnmanaged(BlockPos) = .{};
		defer {
			for (&neighborLists) |*list| {
				list.deinit(main.stackAllocator);
			}
		}
		var isFirstIteration: bool = isFirstBlock;

		self.mutex.lock();
		while (lightQueue.popFront()) |entry| {
			const pos: BlockPos = entry.pos;
			const oldValue: [3]u8 = self.data.getValue(pos.toIndex()).toArray();
			var activeValue: @Vector(3, bool) = @bitCast(entry.activeValue);
			var append: bool = false;
			if (activeValue[0] and entry.value[0] != oldValue[0]) {
				if (oldValue[0] != 0) append = true;
				activeValue[0] = false;
			}
			if (activeValue[1] and entry.value[1] != oldValue[1]) {
				if (oldValue[1] != 0) append = true;
				activeValue[1] = false;
			}
			if (activeValue[2] and entry.value[2] != oldValue[2]) {
				if (oldValue[2] != 0) append = true;
				activeValue[2] = false;
			}
			const blockLight = if (self.isSun) .{0, 0, 0} else extractColor(self.ch.data.getValue(pos.toIndex()).light());
			if ((activeValue[0] and blockLight[0] != 0) or (activeValue[1] and blockLight[1] != 0) or (activeValue[2] and blockLight[2] != 0)) {
				append = true;
			}
			if (append) {
				constructiveList.append(main.stackAllocator, pos);
			}
			if (entry.value[0] == 0) activeValue[0] = false;
			if (entry.value[1] == 0) activeValue[1] = false;
			if (entry.value[2] == 0) activeValue[2] = false;
			if (isFirstIteration) activeValue = .{true, true, true};
			if (!@reduce(.Or, activeValue)) {
				continue;
			}
			isFirstIteration = false;
			var insertValue: [3]u8 = oldValue;
			if (activeValue[0]) insertValue[0] = 0;
			if (activeValue[1]) insertValue[1] = 0;
			if (activeValue[2]) insertValue[2] = 0;
			self.data.setValue(pos.toIndex(), .fromArray(insertValue));
			for (chunk.Neighbor.iterable) |neighbor| {
				if (neighbor.toInt() == entry.sourceDir) continue;
				const neighborPos, const chunkLocation = pos.neighbor(neighbor);
				var result: Entry = .{.pos = neighborPos, .value = entry.value, .sourceDir = neighbor.reverse().toInt(), .activeValue = @bitCast(activeValue)};
				if (!self.isSun or neighbor != .dirDown or result.value[0] != 255 or result.value[1] != 255 or result.value[2] != 255) {
					result.value[0] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[1] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
					result.value[2] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
				}
				calculateOutgoingOcclusion(&result.value, self.ch.data.getValue(pos.toIndex()), self.ch.pos.voxelSize, neighbor);
				if (chunkLocation == .inNeighborChunk) {
					neighborLists[neighbor.toInt()].append(main.stackAllocator, result);
					continue;
				}
				calculateIncomingOcclusion(&result.value, self.ch.data.getValue(neighborPos.toIndex()), self.ch.pos.voxelSize, neighbor.reverse());
				lightQueue.pushBack(result);
			}
		}
		self.mutex.unlock();
		self.addSelfToLightRefreshList(lightRefreshList);

		for (chunk.Neighbor.iterable) |neighbor| {
			if (neighborLists[neighbor.toInt()].items.len == 0) continue;
			const neighborMesh = mesh_storage.getNeighbor(self.ch.pos, self.ch.pos.voxelSize, neighbor) orelse continue;
			constructiveEntries.append(main.stackAllocator, .{
				.mesh = neighborMesh,
				.entries = neighborMesh.lightingData[@intFromBool(self.isSun)].propagateDestructiveFromNeighbor(lightQueue, neighborLists[neighbor.toInt()].items, constructiveEntries, lightRefreshList),
			});
		}

		return constructiveList;
	}

	fn propagateFromNeighbor(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lights: []const Entry, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		std.debug.assert(lightQueue.isEmpty());
		for (lights) |entry| {
			var result = entry;
			calculateIncomingOcclusion(&result.value, self.ch.data.getValue(entry.pos.toIndex()), self.ch.pos.voxelSize, @enumFromInt(entry.sourceDir));
			if (result.value[0] != 0 or result.value[1] != 0 or result.value[2] != 0) lightQueue.pushBack(result);
		}
		self.propagateDirect(lightQueue, lightRefreshList);
	}

	fn propagateDestructiveFromNeighbor(self: *ChannelChunk, lightQueue: *main.utils.CircularBufferQueue(Entry), lights: []const Entry, constructiveEntries: *main.ListUnmanaged(ChunkEntries), lightRefreshList: *main.List(chunk.ChunkPosition)) main.ListUnmanaged(BlockPos) {
		std.debug.assert(lightQueue.isEmpty());
		for (lights) |entry| {
			var result = entry;
			calculateIncomingOcclusion(&result.value, self.ch.data.getValue(entry.pos.toIndex()), self.ch.pos.voxelSize, @enumFromInt(entry.sourceDir));
			lightQueue.pushBack(result);
		}
		return self.propagateDestructive(lightQueue, constructiveEntries, false, lightRefreshList);
	}

	pub fn propagateLights(self: *ChannelChunk, lights: []const BlockPos, comptime checkNeighbors: bool, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(main.stackAllocator, 1 << 12);
		defer lightQueue.deinit();
		for (lights) |pos| {
			if (self.isSun) {
				lightQueue.pushBack(.{.pos = pos, .value = .{255, 255, 255}, .sourceDir = 6, .activeValue = 0b111});
			} else {
				lightQueue.pushBack(.{.pos = pos, .value = extractColor(self.ch.data.getValue(pos.toIndex()).light()), .sourceDir = 6, .activeValue = 0b111});
			}
		}
		if (checkNeighbors) {
			for (chunk.Neighbor.iterable) |neighbor| {
				const x3: i32 = if (neighbor.isPositive()) chunk.chunkMask else 0;
				var x1: i32 = 0;
				while (x1 < chunk.chunkSize) : (x1 += 1) {
					var x2: i32 = 0;
					while (x2 < chunk.chunkSize) : (x2 += 1) {
						var x: i32 = undefined;
						var y: i32 = undefined;
						var z: i32 = undefined;
						if (neighbor.relX() != 0) {
							x = x3;
							y = x1;
							z = x2;
						} else if (neighbor.relY() != 0) {
							x = x1;
							y = x3;
							z = x2;
						} else {
							x = x2;
							y = x1;
							z = x3;
						}
						const neighborMesh = mesh_storage.getNeighbor(self.ch.pos, self.ch.pos.voxelSize, neighbor) orelse continue;
						const neighborLightChunk = neighborMesh.lightingData[@intFromBool(self.isSun)];
						const pos: BlockPos = .fromCoords(@intCast(x), @intCast(y), @intCast(z));
						const neighborPos, _ = pos.neighbor(neighbor);
						var value: [3]u8 = neighborLightChunk.data.getValue(neighborPos.toIndex()).toArray();
						if (!self.isSun or neighbor != .dirUp or value[0] != 255 or value[1] != 255 or value[2] != 255) {
							value[0] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
							value[1] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
							value[2] -|= 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
						}
						calculateOutgoingOcclusion(&value, self.ch.data.getValue(neighborPos.toIndex()), self.ch.pos.voxelSize, neighbor);
						if (value[0] == 0 and value[1] == 0 and value[2] == 0) continue;
						calculateIncomingOcclusion(&value, self.ch.data.getValue(pos.toIndex()), self.ch.pos.voxelSize, neighbor.reverse());
						if (value[0] != 0 or value[1] != 0 or value[2] != 0) lightQueue.pushBack(.{.pos = pos, .value = value, .sourceDir = neighbor.toInt(), .activeValue = 0b111});
					}
				}
			}
		}
		self.propagateDirect(&lightQueue, lightRefreshList);
	}

	pub fn propagateUniformSun(self: *ChannelChunk, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		std.debug.assert(self.isSun);
		self.mutex.lock();
		self.data.fillUniform(.fromArray(.{255, 255, 255}));
		self.mutex.unlock();
		const val = 255 -| 8*|@as(u8, @intCast(self.ch.pos.voxelSize));
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(main.stackAllocator, 1 << 12);
		defer lightQueue.deinit();
		for (chunk.Neighbor.iterable) |neighbor| {
			if (neighbor == .dirUp) continue;
			const neighborMesh = mesh_storage.getNeighbor(self.ch.pos, self.ch.pos.voxelSize, neighbor) orelse continue;
			var list: [chunk.chunkSize*chunk.chunkSize]Entry = undefined;
			for (0..chunk.chunkSize) |x| {
				for (0..chunk.chunkSize) |y| {
					const entry = &list[x*chunk.chunkSize + y];
					entry.pos, _ = entry.pos.neighbor(neighbor);
					switch (neighbor.vectorComponent()) {
						.x => {
							entry.pos = .{
								.x = if (neighbor.isPositive()) 0 else chunk.chunkSize - 1,
								.y = @intCast(x),
								.z = @intCast(y),
							};
							entry.value = .{val, val, val};
						},
						.y => {
							entry.pos = .{
								.y = if (neighbor.isPositive()) 0 else chunk.chunkSize - 1,
								.x = @intCast(x),
								.z = @intCast(y),
							};
							entry.value = .{val, val, val};
						},
						.z => {
							entry.pos = .{
								.z = if (neighbor.isPositive()) 0 else chunk.chunkSize - 1,
								.x = @intCast(x),
								.y = @intCast(y),
							};
							entry.value = .{255, 255, 255};
						},
					}
					entry.activeValue = 0b111;
					entry.sourceDir = neighbor.reverse().toInt();
				}
			}
			neighborMesh.lightingData[1].propagateFromNeighbor(&lightQueue, &list, lightRefreshList);
		}
	}

	pub fn propagateLightsDestructive(self: *ChannelChunk, lights: []const BlockPos, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		var lightQueue = main.utils.CircularBufferQueue(Entry).init(main.stackAllocator, 1 << 12);
		defer lightQueue.deinit();
		for (lights) |pos| {
			lightQueue.pushBack(.{.pos = pos, .value = self.data.getValue(pos.toIndex()).toArray(), .sourceDir = 6, .activeValue = 0b111});
		}
		var constructiveEntries: main.ListUnmanaged(ChunkEntries) = .{};
		defer constructiveEntries.deinit(main.stackAllocator);
		constructiveEntries.append(main.stackAllocator, .{
			.mesh = null,
			.entries = self.propagateDestructive(&lightQueue, &constructiveEntries, true, lightRefreshList),
		});
		for (constructiveEntries.items) |entries| {
			const mesh = entries.mesh;
			var entryList = entries.entries;
			defer entryList.deinit(main.stackAllocator);
			const channelChunk = if (mesh) |_mesh| _mesh.lightingData[@intFromBool(self.isSun)] else self;
			channelChunk.mutex.lock();
			for (entryList.items) |entry| {
				var value = channelChunk.data.getValue(entry.toIndex()).toArray();
				const light = if (self.isSun) .{0, 0, 0} else extractColor(channelChunk.ch.data.getValue(entry.toIndex()).light());
				value = .{
					@max(value[0], light[0]),
					@max(value[1], light[1]),
					@max(value[2], light[2]),
				};
				if (value[0] == 0 and value[1] == 0 and value[2] == 0) continue;
				channelChunk.data.setValue(entry.toIndex(), .fromArray(.{0, 0, 0}));
				lightQueue.pushBack(.{.pos = entry, .value = value, .sourceDir = 6, .activeValue = 0b111});
			}
			channelChunk.mutex.unlock();
			channelChunk.propagateDirect(&lightQueue, lightRefreshList);
		}
	}
};

const LightVector = @Vector(8, u16);

fn getValues(mesh: *ChunkMesh, pos: chunk.BlockPos) LightVector {
	const blockLight = mesh.lightingData[0].getValue(pos);
	const sunLight = mesh.lightingData[1].getValue(pos);
	std.debug.assert(builtin.cpu.arch.endian() == .little);
	const totalLight = @as(u64, sunLight.raw()) | (@as(u64, blockLight.raw()) << 32);
	return @as(@Vector(8, u8), @bitCast(totalLight));
}

fn getLightAt(parent: *ChunkMesh, x: i32, y: i32, z: i32) LightVector {
	const pos: chunk.BlockPos = .fromCoords(@intCast(x & chunk.chunkMask), @intCast(y & chunk.chunkMask), @intCast(z & chunk.chunkMask));
	if (x == pos.x and y == pos.y and z == pos.z) {
		return getValues(parent, pos);
	}
	const wx = parent.pos.wx +% x*parent.pos.voxelSize;
	const wy = parent.pos.wy +% y*parent.pos.voxelSize;
	const wz = parent.pos.wz +% z*parent.pos.voxelSize;
	const neighborMesh = mesh_storage.getMesh(.{.wx = wx, .wy = wy, .wz = wz, .voxelSize = parent.pos.voxelSize}) orelse return @splat(0);
	return getValues(neighborMesh, pos);
}

fn getCornerLight(parent: *ChunkMesh, pos: Vec3i, normal: Vec3f) LightVector {
	const lightPos = @as(Vec3f, @floatFromInt(pos)) + normal*@as(Vec3f, @splat(0.5)) - @as(Vec3f, @splat(0.5));
	const startPos: Vec3i = @floor(lightPos);
	const interp = lightPos - @floor(lightPos);
	var val: LightVector = @splat(0);
	var dx: i32 = 0;
	while (dx <= 1) : (dx += 1) {
		var dy: i32 = 0;
		while (dy <= 1) : (dy += 1) {
			var dz: i32 = 0;
			while (dz <= 1) : (dz += 1) {
				var weight: f32 = 0;
				if (dx == 0) weight = 1 - interp[0] else weight = interp[0];
				if (dy == 0) weight *= 1 - interp[1] else weight *= interp[1];
				if (dz == 0) weight *= 1 - interp[2] else weight *= interp[2];
				const integerWeight: u16 = @trunc(weight*256);
				const lightVal: LightVector = getLightAt(parent, startPos[0] +% dx, startPos[1] +% dy, startPos[2] +% dz);
				val += lightVal*@as(LightVector, @splat(integerWeight));
			}
		}
	}
	return val/@as(LightVector, @splat(256));
}

fn getLightSampleAligned(parent: *ChunkMesh, pos: Vec3i, direction: chunk.Neighbor) LightVector {
	var lightVal: LightVector = getLightAt(parent, pos[0], pos[1], pos[2]);
	if (parent.pos.voxelSize == 1) {
		const nextVal = getLightAt(parent, pos[0] +% direction.relX(), pos[1] +% direction.relY(), pos[2] +% direction.relZ());
		const diff: LightVector = @min(@as(LightVector, @splat(8)), lightVal -| nextVal);
		lightVal = lightVal -| diff*@as(LightVector, @splat(5))/@as(LightVector, @splat(2));
	}
	return lightVal;
}

fn packLightValues(rawVals: [4]LightVector) [4]u32 {
	var result: [4]u32 = undefined;
	for (0..4) |i| {
		result[i] = (@as(u32, rawVals[i][0] >> 3) << 25 |
			@as(u32, rawVals[i][1] >> 3) << 20 |
			@as(u32, rawVals[i][2] >> 3) << 15 |
			@as(u32, rawVals[i][4] >> 3) << 10 |
			@as(u32, rawVals[i][5] >> 3) << 5 |
			@as(u32, rawVals[i][6] >> 3) << 0);
	}
	return result;
}

pub fn getLight(parent: *ChunkMesh, blockPos: Vec3i, textureIndex: u16, quadIndex: QuadIndex) [4]u32 {
	const quadInfo = quadIndex.quadInfo();
	const extraQuadInfo = quadIndex.extraQuadInfo();
	const normal = quadInfo.normal;
	if (!blocks.meshes.textureOcclusionData[textureIndex].load(.monotonic)) { // No ambient occlusion (→ no smooth lighting)
		const fullValues = getLightAt(parent, blockPos[0], blockPos[1], blockPos[2]);
		return packLightValues(@splat(fullValues));
	}
	if (extraQuadInfo.alignedNormalDirection) |dir| { // Fast path using precomputed samples
		var lightValues: [4]LightVector = @splat(@splat(0));
		for (extraQuadInfo.lightSampleListForAxisAlignedModels) |sample| {
			const lightVal = getLightSampleAligned(parent, blockPos +% sample.offset, dir);
			for (0..4) |i| {
				lightValues[i] += @as(LightVector, @splat(sample.weights[i]))*lightVal;
			}
		}
		for (0..4) |i| {
			lightValues[i] /= @splat(256);
		}
		return packLightValues(lightValues);
	}
	if (extraQuadInfo.hasOnlyCornerVertices) { // Fast path for simple quads.
		var rawVals: [4]LightVector = undefined;
		for (0..4) |i| {
			const vertexPos: Vec3f = quadInfo.corners[i];
			const fullPos = blockPos +% @as(Vec3i, @trunc(vertexPos));
			rawVals[i] = getCornerLight(parent, fullPos, normal);
		}
		return packLightValues(rawVals);
	}
	var rawVals: [4]LightVector = undefined;
	for (0..4) |i| {
		const vertexPos: Vec3f = quadInfo.corners[i];
		const lightPos = vertexPos + @as(Vec3f, @floatFromInt(blockPos));
		const containingBlockPos: Vec3i = @floor(lightPos);
		const interp = std.math.clamp(lightPos - @as(Vec3f, @floatFromInt(containingBlockPos)), @as(Vec3f, @splat(0)), @as(Vec3f, @splat(1)));

		var cornerVals: [2][2][2]LightVector = undefined;
		{
			var dx: u31 = 0;
			while (dx <= 1) : (dx += 1) {
				var dy: u31 = 0;
				while (dy <= 1) : (dy += 1) {
					var dz: u31 = 0;
					while (dz <= 1) : (dz += 1) {
						cornerVals[dx][dy][dz] = getCornerLight(parent, containingBlockPos +% Vec3i{dx, dy, dz}, normal);
					}
				}
			}
		}

		var val: LightVector = @splat(0);
		for (0..2) |dx| {
			for (0..2) |dy| {
				for (0..2) |dz| {
					var weight: f32 = 0;
					if (dx == 0) weight = 1 - interp[0] else weight = interp[0];
					if (dy == 0) weight *= 1 - interp[1] else weight *= interp[1];
					if (dz == 0) weight *= 1 - interp[2] else weight *= interp[2];
					const integerWeight: u16 = @trunc(weight*256);
					val += cornerVals[dx][dy][dz]*@as(LightVector, @splat(integerWeight));
				}
			}
		}
		rawVals[i] = val/@as(LightVector, @splat(256));
	}
	return packLightValues(rawVals);
}
