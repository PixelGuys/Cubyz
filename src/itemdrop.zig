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
const main = @import("main.zig");
const random = @import("random.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

const ItemDrop = struct { // MARK: ItemDrop
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
	itemStack: ItemStack,
	despawnTime: i32,
	pickupCooldown: i32,

	reverseIndex: u16,
};

pub const ItemDropManager = struct { // MARK: ItemDropManager
	/// Half the side length of all item entities hitboxes as a cube.
	const radius: f64 = 0.1;
	/// Side length of all item entities hitboxes as a cube.
	const diameter: f64 = 2*radius;

	const pickupRange: f64 = 1.0;

	const maxSpeed = 10;

	const maxCapacity = 65536;

	allocator: NeverFailingAllocator,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},

	list: std.MultiArrayList(ItemDrop),

	indices: [maxCapacity]u16 = undefined,

	isEmpty: std.bit_set.ArrayBitSet(usize, maxCapacity),

	world: ?*ServerWorld,
	gravity: f64,
	airDragFactor: f64,

	size: u32 = 0,

	lastUpdates: ZonElement,

	// TODO: Get rid of this inheritance pattern.
	addWithIndexAndRotation: *const fn(*ItemDropManager, u16, Vec3d, Vec3d, Vec3f, ItemStack, i32, i32) void,

	pub fn init(self: *ItemDropManager, allocator: NeverFailingAllocator, world: ?*ServerWorld, gravity: f64) void {
		self.* = ItemDropManager {
			.allocator = allocator,
			.list = std.MultiArrayList(ItemDrop){},
			.lastUpdates = ZonElement.initArray(allocator),
			.isEmpty = .initFull(),
			.world = world,
			.gravity = gravity,
			.airDragFactor = gravity/maxSpeed,
			.addWithIndexAndRotation = &defaultAddWithIndexAndRotation,
		};
		self.list.resize(self.allocator.allocator, maxCapacity) catch unreachable;
	}

	pub fn deinit(self: *ItemDropManager) void {
		for(self.indices[0..self.size]) |i| {
			if(self.list.items(.itemStack)[i].item) |item| {
				item.deinit();
			}
		}
		self.list.deinit(self.allocator.allocator);
		self.lastUpdates.free(self.allocator);
	}

	pub fn loadFrom(self: *ItemDropManager, zon: ZonElement) void {
		const zonArray = zon.getChild("array");
		for(zonArray.toSlice()) |elem| {
			self.addFromZon(elem);
		}
	}

	pub fn addFromZon(self: *ItemDropManager, zon: ZonElement) void {
		const item = items.Item.init(zon) catch |err| {
			const msg = zon.toStringEfficient(main.stackAllocator, "");
			defer main.stackAllocator.free(msg);
			std.log.err("Ignoring invalid item drop {s} which caused {s}", .{msg, @errorName(err)});
			return;
		};
		const properties = .{
			zon.get(Vec3d, "pos", .{0, 0, 0}),
			zon.get(Vec3d, "vel", .{0, 0, 0}),
			items.ItemStack{.item = item, .amount = zon.get(u16, "amount", 1)},
			zon.get(i32, "despawnTime", 60),
			0
		};
		if(zon.get(?u16, "i", null)) |i| {
			@call(.auto, addWithIndex, .{self, i} ++ properties);
		} else {
			@call(.auto, add, .{self} ++ properties);
		}
	}

	pub fn getPositionAndVelocityData(self: *ItemDropManager, allocator: NeverFailingAllocator) []u8 {
		const _data = allocator.alloc(u8, self.size*50);
		var data = _data;
		for(self.indices[0..self.size]) |i| {
			std.mem.writeInt(u16, data[0..2], i, .big);
			std.mem.writeInt(u64, data[2..10], @bitCast(self.list.items(.pos)[i][0]), .big);
			std.mem.writeInt(u64, data[10..18], @bitCast(self.list.items(.pos)[i][1]), .big);
			std.mem.writeInt(u64, data[18..26], @bitCast(self.list.items(.pos)[i][2]), .big);
			std.mem.writeInt(u64, data[26..34], @bitCast(self.list.items(.vel)[i][0]), .big);
			std.mem.writeInt(u64, data[34..42], @bitCast(self.list.items(.vel)[i][1]), .big);
			std.mem.writeInt(u64, data[42..50], @bitCast(self.list.items(.vel)[i][2]), .big);
			data = data[50..];
		}
		return _data;
	}

	pub fn getInitialList(self: *ItemDropManager, allocator: NeverFailingAllocator) ZonElement {
		var list = ZonElement.initArray(allocator);
		var ii: u32 = 0;
		while(ii < self.size) : (ii += 1) {
			const i = self.indices[ii];
			list.array.append(self.storeSingle(self.lastUpdates.array.allocator, i));
		}
		return list;
	}

	fn storeSingle(self: *ItemDropManager, allocator: NeverFailingAllocator, i: u16) ZonElement {
		main.utils.assertLocked(&self.mutex);
		const obj = ZonElement.initObject(allocator);
		const itemDrop = self.list.get(i);
		obj.put("i", i);
		obj.put("pos", itemDrop.pos);
		obj.put("vel", itemDrop.vel);
		itemDrop.itemStack.storeToZon(allocator, obj);
		obj.put("despawnTime", itemDrop.despawnTime);
		return obj;
	}

	pub fn store(self: *ItemDropManager, allocator: NeverFailingAllocator) ZonElement {
		const zonArray = ZonElement.initArray(allocator);
		{
			self.mutex.lock();
			defer self.mutex.unlock();
			for(self.indices[0..self.size]) |i| {
				const item = self.storeSingle(allocator, i);
				zonArray.array.append(item);
			}
		}
		const zon = ZonElement.initObject(allocator);
		zon.put("array", zonArray);
		return zon;
	}

	pub fn update(self: *ItemDropManager, deltaTime: f32) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		std.debug.assert(self.world != null);
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
				self.removeLocked(i);
			} else {
				ii += 1;
			}
		}
	}

	pub fn addFromBlockPosition(self: *ItemDropManager, blockPos: Vec3i, vel: Vec3d, itemStack: ItemStack, despawnTime: i32) void {
		self.add(
			vec.floatFromInt(f64, blockPos) + Vec3d { // TODO: Consider block bounding boxes.
				random.nextDouble(&main.seed),
				random.nextDouble(&main.seed),
				random.nextDouble(&main.seed),
			} + @as(Vec3d, @splat(radius)),
			vel,
			Vec3f {
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
			},
			itemStack, despawnTime, 0
		);
	}

	pub fn add(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		self.addWithRotation(
			pos, vel,
			Vec3f {
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
			},
			itemStack, despawnTime, pickupCooldown
		);
	}
	
	pub fn addWithIndex(self: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		self.addWithIndexAndRotation(
			self, i, pos, vel,
			Vec3f {
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
			},
			itemStack, despawnTime, pickupCooldown
		);
	}

	pub fn addWithRotation(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		var i: u16 = undefined;
		{
			self.mutex.lock();
			defer self.mutex.unlock();
			if(self.size == maxCapacity) {
				const zon = itemStack.store(main.stackAllocator);
				defer zon.free(main.stackAllocator);
				const string = zon.toString(main.stackAllocator);
				defer main.stackAllocator.free(string);
				std.log.err("Item drop capacitiy limit reached. Failed to add itemStack: {s}", .{string});
				if(itemStack.item) |item| {
					item.deinit();
				}
				return;
			}
			i = @intCast(self.isEmpty.findFirstSet().?);
		}
		self.addWithIndexAndRotation(self, i, pos, vel, rot, itemStack, despawnTime, pickupCooldown);
	}

	fn defaultAddWithIndexAndRotation(self: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		std.debug.assert(self.isEmpty.isSet(i));
		self.isEmpty.unset(i);
		self.list.set(i, ItemDrop {
			.pos = pos,
			.vel = vel,
			.rot = rot,
			.itemStack = itemStack,
			.despawnTime = despawnTime,
			.pickupCooldown = pickupCooldown,
			.reverseIndex = @intCast(self.size),
		});
		if(self.world != null) {
			self.lastUpdates.array.append(self.storeSingle(self.lastUpdates.array.allocator, i));
		}
		self.indices[self.size] = i;
		self.size += 1;
	}

	fn removeLocked(self: *ItemDropManager, i: u16) void {
		main.utils.assertLocked(&self.mutex);
		self.size -= 1;
		const ii = self.list.items(.reverseIndex)[i];
		self.indices[ii] = self.indices[self.size];
		self.list.items(.itemStack)[i].clear();
		self.isEmpty.set(i);
		if(self.world != null) {
			self.lastUpdates.array.append(.{.int = i});
		}
	}

	pub fn remove(self: *ItemDropManager, i: u16) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.removeLocked(i);
	}

	fn updateEnt(self: *ItemDropManager, chunk: *ServerChunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		main.utils.assertLocked(&self.mutex);
		const hitBox = main.game.collision.Box{.min = @splat(-radius), .max = @splat(radius)};
		if(main.game.collision.collides(.server, .x, 0, pos.*, hitBox) != null) {
			self.fixStuckInBlock(chunk, pos, vel, deltaTime);
			return;
		}
		var drag: f64 = self.airDragFactor;
		vel.* += Vec3d{0, 0, -self.gravity*deltaTime};
		inline for(0..3) |i| {
			const move = vel.*[i]*deltaTime;// + acceleration[i]*deltaTime;
			if(main.game.collision.collides(.server, @enumFromInt(i), move, pos.*, hitBox)) |box| {
				if (move < 0) {
					pos.*[i] = box.max[i] + radius;
				} else {
					pos.*[i] = box.max[i] - radius;
				}
				vel.*[i] = 0;
			} else {
				pos.*[i] += move;
			}
			drag += 0.5; // TODO: Calculate drag from block properties and add buoyancy.
		}
		// Apply drag:
		vel.* *= @splat(@max(0, 1 - drag*deltaTime));
	}

	fn fixStuckInBlock(self: *ItemDropManager, chunk: *ServerChunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		main.utils.assertLocked(&self.mutex);
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
};

pub const ClientItemDropManager = struct { // MARK: ClientItemDropManager
	const maxf64Capacity = ItemDropManager.maxCapacity*@sizeOf(Vec3d)/@sizeOf(f64);

	super: ItemDropManager,

	lastTime: i16,

	timeDifference: utils.TimeDifference = .{},

	interpolation: utils.GenericInterpolation(maxf64Capacity)align(64) = undefined,

	var instance: ?*ClientItemDropManager = null;

	pub fn init(self: *ClientItemDropManager, allocator: NeverFailingAllocator, world: *World) void {
		std.debug.assert(instance == null); // Only one instance allowed.
		instance = self;
		self.* = .{
			.super = undefined,
			.lastTime = @as(i16, @truncate(std.time.milliTimestamp())) -% settings.entityLookback,
		};
		self.super.init(allocator, null, world.gravity);
		self.super.addWithIndexAndRotation = &overrideAddWithIndexAndRotation;
		self.interpolation.init(
			@ptrCast(self.super.list.items(.pos).ptr),
			@ptrCast(self.super.list.items(.vel).ptr)
		);
	}

	pub fn deinit(self: *ClientItemDropManager) void {
		std.debug.assert(instance != null); // Double deinit.
		instance = null;
		self.super.deinit();
	}

	pub fn readPosition(self: *ClientItemDropManager, _data: []const u8, time: i16) void {
		var data = _data;
		self.timeDifference.addDataPoint(time);
		var pos: [ItemDropManager.maxCapacity]Vec3d = undefined;
		var vel: [ItemDropManager.maxCapacity]Vec3d = undefined;
		while(data.len != 0) {
			const i = std.mem.readInt(u16, data[0..2], .big);
			pos[i][0] = @bitCast(std.mem.readInt(u64, data[2..10], .big));
			pos[i][1] = @bitCast(std.mem.readInt(u64, data[10..18], .big));
			pos[i][2] = @bitCast(std.mem.readInt(u64, data[18..26], .big));
			vel[i][0] = @bitCast(std.mem.readInt(u64, data[26..34], .big));
			vel[i][1] = @bitCast(std.mem.readInt(u64, data[34..42], .big));
			vel[i][2] = @bitCast(std.mem.readInt(u64, data[42..50], .big));
			data = data[50..];
		}
		self.super.mutex.lock();
		defer self.super.mutex.unlock();
		self.interpolation.updatePosition(@ptrCast(&pos), @ptrCast(&vel), time); // TODO: Only update the ones we actually changed.
	}

	pub fn updateInterpolationData(self: *ClientItemDropManager) void {
		var time = @as(i16, @truncate(std.time.milliTimestamp())) -% settings.entityLookback;
		time -%= self.timeDifference.difference.load(.monotonic);
		{
			self.super.mutex.lock();
			defer self.super.mutex.unlock();
			self.interpolation.updateIndexed(time, self.lastTime, self.super.indices[0..self.super.size], 4);
		}
		self.lastTime = time;
	}

	fn overrideAddWithIndexAndRotation(super: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) void {
		{
			super.mutex.lock();
			defer super.mutex.unlock();
			for(&instance.?.interpolation.lastVel) |*lastVel| {
				@as(*align(8)[ItemDropManager.maxCapacity]Vec3d, @ptrCast(lastVel))[i] = Vec3d{0, 0, 0};
			}
			for(&instance.?.interpolation.lastPos) |*lastPos| {
				@as(*align(8)[ItemDropManager.maxCapacity]Vec3d, @ptrCast(lastPos))[i] = pos;
			}
		}
		super.defaultAddWithIndexAndRotation(i, pos, vel, rot, itemStack, despawnTime, pickupCooldown);
	}

	pub fn remove(self: *ClientItemDropManager, i: u16) void {
		self.super.remove(i);
	}

	pub fn loadFrom(self: *ClientItemDropManager, zon: ZonElement) void {
		self.super.loadFrom(zon);
	}

	pub fn addFromZon(self: *ClientItemDropManager, zon: ZonElement) void {
		self.super.addFromZon(zon);
	}
};

pub const ItemDropRenderer = struct { // MARK: ItemDropRenderer
	var itemShader: graphics.Shader = undefined;
	var itemUniforms: struct {
		projectionMatrix: c_int,
		modelMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		ambientLight: c_int,
		modelIndex: c_int,
		block: c_int,
		time: c_int,
		texture_sampler: c_int,
		emissionSampler: c_int,
		reflectivityAndAbsorptionSampler: c_int,
		reflectionMap: c_int,
		reflectionMapSize: c_int,
		contrast: c_int,
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
				if(std.meta.eql(len, potentialSlot.len)) {
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
			if(self.item == .baseItem and self.item.baseItem.block != null and self.item.baseItem.image.imageData.ptr == graphics.Image.defaultImage.imageData.ptr) {
				// Find sizes and free index:
				const block = blocks.Block{.typ = self.item.baseItem.block.?, .data = 0}; // TODO: Natural standard
				const modelIndex = blocks.meshes.model(block);
				const model = &main.models.models.items[modelIndex];
				var data = main.List(u32).init(main.stackAllocator);
				defer data.deinit();
				for(model.internalQuads) |quad| {
					const textureIndex = blocks.meshes.textureIndex(block, main.models.quads.items[quad].textureSlot);
					data.append(@as(u32, quad) << 16 | textureIndex); // modelAndTexture
					data.append(0); // offsetByNormal
				}
				for(model.neighborFacingQuads) |list| {
					for(list) |quad| {
						const textureIndex = blocks.meshes.textureIndex(block, main.models.quads.items[quad].textureSlot);
						data.append(@as(u32, quad) << 16 | textureIndex); // modelAndTexture
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
		itemShader = graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/item_drop.vs", "assets/cubyz/shaders/item_drop.fs", "", &itemUniforms);
		itemModelSSBO = .init();
		itemModelSSBO.bufferData(i32, &[3]i32{1, 1, 1});
		itemModelSSBO.bind(2);

		modelData = .init(main.globalAllocator);
		freeSlots = .init(main.globalAllocator);
	}

	pub fn deinit() void {
		itemShader.deinit();
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

	pub fn renderItemDrops(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d, time: u32) void {
		game.world.?.itemDrops.updateInterpolationData();
		itemShader.bind();
		c.glUniform1i(itemUniforms.texture_sampler, 0);
		c.glUniform1i(itemUniforms.emissionSampler, 1);
		c.glUniform1i(itemUniforms.reflectivityAndAbsorptionSampler, 2);
		c.glUniform1i(itemUniforms.reflectionMap, 4);
		c.glUniform1f(itemUniforms.reflectionMapSize, main.renderer.reflectionCubeMapSize);
		c.glUniform1i(itemUniforms.time, @as(u31, @truncate(time)));
		c.glUniformMatrix4fv(itemUniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniformMatrix4fv(itemUniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));
		c.glUniform1f(itemUniforms.contrast, 0.12);
		const itemDrops = &game.world.?.itemDrops.super;
		itemDrops.mutex.lock();
		defer itemDrops.mutex.unlock();
		for(itemDrops.indices[0..itemDrops.size]) |i| {
			if(itemDrops.list.items(.itemStack)[i].item) |item| {
				var pos = itemDrops.list.items(.pos)[i];
				const rot = itemDrops.list.items(.rot)[i];
				const light: u32 = 0xffffffff; // TODO: Get this light value from the mesh_storage.
				c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&@max(
					ambientLight*@as(Vec3f, @splat(@as(f32, @floatFromInt(light >> 24))/255)),
					Vec3f{light >> 16 & 255, light >> 8 & 255, light & 255}/@as(Vec3f, @splat(255))
				)));
				pos -= playerPos;

				const model = getModel(item);
				c.glUniform1i(itemUniforms.modelIndex, model.index);
				var vertices: u31 = 36;

				var scale: f32 = 0.3;
				if(item == .baseItem and item.baseItem.block != null and item.baseItem.image.imageData.ptr == graphics.Image.defaultImage.imageData.ptr) {
					const blockType = item.baseItem.block.?;
					c.glUniform1i(itemUniforms.block, blockType);
					vertices = model.len/2*6;
				} else {
					c.glUniform1i(itemUniforms.block, 0);
					scale = 0.5;
				}

				var modelMatrix = Mat4f.translation(@floatCast(pos));
				modelMatrix = modelMatrix.mul(Mat4f.rotationX(-rot[0]));
				modelMatrix = modelMatrix.mul(Mat4f.rotationY(-rot[1]));
				modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-rot[2]));
				modelMatrix = modelMatrix.mul(Mat4f.scale(@splat(scale)));
				modelMatrix = modelMatrix.mul(Mat4f.translation(@splat(-0.5)));
				c.glUniformMatrix4fv(itemUniforms.modelMatrix, 1, c.GL_TRUE, @ptrCast(&modelMatrix));

				c.glBindVertexArray(main.renderer.chunk_meshing.vao);
				c.glDrawElements(c.GL_TRIANGLES, vertices, c.GL_UNSIGNED_INT, null);
			}
		}
	}
};