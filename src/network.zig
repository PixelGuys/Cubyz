const builtin = @import("builtin");
const std = @import("std");
const Atomic = std.atomic.Value;

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
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

//TODO: Might want to use SSL or something similar to encode the message

const Socket = struct {
	const posix = std.posix;
	socketID: posix.socket_t,

	fn startup() void {
		if(builtin.os.tag == .windows) {
			_ = std.os.windows.WSAStartup(2, 2) catch |err| {
				std.log.err("Could not initialize the Windows Socket API: {s}", .{@errorName(err)});
				@panic("Could not init networking.");
			};
		}
	}

	fn init(localPort: u16) !Socket {
		const self = Socket {
			.socketID = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP),
		};
		errdefer self.deinit();
		const bindingAddr = posix.sockaddr.in {
			.port = @byteSwap(localPort),
			.addr = 0,
		};
		try posix.bind(self.socketID, @ptrCast(&bindingAddr), @sizeOf(posix.sockaddr.in));
		return self;
	}

	fn deinit(self: Socket) void {
		posix.close(self.socketID);
	}

	fn send(self: Socket, data: []const u8, destination: Address) void {
		const addr = posix.sockaddr.in {
			.port = @byteSwap(destination.port),
			.addr = destination.ip,
		};
		std.debug.assert(data.len == posix.sendto(self.socketID, data, 0, @ptrCast(&addr), @sizeOf(posix.sockaddr.in)) catch |err| {
			std.log.info("Got error while sending to {}: {s}", .{destination, @errorName(err)});
			return;
		});
	}

	fn receive(self: Socket, buffer: []u8, timeout: i32, resultAddress: *Address) ![]u8 {
		if(builtin.os.tag == .windows) { // Of course Windows always has it's own special thing.
			var pfd = [1]posix.pollfd {
				.{.fd = self.socketID, .events = std.c.POLL.RDNORM | std.c.POLL.RDBAND, .revents = undefined},
			};
			const length = std.os.windows.ws2_32.WSAPoll(&pfd, pfd.len, 0); // The timeout is set to zero. Otherwise sendto operations from other threads will block on this.
			if (length == std.os.windows.ws2_32.SOCKET_ERROR) {
				switch (std.os.windows.ws2_32.WSAGetLastError()) {
					.WSANOTINITIALISED => unreachable,
					.WSAENETDOWN => return error.NetworkSubsystemFailed,
					.WSAENOBUFS => return error.SystemResources,
					// TODO: handle more errors
					else => |err| return std.os.windows.unexpectedWSAError(err),
				}
			} else if(length == 0) {
				std.time.sleep(1000000); // Manually sleep, since WSAPoll is blocking.
				return error.Timeout;
			}
		} else {
			var pfd = [1]posix.pollfd {
				.{.fd = self.socketID, .events = posix.POLL.IN, .revents = undefined},
			};
			const length = try posix.poll(&pfd, timeout);
			if(length == 0) return error.Timeout;
		}
		var addr: posix.sockaddr.in = undefined;
		var addrLen: posix.socklen_t = @sizeOf(posix.sockaddr.in);
		const length = try posix.recvfrom(self.socketID, buffer, 0,  @ptrCast(&addr), &addrLen);
		resultAddress.ip = addr.addr;
		resultAddress.port = @byteSwap(addr.port);
		return buffer[0..length];
	}

	fn resolveIP(addr: []const u8) !u32 {
		const list = try std.net.getAddressList(main.stackAllocator.allocator, addr, settings.defaultPort);
		defer list.deinit();
		return list.addrs[0].in.sa.addr;
	}
};

pub fn init() void {
	Socket.startup();
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
		std.mem.writeInt(i128, seed[0..16], std.time.nanoTimestamp(), builtin.cpu.arch.endian()); // Not the best seed, but it's not that important.
		var random = std.rand.DefaultCsprng.init(seed);
		for(0..16) |_| {
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
			const serverAddress = Address {
				.ip=Socket.resolveIP(ip) catch |err| {
					std.log.err("Cannot resolve stun server address: {s}, error: {s}", .{ip, @errorName(err)});
					continue;
				},
				.port=std.fmt.parseUnsigned(u16, splitter.rest(), 10) catch 3478,
			};
			if(connection.sendRequest(main.globalAllocator, &data, serverAddress, 500*1000000)) |answer| {
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
			const typ = std.mem.readInt(u16, data[0..2], .big);
			const len = std.mem.readInt(u16, data[2..4], .big);
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
							.port = std.mem.readInt(u16, addressData[0..2], .big),
							.ip = std.mem.readInt(u32, addressData[2..6], builtin.cpu.arch.endian()), // Needs to stay in big endian → native.
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
		if(@as(u16, @intCast(data[2] & 0xff))*256 + (data[3] & 0xff) != data.len - 20) return error.BadSize;
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
	online: Atomic(bool) = Atomic(bool).init(false),
	running: Atomic(bool) = Atomic(bool).init(true),

	connections: main.List(*Connection) = undefined,
	requests: main.List(*Request) = undefined,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},
	waitingToFinishReceive: std.Thread.Condition = std.Thread.Condition{},

	receiveBuffer: [Connection.maxPacketSize]u8 = undefined,

	world: ?*game.World = null,

	pub fn init(localPort: u16, online: bool) !*ConnectionManager {
		const result: *ConnectionManager = main.globalAllocator.create(ConnectionManager);
		errdefer main.globalAllocator.destroy(result);
		result.* = .{};
		result.connections = main.List(*Connection).init(main.globalAllocator);
		result.requests = main.List(*Request).init(main.globalAllocator);

		result.socket = Socket.init(localPort) catch |err| blk: {
			if(err == error.AddressInUse) {
				break :blk try Socket.init(0); // Use any port.
			} else return err;
		};
		errdefer Socket.deinit(result.socket);

		result.thread = try std.Thread.spawn(.{}, run, .{result});
		result.thread.setName("Network Thread") catch |err| std.log.err("Couldn't rename thread: {s}", .{@errorName(err)});
		if(online) {
			result.makeOnline();
		}
		return result;
	}

	pub fn deinit(self: *ConnectionManager) void {
		for(self.connections.items) |conn| {
			conn.disconnect();
		}

		self.running.store(false, .monotonic);
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
		if(!self.online.load(.acquire)) {
			self.externalAddress = STUN.requestAddress(self);
			self.online.store(true, .release);
		}
	}

	pub fn send(self: *ConnectionManager, data: []const u8, target: Address) void {
		self.socket.send(data, target);
	}

	pub fn sendRequest(self: *ConnectionManager, allocator: NeverFailingAllocator, data: []const u8, target: Address, timeout_ns: u64) ?[]const u8 {
		self.send(data, target);
		var request = Request{.address = target, .data = data};
		{
			self.mutex.lock();
			defer self.mutex.unlock();
			self.requests.append(&request);

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
			if(allocator.allocator.ptr == main.globalAllocator.allocator.ptr) {
				return request.data;
			} else {
				const result = allocator.dupe(u8, request.data);
				main.globalAllocator.free(request.data);
				return result;
			}
		}
	}

	pub fn addConnection(self: *ConnectionManager, conn: *Connection) void {
		self.mutex.lock();
		defer self.mutex.unlock();

		self.connections.append(conn);
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

	fn onReceive(self: *ConnectionManager, data: []const u8, source: Address) void {
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
					conn.receive(data);
					return;
				}
			}
		}
		defer self.mutex.unlock();
		// Check if it's part of an active request:
		for(self.requests.items) |request| {
			if(request.address.ip == source.ip and request.address.port == source.port) {
				request.data = main.globalAllocator.dupe(u8, data);
				request.requestNotifier.signal();
				return;
			}
		}
		if(self.online.load(.acquire) and source.ip == self.externalAddress.ip and source.port == self.externalAddress.port) return;
		// TODO: Reduce the number of false alarms in the short period after a disconnect.
		std.log.warn("Unknown connection from address: {}", .{source});
		std.log.debug("Message: {any}", .{data});
	}

	pub fn run(self: *ConnectionManager) void {
		self.threadId = std.Thread.getCurrentId();
		var sta = utils.StackAllocator.init(main.globalAllocator, 1 << 23);
		defer sta.deinit();
		main.stackAllocator = sta.allocator();

		var lastTime = std.time.milliTimestamp();
		while(self.running.load(.monotonic)) {
			self.waitingToFinishReceive.broadcast();
			var source: Address = undefined;
			if(self.socket.receive(&self.receiveBuffer, 100, &source)) |data| {
				self.onReceive(data, source);
			} else |err| {
				if(err == error.Timeout) {
					// No message within the last ~100 ms.
				} else {
					std.log.err("Got error on receive: {s}", .{@errorName(err)});
					@panic("Network failed.");
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
						conn.disconnect();
						self.mutex.lock();
					} else {
						conn.sendKeepAlive();
						i += 1;
					}
				}
				if(self.connections.items.len == 0 and self.online.load(.acquire)) {
					// Send a message to external ip, to keep the port open:
					const data = [1]u8{0};
					self.send(&data, self.externalAddress);
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

pub var bytesReceived: [256]Atomic(usize) = [_]Atomic(usize) {Atomic(usize).init(0)} ** 256;
pub var packetsReceived: [256]Atomic(usize) = [_]Atomic(usize) {Atomic(usize).init(0)} ** 256;
pub const Protocols = struct {
	pub var list: [256]?*const fn(*Connection, []const u8) anyerror!void = [_]?*const fn(*Connection, []const u8) anyerror!void {null} ** 256;

	pub const keepAlive: u8 = 0;
	pub const important: u8 = 0xff;
	pub const handShake = struct {
		pub const id: u8 = 1;
		const stepStart: u8 = 0;
		const stepUserData: u8 = 1;
		const stepAssets: u8 = 2;
		const stepServerData: u8 = 3;
		const stepComplete: u8 = 255;

		fn receive(conn: *Connection, data: []const u8) !void {
			if(conn.handShakeState.load(.monotonic) < data[0]) {
				conn.handShakeState.store(data[0], .monotonic);
				switch(data[0]) {
					stepUserData => {
						const json = JsonElement.parseFromString(main.stackAllocator, data[1..]);
						defer json.free(main.stackAllocator);
						const name = json.get([]const u8, "name", "unnamed");
						const version = json.get([]const u8, "version", "unknown");
						std.log.info("User {s} joined using version {s}.", .{name, version});

						{
							// TODO: Send the world data.
							const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets/", .{"Development"}) catch unreachable; // TODO: Use world name.
							defer main.stackAllocator.free(path);
							var dir = try std.fs.cwd().openDir(path, .{.iterate = true});
							defer dir.close();
							var arrayList = main.List(u8).init(main.stackAllocator);
							defer arrayList.deinit();
							arrayList.append(stepAssets);
							try utils.Compression.pack(dir, arrayList.writer());
							conn.sendImportant(id, arrayList.items);
							conn.flush();
						}

						conn.user.?.initPlayer(name);
						const jsonObject = JsonElement.initObject(main.stackAllocator);
						defer jsonObject.free(main.stackAllocator);
						jsonObject.put("player", conn.user.?.player.save(main.stackAllocator));
						const spawn = JsonElement.initObject(main.stackAllocator);
						spawn.put("x", main.server.world.?.spawn[0]);
						spawn.put("y", main.server.world.?.spawn[1]);
						spawn.put("z", main.server.world.?.spawn[2]);
						jsonObject.put("spawn", spawn);
						jsonObject.put("blockPalette", main.server.world.?.blockPalette.save(main.stackAllocator));
						
						const outData = jsonObject.toStringEfficient(main.stackAllocator, &[1]u8{stepServerData});
						defer main.stackAllocator.free(outData);
						conn.sendImportant(id, outData);
						conn.handShakeState.store(stepServerData, .monotonic);
						conn.handShakeState.store(stepComplete, .monotonic);
						main.server.connect(conn.user.?);
					},
					stepAssets => {
						std.log.info("Received assets.", .{});
						std.fs.cwd().deleteTree("serverAssets") catch {}; // Delete old assets.
						var dir = try std.fs.cwd().makeOpenPath("serverAssets", .{});
						defer dir.close();
						try utils.Compression.unpack(dir, data[1..]);
					},
					stepServerData => {
						const json = JsonElement.parseFromString(main.stackAllocator, data[1..]);
						defer json.free(main.stackAllocator);
						try conn.manager.world.?.finishHandshake(json);
						conn.handShakeState.store(stepComplete, .monotonic);
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
			conn.handShakeState.store(stepStart, .monotonic);
		}

		pub fn clientSide(conn: *Connection, name: []const u8) void {
			const jsonObject = JsonElement.initObject(main.stackAllocator);
			defer jsonObject.free(main.stackAllocator);
			jsonObject.putOwnedString("version", settings.version);
			jsonObject.putOwnedString("name", name);
			const prefix = [1]u8 {stepUserData};
			const data = jsonObject.toStringEfficient(main.stackAllocator, &prefix);
			defer main.stackAllocator.free(data);
			conn.sendImportant(id, data);

			conn.mutex.lock();
			conn.handShakeWaiting.wait(&conn.mutex);
			conn.mutex.unlock();
		}
	};
	pub const chunkRequest = struct {
		pub const id: u8 = 2;
		fn receive(conn: *Connection, data: []const u8) !void {
			var remaining = data[0..];
			while(remaining.len >= 16) {
				const request = chunk.ChunkPosition{
					.wx = std.mem.readInt(i32, remaining[0..4], .big),
					.wy = std.mem.readInt(i32, remaining[4..8], .big),
					.wz = std.mem.readInt(i32, remaining[8..12], .big),
					.voxelSize = @intCast(std.mem.readInt(i32, remaining[12..16], .big)),
				};
				if(conn.user) |user| {
					main.server.world.?.queueChunk(request, user);
				}
				remaining = remaining[16..];
			}
		}
		pub fn sendRequest(conn: *Connection, requests: []chunk.ChunkPosition) void {
			if(requests.len == 0) return;
			const data = main.stackAllocator.alloc(u8, 16*requests.len);
			defer main.stackAllocator.free(data);
			var remaining = data;
			for(requests) |req| {
				std.mem.writeInt(i32, remaining[0..4], req.wx, .big);
				std.mem.writeInt(i32, remaining[4..8], req.wy, .big);
				std.mem.writeInt(i32, remaining[8..12], req.wz, .big);
				std.mem.writeInt(i32, remaining[12..16], req.voxelSize, .big);
				remaining = remaining[16..];
			}
			conn.sendImportant(id, data);
		}
	};
	pub const chunkTransmission = struct {
		pub const id: u8 = 3;
		fn receive(_: *Connection, data: []const u8) !void {
			const pos = chunk.ChunkPosition{
				.wx = std.mem.readInt(i32, data[0..4], .big),
				.wy = std.mem.readInt(i32, data[4..8], .big),
				.wz = std.mem.readInt(i32, data[8..12], .big),
				.voxelSize = @intCast(std.mem.readInt(i32, data[12..16], .big)),
			};
			const ch = chunk.Chunk.init(pos);
			try main.server.storage.ChunkCompression.decompressChunk(ch, data[16..]);
			renderer.mesh_storage.updateChunkMesh(ch);
		}
		fn sendChunkOverTheNetwork(conn: *Connection, ch: *chunk.ServerChunk) void {
			ch.mutex.lock();
			const chunkData = main.server.storage.ChunkCompression.compressChunk(main.stackAllocator, &ch.super);
			ch.mutex.unlock();
			defer main.stackAllocator.free(chunkData);
			const data = main.stackAllocator.alloc(u8, chunkData.len + 16);
			defer main.stackAllocator.free(data);
			std.mem.writeInt(i32, data[0..4], ch.super.pos.wx, .big);
			std.mem.writeInt(i32, data[4..8], ch.super.pos.wy, .big);
			std.mem.writeInt(i32, data[8..12], ch.super.pos.wz, .big);
			std.mem.writeInt(i32, data[12..16], ch.super.pos.voxelSize, .big);
			@memcpy(data[16..], chunkData);
			conn.sendImportant(id, data);
		}
		fn sendChunkLocally(ch: *chunk.ServerChunk) void {
			const chunkCopy = chunk.Chunk.init(ch.super.pos);
			chunkCopy.data.deinit();
			chunkCopy.data.initCopy(&ch.super.data);
			renderer.mesh_storage.updateChunkMesh(chunkCopy);
		}
		pub fn sendChunk(conn: *Connection, ch: *chunk.ServerChunk) void {
			if(conn.user.?.isLocal) {
				sendChunkLocally(ch);
			} else {
				sendChunkOverTheNetwork(conn, ch);
			}
		}
	};
	pub const playerPosition = struct {
		pub const id: u8 = 4;
		fn receive(conn: *Connection, data: []const u8) !void {
			conn.user.?.receiveData(data);
		}
		var lastPositionSent: u16 = 0;
		pub fn send(conn: *Connection, playerPos: Vec3d, playerVel: Vec3d, time: u16) void {
			if(time -% lastPositionSent < 50) {
				return; // Only send at most once every 50 ms.
			}
			lastPositionSent = time;
			var data: [62]u8 = undefined;
			std.mem.writeInt(u64, data[0..8],   @as(u64, @bitCast(playerPos[0])), .big);
			std.mem.writeInt(u64, data[8..16],  @as(u64, @bitCast(playerPos[1])), .big);
			std.mem.writeInt(u64, data[16..24], @as(u64, @bitCast(playerPos[2])), .big);
			std.mem.writeInt(u64, data[24..32], @as(u64, @bitCast(playerVel[0])), .big);
			std.mem.writeInt(u64, data[32..40], @as(u64, @bitCast(playerVel[1])), .big);
			std.mem.writeInt(u64, data[40..48], @as(u64, @bitCast(playerVel[2])), .big);
			std.mem.writeInt(u32, data[48..52], @as(u32, @bitCast(game.camera.rotation[0])), .big);
			std.mem.writeInt(u32, data[52..56], @as(u32, @bitCast(game.camera.rotation[1])), .big);
			std.mem.writeInt(u32, data[56..60], @as(u32, @bitCast(game.camera.rotation[2])), .big);
			std.mem.writeInt(u16, data[60..62], time, .big);
			conn.sendUnimportant(id, &data);
		}
	};
	pub const disconnect = struct {
		pub const id: u8 = 5;
		fn receive(conn: *Connection, _: []const u8) !void {
			conn.disconnect();
			if(conn.user) |user| {
				main.server.disconnect(user);
			}
		}
		pub fn disconnect(conn: *Connection) void {
			const noData = [0]u8 {};
			conn.sendUnimportant(id, &noData);
		}
	};
	pub const entityPosition = struct {
		pub const id: u8 = 6;
		const type_entity: u8 = 0;
		const type_item: u8 = 1;
		fn receive(conn: *Connection, data: []const u8) !void {
			if(conn.manager.world) |world| {
				const time = std.mem.readInt(i16, data[1..3], .big);
				if(data[0] == type_entity) {
					main.entity.ClientEntityManager.serverUpdate(time, data[3..]);
				} else if(data[0] == type_item) {
					world.itemDrops.readPosition(data[3..], time);
				}
			}
		}
		pub fn send(conn: *Connection, entityData: []const u8, itemData: []const u8) void {
			const fullEntityData = main.stackAllocator.alloc(u8, entityData.len + 3);
			defer main.stackAllocator.free(fullEntityData);
			fullEntityData[0] = type_entity;
			std.mem.writeInt(i16, fullEntityData[1..3], @as(i16, @truncate(std.time.milliTimestamp())), .big);
			@memcpy(fullEntityData[3..], entityData);
			conn.sendUnimportant(id, fullEntityData);

			const fullItemData = main.stackAllocator.alloc(u8, itemData.len + 3);
			defer main.stackAllocator.free(fullItemData);
			fullItemData[0] = type_item;
			std.mem.writeInt(i16, fullItemData[1..3], @as(i16, @truncate(std.time.milliTimestamp())), .big);
			@memcpy(fullItemData[3..], itemData);
			conn.sendUnimportant(id, fullItemData);
		}
	};
	pub const blockUpdate = struct {
		pub const id: u8 = 7;
		fn receive(conn: *Connection, data: []const u8) !void {
			const x = std.mem.readInt(i32, data[0..4], .big);
			const y = std.mem.readInt(i32, data[4..8], .big);
			const z = std.mem.readInt(i32, data[8..12], .big);
			const newBlock = Block.fromInt(std.mem.readInt(u32, data[12..16], .big));
			if(conn.user != null) { // TODO: Send update event to other players.
				main.server.world.?.updateBlock(x, y, z, newBlock);
			} else {
				renderer.mesh_storage.updateBlock(x, y, z, newBlock);
			}
		}
		pub fn send(conn: *Connection, x: i32, y: i32, z: i32, newBlock: Block) void {
			var data: [16]u8 = undefined;
			std.mem.writeInt(i32, data[0..4], x, .big);
			std.mem.writeInt(i32, data[4..8], y, .big);
			std.mem.writeInt(i32, data[8..12], z, .big);
			std.mem.writeInt(u32, data[12..16], newBlock.toInt(), .big);
			conn.sendImportant(id, &data);
		}
	};
	pub const entity = struct {
		pub const id: u8 = 8;
		fn receive(conn: *Connection, data: []const u8) !void {
			const jsonArray = JsonElement.parseFromString(main.stackAllocator, data);
			defer jsonArray.free(main.stackAllocator);
			var i: u32 = 0;
			while(i < jsonArray.JsonArray.items.len) : (i += 1) {
				const elem = jsonArray.JsonArray.items[i];
				switch(elem) {
					.JsonInt => {
						main.entity.ClientEntityManager.removeEntity(elem.as(u32, 0));
					},
					.JsonObject => {
						main.entity.ClientEntityManager.addEntity(elem);
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
					conn.manager.world.?.itemDrops.loadFrom(elem);
				} else {
					conn.manager.world.?.itemDrops.addFromJson(elem);
				}
			}
		}
		pub fn send(conn: *Connection, msg: []const u8) void {
			conn.sendImportant(id, msg);
		}
		// TODO: Send entity data.
	};
	pub const genericUpdate = struct {
		pub const id: u8 = 9;
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
					const renderDistance = std.mem.readInt(i32, data[1..5], .big);
					if(conn.user) |user| {
						user.renderDistance = @intCast(renderDistance); // TODO: Update the protocol to use u16.
					}
				},
				type_teleport => {
					game.Player.setPosBlocking(Vec3d{
						@bitCast(std.mem.readInt(u64, data[1..9], .big)),
						@bitCast(std.mem.readInt(u64, data[9..17], .big)),
						@bitCast(std.mem.readInt(u64, data[17..25], .big)),
					});
				},
				type_cure => {
					// TODO: health and hunger
				},
				type_inventoryAdd => {
					const slot = std.mem.readInt(u32, data[1..5], .big);
					const amount = std.mem.readInt(u32, data[5..9], .big);
					_ = slot;
					_ = amount;
					// TODO
				},
				type_inventoryFull => {
					// TODO: Parse inventory from json
				},
				type_inventoryClear => {
					// TODO: Clear inventory
				},
				type_itemStackDrop => {
					// TODO: Drop stack
				},
				type_itemStackCollect => {
					const json = JsonElement.parseFromString(main.stackAllocator, data[1..]);
					defer json.free(main.stackAllocator);
					const item = items.Item.init(json) catch |err| {
						std.log.err("Error {s} while collecting item {s}. Ignoring it.", .{@errorName(err), data[1..]});
						return;
					};
					game.Player.mutex.lock();
					defer game.Player.mutex.unlock();
					const remaining = game.Player.inventory__SEND_CHANGES_TO_SERVER.addItem(item, json.get(u16, "amount", 0));

					sendInventory_full(conn, game.Player.inventory__SEND_CHANGES_TO_SERVER);
					if(remaining != 0) {
						// Couldn't collect everything → drop it again.
						itemStackDrop(conn, ItemStack{.item=item, .amount=remaining}, game.Player.super.pos, Vec3f{0, 0, 0}, 0);
					}
				},
				type_timeAndBiome => {
					if(conn.manager.world) |world| {
						const json = JsonElement.parseFromString(main.stackAllocator, data[1..]);
						defer json.free(main.stackAllocator);
						const expectedTime = json.get(i64, "time", 0);
						var curTime = world.gameTime.load(.monotonic);
						if(@abs(curTime -% expectedTime) >= 1000) {
							world.gameTime.store(expectedTime, .monotonic);
						} else if(curTime < expectedTime) { // world.gameTime++
							while(world.gameTime.cmpxchgWeak(curTime, curTime +% 1, .monotonic, .monotonic)) |actualTime| {
								curTime = actualTime;
							}
						} else { // world.gameTime--
							while(world.gameTime.cmpxchgWeak(curTime, curTime -% 1, .monotonic, .monotonic)) |actualTime| {
								curTime = actualTime;
							}
						}
						world.playerBiome.store(main.server.terrain.biomes.getById(json.get([]const u8, "biome", "")), .monotonic);
					}
				},
				else => |unrecognizedType| {
					std.log.err("Unrecognized type for genericUpdateProtocol: {}. Data: {any}", .{unrecognizedType, data});
				},
			}
		}

		fn addHeaderAndSendImportant(conn: *Connection, header: u8, data: []const u8) void {
			const headeredData = main.stackAllocator.alloc(u8, data.len + 1);
			defer main.stackAllocator.free(headeredData);
			headeredData[0] = header;
			@memcpy(headeredData[1..], data);
			conn.sendImportant(id, headeredData);
		}

		fn addHeaderAndSendUnimportant(conn: *Connection, header: u8, data: []const u8) void {
			const headeredData = main.stackAllocator.alloc(u8, data.len + 1);
			defer main.stackAllocator.free(headeredData);
			headeredData[0] = header;
			@memcpy(headeredData[1..], data);
			conn.sendUnimportant(id, headeredData);
		}

		pub fn sendRenderDistance(conn: *Connection, renderDistance: i32) void {
			var data: [5]u8 = undefined;
			data[0] = type_renderDistance;
			std.mem.writeInt(i32, data[1..5], renderDistance, .big);
			conn.sendImportant(id, &data);
		}

		pub fn sendTPCoordinates(conn: *Connection, pos: Vec3d) void {
			var data: [1+24]u8 = undefined;
			data[0] = type_teleport;
			std.mem.writeInt(u64, data[1..9], @as(u64, @bitCast(pos[0])), .big);
			std.mem.writeInt(u64, data[9..17], @as(u64, @bitCast(pos[1])), .big);
			std.mem.writeInt(u64, data[17..25], @as(u64, @bitCast(pos[2])), .big);
			conn.sendImportant(id, &data);
		}

		pub fn sendCure(conn: *Connection) void {
			var data: [1]u8 = undefined;
			data[0] = type_cure;
			conn.sendImportant(id, &data);
		}

		pub fn sendInventory_ItemStack_add(conn: *Connection, slot: u32, amount: i32) void {
			var data: [9]u8 = undefined;
			data[0] = type_inventoryAdd;
			std.mem.writeInt(u32, data[1..5], slot, .big);
			std.mem.writeInt(u32, data[5..9], amount, .big);
			conn.sendImportant(id, &data);
		}


		pub fn sendInventory_full(conn: *Connection, inv: Inventory) void {
			const json = inv.save(main.stackAllocator);
			defer json.free(main.stackAllocator);
			const string = json.toString(main.stackAllocator);
			defer main.stackAllocator.free(string);
			addHeaderAndSendImportant(conn, type_inventoryFull, string);
		}

		pub fn clearInventory(conn: *Connection) void {
			var data: [1]u8 = undefined;
			data[0] = type_inventoryClear;
			conn.sendImportant(id, &data);
		}

		pub fn itemStackDrop(conn: *Connection, stack: ItemStack, pos: Vec3d, dir: Vec3f, vel: f32) void {
			const jsonObject = stack.store(main.stackAllocator);
			defer jsonObject.free(main.stackAllocator);
			jsonObject.put("x", pos[0]);
			jsonObject.put("y", pos[1]);
			jsonObject.put("z", pos[2]);
			jsonObject.put("dirX", dir[0]);
			jsonObject.put("dirY", dir[1]);
			jsonObject.put("dirZ", dir[2]);
			jsonObject.put("vel", vel);
			const string = jsonObject.toString(main.stackAllocator);
			defer main.stackAllocator.free(string);
			addHeaderAndSendImportant(conn, type_itemStackDrop, string);
		}

		pub fn itemStackCollect(conn: *Connection, stack: ItemStack) void {
			const json = stack.store(main.stackAllocator);
			defer json.free(main.stackAllocator);
			const string = json.toString(main.stackAllocator);
			defer main.stackAllocator.free(string);
			addHeaderAndSendImportant(conn, type_itemStackCollect, string);
		}

		pub fn sendTimeAndBiome(conn: *Connection, world: *const main.server.ServerWorld) void {
			const json = JsonElement.initObject(main.stackAllocator);
			defer json.free(main.stackAllocator);
			json.put("time", world.gameTime);
			const pos = conn.user.?.player.pos;
			json.put("biome", (world.getBiome(@intFromFloat(pos[0]), @intFromFloat(pos[1]), @intFromFloat(pos[2]))).id);
			const string = json.toString(main.stackAllocator);
			defer main.stackAllocator.free(string);
			addHeaderAndSendUnimportant(conn, type_timeAndBiome, string);
		}
	};
	pub const chat = struct {
		pub const id: u8 = 10;
		fn receive(conn: *Connection, data: []const u8) !void {
			if(conn.user) |user| {
				if(data[0] == '/') {
					// TODO:
					// CommandExecutor.execute(data, user);
				} else {
					const newMessage = std.fmt.allocPrint(main.stackAllocator.allocator, "[{s}#ffffff]{s}", .{user.name, data}) catch unreachable;
					defer main.stackAllocator.free(newMessage);
					main.server.mutex.lock();
					defer main.server.mutex.unlock();
					main.server.sendMessage(newMessage);
				}
			} else {
				main.gui.windowlist.chat.addMessage(data);
			}
		}

		pub fn send(conn: *Connection, data: []const u8) void {
			conn.sendImportant(id, data);
		}
	};
	pub const lightMapRequest = struct {
		pub const id: u8 = 11;
		fn receive(conn: *Connection, data: []const u8) !void {
			var remaining = data[0..];
			while(remaining.len >= 9) {
				const request = main.server.terrain.SurfaceMap.MapFragmentPosition{
					.wx = std.mem.readInt(i32, remaining[0..4], .big),
					.wy = std.mem.readInt(i32, remaining[4..8], .big),
					.voxelSize = @as(u31, 1) << @intCast(std.mem.readInt(u8, remaining[8..9], .big)),
					.voxelSizeShift = @intCast(std.mem.readInt(u8, remaining[8..9], .big)),
				};
				if(conn.user) |user| {
					main.server.world.?.queueLightMap(request, user);
				}
				remaining = remaining[9..];
			}
		}
		pub fn sendRequest(conn: *Connection, requests: []main.server.terrain.SurfaceMap.MapFragmentPosition) void {
			if(requests.len == 0) return;
			const data = main.stackAllocator.alloc(u8, 9*requests.len);
			defer main.stackAllocator.free(data);
			var remaining = data;
			for(requests) |req| {
				std.mem.writeInt(i32, remaining[0..4], req.wx, .big);
				std.mem.writeInt(i32, remaining[4..8], req.wy, .big);
				std.mem.writeInt(u8, remaining[8..9], req.voxelSizeShift, .big);
				remaining = remaining[9..];
			}
			conn.sendImportant(id, data);
		}
	};
	pub const lightMapTransmission = struct {
		pub const id: u8 = 12;
		fn receive(_: *Connection, _data: []const u8) !void {
			var data = _data;
			const pos = main.server.terrain.SurfaceMap.MapFragmentPosition{
				.wx = std.mem.readInt(i32, data[0..4], .big),
				.wy = std.mem.readInt(i32, data[4..8], .big),
				.voxelSize = @as(u31, 1) << @intCast(std.mem.readInt(u8, data[8..9], .big)),
				.voxelSizeShift = @intCast(std.mem.readInt(u8, data[8..9], .big)),
			};
			const _inflatedData = main.stackAllocator.alloc(u8, main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2);
			defer main.stackAllocator.free(_inflatedData);
			const _inflatedLen = try utils.Compression.inflateTo(_inflatedData, data[9..]);
			if(_inflatedLen != main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2) {
				std.log.err("Transmission of light map has invalid size: {}. Input data: {any}, After inflate: {any}", .{_inflatedLen, data, _inflatedData[0.._inflatedLen]});
			}
			data = _inflatedData;
			const map = main.globalAllocator.create(main.server.terrain.LightMap.LightMapFragment);
			map.init(pos.wx, pos.wy, pos.voxelSize);
			_ = map.refCount.fetchAdd(1, .monotonic);
			for(&map.startHeight) |*val| {
				val.* = std.mem.readInt(i16, data[0..2], .big);
				data = data[2..];
			}
			renderer.mesh_storage.updateLightMap(map);
		}
		pub fn sendLightMap(conn: *Connection, map: *main.server.terrain.LightMap.LightMapFragment) void {
			var uncompressedData: [@sizeOf(@TypeOf(map.startHeight))]u8 = undefined; // TODO: #15280
			for(&map.startHeight, 0..) |val, i| {
				std.mem.writeInt(i16, uncompressedData[2*i..][0..2], val, .big);
			}
			const compressedData = utils.Compression.deflate(main.stackAllocator, &uncompressedData);
			defer main.stackAllocator.free(compressedData);
			const data = main.stackAllocator.alloc(u8, 9 + compressedData.len);
			defer main.stackAllocator.free(data);
			@memcpy(data[9..], compressedData);
			std.mem.writeInt(i32, data[0..4], map.pos.wx, .big);
			std.mem.writeInt(i32, data[4..8], map.pos.wy, .big);
			std.mem.writeInt(u8, data[8..9], map.pos.voxelSizeShift, .big);
			conn.sendImportant(id, data);
		}
	};
};


pub const Connection = struct {
	const maxPacketSize: u32 = 65507; // max udp packet size
	const importantHeaderSize: u32 = 5;
	const maxImportantPacketSize: u32 = 1500 - 20 - 8; // Ethernet MTU minus IP header minus udp header

	// Statistics:
	pub var packetsSent: Atomic(u32) = Atomic(u32).init(0);
	pub var packetsResent: Atomic(u32) = Atomic(u32).init(0);

	manager: *ConnectionManager,
	user: ?*main.server.User = null,

	remoteAddress: Address,
	bruteforcingPort: bool = false,
	bruteForcedPortRange: u16 = 0,

	streamBuffer: [maxImportantPacketSize]u8 = undefined,
	streamPosition: u32 = importantHeaderSize,
	messageID: u32 = 0,
	unconfirmedPackets: main.List(UnconfirmedPacket) = undefined,
	receivedPackets: [3]main.List(u32) = undefined,
	__lastReceivedPackets: [65536]?[]const u8 = [_]?[]const u8{null} ** 65536, // TODO: Wait for #12215 fix.
	lastReceivedPackets: []?[]const u8, // TODO: Wait for #12215 fix.
	packetMemory: *[65536][maxImportantPacketSize]u8 = undefined,
	lastIndex: u32 = 0,

	lastIncompletePacket: u32 = 0,

	lastKeepAliveSent: u32 = 0,
	lastKeepAliveReceived: u32 = 0,
	otherKeepAliveReceived: u32 = 0,

	disconnected: bool = false,
	handShakeState: Atomic(u8) = Atomic(u8).init(Protocols.handShake.stepStart),
	handShakeWaiting: std.Thread.Condition = std.Thread.Condition{},
	lastConnection: i64,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},

	pub fn init(manager: *ConnectionManager, ipPort: []const u8) !*Connection {
		const result: *Connection = main.globalAllocator.create(Connection);
		result.* = Connection {
			.manager = manager,
			.remoteAddress = undefined,
			.lastConnection = std.time.milliTimestamp(),
			.lastReceivedPackets = &result.__lastReceivedPackets, // TODO: Wait for #12215 fix.
			.packetMemory = main.globalAllocator.create([65536][maxImportantPacketSize]u8),
		};
		result.unconfirmedPackets = main.List(UnconfirmedPacket).init(main.globalAllocator);
		result.receivedPackets = [3]main.List(u32){
			main.List(u32).init(main.globalAllocator),
			main.List(u32).init(main.globalAllocator),
			main.List(u32).init(main.globalAllocator),
		};
		errdefer result.deinit();
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

		result.manager.addConnection(result);
		return result;
	}

	pub fn deinit(self: *Connection) void {
		self.disconnect();
		self.manager.finishCurrentReceive(); // Wait until all currently received packets are done.
		for(self.unconfirmedPackets.items) |packet| {
			main.globalAllocator.free(packet.data);
		}
		self.unconfirmedPackets.deinit();
		self.receivedPackets[0].deinit();
		self.receivedPackets[1].deinit();
		self.receivedPackets[2].deinit();
		main.globalAllocator.destroy(self.packetMemory);
		main.globalAllocator.destroy(self);
	}

	fn flush(self: *Connection) void {
		if(self.streamPosition == importantHeaderSize) return; // Don't send empty packets.
		// Fill the header:
		self.streamBuffer[0] = Protocols.important;
		const id = self.messageID;
		self.messageID += 1;
		std.mem.writeInt(u32, self.streamBuffer[1..5], id, .big); // TODO: Use little endian for better hardware support. Currently the aim is interoperability with the java version which uses big endian.

		const packet = UnconfirmedPacket{
			.data = main.globalAllocator.dupe(u8, self.streamBuffer[0..self.streamPosition]),
			.lastKeepAliveSentBefore = self.lastKeepAliveSent,
			.id = id,
		};
		self.unconfirmedPackets.append(packet);
		_ = packetsSent.fetchAdd(1, .monotonic);
		self.manager.send(packet.data, self.remoteAddress);
		self.streamPosition = importantHeaderSize;
	}

	fn writeByteToStream(self: *Connection, data: u8) void {
		self.streamBuffer[self.streamPosition] = data;
		self.streamPosition += 1;
		if(self.streamPosition == self.streamBuffer.len) {
			self.flush();
		}
	}

	pub fn sendImportant(self: *Connection, id: u8, data: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();

		if(self.disconnected) return;
		self.writeByteToStream(id);
		var processedLength = data.len;
		while(processedLength > 0x7f) {
			self.writeByteToStream(@as(u8, @intCast(processedLength & 0x7f)) | 0x80);
			processedLength >>= 7;
		}
		self.writeByteToStream(@intCast(processedLength & 0x7f));

		var remaining: []const u8 = data;
		while(remaining.len != 0) {
			const copyableSize = @min(remaining.len, self.streamBuffer.len - self.streamPosition);
			@memcpy(self.streamBuffer[self.streamPosition..][0..copyableSize], remaining[0..copyableSize]);
			remaining = remaining[copyableSize..];
			self.streamPosition += @intCast(copyableSize);
			if(self.streamPosition == self.streamBuffer.len) {
				self.flush();
			}
		}
	}

	pub fn sendUnimportant(self: *Connection, id: u8, data: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();

		if(self.disconnected) return;
		std.debug.assert(data.len + 1 < maxPacketSize);
		const fullData = main.stackAllocator.alloc(u8, data.len + 1);
		defer main.stackAllocator.free(fullData);
		fullData[0] = id;
		@memcpy(fullData[1..], data);
		self.manager.send(fullData, self.remoteAddress);
	}

	fn receiveKeepAlive(self: *Connection, data: []const u8) void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		self.mutex.lock();
		defer self.mutex.unlock();

		self.otherKeepAliveReceived = std.mem.readInt(u32, data[0..4], .big);
		self.lastKeepAliveReceived = std.mem.readInt(u32, data[4..8], .big);
		var remaining: []const u8 = data[8..];
		while(remaining.len >= 8) {
			const start = std.mem.readInt(u32, remaining[0..4], .big);
			const len = std.mem.readInt(u32, remaining[4..8], .big);
			remaining = remaining[8..];
			var j: usize = 0;
			while(j < self.unconfirmedPackets.items.len) {
				const diff = self.unconfirmedPackets.items[j].id -% start;
				if(diff < len) {
					main.globalAllocator.free(self.unconfirmedPackets.items[j].data);
					_ = self.unconfirmedPackets.swapRemove(j);
				} else {
					j += 1;
				}
			}
		}
	}

	fn sendKeepAlive(self: *Connection) void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		self.mutex.lock();
		defer self.mutex.unlock();

		var runLengthEncodingStarts: main.List(u32) = main.List(u32).init(main.stackAllocator);
		defer runLengthEncodingStarts.deinit();
		var runLengthEncodingLengths: main.List(u32) = main.List(u32).init(main.stackAllocator);
		defer runLengthEncodingLengths.deinit();

		for(self.receivedPackets) |list| {
			for(list.items) |packetID| {
				var leftRegion: ?u32 = null;
				var rightRegion: ?u32 = null;
				for(runLengthEncodingStarts.items, runLengthEncodingLengths.items, 0..) |start, length, reg| {
					const diff = packetID -% start;
					if(diff < length) continue;
					if(diff == length) {
						leftRegion = @intCast(reg);
					}
					if(diff == std.math.maxInt(u32)) {
						rightRegion = @intCast(reg);
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
					runLengthEncodingStarts.append(packetID);
					runLengthEncodingLengths.append(1);
				}
			}
		}
		{ // Cycle the receivedPackets lists:
			const putBackToFront: main.List(u32) = self.receivedPackets[self.receivedPackets.len - 1];
			var i: u32 = self.receivedPackets.len - 1;
			while(i >= 1): (i -= 1) {
				self.receivedPackets[i] = self.receivedPackets[i-1];
			}
			self.receivedPackets[0] = putBackToFront;
			self.receivedPackets[0].clearRetainingCapacity();
		}
		const output = main.stackAllocator.alloc(u8, runLengthEncodingStarts.items.len*8 + 9);
		defer main.stackAllocator.free(output);
		output[0] = Protocols.keepAlive;
		std.mem.writeInt(u32, output[1..5], self.lastKeepAliveSent, .big);
		self.lastKeepAliveSent += 1;
		std.mem.writeInt(u32, output[5..9], self.otherKeepAliveReceived, .big);
		var remaining: []u8 = output[9..];
		for(runLengthEncodingStarts.items, 0..) |_, i| {
			std.mem.writeInt(u32, remaining[0..4], runLengthEncodingStarts.items[i], .big);
			std.mem.writeInt(u32, remaining[4..8], runLengthEncodingLengths.items[i], .big);
			remaining = remaining[8..];
		}
		self.manager.send(output, self.remoteAddress);

		// Resend packets that didn't receive confirmation within the last 2 keep-alive signals.
		for(self.unconfirmedPackets.items) |*packet| {
			if(self.lastKeepAliveReceived -% @as(i33, packet.lastKeepAliveSentBefore) >= 2) {
				_ = packetsSent.fetchAdd(1, .monotonic);
				_ = packetsResent.fetchAdd(1, .monotonic);
				self.manager.send(packet.data, self.remoteAddress);
				packet.lastKeepAliveSentBefore = self.lastKeepAliveSent;
			}
		}
		self.flush();
		if(self.bruteforcingPort) {
			// This is called every 100 ms, so if I send 10 requests it shouldn't be too bad.
			for(0..5) |_| {
				const data = [1]u8{0};
				if(self.remoteAddress.port +% self.bruteForcedPortRange != 0) {
					self.manager.send(&data, Address{.ip = self.remoteAddress.ip, .port = self.remoteAddress.port +% self.bruteForcedPortRange});
				}
				if(self.remoteAddress.port - self.bruteForcedPortRange != 0) {
					self.manager.send(&data, Address{.ip = self.remoteAddress.ip, .port = self.remoteAddress.port -% self.bruteForcedPortRange});
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
			const protocol = receivedPacket[newIndex];
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
				const nextByte = receivedPacket[newIndex];
				newIndex += 1;
				len |= @as(u32, @intCast(nextByte & 0x7f)) << shift;
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
				const otherPacket = self.lastReceivedPackets[idd & 65535] orelse return;
				dataAvailable += otherPacket.len;
			}

			// Copy the data to an array:
			const data = main.stackAllocator.alloc(u8, len);
			defer main.stackAllocator.free(data);
			var remaining = data[0..];
			while(remaining.len != 0) {
				dataAvailable = @min(self.lastReceivedPackets[id & 65535].?.len - newIndex, remaining.len);
				@memcpy(remaining[0..dataAvailable], self.lastReceivedPackets[id & 65535].?[newIndex..newIndex + dataAvailable]);
				newIndex += @intCast(dataAvailable);
				remaining = remaining[dataAvailable..];
				if(newIndex == self.lastReceivedPackets[id & 65535].?.len) {
					id += 1;
					newIndex = 0;
				}
			}
			while(self.lastIncompletePacket != id): (self.lastIncompletePacket += 1) {
				self.lastReceivedPackets[self.lastIncompletePacket & 65535] = null;
			}
			self.lastIndex = newIndex;
			_ = bytesReceived[protocol].fetchAdd(data.len + 1 + (7 + std.math.log2_int(usize, 1 + data.len))/7, .monotonic);
			if(Protocols.list[protocol]) |prot| {
				try prot(self, data);
			} else {
				std.log.warn("Received unknown important protocol with id {}", .{protocol});
			}
		}
	}

	pub fn receive(self: *Connection, data: []const u8) void {
		self.flawedReceive(data) catch |err| {
			std.log.err("Got error while processing received network data: {s}", .{@errorName(err)});
			self.disconnect();
		};
	}

	pub fn flawedReceive(self: *Connection, data: []const u8) !void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		const protocol = data[0];
		if(self.handShakeState.load(.monotonic) != Protocols.handShake.stepComplete and protocol != Protocols.handShake.id and protocol != Protocols.keepAlive and protocol != Protocols.important) {
			return; // Reject all non-handshake packets until the handshake is done.
		}
		self.lastConnection = std.time.milliTimestamp();
		_ = bytesReceived[protocol].fetchAdd(data.len + 20 + 8, .monotonic); // Including IP header and udp header;
		_ = packetsReceived[protocol].fetchAdd(1, .monotonic);
		if(protocol == Protocols.important) {
			const id = std.mem.readInt(u32, data[1..5], .big);
			if(self.handShakeState.load(.monotonic) == Protocols.handShake.stepComplete and id == 0) { // Got a new "first" packet from client. So the client tries to reconnect, but we still think it's connected.
				// TODO: re-initialize connection.
			}
			if(id - @as(i33, self.lastIncompletePacket) >= 65536) {
				std.log.warn("Many incomplete packages. Cannot process any more packages for now.", .{});
				return;
			}
			self.receivedPackets[0].append(id);
			if(id < self.lastIncompletePacket or self.lastReceivedPackets[id & 65535] != null) {
				return; // Already received the package in the past.
			}
			const temporaryMemory: []u8 = (&self.packetMemory[id & 65535])[0..data.len-importantHeaderSize];
			@memcpy(temporaryMemory, data[importantHeaderSize..]);
			self.lastReceivedPackets[id & 65535] = temporaryMemory;
			// Check if a message got completed:
			try self.collectPackets();
		} else if(protocol == Protocols.keepAlive) {
			self.receiveKeepAlive(data[1..]);
		} else {
			if(Protocols.list[protocol]) |prot| {
				try prot(self, data[1..]);
			} else {
				std.log.warn("Received unknown protocol with id {}", .{protocol});
			}
		}
	}

	pub fn disconnect(self: *Connection) void {
		// Send 3 disconnect packages to the other side, just to be sure.
		// If all of them don't get through then there is probably a network issue anyways which would lead to a timeout.
		Protocols.disconnect.disconnect(self);
		std.time.sleep(10000000);
		Protocols.disconnect.disconnect(self);
		std.time.sleep(10000000);
		Protocols.disconnect.disconnect(self);
		self.disconnected = true;
		self.manager.removeConnection(self);
		std.log.info("Disconnected", .{});
	}
};