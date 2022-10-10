const std = @import("std");

const assets = @import("assets.zig");
const chunk = @import("chunk.zig");
const json = @import("json.zig");
const JsonElement = json.JsonElement;
const main = @import("main.zig");
const keyboard = &main.keyboard;
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

pub const camera = struct {
	pub var rotation: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	pub var direction: Vec3f = Vec3f{.x=0, .y=0, .z=0};
	pub var viewMatrix: Mat4f = Mat4f.identity();
	pub fn moveRotation(mouseX: f32, mouseY: f32) void {
		// Mouse movement along the x-axis rotates the image along the y-axis.
		rotation.x += mouseY;
		if(rotation.x > std.math.pi/2.0) {
			rotation.x = std.math.pi/2.0;
		} else if(rotation.x < -std.math.pi/2.0) {
			rotation.x = -std.math.pi/2.0;
		}
		// Mouse movement along the y-axis rotates the image along the x-axis.
		rotation.y += mouseX;

		direction = Vec3f.rotateX(Vec3f{.x=0, .y=0, .z=-1}, rotation.x).rotateY(rotation.y);
	}

	pub fn updateViewMatrix() void {
		viewMatrix = Mat4f.rotationX(rotation.x).mul(Mat4f.rotationY(rotation.y));
	}
};

pub const Player = struct {
	var pos: Vec3d = Vec3d{.x=0, .y=0, .z=0};
	var vel: Vec3d = Vec3d{.x=0, .y=0, .z=0};
	pub var id: u32 = 0;
	pub var isFlying: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(true);
	var mutex: std.Thread.Mutex = std.Thread.Mutex{};

	pub fn getPosBlocking() Vec3d {
		mutex.lock();
		defer mutex.unlock();
		return pos;
	}

	pub fn getVelBlocking() Vec3d {
		mutex.lock();
		defer mutex.unlock();
		return vel;
	}
};

pub const World = struct {
	const dayCycle: u63 = 12000; // Length of one in-game day in 100ms. Midnight is at DAY_CYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes

	conn: *Connection,
	manager: *ConnectionManager,
	ambientLight: f32 = 0,
	clearColor: Vec4f = Vec4f{.x=0, .y=0, .z=0, .w=1},
	name: []const u8,
	milliTime: i64,
	gameTime: i64 = 0,
	spawn: Vec3f = undefined,
	blockPalette: *assets.BlockPalette = undefined,
	// TODO:
//	public ItemEntityManager itemEntityManager;
	
//	TODO: public Biome playerBiome;
//	public final ArrayList<String> chatHistory = new ArrayList<>();

	pub fn init(self: *World, ip: []const u8, manager: *ConnectionManager) !void {
		self.* = World {
			.conn = try Connection.init(manager, ip),
			.manager = manager,
			.name = "client",
			.milliTime = std.time.milliTimestamp(),
		};
		// TODO:
//		super.itemEntityManager = new InterpolatedItemEntityManager(this);
//		player = new ClientPlayer(this, 0);
		try network.Protocols.handShake.clientSide(self.conn, "quanturmdoelvloper"); // TODO: Read name from settings.
	}

	pub fn deinit(self: *World) void {
		self.conn.deinit();
	}

	pub fn finishHandshake(self: *World, jsonObject: JsonElement) !void {
		// TODO: Consider using a per-world allocator.
		self.blockPalette = try assets.BlockPalette.init(renderer.RenderStructure.allocator, jsonObject.getChild("blockPalette"));
		var jsonSpawn = jsonObject.getChild("spawn");
		self.spawn.x = jsonSpawn.get(f32, "x", 0);
		self.spawn.y = jsonSpawn.get(f32, "y", 0);
		self.spawn.z = jsonSpawn.get(f32, "z", 0);

		// TODO:
//		if(Server.world != null) {
//			// Share the registries of the local server:
//			registries = Server.world.getCurrentRegistries();
//		} else {
//			registries = new CurrentWorldRegistries(this, "serverAssets/", blockPalette);
//		}
//
//		player.loadFrom(json.getObjectOrNew("player"), this);
		Player.id = jsonObject.get(u32, "player_id", std.math.maxInt(u32));
//		TODO:
//		// Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
//		ModLoader.postWorldGen(registries);
		try assets.loadWorldAssets("serverAssets", self.blockPalette);
	}

	pub fn update(self: *World) !void {
		var newTime: i64 = std.time.milliTimestamp();
		while(self.milliTime +% 100 -% newTime < 0) { // TODO: Just use milli time directly?
			self.milliTime +%= 100;
			self.gameTime +%= 1;
		}
		// Ambient light:
		{
			var dayTime = std.math.absInt(@mod(self.gameTime, dayCycle) -% dayCycle/2) catch 0;
			if(dayTime < dayCycle/4 - dayCycle/16) {
				self.ambientLight = 0.1;
				self.clearColor.x = 0;
				self.clearColor.y = 0;
				self.clearColor.z = 0;
			} else if(dayTime > dayCycle/4 + dayCycle/16) {
				self.ambientLight = 1;
				self.clearColor.x = 0.8;
				self.clearColor.y = 0.8;
				self.clearColor.z = 1.0;
			} else {
				// b:
				if(dayTime > dayCycle/4) {
					self.clearColor.z = @intToFloat(f32, dayTime - dayCycle/4)/@intToFloat(f32, dayCycle/16);
				} else {
					self.clearColor.z = 0;
				}
				// g:
				if(dayTime > dayCycle/4 + dayCycle/32) {
					self.clearColor.y = 0.8;
				} else if(dayTime > dayCycle/4 - dayCycle/32) {
					self.clearColor.y = 0.8 + 0.8*@intToFloat(f32, dayTime - dayCycle/4 - dayCycle/32)/@intToFloat(f32, dayCycle/16);
				} else {
					self.clearColor.y = 0;
				}
				// r:
				if(dayTime > dayCycle/4) {
					self.clearColor.x = 0.8;
				} else {
					self.clearColor.x = 0.8 + 0.8*@intToFloat(f32, dayTime - dayCycle/4)/@intToFloat(f32, dayCycle/16);
				}
				dayTime -= dayCycle/4;
				dayTime <<= 3;
				self.ambientLight = 0.55 + 0.45*@intToFloat(f32, dayTime)/@intToFloat(f32, dayCycle/2);
			}
		}
		try network.Protocols.playerPosition.send(self.conn, Player.getPosBlocking(), Player.getVelBlocking(), @intCast(u16, newTime & 65535));
	}
	// TODO:
//	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity) {
//		Protocols.GENERIC_UPDATE.itemStackDrop(serverConnection, stack, pos, dir, velocity);
//	}
//	public void updateBlock(int x, int y, int z, int newBlock) {
//		NormalChunk ch = getChunk(x, y, z);
//		if (ch != null) {
//			int old = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
//			if(old != newBlock) {
//				ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, newBlock);
//				Protocols.BLOCK_UPDATE.send(serverConnection, x, y, z, newBlock);
//			}
//		}
//	}
//	/**
//	 * Block update that came from the server. In this case there needs to be no update sent to the server.
//	 */
//	public void remoteUpdateBlock(int x, int y, int z, int newBlock) {
//		NormalChunk ch = getChunk(x, y, z);
//		if (ch != null) {
//			int old = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
//			if(old != newBlock) {
//				ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, newBlock);
//			}
//		}
//	}
//	public void queueChunks(ChunkData[] chunks) {
//		Protocols.CHUNK_REQUEST.sendRequest(serverConnection, chunks);
//	}
//	public NormalChunk getChunk(int wx, int wy, int wz) {
//		RenderOctTree.OctTreeNode node = Cubyz.chunkTree.findNode(new ChunkData(wx, wy, wz, 1));
//		if(node == null)
//			return null;
//		ChunkData chunk = node.mesh.getChunk();
//		if(chunk instanceof NormalChunk)
//			return (NormalChunk)chunk;
//		return null;
//	}
//	public void cleanup() {
//		connectionManager.cleanup();
//		ThreadPool.clear();
//	}
//
//	public final BlockInstance getBlockInstance(int x, int y, int z) {
//		VisibleChunk ch = (VisibleChunk)getChunk(x, y, z);
//		if (ch != null && ch.isLoaded()) {
//			return ch.getBlockInstanceAt(Chunk.getIndex(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask));
//		} else {
//			return null;
//		}
//	}
//
//	public int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
//		VisibleChunk ch = (VisibleChunk)getChunk(x, y, z);
//		if (ch == null || !ch.isLoaded() || !easyLighting)
//			return 0xffffffff;
//		return ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
//	}
//
//	public void getLight(VisibleChunk ch, int x, int y, int z, int[] array) {
//		int block = getBlock(x, y, z);
//		if (block == 0) return;
//		int selfLight = Blocks.light(block);
//		x--;
//		y--;
//		z--;
//		for(int ix = 0; ix < 3; ix++) {
//			for(int iy = 0; iy < 3; iy++) {
//				for(int iz = 0; iz < 3; iz++) {
//					array[ix + iy*3 + iz*9] = getLight(ch, x+ix, y+iy, z+iz, selfLight);
//				}
//			}
//		}
//	}
//
//	protected int getLight(VisibleChunk ch, int x, int y, int z, int minLight) {
//		if (x - ch.wx != (x & Chunk.chunkMask) || y - ch.wy != (y & Chunk.chunkMask) || z - ch.wz != (z & Chunk.chunkMask))
//			ch = (VisibleChunk)getChunk(x, y, z);
//		if (ch == null || !ch.isLoaded())
//			return 0xff000000;
//		int light = ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
//		// Make sure all light channels are at least as big as the minimum:
//		if ((light & 0xff000000) >>> 24 < (minLight & 0xff000000) >>> 24) light = (light & 0x00ffffff) | (minLight & 0xff000000);
//		if ((light & 0x00ff0000) < (minLight & 0x00ff0000)) light = (light & 0xff00ffff) | (minLight & 0x00ff0000);
//		if ((light & 0x0000ff00) < (minLight & 0x0000ff00)) light = (light & 0xffff00ff) | (minLight & 0x0000ff00);
//		if ((light & 0x000000ff) < (minLight & 0x000000ff)) light = (light & 0xffffff00) | (minLight & 0x000000ff);
//		return light;
//	}
};
pub var testWorld: World = undefined; // TODO:
pub var world: ?*World = &testWorld;

pub var projectionMatrix: Mat4f = Mat4f.identity();
pub var lodProjectionMatrix: Mat4f = Mat4f.identity();

pub var fog = Fog{.active = true, .color=.{.x=0, .y=1, .z=0.5}, .density=1.0/15.0/256.0};


pub fn update(deltaTime: f64) !void {
	var movement = Vec3d{.x=0, .y=0, .z=0};
	var forward = Vec3d.rotateY(Vec3d{.x=0, .y=0, .z=-1}, -camera.rotation.y);
	var right = Vec3d{.x=forward.z, .y=0, .z=-forward.x};
	if(keyboard.forward.pressed) {
		if(keyboard.sprint.pressed) {
			if(Player.isFlying.load(.Monotonic)) {
				movement.addEqual(forward.mulScalar(64));
			} else {
				movement.addEqual(forward.mulScalar(8));
			}
		} else {
			movement.addEqual(forward.mulScalar(4));
		}
	}
	if(keyboard.backward.pressed) {
		movement.addEqual(forward.mulScalar(-4));
	}
	if(keyboard.left.pressed) {
		movement.addEqual(right.mulScalar(4));
	}
	if(keyboard.right.pressed) {
		movement.addEqual(right.mulScalar(-4));
	}
	if(keyboard.jump.pressed) {
		if(Player.isFlying.load(.Monotonic)) {
			if(keyboard.sprint.pressed) {
				movement.y = 59.45;
			} else {
				movement.y = 5.45;
			}
		} else { // TODO: if (Cubyz.player.isOnGround())
			movement.y = 5.45;
		}
	}
	if(keyboard.fall.pressed) {
		if(Player.isFlying.load(.Monotonic)) {
			if(keyboard.sprint.pressed) {
				movement.y = -59.45;
			} else {
				movement.y = -5.45;
			}
		}
	}

	{
		Player.mutex.lock();
		defer Player.mutex.unlock();
		Player.pos.addEqual(movement.mulScalar(deltaTime));
	}
	try world.?.update();
}