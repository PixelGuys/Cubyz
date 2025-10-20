const main = @import("main");
const std = @import("std");
const Chunk = main.chunk.Chunk;

const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const BlockDataStorageIndex = main.utils.DenseId(u32);

pub fn BlockDataStorage(T: type) type {
	return struct {
		pub const DataT = T;
		var freeIndexList: main.ListUnmanaged(BlockDataStorageIndex) = .{};
		var nextIndex: BlockDataStorageIndex = @enumFromInt(0);
		pub var storage: main.utils.SparseSet(DataT, BlockDataStorageIndex) = .{};
		pub var mutex: std.Thread.Mutex = .{};

		pub const GetOrPutResult = struct {
			valuePtr: *DataT,
			foundExisting: bool,
		};

		pub fn init() void {
			storage = .{};
			freeIndexList = .{};
		}

		pub fn deinit() void {
			storage.deinit(main.globalAllocator);
			freeIndexList.deinit(main.globalAllocator);
			nextIndex = @enumFromInt(0);
		}

		pub fn reset() void {
			storage.clear();
			freeIndexList.clearRetainingCapacity();
		}

		fn createEntry(pos: Vec3i, chunk: *Chunk) BlockDataStorageIndex {
			main.utils.assertLocked(&mutex);
			const dataIndex: BlockDataStorageIndex = freeIndexList.popOrNull() orelse blk: {
				defer nextIndex = @enumFromInt(@intFromEnum(nextIndex) + 1);
				break :blk nextIndex;
			};

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, blockIndex, dataIndex) catch unreachable;
			chunk.blockPosToEntityDataMapMutex.unlock();
			return dataIndex;
		}

		pub fn add(pos: Vec3i, value: DataT, chunk: *Chunk) void {
			mutex.lock();
			defer mutex.unlock();

			const dataIndex = createEntry(pos, chunk);
			storage.set(main.globalAllocator, dataIndex, value);
		}

		pub fn removeAtIndex(dataIndex: BlockDataStorageIndex) ?DataT {
			main.utils.assertLocked(&mutex);
			freeIndexList.append(main.globalAllocator, dataIndex);
			return storage.fetchRemove(dataIndex) catch null;
		}

		pub fn remove(pos: Vec3i, chunk: *Chunk) ?DataT {
			mutex.lock();
			defer mutex.unlock();

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			const entityNullable = chunk.blockPosToEntityDataMap.fetchRemove(blockIndex);
			chunk.blockPosToEntityDataMapMutex.unlock();

			const entry = entityNullable orelse return null;

			const dataIndex = entry.value;
			return removeAtIndex(dataIndex);
		}

		pub fn getByIndex(dataIndex: BlockDataStorageIndex) ?*DataT {
			main.utils.assertLocked(&mutex);

			return storage.get(dataIndex);
		}

		pub fn get(pos: Vec3i, chunk: *Chunk) ?*DataT {
			main.utils.assertLocked(&mutex);

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			defer chunk.blockPosToEntityDataMapMutex.unlock();

			const dataIndex = chunk.blockPosToEntityDataMap.get(blockIndex) orelse return null;

			return storage.get(dataIndex);
		}

		pub fn getOrPut(pos: Vec3i, chunk: *Chunk) GetOrPutResult {
			main.utils.assertLocked(&mutex);
			if(get(pos, chunk)) |result| return .{.valuePtr = result, .foundExisting = true};

			const dataIndex = createEntry(pos, chunk);
			return .{.valuePtr = storage.add(main.globalAllocator, dataIndex), .foundExisting = false};
		}
	};
}
