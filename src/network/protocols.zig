const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const Block = main.blocks.Block;
const chunk = main.chunk;
const particles = main.particles;
const items = main.items;
const ZonElement = main.ZonElement;
const game = main.game;
const settings = main.settings;
const renderer = main.renderer;
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const BlockUpdate = renderer.mesh_storage.BlockUpdate;

const network = main.network;
const Connection = network.Connection;

var clientReceiveList: [256]?*const fn(*Connection, *utils.BinaryReader) anyerror!void = @splat(null);
var serverReceiveList: [256]?*const fn(*Connection, *utils.BinaryReader) anyerror!void = @splat(null);
var isAsynchronous: [256]bool = @splat(false);
pub var bytesReceived: [256]Atomic(usize) = @splat(.init(0));
pub var bytesSent: [256]Atomic(usize) = @splat(.init(0));

pub fn init() void { // MARK: init()
	inline for(@typeInfo(@This()).@"struct".decls) |decl| {
		const Protocol = @field(@This(), decl.name);
		if(@TypeOf(Protocol) == type and @hasDecl(Protocol, "id")) {
			const id = Protocol.id;
			if(clientReceiveList[id] == null and serverReceiveList[id] == null) {
				if(@hasDecl(Protocol, "clientReceive")) {
					clientReceiveList[id] = Protocol.clientReceive;
				}
				if(@hasDecl(Protocol, "serverReceive")) {
					serverReceiveList[id] = Protocol.serverReceive;
				}
				isAsynchronous[id] = Protocol.asynchronous;
			} else {
				std.log.err("Duplicate list id {}.", .{id});
			}
		}
	}
}

pub fn onReceive(conn: *Connection, protocolIndex: u8, data: []const u8) !void { // MARK: onReceive()
	const protocolReceive = blk: {
		if(conn.isServerSide()) break :blk serverReceiveList[protocolIndex] orelse return error.Invalid;
		break :blk clientReceiveList[protocolIndex] orelse return error.Invalid;
	};

	if(isAsynchronous[protocolIndex]) {
		ProtocolTask.schedule(conn, protocolIndex, protocolReceive, data);
	} else {
		var reader = utils.BinaryReader.init(data);
		protocolReceive(conn, &reader) catch |err| {
			std.log.debug("Got error while executing protocol {} with data {any}", .{protocolIndex, data});
			return err;
		};
	}

	_ = bytesReceived[protocolIndex].fetchAdd(data.len, .monotonic);
}

const ProtocolTask = struct { // MARK: ProtocolTask
	conn: *Connection,
	protocol: u8,
	protocolReceive: *const fn(*Connection, *utils.BinaryReader) anyerror!void,
	data: []const u8,

	const vtable = utils.ThreadPool.VTable{
		.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.utils.castFunctionSelfToAnyopaque(run),
		.clean = main.utils.castFunctionSelfToAnyopaque(clean),
		.taskType = .misc,
	};

	pub fn schedule(conn: *Connection, protocol: u8, protocolReceive: *const fn(*Connection, *utils.BinaryReader) anyerror!void, data: []const u8) void {
		const task = main.globalAllocator.create(ProtocolTask);
		task.* = ProtocolTask{
			.conn = conn,
			.protocol = protocol,
			.protocolReceive = protocolReceive,
			.data = main.globalAllocator.dupe(u8, data),
		};
		main.threadPool.addTask(task, &vtable);
	}

	pub fn getPriority(_: *ProtocolTask) f32 {
		return std.math.floatMax(f32);
	}

	pub fn isStillNeeded(_: *ProtocolTask) bool {
		return true;
	}

	pub fn run(self: *ProtocolTask) void {
		defer self.clean();
		var reader = utils.BinaryReader.init(self.data);
		self.protocolReceive(self.conn, &reader) catch |err| {
			std.log.err("Got error {s} while executing protocol {} with data {any}", .{@errorName(err), self.protocol, self.data}); // TODO: Maybe disconnect on error
		};
	}

	pub fn clean(self: *ProtocolTask) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.destroy(self);
	}
};

pub const handShake = struct { // MARK: handShake
	pub const id: u8 = 1;
	pub const asynchronous = false;

	fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		const newState = try reader.readEnum(Connection.HandShakeState);
		if(@intFromEnum(conn.handShakeState.load(.monotonic)) < @intFromEnum(newState)) {
			conn.handShakeState.store(newState, .monotonic);
			switch(newState) {
				.userData => return error.InvalidSide,
				.assets => {
					std.log.info("Received assets.", .{});
					main.files.cubyzDir().deleteTree("serverAssets") catch {}; // Delete old assets.
					var dir = try main.files.cubyzDir().openDir("serverAssets");
					defer dir.close();
					try utils.Compression.unpack(dir, reader.remaining);
				},
				.serverData => {
					const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
					defer zon.deinit(main.stackAllocator);
					try conn.manager.world.?.finishHandshake(zon);
					conn.handShakeState.store(.complete, .monotonic);
					conn.handShakeWaiting.broadcast(); // Notify the waiting client thread.
				},
				.start, .complete => {},
			}
		} else {
			// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
		}
	}

	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		const newState = try reader.readEnum(Connection.HandShakeState);
		if(@intFromEnum(conn.handShakeState.load(.monotonic)) < @intFromEnum(newState)) {
			conn.handShakeState.store(newState, .monotonic);
			switch(newState) {
				.userData => {
					const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
					defer zon.deinit(main.stackAllocator);
					const name = zon.get([]const u8, "name", "unnamed");
					if(!std.unicode.utf8ValidateSlice(name)) {
						std.log.err("Received player name with invalid UTF-8 characters.", .{});
						return error.Invalid;
					}
					if(name.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(name) > 50) {
						std.log.err("Player has too long name with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(name), name.len});
						return error.Invalid;
					}
					const version = zon.get([]const u8, "version", "unknown");
					std.log.info("User {s} joined using version {s}", .{name, version});

					if(!try settings.version.isCompatibleClientVersion(version)) {
						std.log.warn("Version incompatible with server version {s}", .{settings.version.version});
						return error.IncompatibleVersion;
					}

					{
						const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets/", .{main.server.world.?.path}) catch unreachable;
						defer main.stackAllocator.free(path);
						var dir = try main.files.cubyzDir().openIterableDir(path);
						defer dir.close();
						var writer = try std.Io.Writer.Allocating.initCapacity(main.stackAllocator.allocator, 16);
						defer writer.deinit();
						try writer.writer.writeByte(@intFromEnum(Connection.HandShakeState.assets));
						try utils.Compression.pack(dir, &writer.writer);
						conn.send(.fast, id, writer.written());
					}

					conn.user.?.initPlayer(name);
					const zonObject = ZonElement.initObject(main.stackAllocator);
					defer zonObject.deinit(main.stackAllocator);
					zonObject.put("player", conn.user.?.player.save(main.stackAllocator));
					zonObject.put("player_id", conn.user.?.id);
					zonObject.put("spawn", main.server.world.?.spawn);
					zonObject.put("blockPalette", main.server.world.?.blockPalette.storeToZon(main.stackAllocator));
					zonObject.put("itemPalette", main.server.world.?.itemPalette.storeToZon(main.stackAllocator));
					zonObject.put("toolPalette", main.server.world.?.toolPalette.storeToZon(main.stackAllocator));
					zonObject.put("biomePalette", main.server.world.?.biomePalette.storeToZon(main.stackAllocator));

					const outData = zonObject.toStringEfficient(main.stackAllocator, &[1]u8{@intFromEnum(Connection.HandShakeState.serverData)});
					defer main.stackAllocator.free(outData);
					conn.send(.fast, id, outData);
					conn.handShakeState.store(.serverData, .monotonic);
					main.server.connect(conn.user.?);
				},
				.assets, .serverData => return error.InvalidSide,
				.start, .complete => {},
			}
		} else {
			// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
		}
	}

	pub fn serverSide(conn: *Connection) void {
		conn.handShakeState.store(.start, .monotonic);
	}

	pub fn clientSide(conn: *Connection, name: []const u8) !void {
		const zonObject = ZonElement.initObject(main.stackAllocator);
		defer zonObject.deinit(main.stackAllocator);
		zonObject.putOwnedString("version", settings.version.version);
		zonObject.putOwnedString("name", name);
		const prefix = [1]u8{@intFromEnum(Connection.HandShakeState.userData)};
		const data = zonObject.toStringEfficient(main.stackAllocator, &prefix);
		defer main.stackAllocator.free(data);
		conn.send(.fast, id, data);

		conn.mutex.lock();
		while(true) {
			conn.handShakeWaiting.timedWait(&conn.mutex, 16_000_000) catch {
				main.heap.GarbageCollection.syncPoint();
				continue;
			};
			break;
		}
		if(conn.connectionState.load(.monotonic) == .disconnectDesired) return error.DisconnectedByServer;
		conn.mutex.unlock();
	}
};

pub const chunkRequest = struct { // MARK: chunkRequest
	pub const id: u8 = 2;
	pub const asynchronous = false;
	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		const basePosition = try reader.readVec(Vec3i);
		conn.user.?.clientUpdatePos = basePosition;
		conn.user.?.renderDistance = try reader.readInt(u16);
		while(reader.remaining.len >= 4) {
			const x: i32 = try reader.readInt(i8);
			const y: i32 = try reader.readInt(i8);
			const z: i32 = try reader.readInt(i8);
			const voxelSizeShift: u5 = try reader.readInt(u5);
			const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
			const request = chunk.ChunkPosition{
				.wx = (x << voxelSizeShift + chunk.chunkShift) +% (basePosition[0] & positionMask),
				.wy = (y << voxelSizeShift + chunk.chunkShift) +% (basePosition[1] & positionMask),
				.wz = (z << voxelSizeShift + chunk.chunkShift) +% (basePosition[2] & positionMask),
				.voxelSize = @as(u31, 1) << voxelSizeShift,
			};
			conn.user.?.increaseRefCount();
			main.server.world.?.queueChunkAndDecreaseRefCount(request, conn.user.?);
		}
	}
	pub fn sendRequest(conn: *Connection, requests: []chunk.ChunkPosition, basePosition: Vec3i, renderDistance: u16) void {
		if(requests.len == 0) return;
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 14 + 4*requests.len);
		defer writer.deinit();
		writer.writeVec(Vec3i, basePosition);
		writer.writeInt(u16, renderDistance);
		for(requests) |req| {
			const voxelSizeShift: u5 = std.math.log2_int(u31, req.voxelSize);
			const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
			writer.writeInt(i8, @intCast((req.wx -% (basePosition[0] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
			writer.writeInt(i8, @intCast((req.wy -% (basePosition[1] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
			writer.writeInt(i8, @intCast((req.wz -% (basePosition[2] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
			writer.writeInt(u5, voxelSizeShift);
		}
		conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
	}
};

pub const chunkTransmission = struct { // MARK: chunkTransmission
	pub const id: u8 = 3;
	pub const asynchronous = true;
	fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
		const pos = chunk.ChunkPosition{
			.wx = try reader.readInt(i32),
			.wy = try reader.readInt(i32),
			.wz = try reader.readInt(i32),
			.voxelSize = try reader.readInt(u31),
		};
		const ch = chunk.Chunk.init(pos);
		try main.server.storage.ChunkCompression.loadChunk(ch, .client, reader.remaining);
		renderer.mesh_storage.updateChunkMesh(ch);
	}
	fn sendChunkOverTheNetwork(conn: *Connection, ch: *chunk.ServerChunk) void {
		ch.mutex.lock();
		const chunkData = main.server.storage.ChunkCompression.storeChunk(main.stackAllocator, &ch.super, .toClient, ch.super.pos.voxelSize != 1);
		ch.mutex.unlock();
		defer main.stackAllocator.free(chunkData);
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, chunkData.len + 16);
		defer writer.deinit();
		writer.writeInt(i32, ch.super.pos.wx);
		writer.writeInt(i32, ch.super.pos.wy);
		writer.writeInt(i32, ch.super.pos.wz);
		writer.writeInt(u31, ch.super.pos.voxelSize);
		writer.writeSlice(chunkData);
		conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
	}
	pub fn sendChunk(conn: *Connection, ch: *chunk.ServerChunk) void {
		sendChunkOverTheNetwork(conn, ch);
	}
};

pub const playerPosition = struct { // MARK: playerPosition
	pub const id: u8 = 4;
	pub const asynchronous = false;
	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		try conn.user.?.receiveData(reader);
	}
	var lastPositionSent: u16 = 0;
	pub fn send(conn: *Connection, playerPos: Vec3d, playerVel: Vec3d, time: u16) void {
		if(time -% lastPositionSent < 50) {
			return; // Only send at most once every 50 ms.
		}
		lastPositionSent = time;
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 62);
		defer writer.deinit();
		writer.writeInt(u64, @bitCast(playerPos[0]));
		writer.writeInt(u64, @bitCast(playerPos[1]));
		writer.writeInt(u64, @bitCast(playerPos[2]));
		writer.writeInt(u64, @bitCast(playerVel[0]));
		writer.writeInt(u64, @bitCast(playerVel[1]));
		writer.writeInt(u64, @bitCast(playerVel[2]));
		writer.writeInt(u32, @bitCast(game.camera.rotation[0]));
		writer.writeInt(u32, @bitCast(game.camera.rotation[1]));
		writer.writeInt(u32, @bitCast(game.camera.rotation[2]));
		writer.writeInt(u16, time);
		conn.send(.lossy, id, writer.data.items);
	}
};

pub const entityPosition = struct { // MARK: entityPosition
	pub const id: u8 = 6;
	pub const asynchronous = false;
	const type_entity: u8 = 0;
	const type_item: u8 = 1;
	const Type = enum(u8) {
		noVelocityEntity = 0,
		f16VelocityEntity = 1,
		f32VelocityEntity = 2,
		noVelocityItem = 3,
		f16VelocityItem = 4,
		f32VelocityItem = 5,
	};
	fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		if(conn.manager.world) |world| {
			const time = try reader.readInt(i16);
			const playerPos = try reader.readVec(Vec3d);
			var entityData: main.List(main.entity.EntityNetworkData) = .init(main.stackAllocator);
			defer entityData.deinit();
			var itemData: main.List(main.itemdrop.ItemDropNetworkData) = .init(main.stackAllocator);
			defer itemData.deinit();
			while(reader.remaining.len != 0) {
				const typ = try reader.readEnum(Type);
				switch(typ) {
					.noVelocityEntity, .f16VelocityEntity, .f32VelocityEntity => {
						entityData.append(.{
							.vel = switch(typ) {
								.noVelocityEntity => @splat(0),
								.f16VelocityEntity => @floatCast(try reader.readVec(@Vector(3, f16))),
								.f32VelocityEntity => @floatCast(try reader.readVec(@Vector(3, f32))),
								else => unreachable,
							},
							.id = try reader.readInt(u32),
							.pos = playerPos + try reader.readVec(Vec3f),
							.rot = try reader.readVec(Vec3f),
						});
					},
					.noVelocityItem, .f16VelocityItem, .f32VelocityItem => {
						itemData.append(.{
							.vel = switch(typ) {
								.noVelocityItem => @splat(0),
								.f16VelocityItem => @floatCast(try reader.readVec(@Vector(3, f16))),
								.f32VelocityItem => @floatCast(try reader.readVec(Vec3f)),
								else => unreachable,
							},
							.index = try reader.readInt(u16),
							.pos = playerPos + try reader.readVec(Vec3f),
						});
					},
				}
			}
			main.entity.ClientEntityManager.serverUpdate(time, entityData.items);
			world.itemDrops.readPosition(time, itemData.items);
		}
	}
	pub fn send(conn: *Connection, playerPos: Vec3d, entityData: []main.entity.EntityNetworkData, itemData: []main.itemdrop.ItemDropNetworkData) void {
		var writer = utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();

		writer.writeInt(i16, @truncate(main.timestamp().toMilliseconds()));
		writer.writeVec(Vec3d, playerPos);
		for(entityData) |data| {
			const velocityMagnitudeSqr = vec.lengthSquare(data.vel);
			if(velocityMagnitudeSqr < 1e-6*1e-6) {
				writer.writeEnum(Type, .noVelocityEntity);
			} else if(velocityMagnitudeSqr > 1000*1000) {
				writer.writeEnum(Type, .f32VelocityEntity);
				writer.writeVec(Vec3f, @floatCast(data.vel));
			} else {
				writer.writeEnum(Type, .f16VelocityEntity);
				writer.writeVec(@Vector(3, f16), @floatCast(data.vel));
			}
			writer.writeInt(u32, data.id);
			writer.writeVec(Vec3f, @floatCast(data.pos - playerPos));
			writer.writeVec(Vec3f, data.rot);
		}
		for(itemData) |data| {
			const velocityMagnitudeSqr = vec.lengthSquare(data.vel);
			if(velocityMagnitudeSqr < 1e-6*1e-6) {
				writer.writeEnum(Type, .noVelocityItem);
			} else if(velocityMagnitudeSqr > 1000*1000) {
				writer.writeEnum(Type, .f32VelocityItem);
				writer.writeVec(Vec3f, @floatCast(data.vel));
			} else {
				writer.writeEnum(Type, .f16VelocityItem);
				writer.writeVec(@Vector(3, f16), @floatCast(data.vel));
			}
			writer.writeInt(u16, data.index);
			writer.writeVec(Vec3f, @floatCast(data.pos - playerPos));
		}
		conn.send(.lossy, id, writer.data.items);
	}
};

pub const blockUpdate = struct { // MARK: blockUpdate
	pub const id: u8 = 7;
	pub const asynchronous = false;
	fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
		while(reader.remaining.len != 0) {
			renderer.mesh_storage.updateBlock(.{
				.x = try reader.readInt(i32),
				.y = try reader.readInt(i32),
				.z = try reader.readInt(i32),
				.newBlock = Block.fromInt(try reader.readInt(u32)),
				.blockEntityData = try reader.readSlice(try reader.readInt(usize)),
			});
		}
	}
	pub fn send(conn: *Connection, updates: []const BlockUpdate) void {
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 16);
		defer writer.deinit();

		for(updates) |update| {
			writer.writeInt(i32, update.x);
			writer.writeInt(i32, update.y);
			writer.writeInt(i32, update.z);
			writer.writeInt(u32, update.newBlock.toInt());
			writer.writeInt(usize, update.blockEntityData.len);
			writer.writeSlice(update.blockEntityData);
		}
		conn.send(.fast, id, writer.data.items);
	}
};

pub const entity = struct { // MARK: entity
	pub const id: u8 = 8;
	pub const asynchronous = false;
	fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		const zonArray = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
		defer zonArray.deinit(main.stackAllocator);
		var i: u32 = 0;
		while(i < zonArray.array.items.len) : (i += 1) {
			const elem = zonArray.array.items[i];
			switch(elem) {
				.int => {
					main.entity.ClientEntityManager.removeEntity(elem.as(u32, 0));
				},
				.object => {
					main.entity.ClientEntityManager.addEntity(elem);
				},
				.null => {
					i += 1;
					break;
				},
				else => {
					std.log.err("Unrecognized zon parameters for protocol {}: {s}", .{id, reader.remaining});
				},
			}
		}
		while(i < zonArray.array.items.len) : (i += 1) {
			const elem: ZonElement = zonArray.array.items[i];
			if(elem == .int) {
				conn.manager.world.?.itemDrops.remove(elem.as(u16, 0));
			} else if(!elem.getChild("array").isNull()) {
				conn.manager.world.?.itemDrops.loadFrom(elem);
			} else {
				conn.manager.world.?.itemDrops.addFromZon(elem);
			}
		}
	}
	pub fn send(conn: *Connection, msg: []const u8) void {
		conn.send(.fast, id, msg);
	}
};

pub const genericUpdate = struct { // MARK: genericUpdate
	pub const id: u8 = 9;
	pub const asynchronous = false;

	const UpdateType = enum(u8) {
		gamemode = 0,
		teleport = 1,
		worldEditPos = 2,
		time = 3,
		biome = 4,
		particles = 5,
	};

	const WorldEditPosition = enum(u2) {
		selectedPos1 = 0,
		selectedPos2 = 1,
		clear = 2,
	};

	fn clientReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		switch(try reader.readEnum(UpdateType)) {
			.gamemode => {
				main.items.Inventory.Sync.setGamemode(null, try reader.readEnum(main.game.Gamemode));
			},
			.teleport => {
				game.Player.setPosBlocking(try reader.readVec(Vec3d));
			},
			.worldEditPos => {
				const typ = try reader.readEnum(WorldEditPosition);
				const pos: ?Vec3i = switch(typ) {
					.selectedPos1, .selectedPos2 => try reader.readVec(Vec3i),
					.clear => null,
				};
				switch(typ) {
					.selectedPos1 => game.Player.selectionPosition1 = pos,
					.selectedPos2 => game.Player.selectionPosition2 = pos,
					.clear => {
						game.Player.selectionPosition1 = null;
						game.Player.selectionPosition2 = null;
					},
				}
			},
			.time => {
				const world = conn.manager.world.?;
				const expectedTime = try reader.readInt(i64);

				var curTime = world.gameTime.load(.monotonic);
				if(@abs(curTime -% expectedTime) >= 10) {
					world.gameTime.store(expectedTime, .monotonic);
				} else if(curTime < expectedTime) { // world.gameTime++
					while(world.gameTime.cmpxchgWeak(curTime, curTime +% 1, .monotonic, .monotonic)) |actualTime| {
						curTime = actualTime;
					}
				} else { // world.gameTime--
					while(world.gameTime.cmpxchgWeak(curTime, curTime -% 1, .monotonic, .monotonic)) |actualTime| {
						curTime = actualTime;
					}
				}
			},
			.biome => {
				const world = conn.manager.world.?;
				const biomeId = try reader.readInt(u32);

				const newBiome = main.server.terrain.biomes.getByIndex(biomeId) orelse return error.MissingBiome;
				const oldBiome = world.playerBiome.swap(newBiome, .monotonic);
				if(oldBiome != newBiome) {
					main.audio.setMusic(newBiome.preferredMusic);
				}
			},
			.particles => {
				const sliceSize = try reader.readInt(u16);
				const particleId = try reader.readSlice(sliceSize);
				const pos = try reader.readVec(Vec3d);
				const collides = try reader.readBool();
				const count = try reader.readInt(u32);

				const emitter: particles.Emitter = .init(particleId, collides);
				particles.ParticleSystem.addParticlesFromNetwork(emitter, pos, count);
			},
		}
	}

	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		switch(try reader.readEnum(UpdateType)) {
			.gamemode, .teleport, .time, .biome, .particles => return error.InvalidSide,
			.worldEditPos => {
				const typ = try reader.readEnum(WorldEditPosition);
				const pos: ?Vec3i = switch(typ) {
					.selectedPos1, .selectedPos2 => try reader.readVec(Vec3i),
					.clear => null,
				};
				switch(typ) {
					.selectedPos1 => conn.user.?.worldEditData.selectionPosition1 = pos.?,
					.selectedPos2 => conn.user.?.worldEditData.selectionPosition2 = pos.?,
					.clear => {
						conn.user.?.worldEditData.selectionPosition1 = null;
						conn.user.?.worldEditData.selectionPosition2 = null;
					},
				}
			},
		}
	}

	pub fn sendGamemode(conn: *Connection, gamemode: main.game.Gamemode) void {
		conn.send(.fast, id, &.{@intFromEnum(UpdateType.gamemode), @intFromEnum(gamemode)});
	}

	pub fn sendTPCoordinates(conn: *Connection, pos: Vec3d) void {
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 25);
		defer writer.deinit();

		writer.writeEnum(UpdateType, .teleport);
		writer.writeVec(Vec3d, pos);

		conn.send(.fast, id, writer.data.items);
	}

	pub fn sendWorldEditPos(conn: *Connection, posType: WorldEditPosition, maybePos: ?Vec3i) void {
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 25);
		defer writer.deinit();

		writer.writeEnum(UpdateType, .worldEditPos);
		writer.writeEnum(WorldEditPosition, posType);
		if(maybePos) |pos| {
			writer.writeVec(Vec3i, pos);
		}

		conn.send(.fast, id, writer.data.items);
	}

	pub fn sendBiome(conn: *Connection, biomeIndex: u32) void {
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 13);
		defer writer.deinit();

		writer.writeEnum(UpdateType, .biome);
		writer.writeInt(u32, biomeIndex);

		conn.send(.fast, id, writer.data.items);
	}

	pub fn sendParticles(conn: *Connection, particleId: []const u8, pos: Vec3d, collides: bool, count: u32) void {
		const bufferSize = particleId.len*8 + 32;
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, bufferSize);
		defer writer.deinit();

		writer.writeEnum(UpdateType, .particles);
		writer.writeInt(u16, @intCast(particleId.len));
		writer.writeSlice(particleId);
		writer.writeVec(Vec3d, pos);
		writer.writeBool(collides);
		writer.writeInt(u32, count);

		conn.send(.fast, id, writer.data.items);
	}

	pub fn sendTime(conn: *Connection, world: *const main.server.ServerWorld) void {
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 13);
		defer writer.deinit();

		writer.writeEnum(UpdateType, .time);
		writer.writeInt(i64, world.gameTime);

		conn.send(.fast, id, writer.data.items);
	}
};

pub const chat = struct { // MARK: chat
	pub const id: u8 = 10;
	pub const asynchronous = false;
	fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
		const msg = reader.remaining;
		if(!std.unicode.utf8ValidateSlice(msg)) {
			std.log.err("Received chat message with invalid UTF-8 characters.", .{});
			return error.Invalid;
		}
		main.gui.windowlist.chat.addMessage(msg);
	}
	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		const msg = reader.remaining;
		if(!std.unicode.utf8ValidateSlice(msg)) {
			std.log.err("Received chat message with invalid UTF-8 characters.", .{});
			return error.Invalid;
		}
		const user = conn.user.?;
		if(msg.len > 10000 or main.graphics.TextBuffer.Parser.countVisibleCharacters(msg) > 1000) {
			std.log.err("Received too long chat message with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(msg), msg.len});
			return error.Invalid;
		}
		main.server.messageFrom(msg, user);
	}

	pub fn send(conn: *Connection, msg: []const u8) void {
		conn.send(.lossy, id, msg);
	}
};

pub const lightMapRequest = struct { // MARK: lightMapRequest
	pub const id: u8 = 11;
	pub const asynchronous = false;
	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		while(reader.remaining.len >= 9) {
			const wx = try reader.readInt(i32);
			const wy = try reader.readInt(i32);
			const voxelSizeShift = try reader.readInt(u5);
			const request = main.server.terrain.SurfaceMap.MapFragmentPosition{
				.wx = wx,
				.wy = wy,
				.voxelSize = @as(u31, 1) << voxelSizeShift,
				.voxelSizeShift = voxelSizeShift,
			};
			if(conn.user) |user| {
				user.increaseRefCount();
				main.server.world.?.queueLightMapAndDecreaseRefCount(request, user);
			}
		}
	}
	pub fn sendRequest(conn: *Connection, requests: []main.server.terrain.SurfaceMap.MapFragmentPosition) void {
		if(requests.len == 0) return;
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 9*requests.len);
		defer writer.deinit();
		for(requests) |req| {
			writer.writeInt(i32, req.wx);
			writer.writeInt(i32, req.wy);
			writer.writeInt(u8, req.voxelSizeShift);
		}
		conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
	}
};

pub const lightMapTransmission = struct { // MARK: lightMapTransmission
	pub const id: u8 = 12;
	pub const asynchronous = true;
	fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
		const wx = try reader.readInt(i32);
		const wy = try reader.readInt(i32);
		const voxelSizeShift = try reader.readInt(u5);
		const pos = main.server.terrain.SurfaceMap.MapFragmentPosition{
			.wx = wx,
			.wy = wy,
			.voxelSize = @as(u31, 1) << voxelSizeShift,
			.voxelSizeShift = voxelSizeShift,
		};
		const _inflatedData = main.stackAllocator.alloc(u8, main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2);
		defer main.stackAllocator.free(_inflatedData);
		const _inflatedLen = try utils.Compression.inflateTo(_inflatedData, reader.remaining);
		if(_inflatedLen != main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2) {
			std.log.err("Transmission of light map has invalid size: {}. Input data: {any}, After inflate: {any}", .{_inflatedLen, reader.remaining, _inflatedData[0.._inflatedLen]});
			return error.Invalid;
		}
		var ligthMapReader = utils.BinaryReader.init(_inflatedData);
		const map = main.globalAllocator.create(main.server.terrain.LightMap.LightMapFragment);
		map.init(pos.wx, pos.wy, pos.voxelSize);
		for(&map.startHeight) |*val| {
			val.* = try ligthMapReader.readInt(i16);
		}
		renderer.mesh_storage.updateLightMap(map);
	}
	pub fn sendLightMap(conn: *Connection, map: *main.server.terrain.LightMap.LightMapFragment) void {
		var ligthMapWriter = utils.BinaryWriter.initCapacity(main.stackAllocator, @sizeOf(@TypeOf(map.startHeight)));
		defer ligthMapWriter.deinit();
		for(&map.startHeight) |val| {
			ligthMapWriter.writeInt(i16, val);
		}
		const compressedData = utils.Compression.deflate(main.stackAllocator, ligthMapWriter.data.items, .default);
		defer main.stackAllocator.free(compressedData);
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 9 + compressedData.len);
		defer writer.deinit();
		writer.writeInt(i32, map.pos.wx);
		writer.writeInt(i32, map.pos.wy);
		writer.writeInt(u8, map.pos.voxelSizeShift);
		writer.writeSlice(compressedData);
		conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
	}
};

pub const inventory = struct { // MARK: inventory
	pub const id: u8 = 13;
	pub const asynchronous = false;
	fn clientReceive(_: *Connection, reader: *utils.BinaryReader) !void {
		const typ = try reader.readInt(u8);
		if(typ == 0xff) { // Confirmation
			try items.Inventory.Sync.ClientSide.receiveConfirmation(reader);
		} else if(typ == 0xfe) { // Failure
			items.Inventory.Sync.ClientSide.receiveFailure();
		} else {
			try items.Inventory.Sync.ClientSide.receiveSyncOperation(reader);
		}
	}
	fn serverReceive(conn: *Connection, reader: *utils.BinaryReader) !void {
		const user = conn.user.?;
		if(reader.remaining[0] == 0xff) return error.InvalidPacket;
		items.Inventory.Sync.ServerSide.receiveCommand(user, reader) catch |err| {
			if(err != error.InventoryNotFound) return err;
			sendFailure(conn);
		};
	}
	pub fn sendCommand(conn: *Connection, payloadType: items.Inventory.Command.PayloadType, _data: []const u8) void {
		std.debug.assert(conn.user == null);
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
		defer writer.deinit();
		writer.writeEnum(items.Inventory.Command.PayloadType, payloadType);
		std.debug.assert(writer.data.items[0] != 0xff);
		writer.writeSlice(_data);
		conn.send(.fast, id, writer.data.items);
	}
	pub fn sendConfirmation(conn: *Connection, _data: []const u8) void {
		std.debug.assert(conn.isServerSide());
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
		defer writer.deinit();
		writer.writeInt(u8, 0xff);
		writer.writeSlice(_data);
		conn.send(.fast, id, writer.data.items);
	}
	pub fn sendFailure(conn: *Connection) void {
		std.debug.assert(conn.isServerSide());
		conn.send(.fast, id, &.{0xfe});
	}
	pub fn sendSyncOperation(conn: *Connection, _data: []const u8) void {
		std.debug.assert(conn.isServerSide());
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
		defer writer.deinit();
		writer.writeInt(u8, 0);
		writer.writeSlice(_data);
		conn.send(.fast, id, writer.data.items);
	}
};

pub const blockEntityUpdate = struct { // MARK: blockEntityUpdate
	pub const id: u8 = 14;
	pub const asynchronous = false;
	fn serverReceive(_: *Connection, reader: *utils.BinaryReader) !void {
		const pos = try reader.readVec(Vec3i);
		const blockType = try reader.readInt(u16);
		const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
		defer simChunk.decreaseRefCount();
		const ch = simChunk.chunk.load(.unordered) orelse return;
		ch.mutex.lock();
		defer ch.mutex.unlock();
		const block = ch.getBlock(pos[0] - ch.super.pos.wx, pos[1] - ch.super.pos.wy, pos[2] - ch.super.pos.wz);
		if(block.typ != blockType) return;
		const blockEntity = block.blockEntity() orelse return;
		try blockEntity.updateServerData(pos, &ch.super, .{.update = reader});
		ch.setChanged();

		sendServerDataUpdateToClientsInternal(pos, &ch.super, block, blockEntity);
	}

	pub fn sendClientDataUpdateToServer(conn: *Connection, pos: Vec3i) void {
		const mesh = main.renderer.mesh_storage.getMesh(.initFromWorldPos(pos, 1)) orelse return;
		mesh.mutex.lock();
		defer mesh.mutex.unlock();
		const index = mesh.chunk.getLocalBlockIndex(pos);
		const block = mesh.chunk.data.getValue(index);
		const blockEntity = block.blockEntity() orelse return;

		var writer = utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();
		writer.writeVec(Vec3i, pos);
		writer.writeInt(u16, block.typ);
		blockEntity.getClientToServerData(pos, mesh.chunk, &writer);

		conn.send(.fast, id, writer.data.items);
	}

	fn sendServerDataUpdateToClientsInternal(pos: Vec3i, ch: *chunk.Chunk, block: Block, blockEntity: *main.block_entity.BlockEntityType) void {
		var writer = utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();
		blockEntity.getServerToClientData(pos, ch, &writer);

		const users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, users);

		for(users) |user| {
			blockUpdate.send(user.conn, &.{.{.x = pos[0], .y = pos[1], .z = pos[2], .newBlock = block, .blockEntityData = writer.data.items}});
		}
	}

	pub fn sendServerDataUpdateToClients(pos: Vec3i) void {
		const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
		defer simChunk.decreaseRefCount();
		const ch = simChunk.chunk.load(.unordered) orelse return;
		ch.mutex.lock();
		defer ch.mutex.unlock();
		const block = ch.getBlock(pos[0] - ch.super.pos.wx, pos[1] - ch.super.pos.wy, pos[2] - ch.super.pos.wz);
		const blockEntity = block.blockEntity() orelse return;

		sendServerDataUpdateToClientsInternal(pos, &ch.super, block, blockEntity);
	}
};
