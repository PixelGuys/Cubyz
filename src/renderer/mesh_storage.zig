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
	min: Vec2f = undefined,
	max: Vec2f = undefined,
	active: bool = false,
	rendered: bool = false,
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
var lastRD: i32 = 0;
var mutex = std.Thread.Mutex{};
var blockUpdateMutex = std.Thread.Mutex{};
const BlockUpdate = struct {
	x: i32,
	y: i32,
	z: i32,
	newBlock: blocks.Block,
};
var blockUpdateList: main.List(BlockUpdate) = undefined;

pub fn init() void {
	lastRD = 0;
	blockUpdateList = main.List(BlockUpdate).init(main.globalAllocator);
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

pub fn getNeighborAndIncreaseRefCount(_pos: chunk.ChunkPosition, resolution: u31, neighbor: u3) ?*chunk_meshing.ChunkMesh {
	var pos = _pos;
	pos.wx +%= pos.voxelSize*chunk.chunkSize*chunk.Neighbors.relX[neighbor];
	pos.wy +%= pos.voxelSize*chunk.chunkSize*chunk.Neighbors.relY[neighbor];
	pos.wz +%= pos.voxelSize*chunk.chunkSize*chunk.Neighbors.relZ[neighbor];
	pos.voxelSize = resolution;
	return getMeshAndIncreaseRefCount(pos);
}

fn reduceRenderDistance(fullRenderDistance: i64, reduction: i64) i32 {
	const reducedRenderDistanceSquare: f64 = @floatFromInt(fullRenderDistance*fullRenderDistance - reduction*reduction);
	const reducedRenderDistance: i32 = @intFromFloat(@ceil(@sqrt(@max(0, reducedRenderDistanceSquare))));
	return reducedRenderDistance;
}

fn isInRenderDistance(pos: chunk.ChunkPosition) bool {
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

fn freeOldMeshes(olderPx: i32, olderPy: i32, olderPz: i32, olderRD: i32) void {
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

fn createNewMeshes(olderPx: i32, olderPy: i32, olderPz: i32, olderRD: i32, meshRequests: *main.List(chunk.ChunkPosition), mapRequests: *main.List(LightMap.MapFragmentPosition)) void {
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

pub noinline fn updateAndGetRenderChunks(conn: *network.Connection, playerPos: Vec3d, renderDistance: i32) []*chunk_meshing.ChunkMesh {
	meshList.clearRetainingCapacity();
	if(lastRD != renderDistance) {
		network.Protocols.genericUpdate.sendRenderDistance(conn, renderDistance);
	}

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
	network.Protocols.chunkRequest.sendRequest(conn, meshRequests.items, .{lastPx, lastPy, lastPz});

	// Does occlusion using a breadth-first search that caches an on-screen visibility rectangle.

	const OcclusionData = struct {
		node: *ChunkMeshNode,
		distance: f64,

		pub fn compare(_: void, a: @This(), b: @This()) std.math.Order {
			if(a.distance < b.distance) return .lt;
			if(a.distance > b.distance) return .gt;
			return .eq;
		}
	};

	// TODO: Is there a way to combine this with minecraft's approach?
	var searchList = std.PriorityQueue(OcclusionData, void, OcclusionData.compare).init(main.stackAllocator.allocator, {});
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
			node.mutex.lock();
			const hasMesh = node.mesh != null and node.mesh.?.finishedMeshing;
			node.mutex.unlock();
			if(hasMesh) {
				node.lod = lod;
				node.min = @splat(-1);
				node.max = @splat(1);
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
	const projRotMat = game.projectionMatrix.mul(game.camera.viewMatrix);
	while(searchList.removeOrNull()) |data| {
		nodeList.append(data.node);
		data.node.active = false;

		mutex.lock();
		const mesh = data.node.mesh orelse {
			mutex.unlock();
			continue;
		};
		if(!mesh.finishedMeshing) {
			mutex.unlock();
			continue;
		}
		mesh.increaseRefCount();
		defer mesh.decreaseRefCount();
		mutex.unlock();

		mesh.visibilityMask = 0xff;
		const relPos: Vec3d = @as(Vec3d, @floatFromInt(Vec3i{mesh.pos.wx, mesh.pos.wy, mesh.pos.wz})) - playerPos;
		const relPosFloat: Vec3f = @floatCast(relPos);
		var isNeighborLod: [6]bool = .{false} ** 6;
		for(chunk.Neighbors.iterable) |neighbor| continueNeighborLoop: {
			const component = chunk.Neighbors.extractDirectionComponent(neighbor, relPos);
			if(chunk.Neighbors.isPositive[neighbor] and component + @as(f64, @floatFromInt(chunk.chunkSize*mesh.pos.voxelSize)) <= 0) continue;
			if(!chunk.Neighbors.isPositive[neighbor] and component >= 0) continue;
			if(@reduce(.Or, @min(mesh.chunkBorders[neighbor].min, mesh.chunkBorders[neighbor].max) != mesh.chunkBorders[neighbor].min)) continue; // There was not a single block in the chunk. TODO: Find a better solution.
			const minVec: Vec3f = @floatFromInt(mesh.chunkBorders[neighbor].min*@as(Vec3i, @splat(mesh.pos.voxelSize)));
			const maxVec: Vec3f = @floatFromInt(mesh.chunkBorders[neighbor].max*@as(Vec3i, @splat(mesh.pos.voxelSize)));
			var xyMin: Vec2f = .{10, 10};
			var xyMax: Vec2f = .{-10, -10};
			var numberOfNegatives: u8 = 0;
			var corners: [5]Vec4f = undefined;
			var curCorner: usize = 0;
			for(0..2) |a| {
				for(0..2) |b| {
					
					var cornerVector: Vec3f = undefined;
					switch(chunk.Neighbors.vectorComponent[neighbor]) {
						.x => {
							cornerVector = @select(f32, @Vector(3, bool){true, a == 0, b == 0}, minVec, maxVec);
						},
						.y => {
							cornerVector = @select(f32, @Vector(3, bool){a == 0, true, b == 0}, minVec, maxVec);
						},
						.z => {
							cornerVector = @select(f32, @Vector(3, bool){a == 0, b == 0, true}, minVec, maxVec);
						},
					}
					corners[curCorner] = projRotMat.mulVec(vec.combine(relPosFloat + cornerVector, 1));
					if(corners[curCorner][3] < 0) {
						numberOfNegatives += 1;
					}
					curCorner += 1;
				}
			}
			switch(numberOfNegatives) { // Oh, so complicated. But this should only trigger very close to the player.
				4 => continue,
				0 => {},
				1 => {
					// Needs to duplicate the problematic corner and move it onto the projected plane.
					var problematicOne: usize = 0;
					for(0..curCorner) |i| {
						if(corners[i][3] < 0) {
							problematicOne = i;
							break;
						}
					}
					const problematicVector = corners[problematicOne];
					// The two neighbors of the quad:
					const neighborA = corners[problematicOne ^ 1];
					const neighborB = corners[problematicOne ^ 2];
					// Move the problematic point towards the neighbor:
					const one: Vec4f = @splat(1);
					const weightA: Vec4f = @splat(problematicVector[3]/(problematicVector[3] - neighborA[3]));
					var towardsA = neighborA*weightA + problematicVector*(one - weightA);
					towardsA[3] = 0; // Prevent inaccuracies
					const weightB: Vec4f = @splat(problematicVector[3]/(problematicVector[3] - neighborB[3]));
					var towardsB = neighborB*weightB + problematicVector*(one - weightB);
					towardsB[3] = 0; // Prevent inaccuracies
					corners[problematicOne] = towardsA;
					corners[curCorner] = towardsB;
					curCorner += 1;
				},
				2 => {
					// Needs to move the two problematic corners onto the projected plane.
					var problematicOne: usize = undefined;
					for(0..curCorner) |i| {
						if(corners[i][3] < 0) {
							problematicOne = i;
							break;
						}
					}
					const problematicVectorOne = corners[problematicOne];
					var problematicTwo: usize = undefined;
					for(problematicOne+1..curCorner) |i| {
						if(corners[i][3] < 0) {
							problematicTwo = i;
							break;
						}
					}
					const problematicVectorTwo = corners[problematicTwo];

					const commonDirection = problematicOne ^ problematicTwo;
					const projectionDirection = commonDirection ^ 0b11;
					// The respective neighbors:
					const neighborOne = corners[problematicOne ^ projectionDirection];
					const neighborTwo = corners[problematicTwo ^ projectionDirection];
					// Move the problematic points towards the neighbor:
					const one: Vec4f = @splat(1);
					const weightOne: Vec4f = @splat(problematicVectorOne[3]/(problematicVectorOne[3] - neighborOne[3]));
					var towardsOne = neighborOne*weightOne + problematicVectorOne*(one - weightOne);
					towardsOne[3] = 0; // Prevent inaccuracies
					corners[problematicOne] = towardsOne;

					const weightTwo: Vec4f = @splat(problematicVectorTwo[3]/(problematicVectorTwo[3] - neighborTwo[3]));
					var towardsTwo = neighborTwo*weightTwo + problematicVectorTwo*(one - weightTwo);
					towardsTwo[3] = 0; // Prevent inaccuracies
					corners[problematicTwo] = towardsTwo;
				},
				3 => {
					// Throw away the far problematic vector, move the other two onto the projection plane.
					var neighborIndex: usize = undefined;
					for(0..curCorner) |i| {
						if(corners[i][3] >= 0) {
							neighborIndex = i;
							break;
						}
					}
					const neighborVector = corners[neighborIndex];
					const problematicVectorOne = corners[neighborIndex ^ 1];
					const problematicVectorTwo = corners[neighborIndex ^ 2];
					// Move the problematic points towards the neighbor:
					const one: Vec4f = @splat(1);
					const weightOne: Vec4f = @splat(problematicVectorOne[3]/(problematicVectorOne[3] - neighborVector[3]));
					var towardsOne = neighborVector*weightOne + problematicVectorOne*(one - weightOne);
					towardsOne[3] = 0; // Prevent inaccuracies

					const weightTwo: Vec4f = @splat(problematicVectorTwo[3]/(problematicVectorTwo[3] - neighborVector[3]));
					var towardsTwo = neighborVector*weightTwo + problematicVectorTwo*(one - weightTwo);
					towardsTwo[3] = 0; // Prevent inaccuracies

					corners[0] = neighborVector;
					corners[1] = towardsOne;
					corners[2] = towardsTwo;
					curCorner = 3;
				},
				else => unreachable,
			}

			for(0..curCorner) |i| {
				const projected = corners[i];
				const xy = vec.xy(projected)/@as(Vec2f, @splat(@max(0, projected[3])));
				xyMin = @min(xyMin, xy);
				xyMax = @max(xyMax, xy);
			}
			const min = @max(xyMin, data.node.min);
			const max = @min(xyMax, data.node.max);
			if(@reduce(.Or, min >= max)) continue; // Nothing to render.
			var neighborPos = chunk.ChunkPosition{
				.wx = mesh.pos.wx +% chunk.Neighbors.relX[neighbor]*chunk.chunkSize*mesh.pos.voxelSize,
				.wy = mesh.pos.wy +% chunk.Neighbors.relY[neighbor]*chunk.chunkSize*mesh.pos.voxelSize,
				.wz = mesh.pos.wz +% chunk.Neighbors.relZ[neighbor]*chunk.chunkSize*mesh.pos.voxelSize,
				.voxelSize = mesh.pos.voxelSize,
			};
			var lod: u3 = data.node.lod;
			while(lod <= settings.highestLOD) : (lod += 1) {
				defer {
					neighborPos.wx &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.wy &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.wz &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.voxelSize *= 2;
				}
				const node = getNodePointer(neighborPos);
				if(getMeshAndIncreaseRefCount(neighborPos)) |neighborMesh| {
					std.debug.assert(std.meta.eql(neighborPos, neighborMesh.pos));
					defer neighborMesh.decreaseRefCount();
					if(!neighborMesh.finishedMeshing) continue;
					// Ensure that there are no high-to-low lod transitions, which would produce cracks.
					if(lod == data.node.lod and lod != settings.highestLOD and !node.rendered) {
						var isValid: bool = true;
						const relPos2: Vec3d = @as(Vec3d, @floatFromInt(Vec3i{neighborPos.wx, neighborPos.wy, neighborPos.wz})) - playerPos;
						for(chunk.Neighbors.iterable) |neighbor2| {
							const component2 = chunk.Neighbors.extractDirectionComponent(neighbor2, relPos2);
							if(chunk.Neighbors.isPositive[neighbor2] and component2 + @as(f64, @floatFromInt(chunk.chunkSize*neighborMesh.pos.voxelSize)) >= 0) continue;
							if(!chunk.Neighbors.isPositive[neighbor2] and component2 <= 0) continue;
							{ // Check the chunk of same lod:
								const neighborPos2 = chunk.ChunkPosition{
									.wx = neighborPos.wx + chunk.Neighbors.relX[neighbor2]*chunk.chunkSize*neighborPos.voxelSize,
									.wy = neighborPos.wy + chunk.Neighbors.relY[neighbor2]*chunk.chunkSize*neighborPos.voxelSize,
									.wz = neighborPos.wz + chunk.Neighbors.relZ[neighbor2]*chunk.chunkSize*neighborPos.voxelSize,
									.voxelSize = neighborPos.voxelSize,
								};
								const node2 = getNodePointer(neighborPos2);
								if(node2.rendered) {
									continue;
								}
							}
							{ // Check the chunk of higher lod
								const neighborPos2 = chunk.ChunkPosition{
									.wx = neighborPos.wx + chunk.Neighbors.relX[neighbor2]*chunk.chunkSize*neighborPos.voxelSize,
									.wy = neighborPos.wy + chunk.Neighbors.relY[neighbor2]*chunk.chunkSize*neighborPos.voxelSize,
									.wz = neighborPos.wz + chunk.Neighbors.relZ[neighbor2]*chunk.chunkSize*neighborPos.voxelSize,
									.voxelSize = neighborPos.voxelSize << 1,
								};
								const node2 = getNodePointer(neighborPos2);
								if(node2.rendered) {
									isValid = false;
									break;
								}
							}
						}
						if(!isValid) {
							isNeighborLod[neighbor] = true;
							continue;
						}
					}
					if(lod != data.node.lod) {
						isNeighborLod[neighbor] = true;
					}
					if(node.active) {
						node.min = @min(node.min, min);
						node.max = @max(node.max, max);
					} else {
						node.lod = lod;
						node.min = min;
						node.max = max;
						node.active = true;
						searchList.add(.{
							.node = node,
							.distance = neighborMesh.pos.getMaxDistanceSquared(playerPos),
						}) catch unreachable;
						node.rendered = true;
					}
					break :continueNeighborLoop;
				}
			}
		}
		mesh.changeLodBorders(isNeighborLod);
	}
	for(nodeList.items) |node| {
		node.rendered = false;

		node.mutex.lock();
		const mesh = node.mesh orelse {
			node.mutex.unlock();
			continue;
		};
		if(!mesh.finishedMeshing) {
			node.mutex.unlock();
			continue;
		}
		mesh.increaseRefCount();
		defer mesh.decreaseRefCount();
		node.mutex.unlock();

		if(mesh.pos.voxelSize != @as(u31, 1) << settings.highestLOD) {
			const parent = getNodePointer(.{.wx=mesh.pos.wx, .wy=mesh.pos.wy, .wz=mesh.pos.wz, .voxelSize=mesh.pos.voxelSize << 1});
			parent.mutex.lock();
			defer parent.mutex.unlock();
			if(parent.mesh) |parentMesh| {
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

pub fn updateMeshes(targetTime: i64) void {
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
		const playerPos = game.Player.getPosBlocking();
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
		mesh.increaseRefCount();
	}
}

pub fn finishMesh(mesh: *chunk_meshing.ChunkMesh) void {
	mutex.lock();
	defer mutex.unlock();
	mesh.increaseRefCount();
	updatableList.append(mesh);
}

pub const MeshGenerationTask = struct {
	mesh: *chunk.Chunk,

	pub const vtable = utils.ThreadPool.VTable{
		.getPriority = @ptrCast(&getPriority),
		.isStillNeeded = @ptrCast(&isStillNeeded),
		.run = @ptrCast(&run),
		.clean = @ptrCast(&clean),
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

	pub fn isStillNeeded(self: *MeshGenerationTask, _: i64) bool {
		const distanceSqr = self.mesh.pos.getMinDistanceSquared(game.Player.getPosBlocking()); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
		var maxRenderDistance = settings.renderDistance*chunk.chunkSize*self.mesh.pos.voxelSize;
		maxRenderDistance += 2*self.mesh.pos.voxelSize*chunk.chunkSize;
		return distanceSqr < @as(f64, @floatFromInt(maxRenderDistance*maxRenderDistance));
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