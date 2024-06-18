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
	pub var isFlying: Atomic(bool) = Atomic(bool).init(false);
	pub var mutex: std.Thread.Mutex = std.Thread.Mutex{};
	pub var inventory__SEND_CHANGES_TO_SERVER: Inventory = undefined;
	pub var selectedSlot: u32 = 0;

	pub var maxHealth: f32 = 8;
	pub var health: f32 = 4.5;

	pub var onGround: bool = false;

	pub const radius = 0.3;
	pub const height = 1.8;
	pub const eye = 1.5;

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

	pub fn collides() bool {
		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] - radius)), @intFromFloat(@floor(super.pos[1] - radius)), @intFromFloat(@floor(super.pos[2])))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] + radius - 0.0001)), @intFromFloat(@floor(super.pos[1] - radius)), @intFromFloat(@floor(super.pos[2])))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] + radius - 0.0001)), @intFromFloat(@floor(super.pos[1] + radius - 0.0001)), @intFromFloat(@floor(super.pos[2])))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] - radius)), @intFromFloat(@floor(super.pos[1] + radius - 0.0001)), @intFromFloat(@floor(super.pos[2])))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] - radius)), @intFromFloat(@floor(super.pos[1] - radius)), @intFromFloat(@floor(super.pos[2] + height / 2.0)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] + radius - 0.0001)), @intFromFloat(@floor(super.pos[1] - radius)), @intFromFloat(@floor(super.pos[2] + height / 2.0)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] + radius - 0.0001)), @intFromFloat(@floor(super.pos[1] + radius - 0.0001)), @intFromFloat(@floor(super.pos[2] + height / 2.0)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] - radius)), @intFromFloat(@floor(super.pos[1] + radius - 0.0001)), @intFromFloat(@floor(super.pos[2] + height / 2.0)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] - radius)), @intFromFloat(@floor(super.pos[1] - radius)), @intFromFloat(@floor(super.pos[2] + height - 0.0001)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] + radius - 0.0001)), @intFromFloat(@floor(super.pos[1] - radius)), @intFromFloat(@floor(super.pos[2] + height - 0.0001)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] + radius - 0.0001)), @intFromFloat(@floor(super.pos[1] + radius - 0.0001)), @intFromFloat(@floor(super.pos[2] + height - 0.0001)))) |block| {
			if (block.collide())
				return true;
		}

		if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(super.pos[0] - radius)), @intFromFloat(@floor(super.pos[1] + radius - 0.0001)), @intFromFloat(@floor(super.pos[2] + height - 0.0001)))) |block| {
			if (block.collide())
				return true;
		}

		return false;
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
}

pub fn update(deltaTime: f64) void {
	if (main.renderer.mesh_storage.getBlock(@intFromFloat(@floor(Player.super.pos[0])), @intFromFloat(@floor(Player.super.pos[1])), @intFromFloat(@floor(Player.super.pos[2]))) != null) {		
		if (!Player.isFlying.load(.monotonic)) {
			Player.super.vel[2] -= 30 * deltaTime;
		}

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
						movement[2] += 59.45;
					} else {
						movement[2] += 5.45;
					}
				} else if (Player.onGround) {
					Player.super.vel[2] = @sqrt(1.25 * 30 * 2);
				}
			}
			if(KeyBoard.key("fall").pressed) {
				if(Player.isFlying.load(.monotonic)) {
					if(KeyBoard.key("sprint").pressed) {
						movement[2] += -59.45;
					} else {
						movement[2] += -5.45;
					}
				}
			}

			const newSlot: i32 = @as(i32, @intCast(Player.selectedSlot)) -% @as(i32, @intFromFloat(main.Window.scrollOffset));
			Player.selectedSlot = @intCast(@mod(newSlot, 12));
			main.Window.scrollOffset = 0;
		}

		Player.super.vel[0] = movement[0];
		Player.super.vel[1] = movement[1];

		if (Player.isFlying.load(.monotonic)) {
			Player.super.vel[2] = movement[2];
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

	{
		Player.mutex.lock();
		defer Player.mutex.unlock();

		const move = Player.super.vel*@as(Vec3d, @splat(deltaTime));
		Player.super.pos[0] += move[0];
		if (Player.collides()) {
			if (Player.super.vel[0] < 0) {
				Player.super.pos[0] = @ceil(Player.super.pos[0] - Player.radius) + Player.radius;
				while (Player.collides()) {
					Player.super.pos[0] += 1;
				}
			} else {
				Player.super.pos[0] = @ceil(Player.super.pos[0] + Player.radius) - Player.radius;
				while (Player.collides()) {
					Player.super.pos[0] -= 1;
				}
			}
		}

		Player.super.pos[1] += move[1];
		if (Player.collides()) {
			if (Player.super.vel[1] < 0) {
				Player.super.pos[1] = @ceil(Player.super.pos[1] - Player.radius) + Player.radius;
				while (Player.collides()) {
					Player.super.pos[1] += 1;
				}
			} else {
				Player.super.pos[1] = @ceil(Player.super.pos[1] + Player.radius) - Player.radius;
				while (Player.collides()) {
					Player.super.pos[1] -= 1;
				}
			}
		}
		
		Player.onGround = false;
		Player.super.pos[2] += move[2];
		if (Player.collides()) {
			if (Player.super.vel[2] < 0) {
				Player.super.pos[2] = @ceil(Player.super.pos[2]);
				while (Player.collides()) {
					Player.super.pos[2] += 1;
				}
				Player.onGround = true;
			} else {
				Player.super.pos[2] = @ceil(Player.super.pos[2] + Player.height) - Player.height;
				while (Player.collides()) {
					Player.super.pos[2] -= 1;
				}
			}
			Player.super.vel[2] = 0;
		}
	}

	const biome = world.?.playerBiome.load(.monotonic);
	
	const t = 1 - @as(f32, @floatCast(@exp(-2 * deltaTime)));

	fog.fogColor = (biome.fogColor - fog.fogColor) * @as(Vec3f, @splat(t)) + fog.fogColor;
	fog.density = (biome.fogDensity - fog.density) * t + fog.density;

	world.?.update();
}