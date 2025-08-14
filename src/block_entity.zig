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

pub const BlockEntityIndex = main.utils.DenseId(u32);

const UpdateEvent = union(enum) {
	remove: void,
	update: *BinaryReader,
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

			const dataIndex = chunk.blockPosToEntityDataMap.get(blockIndex) orelse return null;
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
		const inventorySize = 20;
		const StorageServer = BlockEntityDataStorage(struct {
			invId: main.items.Inventory.InventoryId,
		});
		const StorageClient = BlockEntityDataStorage(struct {
			pos: Vec3i,
			angle: f32,
			shouldBeOpen: bool,
		});

		var pipeline: graphics.Pipeline = undefined;
		var uniforms: struct {
			projectionMatrix: c_int,
			viewMatrix: c_int,
			modelMatrix: c_int,
			playerPositionInteger: c_int,
			playerPositionFraction: c_int,
			screenSize: c_int,
			ambientLight: c_int,
			contrast: c_int,
			@"fog.color": c_int,
			@"fog.density": c_int,
			@"fog.fogLower": c_int,
			@"fog.fogHigher": c_int,
			reflectionMapSize: c_int,
			lodDistance: c_int,
			zNear: c_int,
			zFar: c_int,
		} = undefined;

		pub const id = "chest";
		pub fn init() void {
			StorageServer.init();
			StorageClient.init();
			lastUpdateTime = std.time.milliTimestamp();
			pipeline = graphics.Pipeline.init(
				"assets/cubyz/shaders/block_entity/chest.vert",
				"assets/cubyz/shaders/block_entity/chest.frag",
				"",
				&uniforms,
				.{},
				.{.depthTest = true, .depthWrite = true},
				.{.attachments = &.{.noBlending}},
			);
		}
		pub fn deinit() void {
			StorageServer.deinit();
			StorageClient.deinit();
			pipeline.deinit();
		}
		pub fn reset() void {
			StorageServer.reset();
			StorageClient.reset();
			lastUpdateTime = std.time.milliTimestamp();
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

		fn onInventoryOpenCallback(source: main.items.Inventory.Source) void {
			var block = main.server.world.?.getBlock(source.blockInventory[0], source.blockInventory[1], source.blockInventory[2]) orelse return;
			block.data |= 4;
			main.server.world.?.updateBlock(source.blockInventory[0], source.blockInventory[1], source.blockInventory[2], block);
			main.network.Protocols.blockEntityUpdate.sendServerDataUpdateToClients(source.blockInventory);
		}

		fn onInventoryClosedCallback(source: main.items.Inventory.Source) void {
			main.network.Protocols.blockEntityUpdate.sendServerDataUpdateToClients(source.blockInventory);
		}

		const inventoryCallbacks: main.items.Inventory.Callbacks = .{
			.onUpdateCallback = &onInventoryUpdateCallback,
			.onFirstOpenCallback = &onInventoryOpenCallback,
			.onLastCloseCallback = &onInventoryClosedCallback,
		};

		pub fn onLoadClient(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
			return updateClientData(pos, chunk, .{.update = reader});
		}
		pub fn onUnloadClient(dataIndex: BlockEntityIndex) void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			_ = StorageClient.removeAtIndex(dataIndex) orelse unreachable;
		}

		pub fn onLoadServer(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getOrPut(pos, chunk);
			std.debug.assert(!data.foundExisting);
			data.valuePtr.invId = main.items.Inventory.Sync.ServerSide.createExternallyManagedInventory(inventorySize, .normal, .{.blockInventory = pos}, reader, inventoryCallbacks);
		}

		pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
			StorageServer.mutex.lock();
			const data = StorageServer.removeAtIndex(dataIndex) orelse unreachable;
			StorageServer.mutex.unlock();
			main.items.Inventory.Sync.ServerSide.destroyExternallyManagedInventory(data.invId);
		}
		pub fn onStoreServerToClient(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			const data = StorageServer.getByIndex(dataIndex) orelse return;

			const hasClients = main.items.Inventory.Sync.ServerSide.getServerInventoryFromId(data.invId).users.items.len != 0;
			
			writer.writeInt(u1, @intFromBool(hasClients));
		}
		pub fn onStoreServerToDisk(dataIndex: BlockEntityIndex, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			const data = StorageServer.getByIndex(dataIndex) orelse return;

			const inv = main.items.Inventory.Sync.ServerSide.getServerInventoryFromId(data.invId);
			var isEmpty: bool = true;
			for(inv.inv._items) |item| {
				if(item.amount != 0) isEmpty = false;
			}
			if(isEmpty) return;
			inv.inv.toBytes(writer);
		}
		pub fn onInteract(pos: Vec3i, _: *Chunk) EventStatus {
			if(main.KeyBoard.key("shift").pressed) return .ignored;

			main.network.Protocols.blockEntityUpdate.sendClientDataUpdateToServer(main.game.world.?.conn, pos);

			const inventory = main.items.Inventory.init(main.globalAllocator, inventorySize, .normal, .{.blockInventory = pos}, .{});

			main.gui.windowlist.chest.setInventory(inventory);
			main.gui.openWindow("chest");
			main.Window.setMouseGrabbed(false);

			return .handled;
		}

		pub fn updateClientData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
			if(event == .remove) {
				_ = StorageClient.remove(pos, chunk) orelse return;
				return;
			}

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			const data = StorageClient.getOrPut(pos, chunk);
			if(!data.foundExisting) {
				data.valuePtr.* = .{
					.angle = 0,
					.pos = pos,
					.shouldBeOpen = false
				};
			}
			if(event.update.remaining.len != 0) {
				data.valuePtr.shouldBeOpen = try event.update.readInt(u1) != 0;
			}
		}

		pub fn updateServerData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
			switch(event) {
				.remove => {
					const chest = StorageServer.remove(pos, chunk) orelse return;
					main.items.Inventory.Sync.ServerSide.destroyAndDropExternallyManagedInventory(chest.invId, pos);
				},
				.update => |_| {
					StorageServer.mutex.lock();
					defer StorageServer.mutex.unlock();
					const data = StorageServer.getOrPut(pos, chunk);
					if(data.foundExisting) return;
					var reader = BinaryReader.init(&.{});
					data.valuePtr.invId = main.items.Inventory.Sync.ServerSide.createExternallyManagedInventory(inventorySize, .normal, .{.blockInventory = pos}, &reader, inventoryCallbacks);
				},
			}
		}

		pub fn getServerToClientData(pos: Vec3i, chunk: *Chunk, writer: *BinaryWriter) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.get(pos, chunk) orelse return;
			
			const hasClients = main.items.Inventory.Sync.ServerSide.getServerInventoryFromId(data.invId).users.items.len != 0;
			
			writer.writeInt(u1, @intFromBool(hasClients));
		}

		pub fn getClientToServerData(_: Vec3i, _: *Chunk, _: *BinaryWriter) void {}

		var lastUpdateTime: i64 = 0;
		pub fn renderAll(projMatrix: Mat4f, ambientLight: Vec3f, playerPosition: Vec3d) void {
			const newTime = std.time.milliTimestamp();
			const deltaTime = @as(f32, @floatFromInt(newTime - lastUpdateTime))/1000.0;
			lastUpdateTime = newTime;

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			for(StorageClient.storage.dense.items) |*chest| {
				var block = main.renderer.mesh_storage.getBlockFromRenderThread(chest.pos[0], chest.pos[1], chest.pos[2]) orelse continue;
				
				if(block.data >= 4) {
					if(chest.shouldBeOpen) {
						chest.angle += deltaTime * 270.0;
						if (chest.angle > 90.0) {
							chest.angle = 90.0;
						}
					} else {
						chest.angle -= deltaTime * 270.0;
						if (chest.angle < 0.0) {
							chest.angle = 0.0;
							const newBlock = main.blocks.Block{.typ = block.typ, .data = block.data & 3};
							main.renderer.MeshSelection.updateBlockAndSendUpdate(main.game.Player.inventory, 0, chest.pos[0], chest.pos[1], chest.pos[2], block, newBlock);
							continue;
						}
					}

					const rotation: f32 = switch(block.data & 3) {
						0 => std.math.pi / 2.0,
						1 => -std.math.pi / 2.0,
						2 => std.math.pi,
						3 => 0,
						else => unreachable,
					};
					block.data = 4;
					const height = main.blocks.meshes.model(block).model().max[2];
					var modelMatrix = Mat4f.translation(.{0, 0, height});
					modelMatrix = modelMatrix.mul(Mat4f.translation(.{0.5, 0.5, 0}));
					modelMatrix = modelMatrix.mul(Mat4f.rotationZ(rotation));
					modelMatrix = modelMatrix.mul(Mat4f.translation(.{-0.5, -0.5, 0}));
					modelMatrix = modelMatrix.mul(Mat4f.rotationX(std.math.degreesToRadians(chest.angle)));
					block.data = 8;

					var faceData: main.ListUnmanaged(main.renderer.chunk_meshing.FaceData) = .{};
					defer faceData.deinit(main.stackAllocator);
					const model = main.blocks.meshes.model(block).model();
					if(block.hasBackFace()) {
						model.appendInternalQuadsToList(&faceData, main.stackAllocator, block, 1, 1, 1, true);
						for(main.chunk.Neighbor.iterable) |neighbor| {
							model.appendNeighborFacingQuadsToList(&faceData, main.stackAllocator, block, neighbor, 1, 1, 1, true);
						}
					}
					model.appendInternalQuadsToList(&faceData, main.stackAllocator, block, 1, 1, 1, false);
					for(main.chunk.Neighbor.iterable) |neighbor| {
						model.appendNeighborFacingQuadsToList(&faceData, main.stackAllocator, block, neighbor, 1 + neighbor.relX(), 1 + neighbor.relY(), 1 + neighbor.relZ(), false);
					}

					for(faceData.items) |*face| {
						face.position.lightIndex = 0;
					}
					var allocation: graphics.SubAllocation = .{.start = 0, .len = 0};
					main.renderer.chunk_meshing.faceBuffers[0].uploadData(faceData.items, &allocation);
					defer main.renderer.chunk_meshing.faceBuffers[0].free(allocation);
					var lightAllocation: graphics.SubAllocation = .{.start = 0, .len = 0};
					var lightVals: [6]u8 = main.renderer.mesh_storage.getLight(chest.pos[0], chest.pos[1], chest.pos[2]) orelse @splat(0);
					inline for(&lightVals) |*val| {
						val.* = @as(u8, @intFromFloat(@as(f32, @floatFromInt(val.*)) * 0.8));
					}
					const light = (@as(u32, lightVals[0] >> 3) << 25 |
						@as(u32, lightVals[1] >> 3) << 20 |
						@as(u32, lightVals[2] >> 3) << 15 |
						@as(u32, lightVals[3] >> 3) << 10 |
						@as(u32, lightVals[4] >> 3) << 5 |
						@as(u32, lightVals[5] >> 3) << 0);
					main.renderer.chunk_meshing.lightBuffers[0].uploadData(&.{light, light, light, light}, &lightAllocation);
					defer main.renderer.chunk_meshing.lightBuffers[0].free(lightAllocation);

					var chunkAllocation: graphics.SubAllocation = .{.start = 0, .len = 0};
					main.renderer.chunk_meshing.chunkBuffer.uploadData(&.{.{
						.position = .{0, 0, 0},
						.min = undefined,
						.max = undefined,
						.voxelSize = 1,
						.lightStart = lightAllocation.start,
						.vertexStartOpaque = undefined,
						.faceCountsByNormalOpaque = undefined,
						.vertexStartTransparent = undefined,
						.vertexCountTransparent = undefined,
						.visibilityState = 0,
						.oldVisibilityState = 0,
					}}, &chunkAllocation);
					defer main.renderer.chunk_meshing.chunkBuffer.free(chunkAllocation);
					
					pipeline.bind(null);
					c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));

					c.glUniform1f(uniforms.reflectionMapSize, main.renderer.reflectionCubeMapSize);

					c.glUniform1f(uniforms.contrast, 0);

					c.glUniform1f(uniforms.lodDistance, main.settings.@"lod0.5Distance");

					c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&main.game.camera.viewMatrix));

					c.glUniform3f(uniforms.ambientLight, ambientLight[0], ambientLight[1], ambientLight[2]);

					c.glUniform1f(uniforms.zNear, main.renderer.zNear);
					c.glUniform1f(uniforms.zFar, main.renderer.zFar);

					const playerPos = playerPosition - @as(Vec3d, @floatFromInt(chest.pos)) + Vec3d{1, 1, 1};
					c.glUniform3i(uniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
					c.glUniform3f(uniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));
					c.glUniformMatrix4fv(uniforms.modelMatrix, 1, c.GL_TRUE, @ptrCast(&modelMatrix));
					
					c.glBindVertexArray(main.renderer.chunk_meshing.vao);

					main.renderer.chunk_meshing.faceBuffers[0].ssbo.bind(main.renderer.chunk_meshing.faceBuffers[0].binding);
					main.renderer.chunk_meshing.lightBuffers[0].ssbo.bind(main.renderer.chunk_meshing.lightBuffers[0].binding);
					c.glActiveTexture(c.GL_TEXTURE0);
					main.blocks.meshes.blockTextureArray.bind();
					c.glActiveTexture(c.GL_TEXTURE1);
					main.blocks.meshes.emissionTextureArray.bind();
					c.glActiveTexture(c.GL_TEXTURE2);
					main.blocks.meshes.reflectivityAndAbsorptionTextureArray.bind();
					c.glDrawElementsInstancedBaseVertexBaseInstance(c.GL_TRIANGLES, @intCast(6*faceData.items.len), c.GL_UNSIGNED_INT, null, 1, allocation.start*4, chunkAllocation.start);
				}
			}
		}
	};

	pub const Sign = struct {
		const StorageServer = BlockEntityDataStorage(struct {
			text: []const u8,
		});
		const StorageClient = BlockEntityDataStorage(struct {
			text: []const u8,
			renderedTexture: ?main.graphics.Texture = null,
			blockPos: Vec3i,
			block: main.blocks.Block,

			fn deinit(self: @This()) void {
				main.globalAllocator.free(self.text);
				if(self.renderedTexture) |texture| {
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

		pub const id = "sign";
		pub fn init() void {
			StorageServer.init();
			StorageClient.init();
			textureDeinitList = .init(main.globalAllocator);

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
		pub fn deinit() void {
			while(textureDeinitList.popOrNull()) |texture| {
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

		pub fn onUnloadClient(dataIndex: BlockEntityIndex) void {
			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			const entry = StorageClient.removeAtIndex(dataIndex) orelse unreachable;
			entry.deinit();
		}
		pub fn onUnloadServer(dataIndex: BlockEntityIndex) void {
			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();
			const entry = StorageServer.removeAtIndex(dataIndex) orelse unreachable;
			main.globalAllocator.free(entry.text);
		}
		pub fn onInteract(pos: Vec3i, chunk: *Chunk) EventStatus {
			if(main.KeyBoard.key("shift").pressed) return .ignored;

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();
			const data = StorageClient.get(pos, chunk);
			main.gui.windowlist.sign_editor.openFromSignData(pos, if(data) |_data| _data.text else "");

			return .handled;
		}

		pub fn onLoadClient(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
			return updateClientData(pos, chunk, .{.update = reader});
		}
		pub fn updateClientData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
			if(event == .remove or event.update.remaining.len == 0) {
				const entry = StorageClient.remove(pos, chunk) orelse return;
				entry.deinit();
				return;
			}

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			const data = StorageClient.getOrPut(pos, chunk);
			if(data.foundExisting) {
				data.valuePtr.deinit();
			}
			data.valuePtr.* = .{
				.blockPos = pos,
				.block = chunk.data.getValue(chunk.getLocalBlockIndex(pos)),
				.renderedTexture = null,
				.text = main.globalAllocator.dupe(u8, event.update.remaining),
			};
		}

		pub fn onLoadServer(pos: Vec3i, chunk: *Chunk, reader: *BinaryReader) BinaryReader.AllErrors!void {
			return updateServerData(pos, chunk, .{.update = reader});
		}
		pub fn updateServerData(pos: Vec3i, chunk: *Chunk, event: UpdateEvent) BinaryReader.AllErrors!void {
			if(event == .remove or event.update.remaining.len == 0) {
				const entry = StorageServer.remove(pos, chunk) orelse return;
				main.globalAllocator.free(entry.text);
				return;
			}

			StorageServer.mutex.lock();
			defer StorageServer.mutex.unlock();

			const data = StorageServer.getOrPut(pos, chunk);
			if(data.foundExisting) main.globalAllocator.free(data.valuePtr.text);
			data.valuePtr.text = main.globalAllocator.dupe(u8, event.update.remaining);
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
				const mesh = main.renderer.mesh_storage.getMesh(.initFromWorldPos(pos, 1)) orelse return;
				mesh.mutex.lock();
				defer mesh.mutex.unlock();
				const index = mesh.chunk.getLocalBlockIndex(pos);
				const block = mesh.chunk.data.getValue(index);
				const blockEntity = block.blockEntity() orelse return;
				if(!std.mem.eql(u8, blockEntity.id, id)) return;

				StorageClient.mutex.lock();
				defer StorageClient.mutex.unlock();

				const data = StorageClient.getOrPut(pos, mesh.chunk);
				if(data.foundExisting) {
					data.valuePtr.deinit();
				}
				data.valuePtr.* = .{
					.blockPos = pos,
					.block = mesh.chunk.data.getValue(mesh.chunk.getLocalBlockIndex(pos)),
					.renderedTexture = null,
					.text = main.globalAllocator.dupe(u8, newText),
				};
			}

			main.network.Protocols.blockEntityUpdate.sendClientDataUpdateToServer(main.game.world.?.conn, pos);
		}

		pub fn renderAll(projectionMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
			var oldFramebufferBinding: c_int = undefined;
			c.glGetIntegerv(c.GL_DRAW_FRAMEBUFFER_BINDING, &oldFramebufferBinding);

			StorageClient.mutex.lock();
			defer StorageClient.mutex.unlock();

			for(StorageClient.storage.dense.items) |*signData| {
				if(signData.renderedTexture != null) continue;

				c.glViewport(0, 0, textureWidth, textureHeight);
				defer c.glViewport(0, 0, main.Window.width, main.Window.height);

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

			outer: for(StorageClient.storage.dense.items) |signData| {
				if(main.blocks.meshes.model(signData.block).model().internalQuads.len == 0) continue;
				const quad = main.blocks.meshes.model(signData.block).model().internalQuads[0];

				signData.renderedTexture.?.bindTo(0);

				c.glUniform1i(uniforms.quadIndex, @intFromEnum(quad));
				const mesh = main.renderer.mesh_storage.getMesh(main.chunk.ChunkPosition.initFromWorldPos(signData.blockPos, 1)) orelse continue :outer;
				const light: [4]u32 = main.renderer.chunk_meshing.PrimitiveMesh.getLight(mesh, signData.blockPos -% Vec3i{mesh.pos.wx, mesh.pos.wy, mesh.pos.wz}, 0, quad);
				c.glUniform4ui(uniforms.lightData, light[0], light[1], light[2], light[3]);
				c.glUniform3i(uniforms.chunkPos, signData.blockPos[0] & ~main.chunk.chunkMask, signData.blockPos[1] & ~main.chunk.chunkMask, signData.blockPos[2] & ~main.chunk.chunkMask);
				c.glUniform3i(uniforms.blockPos, signData.blockPos[0] & main.chunk.chunkMask, signData.blockPos[1] & main.chunk.chunkMask, signData.blockPos[2] & main.chunk.chunkMask);

				c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
			}
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

pub fn renderAll(projectionMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
	inline for(@typeInfo(BlockEntityTypes).@"struct".decls) |declaration| {
		@field(BlockEntityTypes, declaration.name).renderAll(projectionMatrix, ambientLight, playerPos);
	}
}
