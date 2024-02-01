const std = @import("std");

const main = @import("root");
const network = main.network;
const Connection = network.Connection;
const ConnectionManager = network.ConnectionManager;
const utils = main.utils;
const vec = main.vec;
const Vec3d = vec.Vec3d;

pub const ServerWorld = @import("world.zig").ServerWorld;
pub const terrain = @import("terrain/terrain.zig");
pub const Entity = @import("Entity.zig");


pub const User = struct {
	conn: *Connection,
	player: Entity = .{},
	timeDifference: utils.TimeDifference = .{},
	interpolation: utils.GenericInterpolation(3) = undefined,
	lastTime: i16 = undefined,
	name: []const u8 = "",
	renderDistance: u16 = undefined,
	receivedFirstEntityData: bool = false,
	isLocal: bool = false,
	// TODO: ipPort: []const u8,
//	TODO: public Thread waitingThread;

	pub fn init(manager: *ConnectionManager, ipPort: []const u8) !*User {
		const self = main.globalAllocator.create(User);
		errdefer main.globalAllocator.destroy(self);
		self.* = User {
			.conn = try Connection.init(manager, ipPort),
		};
		self.conn.user = self;
		self.interpolation.init(@ptrCast(&self.player.pos), @ptrCast(&self.player.vel));
		network.Protocols.handShake.serverSide(self.conn);
		// TODO:
//		synchronized(this) {
//			waitingThread = Thread.currentThread();
//			this.wait();
//			waitingThread = null;
//		}
		return self;
	}

	pub fn deinit(self: *User) void {
		self.conn.deinit();
		main.globalAllocator.free(self.name);
		main.globalAllocator.destroy(self);
	}
//	@Override
//	public void disconnect() {
//		super.disconnect();
//		Server.disconnect(this);
//	}

	pub fn initPlayer(self: *User, name: []const u8) void {
		self.name = main.globalAllocator.dupe(u8, name);
		world.?.findPlayer(self);
	}

	pub fn update(self: *User) void {
		std.debug.assert(!mutex.tryLock()); // The mutex should be locked when calling this function.
		var time = @as(i16, @truncate(std.time.milliTimestamp())) -% main.settings.entityLookback;
		time -%= self.timeDifference.difference.load(.Monotonic);
		self.interpolation.update(time, self.lastTime);
		self.lastTime = time;
	}

	pub fn receiveData(self: *User, data: []const u8) void {
		mutex.lock();
		defer mutex.unlock();
		const position: [3]f64 = .{
			@bitCast(std.mem.readInt(u64, data[0..8], .big)),
			@bitCast(std.mem.readInt(u64, data[8..16], .big)),
			@bitCast(std.mem.readInt(u64, data[16..24], .big)),
		};
		const velocity: [3]f64 = .{
			@bitCast(std.mem.readInt(u64, data[24..32], .big)),
			@bitCast(std.mem.readInt(u64, data[32..40], .big)),
			@bitCast(std.mem.readInt(u64, data[40..48], .big)),
		};
		const rotation: [3]f32 = .{
			@bitCast(std.mem.readInt(u32, data[48..52], .big)),
			@bitCast(std.mem.readInt(u32, data[52..56], .big)),
			@bitCast(std.mem.readInt(u32, data[56..60], .big)),
		};
		self.player.rot = rotation;
		const time = std.mem.readInt(i16, data[60..62], .big);
		self.timeDifference.addDataPoint(time);
		self.interpolation.updatePosition(&position, &velocity, time);
	}
	// TODO (Command stuff):
//	@Override
//	public void feedback(String feedback) {
//		Protocols.CHAT.send(this, "#ffff00"+feedback);
//	}
};

pub const updatesPerSec: u32 = 20;
const updateNanoTime: u32 = 1000000000/20;

pub var world: ?*ServerWorld = null;
pub var users: main.List(*User) = undefined;

pub var connectionManager: *ConnectionManager = undefined;

var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var lastTime: i128 = undefined;

pub var mutex: std.Thread.Mutex = .{};

pub var thread: ?std.Thread = null;

fn init(name: []const u8) void {
	std.debug.assert(world == null); // There can only be one world.
	users = main.List(*User).init(main.globalAllocator);
	lastTime = std.time.nanoTimestamp();
	connectionManager = ConnectionManager.init(main.settings.defaultPort, false) catch |err| {
		std.log.err("Couldn't create socket: {s}", .{@errorName(err)});
		@panic("Could not open Server.");
	}; // TODO Configure the second argument in the server settings.
	// TODO: Load the assets.

	world = ServerWorld.init(name, null) catch |err| {
		std.log.err("Failed to create world: {s}", .{@errorName(err)});
		@panic("Can't create world.");
	};
	if(true) blk: { // singleplayer // TODO: Configure this in the server settings.
		const user = User.init(connectionManager, "127.0.0.1:47650") catch |err| {
			std.log.err("Cannot create singleplayer user {s}", .{@errorName(err)});
			break :blk;
		};
		user.isLocal = true;
		connect(user);
	}
}

fn deinit() void {
	for(users.items) |user| {
		user.deinit();
	}
	users.clearAndFree();
	connectionManager.deinit();
	connectionManager = undefined;

	if(world) |_world| {
		_world.deinit();
	}
	world = null;
}

fn update() void {
	world.?.update();
	mutex.lock();
	for(users.items) |user| {
		user.update();
	}
	mutex.unlock();
	// TODO:
//		Entity[] entities = world.getEntities();
//		Protocols.ENTITY.sendToClients(entities, lastSentEntities, world.itemEntityManager);
//		lastSentEntities = entities;
}

pub fn start(name: []const u8) void {
	var sta = utils.StackAllocator.init(main.globalAllocator, 1 << 23);
	defer sta.deinit();
	main.stackAllocator = sta.allocator();
	std.debug.assert(!running.load(.Monotonic)); // There can only be one server.
	init(name);
	defer deinit();
	running.store(true, .Monotonic);
	while(running.load(.Monotonic)) {
		const newTime = std.time.nanoTimestamp();
		if(newTime -% lastTime < updateNanoTime) {
			std.time.sleep(@intCast(lastTime +% updateNanoTime -% newTime));
			lastTime +%= updateNanoTime;
		} else {
			std.log.warn("The server is lagging behind by {d:.1} ms", .{@as(f32, @floatFromInt(newTime -% lastTime -% updateNanoTime))/1000000.0});
			lastTime = newTime;
		}
		update();

	}
}

pub fn stop() void {
	running.store(false, .Monotonic);
}

pub fn disconnect(user: *User) void {
	// TODO: world.forceSave();
	const message = std.fmt.allocPrint(main.stackAllocator, "{s} #ffff00left", .{user.name}) catch unreachable;
	defer main.stackAllocator.free(message);
	mutex.lock();
	defer mutex.unlock();
	sendMessage(message);

	for(users.items, 0..) |other, i| {
		if(other == user) {
			_ = users.swapRemove(i);
			break;
		}
	}
//	TODO:		world.removeEntity(user.player);
//	TODO?		users = usersList.toArray();
}

pub fn connect(user: *User) void {
	const message = std.fmt.allocPrint(main.stackAllocator.allocator, "{s} #ffff00joined", .{user.name}) catch unreachable;
	defer main.stackAllocator.free(message);
	mutex.lock();
	defer mutex.unlock();
	sendMessage(message);

	users.append(user);
	// TODO: users = usersList.toArray();
}

//	private Entity[] lastSentEntities = new Entity[0];

pub fn sendMessage(msg: []const u8) void {
	std.debug.assert(!mutex.tryLock()); // Mutex must be locked!
	std.log.info("Chat: {s}", .{msg}); // TODO use color \033[0;32m
	for(users.items) |user| {
		main.network.Protocols.chat.send(user.conn, msg);
	}
}