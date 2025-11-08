const std = @import("std");
const Atomic = std.atomic.Value;

const assets = @import("assets.zig");
const itemdrop = @import("itemdrop.zig");
const ClientItemDropManager = itemdrop.ClientItemDropManager;
const items = @import("items.zig");
const Inventory = items.Inventory;
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main");
const network = @import("network.zig");
const particles = @import("particles.zig");
const Connection = network.Connection;
const ConnectionManager = network.ConnectionManager;
const vec = @import("vec.zig");
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;
const graphics = @import("graphics.zig");
const Fog = graphics.Fog;
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const Block = main.blocks.Block;
const physics = main.physics;
const KeyBoard = main.KeyBoard;

pub const camera = struct { // MARK: camera
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

pub const collision = struct {
	pub const Box = struct {
		min: Vec3d,
		max: Vec3d,

		pub fn center(self: Box) Vec3d {
			return (self.min + self.max)*@as(Vec3d, @splat(0.5));
		}

		pub fn extent(self: Box) Vec3d {
			return (self.max - self.min)*@as(Vec3d, @splat(0.5));
		}

		pub fn intersects(self: Box, other: Box) bool {
			return @reduce(.And, (self.max > other.min)) and @reduce(.And, (self.min < other.max));
		}
	};

	const Direction = enum(u2) {x = 0, y = 1, z = 2};

	pub fn collideWithBlock(block: main.blocks.Block, x: i32, y: i32, z: i32, entityPosition: Vec3d, entityBoundingBoxExtent: Vec3d, directionVector: Vec3d) ?struct {box: Box, dist: f64} {
		var resultBox: ?Box = null;
		var minDistance: f64 = std.math.floatMax(f64);
		if(block.collide()) {
			const model = block.mode().model(block).model();

			const pos = Vec3d{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};
			const entityCollision = Box{.min = entityPosition - entityBoundingBoxExtent, .max = entityPosition + entityBoundingBoxExtent};

			for(model.collision) |relativeBlockCollision| {
				const blockCollision = Box{.min = relativeBlockCollision.min + pos, .max = relativeBlockCollision.max + pos};
				if(blockCollision.intersects(entityCollision)) {
					const dotMin = vec.dot(directionVector, blockCollision.min);
					const dotMax = vec.dot(directionVector, blockCollision.max);

					const distance = @min(dotMin, dotMax);

					if(distance < minDistance) {
						resultBox = blockCollision;
						minDistance = distance;
					} else if(distance == minDistance) {
						resultBox = .{.min = @min(resultBox.?.min, blockCollision.min), .max = @max(resultBox.?.max, blockCollision.max)};
					}
				}
			}
		}
		return .{.box = resultBox orelse return null, .dist = minDistance};
	}

	pub fn collides(comptime side: main.utils.Side, dir: Direction, amount: f64, pos: Vec3d, hitBox: Box) ?Box {
		var boundingBox: Box = .{
			.min = pos + hitBox.min,
			.max = pos + hitBox.max,
		};
		switch(dir) {
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
		const maxX: i32 = @intFromFloat(@floor(boundingBox.max[0]));
		const minY: i32 = @intFromFloat(@floor(boundingBox.min[1]));
		const maxY: i32 = @intFromFloat(@floor(boundingBox.max[1]));
		const minZ: i32 = @intFromFloat(@floor(boundingBox.min[2]));
		const maxZ: i32 = @intFromFloat(@floor(boundingBox.max[2]));

		const boundingBoxCenter = boundingBox.center();
		const fullBoundingBoxExtent = boundingBox.extent();

		var resultBox: ?Box = null;
		var minDistance: f64 = std.math.floatMax(f64);
		const directionVector: Vec3d = switch(dir) {
			.x => .{-std.math.sign(amount), 0, 0},
			.y => .{0, -std.math.sign(amount), 0},
			.z => .{0, 0, -std.math.sign(amount)},
		};

		var x: i32 = minX;
		while(x <= maxX) : (x += 1) {
			var y: i32 = minY;
			while(y <= maxY) : (y += 1) {
				var z: i32 = maxZ;
				while(z >= minZ) : (z -= 1) {
					const _block = if(side == .client) main.renderer.mesh_storage.getBlockFromRenderThread(x, y, z) else main.server.world.?.getBlock(x, y, z);
					if(_block) |block| {
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

	const SurfaceProperties = struct {
		friction: f32,
		bounciness: f32,
	};

	pub fn calculateSurfaceProperties(comptime side: main.utils.Side, pos: Vec3d, hitBox: Box, defaultFriction: f32) SurfaceProperties {
		const boundingBox: Box = .{
			.min = pos + hitBox.min,
			.max = pos + hitBox.max,
		};
		const minX: i32 = @intFromFloat(@floor(boundingBox.min[0]));
		const maxX: i32 = @intFromFloat(@floor(boundingBox.max[0]));
		const minY: i32 = @intFromFloat(@floor(boundingBox.min[1]));
		const maxY: i32 = @intFromFloat(@floor(boundingBox.max[1]));

		const z: i32 = @intFromFloat(@floor(boundingBox.min[2] - 0.01));

		var friction: f64 = 0;
		var bounciness: f64 = 0;
		var totalArea: f64 = 0;

		var x = minX;
		while(x <= maxX) : (x += 1) {
			var y = minY;
			while(y <= maxY) : (y += 1) {
				const _block = if(side == .client) main.renderer.mesh_storage.getBlockFromRenderThread(x, y, z) else main.server.world.?.getBlock(x, y, z);

				if(_block) |block| {
					const blockPos: Vec3d = .{@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)};

					const blockBox: Box = .{
						.min = blockPos + @as(Vec3d, @floatCast(block.mode().model(block).model().min)),
						.max = blockPos + @as(Vec3d, @floatCast(block.mode().model(block).model().max)),
					};

					if(boundingBox.min[2] > blockBox.max[2] or boundingBox.max[2] < blockBox.min[2]) {
						continue;
					}

					const max = std.math.clamp(vec.xy(blockBox.max), vec.xy(boundingBox.min), vec.xy(boundingBox.max));
					const min = std.math.clamp(vec.xy(blockBox.min), vec.xy(boundingBox.min), vec.xy(boundingBox.max));

					const area = (max[0] - min[0])*(max[1] - min[1]);

					if(block.collide()) {
						totalArea += area;
						friction += area*@as(f64, @floatCast(block.friction()));
						bounciness += area*@as(f64, @floatCast(block.bounciness()));
					}
				}
			}
		}

		if(totalArea == 0) {
			friction = defaultFriction;
			bounciness = 0.0;
		} else {
			friction = friction/totalArea;
			bounciness = bounciness/totalArea;
		}

		return .{
			.friction = @floatCast(friction),
			.bounciness = @floatCast(bounciness),
		};
	}

	const VolumeProperties = struct {
		terminalVelocity: f64,
		density: f64,
		maxDensity: f64,
		mobility: f64,
	};

	fn overlapVolume(a: Box, b: Box) f64 {
		const min = @max(a.min, b.min);
		const max = @min(a.max, b.max);
		if(@reduce(.Or, min >= max)) return 0;
		return @reduce(.Mul, max - min);
	}

	pub fn calculateVolumeProperties(comptime side: main.utils.Side, pos: Vec3d, hitBox: Box, defaults: VolumeProperties) VolumeProperties {
		const boundingBox: Box = .{
			.min = pos + hitBox.min,
			.max = pos + hitBox.max,
		};
		const minX: i32 = @intFromFloat(@floor(boundingBox.min[0]));
		const maxX: i32 = @intFromFloat(@floor(boundingBox.max[0]));
		const minY: i32 = @intFromFloat(@floor(boundingBox.min[1]));
		const maxY: i32 = @intFromFloat(@floor(boundingBox.max[1]));
		const minZ: i32 = @intFromFloat(@floor(boundingBox.min[2]));
		const maxZ: i32 = @intFromFloat(@floor(boundingBox.max[2]));

		var invTerminalVelocitySum: f64 = 0;
		var densitySum: f64 = 0;
		var maxDensity: f64 = defaults.maxDensity;
		var mobilitySum: f64 = 0;
		var volumeSum: f64 = 0;

		var x: i32 = minX;
		while(x <= maxX) : (x += 1) {
			var y: i32 = minY;
			while(y <= maxY) : (y += 1) {
				var z: i32 = maxZ;
				while(z >= minZ) : (z -= 1) {
					const _block = if(side == .client) main.renderer.mesh_storage.getBlockFromRenderThread(x, y, z) else main.server.world.?.getBlock(x, y, z);
					const totalBox: Box = .{
						.min = @floatFromInt(Vec3i{x, y, z}),
						.max = @floatFromInt(Vec3i{x + 1, y + 1, z + 1}),
					};
					const gridVolume = overlapVolume(boundingBox, totalBox);
					volumeSum += gridVolume;

					if(_block) |block| {
						const collisionBox: Box = .{ // TODO: Check all AABBs individually
							.min = totalBox.min + main.blocks.meshes.model(block).model().min,
							.max = totalBox.min + main.blocks.meshes.model(block).model().max,
						};
						const filledVolume = @min(gridVolume, overlapVolume(collisionBox, totalBox));
						const emptyVolume = gridVolume - filledVolume;
						invTerminalVelocitySum += emptyVolume/defaults.terminalVelocity;
						densitySum += emptyVolume*defaults.density;
						mobilitySum += emptyVolume*defaults.mobility;
						invTerminalVelocitySum += filledVolume/block.terminalVelocity();
						densitySum += filledVolume*block.density();
						maxDensity = @max(maxDensity, block.density());
						mobilitySum += filledVolume*block.mobility();
					} else {
						invTerminalVelocitySum += gridVolume/defaults.terminalVelocity;
						densitySum += gridVolume*defaults.density;
						mobilitySum += gridVolume*defaults.mobility;
					}
				}
			}
		}

		return .{
			.terminalVelocity = volumeSum/invTerminalVelocitySum,
			.density = densitySum/volumeSum,
			.maxDensity = maxDensity,
			.mobility = mobilitySum/volumeSum,
		};
	}

	pub fn collideOrStep(comptime side: main.utils.Side, comptime dir: Direction, amount: f64, pos: Vec3d, hitBox: Box, steppingHeight: f64) Vec3d {
		const index = @intFromEnum(dir);

		// First argument is amount we end up moving in dir, second argument is how far up we step
		var resultingMovement: Vec3d = .{0, 0, 0};
		resultingMovement[index] = amount;
		var checkPos = pos;
		checkPos[index] += amount;

		if(collision.collides(side, dir, -amount, checkPos, hitBox)) |box| {
			const newFloor = box.max[2] + hitBox.max[2];
			const heightDifference = newFloor - checkPos[2];
			if(heightDifference <= steppingHeight) {
				// If we collide but might be able to step up
				checkPos[2] = newFloor;
				if(collision.collides(side, dir, -amount, checkPos, hitBox) == null) {
					// If there's no new collision then we can execute the step-up
					resultingMovement[2] = heightDifference;
					return resultingMovement;
				}
			}

			// Otherwise move as close to the container as possible
			if(amount < 0) {
				resultingMovement[index] = box.max[index] - hitBox.min[index] - pos[index];
			} else {
				resultingMovement[index] = box.min[index] - hitBox.max[index] - pos[index];
			}
		}

		return resultingMovement;
	}

	fn isBlockIntersecting(block: Block, posX: i32, posY: i32, posZ: i32, center: Vec3d, extent: Vec3d) bool {
		const model = block.mode().model(block).model();
		const position = Vec3d{@floatFromInt(posX), @floatFromInt(posY), @floatFromInt(posZ)};
		const entityBox = Box{.min = center - extent, .max = center + extent};
		for(model.collision) |relativeBlockCollision| {
			const blockBox = Box{.min = position + relativeBlockCollision.min, .max = position + relativeBlockCollision.max};
			if(blockBox.intersects(entityBox)) {
				return true;
			}
		}

		return false;
	}

	pub fn touchBlocks(entity: main.server.Entity, hitBox: Box, side: main.utils.Side) void {
		const boundingBox: Box = .{.min = entity.pos + hitBox.min, .max = entity.pos + hitBox.max};

		const minX: i32 = @intFromFloat(@floor(boundingBox.min[0] - 0.01));
		const maxX: i32 = @intFromFloat(@floor(boundingBox.max[0] + 0.01));
		const minY: i32 = @intFromFloat(@floor(boundingBox.min[1] - 0.01));
		const maxY: i32 = @intFromFloat(@floor(boundingBox.max[1] + 0.01));
		const minZ: i32 = @intFromFloat(@floor(boundingBox.min[2] - 0.01));
		const maxZ: i32 = @intFromFloat(@floor(boundingBox.max[2] + 0.01));

		const center: Vec3d = boundingBox.center();
		const extent: Vec3d = boundingBox.extent();

		const extentX: Vec3d = extent + Vec3d{0.01, -0.01, -0.01};
		const extentY: Vec3d = extent + Vec3d{-0.01, 0.01, -0.01};
		const extentZ: Vec3d = extent + Vec3d{-0.01, -0.01, 0.01};

		var posX: i32 = minX;
		while(posX <= maxX) : (posX += 1) {
			var posY: i32 = minY;
			while(posY <= maxY) : (posY += 1) {
				var posZ: i32 = minZ;
				while(posZ <= maxZ) : (posZ += 1) {
					const block: ?Block =
						if(side == .client) main.renderer.mesh_storage.getBlockFromRenderThread(posX, posY, posZ) else main.server.world.?.getBlock(posX, posY, posZ);
					if(block == null or block.?.touchFunction() == null)
						continue;
					const touchX: bool = isBlockIntersecting(block.?, posX, posY, posZ, center, extentX);
					const touchY: bool = isBlockIntersecting(block.?, posX, posY, posZ, center, extentY);
					const touchZ: bool = isBlockIntersecting(block.?, posX, posY, posZ, center, extentZ);
					if(touchX or touchY or touchZ)
						block.?.touchFunction().?(block.?, entity, posX, posY, posZ, touchX and touchY and touchZ);
				}
			}
		}
	}
};

pub const Gamemode = enum(u8) {survival = 0, creative = 1};

pub const DamageType = enum(u8) {
	heal = 0, // For when you are adding health
	kill = 1,
	fall = 2,

	pub fn sendMessage(self: DamageType, name: []const u8) void {
		switch(self) {
			.heal => main.server.sendMessage("{s}§#ffffff was healed", .{name}),
			.kill => main.server.sendMessage("{s}§#ffffff was killed", .{name}),
			.fall => main.server.sendMessage("{s}§#ffffff died of fall damage", .{name}),
		}
	}
};

pub const Player = struct { // MARK: Player
	pub var super: main.server.Entity = .{};
	pub var eyePos: Vec3d = .{0, 0, 0};
	pub var eyeVel: Vec3d = .{0, 0, 0};
	pub var eyeCoyote: f64 = 0;
	pub var eyeStep: @Vector(3, bool) = .{false, false, false};
	pub var crouching: bool = false;
	pub var id: u32 = 0;
	pub var gamemode: Atomic(Gamemode) = .init(.creative);
	pub var isFlying: Atomic(bool) = .init(false);
	pub var isGhost: Atomic(bool) = .init(false);
	pub var hyperSpeed: Atomic(bool) = .init(false);
	pub var mutex: std.Thread.Mutex = .{};
	pub const inventorySize = 32;
	pub var inventory: Inventory = undefined;
	pub var selectedSlot: u32 = 0;

	pub var selectionPosition1: ?Vec3i = null;
	pub var selectionPosition2: ?Vec3i = null;

	pub var currentFriction: f32 = 0;
	pub var volumeProperties: collision.VolumeProperties = .{.density = 0, .maxDensity = 0, .mobility = 0, .terminalVelocity = 0};

	pub var onGround: bool = false;
	pub var jumpCooldown: f64 = 0;
	pub var jumpCoyote: f64 = 0;
	pub const jumpCooldownConstant = 0.3;
	pub const jumpCoyoteTimeConstant = 0.100;

	pub const standingBoundingBoxExtent: Vec3d = .{0.3, 0.3, 0.9};
	pub const crouchingBoundingBoxExtent: Vec3d = .{0.3, 0.3, 0.725};
	pub var crouchPerc: f32 = 0;

	pub var outerBoundingBoxExtent: Vec3d = standingBoundingBoxExtent;
	pub var outerBoundingBox: collision.Box = .{
		.min = -standingBoundingBoxExtent,
		.max = standingBoundingBoxExtent,
	};
	pub var eyeBox: collision.Box = .{
		.min = -Vec3d{standingBoundingBoxExtent[0]*0.2, standingBoundingBoxExtent[1]*0.2, 0.6},
		.max = Vec3d{standingBoundingBoxExtent[0]*0.2, standingBoundingBoxExtent[1]*0.2, 0.9 - 0.05},
	};
	pub var desiredEyePos: Vec3d = .{0, 0, 1.7 - standingBoundingBoxExtent[2]};
	pub const jumpHeight = 1.25;

	fn loadFrom(zon: ZonElement) void {
		super.loadFrom(zon);
		inventory.loadFromZon(zon.getChild("inventory"));
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

	pub fn getEyePosBlocking() Vec3d {
		mutex.lock();
		defer mutex.unlock();
		return eyePos + super.pos + desiredEyePos;
	}

	pub fn getEyeVelBlocking() Vec3d {
		mutex.lock();
		defer mutex.unlock();
		return eyeVel;
	}

	pub fn getEyeCoyoteBlocking() f64 {
		mutex.lock();
		defer mutex.unlock();
		return eyeCoyote;
	}

	pub fn getJumpCoyoteBlocking() f64 {
		mutex.lock();
		defer mutex.unlock();
		return jumpCoyote;
	}

	pub fn setGamemode(newGamemode: Gamemode) void {
		gamemode.store(newGamemode, .monotonic);

		if(newGamemode != .creative) {
			isFlying.store(false, .monotonic);
			isGhost.store(false, .monotonic);
			hyperSpeed.store(false, .monotonic);
		}
	}

	pub fn isCreative() bool {
		return gamemode.load(.monotonic) == .creative;
	}

	pub fn isActuallyFlying() bool {
		return isFlying.load(.monotonic) and !isGhost.load(.monotonic);
	}

	pub fn steppingHeight() Vec3d {
		if(onGround) {
			return .{0, 0, 0.6};
		} else {
			return .{0, 0, 0.1};
		}
	}

	pub fn placeBlock() void {
		if(main.renderer.MeshSelection.selectedBlockPos) |blockPos| {
			if(!main.KeyBoard.key("shift").pressed) {
				if(main.renderer.mesh_storage.triggerOnInteractBlockFromRenderThread(blockPos[0], blockPos[1], blockPos[2]) == .handled) return;
			}
			const block = main.renderer.mesh_storage.getBlockFromRenderThread(blockPos[0], blockPos[1], blockPos[2]) orelse main.blocks.Block{.typ = 0, .data = 0};
			const gui = block.gui();
			if(gui.len != 0 and !main.KeyBoard.key("shift").pressed) {
				main.gui.openWindow(gui);
				main.Window.setMouseGrabbed(false);
				return;
			}
		}

		inventory.placeBlock(selectedSlot);
	}

	pub fn kill() void {
		Player.super.pos = world.?.spawn;
		Player.super.vel = .{0, 0, 0};

		Player.super.health = Player.super.maxHealth;
		Player.super.energy = Player.super.maxEnergy;

		Player.eyePos = .{0, 0, 0};
		Player.eyeVel = .{0, 0, 0};
		Player.eyeCoyote = 0;
		Player.jumpCoyote = 0;
		Player.eyeStep = .{false, false, false};
	}

	pub fn breakBlock(deltaTime: f64) void {
		inventory.breakBlock(selectedSlot, deltaTime);
	}

	pub fn acquireSelectedBlock() void {
		if(main.renderer.MeshSelection.selectedBlockPos) |selectedPos| {
			const block = main.renderer.mesh_storage.getBlockFromRenderThread(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;

			const item: items.Item = for(0..items.itemListSize) |idx| {
				const baseItem: main.items.BaseItemIndex = @enumFromInt(idx);
				if(baseItem.block() == block.typ) {
					break .{.baseItem = baseItem};
				}
			} else return;

			// Check if there is already a slot with that item type
			for(0..12) |slotIdx| {
				if(std.meta.eql(inventory.getItem(slotIdx), item)) {
					if(isCreative()) {
						inventory.fillFromCreative(@intCast(slotIdx), item);
					}
					selectedSlot = @intCast(slotIdx);
					return;
				}
			}

			if(isCreative()) {
				const targetSlot = blk: {
					if(inventory.getItem(selectedSlot) == null) break :blk selectedSlot;
					// Look for an empty slot
					for(0..12) |slotIdx| {
						if(inventory.getItem(slotIdx) == null) {
							break :blk slotIdx;
						}
					}
					break :blk selectedSlot;
				};

				inventory.fillFromCreative(@intCast(targetSlot), item);
				selectedSlot = @intCast(targetSlot);
			}
		}
	}
};

pub const World = struct { // MARK: World
	pub const dayCycle: u63 = 12000; // Length of one in-game day in 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes

	conn: *Connection,
	manager: *ConnectionManager,
	ambientLight: f32 = 0,
	name: []const u8,
	milliTime: i64,
	gameTime: Atomic(i64) = .init(0),
	spawn: Vec3f = undefined,
	connected: bool = true,
	blockPalette: *assets.Palette = undefined,
	itemPalette: *assets.Palette = undefined,
	toolPalette: *assets.Palette = undefined,
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
		errdefer self.conn.deinit();

		self.itemDrops.init(main.globalAllocator);
		errdefer self.itemDrops.deinit();
		try network.Protocols.handShake.clientSide(self.conn, settings.playerName);

		main.Window.setMouseGrabbed(true);

		main.blocks.meshes.generateTextureArray();
		main.particles.ParticleManager.generateTextureArray();
		main.models.uploadModels();
	}

	pub fn deinit(self: *World) void {
		self.conn.deinit();

		self.connected = false;

		// TODO: Close all world related guis.
		main.gui.inventory.deinit();
		main.gui.deinit();
		main.gui.init();
		Player.inventory.deinit(main.globalAllocator);
		main.items.clearRecipeCachedInventories();
		main.items.Inventory.Sync.ClientSide.reset();

		main.threadPool.clear();
		main.entity.ClientEntityManager.clear();
		self.itemDrops.deinit();
		self.blockPalette.deinit();
		self.itemPalette.deinit();
		self.toolPalette.deinit();
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
	}

	pub fn finishHandshake(self: *World, zon: ZonElement) !void {
		// TODO: Consider using a per-world allocator.
		self.blockPalette = try assets.Palette.init(main.globalAllocator, zon.getChild("blockPalette"), "cubyz:air");
		errdefer self.blockPalette.deinit();
		self.biomePalette = try assets.Palette.init(main.globalAllocator, zon.getChild("biomePalette"), null);
		errdefer self.biomePalette.deinit();
		self.itemPalette = try assets.Palette.init(main.globalAllocator, zon.getChild("itemPalette"), null);
		errdefer self.itemPalette.deinit();
		self.toolPalette = try assets.Palette.init(main.globalAllocator, zon.getChild("toolPalette"), null);
		errdefer self.toolPalette.deinit();
		self.spawn = zon.get(Vec3f, "spawn", .{0, 0, 0});

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/serverAssets", .{main.files.cubyzDirStr()}) catch unreachable;
		defer main.stackAllocator.free(path);
		try assets.loadWorldAssets(path, self.blockPalette, self.itemPalette, self.toolPalette, self.biomePalette);
		Player.id = zon.get(u32, "player_id", std.math.maxInt(u32));
		Player.inventory = Inventory.init(main.globalAllocator, Player.inventorySize, .normal, .{.playerInventory = Player.id}, .{});
		Player.loadFrom(zon.getChild("player"));
		self.playerBiome = .init(main.server.terrain.biomes.getPlaceholderBiome());
		main.audio.setMusic(self.playerBiome.raw.preferredMusic);
	}

	fn dayNightLightFactor(gameTime: i64) struct {f32, Vec3f} {
		const dayTime = @abs(@mod(gameTime, dayCycle) - dayCycle/2);
		if(dayTime < dayCycle/4 - dayCycle/16) {
			return .{0.1, @splat(0)};
		}
		if(dayTime > dayCycle/4 + dayCycle/16) {
			return .{1, @splat(1)};
		}
		var skyColorFactor: Vec3f = undefined;
		// b:
		if(dayTime > dayCycle/4) {
			skyColorFactor[2] = @as(f32, @floatFromInt(dayTime - dayCycle/4))/@as(f32, @floatFromInt(dayCycle/16));
		} else {
			skyColorFactor[2] = 0;
		}
		// g:
		if(dayTime > dayCycle/4 + dayCycle/32) {
			skyColorFactor[1] = 1;
		} else if(dayTime > dayCycle/4 - dayCycle/32) {
			skyColorFactor[1] = 1 - @as(f32, @floatFromInt(dayCycle/4 + dayCycle/32 - dayTime))/@as(f32, @floatFromInt(dayCycle/16));
		} else {
			skyColorFactor[1] = 0;
		}
		// r:
		if(dayTime > dayCycle/4) {
			skyColorFactor[0] = 1;
		} else {
			skyColorFactor[0] = 1 - @as(f32, @floatFromInt(dayCycle/4 - dayTime))/@as(f32, @floatFromInt(dayCycle/16));
		}

		const ambientLight = 0.1 + 0.9*@as(f32, @floatFromInt(dayTime - (dayCycle/4 - dayCycle/16)))/@as(f32, @floatFromInt(dayCycle/8));
		return .{ambientLight, skyColorFactor};
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
			self.ambientLight, const skyColorFactor = dayNightLightFactor(self.gameTime.load(.unordered));
			fog.fogColor = biomeFog.fogColor*skyColorFactor;
			fog.skyColor = biomeFog.skyColor*skyColorFactor;
			fog.density = biomeFog.density;
			fog.fogLower = biomeFog.fogLower;
			fog.fogHigher = biomeFog.fogHigher;
		}
		network.Protocols.playerPosition.send(self.conn, Player.getPosBlocking(), Player.getVelBlocking(), @intCast(newTime & 65535));
	}
};
pub var testWorld: World = undefined; // TODO:
pub var world: ?*World = null;

pub var projectionMatrix: Mat4f = Mat4f.identity();

var biomeFog = Fog{.skyColor = .{0.8, 0.8, 1}, .fogColor = .{0.8, 0.8, 1}, .density = 1.0/15.0/128.0, .fogLower = 100, .fogHigher = 1000};
pub var fog = Fog{.skyColor = .{0.8, 0.8, 1}, .fogColor = .{0.8, 0.8, 1}, .density = 1.0/15.0/128.0, .fogLower = 100, .fogHigher = 1000};

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
	Player.breakBlock(0);
}

pub fn releaseBreak() void {
	nextBlockBreakTime = null;
}

pub fn pressAcquireSelectedBlock() void {
	Player.acquireSelectedBlock();
}

pub fn flyToggle() void {
	if(!Player.isCreative()) return;

	const newIsFlying = !Player.isActuallyFlying();

	Player.isFlying.store(newIsFlying, .monotonic);
	Player.isGhost.store(false, .monotonic);
}

pub fn ghostToggle() void {
	if(!Player.isCreative()) return;

	const newIsGhost = !Player.isGhost.load(.monotonic);

	Player.isGhost.store(newIsGhost, .monotonic);
	Player.isFlying.store(newIsGhost, .monotonic);
}

pub fn hyperSpeedToggle() void {
	if(!Player.isCreative()) return;

	Player.hyperSpeed.store(!Player.hyperSpeed.load(.monotonic), .monotonic);
}

pub fn update(deltaTime: f64) void { // MARK: update()
	physics.calculateProperties();
	var acc = Vec3d{0, 0, 0};
	const speedMultiplier: f32 = if(Player.hyperSpeed.load(.monotonic)) 4.0 else 1.0;

	const mobility = if(Player.isFlying.load(.monotonic)) 1.0 else Player.volumeProperties.mobility;
	const density = if(Player.isFlying.load(.monotonic)) 0.0 else Player.volumeProperties.density;
	const maxDensity = if(Player.isFlying.load(.monotonic)) 0.0 else Player.volumeProperties.maxDensity;

	const baseFrictionCoefficient: f32 = Player.currentFriction;
	var jumping = false;
	Player.jumpCooldown -= deltaTime;
	// At equillibrium we want to have dv/dt = a - λv = 0 → a = λ*v
	const fricMul = speedMultiplier*baseFrictionCoefficient*if(Player.isFlying.load(.monotonic)) 1.0 else mobility;

	const horizontalForward = vec.rotateZ(Vec3d{0, 1, 0}, -camera.rotation[2]);
	const forward = vec.normalize(std.math.lerp(horizontalForward, camera.direction, @as(Vec3d, @splat(density/@max(1.0, maxDensity)))));
	const right = Vec3d{-horizontalForward[1], horizontalForward[0], 0};
	var movementDir: Vec3d = .{0, 0, 0};
	var movementSpeed: f64 = 0;

	if(main.Window.grabbed) {
		const walkingSpeed: f64 = if(Player.crouching) 2 else 4;
		if(KeyBoard.key("forward").value > 0.0) {
			if(KeyBoard.key("sprint").pressed and !Player.crouching) {
				if(Player.isGhost.load(.monotonic)) {
					movementSpeed = @max(movementSpeed, 128)*KeyBoard.key("forward").value;
					movementDir += forward*@as(Vec3d, @splat(128*KeyBoard.key("forward").value));
				} else if(Player.isFlying.load(.monotonic)) {
					movementSpeed = @max(movementSpeed, 32)*KeyBoard.key("forward").value;
					movementDir += forward*@as(Vec3d, @splat(32*KeyBoard.key("forward").value));
				} else {
					movementSpeed = @max(movementSpeed, 8)*KeyBoard.key("forward").value;
					movementDir += forward*@as(Vec3d, @splat(8*KeyBoard.key("forward").value));
				}
			} else {
				movementSpeed = @max(movementSpeed, walkingSpeed)*KeyBoard.key("forward").value;
				movementDir += forward*@as(Vec3d, @splat(walkingSpeed*KeyBoard.key("forward").value));
			}
		}
		if(KeyBoard.key("backward").value > 0.0) {
			movementSpeed = @max(movementSpeed, walkingSpeed)*KeyBoard.key("backward").value;
			movementDir += forward*@as(Vec3d, @splat(-walkingSpeed*KeyBoard.key("backward").value));
		}
		if(KeyBoard.key("left").value > 0.0) {
			movementSpeed = @max(movementSpeed, walkingSpeed)*KeyBoard.key("left").value;
			movementDir += right*@as(Vec3d, @splat(walkingSpeed*KeyBoard.key("left").value));
		}
		if(KeyBoard.key("right").value > 0.0) {
			movementSpeed = @max(movementSpeed, walkingSpeed)*KeyBoard.key("right").value;
			movementDir += right*@as(Vec3d, @splat(-walkingSpeed*KeyBoard.key("right").value));
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
			} else if((Player.onGround or Player.jumpCoyote > 0.0) and Player.jumpCooldown <= 0) {
				jumping = true;
				Player.jumpCooldown = Player.jumpCooldownConstant;
				if(!Player.onGround) {
					Player.eyeCoyote = 0;
				}
				Player.jumpCoyote = 0;
			} else if(!KeyBoard.key("fall").pressed) {
				movementSpeed = @max(movementSpeed, walkingSpeed);
				movementDir[2] += walkingSpeed;
			}
		} else {
			Player.jumpCooldown = 0;
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
			} else if(!KeyBoard.key("jump").pressed) {
				movementSpeed = @max(movementSpeed, walkingSpeed);
				movementDir[2] -= walkingSpeed;
			}
		}

		if(movementSpeed != 0 and vec.lengthSquare(movementDir) != 0) {
			if(vec.lengthSquare(movementDir) > movementSpeed*movementSpeed) {
				movementDir = vec.normalize(movementDir);
			} else {
				movementDir /= @splat(movementSpeed);
			}
			acc += movementDir*@as(Vec3d, @splat(movementSpeed*fricMul));
		}

		const newSlot: i32 = @as(i32, @intCast(Player.selectedSlot)) -% @as(i32, @intFromFloat(main.Window.scrollOffset));
		Player.selectedSlot = @intCast(@mod(newSlot, 12));
		main.Window.scrollOffset = 0;

		const newPos = Vec2f{
			@floatCast(main.KeyBoard.key("cameraRight").value - main.KeyBoard.key("cameraLeft").value),
			@floatCast(main.KeyBoard.key("cameraDown").value - main.KeyBoard.key("cameraUp").value),
		}*@as(Vec2f, @splat(3.14*settings.controllerSensitivity));
		main.game.camera.moveRotation(newPos[0]/64.0, newPos[1]/64.0);
	}

	Player.crouching = KeyBoard.key("crouch").pressed and !Player.isFlying.load(.monotonic);

	if(collision.collides(.client, .x, 0, Player.super.pos + Player.standingBoundingBoxExtent - Player.crouchingBoundingBoxExtent, .{
		.min = -Player.standingBoundingBoxExtent,
		.max = Player.standingBoundingBoxExtent,
	}) == null) {
		if(Player.onGround) {
			if(Player.crouching) {
				Player.crouchPerc += @floatCast(deltaTime*10);
			} else {
				Player.crouchPerc -= @floatCast(deltaTime*10);
			}
			Player.crouchPerc = std.math.clamp(Player.crouchPerc, 0, 1);
		}

		const smoothPerc = Player.crouchPerc*Player.crouchPerc*(3 - 2*Player.crouchPerc);

		const newOuterBox = (Player.crouchingBoundingBoxExtent - Player.standingBoundingBoxExtent)*@as(Vec3d, @splat(smoothPerc)) + Player.standingBoundingBoxExtent;

		Player.super.pos += newOuterBox - Player.outerBoundingBoxExtent + Vec3d{0.0, 0.0, 0.0001*@abs(newOuterBox[2] - Player.outerBoundingBoxExtent[2])};

		Player.outerBoundingBoxExtent = newOuterBox;

		Player.outerBoundingBox = .{
			.min = -Player.outerBoundingBoxExtent,
			.max = Player.outerBoundingBoxExtent,
		};
		Player.eyeBox = .{
			.min = -Vec3d{Player.outerBoundingBoxExtent[0]*0.2, Player.outerBoundingBoxExtent[1]*0.2, Player.outerBoundingBoxExtent[2] - 0.2},
			.max = Vec3d{Player.outerBoundingBoxExtent[0]*0.2, Player.outerBoundingBoxExtent[1]*0.2, Player.outerBoundingBoxExtent[2] - 0.05},
		};
		Player.desiredEyePos = (Vec3d{0, 0, 1.3 - Player.crouchingBoundingBoxExtent[2]} - Vec3d{0, 0, 1.7 - Player.standingBoundingBoxExtent[2]})*@as(Vec3f, @splat(smoothPerc)) + Vec3d{0, 0, 1.7 - Player.standingBoundingBoxExtent[2]};
	}

	physics.update(deltaTime, acc, jumping);

	const time = std.time.milliTimestamp();
	if(nextBlockPlaceTime) |*placeTime| {
		if(time -% placeTime.* >= 0) {
			placeTime.* += main.settings.updateRepeatSpeed;
			Player.placeBlock();
		}
	}
	if(nextBlockBreakTime) |*breakTime| {
		if(time -% breakTime.* >= 0 or !Player.isCreative()) {
			breakTime.* += main.settings.updateRepeatSpeed;
			Player.breakBlock(deltaTime);
		}
	}

	const biome = world.?.playerBiome.load(.monotonic);

	const t = 1 - @as(f32, @floatCast(@exp(-2*deltaTime)));

	biomeFog.fogColor = (biome.fogColor - biomeFog.fogColor)*@as(Vec3f, @splat(t)) + biomeFog.fogColor;
	biomeFog.skyColor = (biome.skyColor - biomeFog.skyColor)*@as(Vec3f, @splat(t)) + biomeFog.skyColor;
	biomeFog.density = (biome.fogDensity - biomeFog.density)*t + biomeFog.density;
	biomeFog.fogLower = (biome.fogLower - biomeFog.fogLower)*t + biomeFog.fogLower;
	biomeFog.fogHigher = (biome.fogHigher - biomeFog.fogHigher)*t + biomeFog.fogHigher;

	world.?.update();
	particles.ParticleSystem.update(@floatCast(deltaTime));
}
