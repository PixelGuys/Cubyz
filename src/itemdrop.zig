const std = @import("std");

const blocks = @import("blocks.zig");
const chunk_zig = @import("chunk.zig");
const ServerChunk = chunk_zig.ServerChunk;
const game = @import("game.zig");
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const graphics = @import("graphics.zig");
const c = graphics.c;
const items = @import("items.zig");
const ItemStack = items.ItemStack;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const random = @import("random.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const ItemDrop = struct { // MARK: ItemDrop
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
	itemStack: ItemStack,
	despawnTime: i32,
	pickupCooldown: i32,

	reverseIndex: u16,
};

pub const ItemDropNetworkData = struct {
	index: u16,
	pos: Vec3d,
	vel: Vec3d,
};

pub const ItemDropManager = struct { // MARK: ItemDropManager
	/// Half the side length of all item entities hitboxes as a cube.
	pub const radius: f64 = 0.1;
	/// Side length of all item entities hitboxes as a cube.
	pub const diameter: f64 = 2*radius;

	pub const pickupRange: f64 = 1.0;

	const terminalVelocity = 40.0;
	const gravity = 9.81;

	const maxCapacity = 65536;

	allocator: NeverFailingAllocator,

	list: std.MultiArrayList(ItemDrop),

	indices: [maxCapacity]u16 = undefined,

	emptyMutex: std.Thread.Mutex = .{},
	isEmpty: std.bit_set.ArrayBitSet(usize, maxCapacity),

	changeQueue: main.utils.ConcurrentQueue(union(enum) {add: struct {u16, ItemDrop}, remove: u16}),

	world: ?*ServerWorld,
	airDragFactor: f64,

	size: u32 = 0,

	pub fn init(self: *ItemDropManager, allocator: NeverFailingAllocator, world: ?*ServerWorld) void {
		self.* = ItemDropManager{
			.allocator = allocator,
			.list = std.MultiArrayList(ItemDrop){},
			.isEmpty = .initFull(),
			.changeQueue = .init(allocator, 16),
			.world = world,
			.airDragFactor = gravity/terminalVelocity,
		};
		self.list.resize(self.allocator.allocator, maxCapacity) catch unreachable;
	}

	pub fn deinit(self: *ItemDropManager) void {
		self.processChanges();
		self.changeQueue.deinit();
		for(self.indices[0..self.size]) |i| {
			if(self.list.items(.itemStack)[i].item) |item| {
				item.deinit();
			}
		}
		self.list.deinit(self.allocator.allocator);
	}

	pub fn loadFrom(self: *ItemDropManager, zon: ZonElement) void {
		const zonArray = zon.getChild("array");
		for(zonArray.toSlice()) |elem| {
			self.addFromZon(elem);
		}
	}

	pub fn loadFromBytes(self: *ItemDropManager, reader: *main.utils.BinaryReader) !void {
		const version = try reader.readInt(u8);
		if(version != 0) return error.UnsupportedVersion;
		var i: u16 = 0;
		while(reader.remaining.len != 0) : (i += 1) {
			try self.addFromBytes(reader, i);
		}
	}

	pub fn storeToBytes(self: *ItemDropManager, writer: *main.utils.BinaryWriter) void {
		const version = 0;
		writer.writeInt(u8, version);
		for(self.indices[0..self.size]) |i| {
			storeSingleToBytes(writer, self.list.get(i));
		}
	}

	fn addFromBytes(self: *ItemDropManager, reader: *main.utils.BinaryReader, i: u16) !void {
		const despawnTime = try reader.readInt(i32);
		const pos = try reader.readVec(Vec3d);
		const vel = try reader.readVec(Vec3d);
		const itemStack = try items.ItemStack.fromBytes(reader);
		self.addWithIndex(i, pos, vel, random.nextFloatVector(3, &main.seed)*@as(Vec3f, @splat(2*std.math.pi)), itemStack, despawnTime, 0);
	}

	fn storeSingleToBytes(writer: *main.utils.BinaryWriter, itemdrop: ItemDrop) void {
		writer.writeInt(i32, itemdrop.despawnTime);
		writer.writeVec(Vec3d, itemdrop.pos);
		writer.writeVec(Vec3d, itemdrop.vel);
		itemdrop.itemStack.toBytes(writer);
	}

	fn addFromZon(self: *ItemDropManager, zon: ZonElement) void {
		const item = items.Item.init(zon) catch |err| {
			const msg = zon.toStringEfficient(main.stackAllocator, "");
			defer main.stackAllocator.free(msg);
			std.log.err("Ignoring invalid item drop {s} which caused {s}", .{msg, @errorName(err)});
			return;
		};
		const properties = .{
			zon.get(Vec3d, "pos", .{0, 0, 0}),
			zon.get(Vec3d, "vel", .{0, 0, 0}),
			random.nextFloatVector(3, &main.seed)*@as(Vec3f, @splat(2*std.math.pi)),
			items.ItemStack{.item = item, .amount = zon.get(u16, "amount", 1)},
			zon.get(i32, "despawnTime", 60),
			0,
		};
		if(zon.get(?u16, "i", null)) |i| {
			@call(.auto, addWithIndex, .{self, i} ++ properties);
		} else {
			@call(.auto, add, .{self} ++ properties);
		}
	}

	pub fn getPositionAndVelocityData(self: *ItemDropManager, allocator: NeverFailingAllocator) []ItemDropNetworkData {
		const result = allocator.alloc(ItemDropNetworkData, self.size);
		for(self.indices[0..self.size], result) |i, *res| {
			res.* = .{
				.index = i,
				.pos = self.list.items(.pos)[i],
				.vel = self.list.items(.vel)[i],
			};
		}
		return result;
	}

	pub fn getInitialList(self: *ItemDropManager, allocator: NeverFailingAllocator) ZonElement {
		self.processChanges(); // Make sure all the items from the queue are included.
		var list = ZonElement.initArray(allocator);
		var ii: u32 = 0;
		while(ii < self.size) : (ii += 1) {
			const i = self.indices[ii];
			list.array.append(self.storeSingle(allocator, i));
		}
		return list;
	}

	fn storeDrop(allocator: NeverFailingAllocator, itemDrop: ItemDrop, i: u16) ZonElement {
		const obj = ZonElement.initObject(allocator);
		obj.put("i", i);
		obj.put("pos", itemDrop.pos);
		obj.put("vel", itemDrop.vel);
		itemDrop.itemStack.storeToZon(allocator, obj);
		obj.put("despawnTime", itemDrop.despawnTime);
		return obj;
	}

	fn storeSingle(self: *ItemDropManager, allocator: NeverFailingAllocator, i: u16) ZonElement {
		return storeDrop(allocator, self.list.get(i), i);
	}

	pub fn store(self: *ItemDropManager, allocator: NeverFailingAllocator) ZonElement {
		const zonArray = ZonElement.initArray(allocator);
		for(self.indices[0..self.size]) |i| {
			const item = self.storeSingle(allocator, i);
			zonArray.array.append(item);
		}
		const zon = ZonElement.initObject(allocator);
		zon.put("array", zonArray);
		return zon;
	}

	pub fn update(self: *ItemDropManager, deltaTime: f32) void {
		std.debug.assert(self.world != null);
		self.processChanges();
		const pos = self.list.items(.pos);
		const vel = self.list.items(.vel);
		const pickupCooldown = self.list.items(.pickupCooldown);
		const despawnTime = self.list.items(.despawnTime);
		var ii: u32 = 0;
		while(ii < self.size) {
			const i = self.indices[ii];
			if(self.world.?.getSimulationChunkAndIncreaseRefCount(@intFromFloat(pos[i][0]), @intFromFloat(pos[i][1]), @intFromFloat(pos[i][2]))) |simChunk| {
				defer simChunk.decreaseRefCount();
				if(simChunk.getChunk()) |chunk| {
					// Check collision with blocks:
					self.updateEnt(chunk, &pos[i], &vel[i], deltaTime);
				}
			}
			pickupCooldown[i] -= 1;
			despawnTime[i] -= 1;
			if(despawnTime[i] < 0) {
				self.directRemove(i);
			} else {
				ii += 1;
			}
		}
	}

	pub fn add(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		self.emptyMutex.lock();
		const i: u16 = @intCast(self.isEmpty.findFirstSet() orelse {
			self.emptyMutex.unlock();
			if(itemStack.item) |item| {
				std.log.err("Item drop capacitiy limit reached. Failed to add itemStack: {}×{s}", .{itemStack.amount, item.id()});
				item.deinit();
			}
			return;
		});
		self.isEmpty.unset(i);
		const drop = ItemDrop{
			.pos = pos,
			.vel = vel,
			.rot = rot,
			.itemStack = itemStack,
			.despawnTime = despawnTime,
			.pickupCooldown = pickupCooldown,
			.reverseIndex = undefined,
		};
		if(self.world != null) {
			const list = ZonElement.initArray(main.stackAllocator);
			defer list.deinit(main.stackAllocator);
			list.array.append(.null);
			list.array.append(storeDrop(main.stackAllocator, drop, i));
			const updateData = list.toStringEfficient(main.stackAllocator, &.{});
			defer main.stackAllocator.free(updateData);

			const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
			defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
			for(userList) |user| {
				main.network.Protocols.entity.send(user.conn, updateData);
			}
		}

		self.emptyMutex.unlock();
		self.changeQueue.pushBack(.{.add = .{i, drop}});
	}

	fn addWithIndex(self: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		self.emptyMutex.lock();
		std.debug.assert(self.isEmpty.isSet(i));
		self.isEmpty.unset(i);
		const drop = ItemDrop{
			.pos = pos,
			.vel = vel,
			.rot = rot,
			.itemStack = itemStack,
			.despawnTime = despawnTime,
			.pickupCooldown = pickupCooldown,
			.reverseIndex = undefined,
		};
		if(self.world != null) {
			const list = ZonElement.initArray(main.stackAllocator);
			defer list.deinit(main.stackAllocator);
			list.array.append(.null);
			list.array.append(storeDrop(main.stackAllocator, drop, i));
			const updateData = list.toStringEfficient(main.stackAllocator, &.{});
			defer main.stackAllocator.free(updateData);

			const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
			defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
			for(userList) |user| {
				main.network.Protocols.entity.send(user.conn, updateData);
			}
		}

		self.emptyMutex.unlock();
		self.changeQueue.pushBack(.{.add = .{i, drop}});
	}

	fn processChanges(self: *ItemDropManager) void {
		while(self.changeQueue.popFront()) |data| {
			switch(data) {
				.add => |addData| {
					self.internalAdd(addData[0], addData[1]);
				},
				.remove => |index| {
					self.internalRemove(index);
				},
			}
		}
	}

	fn internalAdd(self: *ItemDropManager, i: u16, drop_: ItemDrop) void {
		var drop = drop_;
		if(self.world == null) {
			ClientItemDropManager.clientSideInternalAdd(self, i, drop);
		}
		drop.reverseIndex = @intCast(self.size);
		self.list.set(i, drop);
		self.indices[self.size] = i;
		self.size += 1;
	}

	fn internalRemove(self: *ItemDropManager, i: u16) void {
		self.size -= 1;
		const ii = self.list.items(.reverseIndex)[i];
		self.list.items(.itemStack)[i].deinit();
		self.list.items(.itemStack)[i] = .{};
		self.indices[ii] = self.indices[self.size];
		self.list.items(.reverseIndex)[self.indices[self.size]] = ii;
	}

	fn directRemove(self: *ItemDropManager, i: u16) void {
		std.debug.assert(self.world != null);
		self.emptyMutex.lock();
		self.isEmpty.set(i);

		const list = ZonElement.initArray(main.stackAllocator);
		defer list.deinit(main.stackAllocator);
		list.array.append(.null);
		list.array.append(.{.int = i});
		const updateData = list.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(updateData);

		const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
		defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
		for(userList) |user| {
			main.network.Protocols.entity.send(user.conn, updateData);
		}

		self.emptyMutex.unlock();
		self.internalRemove(i);
	}

	fn updateEnt(self: *ItemDropManager, chunk: *ServerChunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		const hitBox = main.game.collision.Box{.min = @splat(-radius), .max = @splat(radius)};
		if(main.game.collision.collides(.server, .x, 0, pos.*, hitBox) != null) {
			self.fixStuckInBlock(chunk, pos, vel, deltaTime);
			return;
		}
		vel.* += Vec3d{0, 0, -gravity*deltaTime};
		inline for(0..3) |i| {
			const move = vel.*[i]*deltaTime; // + acceleration[i]*deltaTime;
			if(main.game.collision.collides(.server, @enumFromInt(i), move, pos.*, hitBox)) |box| {
				if(move < 0) {
					pos.*[i] = box.max[i] + radius;
				} else {
					pos.*[i] = box.max[i] - radius;
				}
				vel.*[i] = 0;
			} else {
				pos.*[i] += move;
			}
		}
		// Apply drag:
		vel.* *= @splat(@max(0, 1 - self.airDragFactor*deltaTime));
	}

	fn fixStuckInBlock(self: *ItemDropManager, chunk: *ServerChunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		const centeredPos = pos.* - @as(Vec3d, @splat(0.5));
		const pos0: Vec3i = @intFromFloat(@floor(centeredPos));

		var closestEmptyBlock: Vec3i = @splat(-1);
		var closestDist = std.math.floatMax(f64);
		var delta = Vec3i{0, 0, 0};
		while(delta[0] <= 1) : (delta[0] += 1) {
			delta[1] = 0;
			while(delta[1] <= 1) : (delta[1] += 1) {
				delta[2] = 0;
				while(delta[2] <= 1) : (delta[2] += 1) {
					const isSolid = self.checkBlock(chunk, pos, pos0 + delta);
					if(!isSolid) {
						const dist = vec.lengthSquare(@as(Vec3d, @floatFromInt(pos0 + delta)) - centeredPos);
						if(dist < closestDist) {
							closestDist = dist;
							closestEmptyBlock = delta;
						}
					}
				}
			}
		}

		vel.* = @splat(0);
		const unstuckVelocity: f64 = 1;
		if(closestDist == std.math.floatMax(f64)) {
			// Surrounded by solid blocks → move upwards
			vel.*[2] = unstuckVelocity;
			pos.*[2] += vel.*[2]*deltaTime;
		} else {
			vel.* = @as(Vec3d, @splat(unstuckVelocity))*(@as(Vec3d, @floatFromInt(pos0 + closestEmptyBlock)) - centeredPos);
			pos.* += (vel.*)*@as(Vec3d, @splat(deltaTime));
		}
	}

	fn checkBlock(self: *ItemDropManager, chunk: *ServerChunk, pos: *Vec3d, blockPos: Vec3i) bool {
		// Transform to chunk-relative coordinates:
		const chunkPos = blockPos & ~@as(Vec3i, @splat(main.chunk.chunkMask));
		var block: blocks.Block = undefined;
		if(chunk.super.pos.wx == chunkPos[0] and chunk.super.pos.wy == chunkPos[1] and chunk.super.pos.wz == chunkPos[2]) {
			chunk.mutex.lock();
			defer chunk.mutex.unlock();
			block = chunk.getBlock(blockPos[0] - chunk.super.pos.wx, blockPos[1] - chunk.super.pos.wy, blockPos[2] - chunk.super.pos.wz);
		} else {
			const otherChunk = self.world.?.getSimulationChunkAndIncreaseRefCount(chunkPos[0], chunkPos[1], chunkPos[2]) orelse return true;
			defer otherChunk.decreaseRefCount();
			const ch = otherChunk.getChunk() orelse return true;
			ch.mutex.lock();
			defer ch.mutex.unlock();
			block = ch.getBlock(blockPos[0] - ch.super.pos.wx, blockPos[1] - ch.super.pos.wy, blockPos[2] - ch.super.pos.wz);
		}
		return main.game.collision.collideWithBlock(block, blockPos[0], blockPos[1], blockPos[2], pos.*, @splat(radius), @splat(0)) != null;
	}

	pub fn checkEntity(self: *ItemDropManager, user: *main.server.User) void {
		var ii: u32 = 0;
		while(ii < self.size) {
			const i = self.indices[ii];
			if(self.list.items(.pickupCooldown)[i] > 0) {
				ii += 1;
				continue;
			}
			const hitbox = main.game.Player.outerBoundingBox;
			const min = user.player.pos + hitbox.min;
			const max = user.player.pos + hitbox.max;
			const itemPos = self.list.items(.pos)[i];
			const dist = @max(min - itemPos, itemPos - max);
			if(@reduce(.Max, dist) < radius + pickupRange) {
				const itemStack = &self.list.items(.itemStack)[i];
				main.items.Inventory.Sync.ServerSide.tryCollectingToPlayerInventory(user, itemStack);
				if(itemStack.amount == 0) {
					self.directRemove(i);
					continue;
				}
			}
			ii += 1;
		}
	}
};

pub const ClientItemDropManager = struct { // MARK: ClientItemDropManager
	const maxf64Capacity = ItemDropManager.maxCapacity*@sizeOf(Vec3d)/@sizeOf(f64);

	super: ItemDropManager,

	lastTime: i16,

	timeDifference: utils.TimeDifference = .{},

	interpolation: utils.GenericInterpolation(maxf64Capacity) align(64) = undefined,

	var instance: ?*ClientItemDropManager = null;

	var mutex: std.Thread.Mutex = .{};

	pub fn init(self: *ClientItemDropManager, allocator: NeverFailingAllocator) void {
		std.debug.assert(instance == null); // Only one instance allowed.
		instance = self;
		self.* = .{
			.super = undefined,
			.lastTime = @as(i16, @truncate(std.time.milliTimestamp())) -% settings.entityLookback,
		};
		self.super.init(allocator, null);
		self.interpolation.init(
			@ptrCast(self.super.list.items(.pos).ptr),
			@ptrCast(self.super.list.items(.vel).ptr),
		);
	}

	pub fn deinit(self: *ClientItemDropManager) void {
		std.debug.assert(instance != null); // Double deinit.
		self.super.deinit();
		instance = null;
	}

	pub fn readPosition(self: *ClientItemDropManager, time: i16, itemData: []ItemDropNetworkData) void {
		self.timeDifference.addDataPoint(time);
		var pos: [ItemDropManager.maxCapacity]Vec3d = undefined;
		var vel: [ItemDropManager.maxCapacity]Vec3d = undefined;
		for(itemData) |data| {
			pos[data.index] = data.pos;
			vel[data.index] = data.vel;
		}
		mutex.lock();
		defer mutex.unlock();
		self.interpolation.updatePosition(@ptrCast(&pos), @ptrCast(&vel), time); // TODO: Only update the ones we actually changed.
	}

	pub fn updateInterpolationData(self: *ClientItemDropManager) void {
		self.super.processChanges();
		var time = @as(i16, @truncate(std.time.milliTimestamp())) -% settings.entityLookback;
		time -%= self.timeDifference.difference.load(.monotonic);
		{
			mutex.lock();
			defer mutex.unlock();
			self.interpolation.updateIndexed(time, self.lastTime, self.super.indices[0..self.super.size], 4);
		}
		self.lastTime = time;
	}

	fn clientSideInternalAdd(_: *ItemDropManager, i: u16, drop: ItemDrop) void {
		mutex.lock();
		defer mutex.unlock();
		for(&instance.?.interpolation.lastVel) |*lastVel| {
			@as(*align(8) [ItemDropManager.maxCapacity]Vec3d, @ptrCast(lastVel))[i] = Vec3d{0, 0, 0};
		}
		for(&instance.?.interpolation.lastPos) |*lastPos| {
			@as(*align(8) [ItemDropManager.maxCapacity]Vec3d, @ptrCast(lastPos))[i] = drop.pos;
		}
	}

	pub fn remove(self: *ClientItemDropManager, i: u16) void {
		self.super.emptyMutex.lock();
		self.super.isEmpty.set(i);
		self.super.emptyMutex.unlock();
		self.super.changeQueue.pushBack(.{.remove = i});
	}

	pub fn loadFrom(self: *ClientItemDropManager, zon: ZonElement) void {
		self.super.loadFrom(zon);
	}

	pub fn addFromZon(self: *ClientItemDropManager, zon: ZonElement) void {
		self.super.addFromZon(zon);
	}
};

// Going to handle item animations and other things like - bobbing, interpolation, movement reactions
pub const ItemDisplayManager = struct { // MARK: ItemDisplayManager
	pub var showItem: bool = true;
	var cameraFollow: Vec3f = @splat(0);
	var cameraFollowVel: Vec3f = @splat(0);
	const damping: Vec3f = @splat(130);

	pub fn update(deltaTime: f64) void {
		if(deltaTime == 0) return;
		const dt: f32 = @floatCast(deltaTime);

		var playerVel: Vec3f = .{@floatCast((game.Player.super.vel[2]*0.009 + game.Player.eyeVel[2]*0.0075)), 0, 0};
		playerVel = vec.clampMag(playerVel, 0.32);

		// TODO: add *smooth* item sway
		const n1: Vec3f = cameraFollowVel - (cameraFollow - playerVel)*damping*damping*@as(Vec3f, @splat(dt));
		const n2: Vec3f = @as(Vec3f, @splat(1)) + damping*@as(Vec3f, @splat(dt));
		cameraFollowVel = n1/(n2*n2);

		cameraFollow += cameraFollowVel*@as(Vec3f, @splat(dt));
	}
};

pub const ItemDropRenderer = struct { // MARK: ItemDropRenderer
	var itemPipeline: graphics.Pipeline = undefined;
	var itemUniforms: struct {
		projectionMatrix: c_int,
		modelMatrix: c_int,
		viewMatrix: c_int,
		ambientLight: c_int,
		modelIndex: c_int,
		block: c_int,
		reflectionMapSize: c_int,
		contrast: c_int,
		glDepthRange: c_int,
	} = undefined;

	var itemModelSSBO: graphics.SSBO = undefined;
	var modelData: main.List(u32) = undefined;
	var freeSlots: main.List(*ItemVoxelModel) = undefined;

	const ItemVoxelModel = struct {
		index: u31 = undefined,
		len: u31 = undefined,
		item: items.Item,

		fn getSlot(len: u31) u31 {
			for(freeSlots.items, 0..) |potentialSlot, i| {
				if(len == potentialSlot.len) {
					_ = freeSlots.swapRemove(i);
					const result = potentialSlot.index;
					main.globalAllocator.destroy(potentialSlot);
					return result;
				}
			}
			const result: u31 = @intCast(modelData.items.len);
			modelData.resize(result + len);
			return result;
		}

		fn init(template: ItemVoxelModel) *ItemVoxelModel {
			const self = main.globalAllocator.create(ItemVoxelModel);
			self.* = ItemVoxelModel{
				.item = template.item,
			};
			if(self.item == .baseItem and self.item.baseItem.block() != null and self.item.baseItem.image().imageData.ptr == graphics.Image.defaultImage.imageData.ptr) {
				// Find sizes and free index:
				var block = blocks.Block{.typ = self.item.baseItem.block().?, .data = 0};
				block.data = block.mode().naturalStandard;
				const model = blocks.meshes.model(block).model();
				var data = main.List(u32).init(main.stackAllocator);
				defer data.deinit();
				for(model.internalQuads) |quad| {
					const textureIndex = blocks.meshes.textureIndex(block, quad.quadInfo().textureSlot);
					data.append(@as(u32, @intFromEnum(quad)) << 16 | textureIndex); // modelAndTexture
					data.append(0); // offsetByNormal
				}
				for(model.neighborFacingQuads) |list| {
					for(list) |quad| {
						const textureIndex = blocks.meshes.textureIndex(block, quad.quadInfo().textureSlot);
						data.append(@as(u32, @intFromEnum(quad)) << 16 | textureIndex); // modelAndTexture
						data.append(1); // offsetByNormal
					}
				}
				self.len = @intCast(data.items.len);
				self.index = getSlot(self.len);
				@memcpy(modelData.items[self.index..][0..self.len], data.items);
			} else {
				// Find sizes and free index:
				const img = self.item.getImage();
				const size = Vec3i{img.width, 1, img.height};
				self.len = @intCast(3 + @reduce(.Mul, size));
				self.index = getSlot(self.len);
				var dataSection: []u32 = undefined;
				dataSection = modelData.items[self.index..][0..self.len];
				dataSection[0] = @intCast(size[0]);
				dataSection[1] = @intCast(size[1]);
				dataSection[2] = @intCast(size[2]);
				var i: u32 = 3;
				var z: u32 = 0;
				while(z < 1) : (z += 1) {
					var x: u32 = 0;
					while(x < img.width) : (x += 1) {
						var y: u32 = 0;
						while(y < img.height) : (y += 1) {
							dataSection[i] = img.getRGB(x, y).toARBG();
							i += 1;
						}
					}
				}
			}
			itemModelSSBO.bufferData(u32, modelData.items);
			return self;
		}

		fn deinit(self: *ItemVoxelModel) void {
			freeSlots.append(self);
		}

		pub fn equals(self: ItemVoxelModel, other: ?*ItemVoxelModel) bool {
			if(other == null) return false;
			return std.meta.eql(self.item, other.?.item);
		}

		pub fn hashCode(self: ItemVoxelModel) u32 {
			return self.item.hashCode();
		}
	};

	pub fn init() void {
		itemPipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/item_drop.vert",
			"assets/cubyz/shaders/item_drop.frag",
			"",
			&itemUniforms,
			.{},
			.{.depthTest = true},
			.{.attachments = &.{.alphaBlending}},
		);
		itemModelSSBO = .init();
		itemModelSSBO.bufferData(i32, &[3]i32{1, 1, 1});
		itemModelSSBO.bind(2);

		modelData = .init(main.globalAllocator);
		freeSlots = .init(main.globalAllocator);
	}

	pub fn deinit() void {
		itemPipeline.deinit();
		itemModelSSBO.deinit();
		modelData.deinit();
		voxelModels.clear();
		for(freeSlots.items) |freeSlot| {
			main.globalAllocator.destroy(freeSlot);
		}
		freeSlots.deinit();
	}

	var voxelModels: utils.Cache(ItemVoxelModel, 32, 32, ItemVoxelModel.deinit) = .{};

	fn getModel(item: items.Item) *ItemVoxelModel {
		const compareObject = ItemVoxelModel{.item = item};
		return voxelModels.findOrCreate(compareObject, ItemVoxelModel.init, null);
	}

	fn bindCommonUniforms(projMatrix: Mat4f, viewMatrix: Mat4f, ambientLight: Vec3f) void {
		itemPipeline.bind(null);
		c.glUniform1f(itemUniforms.reflectionMapSize, main.renderer.reflectionCubeMapSize);
		c.glUniformMatrix4fv(itemUniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniformMatrix4fv(itemUniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&viewMatrix));
		c.glUniform1f(itemUniforms.contrast, 0.12);
		var depthRange: [2]f32 = undefined;
		c.glGetFloatv(c.GL_DEPTH_RANGE, &depthRange);
		c.glUniform2fv(itemUniforms.glDepthRange, 1, &depthRange);
	}

	fn bindLightUniform(light: [6]u8, ambientLight: Vec3f) void {
		c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&@max(
			ambientLight*@as(Vec3f, @as(Vec3f, @floatFromInt(Vec3i{light[0], light[1], light[2]}))/@as(Vec3f, @splat(255))),
			@as(Vec3f, @floatFromInt(Vec3i{light[3], light[4], light[5]}))/@as(Vec3f, @splat(255)),
		)));
	}

	fn bindModelUniforms(modelIndex: u31, blockType: u16) void {
		c.glUniform1i(itemUniforms.modelIndex, modelIndex);
		c.glUniform1i(itemUniforms.block, blockType);
	}

	fn drawItem(vertices: u31, modelMatrix: Mat4f) void {
		c.glUniformMatrix4fv(itemUniforms.modelMatrix, 1, c.GL_TRUE, @ptrCast(&modelMatrix));
		c.glBindVertexArray(main.renderer.chunk_meshing.vao);
		c.glDrawElements(c.GL_TRIANGLES, vertices, c.GL_UNSIGNED_INT, null);
	}

	pub fn renderItemDrops(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
		game.world.?.itemDrops.updateInterpolationData();

		bindCommonUniforms(projMatrix, game.camera.viewMatrix, ambientLight);
		const itemDrops = &game.world.?.itemDrops.super;
		for(itemDrops.indices[0..itemDrops.size]) |i| {
			if(itemDrops.list.items(.itemStack)[i].item) |item| {
				var pos = itemDrops.list.items(.pos)[i];
				const rot = itemDrops.list.items(.rot)[i];
				const blockPos: Vec3i = @intFromFloat(@floor(pos));
				const light: [6]u8 = main.renderer.mesh_storage.getLight(blockPos[0], blockPos[1], blockPos[2]) orelse @splat(0);
				bindLightUniform(light, ambientLight);
				pos -= playerPos;

				const model = getModel(item);
				var vertices: u31 = 36;

				var scale: f32 = 0.3;
				var blockType: u16 = 0;
				if(item == .baseItem and item.baseItem.block() != null and item.baseItem.image().imageData.ptr == graphics.Image.defaultImage.imageData.ptr) {
					blockType = item.baseItem.block().?;
					vertices = model.len/2*6;
				} else {
					scale = 0.5;
				}
				bindModelUniforms(model.index, blockType);

				var modelMatrix = Mat4f.translation(@floatCast(pos));
				modelMatrix = modelMatrix.mul(Mat4f.rotationX(-rot[0]));
				modelMatrix = modelMatrix.mul(Mat4f.rotationY(-rot[1]));
				modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-rot[2]));
				modelMatrix = modelMatrix.mul(Mat4f.scale(@splat(scale)));
				modelMatrix = modelMatrix.mul(Mat4f.translation(@splat(-0.5)));
				drawItem(vertices, modelMatrix);
			}
		}
	}

	inline fn getIndex(x: u8, y: u8, z: u8) u32 {
		return (z*4) + (y*2) + (x);
	}

	inline fn blendColors(a: [6]f32, b: [6]f32, t: f32) [6]f32 {
		var result: [6]f32 = .{0, 0, 0, 0, 0, 0};
		inline for(0..6) |i| {
			result[i] = std.math.lerp(a[i], b[i], t);
		}
		return result;
	}

	pub fn renderDisplayItems(ambientLight: Vec3f, playerPos: Vec3d) void {
		if(!ItemDisplayManager.showItem) return;

		const projMatrix: Mat4f = Mat4f.perspective(std.math.degreesToRadians(65), @as(f32, @floatFromInt(main.renderer.lastWidth))/@as(f32, @floatFromInt(main.renderer.lastHeight)), 0.01, 3);
		const viewMatrix = Mat4f.identity();
		bindCommonUniforms(projMatrix, viewMatrix, ambientLight);

		const selectedItem = game.Player.inventory.getItem(game.Player.selectedSlot);
		if(selectedItem) |item| {
			var pos: Vec3d = Vec3d{0, 0, 0};
			const rot: Vec3f = ItemDisplayManager.cameraFollow;

			const lightPos = @as(Vec3d, @floatCast(playerPos)) - @as(Vec3f, @splat(0.5));
			const blockPos: Vec3i = @intFromFloat(@floor(lightPos));
			const localBlockPos: Vec3f = @floatCast(lightPos - @as(Vec3d, @floatFromInt(blockPos)));

			var samples: [8][6]f32 = @splat(@splat(0));
			inline for(0..2) |z| {
				inline for(0..2) |y| {
					inline for(0..2) |x| {
						const light: [6]u8 = main.renderer.mesh_storage.getLight(
							blockPos[0] +% @as(i32, @intCast(x)),
							blockPos[1] +% @as(i32, @intCast(y)),
							blockPos[2] +% @as(i32, @intCast(z)),
						) orelse @splat(0);

						inline for(0..6) |i| {
							samples[getIndex(x, y, z)][i] = @as(f32, @floatFromInt(light[i]));
						}
					}
				}
			}

			inline for(0..2) |y| {
				inline for(0..2) |x| {
					samples[getIndex(x, y, 0)] = blendColors(samples[getIndex(x, y, 0)], samples[getIndex(x, y, 1)], localBlockPos[2]);
				}
			}

			inline for(0..2) |x| {
				samples[getIndex(x, 0, 0)] = blendColors(samples[getIndex(x, 0, 0)], samples[getIndex(x, 1, 0)], localBlockPos[1]);
			}

			var result: [6]u8 = .{0, 0, 0, 0, 0, 0};
			inline for(0..6) |i| {
				const val = std.math.lerp(samples[getIndex(0, 0, 0)][i], samples[getIndex(1, 0, 0)][i], localBlockPos[0]);
				result[i] = @as(u8, @intFromFloat(@floor(val)));
			}

			bindLightUniform(result, ambientLight);

			const model = getModel(item);
			var vertices: u31 = 36;

			const isBlock: bool = item == .baseItem and item.baseItem.block() != null and item.baseItem.image().imageData.ptr == graphics.Image.defaultImage.imageData.ptr;
			var scale: f32 = 0;
			var blockType: u16 = 0;
			if(isBlock) {
				blockType = item.baseItem.block().?;
				vertices = model.len/2*6;
				scale = 0.3;
				pos = Vec3d{0.4, 0.55, -0.32};
			} else {
				scale = 0.57;
				pos = Vec3d{0.4, 0.65, -0.3};
			}
			bindModelUniforms(model.index, blockType);

			var modelMatrix = Mat4f.rotationZ(-rot[2]);
			modelMatrix = modelMatrix.mul(Mat4f.rotationY(-rot[1]));
			modelMatrix = modelMatrix.mul(Mat4f.rotationX(-rot[0]));
			modelMatrix = modelMatrix.mul(Mat4f.translation(@floatCast(pos)));
			if(!isBlock) {
				if(item == .tool) {
					modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-std.math.pi*0.47));
					modelMatrix = modelMatrix.mul(Mat4f.rotationY(std.math.pi*0.25));
				} else {
					modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-std.math.pi*0.45));
				}
			} else {
				modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-std.math.pi*0.2));
			}
			modelMatrix = modelMatrix.mul(Mat4f.scale(@splat(scale)));
			modelMatrix = modelMatrix.mul(Mat4f.translation(@splat(-0.5)));
			drawItem(vertices, modelMatrix);
		}
	}
};
