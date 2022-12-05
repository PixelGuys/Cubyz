const std = @import("std");
const Allocator = std.mem.Allocator;

const assets = @import("assets.zig");
const Block = @import("blocks.zig").Block;
const chunk = @import("chunk.zig");
const entity = @import("entity.zig");
const items = @import("items.zig");
const Inventory = items.Inventory;
const ItemStack = items.ItemStack;
const json = @import("json.zig");
const main = @import("main.zig");
const game = @import("game.zig");
const settings = @import("settings.zig");
const JsonElement = json.JsonElement;
const renderer = @import("renderer.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;

//TODO: Might want to use SSL or something similar to encode the message

const Socket = struct {
	const c = @cImport({@cInclude("cross_platform_udp_socket.h");});
	socketID: u31,

	fn checkError(comptime msg: []const u8, comptime T: type, result: T) !std.meta.Int(.unsigned, @bitSizeOf(T) - 1) {
		if(result == -1) {
			std.log.warn(msg, .{c.getError()});
			return error.SocketError;
		}
		return @intCast(std.meta.Int(.unsigned, @bitSizeOf(T) - 1), result);
	}

	fn init(localPort: u16) !Socket {
		return Socket{.socketID = try checkError("Socket creation failed with error: {}", c_int, c.init(localPort))};
	}

	fn deinit(self: Socket) void {
		_ = checkError("Error while closing socket: {}", c_int, c.deinit(self.socketID)) catch 0;
	}

	fn send(self: Socket, data: []const u8, destination: Address) !void {
		_ = try checkError("Error sending data: {}", isize, c.sendTo(self.socketID, data.ptr, data.len, destination.ip, destination.port));
	}

	fn receive(self: Socket, buffer: []u8, timeout: c_int, resultAddress: *Address) ![]u8 {
		var length = try checkError("Receive failed: {}", isize, c.receiveFrom(self.socketID, buffer.ptr, buffer.len, timeout, &resultAddress.ip, &resultAddress.port));
		if(length == 0) return error.Timeout;
		return buffer[0..length];
	}

	fn resolveIP(ip: [:0]const u8) u32 {
		const result: u32 = c.resolveIP(ip.ptr);
		if(result == 0xffffffff) {
			std.log.warn("Could not resolve address: {s} error: {}", .{ip, c.getError()});
		}
		return result;
	}
};

pub fn init() void {
	Socket.c.startup();
	inline for(@typeInfo(@TypeOf(Protocols)).Struct.fields) |field| {
		if(field.field_type == type) {
			const id = @field(Protocols, field.name).id;
			if(id != Protocols.keepAlive and id != Protocols.important and Protocols.list[id] == null) {
				Protocols.list[id] = @field(Protocols, field.name).receive;
			} else {
				std.log.err("Duplicate list id {}.", .{id});
			}
		}
	}
}

const Address = struct {
	ip: u32,
	port: u16,
	isSymmetricNAT: bool = false,
};

const Request = struct {
	address: Address,
	data: []const u8,
	requestNotifier: std.Thread.Condition = std.Thread.Condition{},
};

/// Implements parts of the STUN(Session Traversal Utilities for NAT) protocol to discover public IP+Port
/// Reference: https://datatracker.ietf.org/doc/html/rfc5389
const STUN = struct {
	const ipServerList = [_][]const u8 {
		"iphone-stun.strato-iphone.de:3478",
		"stun.12connect.com:3478",
		"stun.12voip.com:3478",
		"stun.1und1.de:3478",
		"stun.acrobits.cz:3478",
		"stun.actionvoip.com:3478",
		"stun.altar.com.pl:3478",
		"stun.antisip.com:3478",
		"stun.avigora.fr:3478",
		"stun.bluesip.net:3478",
		"stun.cablenet-as.net:3478",
		"stun.callromania.ro:3478",
		"stun.callwithus.com:3478",
		"stun.cheapvoip.com:3478",
		"stun.cloopen.com:3478",
		"stun.commpeak.com:3478",
		"stun.cope.es:3478",
		"stun.counterpath.com:3478",
		"stun.counterpath.net:3478",
		"stun.dcalling.de:3478",
		"stun.demos.ru:3478",
		"stun.dus.net:3478",
		"stun.easycall.pl:3478",
		"stun.easyvoip.com:3478",
		"stun.ekiga.net:3478",
		"stun.epygi.com:3478",
		"stun.etoilediese.fr:3478",
		"stun.freecall.com:3478",
		"stun.freeswitch.org:3478",
		"stun.freevoipdeal.com:3478",
		"stun.gmx.de:3478",
		"stun.gmx.net:3478",
		"stun.halonet.pl:3478",
		"stun.hoiio.com:3478",
		"stun.hosteurope.de:3478",
		"stun.infra.net:3478",
		"stun.internetcalls.com:3478",
		"stun.intervoip.com:3478",
		"stun.ipfire.org:3478",
		"stun.ippi.fr:3478",
		"stun.ipshka.com:3478",
		"stun.it1.hr:3478",
		"stun.ivao.aero:3478",
		"stun.jumblo.com:3478",
		"stun.justvoip.com:3478",
		"stun.l.google.com:19302",
		"stun.linphone.org:3478",
		"stun.liveo.fr:3478",
		"stun.lowratevoip.com:3478",
		"stun.lundimatin.fr:3478",
		"stun.mit.de:3478",
		"stun.miwifi.com:3478",
		"stun.myvoiptraffic.com:3478",
		"stun.netappel.com:3478",
		"stun.netgsm.com.tr:3478",
		"stun.nfon.net:3478",
		"stun.nonoh.net:3478",
		"stun.nottingham.ac.uk:3478",
		"stun.ooma.com:3478",
		"stun.ozekiphone.com:3478",
		"stun.pjsip.org:3478",
		"stun.poivy.com:3478",
		"stun.powervoip.com:3478",
		"stun.ppdi.com:3478",
		"stun.qq.com:3478",
		"stun.rackco.com:3478",
		"stun.rockenstein.de:3478",
		"stun.rolmail.net:3478",
		"stun.rynga.com:3478",
		"stun.schlund.de:3478",
		"stun.sigmavoip.com:3478",
		"stun.sip.us:3478",
		"stun.sipdiscount.com:3478",
		"stun.sipgate.net:10000",
		"stun.sipgate.net:3478",
		"stun.siplogin.de:3478",
		"stun.sipnet.net:3478",
		"stun.sippeer.dk:3478",
		"stun.siptraffic.com:3478",
		"stun.smartvoip.com:3478",
		"stun.smsdiscount.com:3478",
		"stun.solcon.nl:3478",
		"stun.solnet.ch:3478",
		"stun.sonetel.com:3478",
		"stun.sonetel.net:3478",
		"stun.sovtest.ru:3478",
		"stun.srce.hr:3478",
		"stun.stunprotocol.org:3478",
		"stun.t-online.de:3478",
		"stun.tel.lu:3478",
		"stun.telbo.com:3478",
		"stun.tng.de:3478",
		"stun.twt.it:3478",
		"stun.uls.co.za:3478",
		"stun.usfamily.net:3478",
		"stun.vivox.com:3478",
		"stun.vo.lu:3478",
		"stun.voicetrading.com:3478",
		"stun.voip.aebc.com:3478",
		"stun.voip.blackberry.com:3478",
		"stun.voip.eutelia.it:3478",
		"stun.voipblast.com:3478",
		"stun.voipbuster.com:3478",
		"stun.voipbusterpro.com:3478",
		"stun.voipcheap.co.uk:3478",
		"stun.voipcheap.com:3478",
		"stun.voipgain.com:3478",
		"stun.voipgate.com:3478",
		"stun.voipinfocenter.com:3478",
		"stun.voipplanet.nl:3478",
		"stun.voippro.com:3478",
		"stun.voipraider.com:3478",
		"stun.voipstunt.com:3478",
		"stun.voipwise.com:3478",
		"stun.voipzoom.com:3478",
		"stun.voys.nl:3478",
		"stun.voztele.com:3478",
		"stun.webcalldirect.com:3478",
		"stun.wifirst.net:3478",
		"stun.zadarma.com:3478",
		"stun1.l.google.com:19302",
		"stun2.l.google.com:19302",
		"stun3.l.google.com:19302",
		"stun4.l.google.com:19302",
		"stun.nextcloud.com:443",
		"relay.webwormhole.io:3478",
	};
	const MAPPED_ADDRESS: u16 = 0x0001;
	const XOR_MAPPED_ADDRESS: u16 = 0x0020;
	const MAGIC_COOKIE = [_]u8 {0x21, 0x12, 0xA4, 0x42};

	fn requestAddress(connection: *ConnectionManager) Address {
		var oldAddress: ?Address = null;
		var attempt: u32 = 0;
		var seed = [_]u8 {0} ** std.rand.DefaultCsprng.secret_seed_length;
		std.mem.writeIntNative(i128, seed[0..16], std.time.nanoTimestamp()); // Not the best seed, but it's not that important.
		var random = std.rand.DefaultCsprng.init(seed);
		while(attempt < 16): (attempt += 1) {
			// Choose a somewhat random server, so we faster notice if any one of them stopped working.
			const server = ipServerList[random.random().intRangeAtMost(usize, 0, ipServerList.len-1)];
			var data = [_]u8 {
				0x00, 0x01, // message type
				0x00, 0x00, // message length
				MAGIC_COOKIE[0], MAGIC_COOKIE[1], MAGIC_COOKIE[2], MAGIC_COOKIE[3], // "Magic cookie"
				0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // transaction ID
			};
			random.fill(data[8..]); // Fill the transaction ID.

			var splitter = std.mem.split(u8, server, ":");
			var nullTerminatedIP = main.threadAllocator.dupeZ(u8, splitter.first()) catch continue;
			defer main.threadAllocator.free(nullTerminatedIP);
			var serverAddress = Address{.ip=Socket.resolveIP(nullTerminatedIP), .port=std.fmt.parseUnsigned(u16, splitter.rest(), 10) catch 3478};
			if(connection.sendRequest(connection.allocator, &data, serverAddress, 500*1000000) catch |err| {
				std.log.warn("Encountered error: {s} while connecting to STUN server: {s}", .{@errorName(err), server});
				continue;
			}) |answer| {
				defer connection.allocator.free(answer);
				verifyHeader(answer, data[8..20]) catch |err| {
					std.log.warn("Header verification failed with {s} for STUN server: {s} data: {any}", .{@errorName(err), server, answer});
					continue;
				};
				var result = findIPPort(answer) catch |err| {
					std.log.warn("Could not parse IP+Port: {s} for STUN server: {s} data: {any}", .{@errorName(err), server, answer});
					continue;
				};
				if(oldAddress) |other| {
					std.log.info("{}.{}.{}.{}:{}", .{result.ip & 255, result.ip >> 8 & 255, result.ip >> 16 & 255, result.ip >> 24, result.port});
					if(other.ip == result.ip and other.port == result.port) {
						return result;
					} else {
						result.isSymmetricNAT = true;
						return result;
					}
				} else {
					oldAddress = result;
				}
			} else {
				std.log.warn("Couldn't reach STUN server: {s}", .{server});
			}
		}
		return Address{.ip=Socket.resolveIP("127.0.0.1"), .port=settings.defaultPort}; // TODO: Return ip address in LAN.
	}

	fn findIPPort(_data: []const u8) !Address {
		var data = _data[20..]; // Skip the header.
		while(data.len > 0) {
			const typ = std.mem.readIntBig(u16, data[0..2]);
			const len = std.mem.readIntBig(u16, data[2..4]);
			data = data[4..];
			switch(typ) {
				XOR_MAPPED_ADDRESS, MAPPED_ADDRESS => {
					const xor = data[0];
					if(typ == MAPPED_ADDRESS and xor != 0) return error.NonZeroXORForMappedAddress;
					if(data[1] == 0x01) {
						var addressData: [6]u8 = undefined;
						std.mem.copy(u8, &addressData, data[2..8]);
						if(typ == XOR_MAPPED_ADDRESS) {
							addressData[0] ^= MAGIC_COOKIE[0];
							addressData[1] ^= MAGIC_COOKIE[1];
							addressData[2] ^= MAGIC_COOKIE[0];
							addressData[3] ^= MAGIC_COOKIE[1];
							addressData[4] ^= MAGIC_COOKIE[2];
							addressData[5] ^= MAGIC_COOKIE[3];
						}
						return Address {
							.port = std.mem.readIntBig(u16, addressData[0..2]),
							.ip = std.mem.readIntNative(u32, addressData[2..6]), // Needs to stay in big endian → native.
						};
					} else if(data[1] == 0x02) {
						data = data[(len + 3) & ~@as(usize, 3)..]; // Pad to 32 Bit.
						continue; // I don't care about IPv6.
					} else {
						return error.UnknownAddressFamily;
					}
				},
				else => {
					data = data[(len + 3) & ~@as(usize, 3)..]; // Pad to 32 Bit.
				},
			}
		}
		return error.IpPortNotFound;
	}

	fn verifyHeader(data: []const u8, transactionID: []const u8) !void {
		if(data[0] != 0x01 or data[1] != 0x01) return error.NotABinding;
		if(@intCast(u16, data[2] & 0xff)*256 + (data[3] & 0xff) != data.len - 20) return error.BadSize;
		for(MAGIC_COOKIE) |cookie, i| {
			if(data[i + 4] != cookie) return error.WrongCookie;
		}
		for(transactionID) |_, i| {
			if(data[i+8] != transactionID[i]) return error.WrongTransaction;
		}
	}
};

//	private volatile boolean running = true;
pub const ConnectionManager = struct {
	socket: Socket = undefined,
	thread: std.Thread = undefined,
	threadId: std.Thread.Id = undefined,
	externalAddress: Address = undefined,
	online: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(true),
	running: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(true),

	connections: std.ArrayList(*Connection) = undefined,
	requests: std.ArrayList(*Request) = undefined,

	gpa: std.heap.GeneralPurposeAllocator(.{}),
	allocator: std.mem.Allocator = undefined,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},
	waitingToFinishReceive: std.Thread.Condition = std.Thread.Condition{},

	receiveBuffer: [Connection.maxPacketSize]u8 = undefined,

	pub fn init(localPort: u16, online: bool) !*ConnectionManager {
		var gpa = std.heap.GeneralPurposeAllocator(.{}){};
		var result: *ConnectionManager = try gpa.allocator().create(ConnectionManager);
		result.* = ConnectionManager {.gpa = gpa};
		result.allocator = result.gpa.allocator();
		result.connections = std.ArrayList(*Connection).init(result.allocator);
		result.requests = std.ArrayList(*Request).init(result.allocator);

		result.socket = try Socket.init(localPort);
		errdefer Socket.deinit(result.socket);

		result.thread = try std.Thread.spawn(.{}, run, .{result});
		try result.thread.setName("Network Thread");
		if(online) {
			result.makeOnline();
		}
		return result;
	}

	pub fn deinit(self: *ConnectionManager) void {
		for(self.connections.items) |conn| {
			conn.disconnect() catch |err| {std.log.warn("Error while disconnecting: {s}", .{@errorName(err)});};
		}

		self.running.store(false, .Monotonic);
		self.thread.join();
		Socket.deinit(self.socket);
		self.connections.deinit();
		for(self.requests.items) |request| {
			request.requestNotifier.signal();
		}
		self.requests.deinit();

		var gpa = self.gpa;
		gpa.allocator().destroy(self);
		if(gpa.deinit()) {
			@panic("Memory leak in connection.");
		}
	}

	pub fn makeOnline(self: *ConnectionManager) void {
		if(!self.online.load(.Acquire)) {
			self.externalAddress = STUN.requestAddress(self);
			self.online.store(true, .Release);
		}
	}

	pub fn send(self: *ConnectionManager, data: []const u8, target: Address) !void {
		try self.socket.send(data, target);
	}

	pub fn sendRequest(self: *ConnectionManager, allocator: Allocator, data: []const u8, target: Address, timeout_ns: u64) !?[]const u8 {
		try self.send(data, target);
		var request = Request{.address = target, .data = data};
		{
			self.mutex.lock();
			defer self.mutex.unlock();
			try self.requests.append(&request);

			request.requestNotifier.timedWait(&self.mutex, timeout_ns) catch {};

			for(self.requests.items) |req, i| {
				if(req == &request) {
					_ = self.requests.swapRemove(i);
					break;
				}
			}
		}

		// The request data gets modified when a result was received.
		if(request.data.ptr == data.ptr) {
			return null;
		} else {
			if(allocator.ptr == self.allocator.ptr) {
				return request.data;
			} else {
				var result = try allocator.dupe(u8, request.data);
				self.allocator.free(request.data);
				return result;
			}
		}
	}

	pub fn addConnection(self: *ConnectionManager, conn: *Connection) !void {
		self.mutex.lock();
		defer self.mutex.unlock();
		
		try self.connections.append(conn);
	}

	pub fn finishCurrentReceive(self: *ConnectionManager) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.waitingToFinishReceive.wait(&self.mutex);
	}

	pub fn removeConnection(self: *ConnectionManager, conn: *Connection) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		
		for(self.connections.items) |other, i| {
			if(other == conn) {
				_ = self.connections.swapRemove(i);
				break;
			}
		}
	}

	fn onReceive(self: *ConnectionManager, data: []const u8, source: Address) !void {
		std.debug.assert(self.threadId == std.Thread.getCurrentId());
		self.mutex.lock();
		
		for(self.connections.items) |conn| {
			if(conn.remoteAddress.ip == source.ip) {
				if(conn.bruteforcingPort) {
					conn.remoteAddress.port = source.port;
					conn.bruteforcingPort = false;
				}
				if(conn.remoteAddress.port == source.port) {
					self.mutex.unlock();
					try conn.receive(data);
					return;
				}
			}
		}
		defer self.mutex.unlock();
		// Check if it's part of an active request:
		for(self.requests.items) |request| {
			if(request.address.ip == source.ip and request.address.port == source.port) {
				request.data = try self.allocator.dupe(u8, data);
				request.requestNotifier.signal();
				return;
			}
		}
		if(self.online.load(.Acquire) and source.ip == self.externalAddress.ip and source.port == self.externalAddress.port) return;
		// TODO: Reduce the number of false alarms in the short period after a disconnect.
		std.log.warn("Unknown connection from address: {}", .{source});
		std.log.debug("Message: {any}", .{data});
	}

	pub fn run(self: *ConnectionManager) !void {
		self.threadId = std.Thread.getCurrentId();
		var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
		main.threadAllocator = gpa.allocator();
		defer if(gpa.deinit()) {
			@panic("Memory leak");
		};

		var lastTime = std.time.milliTimestamp();
		while(self.running.load(.Monotonic)) {
			self.waitingToFinishReceive.broadcast();
			var source: Address = undefined;
			if(self.socket.receive(&self.receiveBuffer, 100, &source)) |data| {
				try self.onReceive(data, source);
			} else |err| {
				if(err == error.Timeout) {
					// No message within the last ~100 ms.
				} else {
					return err; // TODO: Shutdown the game normally.
				}
			}

			// Send a keep-alive packet roughly every 100 ms:
			if(std.time.milliTimestamp() -% lastTime > 100) {
				lastTime = std.time.milliTimestamp();
				var i: u32 = 0;
				self.mutex.lock();
				defer self.mutex.unlock();
				while(i < self.connections.items.len) {
					var conn = self.connections.items[i];
					if(lastTime -% conn.lastConnection > settings.connectionTimeout and conn.isConnected()) {
						std.log.info("timeout", .{});
						// Timeout a connection if it was connect at some point. New connections are not timed out because that could annoy players(having to restart the connection several times).
						self.mutex.unlock();
						try conn.disconnect();
						self.mutex.lock();
					} else {
						try conn.sendKeepAlive();
						i += 1;
					}
				}
				if(self.connections.items.len == 0 and self.online.load(.Acquire)) {
					// Send a message to external ip, to keep the port open:
					var data = [1]u8{0};
					try self.send(&data, self.externalAddress);
				}
			}
		}
	}
};

const UnconfirmedPacket = struct {
	data: []const u8,
	lastKeepAliveSentBefore: u32,
	id: u32,
};

pub var bytesReceived: [256]usize = [_]usize {0} ** 256;
pub var packetsReceived: [256]usize = [_]usize {0} ** 256;
pub const Protocols: struct {
	var _list: [256]?*const fn(*Connection, []const u8) anyerror!void = [_]?*const fn(*Connection, []const u8) anyerror!void {null} ** 256;
	list: *[256]?*const fn(*Connection, []const u8) anyerror!void = &_list,

	keepAlive: u8 = 0,
	important: u8 = 0xff,
	handShake: type = struct {
		const id: u8 = 1;
		const stepStart: u8 = 0;
		const stepUserData: u8 = 1;
		const stepAssets: u8 = 2;
		const stepServerData: u8 = 3;
		const stepComplete: u8 = 255;

		fn receive(conn: *Connection, data: []const u8) !void {
			if(conn.handShakeState < data[0]) {
				conn.handShakeState = data[0];
				switch(data[0]) {
					stepUserData => {
						var jsonObject = json.parseFromString(main.threadAllocator, data[1..]);
						defer jsonObject.free(main.threadAllocator);
						var name = jsonObject.get([]const u8, "name", "unnamed");
						var version = jsonObject.get([]const u8, "version", "unknown");
						std.log.info("User {s} joined using version {s}.", .{name, version});

						{
							// TODO: Send the world data.
							var path = try std.fmt.allocPrint(main.threadAllocator, "saves/{s}/assets/", .{"Development"}); // TODO: Use world name.
							defer main.threadAllocator.free(path);
							var dir = try std.fs.cwd().openIterableDir(path, .{});
							defer dir.close();
							var arrayList = std.ArrayList(u8).init(main.threadAllocator);
							defer arrayList.deinit();
							try arrayList.append(stepAssets);
							try utils.Compression.pack(dir, arrayList.writer());
							std.log.debug("{any}", .{arrayList.items});
							try conn.sendImportant(id, arrayList.items);
							try conn.flush();
						}

						// TODO:
//					JsonObject jsonObject = new JsonObject();
//					((User)conn).initPlayer(name);
//					jsonObject.put("player", ((User)conn).player.save());
//					jsonObject.put("player_id", ((User)conn).player.id);
//					jsonObject.put("blockPalette", Server.world.blockPalette.save());
//					JsonObject spawn = new JsonObject();
//					spawn.put("x", Server.world.spawn.x);
//					spawn.put("y", Server.world.spawn.y);
//					spawn.put("z", Server.world.spawn.z);
//					jsonObject.put("spawn", spawn);
//					byte[] string = jsonObject.toString().getBytes(StandardCharsets.UTF_8);
//					byte[] outData = new byte[string.length + 1];
//					outData[0] = STEP_SERVER_DATA;
//					System.arraycopy(string, 0, outData, 1, string.length);
//					state.put(conn, STEP_SERVER_DATA);
//					conn.sendImportant(this, outData);
//					state.remove(conn); // Handshake is done.
//					conn.handShakeComplete = true;
//					synchronized(conn) { // Notify the waiting server thread.
//						conn.notifyAll();
//					}
					},
					stepAssets => {
						std.log.info("Received assets.", .{});
						std.fs.cwd().deleteTree("serverAssets") catch {}; // Delete old assets.
						try std.fs.cwd().makePath("serverAssets");
						try utils.Compression.unpack(try std.fs.cwd().openDir("serverAssets", .{}), data[1..]);
					},
					stepServerData => {
						var jsonObject = json.parseFromString(main.threadAllocator, data[1..]);
						defer jsonObject.free(main.threadAllocator);
						try game.world.?.finishHandshake(jsonObject);
						conn.handShakeState = stepComplete;
						conn.handShakeWaiting.broadcast(); // Notify the waiting client thread.
					},
					stepComplete => {

					},
					else => {
						std.log.err("Unknown state in HandShakeProtocol {}", .{data[0]});
					},
				}
			} else {
				// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
			}
		}

		pub fn serverSide(conn: *Connection) void {
			conn.handShakeState = stepStart;
		}

		pub fn clientSide(conn: *Connection, name: []const u8) !void {
			var jsonObject = JsonElement{.JsonObject=try main.threadAllocator.create(std.StringHashMap(JsonElement))};
			defer jsonObject.free(main.threadAllocator);
			jsonObject.JsonObject.* = std.StringHashMap(JsonElement).init(main.threadAllocator);
			try jsonObject.JsonObject.put(try main.threadAllocator.dupe(u8, "version"), JsonElement{.JsonString=settings.version});
			try jsonObject.JsonObject.put(try main.threadAllocator.dupe(u8, "name"), JsonElement{.JsonString=name});
			var prefix = [1]u8 {stepUserData};
			var data = try jsonObject.toStringEfficient(main.threadAllocator, &prefix);
			defer main.threadAllocator.free(data);
			try conn.sendImportant(id, data);

			conn.mutex.lock();
			conn.handShakeWaiting.wait(&conn.mutex);
			conn.mutex.unlock();
		}
	},
	chunkRequest: type = struct {
		const id: u8 = 2;
		fn receive(conn: *Connection, data: []const u8) !void {
			var remaining = data[0..];
			while(remaining.len >= 16) {
				const request = chunk.ChunkPosition{
					.wx = std.mem.readIntBig(chunk.ChunkCoordinate, remaining[0..4]),
					.wy = std.mem.readIntBig(chunk.ChunkCoordinate, remaining[4..8]),
					.wz = std.mem.readIntBig(chunk.ChunkCoordinate, remaining[8..12]),
					.voxelSize = @intCast(chunk.UChunkCoordinate, std.mem.readIntBig(chunk.ChunkCoordinate, remaining[12..16])),
				};
				_ = request;
				_ = conn;
				// TODO: Server.world.queueChunk(request, (User)conn);
				remaining = remaining[16..];
			}
		}
		pub fn sendRequest(conn: *Connection, requests: []chunk.ChunkPosition) !void {
			if(requests.len == 0) return;
			var data = try main.threadAllocator.alloc(u8, 16*requests.len);
			defer main.threadAllocator.free(data);
			var remaining = data;
			for(requests) |req| {
				std.mem.writeIntBig(chunk.ChunkCoordinate, remaining[0..4], req.wx);
				std.mem.writeIntBig(chunk.ChunkCoordinate, remaining[4..8], req.wy);
				std.mem.writeIntBig(chunk.ChunkCoordinate, remaining[8..12], req.wz);
				std.mem.writeIntBig(chunk.ChunkCoordinate, remaining[12..16], req.voxelSize);
				remaining = remaining[16..];
			}
			try conn.sendImportant(id, data);
		}
	},
	chunkTransmission: type = struct {
		const id: u8 = 3;
		fn receive(_: *Connection, _data: []const u8) !void {
			var data = _data;
			var pos = chunk.ChunkPosition{
				.wx = std.mem.readIntBig(chunk.ChunkCoordinate, data[0..4]),
				.wy = std.mem.readIntBig(chunk.ChunkCoordinate, data[4..8]),
				.wz = std.mem.readIntBig(chunk.ChunkCoordinate, data[8..12]),
				.voxelSize = @intCast(chunk.UChunkCoordinate, std.mem.readIntBig(chunk.ChunkCoordinate, data[12..16])),
			};
			const _inflatedData = try main.threadAllocator.alloc(u8, chunk.chunkVolume*4);
			defer main.threadAllocator.free(_inflatedData);
			const _inflatedLen = try utils.Compression.inflateTo(_inflatedData, data[16..]);
			if(_inflatedLen != chunk.chunkVolume*4) {
				std.log.err("Transmission of chunk has invalid size: {}. Input data: {any}, After inflate: {any}", .{_inflatedLen, data, _inflatedData[0.._inflatedLen]});
			}
			data = _inflatedData;
			var ch = try renderer.RenderStructure.allocator.create(chunk.Chunk);
			ch.init(pos);
			for(ch.blocks) |*block| {
				block.* = Block.fromInt(std.mem.readIntBig(u32, data[0..4]));
				data = data[4..];
			}
			try renderer.RenderStructure.updateChunkMesh(ch);
		}
		pub fn sendChunk(conn: *Connection, visData: chunk.ChunkVisibilityData) !void {
			var data = try main.threadAllocator.alloc(u8, 16 + 8*visData.visibles.items.len);
			defer main.threadAllocator.free(data);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[0..4], visData.pos.wx);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[4..8], visData.pos.wy);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[8..12], visData.pos.wz);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[12..16], visData.pos.voxelSize);
			var size = visData.visibles.items.len;
			var x = data[16..][0..size];
			var y = data[16..][size..2*size];
			var z = data[16..][2*size..3*size];
			var neighbors = data[16..][3*size..4*size];
			var visibleBlocks = data[16..][4*size..];
			for(visData.visibles.items) |block, i| {
				x[i] = block.x;
				y[i] = block.y;
				z[i] = block.z;
				neighbors[i] = block.neighbors;
				var blockTypeAndData = @as(u32, block.block.data) << 16 | block.block.typ;
				std.mem.writeIntBig(u32, visibleBlocks[4*i..][0..4], blockTypeAndData);
			}

			var compressed = try utils.Compression.deflate(main.threadAllocator, data);
			defer main.threadAllocator.free(compressed);
			try conn.sendImportant(id, compressed);
		}
	// TODO:
//	public void sendChunk(UDPConnection conn, ChunkData ch) {
//		byte[] data;
//		if(ch instanceof NormalChunk) {
//			byte[] compressedChunk = ChunkIO.compressChunk((NormalChunk)ch);
//			data = new byte[compressedChunk.length + 16];
//			System.arraycopy(compressedChunk, 0, data, 16, compressedChunk.length);
//		} else {
//			assert false: "Invalid chunk class to send over the network " + ch.getClass() + ".";
//			return;
//		}
//		Bits.putInt(data, 0, ch.wx);
//		Bits.putInt(data, 4, ch.wy);
//		Bits.putInt(data, 8, ch.wz);
//		Bits.putInt(data, 12, ch.voxelSize);
//		conn.sendImportant(this, data);
//	}
	},
	playerPosition: type = struct {
		const id: u8 = 4;
		fn receive(conn: *Connection, data: []const u8) !void {
			_ = conn;
			_ = data;
			// TODO: ((User)conn).receiveData(data, offset);
		}
		var lastPositionSent: u16 = 0;
		pub fn send(conn: *Connection, playerPos: Vec3d, playerVel: Vec3d, time: u16) !void {
			if(time -% lastPositionSent < 50) {
				return; // Only send at most once every 50 ms.
			}
			lastPositionSent = time;
			var data: [62]u8 = undefined;
			std.mem.writeIntBig(u64, data[0..8], @bitCast(u64, playerPos[0]));
			std.mem.writeIntBig(u64, data[8..16], @bitCast(u64, playerPos[1]));
			std.mem.writeIntBig(u64, data[16..24], @bitCast(u64, playerPos[2]));
			std.mem.writeIntBig(u64, data[24..32], @bitCast(u64, playerVel[0]));
			std.mem.writeIntBig(u64, data[32..40], @bitCast(u64, playerVel[1]));
			std.mem.writeIntBig(u64, data[40..48], @bitCast(u64, playerVel[2]));
			std.mem.writeIntBig(u32, data[48..52], @bitCast(u32, game.camera.rotation[0]));
			std.mem.writeIntBig(u32, data[52..56], @bitCast(u32, game.camera.rotation[1]));
			std.mem.writeIntBig(u32, data[56..60], @bitCast(u32, game.camera.rotation[2]));
			std.mem.writeIntBig(u16, data[60..62], time);
			try conn.sendUnimportant(id, &data);
		}
	},
	disconnect: type = struct {
		const id: u8 = 5;
		fn receive(conn: *Connection, _: []const u8) !void {
			try conn.disconnect();
		}
		pub fn disconnect(conn: *Connection) !void {
			const noData = [0]u8 {};
			try conn.sendUnimportant(id, &noData);
		}
	},
	entityPosition: type = struct {
		const id: u8 = 6;
		const type_entity: u8 = 0;
		const type_item: u8 = 1;
		fn receive(_: *Connection, data: []const u8) !void {
			if(game.world != null) {
				const time = std.mem.readIntBig(i16, data[1..3]);
				if(data[0] == type_entity) {
					try entity.ClientEntityManager.serverUpdate(time, data[3..]);
				} else if(data[0] == type_item) {
					// TODO: ((InterpolatedItemEntityManager)Cubyz.world.itemEntityManager).readPosition(data[3..], time);
				}
			}
		}
		pub fn send(conn: *Connection, entityData: []const u8, itemData: []const u8) !void {
			const fullEntityData = main.threadAllocator.alloc(u8, entityData.len + 3);
			defer main.threadAllocator.free(fullEntityData);
			fullEntityData[0] = type_entity;
			std.mem.writeIntBig(i16, fullEntityData[1..3], @truncate(i16, std.time.milliTimestamp()));
			std.mem.copy(u8, fullEntityData[3..], entityData);
			conn.sendUnimportant(id, fullEntityData);

			const fullItemData = main.threadAllocator.alloc(u8, itemData.len + 3);
			defer main.threadAllocator.free(fullItemData);
			fullItemData[0] = type_item;
			std.mem.writeIntBig(i16, fullItemData[1..3], @truncate(i16, std.time.milliTimestamp()));
			std.mem.copy(u8, fullItemData[3..], itemData);
			conn.sendUnimportant(id, fullItemData);
		}
	},
	blockUpdate: type = struct {
		const id: u8 = 7;
		fn receive(_: *Connection, data: []const u8) !void {
			var x = std.mem.readIntBig(chunk.ChunkCoordinate, data[0..4]);
			var y = std.mem.readIntBig(chunk.ChunkCoordinate, data[4..8]);
			var z = std.mem.readIntBig(chunk.ChunkCoordinate, data[8..12]);
			var newBlock = Block.fromInt(std.mem.readIntBig(u32, data[12..16]));
			try renderer.RenderStructure.updateBlock(x, y, z, newBlock);
			// TODO:
//		if(conn instanceof User) {
//			Server.world.updateBlock(x, y, z, newBlock);
//		} else {
//			Cubyz.world.remoteUpdateBlock(x, y, z, newBlock);
//		}
		}
		pub fn send(conn: *Connection, x: chunk.ChunkCoordinate, y: chunk.ChunkCoordinate, z: chunk.ChunkCoordinate, newBlock: Block) !void {
			var data: [16]u8 = undefined;
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[0..4], x);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[4..8], y);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[8..12], z);
			std.mem.writeIntBig(chunk.ChunkCoordinate, data[12..16], newBlock.toInt());
			try conn.sendImportant(id, &data);
		}
	},
	entity: type = struct {
		const id: u8 = 8;
		fn receive(_: *Connection, data: []const u8) !void {
			const jsonArray = json.parseFromString(main.threadAllocator, data);
			defer jsonArray.free(main.threadAllocator);
			var i: u32 = 0;
			while(i < jsonArray.JsonArray.items.len) : (i += 1) {
				const elem = jsonArray.JsonArray.items[i];
				switch(elem) {
					.JsonInt => {
						entity.ClientEntityManager.removeEntity(elem.as(u32, 0));
					},
					.JsonObject => {
						try entity.ClientEntityManager.addEntity(elem);
					},
					.JsonNull => {
						i += 1;
						break;
					},
					else => {
						std.log.warn("Unrecognized json parameters for protocol {}: {s}", .{id, data});
					},
				}
			}
			while(i < jsonArray.JsonArray.items.len) : (i += 1) {
				const elem = jsonArray.JsonArray.items[i];
				_ = elem;
				// TODO:
//					if(json.getArray("array") != null) {
//						Cubyz.world.itemEntityManager.loadFrom((JsonObject)json);
//					} else if(json instanceof JsonInt) {
//						Cubyz.world.itemEntityManager.remove(json.asInt(0));
//					} else if(json instanceof JsonObject) {
//						Cubyz.world.itemEntityManager.add(json);
//					}
			}
		}
		pub fn send(conn: *Connection, msg: []const u8) !void {
			conn.sendImportant(id, msg);
		}
//			TODO:
//			public void sendToClients(Entity[] currentEntities, Entity[] lastSentEntities, ItemEntityManager itemEntities) {
//				synchronized(itemEntities) {
//					byte[] data = new byte[currentEntities.length*(4 + 3*8 + 3*8 + 3*4)];
//					int offset = 0;
//					JsonArray entityChanges = new JsonArray();
//					outer:
//					for(Entity ent : currentEntities) {
//						Bits.putInt(data, offset, ent.id);
//						offset += 4;
//						Bits.putDouble(data, offset, ent.getPosition().x);
//						offset += 8;
//						Bits.putDouble(data, offset, ent.getPosition().y);
//						offset += 8;
//						Bits.putDouble(data, offset, ent.getPosition().z);
//						offset += 8;
//						Bits.putFloat(data, offset, ent.getRotation().x);
//						offset += 4;
//						Bits.putFloat(data, offset, ent.getRotation().y);
//						offset += 4;
//						Bits.putFloat(data, offset, ent.getRotation().z);
//						offset += 4;
//						Bits.putDouble(data, offset, ent.vx);
//						offset += 8;
//						Bits.putDouble(data, offset, ent.vy);
//						offset += 8;
//						Bits.putDouble(data, offset, ent.vz);
//						offset += 8;
//						for(int i = 0; i < lastSentEntities.length; i++) {
//							if(lastSentEntities[i] == ent) {
//								lastSentEntities[i] = null;
//								continue outer;
//							}
//						}
//						JsonObject entityData = new JsonObject();
//						entityData.put("id", ent.id);
//						entityData.put("type", ent.getType().getRegistryID().toString());
//						entityData.put("width", ent.width);
//						entityData.put("height", ent.height);
//						entityData.put("name", ent.name);
//						entityChanges.add(entityData);
//					}
//					assert offset == data.length;
//					for(Entity ent : lastSentEntities) {
//						if(ent != null) {
//							entityChanges.add(new JsonInt(ent.id));
//						}
//					}
//					if(!itemEntities.lastUpdates.array.isEmpty()) {
//						entityChanges.add(new JsonOthers(true, false));
//						for(JsonElement elem : itemEntities.lastUpdates.array) {
//							entityChanges.add(elem);
//						}
//						itemEntities.lastUpdates.array.clear();
//					}
//
//					if(!entityChanges.array.isEmpty()) {
//						for(User user : Server.users) {
//							if(user.receivedFirstEntityData) {
//								user.sendImportant(this, entityChanges.toString().getBytes(StandardCharsets.UTF_8));
//							}
//						}
//					}
//					for(User user : Server.users) {
//						if(!user.isConnected()) continue;
//						if(!user.receivedFirstEntityData) {
//							JsonArray fullEntityData = new JsonArray();
//							for(Entity ent : currentEntities) {
//								JsonObject entityData = new JsonObject();
//								entityData.put("id", ent.id);
//								entityData.put("type", ent.getType().getRegistryID().toString());
//								entityData.put("width", ent.width);
//								entityData.put("height", ent.height);
//								entityData.put("name", ent.name);
//								fullEntityData.add(entityData);
//							}
//							fullEntityData.add(new JsonOthers(true, false));
//							fullEntityData.add(itemEntities.store());
//							user.sendImportant(this, fullEntityData.toString().getBytes(StandardCharsets.UTF_8));
//							user.receivedFirstEntityData = true;
//						}
//						Protocols.ENTITY_POSITION.send(user, data, itemEntities.getPositionAndVelocityData());
//					}
//				}
//			}
	},
	genericUpdate: type = struct {
		const id: u8 = 9;
		const type_renderDistance: u8 = 0;
		const type_teleport: u8 = 1;
		const type_cure: u8 = 2;
		const type_inventoryAdd: u8 = 3;
		const type_inventoryFull: u8 = 4;
		const type_inventoryClear: u8 = 5;
		const type_itemStackDrop: u8 = 6;
		const type_itemStackCollect: u8 = 7;
		const type_timeAndBiome: u8 = 8;
		fn receive(conn: *Connection, data: []const u8) !void {
			switch(data[0]) {
				type_renderDistance => {
					const renderDistance = std.mem.readIntBig(i32, data[1..5]);
					const LODFactor = @bitCast(f32, std.mem.readIntBig(u32, data[5..9]));
					_ = renderDistance;
					_ = LODFactor;
					// TODO:
//					if(conn instanceof User) {
//						User user = (User)conn;
//						user.renderDistance = renderDistance;
//						user.LODFactor = LODFactor;
//					}
				},
				type_teleport => {
					game.Player.setPosBlocking(Vec3d{
						@bitCast(f64, std.mem.readIntBig(u64, data[1..9])),
						@bitCast(f64, std.mem.readIntBig(u64, data[9..17])),
						@bitCast(f64, std.mem.readIntBig(u64, data[17..25])),
					});
				},
				type_cure => {
					// TODO:
//					Cubyz.player.health = Cubyz.player.maxHealth;
//					Cubyz.player.hunger = Cubyz.player.maxHunger;
				},
				type_inventoryAdd => {
					const slot = std.mem.readIntBig(u32, data[1..5]);
					const amount = std.mem.readIntBig(u32, data[5..9]);
					_ = slot;
					_ = amount;
					// TODO:
//					((User)conn).player.getInventory().getStack(slot).add(amount);
				},
				type_inventoryFull => {
					// TODO:
//					JsonObject json = JsonParser.parseObjectFromString(new String(data, offset + 1, length - 1, StandardCharsets.UTF_8));
//					((User)conn).player.getInventory().loadFrom(json, Server.world.getCurrentRegistries());
				},
				type_inventoryClear => {
					// TODO:
//					if(conn instanceof User) {
//						Inventory inv = ((User)conn).player.getInventory();
//						for (int i = 0; i < inv.getCapacity(); i++) {
//							inv.getStack(i).clear();
//						}
//					} else {
//						Inventory inv = Cubyz.player.getInventory_AND_DONT_FORGET_TO_SEND_CHANGES_TO_THE_SERVER();
//						for (int i = 0; i < inv.getCapacity(); i++) {
//							inv.getStack(i).clear();
//						}
//						clearInventory(conn); // Needs to send changes back to server, to ensure correct order.
//					}
				},
				type_itemStackDrop => {
					// TODO:
//					JsonObject json = JsonParser.parseObjectFromString(new String(data, offset + 1, length - 1, StandardCharsets.UTF_8));
//					Item item = Item.load(json, Cubyz.world.registries);
//					if (item == null) {
//						break;
//					}
//					Server.world.drop(
//						new ItemStack(item, json.getInt("amount", 1)),
//						new Vector3d(json.getDouble("x", 0), json.getDouble("y", 0), json.getDouble("z", 0)),
//						new Vector3f(json.getFloat("dirX", 0), json.getFloat("dirY", 0), json.getFloat("dirZ", 0)),
//						json.getFloat("vel", 0),
//						Server.UPDATES_PER_SEC*5
//					);
				},
				type_itemStackCollect => {
					const jsonObject = json.parseFromString(main.threadAllocator, data[1..]);
					defer jsonObject.free(main.threadAllocator);
					const item = items.Item.init(jsonObject) catch |err| {
						std.log.err("Error {s} while collecting item {s}. Ignoring it.", .{@errorName(err), data[1..]});
						return;
					};
					game.Player.mutex.lock();
					defer game.Player.mutex.unlock();
					const remaining = game.Player.inventory__SEND_CHANGES_TO_SERVER.addItem(item, jsonObject.get(u16, "amount", 0));

					try sendInventory_full(conn, game.Player.inventory__SEND_CHANGES_TO_SERVER);
					if(remaining != 0) {
						// Couldn't collect everything → drop it again.
						try itemStackDrop(conn, ItemStack{.item=item, .amount=remaining}, game.Player.getPosBlocking(), Vec3f{0, 0, 0}, 0);
					}
				},
				type_timeAndBiome => {
					if(game.world) |world| {
						const jsonObject = json.parseFromString(main.threadAllocator, data[1..]);
						defer jsonObject.free(main.threadAllocator);
						var expectedTime = jsonObject.get(i64, "time", 0);
						var curTime = world.gameTime.load(.Monotonic);
						if(std.math.absInt(curTime -% expectedTime) catch std.math.maxInt(i64) >= 1000) {
							world.gameTime.store(expectedTime, .Monotonic);
						} else if(curTime < expectedTime) { // world.gameTime++
							while(world.gameTime.tryCompareAndSwap(curTime, curTime +% 1, .Monotonic, .Monotonic)) |actualTime| {
								curTime = actualTime;
							}
						} else { // world.gameTime--
							while(world.gameTime.tryCompareAndSwap(curTime, curTime -% 1, .Monotonic, .Monotonic)) |actualTime| {
								curTime = actualTime;
							}
						}
						// TODO:
//						world.playerBiome = world.registries.biomeRegistry.getByID(json.getString("biome", ""));
					}
				},
				else => |unrecognizedType| {
					std.log.err("Unrecognized type for genericUpdateProtocol: {}. Data: {any}", .{unrecognizedType, data});
				},
			}
		}

		fn addHeaderAndSendImportant(conn: *Connection, header: u8, data: []const u8) !void {
			const headeredData = try main.threadAllocator.alloc(u8, data.len + 1);
			defer main.threadAllocator.free(headeredData);
			headeredData[0] = header;
			std.mem.copy(u8, headeredData[1..], data);
			try conn.sendImportant(id, headeredData);
		}

		fn addHeaderAndSendUnimportant(conn: *Connection, header: u8, data: []const u8) !void {
			const headeredData = try main.threadAllocator.alloc(u8, data.len + 1);
			defer main.threadAllocator.free(headeredData);
			headeredData[0] = header;
			std.mem.copy(u8, headeredData[1..], data);
			try conn.sendUnimportant(id, headeredData);
		}

		pub fn sendRenderDistance(conn: *Connection, renderDistance: i32, LODFactor: f32) !void {
			var data: [9]u8 = undefined;
			data[0] = type_renderDistance;
			std.mem.writeIntBig(i32, data[1..5], renderDistance);
			std.mem.writeIntBig(u32, data[5..9], @bitCast(u32, LODFactor));
			try conn.sendImportant(id, &data);
		}

		pub fn sendTPCoordinates(conn: *Connection, pos: Vec3d) !void {
			var data: [1+24]u8 = undefined;
			data[0] = type_teleport;
			std.mem.writeIntBig(u64, data[1..9], @bitCast(u64, pos[0]));
			std.mem.writeIntBig(u64, data[9..17], @bitCast(u64, pos[1]));
			std.mem.writeIntBig(u64, data[17..25], @bitCast(u64, pos[2]));
			try conn.sendImportant(id, &data);
		}

		pub fn sendCure(conn: *Connection) !void {
			var data: [1]u8 = undefined;
			data[0] = type_cure;
			try conn.sendImportant(id, &data);
		}

		pub fn sendInventory_ItemStack_add(conn: *Connection, slot: u32, amount: u32) !void {
			var data: [9]u8 = undefined;
			data[0] = type_inventoryAdd;
			std.mem.writeIntBig(u32, data[1..5], slot);
			std.mem.writeIntBig(u32, data[5..9], amount);
			try conn.sendImportant(id, &data);
		}


		pub fn sendInventory_full(conn: *Connection, inv: Inventory) !void {
			const jsonObject = try inv.save(main.threadAllocator);
			defer jsonObject.free(main.threadAllocator);
			const string = try jsonObject.toString(main.threadAllocator);
			defer main.threadAllocator.free(string);
			try addHeaderAndSendImportant(conn, type_inventoryFull, string);
		}

		pub fn clearInventory(conn: *Connection) !void {
			var data: [1]u8 = undefined;
			data[0] = type_inventoryClear;
			try conn.sendImportant(id, &data);
		}

		pub fn itemStackDrop(conn: *Connection, stack: ItemStack, pos: Vec3d, dir: Vec3f, vel: f32) !void {
			var jsonObject = try stack.store(main.threadAllocator);
			defer jsonObject.free(main.threadAllocator);
			try jsonObject.put("x", pos[0]);
			try jsonObject.put("y", pos[1]);
			try jsonObject.put("z", pos[2]);
			try jsonObject.put("dirX", dir[0]);
			try jsonObject.put("dirY", dir[1]);
			try jsonObject.put("dirZ", dir[2]);
			try jsonObject.put("vel", vel);
			const string = try jsonObject.toString(main.threadAllocator);
			defer main.threadAllocator.free(string);
			try addHeaderAndSendImportant(conn, type_itemStackDrop, string);
		}

		pub fn itemStackCollect(conn: *Connection, stack: ItemStack) !void {
			var jsonObject = try stack.store(main.threadAllocator);
			defer jsonObject.free(main.threadAllocator);
			const string = try jsonObject.toString(main.threadAllocator);
			defer main.threadAllocator.free(string);
			try addHeaderAndSendImportant(conn, type_itemStackCollect, string);
		}

		// TODO:
//	public void sendTimeAndBiome(User user, ServerWorld world) {
//		JsonObject data = new JsonObject();
//		data.put("time", world.gameTime);
//		data.put("biome", world.getBiome((int)user.player.getPosition().x, (int)user.player.getPosition().y, (int)user.player.getPosition().z).getRegistryID().toString());
//		addHeaderAndSendUnimportant(user, TIME_AND_BIOME, data.toString().getBytes(StandardCharsets.UTF_8));
//	}
	},
} = .{};


pub const Connection = struct {
	const maxPacketSize: u32 = 65507; // max udp packet size
	const importantHeaderSize: u32 = 5;
	const maxImportantPacketSize: u32 = 1500 - 20 - 8; // Ethernet MTU minus IP header minus udp header

	// Statistics:
	var packetsSent: u32 = 0;
	var packetsResent: u32 = 0;

	manager: *ConnectionManager,

	gpa: std.heap.GeneralPurposeAllocator(.{}),
	allocator: std.mem.Allocator,

	remoteAddress: Address,
	bruteforcingPort: bool = false,
	bruteForcedPortRange: u16 = 0,

	streamBuffer: [maxImportantPacketSize]u8 = undefined,
	streamPosition: u32 = importantHeaderSize,
	messageID: u32 = 0,
	unconfirmedPackets: std.ArrayList(UnconfirmedPacket) = undefined,
	receivedPackets: [3]std.ArrayList(u32) = undefined,
	__lastReceivedPackets: [65536]?[]const u8 = [_]?[]const u8{null} ** 65536, // TODO: Wait for #12215 fix.
	lastReceivedPackets: []?[]const u8, // TODO: Wait for #12215 fix.
	lastIndex: u32 = 0,

	lastIncompletePacket: u32 = 0,

	lastKeepAliveSent: u32 = 0,
	lastKeepAliveReceived: u32 = 0,
	otherKeepAliveReceived: u32 = 0,

	disconnected: bool = false,
	handShakeState: u8 = Protocols.handShake.stepStart,
	handShakeWaiting: std.Thread.Condition = std.Thread.Condition{},
	lastConnection: i64,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},

	pub fn init(manager: *ConnectionManager, ipPort: []const u8) !*Connection {
		var gpa = std.heap.GeneralPurposeAllocator(.{}){};
		var result: *Connection = try gpa.allocator().create(Connection);
		result.* = Connection {
			.manager = manager,
			.gpa = gpa,
			.allocator = undefined,
			.remoteAddress = undefined,
			.lastConnection = std.time.milliTimestamp(),
			.lastReceivedPackets = &result.__lastReceivedPackets, // TODO: Wait for #12215 fix.
		};
		result.allocator = result.gpa.allocator(); // The right reference(the one that isn't on the stack) needs to be used passed!
		result.unconfirmedPackets = std.ArrayList(UnconfirmedPacket).init(result.allocator);
		result.receivedPackets = [3]std.ArrayList(u32){
			std.ArrayList(u32).init(result.allocator),
			std.ArrayList(u32).init(result.allocator),
			std.ArrayList(u32).init(result.allocator),
		};
		var splitter = std.mem.split(u8, ipPort, ":");
		var nullTerminatedIP = try main.threadAllocator.dupeZ(u8, splitter.first());
		defer main.threadAllocator.free(nullTerminatedIP);
		result.remoteAddress.ip = Socket.resolveIP(nullTerminatedIP);
		var port = splitter.rest();
		if(port.len != 0 and port[0] == '?') {
			result.remoteAddress.isSymmetricNAT = true;
			result.bruteforcingPort = true;
			port = port[1..];
		}
		result.remoteAddress.port = std.fmt.parseUnsigned(u16, port, 10) catch blk: {
			std.log.warn("Could not parse port \"{s}\". Using default port instead.", .{port});
			break :blk settings.defaultPort;
		};

		try result.manager.addConnection(result);
		return result;
	}

	pub fn deinit(self: *Connection) void {
		self.disconnect() catch |err| {std.log.warn("Error while disconnecting: {s}", .{@errorName(err)});};
		self.manager.finishCurrentReceive(); // Wait until all currently received packets are done.
		for(self.unconfirmedPackets.items) |packet| {
			self.allocator.free(packet.data);
		}
		self.unconfirmedPackets.deinit();
		self.receivedPackets[0].deinit();
		self.receivedPackets[1].deinit();
		self.receivedPackets[2].deinit();
		for(self.lastReceivedPackets) |nullablePacket| {
			if(nullablePacket) |packet| {
				self.allocator.free(packet);
			}
		}
		var gpa = self.gpa;
		gpa.allocator().destroy(self);
		if(gpa.deinit()) {
			@panic("Memory leak in connection.");
		}
	}

	fn flush(self: *Connection) !void {
		if(self.streamPosition == importantHeaderSize) return; // Don't send empty packets.
		// Fill the header:
		self.streamBuffer[0] = Protocols.important;
		var id = self.messageID;
		self.messageID += 1;
		std.mem.writeIntBig(u32, self.streamBuffer[1..5], id); // TODO: Use little endian for better hardware support. Currently the aim is interoperability with the java version which uses big endian.

		var packet = UnconfirmedPacket{
			.data = try self.allocator.dupe(u8, self.streamBuffer[0..self.streamPosition]),
			.lastKeepAliveSentBefore = self.lastKeepAliveSent,
			.id = id,
		};
		try self.unconfirmedPackets.append(packet);
		packetsSent += 1;
		try self.manager.send(packet.data, self.remoteAddress);
		self.streamPosition = importantHeaderSize;
	}

	fn writeByteToStream(self: *Connection, data: u8) !void {
		self.streamBuffer[self.streamPosition] = data;
		self.streamPosition += 1;
		if(self.streamPosition == self.streamBuffer.len) {
			try self.flush();
		}
	}

	pub fn sendImportant(self: *Connection, id: u8, data: []const u8) !void {
		self.mutex.lock();
		defer self.mutex.unlock();

		if(self.disconnected) return;
		try self.writeByteToStream(id);
		var processedLength = data.len;
		while(processedLength > 0x7f) {
			try self.writeByteToStream(@intCast(u8, processedLength & 0x7f) | 0x80);
			processedLength >>= 7;
		}
		try self.writeByteToStream(@intCast(u8, processedLength & 0x7f));

		var remaining: []const u8 = data;
		while(remaining.len != 0) {
			var copyableSize = @min(remaining.len, self.streamBuffer.len - self.streamPosition);
			std.mem.copy(u8, self.streamBuffer[self.streamPosition..], remaining[0..copyableSize]);
			remaining = remaining[copyableSize..];
			self.streamPosition += @intCast(u32, copyableSize);
			if(self.streamPosition == self.streamBuffer.len) {
				try self.flush();
			}
		}
	}

	pub fn sendUnimportant(self: *Connection, id: u8, data: []const u8) !void {
		self.mutex.lock();
		defer self.mutex.unlock();

		if(self.disconnected) return;
		std.debug.assert(data.len + 1 < maxPacketSize);
		var fullData = try main.threadAllocator.alloc(u8, data.len + 1);
		defer main.threadAllocator.free(fullData);
		fullData[0] = id;
		std.mem.copy(u8, fullData[1..], data);
		try self.manager.send(fullData, self.remoteAddress);
	}

	fn receiveKeepAlive(self: *Connection, data: []const u8) void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		self.mutex.lock();
		defer self.mutex.unlock();

		self.otherKeepAliveReceived = std.mem.readIntBig(u32, data[0..4]);
		self.lastKeepAliveReceived = std.mem.readIntBig(u32, data[4..8]);
		var remaining: []const u8 = data[8..];
		while(remaining.len >= 8) {
			var start = std.mem.readIntBig(u32, remaining[0..4]);
			var len = std.mem.readIntBig(u32, remaining[4..8]);
			remaining = remaining[8..];
			var j: usize = 0;
			while(j < self.unconfirmedPackets.items.len) {
				var diff = self.unconfirmedPackets.items[j].id -% start;
				if(diff < len) {
					self.allocator.free(self.unconfirmedPackets.items[j].data);
					_ = self.unconfirmedPackets.swapRemove(j);
				} else {
					j += 1;
				}
			}
		}
	}

	fn sendKeepAlive(self: *Connection) !void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		self.mutex.lock();
		defer self.mutex.unlock();

		var runLengthEncodingStarts: std.ArrayList(u32) = std.ArrayList(u32).init(main.threadAllocator);
		defer runLengthEncodingStarts.deinit();
		var runLengthEncodingLengths: std.ArrayList(u32) = std.ArrayList(u32).init(main.threadAllocator);
		defer runLengthEncodingLengths.deinit();

		for(self.receivedPackets) |list| {
			for(list.items) |packetID| {
				var leftRegion: ?u32 = null;
				var rightRegion: ?u32 = null;
				for(runLengthEncodingStarts.items) |start, reg| {
					var diff = packetID -% start;
					if(diff < runLengthEncodingLengths.items[reg]) continue;
					if(diff == runLengthEncodingLengths.items[reg]) {
						leftRegion = @intCast(u32, reg);
					}
					if(diff == std.math.maxInt(u32)) {
						rightRegion = @intCast(u32, reg);
					}
				}
				if(leftRegion) |left| {
					if(rightRegion) |right| {
						// Needs to combine the regions:
						runLengthEncodingLengths.items[left] += runLengthEncodingLengths.items[right] + 1;
						_ = runLengthEncodingStarts.swapRemove(right);
						_ = runLengthEncodingLengths.swapRemove(right);
					} else {
						runLengthEncodingLengths.items[left] += 1;
					}
				} else if(rightRegion) |right| {
					runLengthEncodingStarts.items[right] -= 1;
					runLengthEncodingLengths.items[right] += 1;
				} else {
					try runLengthEncodingStarts.append(packetID);
					try runLengthEncodingLengths.append(1);
				}
			}
		}
		{ // Cycle the receivedPackets lists:
			var putBackToFront: std.ArrayList(u32) = self.receivedPackets[self.receivedPackets.len - 1];
			var i: u32 = self.receivedPackets.len - 1;
			while(i >= 1): (i -= 1) {
				self.receivedPackets[i] = self.receivedPackets[i-1];
			}
			self.receivedPackets[0] = putBackToFront;
			self.receivedPackets[0].clearRetainingCapacity();
		}
		var output = try main.threadAllocator.alloc(u8, runLengthEncodingStarts.items.len*8 + 9);
		defer main.threadAllocator.free(output);
		output[0] = Protocols.keepAlive;
		std.mem.writeIntBig(u32, output[1..5], self.lastKeepAliveSent);
		self.lastKeepAliveSent += 1;
		std.mem.writeIntBig(u32, output[5..9], self.otherKeepAliveReceived);
		var remaining: []u8 = output[9..];
		for(runLengthEncodingStarts.items) |_, i| {
			std.mem.writeIntBig(u32, remaining[0..4], runLengthEncodingStarts.items[i]);
			std.mem.writeIntBig(u32, remaining[4..8], runLengthEncodingLengths.items[i]);
			remaining = remaining[8..];
		}
		try self.manager.send(output, self.remoteAddress);

		// Resend packets that didn't receive confirmation within the last 2 keep-alive signals.
		for(self.unconfirmedPackets.items) |*packet| {
			if(self.lastKeepAliveReceived -% @as(i33, packet.lastKeepAliveSentBefore) >= 2) {
				packetsSent += 1;
				packetsResent += 1;
				try self.manager.send(packet.data, self.remoteAddress);
				packet.lastKeepAliveSentBefore = self.lastKeepAliveSent;
			}
		}
		try self.flush();
		if(self.bruteforcingPort) {
			// This is called every 100 ms, so if I send 10 requests it shouldn't be too bad.
			var i: u16 = 0;
			while(i < 5): (i += 1) {
				var data = [1]u8{0};
				if(self.remoteAddress.port +% self.bruteForcedPortRange != 0) {
					try self.manager.send(&data, Address{.ip = self.remoteAddress.ip, .port = self.remoteAddress.port +% self.bruteForcedPortRange});
				}
				if(self.remoteAddress.port - self.bruteForcedPortRange != 0) {
					try self.manager.send(&data, Address{.ip = self.remoteAddress.ip, .port = self.remoteAddress.port -% self.bruteForcedPortRange});
				}
				self.bruteForcedPortRange +%= 1;
			}
		}
	}

	pub fn isConnected(self: *Connection) bool {
		self.mutex.lock();
		defer self.mutex.unlock();

		return self.otherKeepAliveReceived != 0;
	}

	fn collectPackets(self: *Connection) !void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		while(true) {
			var id = self.lastIncompletePacket;
			var receivedPacket = self.lastReceivedPackets[id & 65535] orelse return;
			var newIndex = self.lastIndex;
			var protocol = receivedPacket[newIndex];
			newIndex += 1;
			if(game.world == null and protocol != Protocols.handShake.id)
				return;

			// Determine the next packet length:
			var len: u32 = 0;
			var shift: u5 = 0;
			while(true) {
				if(newIndex == receivedPacket.len) {
					newIndex = 0;
					id += 1;
					receivedPacket = self.lastReceivedPackets[id & 65535] orelse return;
				}
				var nextByte = receivedPacket[newIndex];
				newIndex += 1;
				len |= @intCast(u32, nextByte & 0x7f) << shift;
				if(nextByte & 0x80 != 0) {
					shift += 7;
				} else {
					break;
				}
			}

			// Check if there is enough data available to fill the packets needs:
			var dataAvailable = receivedPacket.len - newIndex;
			var idd = id + 1;
			while(dataAvailable < len): (idd += 1) {
				var otherPacket = self.lastReceivedPackets[idd & 65535] orelse return;
				dataAvailable += otherPacket.len;
			}

			// Copy the data to an array:
			var data = try main.threadAllocator.alloc(u8, len);
			defer main.threadAllocator.free(data);
			var remaining = data[0..];
			while(remaining.len != 0) {
				dataAvailable = @min(self.lastReceivedPackets[id & 65535].?.len - newIndex, remaining.len);
				std.mem.copy(u8, remaining, self.lastReceivedPackets[id & 65535].?[newIndex..newIndex + dataAvailable]);
				newIndex += @intCast(u32, dataAvailable);
				remaining = remaining[dataAvailable..];
				if(newIndex == self.lastReceivedPackets[id & 65535].?.len) {
					id += 1;
					newIndex = 0;
				}
			}
			while(self.lastIncompletePacket != id): (self.lastIncompletePacket += 1) {
				self.allocator.free(self.lastReceivedPackets[self.lastIncompletePacket & 65535].?);
				self.lastReceivedPackets[self.lastIncompletePacket & 65535] = null;
			}
			self.lastIndex = newIndex;
			bytesReceived[protocol] += data.len + 1 + (7 + std.math.log2_int(usize, 1 + data.len))/7;
			if(Protocols.list[protocol]) |prot| {
				try prot(self, data);
			} else {
				std.log.warn("Received unknown important protocol width id {}", .{protocol});
			}
		}
	}

	pub fn receive(self: *Connection, data: []const u8) !void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		const protocol = data[0];
		if(self.handShakeState != Protocols.handShake.stepComplete and protocol != Protocols.handShake.id and protocol != Protocols.keepAlive and protocol != Protocols.important) {
			return; // Reject all non-handshake packets until the handshake is done.
		}
		self.lastConnection = std.time.milliTimestamp();
		bytesReceived[protocol] += data.len + 20 + 8; // Including IP header and udp header;
		packetsReceived[protocol] += 1;
		if(protocol == Protocols.important) {
			var id = std.mem.readIntBig(u32, data[1..5]);
			if(self.handShakeState == Protocols.handShake.stepComplete and id == 0) { // Got a new "first" packet from client. So the client tries to reconnect, but we still think it's connected.
				// TODO:
//				if(this instanceof User) {
//					Server.disconnect((User)this);
//					disconnected = true;
//					manager.removeConnection(this);
//					new Thread(() -> {
//						try {
//							Server.connect(new User(manager, remoteAddress.getHostAddress() + ":" + remotePort));
//						} catch(Throwable e) {
//							Logger.error(e);
//						}
//					}).start();
//					return;
//				} else {
//					Logger.error("Server 'reconnected'? This makes no sense and the game can't handle that.");
//				}
			}
			if(id - @as(i33, self.lastIncompletePacket) >= 65536) {
				std.log.warn("Many incomplete packages. Cannot process any more packages for now.", .{});
				return;
			}
			try self.receivedPackets[0].append(id);
			if(id < self.lastIncompletePacket or self.lastReceivedPackets[id & 65535] != null) {
				return; // Already received the package in the past.
			}
			self.lastReceivedPackets[id & 65535] = try self.allocator.dupe(u8, data[importantHeaderSize..]);
			// Check if a message got completed:
			try self.collectPackets();
		} else if(protocol == Protocols.keepAlive) {
			self.receiveKeepAlive(data[1..]);
		} else {
			if(Protocols.list[protocol]) |prot| {
				try prot(self, data[1..]);
			} else {
				std.log.warn("Received unknown protocol width id {}", .{protocol});
			}
		}
	}

	pub fn disconnect(self: *Connection) !void {
		// Send 3 disconnect packages to the other side, just to be sure.
		// If all of them don't get through then there is probably a network issue anyways which would lead to a timeout.
		try Protocols.disconnect.disconnect(self);
		std.time.sleep(10000000);
		try Protocols.disconnect.disconnect(self);
		std.time.sleep(10000000);
		try Protocols.disconnect.disconnect(self);
		self.disconnected = true;
		self.manager.removeConnection(self);
		std.log.info("Disconnected", .{});
	}
};