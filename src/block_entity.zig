const std = @import("std");

const main = @import("main.zig");
const Vec3i = main.vec.Vec3i;
const Block = main.blocks.Block;
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const getIndex = main.chunk.getIndex;
const server = main.server;
const User = server.User;
const mesh_storage = main.renderer.mesh_storage;

pub const BlockEntityIndex = main.utils.DenseId(u32);

pub const BlockEntityType = struct {
	id: []const u8,
	vtable: VTable,

	const VTable = struct {
		onLoadClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnloadClient: *const fn(dataIndex: BlockEntityIndex) void,
		onLoadServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnloadServer: *const fn(dataIndex: BlockEntityIndex) void,
		onPlaceClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlaceServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onInteract: *const fn(pos: Vec3i, chunk: *Chunk) EventStatus,
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
	pub inline fn onLoadClient(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onLoadClient(pos, chunk);
	}
	pub inline fn onUnloadClient(self: *BlockEntityType, dataIndex: BlockEntityIndex) void {
		return self.vtable.onUnloadClient(dataIndex);
	}
	pub inline fn onLoadServer(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onLoadServer(pos, chunk);
	}
	pub inline fn onUnloadServer(self: *BlockEntityType, dataIndex: BlockEntityIndex) void {
		return self.vtable.onUnloadServer(dataIndex);
	}
	pub inline fn onPlaceClient(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onPlaceClient(pos, chunk);
	}
	pub inline fn onBreakClient(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onBreakClient(pos, chunk);
	}
	pub inline fn onPlaceServer(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onPlaceServer(pos, chunk);
	}
	pub inline fn onBreakServer(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.onBreakServer(pos, chunk);
	}
	pub inline fn onInteract(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk) EventStatus {
		return self.vtable.onInteract(pos, chunk);
	}
};

pub const EventStatus = enum {
	handled,
	ignored,
};

fn BlockEntityDataStorage(T: type) type {
	return struct {
		pub const DataT = T;
		pub const EntryT = struct {
			absoluteBlockPosition: Vec3i,
			data: DataT,
		};
		var freeIndexList: main.ListUnmanaged(BlockEntityIndex) = .{};
		var nextIndex: BlockEntityIndex = @enumFromInt(0);
		var storage: main.utils.SparseSet(EntryT, BlockEntityIndex) = .{};
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
		pub fn add(pos: Vec3i, value: DataT, chunk: *Chunk) void {
			mutex.lock();
			defer mutex.unlock();

			const dataIndex: BlockEntityIndex = freeIndexList.popOrNull() orelse blk: {
				defer nextIndex = @enumFromInt(@intFromEnum(nextIndex) + 1);
				break :blk nextIndex;
			};
			storage.set(main.globalAllocator, dataIndex, value);

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, blockIndex, @intCast(dataIndex)) catch unreachable;
			chunk.blockPosToEntityDataMapMutex.unlock();
		}
		pub fn removeAtIndex(dataIndex: BlockEntityIndex) void {
			main.utils.assertLocked(&mutex);
			freeIndexList.append(main.globalAllocator, dataIndex);
			storage.remove(dataIndex) catch |err| {
				std.log.err("Error while removing block entity: {s}", .{@errorName(err)});
			};
		}
		pub fn remove(pos: Vec3i, chunk: *Chunk) void {
			mutex.lock();
			defer mutex.unlock();

			const blockIndex = chunk.getLocalBlockIndex(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			const entityNullable = chunk.blockPosToEntityDataMap.fetchRemove(blockIndex);
			chunk.blockPosToEntityDataMapMutex.unlock();

			const entry = entityNullable orelse {
				std.log.err("Couldn't remove entity data of block at position {}", .{pos});
				return;
			};

			const dataIndex = entry.value;
			removeAtIndex(dataIndex);
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

pub const BlockEntityTypes = struct {
	pub const Chest = struct {
		const StorageServer = BlockEntityDataStorage(
			struct {
				id: ?u32,
			},
		);

		pub const id = "chest";
		pub fn init() void {
			StorageServer.init();
		}
		pub fn deinit() void {
			StorageServer.deinit();
		}
		pub fn reset() void {
			StorageServer.reset();
		}

		pub fn onLoadClient(_: Vec3i, _: *Chunk) void {}
		pub fn onUnloadClient(_: BlockEntityIndex) void {}
		pub fn onLoadServer(_: Vec3i, _: *Chunk) void {}
		pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			StorageServer.removeAtIndex(dataIndex);
		}
		pub fn onPlaceClient(_: Vec3i, _: *Chunk) void {}
		pub fn onBreakClient(_: Vec3i, _: *Chunk) void {}
		pub fn onPlaceServer(_: Vec3i, _: *Chunk) void {}
		pub fn onBreakServer(pos: Vec3i, chunk: *Chunk) void {
			StorageServer.remove(pos, chunk);
		}
		pub fn onInteract(pos: Vec3i, _: *Chunk) EventStatus {
			if(main.KeyBoard.key("shift").pressed) return .ignored;

			const inventory = main.items.Inventory.init(main.globalAllocator, 20, .normal, .{.blockInventory = pos});

			main.gui.windowlist.chest.setInventory(inventory);
			main.gui.openWindow("chest");
			main.Window.setMouseGrabbed(false);

			return .handled;
		}
	};
};

var blockyEntityTypes: std.StringHashMapUnmanaged(BlockEntityType) = .{};

pub fn init() void {
	inline for(@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		const class = BlockEntityType.init(@field(BlockEntityTypes, declaration.name));
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
