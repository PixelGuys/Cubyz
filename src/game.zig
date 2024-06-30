const std = @import("std");
const Atomic = std.atomic.Value;

const assets = @import("assets.zig");
const chunk = @import("chunk.zig");
const itemdrop = @import("itemdrop.zig");
const ClientItemDropManager = itemdrop.ClientItemDropManager;
const items = @import("items.zig");
const Inventory = items.Inventory;
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const KeyBoard = main.KeyBoard;
const network = @import("network.zig");
const Connection = network.Connection;
const ConnectionManager = network.ConnectionManager;
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;
const graphics = @import("graphics.zig");
const models = main.models;
const Fog = graphics.Fog;
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");

pub const camera = struct {
	pub var rotation: Vec3f = Vec3f{0, 0, 0};
	pub var direction: Vec3f = Vec3f{0, 0, 0};
	pub var viewMatrix: Mat4f = Mat4f.identity();
	pub fn moveRotation(mouseX: f32, mouseY: f32) void {
		// Mouse movement along the y-axis rotates the image along the x-axis.
		rotation[0] += mouseY;
		if(rotation[0] > std.math.pi/2.0) {
			rotation[0] = std.math.pi/2.0;
		} else if(rotation[0] < -std.math.pi/2.0) {
			rotation[0] = -std.math.pi/2.0;
		}
		// Mouse movement along the x-axis rotates the image along the z-axis.
		rotation[2] += mouseX;
	}

	pub fn updateViewMatrix() void {
		direction = vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -rotation[0]), -rotation[2]);
		viewMatrix = Mat4f.identity().mul(Mat4f.rotationX(rotation[0])).mul(Mat4f.rotationZ(rotation[2]));
	}
};

const Box = struct {
	min: Vec3d,
	max: Vec3d,
};

pub const Player = struct {
	pub var super: main.server.Entity = .{};
	pub var id: u32 = 0;
	pub var isFlying: Atomic(bool) = Atomic(bool).init(false);
	pub var isGhost: Atomic(bool) = Atomic(bool).init(false);
	pub var hyperSpeed: Atomic(bool) = Atomic(bool).init(false);
	pub var mutex: std.Thread.Mutex = std.Thread.Mutex{};
	pub var inventory__SEND_CHANGES_TO_SERVER: Inventory = undefined;
	pub var selectedSlot: u32 = 0;

	pub var maxHealth: f32 = 8;
	pub var health: f32 = 4.5;

	pub var onGround: bool = false;

	pub const radius = 0.3;
	pub const height = 1.8;
	pub const eye = 1.7;
	pub const jumpHeight = 1.25;

	fn loadFrom(json: JsonElement) void {
		super.loadFrom(json);
		inventory__SEND_CHANGES_TO_SERVER.loadFromJson(json.getChild("inventory"));
	}

	pub fn setPosBlocking(newPos: Vec3d) void {
		mutex.lock();
		defer mutex.unlock();
		super.pos = newPos;
	}

	pub fn getPosBlocking() Vec3d {
		mutex.lock();
		defer mutex.unlock();
		return super.pos;
	}

	pub fn getVelBlocking() Vec3d {
		mutex.lock();
		defer mutex.unlock();
		return super.vel;
	}

	pub fn triangleAABB(triangle: [3]Vec3d, box_center: Vec3d, box_extents: Vec3d) bool {
		const X = 0;
		const Y = 1;
		const Z = 2;

		// Translate triangle as conceptually moving AABB to origin
		const v0 = triangle[0] - box_center;
		const v1 = triangle[1] - box_center;
		const v2 = triangle[2] - box_center;

		// Compute edge vectors for triangle
		const f0 = triangle[1] - triangle[0];
		const f1 = triangle[2] - triangle[1];
		const f2 = triangle[0] - triangle[2];

		// Test axis a00
		const a00 = Vec3d{0, -f0[Z], f0[Y]};
		if (!test_axis(a00, v0, v1, v2, box_extents[Y] * @abs(f0[Z]) + box_extents[Z] * @abs(f0[Y]))) {
			return false;
		}

		// Test axis a01
		const a01 = Vec3d{0, -f1[Z], f1[Y]};
		if (!test_axis(a01, v0, v1, v2, box_extents[Y] * @abs(f1[Z]) + box_extents[Z] * @abs(f1[Y]))) {
			return false;
		}

		// Test axis a02
		const a02 = Vec3d{0, -f2[Z], f2[Y]};
		if (!test_axis(a02, v0, v1, v2, box_extents[Y] * @abs(f2[Z]) + box_extents[Z] * @abs(f2[Y]))) {
			return false;
		}

		// Test axis a10
		const a10 = Vec3d{f0[Z], 0, -f0[X]};
		if (!test_axis(a10, v0, v1, v2, box_extents[X] * @abs(f0[Z]) + box_extents[Z] * @abs(f0[X]))) {
			return false;
		}

		// Test axis a11
		const a11 = Vec3d{f1[Z], 0, -f1[X]};
		if (!test_axis(a11, v0, v1, v2, box_extents[X] * @abs(f1[Z]) + box_extents[Z] * @abs(f1[X]))) {
			return false;
		}

		// Test axis a12
		const a12 = Vec3d{f2[Z], 0, -f2[X]};
		if (!test_axis(a12, v0, v1, v2, box_extents[X] * @abs(f2[Z]) + box_extents[Z] * @abs(f2[X]))) {
			return false;
		}

		// Test axis a20
		const a20 = Vec3d{-f0[Y], f0[X], 0};
		if (!test_axis(a20, v0, v1, v2, box_extents[X] * @abs(f0[Y]) + box_extents[Y] * @abs(f0[X]))) {
			return false;
		}

		// Test axis a21
		const a21 = Vec3d{-f1[Y], f1[X], 0};
		if (!test_axis(a21, v0, v1, v2, box_extents[X] * @abs(f1[Y]) + box_extents[Y] * @abs(f1[X]))) {
			return false;
		}

		// Test axis a22
		const a22 = Vec3d{-f2[Y], f2[X], 0};
		if (!test_axis(a22, v0, v1, v2, box_extents[X] * @abs(f2[Y]) + box_extents[Y] * @abs(f2[X]))) {
			return false;
		}

		// Test the three axes corresponding to the face normals of AABB
		if (@max(v0[X], @max(v1[X], v2[X])) < -box_extents[X] or @min(v0[X], @min(v1[X], v2[X])) > box_extents[X]) {
			return false;
		}
		if (@max(v0[Y], @max(v1[Y], v2[Y])) < -box_extents[Y] or @min(v0[Y], @min(v1[Y], v2[Y])) > box_extents[Y]) {
			return false;
		}
		if (@max(v0[Z], @max(v1[Z], v2[Z])) < -box_extents[Z] or @min(v0[Z], @min(v1[Z], v2[Z])) > box_extents[Z]) {
			return false;
		}

		// Test separating axis corresponding to triangle face normal
		const plane_normal = vec.cross(f0, f1);
		const plane_distance = @abs(vec.dot(plane_normal, v0));
		const r = box_extents[X] * @abs(plane_normal[X]) + box_extents[Y] * @abs(plane_normal[Y]) + box_extents[Z] * @abs(plane_normal[Z]);

		return plane_distance <= r;
	}

	fn test_axis(axis: Vec3d, v0: Vec3d, v1: Vec3d, v2: Vec3d, r: f64) bool {
		const p0 = vec.dot(v0, axis);
		const p1 = vec.dot(v1, axis);
		const p2 = vec.dot(v2, axis);
		const min_p = @min(p0, @min(p1, p2));
		const max_p = @max(p0, @max(p1, p2));
		return @max(-max_p, min_p) <= r;
	}

	const Direction = enum {x, y, z};

	pub fn collides(dir: Direction, amount: f64) ?Box {
		var boundingBox: Box = .{
			.min = super.pos - Vec3d{radius, radius, 0},
			.max = super.pos + Vec3d{radius, radius, height},
		};
		switch (dir) {
			.x => {
				if(amount < 0) boundingBox.min[0] += amount else boundingBox.max[0] += amount;
			},
			.y => {
				if(amount < 0) boundingBox.min[1] += amount else boundingBox.max[1] += amount;
			},
			.z => {
				if(amount < 0) boundingBox.min[2] += amount else boundingBox.max[2] += amount;
			},
		}
		const minX: i32 = @intFromFloat(@floor(boundingBox.min[0]));
		const maxX: i32 = @intFromFloat(@floor(boundingBox.max[0] - 0.0001));
		const minY: i32 = @intFromFloat(@floor(boundingBox.min[1]));
		const maxY: i32 = @intFromFloat(@floor(boundingBox.max[1] - 0.0001));
		const minZ: i32 = @intFromFloat(@floor(boundingBox.min[2]));
		const maxZ: i32 = @intFromFloat(@floor(boundingBox.max[2] - 0.0001));

		const boundingBoxCenter = (boundingBox.min + boundingBox.max)/@as(Vec3d, @splat(2));
		const boundingBoxExtent = (boundingBox.max - boundingBox.min - @as(Vec3d, @splat(0.0001)))/@as(Vec3d, @splat(2));

		var resultBox: ?Box = null;
		var minDistance: f64 = std.math.floatMax(f64);
		const directionVector: Vec3d = switch (dir) {
			.x => .{-std.math.sign(amount), 0, 0},
			.y => .{0, -std.math.sign(amount), 0},
			.z => .{0, 0, -std.math.sign(amount)},
		};

		var x: i32 = minX;
		while (x <= maxX) : (x += 1) {
			var y: i32 = minY;
			while (y <= maxY) : (y += 1) {
				var z: i32 = maxZ;
				while (z >= minZ) : (z -= 1) {
					if (main.renderer.mesh_storage.getBlock(x, y, z)) |block| {
						if(block.collide()) {
							const model = &models.models.items[block.mode().model(block)];

							const pos = Vec3d{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};

							for (model.neighborFacingQuads) |quads| {
								for (quads) |quadIndex| {
									const quad = &models.quads.items[quadIndex];
									if (triangleAABB(.{quad.corners[0] + quad.normal + pos, quad.corners[2] + quad.normal + pos, quad.corners[1] + quad.normal + pos}, boundingBoxCenter, boundingBoxExtent)) {
										const min = @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + quad.normal + pos;
										const max = @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + quad.normal + pos;
										const dist = @min(vec.dot(directionVector, min), vec.dot(directionVector, max));
										if(dist < minDistance) {
											resultBox = .{.min = min, .max = max};
											minDistance = dist;
										} else if(dist == minDistance) {
											resultBox.?.min = @min(resultBox.?.min, min);
											resultBox.?.max = @min(resultBox.?.max, max);
										}
									}
									if (triangleAABB(.{quad.corners[1] + quad.normal + pos, quad.corners[2] + quad.normal + pos, quad.corners[3] + quad.normal + pos}, boundingBoxCenter, boundingBoxExtent)) {
										const min = @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + quad.normal + pos;
										const max = @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + quad.normal + pos;
										const dist = @min(vec.dot(directionVector, min), vec.dot(directionVector, max));
										if(dist < minDistance) {
											resultBox = .{.min = min, .max = max};
											minDistance = dist;
										} else if(dist == minDistance) {
											resultBox.?.min = @min(resultBox.?.min, min);
											resultBox.?.max = @min(resultBox.?.max, max);
										}
									}
								}
							}

							for (model.internalQuads) |quadIndex| {
								const quad = &models.quads.items[quadIndex];
								if (triangleAABB(.{quad.corners[0] + pos, quad.corners[2] + pos, quad.corners[1] + pos}, boundingBoxCenter, boundingBoxExtent)) {
									const min = @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + pos;
									const max = @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + pos;
									const dist = @min(vec.dot(directionVector, min), vec.dot(directionVector, max));
									if(dist < minDistance) {
										resultBox = .{.min = min, .max = max};
										minDistance = dist;
									} else if(dist == minDistance) {
										resultBox.?.min = @min(resultBox.?.min, min);
										resultBox.?.max = @min(resultBox.?.max, max);
									}
								}
								if (triangleAABB(.{quad.corners[1] + pos, quad.corners[2] + pos, quad.corners[3] + pos}, boundingBoxCenter, boundingBoxExtent)) {
									const min = @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + pos;
									const max = @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + pos;
									const dist = @min(vec.dot(directionVector, min), vec.dot(directionVector, max));
									if(dist < minDistance) {
										resultBox = .{.min = min, .max = max};
										minDistance = dist;
									} else if(dist == minDistance) {
										resultBox.?.min = @min(resultBox.?.min, min);
										resultBox.?.max = @min(resultBox.?.max, max);
									}
								}
							}
						}
					}
				}
			}
		}

		return resultBox;
	}

	pub fn placeBlock() void {
		if(!main.Window.grabbed) return;
		main.renderer.MeshSelection.placeBlock(&inventory__SEND_CHANGES_TO_SERVER.items[selectedSlot]);
	}

	pub fn breakBlock() void { // TODO: Breaking animation and tools
		if(!main.Window.grabbed) return;
		main.renderer.MeshSelection.breakBlock(&inventory__SEND_CHANGES_TO_SERVER.items[selectedSlot]);
	}

	pub fn acquireSelectedBlock() void { 
		if (main.renderer.MeshSelection.selectedBlockPos) |selectedPos| {
			const block = main.renderer.mesh_storage.getBlock(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;
			for (0..items.itemListSize) |idx|{
				if (items.itemList[idx].block == block.typ){
					const item = items.Item {.baseItem = &items.itemList[idx]};
					inventory__SEND_CHANGES_TO_SERVER.items[selectedSlot] = items.ItemStack {.item = item, .amount = items.itemList[idx].stackSize};
				}
			}
		}
	}
};

pub const World = struct {
	const dayCycle: u63 = 12000; // Length of one in-game day in 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes

	conn: *Connection,
	manager: *ConnectionManager,
	ambientLight: f32 = 0,
	clearColor: Vec4f = Vec4f{0, 0, 0, 1},
	gravity: f64 = 9.81*1.5, // TODO: Balance
	name: []const u8,
	milliTime: i64,
	gameTime: Atomic(i64) = Atomic(i64).init(0),
	spawn: Vec3f = undefined,
	blockPalette: *assets.Palette = undefined,
	biomePalette: *assets.Palette = undefined,
	itemDrops: ClientItemDropManager = undefined,
	playerBiome: Atomic(*const main.server.terrain.biomes.Biome) = undefined,

	pub fn init(self: *World, ip: []const u8, manager: *ConnectionManager) !void {
		self.* = .{
			.conn = try Connection.init(manager, ip, null),
			.manager = manager,
			.name = "client",
			.milliTime = std.time.milliTimestamp(),
		};
		self.itemDrops.init(main.globalAllocator, self);
		Player.inventory__SEND_CHANGES_TO_SERVER = Inventory.init(main.globalAllocator, 32);
		network.Protocols.handShake.clientSide(self.conn, settings.playerName);

		main.Window.setMouseGrabbed(true);

		main.blocks.meshes.generateTextureArray();
		main.models.uploadModels();
		self.playerBiome = Atomic(*const main.server.terrain.biomes.Biome).init(main.server.terrain.biomes.getById(""));
	}

	pub fn deinit(self: *World) void {
		// TODO: Close all world related guis.
		main.gui.deinit();
		main.gui.init();

		main.threadPool.clear();
		self.conn.deinit();
		self.itemDrops.deinit();
		self.blockPalette.deinit();
		self.biomePalette.deinit();
		self.manager.deinit();
		main.server.stop();
		if(main.server.thread) |serverThread| {
			serverThread.join();
			main.server.thread = null;
		}
		main.threadPool.clear();
		renderer.mesh_storage.deinit();
		renderer.mesh_storage.init();
		assets.unloadAssets();
		Player.inventory__SEND_CHANGES_TO_SERVER.deinit(main.globalAllocator);
	}

	pub fn finishHandshake(self: *World, json: JsonElement) !void {
		// TODO: Consider using a per-world allocator.
		self.blockPalette = try assets.Palette.init(main.globalAllocator, json.getChild("blockPalette"), "cubyz:air");
		errdefer self.blockPalette.deinit();
		self.biomePalette = try assets.Palette.init(main.globalAllocator, json.getChild("biomePalette"), null);
		errdefer self.biomePalette.deinit();
		self.spawn = json.get(Vec3f, "spawn", .{0, 0, 0});

		try assets.loadWorldAssets("serverAssets", self.blockPalette, self.biomePalette);
		Player.loadFrom(json.getChild("player"));
		Player.id = json.get(u32, "player_id", std.math.maxInt(u32));
	}

	pub fn update(self: *World) void {
		const newTime: i64 = std.time.milliTimestamp();
		while(self.milliTime +% 100 -% newTime < 0) {
			self.milliTime +%= 100;
			var curTime = self.gameTime.load(.monotonic);
			while(self.gameTime.cmpxchgWeak(curTime, curTime +% 1, .monotonic, .monotonic)) |actualTime| {
				curTime = actualTime;
			}
		}
		// Ambient light:
		{
			const dayTime = @abs(@mod(self.gameTime.load(.monotonic), dayCycle) -% dayCycle/2);
			const biomeFog = fog.fogColor;
			if(dayTime < dayCycle/4 - dayCycle/16) {
				self.ambientLight = 0.1;
				self.clearColor[0] = 0;
				self.clearColor[1] = 0;
				self.clearColor[2] = 0;
			} else if(dayTime > dayCycle/4 + dayCycle/16) {
				self.ambientLight = 1;
				self.clearColor[0] = biomeFog[0];
				self.clearColor[1] = biomeFog[1];
				self.clearColor[2] = biomeFog[2];
			} else {
				// b:
				if(dayTime > dayCycle/4) {
					self.clearColor[2] = biomeFog[2] * @as(f32, @floatFromInt(dayTime - dayCycle/4))/@as(f32, @floatFromInt(dayCycle/16));
				} else {
					self.clearColor[2] = 0;
				}
				// g:
				if(dayTime > dayCycle/4 + dayCycle/32) {
					self.clearColor[1] = biomeFog[1];
				} else if(dayTime > dayCycle/4 - dayCycle/32) {
					self.clearColor[1] = biomeFog[1] - biomeFog[1]*@as(f32, @floatFromInt(dayCycle/4 + dayCycle/32 - dayTime))/@as(f32, @floatFromInt(dayCycle/16));
				} else {
					self.clearColor[1] = 0;
				}
				// r:
				if(dayTime > dayCycle/4) {
					self.clearColor[0] = biomeFog[0];
				} else {
					self.clearColor[0] = biomeFog[0] - biomeFog[0]*@as(f32, @floatFromInt(dayCycle/4 - dayTime))/@as(f32, @floatFromInt(dayCycle/16));
				}
				self.ambientLight = 0.1 + 0.9*@as(f32, @floatFromInt(dayTime - (dayCycle/4 - dayCycle/16)))/@as(f32, @floatFromInt(dayCycle/8));
			}
		}
		network.Protocols.playerPosition.send(self.conn, Player.getPosBlocking(), Player.getVelBlocking(), @intCast(newTime & 65535));
	}
};
pub var testWorld: World = undefined; // TODO:
pub var world: ?*World = null;

pub var projectionMatrix: Mat4f = Mat4f.identity();

pub var fog = Fog{.skyColor=.{0.8, 0.8, 1}, .fogColor=.{0.8, 0.8, 1}, .density=1.0/15.0/128.0}; // TODO: Make this depend on the render distance.

var nextBlockPlaceTime: ?i64 = null;
var nextBlockBreakTime: ?i64 = null;

pub fn pressPlace() void {
	const time = std.time.milliTimestamp();
	nextBlockPlaceTime = time + main.settings.updateRepeatDelay;
	Player.placeBlock();
}

pub fn releasePlace() void {
	nextBlockPlaceTime = null;
}

pub fn pressBreak() void {
	const time = std.time.milliTimestamp();
	nextBlockBreakTime = time + main.settings.updateRepeatDelay;
	Player.breakBlock();
}

pub fn releaseBreak() void {
	nextBlockBreakTime = null;
}

pub fn pressAcquireSelectedBlock() void {
	Player.acquireSelectedBlock();
}

pub fn flyToggle() void {
	Player.isFlying.store(!Player.isFlying.load(.monotonic), .monotonic);
	if(!Player.isFlying.load(.monotonic)) Player.isGhost.store(false, .monotonic);
}

pub fn ghostToggle() void {
	Player.isGhost.store(!Player.isGhost.load(.monotonic), .monotonic);
	if(Player.isGhost.load(.monotonic)) Player.isFlying.store(true, .monotonic);
}

pub fn hyperSpeedToggle() void {
	Player.hyperSpeed.store(!Player.hyperSpeed.load(.monotonic), .monotonic);
}

pub fn update(deltaTime: f64) void {
	const gravity = 30.0;
	const terminalVelocity = 90.0;
	const airFrictionCoefficient = gravity/terminalVelocity; // λ = a/v in equillibrium
	var move: Vec3d = .{0, 0, 0};
	if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(Player.super.pos[0])), @intFromFloat(@floor(Player.super.pos[1])), @intFromFloat(@floor(Player.super.pos[2]))) != null) {		
		var acc = Vec3d{0, 0, 0};
		if (!Player.isFlying.load(.monotonic)) {
			acc[2] = -gravity;
		}

		var baseFrictionCoefficient: f32 = 50;
		const speedMultiplier: f32 = if(Player.hyperSpeed.load(.monotonic)) 4.0 else 1.0;

		if (!Player.onGround and !Player.isFlying.load(.monotonic)) {
			baseFrictionCoefficient = airFrictionCoefficient;
		}

		var jumping: bool = false;
		// At equillibrium we want to have dv/dt = a - λv = 0 → a = λ*v
		const fricMul = speedMultiplier*baseFrictionCoefficient;

		const forward = vec.rotateZ(Vec3d{0, 1, 0}, -camera.rotation[2]);
		const right = Vec3d{-forward[1], forward[0], 0};
		if(main.Window.grabbed) {
			if(KeyBoard.key("forward").pressed) {
				if(KeyBoard.key("sprint").pressed) {
					if(Player.isGhost.load(.monotonic)) {
						acc += forward*@as(Vec3d, @splat(128 * fricMul));
					} else if(Player.isFlying.load(.monotonic)) {
						acc += forward*@as(Vec3d, @splat(32 * fricMul));
					} else {
						acc += forward*@as(Vec3d, @splat(8 * fricMul));
					}
				} else {
					acc += forward*@as(Vec3d, @splat(4 * fricMul));
				}
			}
			if(KeyBoard.key("backward").pressed) {
				acc += forward*@as(Vec3d, @splat(-4 * fricMul));
			}
			if(KeyBoard.key("left").pressed) {
				acc += right*@as(Vec3d, @splat(4 * fricMul));
			}
			if(KeyBoard.key("right").pressed) {
				acc += right*@as(Vec3d, @splat(-4 * fricMul));
			}
			if(KeyBoard.key("jump").pressed) {
				if(Player.isFlying.load(.monotonic)) {
					if(KeyBoard.key("sprint").pressed) {
						if(Player.isGhost.load(.monotonic)) {
							acc[2] += 60 * fricMul;
						} else {
							acc[2] += 25 * fricMul;
						}
					} else {
						acc[2] += 5.45 * fricMul;
					}
				} else if (Player.onGround) {
					jumping = true;
				}
			}
			if(KeyBoard.key("fall").pressed) {
				if(Player.isFlying.load(.monotonic)) {
					if(KeyBoard.key("sprint").pressed) {
						if(Player.isGhost.load(.monotonic)) {
							acc[2] += -60 * fricMul;
						} else {
							acc[2] += -25 * fricMul;
						}
					} else {
						acc[2] += -5.45 * fricMul;
					}
				}
			}

			const newSlot: i32 = @as(i32, @intCast(Player.selectedSlot)) -% @as(i32, @intFromFloat(main.Window.scrollOffset));
			Player.selectedSlot = @intCast(@mod(newSlot, 12));
			main.Window.scrollOffset = 0;
		}

		// This our model for movement on a single frame:
		// dv/dt = a - λ·v
		// dx/dt = v
		// Where a is the acceleration, λ is the friction coefficient
		// The solution is given by:
		// v(t) = a/λ + c_1 e^(λ (-t))
		// v(0) = a/λ + c_1 = v₀
		// c_1 = v₀ - a/λ
		// x(t) = ∫v(t) dt
		// x(t) = ∫a/λ + c_1 e^(λ (-t)) dt
		// x(t) = a/λt - c_1/λ e^(λ (-t)) + C
		// With x(0) = 0 we get C = c_1/λ
		// x(t) = a/λt - c_1/λ e^(λ (-t)) + c_1/λ
		inline for(0..3) |i| {
			var frictionCoefficient = baseFrictionCoefficient;
			if(i == 2 and jumping) { // No friction while jumping
				// Here we want to ensure a specified jump height under air friction.
				Player.super.vel[i] = @sqrt(Player.jumpHeight * gravity * 2);
				frictionCoefficient = airFrictionCoefficient;
			}
			const c_1 = Player.super.vel[i] - acc[i]/frictionCoefficient;
			Player.super.vel[i] = acc[i]/frictionCoefficient + c_1*@exp(-frictionCoefficient*deltaTime);
			move[i] = acc[i]/frictionCoefficient*deltaTime - c_1/frictionCoefficient*@exp(-frictionCoefficient*deltaTime) + c_1/frictionCoefficient;
		}
	}

	const time = std.time.milliTimestamp();
	if(nextBlockPlaceTime) |*placeTime| {
		if(time -% placeTime.* >= 0) {
			placeTime.* += main.settings.updateRepeatSpeed;
			Player.placeBlock();
		}
	}
	if(nextBlockBreakTime) |*breakTime| {
		if(time -% breakTime.* >= 0) {
			breakTime.* += main.settings.updateRepeatSpeed;
			Player.breakBlock();
		}
	}

	if(!Player.isGhost.load(.monotonic)) {
		Player.mutex.lock();
		defer Player.mutex.unlock();

		Player.super.pos[0] += move[0];
		if (Player.collides(.x, -move[0])) |box| {
			var step = false;
			if (box.max[2] - Player.super.pos[2] <= 0.5 and Player.onGround) {
				const old = Player.super.pos[2];
				Player.super.pos[2] = box.max[2] + 0.0001;
				if (Player.collides(.x, 0)) |_| {
					Player.super.pos[2] = old;
				} else {
					step = true;
				}
			}
			if (!step)
			{
				if (move[0] < 0) {
					Player.super.pos[0] = box.max[0] + Player.radius;
					while (Player.collides(.x, 0)) |_| {
						Player.super.pos[0] += 1;
					}
				} else {
					Player.super.pos[0] = box.min[0] - Player.radius;
					while (Player.collides(.x, 0)) |_| {
						Player.super.pos[0] -= 1;
					}
				}
				Player.super.vel[0] = 0;
			}
		}

		Player.super.pos[1] += move[1];
		if (Player.collides(.y, -move[1])) |box| {
			var step = false;
			if (box.max[2] - Player.super.pos[2] <= 0.5 and Player.onGround) {
				const old = Player.super.pos[2];
				Player.super.pos[2] = box.max[2] + 0.0001;
				if (Player.collides(.y, 0)) |_| {
					Player.super.pos[2] = old;
				} else {
					step = true;
				}
			}

			if (!step) {
				if (move[1] < 0) {
					Player.super.pos[1] = box.max[1] + Player.radius;
					while (Player.collides(.y, 0)) |_| {
						Player.super.pos[1] += 1;
					}
				} else {
					Player.super.pos[1] = box.min[1] - Player.radius;
					while (Player.collides(.y, 0)) |_| {
						Player.super.pos[1] -= 1;
					}
				}
				Player.super.vel[1] = 0;
			}
		}

		Player.onGround = false;
		Player.super.pos[2] += move[2];
		if (Player.collides(.z, -move[2])) |box| {
			if (move[2] < 0) {
				Player.super.pos[2] = box.max[2];
				while (Player.collides(.z, 0)) |_| {
					Player.super.pos[2] += 1;
				}
				Player.onGround = true;
			} else {
				Player.super.pos[2] = box.min[2] - Player.height;
				while (Player.collides(.z, 0)) |_| {
					Player.super.pos[2] -= 1;
				}
			}
			Player.super.vel[2] = 0;
		}
	} else {
		Player.super.pos += move;
	}

	const biome = world.?.playerBiome.load(.monotonic);
	
	const t = 1 - @as(f32, @floatCast(@exp(-2 * deltaTime)));

	fog.fogColor = (biome.fogColor - fog.fogColor) * @as(Vec3f, @splat(t)) + fog.fogColor;
	fog.density = (biome.fogDensity - fog.density) * t + fog.density;

	world.?.update();
}