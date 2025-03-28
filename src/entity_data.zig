const std = @import("std");

const main = @import("main.zig");
const List = main.List;
const Vec3i = main.vec.Vec3i;
const Block = main.blocks.Block;
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const getIndex = main.chunk.getIndex;
const server = main.server;
const User = server.User;
const mesh_storage = main.renderer.mesh_storage;

pub const EntityDataClass = struct {
	id: []const u8,
	vtable: VTable,

	const VTable = struct {
		onLoadClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnloadClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onLoadServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnloadServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlaceClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlaceServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onInteract: *const fn(pos: Vec3i, chunk: *Chunk) EventStatus,
	};
	pub fn init(comptime EntityDataClassT: type) EntityDataClass {
		EntityDataClassT.init();
		var class = EntityDataClass{
			.id = EntityDataClassT.id,
			.vtable = undefined,
		};

		inline for(@typeInfo(EntityDataClass.VTable).@"struct".fields) |field| {
			if(!@hasDecl(EntityDataClassT, field.name)) {
				@compileError("EntityDataClass missing field");
			}
			@field(class.vtable, field.name) = &@field(EntityDataClassT, field.name);
		}
		return class;
	}
	pub inline fn onLoadClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onLoadClient(pos, chunk);
	}
	pub inline fn onUnloadClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onUnloadClient(pos, chunk);
	}
	pub inline fn onLoadServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onLoadServer(pos, chunk);
	}
	pub inline fn onUnloadServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onUnloadServer(pos, chunk);
	}
	pub inline fn onPlaceClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onPlaceClient(pos, chunk);
	}
	pub inline fn onBreakClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onBreakClient(pos, chunk);
	}
	pub inline fn onPlaceServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onPlaceServer(pos, chunk);
	}
	pub inline fn onBreakServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onBreakServer(pos, chunk);
	}
	pub inline fn onInteract(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) EventStatus {
		return self.vtable.onInteract(pos, chunk);
	}
};

pub const EventStatus = enum {
	handled,
	ignored,
};

fn BlockEntityDataStorage(comptime side: enum {client, server}, T: type) type {
	return struct {
		pub const DataT = T;
		pub const EntryT = struct {
			absoluteBlockPosition: Vec3i,
			data: DataT,
		};
		var storage: List(EntryT) = undefined;
		pub var mutex: std.Thread.Mutex = .{};

		pub fn init() void {
			storage = .init(main.globalAllocator);
		}
		pub fn deinit() void {
			storage.deinit();
		}
		pub fn reset() void {
			storage.clearRetainingCapacity();
		}
		pub fn add(pos: Vec3i, value: DataT, chunk: *Chunk) void {
			mutex.lock();
			defer mutex.unlock();

			const dataIndex = storage.items.len;
			storage.append(.{.absoluteBlockPosition = pos, .data = value});

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, blockIndex, @intCast(dataIndex)) catch unreachable;
			chunk.blockPosToEntityDataMapMutex.unlock();
		}
		pub fn remove(pos: Vec3i, chunk: *Chunk) void {
			mutex.lock();
			defer mutex.unlock();

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			const entityNullable = chunk.blockPosToEntityDataMap.fetchRemove(blockIndex);
			chunk.blockPosToEntityDataMapMutex.unlock();

			const entry = entityNullable orelse {
				std.log.warn("Couldn't remove entity data of block at position {}", .{pos});
				return;
			};

			const dataIndex = entry.value;
			_ = storage.swapRemove(dataIndex);
			if(dataIndex == storage.items.len) {
				return;
			}

			const movedEntry = storage.items[dataIndex];
			switch(side) {
				.server => propagateRemoveServer(movedEntry.absoluteBlockPosition, dataIndex),
				.client => propagateRemoveClient(movedEntry.absoluteBlockPosition, dataIndex),
			}
		}
		fn propagateRemoveServer(pos: Vec3i, index: u32) void {
			const severChunk = server.world.?.getChunkFromCacheAndIncreaseRefCount(ChunkPosition.initFromWorldPos(pos, 1)).?;
			defer severChunk.decreaseRefCount();

			severChunk.super.blockPosToEntityDataMapMutex.lock();
			defer severChunk.super.blockPosToEntityDataMapMutex.unlock();

			const otherDataIndex = severChunk.super.getLocalBlockIndex(pos);
			severChunk.super.blockPosToEntityDataMap.put(main.globalAllocator.allocator, otherDataIndex, index) catch unreachable;
		}
		fn propagateRemoveClient(pos: Vec3i, index: u32) void {
			const mesh = mesh_storage.getMeshAndIncreaseRefCount(ChunkPosition.initFromWorldPos(pos, 1)).?;
			defer mesh.decreaseRefCount();

			mesh.chunk.blockPosToEntityDataMapMutex.lock();
			defer mesh.chunk.blockPosToEntityDataMapMutex.unlock();

			const otherDataIndex = mesh.chunk.getLocalBlockIndex(pos);
			mesh.chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, otherDataIndex, index) catch unreachable;
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
			return &storage.items[dataIndex].data;
		}
	};
}

pub const EntityDataClasses = struct {
	pub const Chest = struct {
		const StorageServer = BlockEntityDataStorage(
			.server,
			struct {
				contents: u64,
			},
		);
		const StorageClient = BlockEntityDataStorage(
			.client,
			struct {
				contents: u64,
			},
		);

		pub const id = "chest";
		pub fn init() void {
			StorageServer.init();
			StorageClient.init();
		}
		pub fn deinit() void {
			StorageServer.deinit();
			StorageClient.deinit();
		}
		pub fn reset() void {
			StorageServer.reset();
			StorageClient.reset();
		}

		pub fn onLoadClient(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onLoadClient", .{});
		}
		pub fn onUnloadClient(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onUnloadClient", .{});
		}
		pub fn onLoadServer(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onLoadServer", .{});
		}
		pub fn onUnloadServer(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onUnloadServer", .{});
		}
		pub fn onPlaceClient(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onPlaceClient", .{});
			StorageClient.add(pos, .{.contents = 0}, chunk);
		}
		pub fn onBreakClient(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onBreakClient", .{});
			StorageClient.remove(pos, chunk);
		}
		pub fn onPlaceServer(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onPlaceServer", .{});
			StorageServer.add(pos, .{.contents = 0}, chunk);
		}
		pub fn onBreakServer(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onBreakServer", .{});
			StorageServer.remove(pos, chunk);
		}
		pub fn onInteract(pos: Vec3i, chunk: *Chunk) EventStatus {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			const data = StorageClient.get(pos, chunk);
			if(data == null) std.log.debug("Chest.onInteract: null", .{}) else std.log.debug("Chest.onInteract: {}", .{data.?.contents});

			return .handled;
		}
	};
};

var entityDataClasses: std.StringHashMapUnmanaged(EntityDataClass) = .{};

pub fn init() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		const class = EntityDataClass.init(@field(EntityDataClasses, declaration.name));
		entityDataClasses.putNoClobber(main.globalAllocator.allocator, class.id, class) catch unreachable;
		std.log.debug("Registered EntityDataClass '{s}'", .{class.id});
	}
}

pub fn reset() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		@field(EntityDataClasses, declaration.name).reset();
	}
}

pub fn deinit() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		@field(EntityDataClasses, declaration.name).deinit();
	}
	entityDataClasses.deinit(main.globalAllocator.allocator);
}

pub fn getByID(_id: ?[]const u8) ?*EntityDataClass {
	const id = _id orelse return null;
	if(entityDataClasses.getPtr(id)) |cls| return cls;
	std.log.err("EntityDataClass with id '{s}' not found", .{id});
	return null;
}
