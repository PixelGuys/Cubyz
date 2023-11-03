const std = @import("std");
const Allocator = std.mem.Allocator;

const blocks = @import("blocks.zig");
const chunk_zig = @import("chunk.zig");
const Chunk = chunk_zig.Chunk;
const game = @import("game.zig");
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const graphics = @import("graphics.zig");
const c = graphics.c;
const items = @import("items.zig");
const ItemStack = items.ItemStack;
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const random = @import("random.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

const ItemDrop = struct {
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
	itemStack: ItemStack,
	despawnTime: i32,
	pickupCooldown: i32,

	reverseIndex: u16,
};

pub const ItemDropManager = struct {
	/// Half the side length of all item entities hitboxes as a cube.
	const radius: f64 = 0.1;
	/// Side length of all item entities hitboxes as a cube.
	const diameter: f64 = 2*radius;

	const pickupRange: f64 = 1.0;

	const maxSpeed = 10;

	const maxCapacity = 65536;

	allocator: Allocator,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},

	list: std.MultiArrayList(ItemDrop),

	indices: [maxCapacity]u16 = undefined,

	isEmpty: std.bit_set.ArrayBitSet(usize, maxCapacity),

	world: ?*ServerWorld,
	gravity: f64,
	airDragFactor: f64,

	size: u32 = 0,

	lastUpdates: JsonElement,

	// TODO: Get rid of this inheritance pattern.
	addWithIndexAndRotation: *const fn(*ItemDropManager, u16, Vec3d, Vec3d, Vec3f, ItemStack, i32, i32) void,

	pub fn init(self: *ItemDropManager, allocator: Allocator, world: ?*ServerWorld, gravity: f64) !void {
		self.* = ItemDropManager {
			.allocator = allocator,
			.list = std.MultiArrayList(ItemDrop){},
			.lastUpdates = try JsonElement.initArray(allocator),
			.isEmpty = std.bit_set.ArrayBitSet(usize, maxCapacity).initFull(),
			.world = world,
			.gravity = gravity,
			.airDragFactor = gravity/maxSpeed,
			.addWithIndexAndRotation = &defaultAddWithIndexAndRotation,
		};
		try self.list.resize(self.allocator, maxCapacity);
	}

	pub fn deinit(self: *ItemDropManager) void {
		for(self.indices[0..self.size]) |i| {
			if(self.list.items(.itemStack)[i].item) |item| {
				item.deinit();
			}
		}
		self.list.deinit(self.allocator);
		self.lastUpdates.free(self.allocator);
	}

	pub fn loadFrom(self: *ItemDropManager, json: JsonElement) !void {
		const jsonArray = json.getChild("array");
		for(jsonArray.toSlice()) |elem| {
			try self.addFromJson(elem);
		}
	}

	pub fn addFromJson(self: *ItemDropManager, json: JsonElement) !void {
		const item = try items.Item.init(json);
		const properties = .{
			Vec3d{
				json.get(f64, "x", 0),
				json.get(f64, "y", 0),
				json.get(f64, "z", 0),
			},
			Vec3d{
				json.get(f64, "vx", 0),
				json.get(f64, "vy", 0),
				json.get(f64, "vz", 0),
			},
			items.ItemStack{.item = item, .amount = json.get(u16, "amount", 1)},
			json.get(i32, "despawnTime", 60),
			0
		};
		if(json.get(?u16, "i", null)) |i| {
			@call(.auto, addWithIndex, .{self, i} ++ properties);
		} else {
			try @call(.auto, add, .{self} ++ properties);
		}
	}

	pub fn getPositionAndVelocityData(self: *ItemDropManager, allocator: Allocator) ![]u8 {
		const _data = try allocator.alloc(u8, self.size*50);
		var data = _data;
		for(self.indices[0..self.size]) |i| {
			std.mem.writeInt(u16, data[0..2], i, .big);
			std.mem.writeInt(u64, data[2..10], @bitCast(self.pos[i][0]), .big);
			std.mem.writeInt(u64, data[10..18], @bitCast(self.pos[i][1]), .big);
			std.mem.writeInt(u64, data[18..26], @bitCast(self.pos[i][2]), .big);
			std.mem.writeInt(u64, data[26..34], @bitCast(self.vel[i][0]), .big);
			std.mem.writeInt(u64, data[34..42], @bitCast(self.vel[i][1]), .big);
			std.mem.writeInt(u64, data[42..50], @bitCast(self.vel[i][2]), .big);
			data = data[50..];
		}
		return _data;
	}

	fn storeSingle(self: *ItemDropManager, allocator: Allocator, i: u16) !JsonElement {
		std.debug.assert(!self.mutex.tryLock()); // Mutex must be locked!
		const obj = try JsonElement.initObject(allocator);
		const itemDrop = self.list.get(i);
		try obj.put("i", i);
		try obj.put("x", itemDrop.pos.x);
		try obj.put("y", itemDrop.pos.y);
		try obj.put("z", itemDrop.pos.z);
		try obj.put("vx", itemDrop.vel.x);
		try obj.put("vy", itemDrop.vel.y);
		try obj.put("vz", itemDrop.vel.z);
		try itemDrop.itemStack.storeToJson(obj);
		try obj.put("despawnTime", itemDrop.despawnTime);
		return obj;
	}

	pub fn store(self: *ItemDropManager, allocator: Allocator) !JsonElement {
		const jsonArray = try JsonElement.initArray(allocator);
		{
			self.mutex.lock();
			defer self.mutex.unlock();
			for(self.indices[0..self.size]) |i| {
				const item = try self.storeSingle(allocator, i);
				try jsonArray.JsonArray.append(item);
			}
		}
		const json = try JsonElement.initObject(allocator);
		json.put("array", jsonArray);
		return json;
	}

	pub fn update(self: *ItemDropManager, deltaTime: f32) void {
		std.debug.assert(self.world != null);
		const pos = self.list.items(.pos);
		const vel = self.list.items(.vel);
		const pickupCooldown = self.list.items(.pickupCooldown);
		const despawnTime = self.list.items(.despawnTime);
		var ii: u32 = 0;
		while(ii < self.size) {
			const i = self.indices[ii];
			if(self.world.?.getChunk(@intFromFloat(pos[i][0]), @intFromFloat(pos[i][1]), @intFromFloat(pos[i][2]))) |chunk| {
				// Check collision with blocks:
				self.updateEnt(chunk, &pos[i], &vel[i], deltaTime);
			}
			pickupCooldown[i] -= 1;
			despawnTime[i] -= 1;
			if(despawnTime[i] < 0) {
				self.remove(i);
			} else {
				ii += 1;
			}
		}
	}

//TODO:
//	public void checkEntity(Entity ent) {
//		for(int ii = 0; ii < size; ii++) {
//			int i = indices[ii] & 0xffff;
//			int i3 = 3*i;
//			if (pickupCooldown[i] >= 0) continue; // Item cannot be picked up yet.
//			if (Math.abs(ent.position.x - posxyz[i3]) < ent.width + PICKUP_RANGE && Math.abs(ent.position.y + ent.height/2 - posxyz[i3 + 1]) < ent.height + PICKUP_RANGE && Math.abs(ent.position.z - posxyz[i3 + 2]) < ent.width + PICKUP_RANGE) {
//				if(ent.getInventory().canCollect(itemStacks[i].getItem())) {
//					if(ent instanceof Player) {
//						// Needs to go through the network.
//						for(User user : Server.users) {
//							if(user.player == ent) {
//								Protocols.GENERIC_UPDATE.itemStackCollect(user, itemStacks[i]);
//								remove(i);
//								ii--;
//								break;
//							}
//						}
//					} else {
//						int newAmount = ent.getInventory().addItem(itemStacks[i].getItem(), itemStacks[i].getAmount());
//						if(newAmount != 0) {
//							itemStacks[i].setAmount(newAmount);
//						} else {
//							remove(i);
//							ii--;
//						}
//					}
//				}
//			}
//		}
//	}

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

	pub fn add(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) !void {
		try self.addWithRotation(
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

	pub fn addWithRotation(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: i32, pickupCooldown: i32) !void {
		var i: u16 = undefined;
		{
			self.mutex.lock();
			defer self.mutex.unlock();
			if(self.size == maxCapacity) {
				const json = try itemStack.store(main.threadAllocator);
				defer json.free(main.threadAllocator);
				const string = try json.toString(main.threadAllocator);
				defer main.threadAllocator.free(string);
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
// TODO:
//			if(world instanceof ServerWorld) {
//				lastUpdates.add(storeSingle(i));
//			}
		self.indices[self.size] = i;
		self.size += 1;
	}

	pub fn remove(self: *ItemDropManager, i: u16) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.size -= 1;
		const ii = self.list.items(.reverseIndex)[i];
		self.indices[ii] = self.indices[self.size];
		self.list.items(.itemStack)[i].clear();
		self.isEmpty.set(i);
		// TODO:
//			if(world instanceof ServerWorld) {
//				lastUpdates.add(new JsonInt(i));
//			}
	}
// TODO: Check if/how this is needed:
//	public Vector3d getPosition(int index) {
//		index *= 3;
//		return new Vector3d(posxyz[index], posxyz[index+1], posxyz[index+2]);
//	}
//
//	public Vector3f getRotation(int index) {
//		index *= 3;
//		return new Vector3f(rotxyz[index], rotxyz[index+1], rotxyz[index+2]);
//	}

	fn updateEnt(self: *ItemDropManager, chunk: *Chunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		std.debug.assert(!self.mutex.tryLock()); // Mutex must be locked!
		const startedInABlock = self.checkBlocks(chunk, pos);
		if(startedInABlock) {
			self.fixStuckInBlock(chunk, pos, vel, deltaTime);
			return;
		}
		var drag: f64 = self.airDragFactor;
		var acceleration: Vec3d = Vec3d{0, -self.gravity*deltaTime, 0};
		// Update gravity:
		inline for(0..3) |i| {
			const old = pos.*[i];
			pos.*[i] += vel.*[i]*deltaTime + acceleration[i]*deltaTime;
			if(self.checkBlocks(chunk, pos)) {
				pos.*[i] = old;
				vel.*[i] *= 0.5; // Effectively performing binary search over multiple frames.
			}
			drag += 0.5; // TODO: Calculate drag from block properties and add buoyancy.
		}
		// Apply drag:
		vel.* += acceleration;
		vel.* *= @splat(@max(0, 1 - drag*deltaTime));
	}

	fn fixStuckInBlock(self: *ItemDropManager, chunk: *Chunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		std.debug.assert(!self.mutex.tryLock()); // Mutex must be locked!
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
			vel.*[1] = unstuckVelocity;
			pos.*[1] += vel.*[1]*deltaTime;
		} else {
			vel.* = @as(Vec3d, @splat(unstuckVelocity))*(@as(Vec3d, @floatFromInt(pos0 + closestEmptyBlock)) - centeredPos);
			pos.* += (vel.*)*@as(Vec3d, @splat(deltaTime));
		}
	}

	fn checkBlocks(self: *ItemDropManager, chunk: *Chunk, pos: *Vec3d) bool {
		const lowerCornerPos = pos.* - @as(Vec3d, @splat(radius));
		const pos0f64 = @floor(lowerCornerPos);
		const pos0: Vec3i = @intFromFloat(pos0f64);
		var isSolid = self.checkBlock(chunk, pos, pos0);
		if(pos.*[0] - pos0f64[0] + diameter >= 1) {
			isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 0});
			if(pos.*[1] - pos0f64[1] + diameter >= 1) {
				isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 0});
				isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 0});
				if(pos.*[2] - pos0f64[2] + diameter >= 1) {
					isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
					isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 1});
					isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 1});
					isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{1, 1, 1});
				}
			} else {
				isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
				isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 1});
			}
		} else {
			if(pos.*[1] - pos0f64[1] + diameter >= 1) {
				isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 0});
				if(pos.*[2] - pos0f64[2] + diameter >= 1) {
					isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
					isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 1});
				}
			} else {
				isSolid = isSolid or self.checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
			}
		}
		return isSolid;
	}

	fn checkBlock(self: *ItemDropManager, chunk: *Chunk, pos: *Vec3d, blockPos: Vec3i) bool {
		// TODO:
		_ = self;
		_ = chunk;
		_ = pos;
		_ = blockPos;
		return false;
//		// Transform to chunk-relative coordinates:
//		int block = chunk.getBlockPossiblyOutside(x - chunk.wx, y - chunk.wy, z - chunk.wz);
//		if (block == 0) return false;
//		// Check if the item entity is inside the block:
//		boolean isInside = true;
//		if (Blocks.mode(block).changesHitbox()) {
//			isInside = Blocks.mode(block).checkEntity(new Vector3d(posxyz[index3], posxyz[index3+1]-RADIUS, posxyz[index3+2]), RADIUS, DIAMETER, x, y, z, block);
//		}
//		return isInside && Blocks.solid(block);
	}
};

pub const ClientItemDropManager = struct {
	const maxf64Capacity = ItemDropManager.maxCapacity*@sizeOf(Vec3d)/@sizeOf(f64);

	super: ItemDropManager,

	lastTime: i16,

	timeDifference: utils.TimeDifference = .{},

	interpolation: utils.GenericInterpolation(maxf64Capacity)align(64) = undefined,

	var instance: ?*ClientItemDropManager = null;

	pub fn init(self: *ClientItemDropManager, allocator: Allocator, world: *World) !void {
		std.debug.assert(instance == null); // Only one instance allowed.
		instance = self;
		self.* = .{
			.super = undefined,
			.lastTime = @as(i16, @truncate(std.time.milliTimestamp())) -% settings.entityLookback,
		};
		try self.super.init(allocator, null, world.gravity);
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
		time -%= self.timeDifference.difference.load(.Monotonic);
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

	pub fn loadFrom(self: *ClientItemDropManager, json: JsonElement) !void {
		try self.super.loadFrom(json);
	}

	pub fn addFromJson(self: *ClientItemDropManager, json: JsonElement) !void {
		try self.super.addFromJson(json);
	}
};

pub const ItemDropRenderer = struct {
	var itemShader: graphics.Shader = undefined;
	var itemUniforms: struct {
		projectionMatrix: c_int,
		modelMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		ambientLight: c_int,
		modelIndex: c_int,
		block: c_int,
		sizeScale: c_int,
		time: c_int,
		texture_sampler: c_int,
		emissionSampler: c_int,
	} = undefined;

	var itemModelSSBO: graphics.SSBO = undefined;
	var itemVAO: c_uint = undefined;
	var itemVBOs: [2]c_uint = undefined;

	var modelData: std.ArrayList(u32) = undefined;
	var freeSlots: std.ArrayList(*ItemVoxelModel) = undefined;

	const ItemVoxelModel = struct {
		index: u31 = undefined,
		size: Vec3i = undefined,
		item: items.Item,

		fn init(template: ItemVoxelModel) !*ItemVoxelModel {
			const self = try main.globalAllocator.create(ItemVoxelModel);
			self.* = ItemVoxelModel{
				.item = template.item,
			};
			// Find sizes and free index:
			const img = self.item.getImage();
			self.size = Vec3i{img.width, 1, img.height};
			var freeSlot: ?*ItemVoxelModel = null;
			for(freeSlots.items, 0..) |potentialSlot, i| {
				if(std.meta.eql(self.size, potentialSlot.size)) {
					freeSlot = potentialSlot;
					_ = freeSlots.swapRemove(i);
					break;
				}
			}
			const modelDataSize: u32 = @intCast(3 + @reduce(.Mul, self.size));
			var dataSection: []u32 = undefined;
			if(freeSlot) |_freeSlot| {
				main.globalAllocator.destroy(_freeSlot);
				self.index = _freeSlot.index;
			} else {
				self.index = @intCast(modelData.items.len);
				try modelData.resize(self.index + modelDataSize);
			}
			dataSection = modelData.items[self.index..][0..modelDataSize];
			dataSection[0] = @intCast(self.size[0]);
			dataSection[1] = @intCast(self.size[1]);
			dataSection[2] = @intCast(self.size[2]);
			var i: u32 = 3;
			var y: u32 = 0;
			while(y < 1) : (y += 1) {
				var x: u32 = 0;
				while(x < self.size[0]) : (x += 1) {
					var z: u32 = 0;
					while(z < self.size[2]) : (z += 1) {
						dataSection[i] = img.getRGB(x, z).toARBG();
						i += 1;
					}
				}
			}
			itemModelSSBO.bufferData(u32, modelData.items);
			return self;
		}

		fn deinit(self: *ItemVoxelModel) void {
			freeSlots.append(self) catch |err| {
				std.log.err("Encountered error {s} while freeing an ItemVoxelModel. This causes the game to leak {} bytes of memory.", .{@errorName(err), @reduce(.Mul, self.size) + 3});
				main.globalAllocator.destroy(self);
			};
		}

		pub fn equals(self: ItemVoxelModel, other: ?*ItemVoxelModel) bool {
			if(other == null) return false;
			return std.meta.eql(self.item, other.?.item);
		}

		pub fn hashCode(self: ItemVoxelModel) u32 {
			return self.item.hashCode();
		}
	};

	pub fn init() !void {
		itemShader = try graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/item_drop.vs", "assets/cubyz/shaders/item_drop.fs", &itemUniforms);
		itemModelSSBO = graphics.SSBO.init();
		itemModelSSBO.bufferData(i32, &[3]i32{1, 1, 1});
		itemModelSSBO.bind(2);

		const positions = [_]i32 {
			0b011000,
			0b011001,
			0b011010,
			0b011011,

			0b001000,
			0b001001,
			0b001100,
			0b001101,

			0b101000,
			0b101010,
			0b101100,
			0b101110,

			0b010100,
			0b010101,
			0b010110,
			0b010111,

			0b000010,
			0b000011,
			0b000110,
			0b000111,
			
			0b100001,
			0b100011,
			0b100101,
			0b100111,
		};
		const indices = [_]i32 {
			0, 1, 3,
			0, 3, 2,

			4, 7, 5,
			4, 6, 7,

			8, 9, 11,
			8, 11, 10,
			
			12, 15, 13,
			12, 14, 15,

			16, 17, 19,
			16, 19, 18,

			20, 23, 21,
			20, 22, 23,
		};
		c.glGenVertexArrays(1, &itemVAO);
		c.glBindVertexArray(itemVAO);
		c.glEnableVertexAttribArray(0);

		c.glGenBuffers(2, &itemVBOs);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, itemVBOs[0]);
		c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(positions.len*@sizeOf(i32)), &positions, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 1, c.GL_FLOAT, c.GL_FALSE, @sizeOf(i32), null);

		c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, itemVBOs[1]);
		c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len*@sizeOf(i32)), &indices, c.GL_STATIC_DRAW);

		c.glBindVertexArray(0);

		modelData = std.ArrayList(u32).init(main.globalAllocator);
		freeSlots = std.ArrayList(*ItemVoxelModel).init(main.globalAllocator);
	}

	pub fn deinit() void {
		itemShader.deinit();
		itemModelSSBO.deinit();
		c.glDeleteVertexArrays(1, &itemVAO);
		c.glDeleteBuffers(2, &itemVBOs);
		modelData.deinit();
		voxelModels.clear();
		for(freeSlots.items) |freeSlot| {
			main.globalAllocator.destroy(freeSlot);
		}
		freeSlots.deinit();
	}

	var voxelModels: utils.Cache(ItemVoxelModel, 32, 32, ItemVoxelModel.deinit) = .{};

	fn getModelIndex(item: items.Item) !u31 {
		const compareObject = ItemVoxelModel{.item = item};
		return (try voxelModels.findOrCreate(compareObject, ItemVoxelModel.init)).index;
	}

	pub fn renderItemDrops(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d, time: u32) !void {
		game.world.?.itemDrops.updateInterpolationData();
		itemShader.bind();
		c.glUniform1i(itemUniforms.texture_sampler, 0);
		c.glUniform1i(itemUniforms.emissionSampler, 1);
		c.glUniform1i(itemUniforms.time, @as(u31, @truncate(time)));
		c.glUniformMatrix4fv(itemUniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast(&projMatrix));
		c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniformMatrix4fv(itemUniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast(&game.camera.viewMatrix));
		c.glUniform1f(itemUniforms.sizeScale, @floatCast(ItemDropManager.diameter/4.0));
		const itemDrops = &game.world.?.itemDrops.super;
		itemDrops.mutex.lock();
		defer itemDrops.mutex.unlock();
		for(itemDrops.indices[0..itemDrops.size]) |i| {
			if(itemDrops.list.items(.itemStack)[i].item) |item| {
				var pos = itemDrops.list.items(.pos)[i];
				const rot = itemDrops.list.items(.rot)[i];
				// TODO: lighting:
//				int x = (int)(manager.posxyz[index3] + 1.0f);
//				int y = (int)(manager.posxyz[index3+1] + 1.0f);
//				int z = (int)(manager.posxyz[index3+2] + 1.0f);
//
//				int light = Cubyz.world.getLight(x, y, z, ambientLight, ClientSettings.easyLighting);
				const light: u32 = 0xffffffff;
				c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&@max(
					ambientLight*@as(Vec3f, @splat(@as(f32, @floatFromInt(light >> 24))/255)),
					Vec3f{light >> 16 & 255, light >> 8 & 255, light & 255}/@as(Vec3f, @splat(255))
				)));
				pos -= playerPos;
				var modelMatrix = Mat4f.translation(@floatCast(pos));
				modelMatrix = modelMatrix.mul(Mat4f.rotationX(-rot[0]));
				modelMatrix = modelMatrix.mul(Mat4f.rotationY(-rot[1]));
				modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-rot[2]));
				c.glUniformMatrix4fv(itemUniforms.modelMatrix, 1, c.GL_FALSE, @ptrCast(&modelMatrix));

				if(item == .baseItem and item.baseItem.block != null) {
					const blockType = item.baseItem.block.?;
					const block = blocks.Block{.typ = blockType, .data = 0};
					c.glUniform1i(itemUniforms.modelIndex, block.mode().model(block).modelIndex);
					c.glUniform1i(itemUniforms.block, blockType);
				} else {
					const index = try getModelIndex(item);
					c.glUniform1i(itemUniforms.modelIndex, index);
					c.glUniform1i(itemUniforms.block, 0);
				}
				c.glBindVertexArray(itemVAO);
				c.glDrawElements(c.GL_TRIANGLES, 36, c.GL_UNSIGNED_INT, null);
			}
		}
	}
};