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
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;

pub const BlockEntityIndex = main.utils.DenseId(u32);

pub const BlockEntityType = struct {
	id: []const u8,
	vtable: VTable,

	const VTable = struct {
		onLoadClient: *const fn(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void,
		onUnloadClient: *const fn(dataIndex: BlockEntityIndex) void,
		onLoadServer: *const fn(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void,
		onStoreServerToDisk: *const fn(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void,
		onStoreServerToClient: *const fn(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void,
		onUnloadServer: *const fn(dataIndex: BlockEntityIndex) void,
		onPlaceClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlaceServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onInteract: *const fn(pos: Vec3i, chunk: *Chunk) EventStatus,
		updateClientData: *const fn(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void,
		updateServerData: *const fn(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void,
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
	pub inline fn onStoreServerToDisk(self: *BlockEntityType, dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
		return self.vtable.onStoreServerToDisk(dataIndex, writer);
	}
	pub inline fn onStoreServerToClient(self: *BlockEntityType, dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
		return self.vtable.onStoreServerToClient(dataIndex, writer);
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
	pub inline fn updateClientData(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
		return try self.vtable.updateClientData(pos, chunk, reader);
	}
	pub inline fn updateServerData(self: *BlockEntityType, pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
		return try self.vtable.updateServerData(pos, chunk, reader);
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

fn BlockEntityDataStorage(T: type) type {
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

		pub fn onLoadClient(_: Vec3i, _: *Chunk, _: *BinaryReader) BinaryReader.AllErrors!void {}
		pub fn onUnloadClient(_: BlockEntityIndex) void {}
		pub fn onLoadServer(_: Vec3i, _: *Chunk, _: *BinaryReader) BinaryReader.AllErrors!void {}
		pub fn onStoreServerToDisk(_: BlockEntityIndex, _: *BinaryWriter) void {}
		pub fn onStoreServerToClient(_: BlockEntityIndex, _: *BinaryWriter) void {}
		pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			_ = StorageServer.removeAtIndex(dataIndex) orelse unreachable;
		}
		pub fn onPlaceClient(_: Vec3i, _: *Chunk) void {}
		pub fn onBreakClient(_: Vec3i, _: *Chunk) void {}
		pub fn onPlaceServer(_: Vec3i, _: *Chunk) void {}
		pub fn onBreakServer(pos: Vec3i, chunk: *Chunk) void {
			_ = StorageServer.remove(pos, chunk) orelse return;
		}
		pub fn onInteract(pos: Vec3i, _: *Chunk) EventStatus {
			if(main.KeyBoard.key("shift").pressed) return .ignored;

			const inventory = main.items.Inventory.init(main.globalAllocator, 20, .normal, .{.blockInventory = pos});

			main.gui.windowlist.chest.setInventory(inventory);
			main.gui.openWindow("chest");
			main.Window.setMouseGrabbed(false);

			return .handled;
		}

		pub fn updateClientData(_: Vec3i, _: *Chunk, _: *BinaryReader) BinaryReader.AllErrors!void {}
		pub fn updateServerData(_: Vec3i, _: *Chunk, _: *BinaryReader) BinaryReader.AllErrors!void {}
		pub fn getServerToClientData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}
		pub fn getClientToServerData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}
	};

	pub const Sign = struct {
		const StorageServer = BlockEntityDataStorage(struct {
			text: []const u8,
		});
		const StorageClient = BlockEntityDataStorage(struct {
			text: []const u8,
			renderedTexture: ?main.graphics.Texture = null,
		});

		pub const id = "sign";
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

		pub fn onUnloadClient(dataIndex: BlockEntityIndex) void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			const entry = StorageClient.removeAtIndex(dataIndex) orelse unreachable;
			main.globalAllocator.free(entry.text);
		}
		pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			const entry = StorageServer.removeAtIndex(dataIndex) orelse unreachable;
			main.globalAllocator.free(entry.text);
		}
		pub fn onPlaceClient(pos: Vec3i, chunk: *Chunk) void {
			const entry = StorageClient.remove(pos, chunk) orelse return;
			main.globalAllocator.free(entry.text);
		}
		pub fn onBreakClient(pos: Vec3i, chunk: *Chunk) void {
			const entry = StorageClient.remove(pos, chunk) orelse return;
			main.globalAllocator.free(entry.text);
		}
		pub fn onPlaceServer(pos: Vec3i, chunk: *Chunk) void {
			const entry = StorageServer.remove(pos, chunk) orelse return;
			main.globalAllocator.free(entry.text);
		}
		pub fn onBreakServer(pos: Vec3i, chunk: *Chunk) void {
			const entry = StorageServer.remove(pos, chunk) orelse return;
			main.globalAllocator.free(entry.text);
		}
		pub fn onInteract(pos: Vec3i, chunk: *Chunk) EventStatus {
			if(main.KeyBoard.key("shift").pressed) return .ignored;

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			const data = StorageClient.get(pos, chunk); // TODO: orelse return .ignored;
			main.gui.windowlist.sign_editor.openFromSignData(pos, if(data) |_data| _data.text else "TODO: Remove");

			return .handled;
		}

		pub const onLoadClient = updateClientData;
		pub fn updateClientData(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			const data = StorageClient.getOrPut(pos, chunk);
			if(data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
			data.valuePtr.text = main.globalAllocator.dupe(u8, reader.remaining);
		}

		pub const onLoadServer = updateServerData;
		pub fn updateServerData(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getOrPut(pos, chunk);
			if(data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
			data.valuePtr.text = main.globalAllocator.dupe(u8, reader.remaining);
		}

		pub const onStoreServerToClient = onStoreServerToDisk;
		pub fn onStoreServerToDisk(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getByIndex(dataIndex) orelse return;
			writer.writeSlice(data.text);
		}
		pub fn getServerToClientData(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.get(pos, chunk) orelse return;
			writer.writeSlice(data.text);
		}

		pub fn getClientToServerData(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			const data = StorageClient.get(pos, chunk) orelse return;
			writer.writeSlice(data.text);
		}

		pub fn updateTextFromClient(pos: Vec3i, newText: []const u8) void {
			{
				const mesh = main.renderer.mesh_storage.getMeshAndIncreaseRefCount(.initFromWorldPos(pos, 1)) orelse return;
				defer mesh.decreaseRefCount();
				mesh.mutex.lock();
				defer mesh.mutex.unlock();
				const index = mesh.chunk.getLocalBlockIndex(pos);
				const block = mesh.chunk.data.getValue(index);
				const blockEntity = block.blockEntity() orelse return;
				if(!std.mem.eql(u8, blockEntity.id, id)) return;

				StorageClient.mutex.lock();
				defer StorageClient.mutex.unlock();

				const data = StorageClient.getOrPut(pos, mesh.chunk);
				if(data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
				data.valuePtr.text = main.globalAllocator.dupe(u8, newText);
			}

			main.network.Protocols.blockEntityUpdate.sendClientDataUpdateToServer(main.game.world.?.conn, pos);
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
