const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
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

const chunk_meshing = @import("chunk_meshing.zig");



const ChunkMeshNode = struct {
	mesh: ?*chunk_meshing.ChunkMesh = null,
	lod: u3 = undefined,
	active: bool = false,
	rendered: bool = false,
	finishedMeshing: bool = false, // Must be synced with mesh.finishedMeshing
	mutex: std.Thread.Mutex = .{},
};
const storageSize = 64;
const storageMask = storageSize - 1;
var storageLists: [settings.highestLOD + 1]*[storageSize*storageSize*storageSize]ChunkMeshNode = undefined;
var mapStorageLists: [settings.highestLOD + 1]*[storageSize*storageSize]?*LightMap.LightMapFragment = undefined;
var meshList = main.List(*chunk_meshing.ChunkMesh).init(main.globalAllocator);
var priorityMeshUpdateList = main.List(*chunk_meshing.ChunkMesh).init(main.globalAllocator);
pub var updatableList = main.List(*chunk_meshing.ChunkMesh).init(main.globalAllocator);
var mapUpdatableList = main.List(*LightMap.LightMapFragment).init(main.globalAllocator);
var clearList = main.List(*chunk_meshing.ChunkMesh).init(main.globalAllocator);
var lastPx: i32 = 0;
var lastPy: i32 = 0;
var lastPz: i32 = 0;
var lastRD: u16 = 0;
var mutex = std.Thread.Mutex{};
var blockUpdateMutex = std.Thread.Mutex{};
const BlockUpdate = struct {
	x: i32,
	y: i32,
	z: i32,
	newBlock: blocks.Block,
};
var blockUpdateList: main.List(BlockUpdate) = undefined;

pub fn init() void { // MARK: init()
	lastRD = 0;
	blockUpdateList = .init(main.globalAllocator);
	for(&storageLists) |*storageList| {
		storageList.* = main.globalAllocator.create([storageSize*storageSize*storageSize]ChunkMeshNode);
		for(storageList.*) |*val| {
			val.* = .{};
		}
	}
	for(&mapStorageLists) |*mapStorageList| {
		mapStorageList.* = main.globalAllocator.create([storageSize*storageSize]?*LightMap.LightMapFragment);
		@memset(mapStorageList.*, null);
	}
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

	for(updatableList.items) |mesh| {
		mesh.decreaseRefCount();
	}
	updatableList.clearAndFree();
	for(mapUpdatableList.items) |map| {
		map.decreaseRefCount();
	}
	mapUpdatableList.clearAndFree();
	for(priorityMeshUpdateList.items) |mesh| {
		mesh.decreaseRefCount();
	}
	priorityMeshUpdateList.clearAndFree();
	blockUpdateList.clearAndFree();
	meshList.clearAndFree();
	for(clearList.items) |mesh| {
		mesh.deinit();
		main.globalAllocator.destroy(mesh);
	}
	clearList.clearAndFree();
}

// MARK: getters

fn getNodePointer(pos: chunk.ChunkPosition) *ChunkMeshNode {
	const lod = std.math.log2_int(u31, pos.voxelSize);
	var xIndex = pos.wx >> lod+chunk.chunkShift;
	var yIndex = pos.wy >> lod+chunk.chunkShift;
	var zIndex = pos.wz >> lod+chunk.chunkShift;
	xIndex &= storageMask;
	yIndex &= storageMask;
	zIndex &= storageMask;
	const index = (xIndex*storageSize + yIndex)*storageSize + zIndex;
	return &storageLists[lod][@intCast(index)];
}

fn getMapPiecePointer(x: i32, y: i32, voxelSize: u31) *?*LightMap.LightMapFragment {
	const lod = std.math.log2_int(u31, voxelSize);
	var xIndex = x >> lod+LightMap.LightMapFragment.mapShift;
	var yIndex = y >> lod+LightMap.LightMapFragment.mapShift;
	xIndex &= storageMask;
	yIndex &= storageMask;
	const index = xIndex*storageSize + yIndex;
	return &(&mapStorageLists)[lod][@intCast(index)];
}

pub fn getLightMapPieceAndIncreaseRefCount(x: i32, y: i32, voxelSize: u31) ?*LightMap.LightMapFragment {
	mutex.lock();
	defer mutex.unlock();
	const result: *LightMap.LightMapFragment = getMapPiecePointer(x, y, voxelSize).* orelse {
		return null;
	};
	result.increaseRefCount();
	return result;
}

pub fn getBlock(x: i32, y: i32, z: i32) ?blocks.Block {
	const node = getNodePointer(.{.wx = x, .wy = y, .wz = z, .voxelSize=1});
	node.mutex.lock();
	defer node.mutex.unlock();
	const mesh = node.mesh orelse return null;
	const block = mesh.chunk.getBlock(x & chunk.chunkMask, y & chunk.chunkMask, z & chunk.chunkMask);
	return block;
}

pub fn getBlockFromAnyLod(x: i32, y: i32, z: i32) blocks.Block {
	var lod: u5 = 0;
	while(lod < settings.highestLOD) : (lod += 1) {
		const node = getNodePointer(.{.wx = x, .wy = y, .wz = z, .voxelSize=@as(u31, 1) << lod});
		node.mutex.lock();
		defer node.mutex.unlock();
		const mesh = node.mesh orelse continue;
		const block = mesh.chunk.getBlock(x & chunk.chunkMask<<lod, y & chunk.chunkMask<<lod, z & chunk.chunkMask<<lod);
		return block;
	}
	return blocks.Block{.typ = 0, .data = 0};
}

pub fn getMeshAndIncreaseRefCount(pos: chunk.ChunkPosition) ?*chunk_meshing.ChunkMesh {
	const lod = std.math.log2_int(u31, pos.voxelSize);
	const mask = ~((@as(i32, 1) << lod+chunk.chunkShift) - 1);
	const node = getNodePointer(pos);
	node.mutex.lock();
	const mesh = node.mesh orelse {
		node.mutex.unlock();
		return null;
	};
	mesh.increaseRefCount();
	node.mutex.unlock();
	if(pos.wx & mask != mesh.pos.wx or pos.wy & mask != mesh.pos.wy or pos.wz & mask != mesh.pos.wz) {
		mesh.decreaseRefCount();
		return null;
	}
	return mesh;
}

pub fn getMeshFromAnyLodAndIncreaseRefCount(wx: i32, wy: i32, wz: i32, voxelSize: u31) ?*chunk_meshing.ChunkMesh {
	var lod: u5 = @ctz(voxelSize);
	while(lod < settings.highestLOD) : (lod += 1) {
		const mesh = getMeshAndIncreaseRefCount(.{.wx = wx & ~chunk.chunkMask<<lod, .wy = wy & ~chunk.chunkMask<<lod, .wz = wz & ~chunk.chunkMask<<lod, .voxelSize=@as(u31, 1) << lod});
		return mesh orelse continue;
	}
	return null;
}

pub fn getNeighborAndIncreaseRefCount(_pos: chunk.ChunkPosition, resolution: u31, neighbor: chunk.Neighbor) ?*chunk_meshing.ChunkMesh {
	var pos = _pos;
	pos.wx +%= pos.voxelSize*chunk.chunkSize*neighbor.relX();
	pos.wy +%= pos.voxelSize*chunk.chunkSize*neighbor.relY();
	pos.wz +%= pos.voxelSize*chunk.chunkSize*neighbor.relZ();
	pos.voxelSize = resolution;
	return getMeshAndIncreaseRefCount(pos);
}

fn reduceRenderDistance(fullRenderDistance: i64, reduction: i64) i32 {
	const reducedRenderDistanceSquare: f64 = @floatFromInt(fullRenderDistance*fullRenderDistance - reduction*reduction);
	const reducedRenderDistance: i32 = @intFromFloat(@ceil(@sqrt(@max(0, reducedRenderDistanceSquare))));
	return reducedRenderDistance;
}

fn isInRenderDistance(pos: chunk.ChunkPosition) bool {  // MARK: isInRenderDistance()
	const maxRenderDistance = lastRD*chunk.chunkSize*pos.voxelSize;
	const size: u31 = chunk.chunkSize*pos.voxelSize;
	const mask: i32 = size - 1;
	const invMask: i32 = ~mask;

	const minX = lastPx-%maxRenderDistance & invMask;
	const maxX = lastPx+%maxRenderDistance+%size & invMask;
	if(pos.wx -% minX < 0) return false;
	if(pos.wx -% maxX >= 0) return false;
	var deltaX: i64 = @abs(pos.wx +% size/2 -% lastPx);
	deltaX = @max(0, deltaX - size/2);

	const maxYRenderDistance: i32 = reduceRenderDistance(maxRenderDistance, deltaX);
	const minY = lastPy-%maxYRenderDistance & invMask;
	const maxY = lastPy+%maxYRenderDistance+%size & invMask;
	if(pos.wy -% minY < 0) return false;
	if(pos.wy -% maxY >= 0) return false;
	var deltaY: i64 = @abs(pos.wy +% size/2 -% lastPy);
	deltaY = @max(0, deltaY - size/2);

	const maxZRenderDistance: i32 = reduceRenderDistance(maxYRenderDistance, deltaY);
	if(maxZRenderDistance == 0) return false;
	const minZ = lastPz-%maxZRenderDistance & invMask;
	const maxZ = lastPz+%maxZRenderDistance+%size & invMask;
	if(pos.wz -% minZ < 0) return false;
	if(pos.wz -% maxZ >= 0) return false;
	return true;
}

fn isMapInRenderDistance(pos: LightMap.MapFragmentPosition) bool {
	const maxRenderDistance = lastRD*chunk.chunkSize*pos.voxelSize;
	const size: u31 = @as(u31, LightMap.LightMapFragment.mapSize)*pos.voxelSize;
	const mask: i32 = size - 1;
	const invMask: i32 = ~mask;

	const minX = lastPx-%maxRenderDistance & invMask;
	const maxX = lastPx+%maxRenderDistance+%size & invMask;
	if(pos.wx -% minX < 0) return false;
	if(pos.wx -% maxX >= 0) return false;
	var deltaX: i64 = @abs(pos.wx +% size/2 -% lastPx);
	deltaX = @max(0, deltaX - size/2);

	const maxYRenderDistance: i32 = reduceRenderDistance(maxRenderDistance, deltaX);
	if(maxYRenderDistance == 0) return false;
	const minY = lastPy-%maxYRenderDistance & invMask;
	const maxY = lastPy+%maxYRenderDistance+%size & invMask;
	if(pos.wy -% minY < 0) return false;
	if(pos.wy -% maxY >= 0) return false;
	return true;
}

fn freeOldMeshes(olderPx: i32, olderPy: i32, olderPz: i32, olderRD: u16) void { // MARK: freeOldMeshes()
	for(0..storageLists.len) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = chunk.chunkSize << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size-1, size) + 2 <= storageSize);

		const minX = olderPx-%maxRenderDistanceOld & invMask;
		const maxX = olderPx+%maxRenderDistanceOld+%size & invMask;
		var x = minX;
		while(x != maxX): (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			const maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			const maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);

			const minY = olderPy-%maxYRenderDistanceOld & invMask;
			const maxY = olderPy+%maxYRenderDistanceOld+%size & invMask;
			var y = minY;
			while(y != maxY): (y +%= size) {
				const yIndex = @divExact(y, size) & storageMask;
				var deltaYOld: i64 = @abs(y +% size/2 -% olderPy);
				deltaYOld = @max(0, deltaYOld - size/2);
				var deltaYNew: i64 = @abs(y +% size/2 -% lastPy);
				deltaYNew = @max(0, deltaYNew - size/2);
				var maxZRenderDistanceOld: i32 = reduceRenderDistance(maxYRenderDistanceOld, deltaYOld);
				if(maxZRenderDistanceOld == 0) maxZRenderDistanceOld -= size/2;
				var maxZRenderDistanceNew: i32 = reduceRenderDistance(maxYRenderDistanceNew, deltaYNew);
				if(maxZRenderDistanceNew == 0) maxZRenderDistanceNew -= size/2;

				const minZOld = olderPz-%maxZRenderDistanceOld & invMask;
				const maxZOld = olderPz+%maxZRenderDistanceOld+%size & invMask;
				const minZNew = lastPz-%maxZRenderDistanceNew & invMask;
				const maxZNew = lastPz+%maxZRenderDistanceNew+%size & invMask;

				var zValues: [storageSize]i32 = undefined;
				var zValuesLen: usize = 0;
				if(minZNew -% minZOld > 0) {
					var z = minZOld;
					while(z != minZNew and z != maxZOld): (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}
				if(maxZOld -% maxZNew > 0) {
					var z = minZOld +% @max(0, maxZNew -% minZOld);
					while(z != maxZOld): (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}

				for(zValues[0..zValuesLen]) |z| {
					const zIndex = @divExact(z, size) & storageMask;
					const index = (xIndex*storageSize + yIndex)*storageSize + zIndex;
					
					const node = &storageLists[_lod][@intCast(index)];
					node.mutex.lock();
					const oldMesh = node.mesh;
					node.mesh = null;
					node.finishedMeshing = false;
					node.mutex.unlock();
					if(oldMesh) |mesh| {
						mesh.decreaseRefCount();
					}
				}
			}
		}
	}
	for(0..mapStorageLists.len) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = @as(u31, LightMap.LightMapFragment.mapSize) << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size-1, size) + 2 <= storageSize);

		const minX = olderPx-%maxRenderDistanceOld & invMask;
		const maxX = olderPx+%maxRenderDistanceOld+%size & invMask;
		var x = minX;
		while(x != maxX): (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			var maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			if(maxYRenderDistanceNew == 0) maxYRenderDistanceNew -= size/2;
			var maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);
			if(maxYRenderDistanceOld == 0) maxYRenderDistanceOld -= size/2;

			const minYOld = olderPy-%maxYRenderDistanceOld & invMask;
			const maxYOld = olderPy+%maxYRenderDistanceOld+%size & invMask;
			const minYNew = lastPy-%maxYRenderDistanceNew & invMask;
			const maxYNew = lastPy+%maxYRenderDistanceNew+%size & invMask;

			var yValues: [storageSize]i32 = undefined;
			var yValuesLen: usize = 0;
			if(minYNew -% minYOld > 0) {
				var y = minYOld;
				while(y != minYNew and y != maxYOld): (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}
			if(maxYOld -% maxYNew > 0) {
				var y = minYOld +% @max(0, maxYNew -% minYOld);
				while(y != maxYOld): (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}

			for(yValues[0..yValuesLen]) |y| {
				const yIndex = @divExact(y, size) & storageMask;
				const index = xIndex*storageSize + yIndex;
				
				const mapPointer = &mapStorageLists[_lod][@intCast(index)];
				mutex.lock();
				const oldMap = mapPointer.*;
				mapPointer.* = null;
				mutex.unlock();
				if(oldMap) |map| {
					map.decreaseRefCount();
				}
			}
		}
	}
}

fn createNewMeshes(olderPx: i32, olderPy: i32, olderPz: i32, olderRD: u16, meshRequests: *main.List(chunk.ChunkPosition), mapRequests: *main.List(LightMap.MapFragmentPosition)) void { // MARK: createNewMeshes()
	for(0..storageLists.len) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = chunk.chunkSize << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size-1, size) + 2 <= storageSize);

		const minX = lastPx-%maxRenderDistanceNew & invMask;
		const maxX = lastPx+%maxRenderDistanceNew+%size & invMask;
		var x = minX;
		while(x != maxX): (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			const maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			const maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);

			const minY = lastPy-%maxYRenderDistanceNew & invMask;
			const maxY = lastPy+%maxYRenderDistanceNew+%size & invMask;
			var y = minY;
			while(y != maxY): (y +%= size) {
				const yIndex = @divExact(y, size) & storageMask;
				var deltaYOld: i64 = @abs(y +% size/2 -% olderPy);
				deltaYOld = @max(0, deltaYOld - size/2);
				var deltaYNew: i64 = @abs(y +% size/2 -% lastPy);
				deltaYNew = @max(0, deltaYNew - size/2);
				var maxZRenderDistanceNew: i32 = reduceRenderDistance(maxYRenderDistanceNew, deltaYNew);
				if(maxZRenderDistanceNew == 0) maxZRenderDistanceNew -= size/2;
				var maxZRenderDistanceOld: i32 = reduceRenderDistance(maxYRenderDistanceOld, deltaYOld);
				if(maxZRenderDistanceOld == 0) maxZRenderDistanceOld -= size/2;

				const minZOld = olderPz-%maxZRenderDistanceOld & invMask;
				const maxZOld = olderPz+%maxZRenderDistanceOld+%size & invMask;
				const minZNew = lastPz-%maxZRenderDistanceNew & invMask;
				const maxZNew = lastPz+%maxZRenderDistanceNew+%size & invMask;

				var zValues: [storageSize]i32 = undefined;
				var zValuesLen: usize = 0;
				if(minZOld -% minZNew > 0) {
					var z = minZNew;
					while(z != minZOld and z != maxZNew): (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}
				if(maxZNew -% maxZOld > 0) {
					var z = minZNew +% @max(0, maxZOld -% minZNew);
					while(z != maxZNew): (z +%= size) {
						zValues[zValuesLen] = z;
						zValuesLen += 1;
					}
				}

				for(zValues[0..zValuesLen]) |z| {
					const zIndex = @divExact(z, size) & storageMask;
					const index = (xIndex*storageSize + yIndex)*storageSize + zIndex;
					const pos = chunk.ChunkPosition{.wx=x, .wy=y, .wz=z, .voxelSize=@as(u31, 1)<<lod};

					const node = &storageLists[_lod][@intCast(index)];
					node.mutex.lock();
					if(node.mesh) |mesh| {
						std.debug.assert(std.meta.eql(pos, mesh.pos));
					} else {
						meshRequests.append(pos);
					}
					node.mutex.unlock();
				}
			}
		}
	}
	for(0..mapStorageLists.len) |_lod| {
		const lod: u5 = @intCast(_lod);
		const maxRenderDistanceNew = lastRD*chunk.chunkSize << lod;
		const maxRenderDistanceOld = olderRD*chunk.chunkSize << lod;
		const size: u31 = @as(u31, LightMap.LightMapFragment.mapSize) << lod;
		const mask: i32 = size - 1;
		const invMask: i32 = ~mask;

		std.debug.assert(@divFloor(2*maxRenderDistanceNew + size-1, size) + 2 <= storageSize);

		const minX = lastPx-%maxRenderDistanceNew & invMask;
		const maxX = lastPx+%maxRenderDistanceNew+%size & invMask;
		var x = minX;
		while(x != maxX): (x +%= size) {
			const xIndex = @divExact(x, size) & storageMask;
			var deltaXNew: i64 = @abs(x +% size/2 -% lastPx);
			deltaXNew = @max(0, deltaXNew - size/2);
			var deltaXOld: i64 = @abs(x +% size/2 -% olderPx);
			deltaXOld = @max(0, deltaXOld - size/2);
			var maxYRenderDistanceNew: i32 = reduceRenderDistance(maxRenderDistanceNew, deltaXNew);
			if(maxYRenderDistanceNew == 0) maxYRenderDistanceNew -= size/2;
			var maxYRenderDistanceOld: i32 = reduceRenderDistance(maxRenderDistanceOld, deltaXOld);
			if(maxYRenderDistanceOld == 0) maxYRenderDistanceOld -= size/2;

			const minYOld = olderPy-%maxYRenderDistanceOld & invMask;
			const maxYOld = olderPy+%maxYRenderDistanceOld+%size & invMask;
			const minYNew = lastPy-%maxYRenderDistanceNew & invMask;
			const maxYNew = lastPy+%maxYRenderDistanceNew+%size & invMask;

			var yValues: [storageSize]i32 = undefined;
			var yValuesLen: usize = 0;
			if(minYOld -% minYNew > 0) {
				var y = minYNew;
				while(y != minYOld and y != maxYNew): (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}
			if(maxYNew -% maxYOld > 0) {
				var y = minYNew +% @max(0, maxYOld -% minYNew);
				while(y != maxYNew): (y +%= size) {
					yValues[yValuesLen] = y;
					yValuesLen += 1;
				}
			}

			for(yValues[0..yValuesLen]) |y| {
				const yIndex = @divExact(y, size) & storageMask;
				const index = xIndex*storageSize + yIndex;
				const pos = LightMap.MapFragmentPosition{.wx=x, .wy=y, .voxelSize=@as(u31, 1)<<lod, .voxelSizeShift = lod};

				const node = &mapStorageLists[_lod][@intCast(index)];
				mutex.lock();
				if(node.*) |map| {
					std.debug.assert(std.meta.eql(pos, map.pos));
				} else {
					mapRequests.append(pos);
				}
				mutex.unlock();
			}
		}
	}
}

pub noinline fn updateAndGetRenderChunks(conn: *network.Connection, frustum: *const main.renderer.Frustum, playerPos: Vec3d, renderDistance: u16) []*chunk_meshing.ChunkMesh { // MARK: updateAndGetRenderChunks()
	meshList.clearRetainingCapacity();

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

	// Finds all visible chunks and lod chunks using a breadth-first search.

	const SearchData = struct {
		node: *ChunkMeshNode,
		distance: f64,

		pub fn compare(_: void, a: @This(), b: @This()) std.math.Order {
			if(a.distance < b.distance) return .lt;
			if(a.distance > b.distance) return .gt;
			return .eq;
		}
	};

	var searchList = std.PriorityQueue(SearchData, void, SearchData.compare).init(main.stackAllocator.allocator, {});
	defer searchList.deinit();
	{
		var firstPos = chunk.ChunkPosition{
			.wx = @intFromFloat(@floor(playerPos[0])),
			.wy = @intFromFloat(@floor(playerPos[1])),
			.wz = @intFromFloat(@floor(playerPos[2])),
			.voxelSize = 1,
		};
		firstPos.wx &= ~@as(i32, chunk.chunkMask);
		firstPos.wy &= ~@as(i32, chunk.chunkMask);
		firstPos.wz &= ~@as(i32, chunk.chunkMask);
		var lod: u3 = 0;
		while(lod <= settings.highestLOD) : (lod += 1) {
			const node = getNodePointer(firstPos);
			const hasMesh = node.finishedMeshing;
			if(hasMesh) {
				node.lod = lod;
				node.active = true;
				node.rendered = true;
				searchList.add(.{
					.node = node,
					.distance = 0,
				}) catch unreachable;
				break;
			}
			firstPos.wx &= ~@as(i32, firstPos.voxelSize*chunk.chunkSize);
			firstPos.wy &= ~@as(i32, firstPos.voxelSize*chunk.chunkSize);
			firstPos.wz &= ~@as(i32, firstPos.voxelSize*chunk.chunkSize);
			firstPos.voxelSize *= 2;
		}
	}
	var nodeList = main.List(*ChunkMeshNode).init(main.stackAllocator);
	defer nodeList.deinit();
	while(searchList.removeOrNull()) |data| {
		std.debug.assert(data.node.finishedMeshing);
		nodeList.append(data.node);
		data.node.active = false;

		const mesh = data.node.mesh.?; // No need to lock the mutex, since no other thread is allowed to overwrite the mesh (unless it's null).
		const pos = mesh.pos;

		mesh.visibilityMask = 0xff;
		const relPos: Vec3d = @as(Vec3d, @floatFromInt(Vec3i{pos.wx, pos.wy, pos.wz})) - playerPos;
		const relPosFloat: Vec3f = @floatCast(relPos);
		var isNeighborLod: [6]bool = .{false} ** 6;
		neighborLoop: for(chunk.Neighbor.iterable) |neighbor| {
			const component = neighbor.extractDirectionComponent(relPosFloat);
			if(neighbor.isPositive() and component + @as(f32, @floatFromInt(chunk.chunkSize*pos.voxelSize)) <= 0) continue;
			if(!neighbor.isPositive() and component >= 0) continue;
			var neighborPos = chunk.ChunkPosition{
				.wx = pos.wx +% neighbor.relX()*chunk.chunkSize*pos.voxelSize,
				.wy = pos.wy +% neighbor.relY()*chunk.chunkSize*pos.voxelSize,
				.wz = pos.wz +% neighbor.relZ()*chunk.chunkSize*pos.voxelSize,
				.voxelSize = pos.voxelSize,
			};
			if(!getNodePointer(neighborPos).active) { // Don't repeat the same frustum check all the time.
				if(!frustum.testAAB(relPosFloat + @as(Vec3f, @floatFromInt(Vec3i{neighbor.relX()*chunk.chunkSize*pos.voxelSize, neighbor.relY()*chunk.chunkSize*pos.voxelSize, neighbor.relZ()*chunk.chunkSize*pos.voxelSize})), @splat(@floatFromInt(chunk.chunkSize*pos.voxelSize))))
					continue;
			}
			var lod: u3 = data.node.lod;
			lodLoop: while(lod <= settings.highestLOD) : (lod += 1) {
				defer {
					neighborPos.wx &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.wy &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.wz &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.voxelSize *= 2;
				}
				const node = getNodePointer(neighborPos);
				if(node.finishedMeshing) {
					// Ensure that there are no high-to-low lod transitions, which would produce cracks.
					if(lod == data.node.lod and lod != settings.highestLOD and !node.rendered) {
						const relPos2: Vec3d = @as(Vec3d, @floatFromInt(Vec3i{neighborPos.wx, neighborPos.wy, neighborPos.wz})) - playerPos;
						for(chunk.Neighbor.iterable) |neighbor2| {
							const component2 = neighbor2.extractDirectionComponent(relPos2);
							if(neighbor2.isPositive() and component2 + @as(f64, @floatFromInt(chunk.chunkSize*neighborPos.voxelSize)) >= 0) continue;
							if(!neighbor2.isPositive() and component2 <= 0) continue;
							{ // Check the chunk of same lod:
								const neighborPos2 = chunk.ChunkPosition{
									.wx = neighborPos.wx + neighbor2.relX()*chunk.chunkSize*neighborPos.voxelSize,
									.wy = neighborPos.wy + neighbor2.relY()*chunk.chunkSize*neighborPos.voxelSize,
									.wz = neighborPos.wz + neighbor2.relZ()*chunk.chunkSize*neighborPos.voxelSize,
									.voxelSize = neighborPos.voxelSize,
								};
								const node2 = getNodePointer(neighborPos2);
								if(node2.rendered) {
									continue;
								}
							}
							{ // Check the chunk of higher lod
								const neighborPos2 = chunk.ChunkPosition{
									.wx = neighborPos.wx + neighbor2.relX()*chunk.chunkSize*neighborPos.voxelSize,
									.wy = neighborPos.wy + neighbor2.relY()*chunk.chunkSize*neighborPos.voxelSize,
									.wz = neighborPos.wz + neighbor2.relZ()*chunk.chunkSize*neighborPos.voxelSize,
									.voxelSize = neighborPos.voxelSize << 1,
								};
								const node2 = getNodePointer(neighborPos2);
								if(node2.rendered) {
									isNeighborLod[neighbor.toInt()] = true;
									continue :lodLoop;
								}
							}
						}
					}
					if(lod != data.node.lod) {
						isNeighborLod[neighbor.toInt()] = true;
					}
					if(!node.active) {
						node.lod = lod;
						node.active = true;
						searchList.add(.{
							.node = node,
							.distance = neighborPos.getMaxDistanceSquared(playerPos),
						}) catch unreachable;
						node.rendered = true;
					}
					continue :neighborLoop;
				}
			}
		}
		mesh.changeLodBorders(isNeighborLod);
	}
	for(nodeList.items) |node| {
		node.rendered = false;
		if(!node.finishedMeshing) continue;

		const mesh = node.mesh.?; // No need to lock the mutex, since no other thread is allowed to overwrite the mesh (unless it's null).

		if(mesh.pos.voxelSize != @as(u31, 1) << settings.highestLOD) {
			const parent = getNodePointer(.{.wx=mesh.pos.wx, .wy=mesh.pos.wy, .wz=mesh.pos.wz, .voxelSize=mesh.pos.voxelSize << 1});
			if(parent.finishedMeshing) {
				const parentMesh = parent.mesh.?; // No need to lock the mutex, since no other thread is allowed to overwrite the mesh (unless it's null).
				const sizeShift = chunk.chunkShift + @ctz(mesh.pos.voxelSize);
				const octantIndex: u3 = @intCast((mesh.pos.wx>>sizeShift & 1) | (mesh.pos.wy>>sizeShift & 1)<<1 | (mesh.pos.wz>>sizeShift & 1)<<2);
				parentMesh.visibilityMask &= ~(@as(u8, 1) << octantIndex);
			}
		}
		node.mutex.lock();
		if(mesh.needsMeshUpdate) {
			mesh.uploadData();
			mesh.needsMeshUpdate = false;
		}
		node.mutex.unlock();
		// Remove empty meshes.
		if(!mesh.isEmpty()) {
			meshList.append(mesh);
		}
	}

	return meshList.items;
}

pub fn updateMeshes(targetTime: i64) void { // MARK: updateMeshes()
	{ // First of all process all the block updates:
		blockUpdateMutex.lock();
		defer blockUpdateMutex.unlock();
		for(blockUpdateList.items) |blockUpdate| {
			const pos = chunk.ChunkPosition{.wx=blockUpdate.x, .wy=blockUpdate.y, .wz=blockUpdate.z, .voxelSize=1};
			if(getMeshAndIncreaseRefCount(pos)) |mesh| {
				defer mesh.decreaseRefCount();
				mesh.updateBlock(blockUpdate.x, blockUpdate.y, blockUpdate.z, blockUpdate.newBlock);
			} // TODO: It seems like we simply ignore the block update if we don't have the mesh yet.
		}
		blockUpdateList.clearRetainingCapacity();
	}
	mutex.lock();
	defer mutex.unlock();
	for(clearList.items) |mesh| {
		mesh.deinit();
		main.globalAllocator.destroy(mesh);
	}
	clearList.clearRetainingCapacity();
	while (priorityMeshUpdateList.items.len != 0) {
		const mesh = priorityMeshUpdateList.orderedRemove(0);
		if(!mesh.needsMeshUpdate) {
			mutex.unlock();
			defer mutex.lock();
			mesh.decreaseRefCount();
			continue;
		}
		mesh.needsMeshUpdate = false;
		const node = getNodePointer(mesh.pos);
		node.mutex.lock();
		if(node.mesh != mesh) {
			node.mutex.unlock();
			mutex.unlock();
			defer mutex.lock();
			mesh.decreaseRefCount();
			continue;
		}
		node.mutex.unlock();
		mutex.unlock();
		defer mutex.lock();
		mesh.decreaseRefCount();
		mesh.uploadData();
		if(std.time.milliTimestamp() >= targetTime) break; // Update at least one mesh.
	}
	while(mapUpdatableList.popOrNull()) |map| {
		if(!isMapInRenderDistance(map.pos)) {
			map.decreaseRefCount();
		} else {
			const mapPointer = getMapPiecePointer(map.pos.wx, map.pos.wy, map.pos.voxelSize);
			if(mapPointer.*) |old| {
				old.decreaseRefCount();
			}
			mapPointer.* = map;
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
				const mesh = updatableList.items[i];
				if(!isInRenderDistance(mesh.pos)) {
					_ = updatableList.swapRemove(i);
					mutex.unlock();
					defer mutex.lock();
					mesh.decreaseRefCount();
					continue;
				}
				const priority = mesh.pos.getPriority(playerPos);
				if(priority > closestPriority) {
					closestPriority = priority;
					closestIndex = i;
				}
				i += 1;
			}
			if(updatableList.items.len == 0) break;
		}
		const mesh = updatableList.swapRemove(closestIndex);
		mutex.unlock();
		defer mutex.lock();
		if(isInRenderDistance(mesh.pos)) {
			const node = getNodePointer(mesh.pos);
			node.finishedMeshing = true;
			mesh.finishedMeshing = true;
			mesh.uploadData();
			node.mutex.lock();
			const oldMesh = node.mesh;
			node.mesh = mesh;
			node.mutex.unlock();
			if(oldMesh) |_oldMesh| {
				_oldMesh.decreaseRefCount();
			}
		} else {
			mesh.decreaseRefCount();
		}
		if(std.time.milliTimestamp() >= targetTime) break; // Update at least one mesh.
	}
}

// MARK: adders

pub fn addMeshToClearListAndDecreaseRefCount(mesh: *chunk_meshing.ChunkMesh) void {
	std.debug.assert(mesh.refCount.load(.monotonic) == 0);
	mutex.lock();
	defer mutex.unlock();
	clearList.append(mesh);
}

pub fn addToUpdateListAndDecreaseRefCount(mesh: *chunk_meshing.ChunkMesh) void {
	std.debug.assert(mesh.refCount.load(.monotonic) != 0);
	mutex.lock();
	defer mutex.unlock();
	if(mesh.finishedMeshing) {
		priorityMeshUpdateList.append(mesh);
		mesh.needsMeshUpdate = true;
	} else {
		mutex.unlock();
		defer mutex.lock();
		mesh.decreaseRefCount();
	}
}

pub fn addMeshToStorage(mesh: *chunk_meshing.ChunkMesh) error{AlreadyStored}!void {
	mutex.lock();
	defer mutex.unlock();
	if(isInRenderDistance(mesh.pos)) {
		const node = getNodePointer(mesh.pos);
		node.mutex.lock();
		defer node.mutex.unlock();
		if(node.mesh != null) {
			return error.AlreadyStored;
		}
		node.mesh = mesh;
		node.finishedMeshing = mesh.finishedMeshing;
		mesh.increaseRefCount();
	}
}

pub fn finishMesh(mesh: *chunk_meshing.ChunkMesh) void {
	mutex.lock();
	defer mutex.unlock();
	mesh.increaseRefCount();
	updatableList.append(mesh);
}

pub const MeshGenerationTask = struct { // MARK: MeshGenerationTask
	mesh: *chunk.Chunk,

	pub const vtable = utils.ThreadPool.VTable{
		.getPriority = @ptrCast(&getPriority),
		.isStillNeeded = @ptrCast(&isStillNeeded),
		.run = @ptrCast(&run),
		.clean = @ptrCast(&clean),
		.taskType = .meshgenAndLighting,
	};

	pub fn schedule(mesh: *chunk.Chunk) void {
		const task = main.globalAllocator.create(MeshGenerationTask);
		task.* = MeshGenerationTask {
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
		const mesh = main.globalAllocator.create(chunk_meshing.ChunkMesh);
		mesh.init(pos, self.mesh);
		defer mesh.decreaseRefCount();
		mesh.generateLightingData() catch return;
	}

	pub fn clean(self: *MeshGenerationTask) void {
		self.mesh.deinit();
		main.globalAllocator.destroy(self);
	}
};

// MARK: updaters

pub fn updateBlock(x: i32, y: i32, z: i32, newBlock: blocks.Block) void {
	blockUpdateMutex.lock();
	defer blockUpdateMutex.unlock();
	blockUpdateList.append(BlockUpdate{.x=x, .y=y, .z=z, .newBlock=newBlock});
}

pub fn updateChunkMesh(mesh: *chunk.Chunk) void {
	MeshGenerationTask.schedule(mesh);
}

pub fn updateLightMap(map: *LightMap.LightMapFragment) void {
	mutex.lock();
	defer mutex.unlock();
	mapUpdatableList.append(map);
}
