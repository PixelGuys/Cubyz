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

	pub const boundingBoxExtent: Vec3d = .{0.4, 0.4, 0.9};
	pub const eye = 1.7 - boundingBoxExtent[2];
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

	pub fn collisionBox(relativeHitBox: Box) Box {
		var hitBox = relativeHitBox;
		hitBox.min += super.pos;
		hitBox.max += super.pos;
		const hitBoxCenter: Vec3d = (hitBox.min + hitBox.max)*@as(Vec3d, @splat(0.5));
		const hitBoxExtent: Vec3d = (hitBox.max - hitBox.min)*@as(Vec3d, @splat(0.5)) - @as(Vec3d, @splat(0.0001));
		var result: Box = .{
			.min = hitBox.max,
			.max = hitBox.min,
		};
		const minX: i32 = @intFromFloat(@floor(hitBoxCenter[0] - hitBoxExtent[0]));
		const maxX: i32 = @intFromFloat(@floor(hitBoxCenter[0] + hitBoxExtent[0]));
		const minY: i32 = @intFromFloat(@floor(hitBoxCenter[1] - hitBoxExtent[1]));
		const maxY: i32 = @intFromFloat(@floor(hitBoxCenter[1] + hitBoxExtent[1]));
		const minZ: i32 = @intFromFloat(@floor(hitBoxCenter[2] - hitBoxExtent[2]));
		const maxZ: i32 = @intFromFloat(@floor(hitBoxCenter[2] + hitBoxExtent[2]));

		var x: i32 = minX;
		while (x <= maxX) : (x += 1) {
			var y: i32 = minY;
			while (y <= maxY) : (y += 1) {
				var z: i32 = maxZ;
				while (z >= minZ) : (z -= 1) {
					if (main.renderer.mesh_storage.getBlock(x, y, z)) |block| {
						if (block.collide()) {
							const model = &models.models.items[block.mode().model(block)];

							const pos = Vec3d{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};

							for (model.neighborFacingQuads) |quads| {
								for (quads) |quadIndex| {
									const quad = &models.quads.items[quadIndex];
									if (triangleAABB(.{quad.corners[0] + quad.normal + pos, quad.corners[2] + quad.normal + pos, quad.corners[1] + quad.normal + pos}, hitBoxCenter, hitBoxExtent)) {
										result.min = @min(result.min, @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + quad.normal + pos);
										result.max = @max(result.max, @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + quad.normal + pos);
										result.min = @select(f64, quad.normal > @as(Vec3d, @splat(0.5)), hitBox.min, result.min);
										result.max = @select(f64, quad.normal < @as(Vec3d, @splat(-0.5)), hitBox.max, result.max);
									}
									if (triangleAABB(.{quad.corners[1] + quad.normal + pos, quad.corners[2] + quad.normal + pos, quad.corners[3] + quad.normal + pos}, hitBoxCenter, hitBoxExtent)) {
										result.min = @min(result.min, @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + quad.normal + pos);
										result.max = @max(result.max, @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + quad.normal + pos);
										result.min = @select(f64, quad.normal > @as(Vec3d, @splat(0.5)), hitBox.min, result.min);
										result.max = @select(f64, quad.normal < @as(Vec3d, @splat(-0.5)), hitBox.max, result.max);
									}
								}
							}

							for (model.internalQuads) |quadIndex| {
								const quad = &models.quads.items[quadIndex];
								if (triangleAABB(.{quad.corners[0] + pos, quad.corners[2] + pos, quad.corners[1] + pos}, hitBoxCenter, hitBoxExtent)) {
									result.min = @min(result.min, @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + pos);
									result.max = @max(result.max, @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + pos);
									result.min = @select(f64, quad.normal > @as(Vec3d, @splat(0.5)), hitBox.min, result.min);
									result.max = @select(f64, quad.normal < @as(Vec3d, @splat(-0.5)), hitBox.max, result.max);
								}
								if (triangleAABB(.{quad.corners[1] + pos, quad.corners[2] + pos, quad.corners[3] + pos}, hitBoxCenter, hitBoxExtent)) {
									result.min = @min(result.min, @min(@min(quad.corners[0], quad.corners[1]), @min(quad.corners[2], quad.corners[3])) + pos);
									result.max = @max(result.max, @max(@max(quad.corners[0], quad.corners[1]), @max(quad.corners[2], quad.corners[3])) + pos);
									result.min = @select(f64, quad.normal > @as(Vec3d, @splat(0.5)), hitBox.min, result.min);
									result.max = @select(f64, quad.normal < @as(Vec3d, @splat(-0.5)), hitBox.max, result.max);
								}
							}
						}
					}
				}
			}
		}
		result.min = @max(hitBox.min, result.min);
		result.max = @min(hitBox.max, result.max);
		result.min = @min(result.min, result.max);
		result.min -= super.pos;
		result.max -= super.pos;
		return result;
	}
	const Direction = enum {x, y, z};

	pub fn collideWithBlock(block: main.blocks.Block, x: i32, y: i32, z: i32, entityPosition: Vec3d, entityBoundingBoxExtent: Vec3d, directionVector: Vec3d) ?struct{box: Box, dist: f64} {
		var resultBox: ?Box = null;
		var minDistance: f64 = std.math.floatMax(f64);
		if(block.collide()) {
			const model = &models.models.items[block.mode().model(block)];

			const pos = Vec3d{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};

			for (model.neighborFacingQuads) |quads| {
				for (quads) |quadIndex| {
					const quad = &models.quads.items[quadIndex];
					if (triangleAABB(.{quad.corners[0] + quad.normal + pos, quad.corners[2] + quad.normal + pos, quad.corners[1] + quad.normal + pos}, entityPosition, entityBoundingBoxExtent)) {
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
					if (triangleAABB(.{quad.corners[1] + quad.normal + pos, quad.corners[2] + quad.normal + pos, quad.corners[3] + quad.normal + pos}, entityPosition, entityBoundingBoxExtent)) {
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
				if (triangleAABB(.{quad.corners[0] + pos, quad.corners[2] + pos, quad.corners[1] + pos}, entityPosition, entityBoundingBoxExtent)) {
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
				if (triangleAABB(.{quad.corners[1] + pos, quad.corners[2] + pos, quad.corners[3] + pos}, entityPosition, entityBoundingBoxExtent)) {
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
		if(resultBox) |box| return .{.box = box, .dist = minDistance}
		else return null;
	}

	pub fn collides(dir: Direction, amount: f64, hitBox: Box) ?Box {
		var boundingBox: Box = .{
			.min = super.pos + hitBox.min,
			.max = super.pos + hitBox.max,
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
		const fullBoundingBoxExtent = (boundingBox.max - boundingBox.min - @as(Vec3d, @splat(0.0001)))/@as(Vec3d, @splat(2));

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
						if(collideWithBlock(block, x, y, z, boundingBoxCenter, fullBoundingBoxExtent, directionVector)) |res| {
							if(res.dist < minDistance) {
								resultBox = res.box;
								minDistance = res.dist;
							} else if(res.dist == minDistance) {
								resultBox.?.min = @min(resultBox.?.min, res.box.min);
								resultBox.?.max = @min(resultBox.?.max, res.box.max);
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
	const inner: Box = .{
		.min = -Player.boundingBoxExtent + Vec3d{Player.boundingBoxExtent[0]/3.0, Player.boundingBoxExtent[1]/3.0, Player.boundingBoxExtent[2]/4.0 + 0.5},
		.max = Player.boundingBoxExtent - Vec3d{Player.boundingBoxExtent[0]/3.0, Player.boundingBoxExtent[1]/3.0, Player.boundingBoxExtent[2]/10.0},
	};
	const outer: Box = .{
		.min = -Player.boundingBoxExtent,
		.max = Player.boundingBoxExtent,
	};
	const gravity = 30.0;
	const terminalVelocity = 90.0;
	const airFrictionCoefficient = gravity/terminalVelocity; // λ = a/v in equillibrium
	var move: Vec3d = .{0, 0, 0};
	if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(Player.super.pos[0])), @intFromFloat(@floor(Player.super.pos[1])), @intFromFloat(@floor(Player.super.pos[2]))) != null) {		
		var acc = Vec3d{0, 0, 0};
		if (!Player.isFlying.load(.monotonic)) {
			acc[2] = -gravity;
		}
		var springConstants = Vec3d{0, 0, 0};

		var baseFrictionCoefficient: f32 = 50;
		var directionalFrictionCoefficients: Vec3f = @splat(0);
		const speedMultiplier: f32 = if(Player.hyperSpeed.load(.monotonic)) 4.0 else 1.0;

		if (!Player.onGround and !Player.isFlying.load(.monotonic)) {
			baseFrictionCoefficient = airFrictionCoefficient;
		}

		var jumping: bool = false;
		// At equillibrium we want to have dv/dt = a - λv = 0 → a = λ*v
		const fricMul = speedMultiplier*baseFrictionCoefficient;

		const forward = vec.rotateZ(Vec3d{0, 1, 0}, -camera.rotation[2]);
		const right = Vec3d{-forward[1], forward[0], 0};
		var movementDir: Vec3d = .{0, 0, 0};
		var movementSpeed: f64 = 0;
		if(main.Window.grabbed) {
			if(KeyBoard.key("forward").pressed) {
				if(KeyBoard.key("sprint").pressed) {
					if(Player.isGhost.load(.monotonic)) {
						movementSpeed = @max(movementSpeed, 128);
						movementDir += forward*@as(Vec3d, @splat(128));
					} else if(Player.isFlying.load(.monotonic)) {
						movementSpeed = @max(movementSpeed, 32);
						movementDir += forward*@as(Vec3d, @splat(32));
					} else {
						movementSpeed = @max(movementSpeed, 8);
						movementDir += forward*@as(Vec3d, @splat(8));
					}
				} else {
					movementSpeed = @max(movementSpeed, 4);
					movementDir += forward*@as(Vec3d, @splat(4));
				}
			}
			if(KeyBoard.key("backward").pressed) {
				movementSpeed = @max(movementSpeed, 4);
				movementDir += forward*@as(Vec3d, @splat(-4));
			}
			if(KeyBoard.key("left").pressed) {
				movementSpeed = @max(movementSpeed, 4);
				movementDir += right*@as(Vec3d, @splat(4));
			}
			if(KeyBoard.key("right").pressed) {
				movementSpeed = @max(movementSpeed, 4);
				movementDir += right*@as(Vec3d, @splat(-4));
			}
			if(KeyBoard.key("jump").pressed) {
				if(Player.isFlying.load(.monotonic)) {
					if(KeyBoard.key("sprint").pressed) {
						if(Player.isGhost.load(.monotonic)) {
							movementSpeed = @max(movementSpeed, 60);
							movementDir[2] += 60;
						} else {
							movementSpeed = @max(movementSpeed, 25);
							movementDir[2] += 25;
						}
					} else {
						movementSpeed = @max(movementSpeed, 5.5);
						movementDir[2] += 5.5;
					}
				} else if (Player.onGround) {
					jumping = true;
				}
			}
			if(KeyBoard.key("fall").pressed) {
				if(Player.isFlying.load(.monotonic)) {
					if(KeyBoard.key("sprint").pressed) {
						if(Player.isGhost.load(.monotonic)) {
							movementSpeed = @max(movementSpeed, 60);
							movementDir[2] -= 60;
						} else {
							movementSpeed = @max(movementSpeed, 25);
							movementDir[2] -= 25;
						}
					} else {
						movementSpeed = @max(movementSpeed, 5.5);
						movementDir[2] -= 5.5;
					}
				}
			}
			if(movementSpeed != 0 and vec.lengthSquare(movementDir) != 0) {
				movementDir = vec.normalize(movementDir);
				acc += movementDir*@as(Vec3d, @splat(movementSpeed*fricMul));
			}

			const newSlot: i32 = @as(i32, @intCast(Player.selectedSlot)) -% @as(i32, @intFromFloat(main.Window.scrollOffset));
			Player.selectedSlot = @intCast(@mod(newSlot, 12));
			main.Window.scrollOffset = 0;
		}
		var shouldStep: bool = false;
		if(!Player.isGhost.load(.monotonic)) { // Collision acceleration:
			Player.mutex.lock();
			defer Player.mutex.unlock();
			const boxes = [6] Box {
				.{
					.min = .{inner.max[0], inner.min[1], inner.min[2]},
					.max = .{outer.max[0], inner.max[1], inner.max[2]},
				},
				.{
					.min = .{outer.min[0], inner.min[1], inner.min[2]},
					.max = .{inner.min[0], inner.max[1], inner.max[2]},
				},
				.{
					.min = .{inner.min[0], inner.max[1], inner.min[2]},
					.max = .{inner.max[0], outer.max[1], inner.max[2]},
				},
				.{
					.min = .{inner.min[0], outer.min[1], inner.min[2]},
					.max = .{inner.max[0], inner.min[1], inner.max[2]},
				},
				.{
					.min = .{inner.min[0], inner.min[1], inner.max[2]},
					.max = .{inner.max[0], inner.max[1], outer.max[2]},
				},
				.{
					.min = .{inner.min[0], inner.min[1], outer.min[2]},
					.max = .{inner.max[0], inner.max[1], inner.min[2]},
				},
			};
			const forceMultipliers = [6]f64 {
				200,
				200,
				200,
				200,
				200,
				400,
			};
			const frictionMultipliers = [6]f64 {
				30,
				30,
				30,
				30,
				30,
				30,
			};
			const forceDir = [6]Vec3d {
				.{-1, 0, 0},
				.{1, 0, 0},
				.{0, -1, 0},
				.{0, 1, 0},
				.{0, 0, -1},
				.{0, 0, 1},
			};

			for(boxes, 0..) |box, i| {
				const collision = Player.collisionBox(box);
				var strength = vec.dot(@abs(forceDir[i]), collision.max - collision.min)/vec.dot(@abs(forceDir[i]), box.max - box.min);
				if(strength == 0) continue;
				if(i < 4 and vec.dot(forceDir[i], movementDir) < 0) {
					strength += vec.dot(forceDir[i], movementDir)*@sqrt(2.0); // Cling to walls
				}
				if(i == 5 and strength > 0.5) {
					shouldStep = true;
				}
				const dir = forceDir[i];
				const force = strength*forceMultipliers[i];
				const friction = frictionMultipliers[i];
				springConstants += @as(Vec3d, @splat(forceMultipliers[i]/vec.dot(@abs(forceDir[i]), box.max - box.min)))*@abs(dir);
				directionalFrictionCoefficients += @floatCast(@as(Vec3d, @splat(friction))*@abs(dir));
				acc += @as(Vec3d, @splat(force))*dir;
			}
		}

		if(shouldStep) {
			acc[2] += @sqrt(acc[0]*acc[0] + acc[1]*acc[1]);
		}

		// This our model for movement on a single frame:
		// dv/dt = a - k*x - λ·v
		// dx/dt = v
		// Where a is the acceleration, k is the spring constant and λ is the friction coefficient
		inline for(0..3) |i| {
			var frictionCoefficient = baseFrictionCoefficient + directionalFrictionCoefficients[i];
			if(i == 2 and jumping) { // No friction while jumping
				// Here we want to ensure a specified jump height under air friction.
				Player.super.vel[i] = @sqrt(Player.jumpHeight * gravity * 2);
				frictionCoefficient = airFrictionCoefficient;
			}
			const v_0 = Player.super.vel[i];
			const k = springConstants[i];
			const a = acc[i];
			if(k == 0) {
				// Here we can use a simplified model without the spring constant:
				// dv/dt = a - λ·v
				// (1 - a)/v dv = -λ dt
				// (1 - a)ln(v) + C = -λt
				// v(t) = a/λ + c_1 e^(λ (-t))
				// v(0) = a/λ + c_1 = v₀
				// c_1 = v₀ - a/λ
				// x(t) = ∫v(t) dt
				// x(t) = ∫a/λ + c_1 e^(λ (-t)) dt
				// x(t) = a/λt - c_1/λ e^(λ (-t)) + C
				// With x(0) = 0 we get C = c_1/λ
				// x(t) = a/λt - c_1/λ e^(λ (-t)) + c_1/λ
				const c_1 = v_0 - a/frictionCoefficient;
				Player.super.vel[i] = a/frictionCoefficient + c_1*@exp(-frictionCoefficient*deltaTime);
				move[i] = a/frictionCoefficient*deltaTime - c_1/frictionCoefficient*@exp(-frictionCoefficient*deltaTime) + c_1/frictionCoefficient;
			} else {
				// here we need to solve the full equation:
				// The solution of this differential equation is given by
				// x(t) = a/k + c_1 e^(1/2 t (-c_3 - λ)) + c_2 e^(1/2 t (c_3 - λ))
				// With c_3 = sqrt(λ^2 - 4 k) which can be imaginary
				// v(t) is just the derivative, given by
				// v(t) = 1/2 (-c_3 - λ) c_1 e^(1/2 t (-c_3 - λ)) + (1/2 (c_3 - λ)) c_2 e^(1/2 t (c_3 - λ))
				// Now for simplicity we set x(0) = 0 and v(0) = v₀
				// a/k + c_1 + c_2 = 0 → c_1 = -a/k - c_2
				// (-c_3 - λ) c_1 + (c_3 - λ) c_2 = 2v₀
				// → (-c_3 - λ) (-a/k - c_2) + (c_3 - λ) c_2 = 2v₀
				// → (-c_3 - λ) (-a/k) - (-c_3 - λ)c_2 + (c_3 - λ) c_2 = 2v₀
				// → ((c_3 - λ) - (-c_3 - λ))c_2 = 2v₀ - (c_3 + λ) (a/k)
				// → (c_3 - λ + c_3 + λ)c_2 = 2v₀ - (c_3 + λ) (a/k)
				// → 2 c_3 c_2 = 2v₀ - (c_3 + λ) (a/k)
				// → c_2 = (2v₀ - (c_3 + λ) (a/k))/(2 c_3)
				// → c_2 = v₀/c_3 - (1 + λ/c_3)/2 (a/k)
				// In total we get:
				// c_3 = sqrt(λ^2 - 4 k)
				// c_2 = (2v₀ - (c_3 + λ) (a/k))/(2 c_3)
				// c_1 = -a/k - c_2
				const c_3 = vec.Complex.fromSqrt(frictionCoefficient*frictionCoefficient - 4*k);
				const c_2 = (((c_3.addScalar(frictionCoefficient).mulScalar(-a/k)).addScalar(2*v_0)).div(c_3.mulScalar(2)));
				const c_1 = c_2.addScalar(a/k).negate();
				// v(t) = 1/2 (-c_3 - λ) c_1 e^(1/2 t (-c_3 - λ)) + (1/2 (c_3 - λ)) c_2 e^(1/2 t (c_3 - λ))
				// x(t) = a/k + c_1 e^(1/2 t (-c_3 - λ)) + c_2 e^(1/2 t (c_3 - λ))
				const firstTerm = c_1.mul((c_3.negate().subScalar(frictionCoefficient)).mulScalar(deltaTime/2).exp());
				const secondTerm = c_2.mul((c_3.subScalar(frictionCoefficient)).mulScalar(deltaTime/2).exp());
				Player.super.vel[i] = firstTerm.mul(c_3.negate().subScalar(frictionCoefficient).mulScalar(0.5)).add(secondTerm.mul((c_3.subScalar(frictionCoefficient)).mulScalar(0.5))).val[0];
				move[i] = firstTerm.add(secondTerm).addScalar(a/k).val[0];
			}
		}

		Player.onGround = acc[2] >= -1;
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
		const hitBox = inner;

		if (Player.collides(.x, -move[0], hitBox)) |box| {
			if (move[0] < 0) {
				Player.super.pos[0] = box.max[0] - hitBox.min[0];
				while (Player.collides(.x, 0, hitBox)) |_| {
					Player.super.pos[0] += 1;
				}
			} else {
				Player.super.pos[0] = box.min[0] - hitBox.max[0];
				while (Player.collides(.x, 0, hitBox)) |_| {
					Player.super.pos[0] -= 1;
				}
			}
			Player.super.vel[0] = 0;
		}

		Player.super.pos[1] += move[1];
		if (Player.collides(.y, -move[1], hitBox)) |box| {
			if (move[1] < 0) {
				Player.super.pos[1] = box.max[1] - hitBox.min[1];
				while (Player.collides(.y, 0, hitBox)) |_| {
					Player.super.pos[1] += 1;
				}
			} else {
				Player.super.pos[1] = box.min[1] - hitBox.max[1];
				while (Player.collides(.y, 0, hitBox)) |_| {
					Player.super.pos[1] -= 1;
				}
			}
			Player.super.vel[1] = 0;
		}

		Player.super.pos[2] += move[2];
		if (Player.collides(.z, -move[2], hitBox)) |box| {
			if (move[2] < 0) {
				Player.super.pos[2] = box.max[2] - hitBox.min[2];
				while (Player.collides(.z, 0, hitBox)) |_| {
					Player.super.pos[2] += 1;
				}
			} else {
				Player.super.pos[2] = box.min[2] - hitBox.max[2];
				while (Player.collides(.z, 0, hitBox)) |_| {
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