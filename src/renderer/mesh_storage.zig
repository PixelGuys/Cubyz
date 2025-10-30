const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const blocks = main.blocks;
const chunk = main.chunk;
const game = main.game;
const network = main.network;
const settings = main.settings;
const utils = main.utils;
const LightMap = main.server.terrain.LightMap;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec4f = vec.Vec4f;
const Mat4f = vec.Mat4f;
const EventStatus = main.block_entity.EventStatus;

const chunk_meshing = @import("chunk_meshing.zig");
const ChunkMesh = chunk_meshing.ChunkMesh;

const ChunkMeshNode = struct {
	mesh: Atomic(?*chunk_meshing.ChunkMesh) = .init(null),
	active: bool = false,
	rendered: bool = false,
	finishedMeshing: bool = false, // Must be synced with mesh.finishedMeshing
	finishedMeshingHigherResolution: u8 = 0, // Must be synced with finishedMeshing of the 8 higher resolution chunks.
	pos: chunk.ChunkPosition = undefined,
	isNeighborLod: [6]bool = @splat(false), // Must be synced with mesh.isNeighborLod
};
const storageSize = 64;
const storageMask = storageSize - 1;
var storageLists: [settings.highestSupportedLod + 1]*[storageSize*storageSize*storageSize]ChunkMeshNode = undefined;
var mapStorageLists: [settings.highestSupportedLod + 1]*[storageSize*storageSize]Atomic(?*LightMap.LightMapFragment) = undefined;
var meshList = main.List(*chunk_meshing.ChunkMesh).init(main.globalAllocator);
var priorityMeshUpdateList: main.utils.ConcurrentQueue(chunk.ChunkPosition) = undefined;
pub var updatableList = main.List(chunk.ChunkPosition).init(main.globalAllocator);
var mapUpdatableList: main.utils.ConcurrentQueue(*LightMap.LightMapFragment) = undefined;
var lastPx: i32 = 0;
var lastPy: i32 = 0;
var lastPz: i32 = 0;
var lastRD: u16 = 0;
var mutex: std.Thread.Mutex = .{};

pub const BlockUpdate = struct {
	x: i32,
	y: i32,
	z: i32,
	newBlock: blocks.Block,
	blockEntityData: []const u8,

	pub fn init(pos: Vec3i, block: blocks.Block, blockEntityData: []const u8) BlockUpdate {
		return .{.x = pos[0], .y = pos[1], .z = pos[2], .newBlock = block, .blockEntityData = blockEntityData};
	}

	pub fn initManaged(allocator: main.heap.NeverFailingAllocator, template: BlockUpdate) BlockUpdate {
		return .{
			.x = template.x,
			.y = template.y,
			.z = template.z,
			.newBlock = template.newBlock,
			.blockEntityData = allocator.dupe(u8, template.blockEntityData),
		};
	}

	pub fn deinitManaged(self: BlockUpdate, allocator: main.heap.NeverFailingAllocator) void {
		allocator.free(self.blockEntityData);
	}
};

var blockUpdateList: main.utils.ConcurrentQueue(BlockUpdate) = undefined;

pub var meshMemoryPool: main.heap.MemoryPool(chunk_meshing.ChunkMesh) = undefined;

pub fn init() void { // MARK: init()
	lastRD = 0;
	blockUpdateList = .init(main.globalAllocator, 16);
	meshMemoryPool = .init(main.globalAllocator);
	for(&storageLists) |*storageList| {
		storageList.* = main.globalAllocator.create([storageSize*storageSize*storageSize]ChunkMeshNode);
		for(storageList.*) |*val| {
			val.* = .{};
		}
	}
	for(&mapStorageLists) |*mapStorageList| {
		mapStorageList.* = main.globalAllocator.create([storageSize*storageSize]Atomic(?*LightMap.LightMapFragment));
		@memset(mapStorageList.*, .init(null));
	}
	priorityMeshUpdateList = .init(main.globalAllocator, 16);
	mapUpdatableList = .init(main.globalAllocator, 16);
}

pub fn deinit() void {
	const olderPx = lastPx;
	const olderPy = lastPy;
	const olderPz = lastPz;
	const olderRD = lastRD;
	lastPx = 0;
	lastPy = 0;
	lastPz = 0;
	lastRD = 0;
	freeOldMeshes(olderPx, olderPy, olderPz, olderRD);
	for(storageLists) |storageList| {
		main.globalAllocator.destroy(storageList);
	}
	for(mapStorageLists) |mapStorageList| {
		main.globalAllocator.destroy(mapStorageList);
	}

	updatableList.clearAndFree();
	while(mapUpdatableList.popFront()) |map| {
		map.deferredDeinit();
	}
	mapUpdatableList.deinit();
	priorityMeshUpdateList.deinit();
	while(blockUpdateList.popFront()) |blockUpdate| {
		blockUpdate.deinitManaged(main.globalAllocator);
	}
	blockUpdateList.deinit();
	meshList.clearAndFree();
	main.heap.GarbageCollection.waitForFreeCompletion();
	meshMemoryPool.deinit();
}

// MARK: getters

fn getNodePointer(pos: chunk.ChunkPosition) *ChunkMeshNode {
	const lod = std.math.log2_int(u31, pos.voxelSize);
	var xIndex = pos.wx >> lod + chunk.chunkShift;
	var yIndex = pos.wy >> lod + chunk.chunkShift;
	var zIndex = pos.wz >> lod + chunk.chunkShift;
	xIndex &= storageMask;
	yIndex &= storageMask;
	zIndex &= storageMask;
	const index = (xIndex*storageSize + yIndex)*storageSize + zIndex;
	return &storageLists[lod][@intCast(index)];
}

fn finishedMeshingMask(x: bool, y: bool, z: bool) u8 {
	return @as(u8, 1) << (@as(u3, @intFromBool(x))*4 + @as(u3, @intFromBool(y))*2 + @as(u3, @intFromBool(z)));
}

fn updateHigherLodNodeFinishedMeshing(pos_: chunk.ChunkPosition, finishedMeshing: bool) void {
	const lod = std.math.log2_int(u31, pos_.voxelSize);
	if(lod == settings.highestLod) return;
	var pos = pos_;
	pos.wx &= ~@as(i32, pos.voxelSize*chunk.chunkSize);
	pos.wy &= ~@as(i32, pos.voxelSize*chunk.chunkSize);
	pos.wz &= ~@as(i32, pos.voxelSize*chunk.chunkSize);
	pos.voxelSize *= 2;
	const mask = finishedMeshingMask(pos.wx != pos_.wx, pos.wy != pos_.wy, pos.wz != pos_.wz);
	const node = getNodePointer(pos);
	if(finishedMeshing) {
		node.finishedMeshingHigherResolution |= mask;
	} else {
		node.finishedMeshingHigherResolution &= ~mask;
	}
}

fn getMapPiecePointer(x: i32, y: i32, voxelSize: u31) *Atomic(?*LightMap.LightMapFragment) {
	const lod = std.math.log2_int(u31, voxelSize);
	var xIndex = x >> lod + LightMap.LightMapFragment.mapShift;
	var yIndex = y >> lod + LightMap.LightMapFragment.mapShift;
	xIndex &= storageMask;
	yIndex &= storageMask;
	const index = xIndex*storageSize + yIndex;
	return &(&mapStorageLists)[lod][@intCast(index)];
}

pub fn getLightMapPiece(x: i32, y: i32, voxelSize: u31) ?*LightMap.LightMapFragment {
	return getMapPiecePointer(x, y, voxelSize).load(.acquire);
}

pub fn getBlockFromRenderThread(x: i32, y: i32, z: i32) ?blocks.Block {
	const node = getNodePointer(.{.wx = x, .wy = y, .wz = z, .voxelSize = 1});
	const mesh = node.mesh.load(.acquire) orelse return null;
	const block = mesh.chunk.getBlock(x & chunk.chunkMask, y & chunk.chunkMask, z & chunk.chunkMask);
	return block;
}

pub fn triggerOnInteractBlockFromRenderThread(x: i32, y: i32, z: i32) main.callbacks.Result {
	const node = getNodePointer(.{.wx = x, .wy = y, .wz = z, .voxelSize = 1});
	const mesh = node.mesh.load(.acquire) orelse return .ignored;
	const block = mesh.chunk.getBlock(x & chunk.chunkMask, y & chunk.chunkMask, z & chunk.chunkMask);
	if(block.blockEntity()) |blockEntity| {
		return blockEntity.onInteract(.{x, y, z}, mesh.chunk);
	}
	// Event was not handled.
	return .ignored;
}

pub fn getLight(wx: i32, wy: i32, wz: i32) ?[6]u8 {
	const node = getNodePointer(.{.wx = wx, .wy = wy, .wz = wz, .voxelSize = 1});
	const mesh = node.mesh.load(.acquire) orelse return null;
	const x = wx & chunk.chunkMask;
	const y = wy & chunk.chunkMask;
	const z = wz & chunk.chunkMask;
	return mesh.lightingData[1].getValue(x, y, z) ++ mesh.lightingData[0].getValue(x, y, z);
}

pub fn getBlockFromAnyLodFromRenderThread(x: i32, y: i32, z: i32) blocks.Block {
	var lod: u5 = 0;
	while(lod <= settings.highestLod) : (lod += 1) {
		const node = getNodePointer(.{.wx = x, .wy = y, .wz = z, .voxelSize = @as(u31, 1) << lod});
		const mesh = node.mesh.load(.acquire) orelse continue;
		const block = mesh.chunk.getBlock(x & chunk.chunkMask << lod, y & chunk.chunkMask << lod, z & chunk.chunkMask << lod);
		return block;
	}
	return blocks.Block{.typ = 0, .data = 0};
}

pub fn getMesh(pos: chunk.ChunkPosition) ?*chunk_meshing.ChunkMesh {
	const lod = std.math.log2_int(u31, pos.voxelSize);
	const mask = ~((@as(i32, 1) << lod + chunk.chunkShift) - 1);
	const node = getNodePointer(pos);
	const mesh = node.mesh.load(.acquire) orelse return null;
	if(pos.wx & mask != mesh.pos.wx or pos.wy & mask != mesh.pos.wy or pos.wz & mask != mesh.pos.wz) {
		return null;
	}
	return mesh;
}

pub fn getMeshFromAnyLod(wx: i32, wy: i32, wz: i32, voxelSize: u31) ?*chunk_meshing.ChunkMesh {
	var lod: u5 = @ctz(voxelSize);
	while(lod < settings.highestLod) : (lod += 1) {
		const mesh = getMesh(.{.wx = wx & ~chunk.chunkMask << lod, .wy = wy & ~chunk.chunkMask << lod, .wz = wz & ~chunk.chunkMask << lod, .voxelSize = @as(u31, 1) << lod});
		return mesh orelse continue;
	}
	return null;
}

pub fn getNeighbor(_pos: chunk.ChunkPosition, resolution: u31, neighbor: chunk.Neighbor) ?*chunk_meshing.ChunkMesh {
	var pos = _pos;
	pos.wx +%= pos.voxelSize*chunk.chunkSize*neighbor.relX();
	pos.wy +%= pos.voxelSize*chunk.chunkSize*neighbor.relY();
	pos.wz +%= pos.voxelSize*chunk.chunkSize*neighbor.relZ();
	pos.voxelSize = resolution;
	return getMesh(pos);
}

fn reduceRenderDistance(fullRenderDistance: i64, reduction: i64) i32 {
	const reducedRenderDistanceSquare: f64 = @floatFromInt(fullRenderDistance*fullRenderDistance - reduction*reduction);
	const reducedRenderDistance: i32 = @intFromFloat(@ceil(@sqrt(@max(0, reducedRenderDistanceSquare))));
	return reducedRenderDistance;
}

fn isInRenderDistance(pos: chunk.ChunkPosition) bool { // MARK: isInRenderDistance()
	const maxRenderDistance = lastRD*chunk.chunkSize*pos.voxelSize;
	const size: u31 = chunk.chunkSize*pos.voxelSize;
	const mask: i32 = size - 1;
	const invMask: i32 = ~mask;

	const minX = lastPx -% maxRenderDistance & invMask;
	const maxX = lastPx +% maxRenderDistance +% size & invMask;
	if(pos.wx -% minX < 0) return false;
	if(pos.wx -% maxX >= 0) return false;
	var deltaX: i64 = @abs(pos.wx +% size/2 -% lastPx);
	deltaX = @max(0, deltaX - size/2);

	const maxYRenderDistance: i32 = reduceRenderDistance(maxRenderDistance, deltaX);
	const minY = lastPy -% maxYRenderDistance & invMask;
	const maxY = lastPy +% maxYRenderDistance +% size & invMask;
	if(pos.wy -% minY < 0) return false;
	if(pos.wy -% maxY >= 0) return false;
	var deltaY: i64 = @abs(pos.wy +% size/2 -% lastPy);
	deltaY = @max(0, deltaY - size/2);

	const maxZRenderDistance: i32 = reduceRenderDistance(maxYRenderDistance, deltaY);
	if(maxZRenderDistance == 0) return false;
	const minZ = lastPz -% maxZRenderDistance & invMask;
	const maxZ = lastPz +% maxZRenderDistance +% size & invMask;
	if(pos.wz -% minZ < 0) return false;
	if(pos.wz -% maxZ >= 0) return false;
	return true;
}

fn isMapInRenderDistance(pos: LightMap.MapFragmentPosition) bool {
	const maxRenderDistance = lastRD*chunk.chunkSize*pos.voxelSize;
	const size: u31 = @as(u31, LightMap.LightMapFragment.mapSize)*pos.voxelSize;
	const mask: i32 = size - 1;
	const invMask: i32 = ~mask;

	const minX = lastPx -% maxRenderDistance & invMask;
	const maxX = lastPx +% maxRenderDistance +% size & invMask;
	if(pos.wx -% minX < 0) return false;
	if(pos.wx -% maxX >= 0) return false;
	var deltaX: i64 = @abs(pos.wx +% size/2 -% lastPx);
	deltaX = @max(0, deltaX - size/2);

	const maxYRenderDistance: i32 = reduceRenderDistance(maxRenderDistance, deltaX);
	if(maxYRenderDistance == 0) return false;
	const minY = lastPy -% maxYRenderDistance & invMask;
	const maxY = lastPy +% maxYRenderDistance +% size & invMask;
	if(pos.wy -% minY < 0) return false;
	if(pos.wy -% maxY >= 0) return false;
	return true;
}

fn freeOldMeshes(olderPx: i32, olderPy: i32, olderPz: i32, olderRD: u16) void { // MARK: freeOldMeshes()
	for(0..settings.highestLod + 1) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = chunk.chunkSize << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size - 1, size) + 2 <= storageSize);

		const minX = olderPx -% maxRenderDistanceOld & invMask;
		const maxX = olderPx +% maxRenderDistanceOld +% size & invMask;
		var x = minX;
		while(x != maxX) : (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			const maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			const maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);

			const minY = olderPy -% maxYRenderDistanceOld & invMask;
			const maxY = olderPy +% maxYRenderDistanceOld +% size & invMask;
			var y = minY;
			while(y != maxY) : (y +%= size) {
				const yIndex = @divExact(y, size) & storageMask;
				var deltaYOld: i64 = @abs(y +% size/2 -% olderPy);
				deltaYOld = @max(0, deltaYOld - size/2);
				var deltaYNew: i64 = @abs(y +% size/2 -% lastPy);
				deltaYNew = @max(0, deltaYNew - size/2);
				var maxZRenderDistanceOld: i32 = reduceRenderDistance(maxYRenderDistanceOld, deltaYOld);
				if(maxZRenderDistanceOld == 0) maxZRenderDistanceOld -= size/2;
				var maxZRenderDistanceNew: i32 = reduceRenderDistance(maxYRenderDistanceNew, deltaYNew);
				if(maxZRenderDistanceNew == 0) maxZRenderDistanceNew -= size/2;

				const minZOld = olderPz -% maxZRenderDistanceOld & invMask;
				const maxZOld = olderPz +% maxZRenderDistanceOld +% size & invMask;
				const minZNew = lastPz -% maxZRenderDistanceNew & invMask;
				const maxZNew = lastPz +% maxZRenderDistanceNew +% size & invMask;

				var zValues: [storageSize]i32 = undefined;
				var zValuesLen: usize = 0;
				if(minZNew -% minZOld > 0) {
					var z = minZOld;
					while(z != minZNew and z != maxZOld) : (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}
				if(maxZOld -% maxZNew > 0) {
					var z = minZOld +% @max(0, maxZNew -% minZOld);
					while(z != maxZOld) : (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}

				for(zValues[0..zValuesLen]) |z| {
					const zIndex = @divExact(z, size) & storageMask;
					const index = (xIndex*storageSize + yIndex)*storageSize + zIndex;

					const node = &storageLists[_lod][@intCast(index)];
					const oldMesh = node.mesh.swap(null, .monotonic);
					node.pos = undefined;
					if(oldMesh) |mesh| {
						node.finishedMeshing = false;
						updateHigherLodNodeFinishedMeshing(mesh.pos, false);
						mesh.deferredDeinit();
					}
					node.isNeighborLod = @splat(false);
				}
			}
		}
	}
	for(0..settings.highestLod + 1) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = @as(u31, LightMap.LightMapFragment.mapSize) << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size - 1, size) + 2 <= storageSize);

		const minX = olderPx -% maxRenderDistanceOld & invMask;
		const maxX = olderPx +% maxRenderDistanceOld +% size & invMask;
		var x = minX;
		while(x != maxX) : (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			var maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			if(maxYRenderDistanceNew == 0) maxYRenderDistanceNew -= size/2;
			var maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);
			if(maxYRenderDistanceOld == 0) maxYRenderDistanceOld -= size/2;

			const minYOld = olderPy -% maxYRenderDistanceOld & invMask;
			const maxYOld = olderPy +% maxYRenderDistanceOld +% size & invMask;
			const minYNew = lastPy -% maxYRenderDistanceNew & invMask;
			const maxYNew = lastPy +% maxYRenderDistanceNew +% size & invMask;

			var yValues: [storageSize]i32 = undefined;
			var yValuesLen: usize = 0;
			if(minYNew -% minYOld > 0) {
				var y = minYOld;
				while(y != minYNew and y != maxYOld) : (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}
			if(maxYOld -% maxYNew > 0) {
				var y = minYOld +% @max(0, maxYNew -% minYOld);
				while(y != maxYOld) : (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}

			for(yValues[0..yValuesLen]) |y| {
				const yIndex = @divExact(y, size) & storageMask;
				const index = xIndex*storageSize + yIndex;

				const oldMap = mapStorageLists[_lod][@intCast(index)].swap(null, .monotonic);
				if(oldMap) |map| {
					map.deferredDeinit();
				}
			}
		}
	}
}

fn createNewMeshes(olderPx: i32, olderPy: i32, olderPz: i32, olderRD: u16, meshRequests: *main.List(chunk.ChunkPosition), mapRequests: *main.List(LightMap.MapFragmentPosition)) void { // MARK: createNewMeshes()
	for(0..settings.highestLod + 1) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = chunk.chunkSize << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size - 1, size) + 2 <= storageSize);

		const minX = lastPx -% maxRenderDistanceNew & invMask;
		const maxX = lastPx +% maxRenderDistanceNew +% size & invMask;
		var x = minX;
		while(x != maxX) : (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			const maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			const maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);

			const minY = lastPy -% maxYRenderDistanceNew & invMask;
			const maxY = lastPy +% maxYRenderDistanceNew +% size & invMask;
			var y = minY;
			while(y != maxY) : (y +%= size) {
				const yIndex = @divExact(y, size) & storageMask;
				var deltaYOld: i64 = @abs(y +% size/2 -% olderPy);
				deltaYOld = @max(0, deltaYOld - size/2);
				var deltaYNew: i64 = @abs(y +% size/2 -% lastPy);
				deltaYNew = @max(0, deltaYNew - size/2);
				var maxZRenderDistanceNew: i32 = reduceRenderDistance(maxYRenderDistanceNew, deltaYNew);
				if(maxZRenderDistanceNew == 0) maxZRenderDistanceNew -= size/2;
				var maxZRenderDistanceOld: i32 = reduceRenderDistance(maxYRenderDistanceOld, deltaYOld);
				if(maxZRenderDistanceOld == 0) maxZRenderDistanceOld -= size/2;

				const minZOld = olderPz -% maxZRenderDistanceOld & invMask;
				const maxZOld = olderPz +% maxZRenderDistanceOld +% size & invMask;
				const minZNew = lastPz -% maxZRenderDistanceNew & invMask;
				const maxZNew = lastPz +% maxZRenderDistanceNew +% size & invMask;

				var zValues: [storageSize]i32 = undefined;
				var zValuesLen: usize = 0;
				if(minZOld -% minZNew > 0) {
					var z = minZNew;
					while(z != minZOld and z != maxZNew) : (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}
				if(maxZNew -% maxZOld > 0) {
					var z = minZNew +% @max(0, maxZOld -% minZNew);
					while(z != maxZNew) : (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}

				for(zValues[0..zValuesLen]) |z| {
					const zIndex = @divExact(z, size) & storageMask;
					const index = (xIndex*storageSize + yIndex)*storageSize + zIndex;
					const pos = chunk.ChunkPosition{.wx = x, .wy = y, .wz = z, .voxelSize = @as(u31, 1) << lod};

					const node = &storageLists[_lod][@intCast(index)];
					node.pos = pos;
					if(node.mesh.load(.acquire)) |mesh| {
						std.debug.assert(std.meta.eql(pos, mesh.pos));
					} else {
						meshRequests.append(pos);
					}
				}
			}
		}
	}
	for(0..settings.highestLod + 1) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = @as(u31, LightMap.LightMapFragment.mapSize) << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size - 1, size) + 2 <= storageSize);

		const minX = lastPx -% maxRenderDistanceNew & invMask;
		const maxX = lastPx +% maxRenderDistanceNew +% size & invMask;
		var x = minX;
		while(x != maxX) : (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			var maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			if(maxYRenderDistanceNew == 0) maxYRenderDistanceNew -= size/2;
			var maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);
			if(maxYRenderDistanceOld == 0) maxYRenderDistanceOld -= size/2;

			const minYOld = olderPy -% maxYRenderDistanceOld & invMask;
			const maxYOld = olderPy +% maxYRenderDistanceOld +% size & invMask;
			const minYNew = lastPy -% maxYRenderDistanceNew & invMask;
			const maxYNew = lastPy +% maxYRenderDistanceNew +% size & invMask;

			var yValues: [storageSize]i32 = undefined;
			var yValuesLen: usize = 0;
			if(minYOld -% minYNew > 0) {
				var y = minYNew;
				while(y != minYOld and y != maxYNew) : (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}
			if(maxYNew -% maxYOld > 0) {
				var y = minYNew +% @max(0, maxYOld -% minYNew);
				while(y != maxYNew) : (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}

			for(yValues[0..yValuesLen]) |y| {
				const yIndex = @divExact(y, size) & storageMask;
				const index = xIndex*storageSize + yIndex;
				const pos = LightMap.MapFragmentPosition{.wx = x, .wy = y, .voxelSize = @as(u31, 1) << lod, .voxelSizeShift = lod};

				const map = mapStorageLists[_lod][@intCast(index)].load(.unordered);
				if(map) |_map| {
					std.debug.assert(std.meta.eql(pos, _map.pos));
				} else {
					mapRequests.append(pos);
				}
			}
		}
	}
}

pub noinline fn updateAndGetRenderChunks(conn: *network.Connection, frustum: *const main.renderer.Frustum, playerPos: Vec3d, renderDistance: u16) []*chunk_meshing.ChunkMesh { // MARK: updateAndGetRenderChunks()
	meshList.clearRetainingCapacity();

	const playerPosInt: Vec3i = @intFromFloat(@floor(playerPos));

	var meshRequests = main.List(chunk.ChunkPosition).init(main.stackAllocator);
	defer meshRequests.deinit();
	var mapRequests = main.List(LightMap.MapFragmentPosition).init(main.stackAllocator);
	defer mapRequests.deinit();

	const olderPx = lastPx;
	const olderPy = lastPy;
	const olderPz = lastPz;
	const olderRD = lastRD;
	mutex.lock();
	lastPx = @intFromFloat(playerPos[0]);
	lastPy = @intFromFloat(playerPos[1]);
	lastPz = @intFromFloat(playerPos[2]);
	lastRD = renderDistance;
	mutex.unlock();
	freeOldMeshes(olderPx, olderPy, olderPz, olderRD);

	createNewMeshes(olderPx, olderPy, olderPz, olderRD, &meshRequests, &mapRequests);

	// Make requests as soon as possible to reduce latency:
	network.Protocols.lightMapRequest.sendRequest(conn, mapRequests.items);
	network.Protocols.chunkRequest.sendRequest(conn, meshRequests.items, .{lastPx, lastPy, lastPz}, lastRD);

	// Finds all visible chunks and lod chunks using a breadth-first hierarchical search.

	var searchList = main.utils.CircularBufferQueue(*ChunkMeshNode).init(main.stackAllocator, 1024);
	defer searchList.deinit();
	{
		var firstPos = chunk.ChunkPosition{
			.wx = @intFromFloat(@floor(playerPos[0])),
			.wy = @intFromFloat(@floor(playerPos[1])),
			.wz = @intFromFloat(@floor(playerPos[2])),
			.voxelSize = 1,
		};
		const lod: u3 = settings.highestLod;
		firstPos.wx &= ~@as(i32, chunk.chunkMask << lod | (@as(i32, 1) << lod) - 1);
		firstPos.wy &= ~@as(i32, chunk.chunkMask << lod | (@as(i32, 1) << lod) - 1);
		firstPos.wz &= ~@as(i32, chunk.chunkMask << lod | (@as(i32, 1) << lod) - 1);
		firstPos.voxelSize <<= lod;
		const node = getNodePointer(firstPos);
		const hasMesh = node.finishedMeshing;
		if(hasMesh) {
			node.active = true;
			node.rendered = true;
			searchList.pushBack(node);
		}
	}
	var nodeList = main.List(*ChunkMeshNode).initCapacity(main.stackAllocator, 1024);
	defer nodeList.deinit();
	while(searchList.popFront()) |node| {
		std.debug.assert(node.finishedMeshing);
		std.debug.assert(node.active);
		if(!node.active) continue;
		node.active = false;

		const pos = node.pos;

		const relPos: Vec3d = @as(Vec3d, @floatFromInt(Vec3i{pos.wx, pos.wy, pos.wz})) - playerPos;
		const relPosFloat: Vec3f = @floatCast(relPos);

		if(pos.voxelSize == @as(i32, 1) << settings.highestLod) {
			for(chunk.Neighbor.iterable) |neighbor| {
				const component = neighbor.extractDirectionComponent(relPosFloat);
				if(neighbor.isPositive() and component + @as(f32, @floatFromInt(chunk.chunkSize*pos.voxelSize)) <= 0) continue;
				if(!neighbor.isPositive() and component >= 0) continue;
				const neighborPos = chunk.ChunkPosition{
					.wx = pos.wx +% neighbor.relX()*chunk.chunkSize*pos.voxelSize,
					.wy = pos.wy +% neighbor.relY()*chunk.chunkSize*pos.voxelSize,
					.wz = pos.wz +% neighbor.relZ()*chunk.chunkSize*pos.voxelSize,
					.voxelSize = pos.voxelSize,
				};
				const node2 = getNodePointer(neighborPos);
				if(!node2.active and node2.finishedMeshing) {
					if(!frustum.testAAB(relPosFloat + @as(Vec3f, @floatFromInt(Vec3i{neighbor.relX()*chunk.chunkSize*pos.voxelSize, neighbor.relY()*chunk.chunkSize*pos.voxelSize, neighbor.relZ()*chunk.chunkSize*pos.voxelSize})), @splat(@floatFromInt(chunk.chunkSize*pos.voxelSize))))
						continue;
					node2.active = true;
					node2.rendered = true;
					searchList.pushBack(node2);
				}
			}
		}

		if(node.finishedMeshingHigherResolution == 0xff) {
			node.rendered = false;
			const lowerLodBit: i32 = pos.voxelSize*chunk.chunkSize >> 1;
			const startPos: chunk.ChunkPosition = .{
				.wx = pos.wx | if((pos.wx | lowerLodBit) -% playerPosInt[0] > 0) lowerLodBit else 0,
				.wy = pos.wy | if((pos.wy | lowerLodBit) -% playerPosInt[1] > 0) lowerLodBit else 0,
				.wz = pos.wz | if((pos.wz | lowerLodBit) -% playerPosInt[2] > 0) lowerLodBit else 0,
				.voxelSize = pos.voxelSize >> 1,
			};
			for(0..2) |dx| {
				for(0..2) |dy| {
					for(0..2) |dz| {
						var nextPos = startPos;
						if(dx == 1) nextPos.wx ^= lowerLodBit;
						if(dy == 1) nextPos.wy ^= lowerLodBit;
						if(dz == 1) nextPos.wz ^= lowerLodBit;
						const node2 = getNodePointer(nextPos);
						const relNextPos: Vec3d = @as(Vec3d, @floatFromInt(Vec3i{nextPos.wx, nextPos.wy, nextPos.wz})) - playerPos;
						if(!frustum.testAAB(@floatCast(relNextPos), @splat(@floatFromInt(chunk.chunkSize*nextPos.voxelSize))))
							continue;
						std.debug.assert(node2.finishedMeshing);
						node2.active = true;
						node2.rendered = true;
						searchList.pushFront(node2);
					}
				}
			}
		} else {
			nodeList.append(node);
		}
	}
	for(nodeList.items) |node| {
		const pos = node.pos;
		var isNeighborLod: [6]bool = @splat(false);
		if(pos.voxelSize != @as(i32, 1) << settings.highestLod) {
			for(chunk.Neighbor.iterable) |neighbor| {
				var neighborPos = chunk.ChunkPosition{
					.wx = pos.wx +% neighbor.relX()*chunk.chunkSize*pos.voxelSize,
					.wy = pos.wy +% neighbor.relY()*chunk.chunkSize*pos.voxelSize,
					.wz = pos.wz +% neighbor.relZ()*chunk.chunkSize*pos.voxelSize,
					.voxelSize = pos.voxelSize,
				};
				neighborPos.wx &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
				neighborPos.wy &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
				neighborPos.wz &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
				neighborPos.voxelSize *= 2;
				const node2 = getNodePointer(neighborPos);
				isNeighborLod[neighbor.toInt()] = node2.finishedMeshingHigherResolution != 0xff;
			}
		}
		if(!std.meta.eql(node.isNeighborLod, isNeighborLod)) {
			const mesh = node.mesh.load(.acquire).?; // no other thread is allowed to overwrite the mesh (unless it's null).
			mesh.isNeighborLod = isNeighborLod;
			node.isNeighborLod = isNeighborLod;
			mesh.uploadData();
		}
	}
	for(nodeList.items) |node| {
		node.rendered = false;
		if(!node.finishedMeshing) continue;

		const mesh = node.mesh.load(.acquire).?; // no other thread is allowed to overwrite the mesh (unless it's null).

		if(mesh.needsMeshUpdate) {
			mesh.uploadData();
			mesh.needsMeshUpdate = false;
		}
		// Remove empty meshes.
		if(!mesh.isEmpty()) {
			meshList.append(mesh);
		}
	}

	return meshList.items;
}

pub fn updateMeshes(targetTime: i64) void { // MARK: updateMeshes()=
	if(!blockUpdateList.isEmpty()) batchUpdateBlocks();

	mutex.lock();
	defer mutex.unlock();
	while(priorityMeshUpdateList.popFront()) |pos| {
		const mesh = getMesh(pos) orelse continue;
		if(!mesh.needsMeshUpdate) {
			continue;
		}
		mesh.needsMeshUpdate = false;
		mutex.unlock();
		defer mutex.lock();
		mesh.uploadData();
		if(std.time.milliTimestamp() >= targetTime) break; // Update at least one mesh.
	}
	while(mapUpdatableList.popFront()) |map| {
		if(!isMapInRenderDistance(map.pos)) {
			map.deferredDeinit();
		} else {
			const mapPointer = getMapPiecePointer(map.pos.wx, map.pos.wy, map.pos.voxelSize).swap(map, .release);
			if(mapPointer) |old| {
				old.deferredDeinit();
			}
		}
	}
	while(updatableList.items.len != 0) {
		// TODO: Find a faster solution than going through the entire list every frame.
		var closestPriority: f32 = -std.math.floatMax(f32);
		var closestIndex: usize = 0;
		const playerPos = game.Player.getEyePosBlocking();
		{
			var i: usize = 0;
			while(i < updatableList.items.len) {
				const pos = updatableList.items[i];
				if(!isInRenderDistance(pos)) {
					_ = updatableList.swapRemove(i);
					mutex.unlock();
					defer mutex.lock();
					continue;
				}
				const priority = pos.getPriority(playerPos);
				if(priority > closestPriority) {
					closestPriority = priority;
					closestIndex = i;
				}
				i += 1;
			}
			if(updatableList.items.len == 0) break;
		}
		const pos = updatableList.swapRemove(closestIndex);
		mutex.unlock();
		defer mutex.lock();
		if(isInRenderDistance(pos)) {
			const node = getNodePointer(pos);
			if(node.finishedMeshing) continue;
			const mesh = getMesh(pos) orelse continue;
			node.finishedMeshing = true;
			mesh.finishedMeshing = true;
			updateHigherLodNodeFinishedMeshing(pos, true);
			mesh.uploadData();
		}
		if(std.time.milliTimestamp() >= targetTime) break; // Update at least one mesh.
	}
}

fn batchUpdateBlocks() void {
	var lightRefreshList = main.List(chunk.ChunkPosition).init(main.stackAllocator);
	defer lightRefreshList.deinit();

	var regenerateMeshList = main.List(*ChunkMesh).init(main.stackAllocator);
	defer regenerateMeshList.deinit();

	// First of all process all the block updates:
	while(blockUpdateList.popFront()) |blockUpdate| {
		defer blockUpdate.deinitManaged(main.globalAllocator);
		const pos = chunk.ChunkPosition{.wx = blockUpdate.x, .wy = blockUpdate.y, .wz = blockUpdate.z, .voxelSize = 1};
		if(getMesh(pos)) |mesh| {
			mesh.updateBlock(blockUpdate.x, blockUpdate.y, blockUpdate.z, blockUpdate.newBlock, blockUpdate.blockEntityData, &lightRefreshList, &regenerateMeshList);
		} // TODO: It seems like we simply ignore the block update if we don't have the mesh yet.
	}
	for(regenerateMeshList.items) |mesh| {
		mesh.generateMesh(&lightRefreshList);
	}
	for(lightRefreshList.items) |pos| {
		ChunkMesh.scheduleLightRefresh(pos);
	}
	for(regenerateMeshList.items) |mesh| {
		mesh.uploadData();
	}
}

// MARK: adders

pub fn addToUpdateList(mesh: *chunk_meshing.ChunkMesh) void {
	mutex.lock();
	defer mutex.unlock();
	if(mesh.finishedMeshing) {
		priorityMeshUpdateList.pushBack(mesh.pos);
		mesh.needsMeshUpdate = true;
	}
}

pub fn addMeshToStorage(mesh: *chunk_meshing.ChunkMesh) error{AlreadyStored, NoLongerNeeded}!void {
	mutex.lock();
	defer mutex.unlock();
	if(!isInRenderDistance(mesh.pos)) {
		return error.NoLongerNeeded;
	}
	const node = getNodePointer(mesh.pos);
	if(node.mesh.cmpxchgStrong(null, mesh, .release, .monotonic) != null) {
		return error.AlreadyStored;
	}
	node.finishedMeshing = mesh.finishedMeshing;
	updateHigherLodNodeFinishedMeshing(mesh.pos, mesh.finishedMeshing);
}

pub fn finishMesh(pos: chunk.ChunkPosition) void {
	mutex.lock();
	defer mutex.unlock();
	updatableList.append(pos);
}

pub const MeshGenerationTask = struct { // MARK: MeshGenerationTask
	mesh: *chunk.Chunk,

	pub const vtable = utils.ThreadPool.VTable{
		.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.utils.castFunctionSelfToAnyopaque(run),
		.clean = main.utils.castFunctionSelfToAnyopaque(clean),
		.taskType = .meshgenAndLighting,
	};

	pub fn schedule(mesh: *chunk.Chunk) void {
		const task = main.globalAllocator.create(MeshGenerationTask);
		task.* = MeshGenerationTask{
			.mesh = mesh,
		};
		main.threadPool.addTask(task, &vtable);
	}

	pub fn getPriority(self: *MeshGenerationTask) f32 {
		return self.mesh.pos.getPriority(game.Player.getPosBlocking()); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
	}

	pub fn isStillNeeded(self: *MeshGenerationTask) bool {
		const distanceSqr = self.mesh.pos.getMinDistanceSquared(@intFromFloat(game.Player.getPosBlocking())); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
		var maxRenderDistance = settings.renderDistance*chunk.chunkSize*self.mesh.pos.voxelSize;
		maxRenderDistance += 2*self.mesh.pos.voxelSize*chunk.chunkSize;
		return distanceSqr < maxRenderDistance*maxRenderDistance;
	}

	pub fn run(self: *MeshGenerationTask) void {
		defer main.globalAllocator.destroy(self);
		const pos = self.mesh.pos;
		const mesh = ChunkMesh.init(pos, self.mesh);
		mesh.generateLightingData() catch mesh.deferredDeinit();
	}

	pub fn clean(self: *MeshGenerationTask) void {
		self.mesh.deinit();
		main.globalAllocator.destroy(self);
	}
};

// MARK: updaters

pub fn updateBlock(update: BlockUpdate) void {
	blockUpdateList.pushBack(BlockUpdate.initManaged(main.globalAllocator, update));
}

pub fn updateChunkMesh(mesh: *chunk.Chunk) void {
	MeshGenerationTask.schedule(mesh);
}

pub fn updateLightMap(map: *LightMap.LightMapFragment) void {
	mapUpdatableList.pushBack(map);
}

// MARK: Block breaking animation

pub fn addBreakingAnimation(pos: Vec3i, breakingProgress: f32) void {
	const animationFrame: usize = @intFromFloat(breakingProgress*@as(f32, @floatFromInt(main.blocks.meshes.blockBreakingTextures.items.len)));
	const texture = main.blocks.meshes.blockBreakingTextures.items[animationFrame];

	const block = getBlockFromRenderThread(pos[0], pos[1], pos[2]) orelse return;
	const model = main.blocks.meshes.model(block).model();

	for(model.internalQuads) |quadIndex| {
		addBreakingAnimationFace(pos, quadIndex, texture, null, block.transparent());
	}
	for(&model.neighborFacingQuads, 0..) |quads, n| {
		for(quads) |quadIndex| {
			addBreakingAnimationFace(pos, quadIndex, texture, @enumFromInt(n), block.transparent());
		}
	}
}

fn addBreakingAnimationFace(pos: Vec3i, quadIndex: main.models.QuadIndex, texture: u16, neighbor: ?chunk.Neighbor, isTransparent: bool) void {
	const worldPos = pos +% if(neighbor) |n| n.relPos() else Vec3i{0, 0, 0};
	const relPos = worldPos & @as(Vec3i, @splat(main.chunk.chunkMask));
	const mesh = getMesh(.{.wx = worldPos[0], .wy = worldPos[1], .wz = worldPos[2], .voxelSize = 1}) orelse return;
	mesh.mutex.lock();
	defer mesh.mutex.unlock();
	const lightIndex = blk: {
		const meshData = if(isTransparent) &mesh.transparentMesh else &mesh.opaqueMesh;
		meshData.lock.lockRead();
		defer meshData.lock.unlockRead();
		for(meshData.completeList.getEverything()) |face| {
			if(face.position.x == relPos[0] and face.position.y == relPos[1] and face.position.z == relPos[2] and face.blockAndQuad.quadIndex == quadIndex) {
				break :blk face.position.lightIndex;
			}
		}
		// The face doesn't exist.
		return;
	};
	mesh.blockBreakingFacesChanged = true;
	mesh.blockBreakingFaces.append(.{
		.position = .{
			.x = @intCast(relPos[0]),
			.y = @intCast(relPos[1]),
			.z = @intCast(relPos[2]),
			.isBackFace = false,
			.lightIndex = lightIndex,
		},
		.blockAndQuad = .{
			.texture = texture,
			.quadIndex = quadIndex,
		},
	});
}

fn removeBreakingAnimationFace(pos: Vec3i, quadIndex: main.models.QuadIndex, neighbor: ?chunk.Neighbor) void {
	const worldPos = pos +% if(neighbor) |n| n.relPos() else Vec3i{0, 0, 0};
	const relPos = worldPos & @as(Vec3i, @splat(main.chunk.chunkMask));
	const mesh = getMesh(.{.wx = worldPos[0], .wy = worldPos[1], .wz = worldPos[2], .voxelSize = 1}) orelse return;
	for(mesh.blockBreakingFaces.items, 0..) |face, i| {
		if(face.position.x == relPos[0] and face.position.y == relPos[1] and face.position.z == relPos[2] and face.blockAndQuad.quadIndex == quadIndex) {
			_ = mesh.blockBreakingFaces.swapRemove(i);
			mesh.blockBreakingFacesChanged = true;
			break;
		}
	}
}

pub fn removeBreakingAnimation(pos: Vec3i) void {
	const block = getBlockFromRenderThread(pos[0], pos[1], pos[2]) orelse return;
	const model = main.blocks.meshes.model(block).model();

	for(model.internalQuads) |quadIndex| {
		removeBreakingAnimationFace(pos, quadIndex, null);
	}
	for(&model.neighborFacingQuads, 0..) |quads, n| {
		for(quads) |quadIndex| {
			removeBreakingAnimationFace(pos, quadIndex, @enumFromInt(n));
		}
	}
}
