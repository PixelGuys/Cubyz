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
const ZonElement = @import("zon.zig").ZonElement;
const main = @import("main.zig");
const game = @import("game.zig");
const settings = @import("settings.zig");
const renderer = @import("renderer.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const networkEndian: std.builtin.Endian = .big;

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
		const self = Socket{
			.socketID = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP),
		};
		errdefer self.deinit();
		const bindingAddr = posix.sockaddr.in{
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
		const addr = posix.sockaddr.in{
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
			var pfd = [1]posix.pollfd{
				.{.fd = self.socketID, .events = std.c.POLL.RDNORM | std.c.POLL.RDBAND, .revents = undefined},
			};
			const length = std.os.windows.ws2_32.WSAPoll(&pfd, pfd.len, 0); // The timeout is set to zero. Otherwise sendto operations from other threads will block on this.
			if(length == std.os.windows.ws2_32.SOCKET_ERROR) {
				switch(std.os.windows.ws2_32.WSAGetLastError()) {
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
			var pfd = [1]posix.pollfd{
				.{.fd = self.socketID, .events = posix.POLL.IN, .revents = undefined},
			};
			const length = try posix.poll(&pfd, timeout);
			if(length == 0) return error.Timeout;
		}
		var addr: posix.sockaddr.in = undefined;
		var addrLen: posix.socklen_t = @sizeOf(posix.sockaddr.in);
		const length = try posix.recvfrom(self.socketID, buffer, 0, @ptrCast(&addr), &addrLen);
		resultAddress.ip = addr.addr;
		resultAddress.port = @byteSwap(addr.port);
		return buffer[0..length];
	}

	fn resolveIP(addr: []const u8) !u32 {
		const list = try std.net.getAddressList(main.stackAllocator.allocator, addr, settings.defaultPort);
		defer list.deinit();
		return list.addrs[0].in.sa.addr;
	}

	fn getPort(self: Socket) !u16 {
		var addr: posix.sockaddr.in = undefined;
		var addrLen: posix.socklen_t = @sizeOf(posix.sockaddr.in);
		try posix.getsockname(self.socketID, @ptrCast(&addr), &addrLen);
		return @byteSwap(addr.port);
	}
};

pub fn init() void {
	Socket.startup();
	inline for(@typeInfo(Protocols).@"struct".decls) |decl| {
		if(@TypeOf(@field(Protocols, decl.name)) == type) {
			const id = @field(Protocols, decl.name).id;
			if(id != Protocols.keepAlive and id != Protocols.important and Protocols.list[id] == null) {
				Protocols.list[id] = @field(Protocols, decl.name).receive;
				Protocols.isAsynchronous[id] = @field(Protocols, decl.name).asynchronous;
			} else {
				std.log.err("Duplicate list id {}.", .{id});
			}
		}
	}
}

pub const Address = struct {
	ip: u32,
	port: u16,
	isSymmetricNAT: bool = false,

	pub fn format(self: Address, _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
		if(self.isSymmetricNAT) {
			try writer.print("{}.{}.{}.{}:?{}", .{self.ip & 255, self.ip >> 8 & 255, self.ip >> 16 & 255, self.ip >> 24, self.port});
		} else {
			try writer.print("{}.{}.{}.{}:{}", .{self.ip & 255, self.ip >> 8 & 255, self.ip >> 16 & 255, self.ip >> 24, self.port});
		}
	}
};

const Request = struct {
	address: Address,
	data: []const u8,
	requestNotifier: std.Thread.Condition = std.Thread.Condition{},
};

/// Implements parts of the STUN(Session Traversal Utilities for NAT) protocol to discover public IP+Port
/// Reference: https://datatracker.ietf.org/doc/html/rfc5389
const STUN = struct { // MARK: STUN
	const ipServerList = [_][]const u8{
		"stun.12voip.com:3478",
		"stun.1und1.de:3478",
		"stun.acrobits.cz:3478",
		"stun.actionvoip.com:3478",
		"stun.antisip.com:3478",
		"stun.avigora.fr:3478",
		"stun.bluesip.net:3478",
		"stun.cablenet-as.net:3478",
		"stun.callromania.ro:3478",
		"stun.cheapvoip.com:3478",
		"stun.cope.es:3478",
		"stun.counterpath.com:3478",
		"stun.counterpath.net:3478",
		"stun.dcalling.de:3478",
		"stun.dus.net:3478",
		"stun.ekiga.net:3478",
		"stun.epygi.com:3478",
		"stun.freeswitch.org:3478",
		"stun.freevoipdeal.com:3478",
		"stun.gmx.de:3478",
		"stun.gmx.net:3478",
		"stun.halonet.pl:3478",
		"stun.hoiio.com:3478",
		"stun.internetcalls.com:3478",
		"stun.intervoip.com:3478",
		"stun.ipfire.org:3478",
		"stun.ippi.fr:3478",
		"stun.ipshka.com:3478",
		"stun.it1.hr:3478",
		"stun.jumblo.com:3478",
		"stun.justvoip.com:3478",
		"stun.l.google.com:19302",
		"stun.linphone.org:3478",
		"stun.liveo.fr:3478",
		"stun.lowratevoip.com:3478",
		"stun.myvoiptraffic.com:3478",
		"stun.netappel.com:3478",
		"stun.netgsm.com.tr:3478",
		"stun.nfon.net:3478",
		"stun.nonoh.net:3478",
		"stun.ozekiphone.com:3478",
		"stun.pjsip.org:3478",
		"stun.powervoip.com:3478",
		"stun.ppdi.com:3478",
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
		"stun.siptraffic.com:3478",
		"stun.smartvoip.com:3478",
		"stun.smsdiscount.com:3478",
		"stun.solcon.nl:3478",
		"stun.solnet.ch:3478",
		"stun.sonetel.com:3478",
		"stun.sonetel.net:3478",
		"stun.srce.hr:3478",
		"stun.t-online.de:3478",
		"stun.tel.lu:3478",
		"stun.telbo.com:3478",
		"stun.tng.de:3478",
		"stun.twt.it:3478",
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
	const MAGIC_COOKIE = [_]u8{0x21, 0x12, 0xA4, 0x42};

	fn requestAddress(connection: *ConnectionManager) Address {
		var oldAddress: ?Address = null;
		var seed: [std.Random.DefaultCsprng.secret_seed_length]u8 = @splat(0);
		std.mem.writeInt(i128, seed[0..16], std.time.nanoTimestamp(), builtin.cpu.arch.endian()); // Not the best seed, but it's not that important.
		var random = std.Random.DefaultCsprng.init(seed);
		for(0..16) |_| {
			// Choose a somewhat random server, so we faster notice if any one of them stopped working.
			const server = ipServerList[random.random().intRangeAtMost(usize, 0, ipServerList.len - 1)];
			var data = [_]u8{
				0x00, 0x01, // message type
				0x00, 0x00, // message length
				MAGIC_COOKIE[0], MAGIC_COOKIE[1], MAGIC_COOKIE[2], MAGIC_COOKIE[3], // "Magic cookie"
				0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // transaction ID
			};
			random.fill(data[8..]); // Fill the transaction ID.

			var splitter = std.mem.splitScalar(u8, server, ':');
			const ip = splitter.first();
			const serverAddress = Address{
				.ip = Socket.resolveIP(ip) catch |err| {
					std.log.warn("Cannot resolve stun server address: {s}, error: {s}", .{ip, @errorName(err)});
					continue;
				},
				.port = std.fmt.parseUnsigned(u16, splitter.rest(), 10) catch 3478,
			};
			if(connection.sendRequest(main.globalAllocator, &data, serverAddress, 500*1000000)) |answer| {
				defer main.globalAllocator.free(answer);
				verifyHeader(answer, data[8..20]) catch |err| {
					std.log.err("Header verification failed with {s} for STUN server: {s} data: {any}", .{@errorName(err), server, answer});
					continue;
				};
				var result = findIPPort(answer) catch |err| {
					std.log.err("Could not parse IP+Port: {s} for STUN server: {s} data: {any}", .{@errorName(err), server, answer});
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
		return Address{.ip = Socket.resolveIP("127.0.0.1") catch unreachable, .port = settings.defaultPort}; // TODO: Return ip address in LAN.
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
						return Address{
							.port = std.mem.readInt(u16, addressData[0..2], .big),
							.ip = std.mem.readInt(u32, addressData[2..6], builtin.cpu.arch.endian()), // Needs to stay in big endian → native.
						};
					} else if(data[1] == 0x02) {
						data = data[(len + 3) & ~@as(usize, 3) ..]; // Pad to 32 Bit.
						continue; // I don't care about IPv6.
					} else {
						return error.UnknownAddressFamily;
					}
				},
				else => {
					data = data[(len + 3) & ~@as(usize, 3) ..]; // Pad to 32 Bit.
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
			if(data[i + 8] != transactionID[i]) return error.WrongTransaction;
		}
	}
};

pub const ConnectionManager = struct { // MARK: ConnectionManager
	socket: Socket = undefined,
	thread: std.Thread = undefined,
	threadId: std.Thread.Id = undefined,
	externalAddress: Address = undefined,
	online: Atomic(bool) = .init(false),
	running: Atomic(bool) = .init(true),

	connections: main.List(*Connection) = undefined,
	requests: main.List(*Request) = undefined,

	mutex: std.Thread.Mutex = .{},
	waitingToFinishReceive: std.Thread.Condition = std.Thread.Condition{},
	newConnectionCallback: Atomic(?*const fn(Address) void) = .init(null),

	receiveBuffer: [Connection.maxPacketSize]u8 = undefined,

	world: ?*game.World = null,

	localPort: u16 = undefined,

	packetSendRequests: std.PriorityQueue(PacketSendRequest, void, PacketSendRequest.compare) = undefined,

	const PacketSendRequest = struct {
		data: []const u8,
		target: Address,
		time: i64,

		fn compare(_: void, a: PacketSendRequest, b: PacketSendRequest) std.math.Order {
			return std.math.order(a.time, b.time);
		}
	};

	pub fn init(localPort: u16, online: bool) !*ConnectionManager {
		const result: *ConnectionManager = main.globalAllocator.create(ConnectionManager);
		errdefer main.globalAllocator.destroy(result);
		result.* = .{};
		result.connections = .init(main.globalAllocator);
		result.requests = .init(main.globalAllocator);
		result.packetSendRequests = .init(main.globalAllocator.allocator, {});

		result.localPort = localPort;
		result.socket = Socket.init(localPort) catch |err| blk: {
			if(err == error.AddressInUse) {
				const socket = try Socket.init(0); // Use any port.
				result.localPort = try socket.getPort();
				break :blk socket;
			} else return err;
		};
		errdefer Socket.deinit(result.socket);
		if(localPort == 0) result.localPort = try result.socket.getPort();

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
		while(self.packetSendRequests.removeOrNull()) |packet| {
			main.globalAllocator.free(packet.data);
		}
		self.packetSendRequests.deinit();

		main.globalAllocator.destroy(self);
	}

	pub fn makeOnline(self: *ConnectionManager) void {
		if(!self.online.load(.acquire)) {
			self.externalAddress = STUN.requestAddress(self);
			self.online.store(true, .release);
		}
	}

	pub fn send(self: *ConnectionManager, data: []const u8, target: Address, nanoTime: ?i64) void {
		if(nanoTime) |time| {
			self.mutex.lock();
			defer self.mutex.unlock();
			self.packetSendRequests.add(.{
				.data = main.globalAllocator.dupe(u8, data),
				.target = target,
				.time = time,
			}) catch unreachable;
		} else {
			self.socket.send(data, target);
		}
	}

	pub fn sendRequest(self: *ConnectionManager, allocator: NeverFailingAllocator, data: []const u8, target: Address, timeout_ns: u64) ?[]const u8 {
		self.socket.send(data, target);
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

	pub fn addConnection(self: *ConnectionManager, conn: *Connection) error{AlreadyConnected}!void {
		self.mutex.lock();
		defer self.mutex.unlock();
		for(self.connections.items) |other| {
			if(other.remoteAddress.ip == conn.remoteAddress.ip and other.remoteAddress.port == conn.remoteAddress.port) return error.AlreadyConnected;
		}
		self.connections.append(conn);
	}

	pub fn finishCurrentReceive(self: *ConnectionManager) void {
		std.debug.assert(self.threadId != std.Thread.getCurrentId()); // WOuld cause deadlock, since we are in a receive.
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
		{
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
		}
		if(self.newConnectionCallback.load(.monotonic)) |callback| {
			callback(source);
		} else {
			// TODO: Reduce the number of false alarms in the short period after a disconnect.
			std.log.warn("Unknown connection from address: {}", .{source});
			std.log.debug("Message: {any}", .{data});
		}
	}

	pub fn run(self: *ConnectionManager) void {
		self.threadId = std.Thread.getCurrentId();
		var sta = main.heap.StackAllocator.init(main.globalAllocator, 1 << 23);
		defer sta.deinit();
		main.stackAllocator = sta.allocator();

		var lastTime: i64 = @truncate(std.time.nanoTimestamp());
		while(self.running.load(.monotonic)) {
			self.waitingToFinishReceive.broadcast();
			var source: Address = undefined;
			if(self.socket.receive(&self.receiveBuffer, 1, &source)) |data| {
				self.onReceive(data, source);
			} else |err| {
				if(err == error.Timeout) {
					// No message within the last ~100 ms.
				} else if(err == error.ConnectionResetByPeer) {
					std.log.err("Got error.ConnectionResetByPeer on receive. This indicates that a previous message did not find a valid destination.", .{});
				} else {
					std.log.err("Got error on receive: {s}", .{@errorName(err)});
					@panic("Network failed.");
				}
			}
			const curTime: i64 = @truncate(std.time.nanoTimestamp());
			{
				self.mutex.lock();
				defer self.mutex.unlock();
				while(self.packetSendRequests.peek() != null and self.packetSendRequests.peek().?.time -% curTime <= 0) {
					const packet = self.packetSendRequests.remove();
					self.socket.send(packet.data, packet.target);
					main.globalAllocator.free(packet.data);
				}
			}

			// Send a keep-alive packet roughly every 100 ms:
			if(curTime -% lastTime > 100_000_000) {
				lastTime = curTime;
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
						if(conn.user) |user| {
							main.server.disconnect(user);
						}
						self.mutex.lock();
					} else {
						self.mutex.unlock();
						conn.sendKeepAlive();
						self.mutex.lock();
						i += 1;
					}
				}
				if(self.connections.items.len == 0 and self.online.load(.acquire)) {
					// Send a message to external ip, to keep the port open:
					const data = [1]u8{0};
					self.socket.send(&data, self.externalAddress);
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

// MARK: Protocols
pub var bytesReceived: [256]Atomic(usize) = @splat(.init(0));
pub var packetsReceived: [256]Atomic(usize) = @splat(.init(0));
pub const Protocols = struct {
	pub var list: [256]?*const fn(*Connection, *utils.BinaryReader) anyerror!void = @splat(null);
	pub var isAsynchronous: [256]bool = @splat(false);

	pub const keepAlive: u8 = 0;
	pub const important: u8 = 0xff;
	pub const handShake = struct {
		pub const id: u8 = 1;
		pub const asynchronous = false;
		const stepStart: u8 = 0;
		const stepUserData: u8 = 1;
		const stepAssets: u8 = 2;
		const stepServerData: u8 = 3;
		pub const stepComplete: u8 = 255;

		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const newState = try reader.readInt(u8);
			if(conn.handShakeState.load(.monotonic) < newState) {
				conn.handShakeState.store(newState, .monotonic);
				switch(newState) {
					stepUserData => {
						const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
						defer zon.deinit(main.stackAllocator);
						const name = zon.get([]const u8, "name", "unnamed");
						if(name.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(name) > 50) {
							std.log.err("Player has too long name with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(name), name.len});
							return error.Invalid;
						}
						const version = zon.get([]const u8, "version", "unknown");
						std.log.info("User {s} joined using version {s}.", .{name, version});

						{
							const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets/", .{main.server.world.?.name}) catch unreachable;
							defer main.stackAllocator.free(path);
							var dir = try std.fs.cwd().openDir(path, .{.iterate = true});
							defer dir.close();
							var arrayList = main.List(u8).init(main.stackAllocator);
							defer arrayList.deinit();
							arrayList.append(stepAssets);
							try utils.Compression.pack(dir, arrayList.writer());
							conn.sendImportant(id, arrayList.items);
						}

						conn.user.?.initPlayer(name);
						const zonObject = ZonElement.initObject(main.stackAllocator);
						defer zonObject.deinit(main.stackAllocator);
						zonObject.put("player", conn.user.?.player.save(main.stackAllocator));
						zonObject.put("player_id", conn.user.?.id);
						zonObject.put("spawn", main.server.world.?.spawn);
						zonObject.put("blockPalette", main.server.world.?.blockPalette.storeToZon(main.stackAllocator));
						zonObject.put("itemPalette", main.server.world.?.itemPalette.storeToZon(main.stackAllocator));
						zonObject.put("biomePalette", main.server.world.?.biomePalette.storeToZon(main.stackAllocator));

						const outData = zonObject.toStringEfficient(main.stackAllocator, &[1]u8{stepServerData});
						defer main.stackAllocator.free(outData);
						conn.sendImportant(id, outData);
						conn.mutex.lock();
						conn.flush();
						conn.mutex.unlock();
						conn.handShakeState.store(stepServerData, .monotonic);
						main.server.connect(conn.user.?);
					},
					stepAssets => {
						std.log.info("Received assets.", .{});
						std.fs.cwd().deleteTree("serverAssets") catch {}; // Delete old assets.
						var dir = try std.fs.cwd().makeOpenPath("serverAssets", .{});
						defer dir.close();
						try utils.Compression.unpack(dir, reader.remaining);
					},
					stepServerData => {
						const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
						defer zon.deinit(main.stackAllocator);
						try conn.manager.world.?.finishHandshake(zon);
						conn.handShakeState.store(stepComplete, .monotonic);
						conn.handShakeWaiting.broadcast(); // Notify the waiting client thread.
					},
					stepComplete => {},
					else => {
						std.log.err("Unknown state in HandShakeProtocol {}", .{newState});
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
			const zonObject = ZonElement.initObject(main.stackAllocator);
			defer zonObject.deinit(main.stackAllocator);
			zonObject.putOwnedString("version", settings.version);
			zonObject.putOwnedString("name", name);
			const prefix = [1]u8{stepUserData};
			const data = zonObject.toStringEfficient(main.stackAllocator, &prefix);
			defer main.stackAllocator.free(data);
			conn.sendImportant(id, data);

			conn.mutex.lock();
			conn.flush();
			conn.handShakeWaiting.wait(&conn.mutex);
			conn.mutex.unlock();
		}
	};
	pub const chunkRequest = struct {
		pub const id: u8 = 2;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const basePosition = Vec3i{
				try reader.readInt(i32),
				try reader.readInt(i32),
				try reader.readInt(i32),
			};
			conn.user.?.clientUpdatePos = basePosition;
			conn.user.?.renderDistance = try reader.readInt(u16);
			while(reader.remaining.len >= 4) {
				const x: i32 = try reader.readInt(i8);
				const y: i32 = try reader.readInt(i8);
				const z: i32 = try reader.readInt(i8);
				const voxelSizeShift: u5 = try reader.readInt(u5);
				const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
				const request = chunk.ChunkPosition{
					.wx = (x << voxelSizeShift + chunk.chunkShift) +% (basePosition[0] & positionMask),
					.wy = (y << voxelSizeShift + chunk.chunkShift) +% (basePosition[1] & positionMask),
					.wz = (z << voxelSizeShift + chunk.chunkShift) +% (basePosition[2] & positionMask),
					.voxelSize = @as(u31, 1) << voxelSizeShift,
				};
				if(conn.user) |user| {
					user.increaseRefCount();
					main.server.world.?.queueChunkAndDecreaseRefCount(request, user);
				}
			}
		}
		pub fn sendRequest(conn: *Connection, requests: []chunk.ChunkPosition, basePosition: Vec3i, renderDistance: u16) void {
			if(requests.len == 0) return;
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 14 + 4*requests.len);
			defer writer.deinit();
			writer.writeInt(i32, basePosition[0]);
			writer.writeInt(i32, basePosition[1]);
			writer.writeInt(i32, basePosition[2]);
			writer.writeInt(u16, renderDistance);
			for(requests) |req| {
				const voxelSizeShift: u5 = std.math.log2_int(u31, req.voxelSize);
				const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
				writer.writeInt(i8, @intCast((req.wx -% (basePosition[0] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
				writer.writeInt(i8, @intCast((req.wy -% (basePosition[1] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
				writer.writeInt(i8, @intCast((req.wz -% (basePosition[2] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
				writer.writeInt(u5, voxelSizeShift);
			}
			conn.sendImportant(id, writer.data.items);
		}
	};
	pub const chunkTransmission = struct {
		pub const id: u8 = 3;
		pub const asynchronous = true;
		fn receive(_: *Connection, reader: *utils.BinaryReader) !void {
			const pos = chunk.ChunkPosition{
				.wx = try reader.readInt(i32),
				.wy = try reader.readInt(i32),
				.wz = try reader.readInt(i32),
				.voxelSize = try reader.readInt(u31),
			};
			const ch = chunk.Chunk.init(pos);
			try main.server.storage.ChunkCompression.decompressChunk(ch, reader.remaining);
			renderer.mesh_storage.updateChunkMesh(ch);
		}
		fn sendChunkOverTheNetwork(conn: *Connection, ch: *chunk.ServerChunk) void {
			ch.mutex.lock();
			const chunkData = main.server.storage.ChunkCompression.compressChunk(main.stackAllocator, &ch.super, ch.super.pos.voxelSize != 1);
			ch.mutex.unlock();
			defer main.stackAllocator.free(chunkData);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, chunkData.len + 16);
			defer writer.deinit();
			writer.writeInt(i32, ch.super.pos.wx);
			writer.writeInt(i32, ch.super.pos.wy);
			writer.writeInt(i32, ch.super.pos.wz);
			writer.writeInt(u31, ch.super.pos.voxelSize);
			writer.writeSlice(chunkData);
			conn.sendImportant(id, writer.data.items);
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
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			try conn.user.?.receiveData(reader);
		}
		var lastPositionSent: u16 = 0;
		pub fn send(conn: *Connection, playerPos: Vec3d, playerVel: Vec3d, time: u16) void {
			if(time -% lastPositionSent < 50) {
				return; // Only send at most once every 50 ms.
			}
			lastPositionSent = time;
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 62);
			defer writer.deinit();
			writer.writeInt(u64, @bitCast(playerPos[0]));
			writer.writeInt(u64, @bitCast(playerPos[1]));
			writer.writeInt(u64, @bitCast(playerPos[2]));
			writer.writeInt(u64, @bitCast(playerVel[0]));
			writer.writeInt(u64, @bitCast(playerVel[1]));
			writer.writeInt(u64, @bitCast(playerVel[2]));
			writer.writeInt(u32, @bitCast(game.camera.rotation[0]));
			writer.writeInt(u32, @bitCast(game.camera.rotation[1]));
			writer.writeInt(u32, @bitCast(game.camera.rotation[2]));
			writer.writeInt(u16, time);
			conn.sendUnimportant(id, writer.data.items);
		}
	};
	pub const disconnect = struct {
		pub const id: u8 = 5;
		pub const asynchronous = false;
		fn receive(conn: *Connection, _: *utils.BinaryReader) !void {
			conn.disconnect();
			if(conn.user) |user| {
				main.server.disconnect(user);
			} else {
				main.exitToMenu(undefined);
			}
		}
		pub fn disconnect(conn: *Connection) void {
			const noData = [0]u8{};
			conn.sendUnimportant(id, &noData);
		}
	};
	pub const entityPosition = struct {
		pub const id: u8 = 6;
		pub const asynchronous = false;
		const type_entity: u8 = 0;
		const type_item: u8 = 1;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			if(conn.manager.world) |world| {
				const typ = try reader.readInt(u8);
				const time = try reader.readInt(i16);
				if(typ == type_entity) {
					try main.entity.ClientEntityManager.serverUpdate(time, reader);
				} else if(typ == type_item) {
					try world.itemDrops.readPosition(reader, time);
				}
			}
		}
		pub fn send(conn: *Connection, entityData: []const u8, itemData: []const u8) void {
			if(entityData.len != 0) {
				var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, entityData.len + 3);
				defer writer.deinit();
				writer.writeInt(u8, type_entity);
				writer.writeInt(i16, @truncate(std.time.milliTimestamp()));
				writer.writeSlice(entityData);
				conn.sendUnimportant(id, writer.data.items);
			}

			if(itemData.len != 0) {
				var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, itemData.len + 3);
				defer writer.deinit();
				writer.writeInt(u8, type_item);
				writer.writeInt(i16, @truncate(std.time.milliTimestamp()));
				writer.writeSlice(itemData);
				conn.sendUnimportant(id, writer.data.items);
			}
		}
	};
	pub const blockUpdate = struct {
		pub const id: u8 = 7;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const x = try reader.readInt(i32);
			const y = try reader.readInt(i32);
			const z = try reader.readInt(i32);
			const newBlock = Block.fromInt(try reader.readInt(u32));
			if(conn.user != null) {
				return error.InvalidPacket;
			} else {
				renderer.mesh_storage.updateBlock(x, y, z, newBlock);
			}
		}
		pub fn send(conn: *Connection, x: i32, y: i32, z: i32, newBlock: Block) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 16);
			defer writer.deinit();
			writer.writeInt(i32, x);
			writer.writeInt(i32, y);
			writer.writeInt(i32, z);
			writer.writeInt(u32, newBlock.toInt());
			conn.sendImportant(id, writer.data.items);
		}
	};
	pub const entity = struct {
		pub const id: u8 = 8;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const zonArray = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
			defer zonArray.deinit(main.stackAllocator);
			var i: u32 = 0;
			while(i < zonArray.array.items.len) : (i += 1) {
				const elem = zonArray.array.items[i];
				switch(elem) {
					.int => {
						main.entity.ClientEntityManager.removeEntity(elem.as(u32, 0));
					},
					.object => {
						main.entity.ClientEntityManager.addEntity(elem);
					},
					.null => {
						i += 1;
						break;
					},
					else => {
						std.log.err("Unrecognized zon parameters for protocol {}: {s}", .{id, reader.remaining});
					},
				}
			}
			while(i < zonArray.array.items.len) : (i += 1) {
				const elem: ZonElement = zonArray.array.items[i];
				if(elem == .int) {
					conn.manager.world.?.itemDrops.remove(elem.as(u16, 0));
				} else if(!elem.getChild("array").isNull()) {
					conn.manager.world.?.itemDrops.loadFrom(elem);
				} else {
					conn.manager.world.?.itemDrops.addFromZon(elem);
				}
			}
		}
		pub fn send(conn: *Connection, msg: []const u8) void {
			conn.sendImportant(id, msg);
		}
	};
	pub const genericUpdate = struct {
		pub const id: u8 = 9;
		pub const asynchronous = false;
		const type_gamemode: u8 = 0;
		const type_teleport: u8 = 1;
		const type_cure: u8 = 2;
		const type_worldEditPos: u8 = 3;
		const type_reserved3: u8 = 4;
		const type_reserved4: u8 = 5;
		const type_reserved5: u8 = 6;
		const type_reserved6: u8 = 7;
		const type_timeAndBiome: u8 = 8;

		const WorldEditPosition = enum(u2) {
			selectedPos1 = 0,
			selectedPos2 = 1,
			clear = 2,
		};

		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			switch(try reader.readInt(u8)) {
				type_gamemode => {
					if(conn.user != null) return error.InvalidPacket;
					main.items.Inventory.Sync.setGamemode(null, try reader.readEnum(main.game.Gamemode));
				},
				type_teleport => {
					game.Player.setPosBlocking(Vec3d{
						@bitCast(try reader.readInt(u64)),
						@bitCast(try reader.readInt(u64)),
						@bitCast(try reader.readInt(u64)),
					});
				},
				type_cure => {
					// TODO: health and hunger
				},
				type_worldEditPos => {
					const typ = try reader.readEnum(WorldEditPosition);
					switch(typ) {
						.selectedPos1, .selectedPos2 => {
							const pos = Vec3i{
								try reader.readInt(i32),
								try reader.readInt(i32),
								try reader.readInt(i32),
							};
							switch(typ) {
								.selectedPos1 => game.Player.selectionPosition1 = pos,
								.selectedPos2 => game.Player.selectionPosition2 = pos,
								else => unreachable,
							}
						},
						.clear => {
							game.Player.selectionPosition1 = null;
							game.Player.selectionPosition2 = null;
						},
					}
				},
				type_reserved3 => {},
				type_reserved4 => {},
				type_reserved5 => {},
				type_reserved6 => {},
				type_timeAndBiome => {
					if(conn.manager.world) |world| {
						const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
						defer zon.deinit(main.stackAllocator);
						const expectedTime = zon.get(i64, "time", 0);
						var curTime = world.gameTime.load(.monotonic);
						if(@abs(curTime -% expectedTime) >= 10) {
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
						const newBiome = main.server.terrain.biomes.getById(zon.get([]const u8, "biome", ""));
						const oldBiome = world.playerBiome.swap(newBiome, .monotonic);
						if(oldBiome != newBiome) {
							main.audio.setMusic(newBiome.preferredMusic);
						}
					}
				},
				else => |unrecognizedType| {
					std.log.err("Unrecognized type for genericUpdateProtocol: {}. Data: {any}", .{unrecognizedType, reader.remaining});
					return error.Invalid;
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

		pub fn sendGamemode(conn: *Connection, gamemode: main.game.Gamemode) void {
			conn.sendImportant(id, &.{type_gamemode, @intFromEnum(gamemode)});
		}

		pub fn sendTPCoordinates(conn: *Connection, pos: Vec3d) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 25);
			defer writer.deinit();
			writer.writeInt(u8, type_teleport);
			writer.writeInt(u64, @bitCast(pos[0]));
			writer.writeInt(u64, @bitCast(pos[1]));
			writer.writeInt(u64, @bitCast(pos[2]));
			conn.sendImportant(id, writer.data.items);
		}

		pub fn sendCure(conn: *Connection) void {
			var data: [1]u8 = undefined;
			data[0] = type_cure;
			conn.sendImportant(id, &data);
		}

		pub fn sendWorldEditPos(conn: *Connection, posType: WorldEditPosition, maybePos: ?Vec3i) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 25);
			defer writer.deinit();
			writer.writeInt(u8, type_worldEditPos);
			writer.writeEnum(WorldEditPosition, posType);
			if(maybePos) |pos| {
				writer.writeInt(i32, pos[0]);
				writer.writeInt(i32, pos[1]);
				writer.writeInt(i32, pos[2]);
			}
			conn.sendImportant(id, writer.data.items);
		}

		pub fn sendTimeAndBiome(conn: *Connection, world: *const main.server.ServerWorld) void {
			const zon = ZonElement.initObject(main.stackAllocator);
			defer zon.deinit(main.stackAllocator);
			zon.put("time", world.gameTime);
			const pos = conn.user.?.player.pos;
			zon.put("biome", (world.getBiome(@intFromFloat(pos[0]), @intFromFloat(pos[1]), @intFromFloat(pos[2]))).id);
			const string = zon.toString(main.stackAllocator);
			defer main.stackAllocator.free(string);
			addHeaderAndSendUnimportant(conn, type_timeAndBiome, string);
		}
	};
	pub const chat = struct {
		pub const id: u8 = 10;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const msg = reader.remaining;
			if(conn.user) |user| {
				if(msg.len > 10000 or main.graphics.TextBuffer.Parser.countVisibleCharacters(msg) > 1000) {
					std.log.err("Received too long chat message with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(msg), msg.len});
					return error.Invalid;
				}
				main.server.messageFrom(msg, user);
			} else {
				main.gui.windowlist.chat.addMessage(msg);
			}
		}

		pub fn send(conn: *Connection, msg: []const u8) void {
			conn.sendImportant(id, msg);
		}
	};
	pub const lightMapRequest = struct {
		pub const id: u8 = 11;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			while(reader.remaining.len >= 9) {
				const wx = try reader.readInt(i32);
				const wy = try reader.readInt(i32);
				const voxelSizeShift = try reader.readInt(u5);
				const request = main.server.terrain.SurfaceMap.MapFragmentPosition{
					.wx = wx,
					.wy = wy,
					.voxelSize = @as(u31, 1) << voxelSizeShift,
					.voxelSizeShift = voxelSizeShift,
				};
				if(conn.user) |user| {
					user.increaseRefCount();
					main.server.world.?.queueLightMapAndDecreaseRefCount(request, user);
				}
			}
		}
		pub fn sendRequest(conn: *Connection, requests: []main.server.terrain.SurfaceMap.MapFragmentPosition) void {
			if(requests.len == 0) return;
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 9*requests.len);
			defer writer.deinit();
			for(requests) |req| {
				writer.writeInt(i32, req.wx);
				writer.writeInt(i32, req.wy);
				writer.writeInt(u8, req.voxelSizeShift);
			}
			conn.sendImportant(id, writer.data.items);
		}
	};
	pub const lightMapTransmission = struct {
		pub const id: u8 = 12;
		pub const asynchronous = true;
		fn receive(_: *Connection, reader: *utils.BinaryReader) !void {
			const wx = try reader.readInt(i32);
			const wy = try reader.readInt(i32);
			const voxelSizeShift = try reader.readInt(u5);
			const pos = main.server.terrain.SurfaceMap.MapFragmentPosition{
				.wx = wx,
				.wy = wy,
				.voxelSize = @as(u31, 1) << voxelSizeShift,
				.voxelSizeShift = voxelSizeShift,
			};
			const _inflatedData = main.stackAllocator.alloc(u8, main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2);
			defer main.stackAllocator.free(_inflatedData);
			const _inflatedLen = try utils.Compression.inflateTo(_inflatedData, reader.remaining);
			if(_inflatedLen != main.server.terrain.LightMap.LightMapFragment.mapSize*main.server.terrain.LightMap.LightMapFragment.mapSize*2) {
				std.log.err("Transmission of light map has invalid size: {}. Input data: {any}, After inflate: {any}", .{_inflatedLen, reader.remaining, _inflatedData[0.._inflatedLen]});
				return error.Invalid;
			}
			var ligthMapReader = utils.BinaryReader.init(_inflatedData, networkEndian);
			const map = main.globalAllocator.create(main.server.terrain.LightMap.LightMapFragment);
			map.init(pos.wx, pos.wy, pos.voxelSize);
			_ = map.refCount.fetchAdd(1, .monotonic);
			for(&map.startHeight) |*val| {
				val.* = try ligthMapReader.readInt(i16);
			}
			renderer.mesh_storage.updateLightMap(map);
		}
		pub fn sendLightMap(conn: *Connection, map: *main.server.terrain.LightMap.LightMapFragment) void {
			var ligthMapWriter = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, @sizeOf(@TypeOf(map.startHeight)));
			defer ligthMapWriter.deinit();
			for(&map.startHeight) |val| {
				ligthMapWriter.writeInt(i16, val);
			}
			const compressedData = utils.Compression.deflate(main.stackAllocator, ligthMapWriter.data.items, .default);
			defer main.stackAllocator.free(compressedData);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, 9 + compressedData.len);
			defer writer.deinit();
			writer.writeInt(i32, map.pos.wx);
			writer.writeInt(i32, map.pos.wy);
			writer.writeInt(u8, map.pos.voxelSizeShift);
			writer.writeSlice(compressedData);
			conn.sendImportant(id, writer.data.items);
		}
	};
	pub const inventory = struct {
		pub const id: u8 = 13;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			if(conn.user) |user| {
				if(reader.remaining[0] == 0xff) return error.InvalidPacket;
				try items.Inventory.Sync.ServerSide.receiveCommand(user, reader);
			} else {
				const typ = try reader.readInt(u8);
				if(typ == 0xff) { // Confirmation
					try items.Inventory.Sync.ClientSide.receiveConfirmation(reader);
				} else if(typ == 0xfe) { // Failure
					items.Inventory.Sync.ClientSide.receiveFailure();
				} else {
					try items.Inventory.Sync.ClientSide.receiveSyncOperation(reader);
				}
			}
		}
		pub fn sendCommand(conn: *Connection, payloadType: items.Inventory.Command.PayloadType, _data: []const u8) void {
			std.debug.assert(conn.user == null);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, _data.len + 1);
			defer writer.deinit();
			writer.writeEnum(items.Inventory.Command.PayloadType, payloadType);
			std.debug.assert(writer.data.items[0] != 0xff);
			writer.writeSlice(_data);
			conn.sendImportant(id, writer.data.items);
		}
		pub fn sendConfirmation(conn: *Connection, _data: []const u8) void {
			std.debug.assert(conn.user != null);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, _data.len + 1);
			defer writer.deinit();
			writer.writeInt(u8, 0xff);
			writer.writeSlice(_data);
			conn.sendImportant(id, writer.data.items);
		}
		pub fn sendFailure(conn: *Connection) void {
			std.debug.assert(conn.user != null);
			conn.sendImportant(id, &.{0xfe});
		}
		pub fn sendSyncOperation(conn: *Connection, _data: []const u8) void {
			std.debug.assert(conn.user != null);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, networkEndian, _data.len + 1);
			defer writer.deinit();
			writer.writeInt(u8, 0);
			writer.writeSlice(_data);
			conn.sendImportant(id, writer.data.items);
		}
	};
};

pub const Connection = struct { // MARK: Connection
	const maxPacketSize: u32 = 65507; // max udp packet size
	const importantHeaderSize: u32 = 5;
	const maxImportantPacketSize: u32 = 576 - 20 - 8; // IPv4 MTU minus IP header minus udp header
	const headerOverhead = 20 + 8 + 42; // IP Header + UDP Header + Ethernet header/footer
	const congestionControl_historySize = 16;
	const congestionControl_historyMask = congestionControl_historySize - 1;
	const minimumBandWidth = 10_000;
	const timeUnit = 100_000_000;

	// Statistics:
	pub var packetsSent: Atomic(u32) = .init(0);
	pub var packetsResent: Atomic(u32) = .init(0);

	manager: *ConnectionManager,
	user: ?*main.server.User,

	remoteAddress: Address,
	bruteforcingPort: bool = false,
	bruteForcedPortRange: u16 = 0,

	streamBuffer: [maxImportantPacketSize]u8 = undefined,
	streamPosition: u32 = importantHeaderSize,
	messageID: u32 = 0,
	packetQueue: main.utils.CircularBufferQueue(UnconfirmedPacket) = undefined,
	unconfirmedPackets: main.List(UnconfirmedPacket) = undefined,
	receivedPackets: [3]main.List(u32) = undefined,
	__lastReceivedPackets: [65536]?[]const u8 = @splat(null), // TODO: Wait for #12215 fix.
	lastReceivedPackets: []?[]const u8, // TODO: Wait for #12215 fix.
	packetMemory: *[65536][maxImportantPacketSize]u8 = undefined,
	lastIndex: u32 = 0,

	lastIncompletePacket: u32 = 0,

	lastKeepAliveSent: u32 = 0,
	lastKeepAliveReceived: u32 = 0,
	otherKeepAliveReceived: u32 = 0,

	congestionControl_bandWidthSentHistory: [congestionControl_historySize]usize = @splat(0),
	congestionControl_bandWidthReceivedHistory: [congestionControl_historySize]usize = @splat(0),
	congestionControl_bandWidthEstimate: usize = minimumBandWidth,
	congestionControl_inversebandWidth: f32 = timeUnit/minimumBandWidth,
	congestionControl_lastSendTime: i64,
	congestionControl_sendTimeLimit: i64,
	congestionControl_bandWidthUsed: usize = 0,
	congestionControl_curPosition: usize = 0,

	disconnected: Atomic(bool) = .init(false),
	handShakeState: Atomic(u8) = .init(Protocols.handShake.stepStart),
	handShakeWaiting: std.Thread.Condition = std.Thread.Condition{},
	lastConnection: i64,

	mutex: std.Thread.Mutex = .{},

	pub fn init(manager: *ConnectionManager, ipPort: []const u8, user: ?*main.server.User) !*Connection {
		const result: *Connection = main.globalAllocator.create(Connection);
		errdefer main.globalAllocator.destroy(result);
		result.* = Connection{
			.manager = manager,
			.user = user,
			.remoteAddress = undefined,
			.lastConnection = @truncate(std.time.nanoTimestamp()),
			.lastReceivedPackets = &result.__lastReceivedPackets, // TODO: Wait for #12215 fix.
			.packetMemory = main.globalAllocator.create([65536][maxImportantPacketSize]u8),
			.congestionControl_lastSendTime = @truncate(std.time.nanoTimestamp()),
			.congestionControl_sendTimeLimit = @as(i64, @truncate(std.time.nanoTimestamp())) +% timeUnit*21/20,
		};
		errdefer main.globalAllocator.free(result.packetMemory);
		result.unconfirmedPackets = .init(main.globalAllocator);
		errdefer result.unconfirmedPackets.deinit();
		result.packetQueue = .init(main.globalAllocator, 1024);
		errdefer result.packetQueue.deinit();
		result.receivedPackets = [3]main.List(u32){
			.init(main.globalAllocator),
			.init(main.globalAllocator),
			.init(main.globalAllocator),
		};
		errdefer for(&result.receivedPackets) |*list| {
			list.deinit();
		};
		var splitter = std.mem.splitScalar(u8, ipPort, ':');
		const ip = splitter.first();
		result.remoteAddress.ip = try Socket.resolveIP(ip);
		var port = splitter.rest();
		if(port.len != 0 and port[0] == '?') {
			result.remoteAddress.isSymmetricNAT = true;
			result.bruteforcingPort = true;
			port = port[1..];
		}
		result.remoteAddress.port = std.fmt.parseUnsigned(u16, port, 10) catch blk: {
			if(ip.len != ipPort.len) std.log.err("Could not parse port \"{s}\". Using default port instead.", .{port});
			break :blk settings.defaultPort;
		};

		try result.manager.addConnection(result);
		return result;
	}

	fn reinitialize(self: *Connection) void {
		main.utils.assertLocked(&self.mutex);
		self.streamPosition = importantHeaderSize;
		self.messageID = 0;
		while(self.packetQueue.dequeue()) |packet| {
			main.globalAllocator.free(packet.data);
		}
		for(self.unconfirmedPackets.items) |packet| {
			main.globalAllocator.free(packet.data);
		}
		self.unconfirmedPackets.clearRetainingCapacity();
		self.receivedPackets[0].clearRetainingCapacity();
		self.receivedPackets[1].clearRetainingCapacity();
		self.receivedPackets[2].clearRetainingCapacity();
		self.lastIndex = 0;
		self.lastIncompletePacket = 0;
		self.handShakeState = .init(Protocols.handShake.stepStart);
	}

	pub fn deinit(self: *Connection) void {
		self.disconnect();
		self.manager.finishCurrentReceive(); // Wait until all currently received packets are done.
		for(self.unconfirmedPackets.items) |packet| {
			main.globalAllocator.free(packet.data);
		}
		self.unconfirmedPackets.deinit();
		while(self.packetQueue.dequeue()) |packet| {
			main.globalAllocator.free(packet.data);
		}
		self.packetQueue.deinit();
		self.receivedPackets[0].deinit();
		self.receivedPackets[1].deinit();
		self.receivedPackets[2].deinit();
		main.globalAllocator.destroy(self.packetMemory);
		main.globalAllocator.destroy(self);
	}

	fn trySendingPacket(self: *Connection, data: []const u8) bool {
		std.debug.assert(data[0] == Protocols.important);
		const curTime: i64 = @truncate(std.time.nanoTimestamp());
		if(curTime -% self.congestionControl_lastSendTime > 0) {
			self.congestionControl_lastSendTime = curTime;
		}
		const shouldSend = self.congestionControl_bandWidthUsed < self.congestionControl_bandWidthEstimate and self.congestionControl_lastSendTime -% self.congestionControl_sendTimeLimit < 0;
		if(shouldSend) {
			_ = packetsSent.fetchAdd(1, .monotonic);
			self.manager.send(data, self.remoteAddress, self.congestionControl_lastSendTime);
			const packetSize = data.len + headerOverhead;
			self.congestionControl_lastSendTime +%= @intFromFloat(@as(f32, @floatFromInt(packetSize))*self.congestionControl_inversebandWidth);
			self.congestionControl_bandWidthUsed += packetSize;
		}
		return shouldSend;
	}

	fn flush(self: *Connection) void {
		main.utils.assertLocked(&self.mutex);
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
		if(self.trySendingPacket(packet.data)) {
			self.unconfirmedPackets.append(packet);
		} else {
			self.packetQueue.enqueue(packet);
		}
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

		if(self.disconnected.load(.unordered)) return;
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

		if(self.disconnected.load(.unordered)) return;
		std.debug.assert(data.len + 1 < maxPacketSize);
		const fullData = main.stackAllocator.alloc(u8, data.len + 1);
		defer main.stackAllocator.free(fullData);
		fullData[0] = id;
		@memcpy(fullData[1..], data);
		self.manager.send(fullData, self.remoteAddress, null);
	}

	fn receiveKeepAlive(self: *Connection, data: []const u8) void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		if(data.len == 0) return; // This is sent when brute forcing the port.
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
					const index = self.unconfirmedPackets.items[j].lastKeepAliveSentBefore & congestionControl_historyMask;
					self.congestionControl_bandWidthReceivedHistory[index] += self.unconfirmedPackets.items[j].data.len + headerOverhead;
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

		var runLengthEncodingStarts = main.List(u32).init(main.stackAllocator);
		defer runLengthEncodingStarts.deinit();
		var runLengthEncodingLengths = main.List(u32).init(main.stackAllocator);
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
			while(i >= 1) : (i -= 1) {
				self.receivedPackets[i] = self.receivedPackets[i - 1];
			}
			self.receivedPackets[0] = putBackToFront;
			self.receivedPackets[0].clearRetainingCapacity();
		}
		const output = main.stackAllocator.alloc(u8, runLengthEncodingStarts.items.len*8 + 9);
		defer main.stackAllocator.free(output);
		output[0] = Protocols.keepAlive;
		std.mem.writeInt(u32, output[1..5], self.lastKeepAliveSent, .big);
		std.mem.writeInt(u32, output[5..9], self.otherKeepAliveReceived, .big);
		var remaining: []u8 = output[9..];
		for(runLengthEncodingStarts.items, 0..) |_, i| {
			std.mem.writeInt(u32, remaining[0..4], runLengthEncodingStarts.items[i], .big);
			std.mem.writeInt(u32, remaining[4..8], runLengthEncodingLengths.items[i], .big);
			remaining = remaining[8..];
		}
		self.manager.send(output, self.remoteAddress, null);

		// Congestion control:
		self.congestionControl_bandWidthSentHistory[self.lastKeepAliveSent & congestionControl_historyMask] = self.congestionControl_bandWidthUsed;
		self.lastKeepAliveSent += 1;
		self.congestionControl_bandWidthReceivedHistory[self.lastKeepAliveSent & congestionControl_historyMask] = 0;
		//self.congestionControl_bandWidthUsed = 0;
		var maxBandWidth: usize = minimumBandWidth;
		var dataSentAtMaxBandWidth: usize = minimumBandWidth;
		var maxDataSent: usize = 0;
		{
			var i: usize = self.lastKeepAliveReceived -% 1 & congestionControl_historyMask;
			while(i != self.lastKeepAliveReceived -% 1 & congestionControl_historyMask) : (i = i -% 1 & congestionControl_historyMask) {
				const dataSent: usize = self.congestionControl_bandWidthSentHistory[i];
				const dataReceived: usize = self.congestionControl_bandWidthReceivedHistory[i];
				if(dataReceived > maxBandWidth) {
					maxBandWidth = dataReceived;
					dataSentAtMaxBandWidth = dataSent;
				}
				maxDataSent = @max(maxDataSent, dataSent);
				if(dataSent > dataReceived + dataReceived/64) { // Only look into the history until a packet loss occured to react fast to sudden bandwidth reductions.
					break;
				}
			}
		}
		for(0..congestionControl_historySize) |i| {
			if(self.congestionControl_bandWidthReceivedHistory[i] > maxBandWidth) {
				maxBandWidth = self.congestionControl_bandWidthReceivedHistory[i];
				dataSentAtMaxBandWidth = self.congestionControl_bandWidthSentHistory[i];
			}
			maxDataSent = @max(maxDataSent, self.congestionControl_bandWidthSentHistory[i]);
		}

		if(maxBandWidth == dataSentAtMaxBandWidth and maxDataSent < maxBandWidth + maxBandWidth/64) { // Startup phase → Try to ramp up fast
			self.congestionControl_bandWidthEstimate = maxBandWidth*2;
		} else {
			self.congestionControl_bandWidthEstimate = maxBandWidth + maxBandWidth/64;
			if(dataSentAtMaxBandWidth < maxBandWidth + maxBandWidth/128) { // Ramp up faster
				self.congestionControl_bandWidthEstimate += maxBandWidth/16;
			}
		}
		self.congestionControl_inversebandWidth = timeUnit/@as(f32, @floatFromInt(self.congestionControl_bandWidthEstimate));
		self.congestionControl_bandWidthUsed = 0;
		self.congestionControl_sendTimeLimit = @as(i64, @truncate(std.time.nanoTimestamp())) + timeUnit*21/20;

		// Resend packets that didn't receive confirmation within the last 2 keep-alive signals.
		for(self.unconfirmedPackets.items) |*packet| {
			if(self.lastKeepAliveReceived -% @as(i33, packet.lastKeepAliveSentBefore) >= 2) {
				if(self.trySendingPacket(packet.data)) {
					_ = packetsResent.fetchAdd(1, .monotonic);
					packet.lastKeepAliveSentBefore = self.lastKeepAliveSent;
				} else break;
			}
		}
		while(true) {
			if(self.packetQueue.peek()) |_packet| {
				if(self.trySendingPacket(_packet.data)) {
					std.debug.assert(std.meta.eql(self.packetQueue.dequeue(), _packet)); // Remove it from the queue
					var packet = _packet;
					packet.lastKeepAliveSentBefore = self.lastKeepAliveSent;
					self.unconfirmedPackets.append(packet);
				} else break;
			} else break;
		}
		self.flush();
		if(self.bruteforcingPort) {
			// This is called every 100 ms, so if I send 10 requests it shouldn't be too bad.
			for(0..5) |_| {
				const data = [1]u8{0};
				if(self.remoteAddress.port +% self.bruteForcedPortRange != 0) {
					self.manager.send(&data, Address{.ip = self.remoteAddress.ip, .port = self.remoteAddress.port +% self.bruteForcedPortRange}, null);
				}
				if(self.remoteAddress.port - self.bruteForcedPortRange != 0) {
					self.manager.send(&data, Address{.ip = self.remoteAddress.ip, .port = self.remoteAddress.port -% self.bruteForcedPortRange}, null);
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
			while(dataAvailable < len) : (idd += 1) {
				const otherPacket = self.lastReceivedPackets[idd & 65535] orelse return;
				dataAvailable += otherPacket.len;
			}

			// Copy the data to an array:
			const data = main.stackAllocator.alloc(u8, len);
			defer main.stackAllocator.free(data);
			var remaining = data[0..];
			while(remaining.len != 0) {
				dataAvailable = @min(self.lastReceivedPackets[id & 65535].?.len - newIndex, remaining.len);
				@memcpy(remaining[0..dataAvailable], self.lastReceivedPackets[id & 65535].?[newIndex .. newIndex + dataAvailable]);
				newIndex += @intCast(dataAvailable);
				remaining = remaining[dataAvailable..];
				if(newIndex == self.lastReceivedPackets[id & 65535].?.len) {
					id += 1;
					newIndex = 0;
				}
			}
			while(self.lastIncompletePacket != id) : (self.lastIncompletePacket += 1) {
				self.lastReceivedPackets[self.lastIncompletePacket & 65535] = null;
			}
			self.lastIndex = newIndex;
			_ = bytesReceived[protocol].fetchAdd(data.len + 1 + (7 + std.math.log2_int(usize, 1 + data.len))/7, .monotonic);
			if(Protocols.list[protocol]) |prot| {
				if(Protocols.isAsynchronous[protocol]) {
					ProtocolTask.schedule(self, protocol, data);
				} else {
					var reader = utils.BinaryReader.init(data, networkEndian);
					try prot(self, &reader);
				}
			} else {
				std.log.err("Received unknown important protocol with id {}", .{protocol});
			}
		}
	}

	pub fn receive(self: *Connection, data: []const u8) void {
		self.flawedReceive(data) catch |err| {
			std.log.err("Got error while processing received network data: {s}", .{@errorName(err)});
			if(@errorReturnTrace()) |trace| {
				std.log.info("{}", .{trace});
			}
			self.disconnect();
		};
	}

	pub fn flawedReceive(self: *Connection, data: []const u8) !void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		const protocol = data[0];
		if(self.handShakeState.load(.monotonic) != Protocols.handShake.stepComplete and protocol != Protocols.handShake.id and protocol != Protocols.keepAlive and protocol != Protocols.important) {
			return; // Reject all non-handshake packets until the handshake is done.
		}
		self.lastConnection = @truncate(std.time.nanoTimestamp());
		_ = bytesReceived[protocol].fetchAdd(data.len + 20 + 8, .monotonic); // Including IP header and udp header;
		_ = packetsReceived[protocol].fetchAdd(1, .monotonic);
		if(protocol == Protocols.important) {
			const id = std.mem.readInt(u32, data[1..5], .big);
			if(self.handShakeState.load(.monotonic) == Protocols.handShake.stepComplete and id == 0) { // Got a new "first" packet from client. So the client tries to reconnect, but we still think it's connected.
				if(self.user) |user| {
					user.reinitialize();
					self.mutex.lock();
					defer self.mutex.unlock();
					self.reinitialize();
				} else {
					std.log.err("Server reconnected?", .{});
					self.disconnect();
				}
			}
			if(id - @as(i33, self.lastIncompletePacket) >= 65536) {
				std.log.warn("Many incomplete packets. Cannot process any more packets for now.", .{});
				return;
			}
			self.receivedPackets[0].append(id);
			if(id < self.lastIncompletePacket or self.lastReceivedPackets[id & 65535] != null) {
				return; // Already received the package in the past.
			}
			const temporaryMemory: []u8 = (&self.packetMemory[id & 65535])[0 .. data.len - importantHeaderSize];
			@memcpy(temporaryMemory, data[importantHeaderSize..]);
			self.lastReceivedPackets[id & 65535] = temporaryMemory;
			// Check if a message got completed:
			try self.collectPackets();
		} else if(protocol == Protocols.keepAlive) {
			self.receiveKeepAlive(data[1..]);
		} else {
			if(Protocols.list[protocol]) |prot| {
				var reader = utils.BinaryReader.init(data[1..], networkEndian);
				try prot(self, &reader);
			} else {
				std.log.err("Received unknown protocol with id {}", .{protocol});
				return error.Invalid;
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
		self.disconnected.store(true, .unordered);
		self.manager.removeConnection(self);
		std.log.info("Disconnected", .{});
	}
};

const ProtocolTask = struct {
	conn: *Connection,
	protocol: u8,
	data: []const u8,

	const vtable = utils.ThreadPool.VTable{
		.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
		.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
		.run = main.utils.castFunctionSelfToAnyopaque(run),
		.clean = main.utils.castFunctionSelfToAnyopaque(clean),
		.taskType = .misc,
	};

	pub fn schedule(conn: *Connection, protocol: u8, data: []const u8) void {
		const task = main.globalAllocator.create(ProtocolTask);
		task.* = ProtocolTask{
			.conn = conn,
			.protocol = protocol,
			.data = main.globalAllocator.dupe(u8, data),
		};
		main.threadPool.addTask(task, &vtable);
	}

	pub fn getPriority(_: *ProtocolTask) f32 {
		return std.math.floatMax(f32);
	}

	pub fn isStillNeeded(_: *ProtocolTask) bool {
		return true;
	}

	pub fn run(self: *ProtocolTask) void {
		defer self.clean();
		var reader = utils.BinaryReader.init(self.data, networkEndian);
		Protocols.list[self.protocol].?(self.conn, &reader) catch |err| {
			std.log.err("Got error {s} while executing protocol {} with data {any}", .{@errorName(err), self.protocol, self.data}); // TODO: Maybe disconnect on error
		};
	}

	pub fn clean(self: *ProtocolTask) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.destroy(self);
	}
};
