const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const assets = @import("assets.zig");
const Block = @import("blocks.zig").Block;
const chunk = @import("chunk.zig");
const entity = @import("entity.zig");
const items = @import("items.zig");
const Inventory = items.Inventory;
const ItemStack = items.ItemStack;
const JsonElement = @import("json.zig").JsonElement;
const main = @import("main.zig");
const game = @import("game.zig");
const settings = @import("settings.zig");
const renderer = @import("renderer.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;

//TODO: Might want to use SSL or something similar to encode the message

const Socket = struct {
	const os = std.os;
	socketID: os.socket_t,

	fn startup() !void {
		if(builtin.os.tag == .windows) {
			_ = try os.windows.WSAStartup(2, 2);
		}
	}

	fn init(localPort: u16) !Socket {
		var self = Socket {
			.socketID = try os.socket(os.AF.INET, os.SOCK.DGRAM, os.IPPROTO.UDP),
		};
		errdefer self.deinit();
		const bindingAddr = os.sockaddr.in {
			.port = @byteSwap(localPort),
			.addr = 0,
		};
		try os.bind(self.socketID, @ptrCast(*const os.sockaddr, &bindingAddr), @sizeOf(os.sockaddr.in));
		return self;
	}

	fn deinit(self: Socket) void {
		os.closeSocket(self.socketID);
	}

	fn send(self: Socket, data: []const u8, destination: Address) !void {
		const addr = os.sockaddr.in {
			.port = @byteSwap(destination.port),
			.addr = destination.ip,
		};
		std.debug.assert(data.len == os.sendto(self.socketID, data, 0, @ptrCast(*const os.sockaddr, &addr), @sizeOf(os.sockaddr.in)) catch |err| {
			std.log.info("Got error while sending to {}: {s}", .{destination, @errorName(err)});
			return;
		});
	}

	fn receive(self: Socket, buffer: []u8, timeout: i32, resultAddress: *Address) ![]u8 {
		if(builtin.os.tag == .windows) { // Of course Windows always has it's own special thing.
			var pfd = [1]os.pollfd {
				.{.fd = self.socketID, .events = std.c.POLL.RDNORM | std.c.POLL.RDBAND, .revents = undefined},
			};
			const length = os.windows.ws2_32.WSAPoll(&pfd, pfd.len, timeout); // TODO: #16122
			if (length == os.windows.ws2_32.SOCKET_ERROR) {
                switch (os.windows.ws2_32.WSAGetLastError()) {
                    .WSANOTINITIALISED => unreachable,
                    .WSAENETDOWN => return error.NetworkSubsystemFailed,
                    .WSAENOBUFS => return error.SystemResources,
                    // TODO: handle more errors
                    else => |err| return os.windows.unexpectedWSAError(err),
                }
            } else if(length == 0) {
                return error.Timeout;
            }
		} else {
			var pfd = [1]os.pollfd {
				.{.fd = self.socketID, .events = os.POLL.IN, .revents = undefined},
			};
			const length = try os.poll(&pfd, timeout);
			if(length == 0) return error.Timeout; return error.Timeout;
		}
		var addr: os.sockaddr.in = undefined;
		var addrLen: os.socklen_t = @sizeOf(os.sockaddr.in);
		const length = try os.recvfrom(self.socketID, buffer, 0,  @ptrCast(*os.sockaddr, &addr), &addrLen);
		resultAddress.ip = addr.addr;
		resultAddress.port = @byteSwap(addr.port);
		return buffer[0..length];
	}

	fn resolveIP(addr: []const u8) !u32 {
		const list = try std.net.getAddressList(main.threadAllocator, addr, settings.defaultPort);
		defer list.deinit();
		return list.addrs[0].in.sa.addr;
	}
};

pub fn init() !void {
	try Socket.startup();
	inline for(@typeInfo(Protocols).Struct.decls) |decl| {
		if(@TypeOf(@field(Protocols, decl.name)) == type) {
			const id = @field(Protocols, decl.name).id;
			if(id != Protocols.keepAlive and id != Protocols.important and Protocols.list[id] == null) {
				Protocols.list[id] = @field(Protocols, decl.name).receive;
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

	pub fn format(self: Address, _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
		try writer.print("{}.{}.{}.{}:{}", .{self.ip & 255, self.ip >> 8 & 255, self.ip >> 16 & 255, self.ip >> 24, self.port});
	}
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
		var seed = [_]u8 {0} ** std.rand.DefaultCsprng.secret_seed_length;
		std.mem.writeIntNative(i128, seed[0..16], std.time.nanoTimestamp()); // Not the best seed, but it's not that important.
		var random = std.rand.DefaultCsprng.init(seed);
		for(0..16) |attempt| {
			_ = attempt;
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
			const ip = splitter.first();
			var serverAddress = Address {
				.ip=Socket.resolveIP(ip) catch |err| {
					std.log.err("Cannot resolve stun server address: {s}, error: {s}", .{ip, @errorName(err)});
					continue;
				},
				.port=std.fmt.parseUnsigned(u16, splitter.rest(), 10) catch 3478
			};
			if(connection.sendRequest(main.globalAllocator, &data, serverAddress, 500*1000000) catch |err| {
				std.log.warn("Encountered error: {s} while connecting to STUN server: {s}", .{@errorName(err), server});
				continue;
			}) |answer| {
				defer main.globalAllocator.free(answer);
				verifyHeader(answer, data[8..20]) catch |err| {
					std.log.warn("Header verification failed with {s} for STUN server: {s} data: {any}", .{@errorName(err), server, answer});
					continue;
				};
				var result = findIPPort(answer) catch |err| {
					std.log.warn("Could not parse IP+Port: {s} for STUN server: {s} data: {any}", .{@errorName(err), server, answer});
					continue;
				};
				if(oldAddress) |other| {
					std.log.info("{}", .{result});
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
		return Address{.ip=Socket.resolveIP("127.0.0.1") catch unreachable, .port=settings.defaultPort}; // TODO: Return ip address in LAN.
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
						var addressData: [6]u8 = data[2..8].*;
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
		for(MAGIC_COOKIE, 0..) |cookie, i| {
			if(data[i + 4] != cookie) return error.WrongCookie;
		}
		for(transactionID, 0..) |_, i| {
			if(data[i+8] != transactionID[i]) return error.WrongTransaction;
		}
	}
};

pub const ConnectionManager = struct {
	socket: Socket = undefined,
	thread: std.Thread = undefined,
	threadId: std.Thread.Id = undefined,
	externalAddress: Address = undefined,
	online: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
	running: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(true),

	connections: std.ArrayList(*Connection) = undefined,
	requests: std.ArrayList(*Request) = undefined,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},
	waitingToFinishReceive: std.Thread.Condition = std.Thread.Condition{},

	receiveBuffer: [Connection.maxPacketSize]u8 = undefined,

	world: ?*game.World = null,

	pub fn init(localPort: u16, online: bool) !*ConnectionManager {
		var result: *ConnectionManager = try main.globalAllocator.create(ConnectionManager);
		result.* = .{};
		result.connections = std.ArrayList(*Connection).init(main.globalAllocator);
		result.requests = std.ArrayList(*Request).init(main.globalAllocator);

		result.socket = Socket.init(localPort) catch |err| blk: {
			if(err == error.AddressInUse) {
				break :blk try Socket.init(0); // Use any port.
			} else return err;
		};
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

		main.globalAllocator.destroy(self);
	}

	pub fn makeOnline(self: *ConnectionManager) void {
		if(!self.online.load(.Acquire)) {
			self.externalAddress = STUN.requestAddress(self);
			self.online.store(true, .Release);
		}
	}

	pub fn send(self: *ConnectionManager, data: []const u8, target: Address) Allocator.Error!void {
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

			for(self.requests.items, 0..) |req, i| {
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
			if(allocator.ptr == main.globalAllocator.ptr) {
				return request.data;
			} else {
				var result = try allocator.dupe(u8, request.data);
				main.globalAllocator.free(request.data);
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
		
		for(self.connections.items, 0..) |other, i| {
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
				request.data = try main.globalAllocator.dupe(u8, data);
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
		defer if(gpa.deinit() == .leak) {
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
pub const Protocols = struct {
	pub var list: [256]?*const fn(*Connection, []const u8) anyerror!void = [_]?*const fn(*Connection, []const u8) anyerror!void {null} ** 256;

	pub const keepAlive: u8 = 0;
	pub const important: u8 = 0xff;
	pub const handShake = struct {
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
						const json = JsonElement.parseFromString(main.threadAllocator, data[1..]);
						defer json.free(main.threadAllocator);
						const name = json.get([]const u8, "name", "unnamed");
						const version = json.get([]const u8, "version", "unknown");
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
							try conn.sendImportant(id, arrayList.items);
							try conn.flush();
						}

						// TODO:
						try conn.user.?.initPlayer(name);
						const jsonObject = try JsonElement.initObject(main.threadAllocator);
						defer jsonObject.free(main.threadAllocator);
						try jsonObject.put("player", try conn.user.?.player.save(main.threadAllocator));
						// TODO:
//					jsonObject.put("player_id", ((User)conn).player.id);
//					jsonObject.put("blockPalette", Server.world.blockPalette.save());
						const spawn = try JsonElement.initObject(main.threadAllocator);
						try spawn.put("x", main.server.world.?.spawn[0]);
						try spawn.put("y", main.server.world.?.spawn[1]);
						try spawn.put("z", main.server.world.?.spawn[2]);
						try jsonObject.put("spawn", spawn);
						
						const outData = try jsonObject.toStringEfficient(main.threadAllocator, &[1]u8{stepServerData});
						defer main.threadAllocator.free(outData);
						try conn.sendImportant(id, outData);
						conn.handShakeState = stepServerData;
						conn.handShakeState = stepComplete;
						// TODO:
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
						var json = JsonElement.parseFromString(main.threadAllocator, data[1..]);
						defer json.free(main.threadAllocator);
						try conn.manager.world.?.finishHandshake(json);
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
			try jsonObject.putOwnedString("version", settings.version);
			try jsonObject.putOwnedString("name", name);
			var prefix = [1]u8 {stepUserData};
			var data = try jsonObject.toStringEfficient(main.threadAllocator, &prefix);
			defer main.threadAllocator.free(data);
			try conn.sendImportant(id, data);

			conn.mutex.lock();
			conn.handShakeWaiting.wait(&conn.mutex);
			conn.mutex.unlock();
		}
	};
	pub const chunkRequest = struct {
		const id: u8 = 2;
		fn receive(conn: *Connection, data: []const u8) !void {
			var remaining = data[0..];
			while(remaining.len >= 16) {
				const request = chunk.ChunkPosition{
					.wx = std.mem.readIntBig(i32, remaining[0..4]),
					.wy = std.mem.readIntBig(i32, remaining[4..8]),
					.wz = std.mem.readIntBig(i32, remaining[8..12]),
					.voxelSize = @intCast(u31, std.mem.readIntBig(i32, remaining[12..16])),
				};
				if(conn.user) |user| {
					try main.server.world.?.queueChunk(request, user);
				}
				remaining = remaining[16..];
			}
		}
		pub fn sendRequest(conn: *Connection, requests: []chunk.ChunkPosition) !void {
			if(requests.len == 0) return;
			var data = try main.threadAllocator.alloc(u8, 16*requests.len);
			defer main.threadAllocator.free(data);
			var remaining = data;
			for(requests) |req| {
				std.mem.writeIntBig(i32, remaining[0..4], req.wx);
				std.mem.writeIntBig(i32, remaining[4..8], req.wy);
				std.mem.writeIntBig(i32, remaining[8..12], req.wz);
				std.mem.writeIntBig(i32, remaining[12..16], req.voxelSize);
				remaining = remaining[16..];
			}
			try conn.sendImportant(id, data);
		}
	};
	pub const chunkTransmission = struct {
		const id: u8 = 3;
		fn receive(_: *Connection, _data: []const u8) !void {
			var data = _data;
			var pos = chunk.ChunkPosition{
				.wx = std.mem.readIntBig(i32, data[0..4]),
				.wy = std.mem.readIntBig(i32, data[4..8]),
				.wz = std.mem.readIntBig(i32, data[8..12]),
				.voxelSize = @intCast(u31, std.mem.readIntBig(i32, data[12..16])),
			};
			const _inflatedData = try main.threadAllocator.alloc(u8, chunk.chunkVolume*4);
			defer main.threadAllocator.free(_inflatedData);
			const _inflatedLen = try utils.Compression.inflateTo(_inflatedData, data[16..]);
			if(_inflatedLen != chunk.chunkVolume*4) {
				std.log.err("Transmission of chunk has invalid size: {}. Input data: {any}, After inflate: {any}", .{_inflatedLen, data, _inflatedData[0.._inflatedLen]});
			}
			data = _inflatedData;
			var ch = try main.globalAllocator.create(chunk.Chunk);
			ch.init(pos);
			for(&ch.blocks) |*block| {
				block.* = Block.fromInt(std.mem.readIntBig(u32, data[0..4]));
				data = data[4..];
			}
			try renderer.RenderStructure.updateChunkMesh(ch);
		}
		pub fn sendChunk(conn: *Connection, ch: *chunk.Chunk) Allocator.Error!void {
			var uncompressedData: [@sizeOf(@TypeOf(ch.blocks))]u8 = undefined; // TODO: #15280
			for(&ch.blocks, 0..) |*block, i| {
				std.mem.writeIntBig(u32, uncompressedData[4*i..][0..4], block.toInt());
			}
			const compressedData = try utils.Compression.deflate(main.threadAllocator, &uncompressedData);
			defer main.threadAllocator.free(compressedData);
			const data =try  main.threadAllocator.alloc(u8, 16 + compressedData.len);
			defer main.threadAllocator.free(data);
			@memcpy(data[16..], compressedData);
			std.mem.writeIntBig(i32, data[0..4], ch.pos.wx);
			std.mem.writeIntBig(i32, data[4..8], ch.pos.wy);
			std.mem.writeIntBig(i32, data[8..12], ch.pos.wz);
			std.mem.writeIntBig(i32, data[12..16], ch.pos.voxelSize);
			try conn.sendImportant(id, data);
		}
	};
	pub const playerPosition = struct {
		const id: u8 = 4;
		fn receive(conn: *Connection, data: []const u8) !void {
			conn.user.?.receiveData(data);
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
	};
	pub const disconnect = struct {
		const id: u8 = 5;
		fn receive(conn: *Connection, _: []const u8) !void {
			try conn.disconnect();
		}
		pub fn disconnect(conn: *Connection) !void {
			const noData = [0]u8 {};
			try conn.sendUnimportant(id, &noData);
		}
	};
	pub const entityPosition = struct {
		const id: u8 = 6;
		const type_entity: u8 = 0;
		const type_item: u8 = 1;
		fn receive(conn: *Connection, data: []const u8) !void {
			if(conn.manager.world) |world| {
				const time = std.mem.readIntBig(i16, data[1..3]);
				if(data[0] == type_entity) {
					try main.entity.ClientEntityManager.serverUpdate(time, data[3..]);
				} else if(data[0] == type_item) {
					world.itemDrops.readPosition(data[3..], time);
				}
			}
		}
		pub fn send(conn: *Connection, entityData: []const u8, itemData: []const u8) !void {
			const fullEntityData = main.threadAllocator.alloc(u8, entityData.len + 3);
			defer main.threadAllocator.free(fullEntityData);
			fullEntityData[0] = type_entity;
			std.mem.writeIntBig(i16, fullEntityData[1..3], @truncate(i16, std.time.milliTimestamp()));
			@memcpy(fullEntityData[3..], entityData);
			conn.sendUnimportant(id, fullEntityData);

			const fullItemData = main.threadAllocator.alloc(u8, itemData.len + 3);
			defer main.threadAllocator.free(fullItemData);
			fullItemData[0] = type_item;
			std.mem.writeIntBig(i16, fullItemData[1..3], @truncate(i16, std.time.milliTimestamp()));
			@memcpy(fullItemData[3..], itemData);
			conn.sendUnimportant(id, fullItemData);
		}
	};
	pub const blockUpdate = struct {
		const id: u8 = 7;
		fn receive(_: *Connection, data: []const u8) !void {
			var x = std.mem.readIntBig(i32, data[0..4]);
			var y = std.mem.readIntBig(i32, data[4..8]);
			var z = std.mem.readIntBig(i32, data[8..12]);
			var newBlock = Block.fromInt(std.mem.readIntBig(u32, data[12..16]));
			try renderer.RenderStructure.updateBlock(x, y, z, newBlock);
			// TODO:
//		if(conn instanceof User) {
//			Server.world.updateBlock(x, y, z, newBlock);
//		} else {
//			Cubyz.world.remoteUpdateBlock(x, y, z, newBlock);
//		}
		}
		pub fn send(conn: *Connection, x: i32, y: i32, z: i32, newBlock: Block) !void {
			var data: [16]u8 = undefined;
			std.mem.writeIntBig(i32, data[0..4], x);
			std.mem.writeIntBig(i32, data[4..8], y);
			std.mem.writeIntBig(i32, data[8..12], z);
			std.mem.writeIntBig(u32, data[12..16], newBlock.toInt());
			try conn.sendImportant(id, &data);
		}
	};
	pub const entity = struct {
		const id: u8 = 8;
		fn receive(conn: *Connection, data: []const u8) !void {
			const jsonArray = JsonElement.parseFromString(main.threadAllocator, data);
			defer jsonArray.free(main.threadAllocator);
			var i: u32 = 0;
			while(i < jsonArray.JsonArray.items.len) : (i += 1) {
				const elem = jsonArray.JsonArray.items[i];
				switch(elem) {
					.JsonInt => {
						main.entity.ClientEntityManager.removeEntity(elem.as(u32, 0));
					},
					.JsonObject => {
						try main.entity.ClientEntityManager.addEntity(elem);
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
				const elem: JsonElement = jsonArray.JsonArray.items[i];
				if(elem == .JsonInt) {
					conn.manager.world.?.itemDrops.remove(elem.as(u16, 0));
				} else if(!elem.getChild("array").isNull()) {
					try conn.manager.world.?.itemDrops.loadFrom(elem);
				} else {
					try conn.manager.world.?.itemDrops.addFromJson(elem);
				}
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
	};
	pub const genericUpdate = struct {
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
					const lodFactor = @bitCast(f32, std.mem.readIntBig(u32, data[5..9]));
					if(conn.user) |user| {
						user.renderDistance = @intCast(u16, renderDistance); // TODO: Update the protocol to use u16.
						user.lodFactor = lodFactor;
					}
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
					const json = JsonElement.parseFromString(main.threadAllocator, data[1..]);
					defer json.free(main.threadAllocator);
					const item = items.Item.init(json) catch |err| {
						std.log.err("Error {s} while collecting item {s}. Ignoring it.", .{@errorName(err), data[1..]});
						return;
					};
					game.Player.mutex.lock();
					defer game.Player.mutex.unlock();
					const remaining = game.Player.inventory__SEND_CHANGES_TO_SERVER.addItem(item, json.get(u16, "amount", 0));

					try sendInventory_full(conn, game.Player.inventory__SEND_CHANGES_TO_SERVER);
					if(remaining != 0) {
						// Couldn't collect everything → drop it again.
						try itemStackDrop(conn, ItemStack{.item=item, .amount=remaining}, game.Player.super.pos, Vec3f{0, 0, 0}, 0);
					}
				},
				type_timeAndBiome => {
					if(conn.manager.world) |world| {
						const json = JsonElement.parseFromString(main.threadAllocator, data[1..]);
						defer json.free(main.threadAllocator);
						var expectedTime = json.get(i64, "time", 0);
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
						world.playerBiome = main.server.terrain.biomes.getById(json.get([]const u8, "biome", ""));
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
			@memcpy(headeredData[1..], data);
			try conn.sendImportant(id, headeredData);
		}

		fn addHeaderAndSendUnimportant(conn: *Connection, header: u8, data: []const u8) !void {
			const headeredData = try main.threadAllocator.alloc(u8, data.len + 1);
			defer main.threadAllocator.free(headeredData);
			headeredData[0] = header;
			@memcpy(headeredData[1..], data);
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

		pub fn sendInventory_ItemStack_add(conn: *Connection, slot: u32, amount: i32) !void {
			var data: [9]u8 = undefined;
			data[0] = type_inventoryAdd;
			std.mem.writeIntBig(u32, data[1..5], slot);
			std.mem.writeIntBig(u32, data[5..9], amount);
			try conn.sendImportant(id, &data);
		}


		pub fn sendInventory_full(conn: *Connection, inv: Inventory) !void {
			const json = try inv.save(main.threadAllocator);
			defer json.free(main.threadAllocator);
			const string = try json.toString(main.threadAllocator);
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
			var json = try stack.store(main.threadAllocator);
			defer json.free(main.threadAllocator);
			const string = try json.toString(main.threadAllocator);
			defer main.threadAllocator.free(string);
			try addHeaderAndSendImportant(conn, type_itemStackCollect, string);
		}

		pub fn sendTimeAndBiome(conn: *Connection, world: *const main.server.ServerWorld) !void {
			var json = try JsonElement.initObject(main.threadAllocator);
			defer json.free(main.threadAllocator);
			try json.put("time", world.gameTime);
			// TODO: json.put("biome", world.getBiome((int)user.player.getPosition().x, (int)user.player.getPosition().y, (int)user.player.getPosition().z).getRegistryID().toString());
			const string = try json.toString(main.threadAllocator);
			defer main.threadAllocator.free(string);
			try addHeaderAndSendUnimportant(conn, type_timeAndBiome, string);
		}
	};
	pub const chat = struct {
		const id: u8 = 10;
		fn receive(conn: *Connection, data: []const u8) !void {
			if(conn.user) |user| {
				if(data[0] == '/') {
					// TODO:
					// CommandExecutor.execute(data, user);
				} else {
					const newMessage = try std.fmt.allocPrint(main.threadAllocator, "[{s}#ffffff]{s}", .{user.name, data});
					defer main.threadAllocator.free(newMessage);
					main.server.mutex.lock();
					defer main.server.mutex.unlock();
					try main.server.sendMessage(newMessage);
				}
			} else {
				try main.gui.windowlist.chat.addMessage(data);
			}
		}

		pub fn send(conn: *Connection, data: []const u8) !void {
			try conn.sendImportant(id, data);
		}
	};
};


pub const Connection = struct {
	const maxPacketSize: u32 = 65507; // max udp packet size
	const importantHeaderSize: u32 = 5;
	const maxImportantPacketSize: u32 = 1500 - 20 - 8; // Ethernet MTU minus IP header minus udp header

	// Statistics:
	var packetsSent: u32 = 0;
	var packetsResent: u32 = 0;

	manager: *ConnectionManager,
	user: ?*main.server.User = null,

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
		var result: *Connection = try main.globalAllocator.create(Connection);
		result.* = Connection {
			.manager = manager,
			.remoteAddress = undefined,
			.lastConnection = std.time.milliTimestamp(),
			.lastReceivedPackets = &result.__lastReceivedPackets, // TODO: Wait for #12215 fix.
		};
		result.unconfirmedPackets = std.ArrayList(UnconfirmedPacket).init(main.globalAllocator);
		result.receivedPackets = [3]std.ArrayList(u32){
			std.ArrayList(u32).init(main.globalAllocator),
			std.ArrayList(u32).init(main.globalAllocator),
			std.ArrayList(u32).init(main.globalAllocator),
		};
		var splitter = std.mem.split(u8, ipPort, ":");
		const ip = splitter.first();
		result.remoteAddress.ip = try Socket.resolveIP(ip);
		var port = splitter.rest();
		if(port.len != 0 and port[0] == '?') {
			result.remoteAddress.isSymmetricNAT = true;
			result.bruteforcingPort = true;
			port = port[1..];
		}
		result.remoteAddress.port = std.fmt.parseUnsigned(u16, port, 10) catch blk: {
			if(ip.len != ipPort.len) std.log.warn("Could not parse port \"{s}\". Using default port instead.", .{port});
			break :blk settings.defaultPort;
		};

		try result.manager.addConnection(result);
		return result;
	}

	pub fn deinit(self: *Connection) void {
		self.disconnect() catch |err| {std.log.warn("Error while disconnecting: {s}", .{@errorName(err)});};
		self.manager.finishCurrentReceive(); // Wait until all currently received packets are done.
		for(self.unconfirmedPackets.items) |packet| {
			main.globalAllocator.free(packet.data);
		}
		self.unconfirmedPackets.deinit();
		self.receivedPackets[0].deinit();
		self.receivedPackets[1].deinit();
		self.receivedPackets[2].deinit();
		for(self.lastReceivedPackets) |nullablePacket| {
			if(nullablePacket) |packet| {
				main.globalAllocator.free(packet);
			}
		}
		main.globalAllocator.destroy(self);
	}

	fn flush(self: *Connection) Allocator.Error!void {
		if(self.streamPosition == importantHeaderSize) return; // Don't send empty packets.
		// Fill the header:
		self.streamBuffer[0] = Protocols.important;
		var id = self.messageID;
		self.messageID += 1;
		std.mem.writeIntBig(u32, self.streamBuffer[1..5], id); // TODO: Use little endian for better hardware support. Currently the aim is interoperability with the java version which uses big endian.

		var packet = UnconfirmedPacket{
			.data = try main.globalAllocator.dupe(u8, self.streamBuffer[0..self.streamPosition]),
			.lastKeepAliveSentBefore = self.lastKeepAliveSent,
			.id = id,
		};
		try self.unconfirmedPackets.append(packet);
		packetsSent += 1;
		try self.manager.send(packet.data, self.remoteAddress);
		self.streamPosition = importantHeaderSize;
	}

	fn writeByteToStream(self: *Connection, data: u8) Allocator.Error!void {
		self.streamBuffer[self.streamPosition] = data;
		self.streamPosition += 1;
		if(self.streamPosition == self.streamBuffer.len) {
			try self.flush();
		}
	}

	pub fn sendImportant(self: *Connection, id: u8, data: []const u8) Allocator.Error!void {
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
			@memcpy(self.streamBuffer[self.streamPosition..][0..copyableSize], remaining[0..copyableSize]);
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
		@memcpy(fullData[1..], data);
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
					main.globalAllocator.free(self.unconfirmedPackets.items[j].data);
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
				for(runLengthEncodingStarts.items, runLengthEncodingLengths.items, 0..) |start, length, reg| {
					var diff = packetID -% start;
					if(diff < length) continue;
					if(diff == length) {
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
		for(runLengthEncodingStarts.items, 0..) |_, i| {
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
			for(0..5) |_| {
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
			if(self.manager.world == null and self.user == null and protocol != Protocols.handShake.id)
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
				@memcpy(remaining[0..dataAvailable], self.lastReceivedPackets[id & 65535].?[newIndex..newIndex + dataAvailable]);
				newIndex += @intCast(u32, dataAvailable);
				remaining = remaining[dataAvailable..];
				if(newIndex == self.lastReceivedPackets[id & 65535].?.len) {
					id += 1;
					newIndex = 0;
				}
			}
			while(self.lastIncompletePacket != id): (self.lastIncompletePacket += 1) {
				main.globalAllocator.free(self.lastReceivedPackets[self.lastIncompletePacket & 65535].?);
				self.lastReceivedPackets[self.lastIncompletePacket & 65535] = null;
			}
			self.lastIndex = newIndex;
			bytesReceived[protocol] += data.len + 1 + (7 + std.math.log2_int(usize, 1 + data.len))/7;
			if(Protocols.list[protocol]) |prot| {
				try prot(self, data);
			} else {
				std.log.warn("Received unknown important protocol with id {}", .{protocol});
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
			self.lastReceivedPackets[id & 65535] = try main.globalAllocator.dupe(u8, data[importantHeaderSize..]);
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