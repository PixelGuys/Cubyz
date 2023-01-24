const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk_zig = @import("chunk.zig");
const Chunk = chunk_zig.Chunk;
const game = @import("game.zig");
const World = game.World;
const items = @import("items.zig");
const ItemStack = items.ItemStack;
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const random = @import("random.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

const ItemDrop = struct {
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
	itemStack: ItemStack,
	despawnTime: u32,
	pickupCooldown: u32,

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

	world: *World,
	gravity: f64,
	airDragFactor: f64,

	size: u32 = 0,

	lastUpdates: JsonElement,

	// TODO: Get rid of this inheritance pattern.
	addWithIndexAndRotation: *const fn(*ItemDropManager, u16, Vec3d, Vec3d, Vec3f, ItemStack, u32, u32) void,

	pub fn init(self: *ItemDropManager, allocator: Allocator, world: *World) !void {
		self.* = ItemDropManager {
			.allocator = allocator,
			.list = std.MultiArrayList(ItemDrop){},
			.lastUpdates = try JsonElement.initArray(allocator),
			.isEmpty = std.bit_set.ArrayBitSet(usize, maxCapacity).initFull(),
			.world = world,
			.gravity = world.gravity,
			.airDragFactor = world.gravity/maxSpeed,
			.addWithIndexAndRotation = &defaultAddWithIndexAndRotation,
		};
		try self.list.resize(self.allocator, maxCapacity);
	}

	pub fn deinit(self: *ItemDropManager) void {
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
			json.get(u32, "despawnTime", 60),
			0
		};
		if(json.get(?usize, "i", null)) |i| {
			@call(.auto, addWithIndex, .{self, @intCast(u16, i)} ++ properties);
		} else {
			try @call(.auto, add, .{self} ++ properties);
		}
	}

	pub fn getPositionAndVelocityData(self: *ItemDropManager, allocator: Allocator) ![]u8 {
		const _data = try allocator.alloc(u8, self.size*50);
		var data = _data;
		var ii: u16 = 0;
		while(data.len != 0): (ii += 1) {
			const i = self.indices[ii];
			std.mem.writeIntBig(u16, data[0..2], i);
			std.mem.writeIntBig(u64, data[2..10], @bitCast(u64, self.pos[i][0]));
			std.mem.writeIntBig(u64, data[10..18], @bitCast(u64, self.pos[i][1]));
			std.mem.writeIntBig(u64, data[18..26], @bitCast(u64, self.pos[i][2]));
			std.mem.writeIntBig(u64, data[26..34], @bitCast(u64, self.vel[i][0]));
			std.mem.writeIntBig(u64, data[34..42], @bitCast(u64, self.vel[i][1]));
			std.mem.writeIntBig(u64, data[42..50], @bitCast(u64, self.vel[i][2]));
			data = data[50..];
		}
		return _data;
	}

	fn storeSingle(self: *ItemDropManager, allocator: Allocator, i: u16) !JsonElement {
		std.debug.assert(!self.mutex.tryLock()); // Mutex must be locked!
		var obj = try JsonElement.initObject(allocator);
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
			var ii: u32 = 0;
			while(ii < self.size) : (ii += 1) {
				const item = try self.storeSingle(allocator, self.indices[ii]);
				try jsonArray.JsonArray.append(item);
			}
		}
		const json = try JsonElement.initObject(allocator);
		json.put("array", jsonArray);
		return json;
	}

	pub fn update(self: *ItemDropManager, deltaTime: f32) void {
		const pos = self.list.items(.pos);
		const vel = self.list.items(.vel);
		const pickupCooldown = self.list.items(.pickupCooldown);
		const despawnTime = self.list.items(.despawnTime);
		var ii: u32 = 0;
		while(ii < self.size) : (ii += 1) {
			const i = self.indices[ii];
			if(self.world.getChunk(pos[i][0], pos[i][1], pos[i][2])) |chunk| {
				// Check collision with blocks:
				self.updateEnt(chunk, &pos[i], &vel[i], deltaTime);
			}
			pickupCooldown[i] -= 1;
			despawnTime[i] -= 1;
			if(despawnTime[i] < 0) {
				self.remove(i);
				ii -= 1;
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

	pub fn addFromBlockPosition(self: *ItemDropManager, blockPos: Vec3i, vel: Vec3d, itemStack: ItemStack, despawnTime: u32) void {
		self.add(
			Vec3d {
				@intToFloat(f64, blockPos[0]) + @floatCast(f64, random.nextFloat(&main.seed)), // TODO: Consider block bounding boxes.
				@intToFloat(f64, blockPos[1]) + @floatCast(f64, random.nextFloat(&main.seed)),
				@intToFloat(f64, blockPos[2]) + @floatCast(f64, random.nextFloat(&main.seed)),
			} + @splat(3, @as(f64, radius)),
			vel,
			Vec3f {
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
				2*std.math.pi*random.nextFloat(&main.seed),
			},
			itemStack, despawnTime, 0
		);
	}

	pub fn add(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, itemStack: ItemStack, despawnTime: u32, pickupCooldown: u32) !void {
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
	
	pub fn addWithIndex(self: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, itemStack: ItemStack, despawnTime: u32, pickupCooldown: u32) void {
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

	pub fn addWithRotation(self: *ItemDropManager, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: u32, pickupCooldown: u32) !void {
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
			i = @intCast(u16, self.isEmpty.findFirstSet().?);
		}
		self.addWithIndexAndRotation(self, i, pos, vel, rot, itemStack, despawnTime, pickupCooldown);
	}

	fn defaultAddWithIndexAndRotation(self: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: u32, pickupCooldown: u32) void {
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
			.reverseIndex = @intCast(u16, self.size),
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
		const startedInABlock = checkBlocks(chunk, pos);
		if(startedInABlock) {
			self.fixStuckInBlock(chunk, pos, vel, deltaTime);
			return;
		}
		const drag: f64 = self.airDragFactor;
		var acceleration: Vec3f = Vec3f{0, -self.gravity*deltaTime, 0};
		// Update gravity:
		inline for([_]u0{0} ** 3) |_, i| { // TODO: Use the new for loop syntax.
			const old = pos[i];
			pos[i] += vel[i]*deltaTime + acceleration[i]*deltaTime;
			if(self.checkBlocks(chunk, pos)) {
				pos[i] = old;
				vel[i] *= 0.5; // Effectively performing binary search over multiple frames.
			}
			drag += 0.5; // TODO: Calculate drag from block properties and add buoyancy.
		}
		// Apply drag:
		vel.* += acceleration;
		vel.* *= @splat(3, @max(0, 1 - drag*deltaTime));
	}

	fn fixStuckInBlock(self: *ItemDropManager, chunk: *Chunk, pos: *Vec3d, vel: *Vec3d, deltaTime: f64) void {
		std.debug.assert(!self.mutex.tryLock()); // Mutex must be locked!
		const centeredPos = pos.* - @splat(3, @as(f64, 0.5));
		const pos0 = vec.floatToInt(i32, @floor(centeredPos));

		var closestEmptyBlock = @splat(3, @splat(i32, -1));
		var closestDist = std.math.floatMax(f64);
		var delta = Vec3i{0, 0, 0};
		while(delta[0] <= 1) : (delta[0] += 1) {
			delta[1] = 0;
			while(delta[1] <= 1) : (delta[1] += 1) {
				delta[2] = 0;
				while(delta[2] <= 1) : (delta[2] += 1) {
					const isSolid = self.checkBlock(chunk, pos, pos0 + delta);
					if(!isSolid) {
						const dist = vec.lengthSquare(vec.intToFloat(f64, pos0 + delta) - centeredPos);
						if(dist < closestDist) {
							closestDist = dist;
							closestEmptyBlock = delta;
						}
					}
				}
			}
		}

		vel.* = @splat(3, @as(f64, 0));
		const factor = 1; // TODO: Investigate what past me wanted to accomplish here.
		if(closestDist == std.math.floatMax(f64)) {
			// Surrounded by solid blocks → move upwards
			vel[1] = factor;
			pos[1] += vel[1]*deltaTime;
		} else {
			vel.* = @splat(3, factor)*(vec.intToFloat(f64, pos0 + closestEmptyBlock) - centeredPos);
			pos.* += (vel.*)*@splat(3, deltaTime);
		}
	}

	fn checkBlocks(self: *ItemDropManager, chunk: *Chunk, pos: *Vec3d) void {
		const lowerCornerPos = pos.* - @splat(3, radius);
		const pos0 = vec.floatToInt(i32, @floor(lowerCornerPos));
		const isSolid = self.checkBlock(chunk, pos, pos0);
		if(pos[0] - @intToFloat(f64, pos0[0]) + diameter >= 1) {
			isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 0});
			if(pos[1] - @intToFloat(f64, pos0[1]) + diameter >= 1) {
				isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 0});
				isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 0});
				if(pos[2] - @intToFloat(f64, pos0[2]) + diameter >= 1) {
					isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
					isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 1});
					isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 1});
					isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{1, 1, 1});
				}
			} else {
				isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
				isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{1, 0, 1});
			}
		} else {
			if(pos[1] - @intToFloat(f64, pos0[1]) + diameter >= 1) {
				isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 0});
				if(pos[2] - @intToFloat(f64, pos0[2]) + diameter >= 1) {
					isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
					isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 1, 1});
				}
			} else {
				isSolid |= checkBlock(chunk, pos, pos0 + Vec3i{0, 0, 1});
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

	interpolation: utils.GenericInterpolation(maxf64Capacity) = undefined,

	var instance: ?*ClientItemDropManager = null;

	pub fn init(self: *ClientItemDropManager, allocator: Allocator, world: *World) !void {
		std.debug.assert(instance == null); // Only one instance allowed.
		instance = self;
		self.* = ClientItemDropManager {
			.super = undefined,
			.lastTime = @truncate(i16, std.time.milliTimestamp()) -% settings.entityLookback,
		};
		try self.super.init(allocator, world);
		self.super.addWithIndexAndRotation = &overrideAddWithIndexAndRotation;
		self.interpolation.init(
			@ptrCast(*[maxf64Capacity]f64, self.super.list.items(.pos).ptr),
			@ptrCast(*[maxf64Capacity]f64, self.super.list.items(.vel).ptr)
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
			const i = std.mem.readIntBig(u16, data[0..2]);
			pos[i][0] = @bitCast(f64, std.mem.readIntBig(u64, data[2..10]));
			pos[i][1] = @bitCast(f64, std.mem.readIntBig(u64, data[10..18]));
			pos[i][2] = @bitCast(f64, std.mem.readIntBig(u64, data[18..26]));
			vel[i][0] = @bitCast(f64, std.mem.readIntBig(u64, data[26..34]));
			vel[i][1] = @bitCast(f64, std.mem.readIntBig(u64, data[34..42]));
			vel[i][2] = @bitCast(f64, std.mem.readIntBig(u64, data[42..50]));
			data = data[50..];
		}
		self.interpolation.updatePosition(@ptrCast(*[maxf64Capacity]f64, &pos), @ptrCast(*[maxf64Capacity]f64, &vel), time); // TODO: Only update the ones we actually changed.
	}

	pub fn updateInterpolationData(self: *ClientItemDropManager) void {
		var time = @truncate(i16, std.time.milliTimestamp()) -% settings.entityLookback;
		time -%= self.timeDifference.difference;
		self.interpolation.updateIndexed(time, self.lastTime, &self.super.indices, 3);
		self.lastTime = time;
	}

	fn overrideAddWithIndexAndRotation(super: *ItemDropManager, i: u16, pos: Vec3d, vel: Vec3d, rot: Vec3f, itemStack: ItemStack, despawnTime: u32, pickupCooldown: u32) void {
		{
			super.mutex.lock();
			defer super.mutex.unlock();
			for(instance.?.interpolation.lastVel) |*lastVel| {
				@ptrCast(*align(8)[ItemDropManager.maxCapacity]Vec3d, lastVel)[i] = Vec3d{0, 0, 0};
			}
			for(instance.?.interpolation.lastPos) |*lastPos| {
				@ptrCast(*align(8)[ItemDropManager.maxCapacity]Vec3d, lastPos)[i] = pos;
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