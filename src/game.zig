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

pub const Player = struct {
	pub var super: main.server.Entity = .{};
	pub var id: u32 = 0;
	pub var isFlying: Atomic(bool) = Atomic(bool).init(true);
	pub var mutex: std.Thread.Mutex = std.Thread.Mutex{};
	pub var inventory__SEND_CHANGES_TO_SERVER: Inventory = undefined;
	pub var selectedSlot: u32 = 0;

	pub var maxHealth: f32 = 8;
	pub var health: f32 = 4.5;

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

	pub fn placeBlock() void {
		if(!main.Window.grabbed) return;
		main.renderer.MeshSelection.placeBlock(&inventory__SEND_CHANGES_TO_SERVER.items[selectedSlot]);
	}

	pub fn breakBlock() void { // TODO: Breaking animation and tools
		if(!main.Window.grabbed) return;
		main.renderer.MeshSelection.breakBlock(&inventory__SEND_CHANGES_TO_SERVER.items[selectedSlot]);
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
	blockPalette: *assets.BlockPalette = undefined,
	itemDrops: ClientItemDropManager = undefined,
	playerBiome: Atomic(*const main.server.terrain.biomes.Biome) = undefined,

	pub fn init(self: *World, ip: []const u8, manager: *ConnectionManager) !void {
		self.* = .{
			.conn = try Connection.init(manager, ip),
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
		main.threadPool.clear();
		self.conn.deinit();
		self.itemDrops.deinit();
		self.blockPalette.deinit();
		Player.inventory__SEND_CHANGES_TO_SERVER.deinit(main.globalAllocator);
		self.manager.deinit();
		main.server.stop();
		if(main.server.thread) |serverThread| {
			serverThread.join();
			main.server.thread = null;
		}
		main.threadPool.clear();
		assets.unloadAssets();
	}

	pub fn finishHandshake(self: *World, json: JsonElement) !void {
		// TODO: Consider using a per-world allocator.
		self.blockPalette = try assets.BlockPalette.init(main.globalAllocator, json.getChild("blockPalette"));
		errdefer self.blockPalette.deinit();
		const jsonSpawn = json.getChild("spawn");
		self.spawn[0] = jsonSpawn.get(f32, "x", 0);
		self.spawn[1] = jsonSpawn.get(f32, "y", 0);
		self.spawn[2] = jsonSpawn.get(f32, "z", 0);

		try assets.loadWorldAssets("serverAssets", self.blockPalette);
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
			if(dayTime < dayCycle/4 - dayCycle/16) {
				self.ambientLight = 0.1;
				self.clearColor[0] = 0;
				self.clearColor[1] = 0;
				self.clearColor[2] = 0;
			} else if(dayTime > dayCycle/4 + dayCycle/16) {
				self.ambientLight = 1;
				self.clearColor[0] = 0.8;
				self.clearColor[1] = 0.8;
				self.clearColor[2] = 1.0;
			} else {
				// b:
				if(dayTime > dayCycle/4) {
					self.clearColor[2] = @as(f32, @floatFromInt(dayTime - dayCycle/4))/@as(f32, @floatFromInt(dayCycle/16));
				} else {
					self.clearColor[2] = 0;
				}
				// g:
				if(dayTime > dayCycle/4 + dayCycle/32) {
					self.clearColor[1] = 0.8;
				} else if(dayTime > dayCycle/4 - dayCycle/32) {
					self.clearColor[1] = 0.8 - 0.8*@as(f32, @floatFromInt(dayCycle/4 + dayCycle/32 - dayTime))/@as(f32, @floatFromInt(dayCycle/16));
				} else {
					self.clearColor[1] = 0;
				}
				// r:
				if(dayTime > dayCycle/4) {
					self.clearColor[0] = 0.8;
				} else {
					self.clearColor[0] = 0.8 - 0.8*@as(f32, @floatFromInt(dayCycle/4 - dayTime))/@as(f32, @floatFromInt(dayCycle/16));
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

pub var fog = Fog{.color=.{0, 1, 0.5}, .density=1.0/15.0/128.0}; // TODO: Make this depend on the render distance.

pub fn update(deltaTime: f64) void {
	var movement = Vec3d{0, 0, 0};
	const forward = vec.rotateZ(Vec3d{0, 1, 0}, -camera.rotation[2]);
	const right = Vec3d{-forward[1], forward[0], 0};
	if(main.Window.grabbed) {
		if(KeyBoard.key("forward").pressed) {
			if(KeyBoard.key("sprint").pressed) {
				if(Player.isFlying.load(.monotonic)) {
					movement += forward*@as(Vec3d, @splat(128));
				} else {
					movement += forward*@as(Vec3d, @splat(8));
				}
			} else {
				movement += forward*@as(Vec3d, @splat(4));
			}
		}
		if(KeyBoard.key("backward").pressed) {
			movement += forward*@as(Vec3d, @splat(-4));
		}
		if(KeyBoard.key("left").pressed) {
			movement += right*@as(Vec3d, @splat(4));
		}
		if(KeyBoard.key("right").pressed) {
			movement += right*@as(Vec3d, @splat(-4));
		}
		if(KeyBoard.key("jump").pressed) {
			if(Player.isFlying.load(.monotonic)) {
				if(KeyBoard.key("sprint").pressed) {
					movement[2] = 59.45;
				} else {
					movement[2] = 5.45;
				}
			} else { // TODO: if (Cubyz.player.isOnGround())
				movement[2] = 5.45;
			}
		}
		if(KeyBoard.key("fall").pressed) {
			if(Player.isFlying.load(.monotonic)) {
				if(KeyBoard.key("sprint").pressed) {
					movement[2] = -59.45;
				} else {
					movement[2] = -5.45;
				}
			}
		}
		const newSlot: i32 = @as(i32, @intCast(Player.selectedSlot)) -% @as(i32, @intFromFloat(main.Window.scrollOffset));
		Player.selectedSlot = @intCast(@mod(newSlot, 12));
		main.Window.scrollOffset = 0;
	}

	{
		Player.mutex.lock();
		defer Player.mutex.unlock();
		Player.super.pos += movement*@as(Vec3d, @splat(deltaTime));
	}
	world.?.update();
}