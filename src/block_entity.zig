const std = @import("std");

const main = @import("main.zig");
const Block = main.blocks.Block;
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const getIndex = main.chunk.getIndex;
const graphics = main.graphics;
const c = graphics.c;
const server = main.server;
const User = server.User;
const mesh_storage = main.renderer.mesh_storage;
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

const block_entities = @import("block_entities");

pub const BlockEntityIndex = main.utils.DenseId(u32);

pub const UpdateEvent = union(enum) {
	remove: void,
	createOrUpdate: *BinaryReader,
};

pub const BlockEntityType = struct {
	id: []const u8,
	vtable: VTable,

	const VTable = struct {
		onLoadClient: *const fn(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void,
		onUnloadClient: *const fn(dataIndex: BlockEntityIndex) void,
		onLoadServer: *const fn(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void,
		onUnloadServer: *const fn(dataIndex: BlockEntityIndex) void,
		onStoreServerToDisk: *const fn(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void,
		onStoreServerToClient: *const fn(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void,
		onInteract: *const fn(pos: Vec3i, chunk: *Chunk) EventStatus,
		updateClientData: *const fn(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void,
		updateServerData: *const fn(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void,
		getServerToClientData: *const fn(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void,
		getClientToServerData: *const fn(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void,
	};
	pub fn init(comptime BlockEntityTypeT: type) BlockEntityType {
		BlockEntityTypeT.init();
		var class = BlockEntityType{
			.id = BlockEntityTypeT.id,
			.vtable = undefined,
		};

		inline for(@typeInfo(BlockEntityType.VTable).@"struct".fields) |field| {
			if(!@hasDecl(BlockEntityTypeT, field.name)) {
				@compileError("BlockEntityType missing field '" ++ field.name ++ "'");
			}
			@field(class.vtable, field.name) = &@field(BlockEntityTypeT, field.name);
		}
		return class;
	}
	pub inline fn onLoadClient(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
		return self.vtable.onLoadClient(pos, chunk, reader);
	}
	pub inline fn onUnloadClient(self: *BlockEntityType, dataIndex: BlockEntityIndex) void {
		return self.vtable.onUnloadClient(dataIndex);
	}
	pub inline fn onLoadServer(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
		return self.vtable.onLoadServer(pos, chunk, reader);
	}
	pub inline fn onUnloadServer(self: *BlockEntityType, dataIndex: BlockEntityIndex) void {
		return self.vtable.onUnloadServer(dataIndex);
	}
	pub inline fn onStoreServerToDisk(self: *BlockEntityType, dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
		return self.vtable.onStoreServerToDisk(dataIndex, writer);
	}
	pub inline fn onStoreServerToClient(self: *BlockEntityType, dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
		return self.vtable.onStoreServerToClient(dataIndex, writer);
	}
	pub inline fn onInteract(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) EventStatus {
		return self.vtable.onInteract(pos, chunk);
	}
	pub inline fn updateClientData(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
		return try self.vtable.updateClientData(pos, chunk, event);
	}
	pub inline fn updateServerData(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
		return try self.vtable.updateServerData(pos, chunk, event);
	}
	pub inline fn getServerToClientData(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
		return self.vtable.getServerToClientData(pos, chunk, writer);
	}
	pub inline fn getClientToServerData(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
		return self.vtable.getClientToServerData(pos, chunk, writer);
	}
};

pub const EventStatus = enum {
	handled,
	ignored,
};

pub fn BlockEntityDataStorage(T: type) type {
	return struct {
		pub const DataT = T;
		var freeIndexList: main.ListUnmanaged(BlockEntityIndex) = .{};
		var nextIndex: BlockEntityIndex = @enumFromInt(0);
		var storage: main.utils.SparseSet(DataT, BlockEntityIndex) = .{};
		pub var mutex: std.Thread.Mutex = .{};

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
		fn createEntry(pos: Vec3i, chunk: *Chunk) BlockEntityIndex {
			main.utils.assertLocked(&mutex);
			const dataIndex: BlockEntityIndex = freeIndexList.popOrNull() orelse blk: {
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
		pub fn removeAtIndex(dataIndex: BlockEntityIndex) ?DataT {
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
		pub fn getByIndex(dataIndex: BlockEntityIndex) ?*DataT {
			main.utils.assertLocked(&mutex);

			return storage.get(dataIndex);
		}
		pub fn get(pos: Vec3i, chunk: *Chunk) ?*DataT {
			main.utils.assertLocked(&mutex);

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			defer chunk.blockPosToEntityDataMapMutex.unlock();

			const dataIndex = chunk.blockPosToEntityDataMap.get(blockIndex) orelse {
				std.log.warn("Couldn't get entity data of block at position {}", .{pos});
				return null;
			};
			return storage.get(dataIndex);
		}
		pub const GetOrPutResult = struct {
			valuePtr: *DataT,
			foundExisting: bool,
		};
		pub fn getOrPut(pos: Vec3i, chunk: *Chunk) GetOrPutResult {
			main.utils.assertLocked(&mutex);
			if(get(pos, chunk)) |result| return .{.valuePtr = result, .foundExisting = true};

			const dataIndex = createEntry(pos, chunk);
			return .{.valuePtr = storage.add(main.globalAllocator, dataIndex), .foundExisting = false};
		}
	};
}

var blockyEntityTypes: std.StringHashMapUnmanaged(BlockEntityType) = .{};

pub fn init() void {
	inline for(@typeInfo(block_entities).@"struct".decls) |declaration| {
		const class = BlockEntityType.init(@field(block_entities, declaration.name));
		blockyEntityTypes.putNoClobber(main.globalAllocator.allocator, class.id, class) catch unreachable;
		std.log.debug("Registered BlockEntityType '{s}'", .{class.id});
	}
}

pub fn reset() void {
	inline for(@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).reset();
	}
}

pub fn deinit() void {
	inline for(@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).deinit();
	}
	blockyEntityTypes.deinit(main.globalAllocator.allocator);
}

pub fn getByID(_id: ?[]const u8) ?*BlockEntityType {
	const id = _id orelse return null;
	if(blockyEntityTypes.getPtr(id)) |cls| return cls;
	std.log.err("BlockEntityType with id '{s}' not found", .{id});
	return null;
}

pub fn renderAll(projectionMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
	inline for(@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).renderAll(projectionMatrix, ambientLight, playerPos);
	}
}
