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

const UpdateEvent = union(enum) {
	update: *BinaryReader,
};

pub const ErrorSet = BinaryReader.AllErrors || error{Invalid};

const BlockEntityComponentTypeIndex = main.utils.DenseId(u16);

pub const BlockEntityType = struct { // MARK: BlockEntityType
	id: []const u8,
	index: BlockEntityComponentTypeIndex = .noValue,
	vtable: VTable,

	const VTable = struct {
		onLoadClient: *const fn (entity: BlockEntity, block: Block, reader: *BinaryReader) ErrorSet!void,
		onUnloadClient: *const fn (entity: BlockEntity) void,
		onLoadServer: *const fn (entity: BlockEntity, block: Block, reader: *BinaryReader) ErrorSet!void,
		onUnloadServer: *const fn (entity: BlockEntity) void,
		onStoreServerToDisk: *const fn (entity: BlockEntity, writer: *BinaryWriter) void,
		onStoreServerToClient: *const fn (entity: BlockEntity, writer: *BinaryWriter) void,
		onInteract: *const fn (pos: Vec3i, chunk: *Chunk) main.callbacks.Result,
		updateClientData: *const fn (entity: BlockEntity, block: main.blocks.Block, event: UpdateEvent) ErrorSet!void,
		updateServerData: *const fn (pos: Vec3i, chunk: *Chunk, event: UpdateEvent) ErrorSet!void,
		getServerToClientData: *const fn (pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void,
		getClientToServerData: *const fn (pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void,
		removeClient: *const fn (entity: BlockEntity) void,
		removeServer: *const fn (entity: BlockEntity) void,
	};
	pub fn init(comptime BlockEntityTypeT: type, comptime id: []const u8) BlockEntityType {
		BlockEntityTypeT.init();
		var class = BlockEntityType{
			.id = id,
			.vtable = undefined,
		};

		inline for (@typeInfo(BlockEntityType.VTable).@"struct".fields) |field| {
			if (!@hasDecl(BlockEntityTypeT, field.name)) {
				@compileError("BlockEntityType missing field '" ++ field.name ++ "'");
			}
			@field(class.vtable, field.name) = &@field(BlockEntityTypeT, field.name);
		}
		return class;
	}
	pub inline fn onLoadClient(self: *const BlockEntityType, entity: BlockEntity, block: Block, reader: *BinaryReader) ErrorSet!void {
		return self.vtable.onLoadClient(entity, block, reader);
	}
	pub inline fn onUnloadClient(self: *const BlockEntityType, entity: BlockEntity) void {
		return self.vtable.onUnloadClient(entity);
	}
	pub inline fn onLoadServer(self: *const BlockEntityType, entity: BlockEntity, block: Block, reader: *BinaryReader) ErrorSet!void {
		return self.vtable.onLoadServer(entity, block, reader);
	}
	pub inline fn onUnloadServer(self: *const BlockEntityType, entity: BlockEntity) void {
		return self.vtable.onUnloadServer(entity);
	}
	pub inline fn onStoreServerToDisk(self: *const BlockEntityType, entity: BlockEntity, writer: *BinaryWriter) void {
		return self.vtable.onStoreServerToDisk(entity, writer);
	}
	pub inline fn onStoreServerToClient(self: *const BlockEntityType, entity: BlockEntity, writer: *BinaryWriter) void {
		return self.vtable.onStoreServerToClient(entity, writer);
	}
	pub inline fn onInteract(self: *const BlockEntityType, pos: Vec3i, chunk: *Chunk) main.callbacks.Result {
		return self.vtable.onInteract(pos, chunk);
	}
	pub inline fn updateClientData(self: *const BlockEntityType, entity: BlockEntity, block: main.blocks.Block, event: UpdateEvent) ErrorSet!void {
		return try self.vtable.updateClientData(entity, block, event);
	}
	pub inline fn updateServerData(self: *const BlockEntityType, pos: Vec3i, chunk: *Chunk, event: UpdateEvent) ErrorSet!void {
		return try self.vtable.updateServerData(pos, chunk, event);
	}
	pub inline fn getServerToClientData(self: *const BlockEntityType, pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
		return self.vtable.getServerToClientData(pos, chunk, writer);
	}
	pub inline fn getClientToServerData(self: *const BlockEntityType, pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
		return self.vtable.getClientToServerData(pos, chunk, writer);
	}
	pub inline fn removeClient(self: *const BlockEntityType, entity: BlockEntity) void {
		return self.vtable.removeClient(entity);
	}
	pub inline fn removeServer(self: *const BlockEntityType, entity: BlockEntity) void {
		return self.vtable.removeServer(entity);
	}
};

pub const BlockEntity = enum(u32) { // MARK: BlockEntity
	noValue = std.math.maxInt(u32),
	_,

	var freeIndexList: main.ListUnmanaged(BlockEntity) = .{};
	var nextIndex: BlockEntity = @enumFromInt(0);
	var mutex: std.Thread.Mutex = .{};

	fn globalDeinit() void {
		freeIndexList.deinit(main.globalAllocator);
		nextIndex = undefined;
		freeIndexList = undefined;
	}

	fn reset() void {
		freeIndexList.clearRetainingCapacity();
		nextIndex = @enumFromInt(0);
	}

	fn createIndex() BlockEntity {
		mutex.lock();
		defer mutex.unlock();
		return freeIndexList.popOrNull() orelse {
			defer nextIndex = @enumFromInt(@intFromEnum(nextIndex) + 1);
			return nextIndex;
		};
	}

	fn destroyIndex(self: BlockEntity) void {
		mutex.lock();
		defer mutex.unlock();
		freeIndexList.append(main.globalAllocator, self);
	}

	pub fn init(pos: Vec3i, chunk: *Chunk) BlockEntity {
		const self = createIndex();
		if (@intFromEnum(self) >= sharedBlockEntityData.committedCapacity) {
			sharedBlockEntityDataMutex.lock();
			defer sharedBlockEntityDataMutex.unlock();
			sharedBlockEntityData.ensureCapacity(@intFromEnum(self) + 1);
		}
		self.sharedData().* = .{
			.components = .{},
			.pos = pos,
		};
		const localPos = chunk.getLocalBlockPos(pos);

		chunk.blockPosToEntityDataMapMutex.lock();
		chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, localPos, self) catch unreachable;
		chunk.blockPosToEntityDataMapMutex.unlock();

		return self;
	}

	pub fn initAndLoad(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader, comptime side: main.sync.Side) ErrorSet!BlockEntity {
		const self: BlockEntity = .init(pos, chunk);
		const block = chunk.getBlock(pos[0] & main.chunk.chunkMask, pos[1] & main.chunk.chunkMask, pos[2] & main.chunk.chunkMask); // TODO: Load entity types from the data
		if (side == .client) {
			try block.blockEntity().?.onLoadClient(self, block, reader);
		} else {
			try block.blockEntity().?.onLoadServer(self, block, reader);
		}
		return self;
	}

	pub fn deinit(self: BlockEntity, comptime side: main.sync.Side) void {
		for (self.sharedData().components.items) |component| {
			if (side == .client) {
				blockEntityComponentTypes.items[@intFromEnum(component)].removeClient(self);
			} else {
				blockEntityComponentTypes.items[@intFromEnum(component)].removeServer(self);
			}
		}
		self.sharedData().components.deinit(main.globalAllocator);
		self.destroyIndex();
	}

	pub fn removeComponent(self: BlockEntity, componentType: BlockEntityComponentTypeIndex, comptime side: main.sync.Side) void {
		for (self.sharedData().components.items, 0..) |component, i| {
			if (component == componentType) {
				if (side == .client) {
					blockEntityComponentTypes.items[@intFromEnum(component)].removeClient(self);
				} else {
					blockEntityComponentTypes.items[@intFromEnum(component)].removeServer(self);
				}
				_ = self.sharedData().components.swapRemove(i);
				return;
			}
		}
		@panic("Component not found.");
	}

	pub fn sharedData(self: BlockEntity) *SharedBlockEntityData {
		return &sharedBlockEntityData.mem[@intFromEnum(self)];
	}

	fn ComponentStorageType(comptime side: main.sync.Side, comptime id: []const u8) type {
		const Type = @field(BlockEntityTypes, id);
		switch (side) {
			.client => return Type.StorageClient,
			.server => return Type.StorageServer,
		}
	}

	pub fn getComponent(self: BlockEntity, comptime side: main.sync.Side, comptime id: []const u8) ?ComponentStorageType(side, id).DataT {
		const StorageType = ComponentStorageType(side, id);
		StorageType.mutex.lock();
		defer StorageType.mutex.unlock();
		return (StorageType.getByIndex(self) orelse return null).*;
	}
};

var sharedBlockEntityData: main.utils.VirtualList(SharedBlockEntityData, 0xffffffff) = undefined;
var sharedBlockEntityDataMutex: std.Thread.Mutex = .{};

pub const SharedBlockEntityData = struct {
	pos: Vec3i,
	components: main.ListUnmanaged(BlockEntityComponentTypeIndex),
};

pub fn updateClientData(pos: Vec3i, chunk: *Chunk, block: main.blocks.Block, data: *BinaryReader) !void {
	if (block.blockEntity()) |blockEntity| {
		const entity = getOrCreateByPosition(pos, chunk);
		try blockEntity.updateClientData(entity, block, .{.update = data});
	}
}

pub fn getOrCreateByPosition(pos: Vec3i, chunk: *Chunk) BlockEntity {
	const localPos = chunk.getLocalBlockPos(pos);

	{
		chunk.blockPosToEntityDataMapMutex.lock();
		defer chunk.blockPosToEntityDataMapMutex.unlock();
		if (chunk.blockPosToEntityDataMap.get(localPos)) |entity| return entity;
	}
	return BlockEntity.init(pos, chunk);
}

pub fn getByPosition(pos: Vec3i, chunk: *Chunk) ?BlockEntity {
	const localPos = chunk.getLocalBlockPos(pos);

	chunk.blockPosToEntityDataMapMutex.lock();
	defer chunk.blockPosToEntityDataMapMutex.unlock();
	return chunk.blockPosToEntityDataMap.get(localPos);
}

pub fn destroyBlockEntityByPosition(pos: Vec3i, chunk: *Chunk, comptime side: main.sync.Side) void {
	const entity = getByPosition(pos, chunk) orelse return;
	entity.deinit(side);
}

fn BlockEntityDataStorage(T: type) type { // MARK: BlockEntityDataStorage
	return struct {
		pub const DataT = T;
		var storage: main.utils.SparseSet(DataT, BlockEntity) = undefined;
		pub var mutex: std.Thread.Mutex = .{};

		pub fn init() void {
			storage = .{};
		}
		pub fn deinit() void {
			storage.deinit(main.globalAllocator);
			storage = undefined;
		}
		pub fn reset() void {
			storage.clear();
		}
		pub fn add(entity: BlockEntity, value: DataT) void {
			mutex.lock();
			defer mutex.unlock();

			storage.set(main.globalAllocator, entity, value);
		}
		pub fn removeAtIndex(entity: BlockEntity) ?DataT {
			main.utils.assertLocked(&mutex);
			return storage.fetchRemove(entity) catch null;
		}
		pub fn remove2(pos: Vec3i, chunk: *Chunk) ?DataT {
			mutex.lock();
			defer mutex.unlock();

			const localPos = chunk.getLocalBlockPos(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			const entityNullable = chunk.blockPosToEntityDataMap.fetchRemove(localPos);
			chunk.blockPosToEntityDataMapMutex.unlock();

			const entry = entityNullable orelse return null;

			const dataIndex = entry.value;
			return removeAtIndex(dataIndex);
		}
		pub fn getByIndex(entity: BlockEntity) ?*DataT {
			main.utils.assertLocked(&mutex);

			return storage.get(entity);
		}
		pub fn get(pos: Vec3i, chunk: *Chunk) ?*DataT {
			main.utils.assertLocked(&mutex);

			const localPos = chunk.getLocalBlockPos(pos);

			chunk.blockPosToEntityDataMapMutex.lock();
			defer chunk.blockPosToEntityDataMapMutex.unlock();

			const dataIndex = chunk.blockPosToEntityDataMap.get(localPos) orelse return null;
			return storage.get(dataIndex);
		}
		pub const GetOrPutResult = struct {
			valuePtr: *DataT,
			foundExisting: bool,
		};
		pub fn getOrPut(entity: BlockEntity) GetOrPutResult {
			main.utils.assertLocked(&mutex);
			if (getByIndex(entity)) |result| return .{.valuePtr = result, .foundExisting = true};

			return .{.valuePtr = storage.add(main.globalAllocator, entity), .foundExisting = false};
		}
	};
}

pub const BlockEntityTypes = struct { // MARK: BlockEntityTypes
	pub const @"cubyz:chest" = struct { // MARK: cubyz:chest
		const inventorySize = 20;
		const StorageServer = BlockEntityDataStorage(struct {
			invId: main.items.Inventory.InventoryId,
		});

		pub fn init() void {
			StorageServer.init();
		}
		pub fn deinit() void {
			StorageServer.deinit();
		}
		pub fn reset() void {
			StorageServer.reset();
		}

		fn onInventoryUpdateCallback(source: main.items.Inventory.Source) void {
			const pos = source.blockInventory;
			const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
			defer simChunk.decreaseRefCount();
			const ch = simChunk.getChunk() orelse return;
			ch.mutex.lock();
			defer ch.mutex.unlock();
			ch.setChanged();
		}

		const inventoryCallbacks = main.items.Inventory.Callbacks{
			.onUpdateCallback = &onInventoryUpdateCallback,
		};

		pub fn onLoadClient(_: BlockEntity, _: Block, _: *BinaryReader) ErrorSet!void {}
		pub fn onUnloadClient(_: BlockEntity) void {}
		pub fn onLoadServer(entity: BlockEntity, _: Block, reader: *BinaryReader) ErrorSet!void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getOrPut(entity);
			std.debug.assert(!data.foundExisting);
			data.valuePtr.invId = main.items.Inventory.ServerSide.createExternallyManagedInventory(inventorySize, .normal, .{.blockInventory = entity.sharedData().pos}, reader, inventoryCallbacks);
		}

		pub fn onUnloadServer(entity: BlockEntity) void {
			StorageServer.mutex.lock();
			const data = StorageServer.removeAtIndex(entity) orelse unreachable;
			StorageServer.mutex.unlock();
			main.items.Inventory.ServerSide.destroyExternallyManagedInventory(data.invId);
		}
		pub fn onStoreServerToDisk(entity: BlockEntity, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			const data = StorageServer.getByIndex(entity) orelse return;

			const inv = main.items.Inventory.ServerSide.getInventoryFromId(data.invId);
			var isEmpty: bool = true;
			for (inv._items) |item| {
				if (item.amount != 0) isEmpty = false;
			}
			if (isEmpty) return;
			inv.toBytes(writer);
		}
		pub fn onStoreServerToClient(_: BlockEntity, _: *BinaryWriter) void {}
		pub fn onInteract(pos: Vec3i, _: *Chunk) main.callbacks.Result {
			main.network.protocols.blockEntityUpdate.sendClientDataUpdateToServer(main.game.world.?.conn, pos);

			const inventory = main.items.Inventory.ClientInventory.init(main.globalAllocator, inventorySize, .normal, .serverShared, .{.blockInventory = pos}, .{});

			main.gui.windowlist.chest.setInventory(inventory);
			main.gui.openWindow("chest");
			main.Window.setMouseGrabbed(false);

			return .handled;
		}

		pub fn updateClientData(_: BlockEntity, _: main.blocks.Block, _: UpdateEvent) ErrorSet!void {}
		pub fn removeClient(_: BlockEntity) void {}
		pub fn updateServerData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) ErrorSet!void {
			if (true) @panic("TODO");
			switch (event) {
				.update => |_| {
					StorageServer.mutex.lock();
					defer StorageServer.mutex.unlock();
					const data = StorageServer.getOrPut(pos, chunk);
					if (data.foundExisting) return;
					var reader = BinaryReader.init(&.{});
					data.valuePtr.invId = main.items.Inventory.ServerSide.createExternallyManagedInventory(inventorySize, .normal, .{.blockInventory = pos}, &reader, inventoryCallbacks);
				},
			}
		}
		pub fn removeServer(entity: BlockEntity) void {
			const entry = StorageServer.removeAtIndex(entity) orelse return;
			main.items.Inventory.ServerSide.destroyAndDropExternallyManagedInventory(entry.invId, entity.sharedData().pos);
		}
		pub fn getServerToClientData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}
		pub fn getClientToServerData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}

		pub fn renderAll(_: Mat4f, _: Vec3f, _: Vec3d) void {}
	};

	pub const @"cubyz:sign" = struct { // MARK: cubyz:sign
		const StorageServer = BlockEntityDataStorage(struct {
			text: []const u8,
		});
		const StorageClient = BlockEntityDataStorage(struct {
			text: []const u8,
			renderedTexture: ?main.graphics.Texture = null,
			block: main.blocks.Block,

			fn deinit(self: @This()) void {
				main.globalAllocator.free(self.text);
				if (self.renderedTexture) |texture| {
					textureDeinitLock.lock();
					defer textureDeinitLock.unlock();
					textureDeinitList.append(texture);
				}
			}
		});
		var textureDeinitList: main.List(graphics.Texture) = undefined;
		var textureDeinitLock: std.Thread.Mutex = .{};
		var pipeline: graphics.Pipeline = undefined;
		var uniforms: struct {
			ambientLight: c_int,
			projectionMatrix: c_int,
			viewMatrix: c_int,
			playerPositionInteger: c_int,
			playerPositionFraction: c_int,
			quadIndex: c_int,
			lightData: c_int,
			chunkPos: c_int,
			blockPos: c_int,
		} = undefined;

		// TODO: Load these from some per-block settings
		const textureWidth = 128;
		const textureHeight = 72;
		const textureMargin = 4;

		pub fn init() void {
			StorageServer.init();
			StorageClient.init();
			textureDeinitList = .init(main.globalAllocator);
			if (!main.settings.launchConfig.headlessServer) {
				pipeline = graphics.Pipeline.init(
					"assets/cubyz/shaders/block_entity/sign.vert",
					"assets/cubyz/shaders/block_entity/sign.frag",
					"",
					&uniforms,
					.{},
					.{.depthTest = true, .depthCompare = .equal, .depthWrite = false},
					.{.attachments = &.{.alphaBlending}},
				);
			}
		}
		pub fn deinit() void {
			while (textureDeinitList.popOrNull()) |texture| {
				texture.deinit();
			}
			textureDeinitList.deinit();
			pipeline.deinit();
			StorageServer.deinit();
			StorageClient.deinit();
		}
		pub fn reset() void {
			StorageServer.reset();
			StorageClient.reset();
		}

		pub fn onUnloadClient(entity: BlockEntity) void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			const entry = StorageClient.removeAtIndex(entity) orelse unreachable;
			entry.deinit();
		}
		pub fn onUnloadServer(entity: BlockEntity) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			const entry = StorageServer.removeAtIndex(entity) orelse unreachable;
			main.globalAllocator.free(entry.text);
		}
		pub fn onInteract(_: Vec3i, _: *Chunk) main.callbacks.Result { // TODO: Remove
			return .ignored;
		}

		pub fn onLoadClient(entity: BlockEntity, block: Block, reader: *BinaryReader) ErrorSet!void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			const data = StorageClient.getOrPut(entity);
			std.debug.assert(!data.foundExisting);
			data.valuePtr.* = .{
				.block = block,
				.renderedTexture = null,
				.text = main.globalAllocator.dupe(u8, reader.remaining),
			};
		}
		pub fn updateClientData(entity: BlockEntity, block: main.blocks.Block, event: UpdateEvent) ErrorSet!void {
			if (event.update.remaining.len == 0) {
				{
					StorageClient.mutex.lock();
					defer StorageClient.mutex.unlock();
					if (StorageClient.getByIndex(entity) == null) return;
				}
				const index = blockyEntityComponentTypesMap.get("cubyz:sign").?.index; // TODO
				entity.removeComponent(index, .client);
				return;
			}

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			const data = StorageClient.getOrPut(entity);
			if (data.foundExisting) {
				data.valuePtr.deinit();
			}
			data.valuePtr.* = .{
				.block = block,
				.renderedTexture = null,
				.text = main.globalAllocator.dupe(u8, event.update.remaining),
			};
		}
		pub fn removeClient(entity: BlockEntity) void {
			const entry = StorageClient.removeAtIndex(entity) orelse return;
			entry.deinit();
		}

		pub fn onLoadServer(entity: BlockEntity, _: Block, reader: *BinaryReader) ErrorSet!void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getOrPut(entity);
			std.debug.assert(!data.foundExisting);
			data.valuePtr.text = main.globalAllocator.dupe(u8, reader.remaining);
		}
		pub fn updateServerData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) ErrorSet!void {
			if (true) @panic("TODO");
			if (event.update.remaining.len == 0) {
				const entity = getByPosition(pos, chunk) orelse return;
				const index = blockyEntityComponentTypesMap.get("cubyz:sign").?.index; // TODO
				entity.removeComponent(index, .server);
				return;
			}

			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const newText = event.update.remaining;

			if (!std.unicode.utf8ValidateSlice(newText)) {
				std.log.err("Received sign text with invalid UTF-8 characters.", .{});
				return error.Invalid;
			}

			const data = StorageServer.getOrPut(pos, chunk);
			if (data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
			data.valuePtr.text = main.globalAllocator.dupe(u8, event.update.remaining);
		}
		pub fn removeServer(entity: BlockEntity) void {
			const entry = StorageServer.removeAtIndex(entity) orelse return;
			main.globalAllocator.free(entry.text);
		}

		pub const onStoreServerToClient = onStoreServerToDisk;
		pub fn onStoreServerToDisk(entity: BlockEntity, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getByIndex(entity) orelse return;
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

		pub fn updateText(pos: Vec3i, chunk: *Chunk, block: main.blocks.Block, newText: []const u8, side: main.sync.Side) void {
			if (!std.unicode.utf8ValidateSlice(newText)) {
				std.log.err("Received sign text with invalid UTF-8 characters.", .{});
				return;
			}

			const entity = getOrCreateByPosition(pos, chunk);
			if (side == .client) {
				StorageClient.mutex.lock();
				defer StorageClient.mutex.unlock();

				const data = StorageClient.getOrPut(entity);
				if (data.foundExisting) data.valuePtr.deinit();
				data.valuePtr.* = .{
					.block = block,
					.renderedTexture = null,
					.text = main.globalAllocator.dupe(u8, newText),
				};
			} else {
				{
					StorageServer.mutex.lock();
					defer StorageServer.mutex.unlock();

					const data = StorageServer.getOrPut(entity);
					if (data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
					data.valuePtr.* = .{
						.text = main.globalAllocator.dupe(u8, newText),
					};
				}

				const serverChunk: *main.chunk.ServerChunk = @fieldParentPtr("super", chunk);
				serverChunk.mutex.lock();
				serverChunk.setChanged();
				serverChunk.mutex.unlock();
			}
		}

		pub fn renderAll(projectionMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
			var oldFramebufferBinding: c_int = undefined;
			c.glGetIntegerv(c.GL_DRAW_FRAMEBUFFER_BINDING, &oldFramebufferBinding);

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			for (StorageClient.storage.dense.items) |*signData| {
				if (signData.renderedTexture != null) continue;

				var oldViewport: [4]c_int = undefined;
				c.glGetIntegerv(c.GL_VIEWPORT, &oldViewport);
				c.glViewport(0, 0, textureWidth, textureHeight);
				defer c.glViewport(oldViewport[0], oldViewport[1], oldViewport[2], oldViewport[3]);

				var finalFrameBuffer: graphics.FrameBuffer = undefined;
				finalFrameBuffer.init(false, c.GL_NEAREST, c.GL_REPEAT);
				finalFrameBuffer.updateSize(textureWidth, textureHeight, c.GL_RGBA8);
				finalFrameBuffer.bind();
				finalFrameBuffer.clear(.{0, 0, 0, 0});
				signData.renderedTexture = .{.textureID = finalFrameBuffer.texture};
				defer c.glDeleteFramebuffers(1, &finalFrameBuffer.frameBuffer);

				const oldTranslation = graphics.draw.setTranslation(.{textureMargin, textureMargin});
				defer graphics.draw.restoreTranslation(oldTranslation);
				const oldClip = graphics.draw.setClip(.{textureWidth - 2*textureMargin, textureHeight - 2*textureMargin});
				defer graphics.draw.restoreClip(oldClip);

				var textBuffer = graphics.TextBuffer.init(main.stackAllocator, signData.text, .{.color = 0x000000}, false, .center); // TODO: Make the color configurable in the zon
				defer textBuffer.deinit();
				_ = textBuffer.calculateLineBreaks(16, textureWidth - 2*textureMargin);
				textBuffer.renderTextWithoutShadow(0, 0, 16);
			}

			c.glBindFramebuffer(c.GL_FRAMEBUFFER, @bitCast(oldFramebufferBinding));

			pipeline.bind(null);
			c.glBindVertexArray(main.renderer.chunk_meshing.vao);

			c.glUniform3f(uniforms.ambientLight, ambientLight[0], ambientLight[1], ambientLight[2]);
			c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projectionMatrix));
			c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&main.game.camera.viewMatrix));
			c.glUniform3i(uniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
			c.glUniform3f(uniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));

			outer: for (StorageClient.storage.dense.items, 0..) |signData, i| {
				if (main.blocks.meshes.model(signData.block).model().internalQuads.len == 0) continue;
				const quad = main.blocks.meshes.model(signData.block).model().internalQuads[0];
				const blockPos = StorageClient.storage.denseToSparseIndex.items[i].sharedData().pos;

				signData.renderedTexture.?.bindTo(0);

				c.glUniform1i(uniforms.quadIndex, @intFromEnum(quad));
				const mesh = main.renderer.mesh_storage.getMesh(main.chunk.ChunkPosition.initFromWorldPos(blockPos, 1)) orelse continue :outer;
				const light: [4]u32 = main.renderer.chunk_meshing.PrimitiveMesh.getLight(mesh, blockPos -% Vec3i{mesh.pos.wx, mesh.pos.wy, mesh.pos.wz}, 0, quad);
				c.glUniform4ui(uniforms.lightData, light[0], light[1], light[2], light[3]);
				c.glUniform3i(uniforms.chunkPos, blockPos[0] & ~main.chunk.chunkMask, blockPos[1] & ~main.chunk.chunkMask, blockPos[2] & ~main.chunk.chunkMask);
				c.glUniform3i(uniforms.blockPos, blockPos[0] & main.chunk.chunkMask, blockPos[1] & main.chunk.chunkMask, blockPos[2] & main.chunk.chunkMask);

				c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
			}
		}
	};
};

var blockyEntityComponentTypesMap: std.StringHashMapUnmanaged(*BlockEntityType) = .{};
var palette: *main.assets.Palette = undefined;
var blockEntityComponentTypes: main.ListUnmanaged(*BlockEntityType) = undefined;

pub fn globalInit() void {
	sharedBlockEntityData = .init();
	inline for (@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		const class = main.globalArena.create(BlockEntityType);
		class.* = BlockEntityType.init(@field(BlockEntityTypes, declaration.name), declaration.name);
		blockyEntityComponentTypesMap.putNoClobber(main.globalAllocator.allocator, class.id, class) catch unreachable;
		std.log.debug("Registered BlockEntityType '{s}'", .{class.id});
	}
}

pub fn globalDeinit() void {
	inline for (@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).deinit();
	}
	BlockEntity.globalDeinit();
	blockyEntityComponentTypesMap.deinit(main.globalAllocator.allocator);
	sharedBlockEntityData.deinit();
}

pub fn init(palette_: *main.assets.Palette) void {
	palette = palette_;
	blockEntityComponentTypes = .{};
	for (palette.palette.items) |entry| {
		const index = blockEntityComponentTypes.items.len;
		blockEntityComponentTypes.append(main.worldArena, blockyEntityComponentTypesMap.get(entry) orelse blk: {
			std.log.err("Couldn't find block entity with id {s}. Loading may fail.", .{entry});
			break :blk undefined; // TODO: Add an empty placeholder component instead.
		});
		blockEntityComponentTypes.items[index].index = @enumFromInt(@as(u16, @intCast(index)));
	}
	var iterator = blockyEntityComponentTypesMap.valueIterator();
	while (iterator.next()) |componentType| {
		if (componentType.*.index == .noValue) {
			palette.add(componentType.*.id);
			const index = blockEntityComponentTypes.items.len;
			blockEntityComponentTypes.append(main.worldArena, componentType.*);
			blockEntityComponentTypes.items[index].index = @enumFromInt(@as(u16, @intCast(index)));
		}
	}
	std.debug.assert(blockEntityComponentTypes.items.len == palette.palette.items.len);
}

pub fn reset() void {
	inline for (@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).reset();
	}
	BlockEntity.reset();
	blockyEntityComponentTypesMap = undefined;
	palette = undefined;
	blockEntityComponentTypes = undefined;
}

pub fn getByID(_id: ?[]const u8) ?*const BlockEntityType {
	const id = _id orelse return null;
	if (blockyEntityComponentTypesMap.get(id)) |cls| return cls;
	std.log.err("BlockEntityType with id '{s}' not found", .{id});
	return null;
}

pub fn renderAll(projectionMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
	inline for (@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).renderAll(projectionMatrix, ambientLight, playerPos);
	}
}
