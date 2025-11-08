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
const main = @import("main");
const game = @import("game.zig");
const settings = @import("settings.zig");
const renderer = @import("renderer.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const BlockUpdate = renderer.mesh_storage.BlockUpdate;

//TODO: Might want to use SSL or something similar to encode the message

const ms = 1_000;
inline fn networkTimestamp() i64 {
	return std.time.microTimestamp();
}

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
		if(builtin.os.tag == .windows) { // TODO: Upstream error, fix after next Zig update after #24466 is merged
			const sendto = struct {
				extern "c" fn sendto(sockfd: posix.system.fd_t, buf: *const anyopaque, len: usize, flags: u32, dest_addr: ?*const posix.system.sockaddr, addrlen: posix.system.socklen_t) c_int;
			}.sendto;
			const result = sendto(self.socketID, data.ptr, data.len, 0, @ptrCast(&addr), @sizeOf(posix.sockaddr.in));
			if(result < 0) {
				std.log.info("Got error while sending to {f}: {s}", .{destination, @tagName(std.os.windows.ws2_32.WSAGetLastError())});
			} else {
				std.debug.assert(@as(usize, @intCast(result)) == data.len);
			}
		} else {
			std.debug.assert(data.len == posix.sendto(self.socketID, data, 0, @ptrCast(&addr), @sizeOf(posix.sockaddr.in)) catch |err| {
				std.log.info("Got error while sending to {f}: {s}", .{destination, @errorName(err)});
				return;
			});
		}
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
				std.Thread.sleep(1000000); // Manually sleep, since WSAPoll is blocking.
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

	pub const localHost = 0x0100007f;

	pub fn format(self: Address, writer: anytype) !void {
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
					std.log.info("{f}", .{result});
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
	allowNewConnections: Atomic(bool) = .init(false),

	receiveBuffer: [Connection.maxMtu]u8 = undefined,

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
		errdefer result.socket.deinit();
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
		self.socket.deinit();
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
		if(self.allowNewConnections.load(.monotonic) or source.ip == Address.localHost) {
			if(data.len != 0 and data[0] == @intFromEnum(Connection.ChannelId.init)) {
				const ip = std.fmt.allocPrint(main.stackAllocator.allocator, "{f}", .{source}) catch unreachable;
				defer main.stackAllocator.free(ip);
				const user = main.server.User.initAndIncreaseRefCount(main.server.connectionManager, ip) catch |err| {
					std.log.err("Cannot connect user from external IP {f}: {s}", .{source, @errorName(err)});
					return;
				};
				user.decreaseRefCount();
			}
		} else {
			// TODO: Reduce the number of false alarms in the short period after a disconnect.
			std.log.warn("Unknown connection from address: {f}", .{source});
			std.log.debug("Message: {any}", .{data});
		}
	}

	pub fn run(self: *ConnectionManager) void {
		self.threadId = std.Thread.getCurrentId();
		main.initThreadLocals();
		defer main.deinitThreadLocals();

		var lastTime: i64 = networkTimestamp();
		while(self.running.load(.monotonic)) {
			main.heap.GarbageCollection.syncPoint();
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
			const curTime: i64 = networkTimestamp();
			{
				self.mutex.lock();
				defer self.mutex.unlock();
				while(self.packetSendRequests.peek() != null and self.packetSendRequests.peek().?.time -% curTime <= 0) {
					const packet = self.packetSendRequests.remove();
					self.socket.send(packet.data, packet.target);
					main.globalAllocator.free(packet.data);
				}
			}

			// Send packets roughly every 1 ms:
			if(curTime -% lastTime > 1*ms) {
				lastTime = curTime;
				var i: u32 = 0;
				self.mutex.lock();
				defer self.mutex.unlock();
				while(i < self.connections.items.len) {
					var conn = self.connections.items[i];
					self.mutex.unlock();
					conn.processNextPackets();
					self.mutex.lock();
					i += 1;
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
pub const Protocols = struct {
	pub var list: [256]?*const fn(*Connection, *utils.BinaryReader) anyerror!void = @splat(null);
	pub var isAsynchronous: [256]bool = @splat(false);
	pub var bytesReceived: [256]Atomic(usize) = @splat(.init(0));
	pub var bytesSent: [256]Atomic(usize) = @splat(.init(0));

	pub const keepAlive: u8 = 0;
	pub const important: u8 = 0xff;
	pub const handShake = struct {
		pub const id: u8 = 1;
		pub const asynchronous = false;

		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const newState = try reader.readEnum(Connection.HandShakeState);
			if(@intFromEnum(conn.handShakeState.load(.monotonic)) < @intFromEnum(newState)) {
				conn.handShakeState.store(newState, .monotonic);
				switch(newState) {
					.userData => {
						const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
						defer zon.deinit(main.stackAllocator);
						const name = zon.get([]const u8, "name", "unnamed");
						if(!std.unicode.utf8ValidateSlice(name)) {
							std.log.err("Received player name with invalid UTF-8 characters.", .{});
							return error.Invalid;
						}
						if(name.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(name) > 50) {
							std.log.err("Player has too long name with {}/{} characters.", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(name), name.len});
							return error.Invalid;
						}
						const version = zon.get([]const u8, "version", "unknown");
						std.log.info("User {s} joined using version {s}", .{name, version});

						if(!try main.settings.version.isCompatibleClientVersion(version)) {
							std.log.warn("Version incompatible with server version {s}", .{main.settings.version.version});
							return error.IncompatibleVersion;
						}

						{
							const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets/", .{main.server.world.?.path}) catch unreachable;
							defer main.stackAllocator.free(path);
							var dir = try main.files.cubyzDir().openIterableDir(path);
							defer dir.close();
							var arrayList = main.List(u8).init(main.stackAllocator);
							defer arrayList.deinit();
							arrayList.append(@intFromEnum(Connection.HandShakeState.assets));
							try utils.Compression.pack(dir, arrayList.writer());
							conn.send(.fast, id, arrayList.items);
						}

						conn.user.?.initPlayer(name);
						const zonObject = ZonElement.initObject(main.stackAllocator);
						defer zonObject.deinit(main.stackAllocator);
						zonObject.put("player", conn.user.?.player.save(main.stackAllocator));
						zonObject.put("player_id", conn.user.?.id);
						zonObject.put("spawn", main.server.world.?.spawn);
						zonObject.put("blockPalette", main.server.world.?.blockPalette.storeToZon(main.stackAllocator));
						zonObject.put("itemPalette", main.server.world.?.itemPalette.storeToZon(main.stackAllocator));
						zonObject.put("toolPalette", main.server.world.?.toolPalette.storeToZon(main.stackAllocator));
						zonObject.put("biomePalette", main.server.world.?.biomePalette.storeToZon(main.stackAllocator));

						const outData = zonObject.toStringEfficient(main.stackAllocator, &[1]u8{@intFromEnum(Connection.HandShakeState.serverData)});
						defer main.stackAllocator.free(outData);
						conn.send(.fast, id, outData);
						conn.handShakeState.store(.serverData, .monotonic);
						main.server.connect(conn.user.?);
					},
					.assets => {
						std.log.info("Received assets.", .{});
						main.files.cwd().deleteTree("serverAssets") catch {}; // Delete the assets created before migration
						main.files.cubyzDir().deleteTree("serverAssets") catch {}; // Delete old assets.
						var dir = try main.files.cubyzDir().openDir("serverAssets");
						defer dir.close();
						try utils.Compression.unpack(dir, reader.remaining);
					},
					.serverData => {
						const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
						defer zon.deinit(main.stackAllocator);
						try conn.manager.world.?.finishHandshake(zon);
						conn.handShakeState.store(.complete, .monotonic);
						conn.handShakeWaiting.broadcast(); // Notify the waiting client thread.
					},
					.start, .complete => {},
				}
			} else {
				// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
			}
		}

		pub fn serverSide(conn: *Connection) void {
			conn.handShakeState.store(.start, .monotonic);
		}

		pub fn clientSide(conn: *Connection, name: []const u8) !void {
			const zonObject = ZonElement.initObject(main.stackAllocator);
			defer zonObject.deinit(main.stackAllocator);
			zonObject.putOwnedString("version", settings.version.version);
			zonObject.putOwnedString("name", name);
			const prefix = [1]u8{@intFromEnum(Connection.HandShakeState.userData)};
			const data = zonObject.toStringEfficient(main.stackAllocator, &prefix);
			defer main.stackAllocator.free(data);
			conn.send(.fast, id, data);

			conn.mutex.lock();
			while(true) {
				conn.handShakeWaiting.timedWait(&conn.mutex, 16_000_000) catch {
					main.heap.GarbageCollection.syncPoint();
					continue;
				};
				break;
			}
			if(conn.connectionState.load(.monotonic) == .disconnectDesired) return error.DisconnectedByServer;
			conn.mutex.unlock();
		}
	};
	pub const chunkRequest = struct {
		pub const id: u8 = 2;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const basePosition = try reader.readVec(Vec3i);
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
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 14 + 4*requests.len);
			defer writer.deinit();
			writer.writeVec(Vec3i, basePosition);
			writer.writeInt(u16, renderDistance);
			for(requests) |req| {
				const voxelSizeShift: u5 = std.math.log2_int(u31, req.voxelSize);
				const positionMask = ~((@as(i32, 1) << voxelSizeShift + chunk.chunkShift) - 1);
				writer.writeInt(i8, @intCast((req.wx -% (basePosition[0] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
				writer.writeInt(i8, @intCast((req.wy -% (basePosition[1] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
				writer.writeInt(i8, @intCast((req.wz -% (basePosition[2] & positionMask)) >> voxelSizeShift + chunk.chunkShift));
				writer.writeInt(u5, voxelSizeShift);
			}
			conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
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
			try main.server.storage.ChunkCompression.loadChunk(ch, .client, reader.remaining);
			renderer.mesh_storage.updateChunkMesh(ch);
		}
		fn sendChunkOverTheNetwork(conn: *Connection, ch: *chunk.ServerChunk) void {
			ch.mutex.lock();
			const chunkData = main.server.storage.ChunkCompression.storeChunk(main.stackAllocator, &ch.super, .toClient, ch.super.pos.voxelSize != 1);
			ch.mutex.unlock();
			defer main.stackAllocator.free(chunkData);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, chunkData.len + 16);
			defer writer.deinit();
			writer.writeInt(i32, ch.super.pos.wx);
			writer.writeInt(i32, ch.super.pos.wy);
			writer.writeInt(i32, ch.super.pos.wz);
			writer.writeInt(u31, ch.super.pos.voxelSize);
			writer.writeSlice(chunkData);
			conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
		}
		pub fn sendChunk(conn: *Connection, ch: *chunk.ServerChunk) void {
			sendChunkOverTheNetwork(conn, ch);
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
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 62);
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
			conn.send(.lossy, id, writer.data.items);
		}
	};
	pub const entityPosition = struct {
		pub const id: u8 = 6;
		pub const asynchronous = false;
		const type_entity: u8 = 0;
		const type_item: u8 = 1;
		const Type = enum(u8) {
			noVelocityEntity = 0,
			f16VelocityEntity = 1,
			f32VelocityEntity = 2,
			noVelocityItem = 3,
			f16VelocityItem = 4,
			f32VelocityItem = 5,
		};
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			if(conn.isServerSide()) return error.InvalidSide;
			if(conn.manager.world) |world| {
				const time = try reader.readInt(i16);
				const playerPos = try reader.readVec(Vec3d);
				var entityData: main.List(main.entity.EntityNetworkData) = .init(main.stackAllocator);
				defer entityData.deinit();
				var itemData: main.List(main.itemdrop.ItemDropNetworkData) = .init(main.stackAllocator);
				defer itemData.deinit();
				while(reader.remaining.len != 0) {
					const typ = try reader.readEnum(Type);
					switch(typ) {
						.noVelocityEntity, .f16VelocityEntity, .f32VelocityEntity => {
							entityData.append(.{
								.vel = switch(typ) {
									.noVelocityEntity => @splat(0),
									.f16VelocityEntity => @floatCast(try reader.readVec(@Vector(3, f16))),
									.f32VelocityEntity => @floatCast(try reader.readVec(@Vector(3, f32))),
									else => unreachable,
								},
								.id = try reader.readInt(u32),
								.pos = playerPos + try reader.readVec(Vec3f),
								.rot = try reader.readVec(Vec3f),
							});
						},
						.noVelocityItem, .f16VelocityItem, .f32VelocityItem => {
							itemData.append(.{
								.vel = switch(typ) {
									.noVelocityItem => @splat(0),
									.f16VelocityItem => @floatCast(try reader.readVec(@Vector(3, f16))),
									.f32VelocityItem => @floatCast(try reader.readVec(Vec3f)),
									else => unreachable,
								},
								.index = try reader.readInt(u16),
								.pos = playerPos + try reader.readVec(Vec3f),
							});
						},
					}
				}
				main.entity.ClientEntityManager.serverUpdate(time, entityData.items);
				world.itemDrops.readPosition(time, itemData.items);
			}
		}
		pub fn send(conn: *Connection, playerPos: Vec3d, entityData: []main.entity.EntityNetworkData, itemData: []main.itemdrop.ItemDropNetworkData) void {
			var writer = utils.BinaryWriter.init(main.stackAllocator);
			defer writer.deinit();

			writer.writeInt(i16, @truncate(std.time.milliTimestamp()));
			writer.writeVec(Vec3d, playerPos);
			for(entityData) |data| {
				const velocityMagnitudeSqr = vec.lengthSquare(data.vel);
				if(velocityMagnitudeSqr < 1e-6*1e-6) {
					writer.writeEnum(Type, .noVelocityEntity);
				} else if(velocityMagnitudeSqr > 1000*1000) {
					writer.writeEnum(Type, .f32VelocityEntity);
					writer.writeVec(Vec3f, @floatCast(data.vel));
				} else {
					writer.writeEnum(Type, .f16VelocityEntity);
					writer.writeVec(@Vector(3, f16), @floatCast(data.vel));
				}
				writer.writeInt(u32, data.id);
				writer.writeVec(Vec3f, @floatCast(data.pos - playerPos));
				writer.writeVec(Vec3f, data.rot);
			}
			for(itemData) |data| {
				const velocityMagnitudeSqr = vec.lengthSquare(data.vel);
				if(velocityMagnitudeSqr < 1e-6*1e-6) {
					writer.writeEnum(Type, .noVelocityItem);
				} else if(velocityMagnitudeSqr > 1000*1000) {
					writer.writeEnum(Type, .f32VelocityItem);
					writer.writeVec(Vec3f, @floatCast(data.vel));
				} else {
					writer.writeEnum(Type, .f16VelocityItem);
					writer.writeVec(@Vector(3, f16), @floatCast(data.vel));
				}
				writer.writeInt(u16, data.index);
				writer.writeVec(Vec3f, @floatCast(data.pos - playerPos));
			}
			conn.send(.lossy, id, writer.data.items);
		}
	};
	pub const blockUpdate = struct {
		pub const id: u8 = 7;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			if(conn.isServerSide()) {
				return error.InvalidPacket;
			}
			while(reader.remaining.len != 0) {
				renderer.mesh_storage.updateBlock(.{
					.x = try reader.readInt(i32),
					.y = try reader.readInt(i32),
					.z = try reader.readInt(i32),
					.newBlock = Block.fromInt(try reader.readInt(u32)),
					.blockEntityData = try reader.readSlice(try reader.readInt(usize)),
				});
			}
		}
		pub fn send(conn: *Connection, updates: []const BlockUpdate) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 16);
			defer writer.deinit();

			for(updates) |update| {
				writer.writeInt(i32, update.x);
				writer.writeInt(i32, update.y);
				writer.writeInt(i32, update.z);
				writer.writeInt(u32, update.newBlock.toInt());
				writer.writeInt(usize, update.blockEntityData.len);
				writer.writeSlice(update.blockEntityData);
			}
			conn.send(.fast, id, writer.data.items);
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
			conn.send(.fast, id, msg);
		}
	};
	pub const genericUpdate = struct {
		pub const id: u8 = 9;
		pub const asynchronous = false;

		const UpdateType = enum(u8) {
			gamemode = 0,
			teleport = 1,
			worldEditPos = 2,
			time = 3,
			biome = 4,
		};

		const WorldEditPosition = enum(u2) {
			selectedPos1 = 0,
			selectedPos2 = 1,
			clear = 2,
		};

		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			switch(try reader.readEnum(UpdateType)) {
				.gamemode => {
					if(conn.isServerSide()) return error.InvalidPacket;
					main.items.Inventory.Sync.setGamemode(null, try reader.readEnum(main.game.Gamemode));
				},
				.teleport => {
					if(conn.isServerSide()) return error.InvalidPacket;
					game.Player.setPosBlocking(try reader.readVec(Vec3d));
				},
				.worldEditPos => {
					const typ = try reader.readEnum(WorldEditPosition);
					const pos: ?Vec3i = switch(typ) {
						.selectedPos1, .selectedPos2 => try reader.readVec(Vec3i),
						.clear => null,
					};
					if(conn.isServerSide()) {
						switch(typ) {
							.selectedPos1 => conn.user.?.worldEditData.selectionPosition1 = pos.?,
							.selectedPos2 => conn.user.?.worldEditData.selectionPosition2 = pos.?,
							.clear => {
								conn.user.?.worldEditData.selectionPosition1 = null;
								conn.user.?.worldEditData.selectionPosition2 = null;
							},
						}
					} else {
						switch(typ) {
							.selectedPos1 => game.Player.selectionPosition1 = pos,
							.selectedPos2 => game.Player.selectionPosition2 = pos,
							.clear => {
								game.Player.selectionPosition1 = null;
								game.Player.selectionPosition2 = null;
							},
						}
					}
				},
				.time => {
					if(conn.manager.world) |world| {
						const expectedTime = try reader.readInt(i64);

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
					}
				},
				.biome => {
					if(conn.manager.world) |world| {
						const biomeId = try reader.readInt(u32);

						const newBiome = main.server.terrain.biomes.getByIndex(biomeId) orelse return error.MissingBiome;
						const oldBiome = world.playerBiome.swap(newBiome, .monotonic);
						if(oldBiome != newBiome) {
							main.audio.setMusic(newBiome.preferredMusic);
						}
					}
				},
			}
		}

		pub fn sendGamemode(conn: *Connection, gamemode: main.game.Gamemode) void {
			conn.send(.fast, id, &.{@intFromEnum(UpdateType.gamemode), @intFromEnum(gamemode)});
		}

		pub fn sendTPCoordinates(conn: *Connection, pos: Vec3d) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 25);
			defer writer.deinit();

			writer.writeEnum(UpdateType, .teleport);
			writer.writeVec(Vec3d, pos);

			conn.send(.fast, id, writer.data.items);
		}

		pub fn sendWorldEditPos(conn: *Connection, posType: WorldEditPosition, maybePos: ?Vec3i) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 25);
			defer writer.deinit();

			writer.writeEnum(UpdateType, .worldEditPos);
			writer.writeEnum(WorldEditPosition, posType);
			if(maybePos) |pos| {
				writer.writeVec(Vec3i, pos);
			}

			conn.send(.fast, id, writer.data.items);
		}

		pub fn sendBiome(conn: *Connection, biomeIndex: u32) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 13);
			defer writer.deinit();

			writer.writeEnum(UpdateType, .biome);
			writer.writeInt(u32, biomeIndex);

			conn.send(.fast, id, writer.data.items);
		}

		pub fn sendTime(conn: *Connection, world: *const main.server.ServerWorld) void {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 13);
			defer writer.deinit();

			writer.writeEnum(UpdateType, .time);
			writer.writeInt(i64, world.gameTime);

			conn.send(.fast, id, writer.data.items);
		}
	};
	pub const chat = struct {
		pub const id: u8 = 10;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			const msg = reader.remaining;
			if(!std.unicode.utf8ValidateSlice(msg)) {
				std.log.err("Received chat message with invalid UTF-8 characters.", .{});
				return error.Invalid;
			}
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
			conn.send(.lossy, id, msg);
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
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 9*requests.len);
			defer writer.deinit();
			for(requests) |req| {
				writer.writeInt(i32, req.wx);
				writer.writeInt(i32, req.wy);
				writer.writeInt(u8, req.voxelSizeShift);
			}
			conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
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
			var ligthMapReader = utils.BinaryReader.init(_inflatedData);
			const map = main.globalAllocator.create(main.server.terrain.LightMap.LightMapFragment);
			map.init(pos.wx, pos.wy, pos.voxelSize);
			for(&map.startHeight) |*val| {
				val.* = try ligthMapReader.readInt(i16);
			}
			renderer.mesh_storage.updateLightMap(map);
		}
		pub fn sendLightMap(conn: *Connection, map: *main.server.terrain.LightMap.LightMapFragment) void {
			var ligthMapWriter = utils.BinaryWriter.initCapacity(main.stackAllocator, @sizeOf(@TypeOf(map.startHeight)));
			defer ligthMapWriter.deinit();
			for(&map.startHeight) |val| {
				ligthMapWriter.writeInt(i16, val);
			}
			const compressedData = utils.Compression.deflate(main.stackAllocator, ligthMapWriter.data.items, .default);
			defer main.stackAllocator.free(compressedData);
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 9 + compressedData.len);
			defer writer.deinit();
			writer.writeInt(i32, map.pos.wx);
			writer.writeInt(i32, map.pos.wy);
			writer.writeInt(u8, map.pos.voxelSizeShift);
			writer.writeSlice(compressedData);
			conn.send(.fast, id, writer.data.items); // TODO: Can this use the slow channel?
		}
	};
	pub const inventory = struct {
		pub const id: u8 = 13;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			if(conn.user) |user| {
				if(reader.remaining[0] == 0xff) return error.InvalidPacket;
				items.Inventory.Sync.ServerSide.receiveCommand(user, reader) catch |err| {
					if(err != error.InventoryNotFound) return err;
					sendFailure(conn);
				};
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
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
			defer writer.deinit();
			writer.writeEnum(items.Inventory.Command.PayloadType, payloadType);
			std.debug.assert(writer.data.items[0] != 0xff);
			writer.writeSlice(_data);
			conn.send(.fast, id, writer.data.items);
		}
		pub fn sendConfirmation(conn: *Connection, _data: []const u8) void {
			std.debug.assert(conn.isServerSide());
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
			defer writer.deinit();
			writer.writeInt(u8, 0xff);
			writer.writeSlice(_data);
			conn.send(.fast, id, writer.data.items);
		}
		pub fn sendFailure(conn: *Connection) void {
			std.debug.assert(conn.isServerSide());
			conn.send(.fast, id, &.{0xfe});
		}
		pub fn sendSyncOperation(conn: *Connection, _data: []const u8) void {
			std.debug.assert(conn.isServerSide());
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, _data.len + 1);
			defer writer.deinit();
			writer.writeInt(u8, 0);
			writer.writeSlice(_data);
			conn.send(.fast, id, writer.data.items);
		}
	};
	pub const blockEntityUpdate = struct {
		pub const id: u8 = 14;
		pub const asynchronous = false;
		fn receive(conn: *Connection, reader: *utils.BinaryReader) !void {
			if(!conn.isServerSide()) return error.Invalid;

			const pos = try reader.readVec(Vec3i);
			const blockType = try reader.readInt(u16);
			const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
			defer simChunk.decreaseRefCount();
			const ch = simChunk.chunk.load(.unordered) orelse return;
			ch.mutex.lock();
			defer ch.mutex.unlock();
			const block = ch.getBlock(pos[0] - ch.super.pos.wx, pos[1] - ch.super.pos.wy, pos[2] - ch.super.pos.wz);
			if(block.typ != blockType) return;
			const blockEntity = block.blockEntity() orelse return;
			try blockEntity.updateServerData(pos, &ch.super, .{.update = reader});
			ch.setChanged();

			sendServerDataUpdateToClientsInternal(pos, &ch.super, block, blockEntity);
		}

		pub fn sendClientDataUpdateToServer(conn: *Connection, pos: Vec3i) void {
			const mesh = main.renderer.mesh_storage.getMesh(.initFromWorldPos(pos, 1)) orelse return;
			mesh.mutex.lock();
			defer mesh.mutex.unlock();
			const index = mesh.chunk.getLocalBlockIndex(pos);
			const block = mesh.chunk.data.getValue(index);
			const blockEntity = block.blockEntity() orelse return;

			var writer = utils.BinaryWriter.init(main.stackAllocator);
			defer writer.deinit();
			writer.writeVec(Vec3i, pos);
			writer.writeInt(u16, block.typ);
			blockEntity.getClientToServerData(pos, mesh.chunk, &writer);

			conn.send(.fast, id, writer.data.items);
		}

		fn sendServerDataUpdateToClientsInternal(pos: Vec3i, ch: *chunk.Chunk, block: Block, blockEntity: *main.block_entity.BlockEntityType) void {
			var writer = utils.BinaryWriter.init(main.stackAllocator);
			defer writer.deinit();
			blockEntity.getServerToClientData(pos, ch, &writer);

			const users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
			defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, users);

			for(users) |user| {
				blockUpdate.send(user.conn, &.{.{.x = pos[0], .y = pos[1], .z = pos[2], .newBlock = block, .blockEntityData = writer.data.items}});
			}
		}

		pub fn sendServerDataUpdateToClients(pos: Vec3i) void {
			const simChunk = main.server.world.?.getSimulationChunkAndIncreaseRefCount(pos[0], pos[1], pos[2]) orelse return;
			defer simChunk.decreaseRefCount();
			const ch = simChunk.chunk.load(.unordered) orelse return;
			ch.mutex.lock();
			defer ch.mutex.unlock();
			const block = ch.getBlock(pos[0] - ch.super.pos.wx, pos[1] - ch.super.pos.wy, pos[2] - ch.super.pos.wz);
			const blockEntity = block.blockEntity() orelse return;

			sendServerDataUpdateToClientsInternal(pos, &ch.super, block, blockEntity);
		}
	};
};

pub const Connection = struct { // MARK: Connection
	const maxMtu: u32 = 65507; // max udp packet size
	const importantHeaderSize: u32 = 5;
	const minMtu: u32 = 576 - 20 - 8; // IPv4 MTU minus IP header minus udp header
	const headerOverhead = 20 + 8 + 42; // IP Header + UDP Header + Ethernet header/footer
	const congestionControl_historySize = 16;
	const congestionControl_historyMask = congestionControl_historySize - 1;
	const minimumBandWidth = 10_000;

	const receiveBufferSize = 8 << 20;

	// Statistics:
	pub var packetsSent: Atomic(u32) = .init(0);
	pub var packetsResent: Atomic(u32) = .init(0);
	pub var internalMessageOverhead: Atomic(usize) = .init(0);
	pub var internalHeaderOverhead: Atomic(usize) = .init(0);
	pub var externalHeaderOverhead: Atomic(usize) = .init(0);

	const SequenceIndex = i32;

	const LossStatus = enum {
		noLoss,
		singleLoss,
		doubleLoss,
	};

	const RangeBuffer = struct { // MARK: RangeBuffer
		const Range = struct {
			start: SequenceIndex,
			len: SequenceIndex,

			fn end(self: Range) SequenceIndex {
				return self.start +% self.len;
			}
		};
		ranges: main.ListUnmanaged(Range),

		pub fn init() RangeBuffer {
			return .{
				.ranges = .{},
			};
		}

		pub fn clear(self: *RangeBuffer) void {
			self.ranges.clearRetainingCapacity();
		}

		pub fn deinit(self: RangeBuffer, allocator: NeverFailingAllocator) void {
			self.ranges.deinit(allocator);
		}

		pub fn addRange(self: *RangeBuffer, allocator: NeverFailingAllocator, range: Range) void {
			if(self.hasRange(range)) return;
			var startRange: ?Range = null;
			var endRange: ?Range = null;
			var i: usize = 0;
			while(i < self.ranges.items.len) {
				const other = self.ranges.items[i];
				if(range.start -% other.start <= 0 and range.end() -% other.end() >= 0) {
					_ = self.ranges.swapRemove(i);
					continue;
				}
				if(range.start -% other.end() <= 0 and range.start -% other.start >= 0) {
					_ = self.ranges.swapRemove(i);
					startRange = other;
					continue;
				}
				if(range.end() -% other.start >= 0 and range.end() -% other.end() <= 0) {
					_ = self.ranges.swapRemove(i);
					endRange = other;
					continue;
				}
				i += 1;
			}
			var mergedRange = range;
			if(startRange) |start| {
				mergedRange.start = start.start;
				mergedRange.len = range.end() -% mergedRange.start;
			}
			if(endRange) |end| {
				mergedRange.len = end.end() -% mergedRange.start;
			}
			self.ranges.append(allocator, mergedRange);
		}

		pub fn hasRange(self: *RangeBuffer, range: Range) bool {
			for(self.ranges.items) |other| {
				if(range.start -% other.start >= 0 and range.end() -% other.end() <= 0) {
					return true;
				}
			}
			return false;
		}

		pub fn extractFirstRange(self: *RangeBuffer) ?Range {
			if(self.ranges.items.len == 0) return null;
			var firstRange = self.ranges.items[0];
			var index: usize = 0;
			for(self.ranges.items[1..], 1..) |range, i| {
				if(range.start -% firstRange.start < 0) {
					firstRange = range;
					index = i;
				}
			}
			_ = self.ranges.swapRemove(index);
			return firstRange;
		}
	};

	const ReceiveBuffer = struct { // MARK: ReceiveBuffer
		const Range = struct {
			start: SequenceIndex,
			len: SequenceIndex,
		};
		const Header = struct {
			protocolIndex: u8,
			size: u32,
		};
		ranges: RangeBuffer,
		availablePosition: SequenceIndex = undefined,
		currentReadPosition: SequenceIndex = undefined,
		buffer: main.utils.FixedSizeCircularBuffer(u8, receiveBufferSize),
		header: ?Header = null,
		protocolBuffer: main.ListUnmanaged(u8) = .{},

		pub fn init() ReceiveBuffer {
			return .{
				.ranges = .init(),
				.buffer = .init(main.globalAllocator),
			};
		}

		pub fn deinit(self: ReceiveBuffer) void {
			self.ranges.deinit(main.globalAllocator);
			self.protocolBuffer.deinit(main.globalAllocator);
			self.buffer.deinit(main.globalAllocator);
		}

		fn applyRanges(self: *ReceiveBuffer) void {
			const range = self.ranges.extractFirstRange() orelse unreachable;
			std.debug.assert(range.start == self.availablePosition);
			self.availablePosition = range.end();
		}

		fn getHeaderInformation(self: *ReceiveBuffer) !?Header {
			if(self.currentReadPosition == self.availablePosition) return null;
			var header: Header = .{
				.protocolIndex = self.buffer.getAtOffset(0) orelse unreachable,
				.size = 0,
			};
			var i: u8 = 1;
			while(true) : (i += 1) {
				if(self.currentReadPosition +% i == self.availablePosition) return null;
				const nextByte = self.buffer.getAtOffset(i) orelse unreachable;
				header.size = header.size << 7 | (nextByte & 0x7f);
				if(nextByte & 0x80 == 0) break;
				if(header.size > std.math.maxInt(@TypeOf(header.size)) >> 7) return error.Invalid;
			}
			self.buffer.discardElementsFront(i + 1);
			self.currentReadPosition +%= @intCast(i + 1);
			return header;
		}

		fn collectRangesAndExecuteProtocols(self: *ReceiveBuffer, conn: *Connection) !void {
			self.applyRanges();
			while(true) {
				if(self.header == null) {
					self.header = try self.getHeaderInformation() orelse return;
					self.protocolBuffer.ensureCapacity(main.globalAllocator, self.header.?.size);
				}
				const amount = @min(@as(usize, @intCast(self.availablePosition -% self.currentReadPosition)), self.header.?.size - self.protocolBuffer.items.len);
				if(self.availablePosition -% self.currentReadPosition == 0) return;

				self.buffer.popSliceFront(self.protocolBuffer.addManyAssumeCapacity(amount)) catch unreachable;
				self.currentReadPosition +%= @intCast(amount);
				if(self.protocolBuffer.items.len != self.header.?.size) return;

				const protocolIndex = self.header.?.protocolIndex;
				self.header = null;
				const protocolReceive = Protocols.list[protocolIndex] orelse return error.Invalid;

				if(Protocols.isAsynchronous[protocolIndex]) {
					ProtocolTask.schedule(conn, protocolIndex, self.protocolBuffer.items);
				} else {
					var reader = utils.BinaryReader.init(self.protocolBuffer.items);
					protocolReceive(conn, &reader) catch |err| {
						std.log.debug("Got error while executing protocol {} with data {any}", .{protocolIndex, self.protocolBuffer.items});
						return err;
					};
				}

				_ = Protocols.bytesReceived[protocolIndex].fetchAdd(self.protocolBuffer.items.len, .monotonic);
				self.protocolBuffer.clearRetainingCapacity();
				if(self.protocolBuffer.items.len > 1 << 24) {
					self.protocolBuffer.shrinkAndFree(main.globalAllocator, 1 << 24);
				}
			}
		}

		const ReceiveStatus = enum {
			accepted,
			rejected,
		};

		pub fn receive(self: *ReceiveBuffer, conn: *Connection, start: SequenceIndex, data: []const u8) !ReceiveStatus {
			const len: SequenceIndex = @intCast(data.len);
			if(start -% self.availablePosition < 0) return .accepted; // We accepted it in the past.
			const offset: usize = @intCast(start -% self.currentReadPosition);
			self.buffer.insertSliceAtOffset(data, offset) catch return .rejected;
			self.ranges.addRange(main.globalAllocator, .{.start = start, .len = len});
			if(start == self.availablePosition) {
				try self.collectRangesAndExecuteProtocols(conn);
			}
			return .accepted;
		}
	};

	const SendBuffer = struct { // MARK: SendBuffer
		const Range = struct {
			start: SequenceIndex,
			len: SequenceIndex,
			timestamp: i64,
			wasResent: bool = false,
			wasResentAsFirstPacket: bool = false,
			considerForCongestionControl: bool,

			fn compareTime(_: void, a: Range, b: Range) std.math.Order {
				if(a.timestamp == b.timestamp) return .eq;
				if(a.timestamp -% b.timestamp > 0) return .gt;
				return .lt;
			}
		};
		unconfirmedRanges: std.PriorityQueue(Range, void, Range.compareTime),
		lostRanges: main.utils.CircularBufferQueue(Range),
		buffer: main.utils.CircularBufferQueue(u8),
		fullyConfirmedIndex: SequenceIndex,
		highestSentIndex: SequenceIndex,
		nextIndex: SequenceIndex,
		lastUnsentTime: i64,

		pub fn init(index: SequenceIndex) SendBuffer {
			return .{
				.unconfirmedRanges = .init(main.globalAllocator.allocator, {}),
				.lostRanges = .init(main.globalAllocator, 1 << 10),
				.buffer = .init(main.globalAllocator, 1 << 20),
				.fullyConfirmedIndex = index,
				.highestSentIndex = index,
				.nextIndex = index,
				.lastUnsentTime = networkTimestamp(),
			};
		}

		pub fn deinit(self: SendBuffer) void {
			self.unconfirmedRanges.deinit();
			self.lostRanges.deinit();
			self.buffer.deinit();
		}

		pub fn insertMessage(self: *SendBuffer, protocolIndex: u8, data: []const u8, time: i64) !void {
			if(self.highestSentIndex == self.fullyConfirmedIndex) {
				self.lastUnsentTime = time;
			}
			if(data.len + self.buffer.len > std.math.maxInt(SequenceIndex)) return error.OutOfMemory;
			self.buffer.pushBack(protocolIndex);
			self.nextIndex +%= 1;
			_ = internalHeaderOverhead.fetchAdd(1, .monotonic);
			const bits = 1 + if(data.len == 0) 0 else std.math.log2_int(usize, data.len);
			const bytes = std.math.divCeil(usize, bits, 7) catch unreachable;
			for(0..bytes) |i| {
				const shift = 7*(bytes - i - 1);
				const byte = (data.len >> @intCast(shift) & 0x7f) | if(i == bytes - 1) @as(u8, 0) else 0x80;
				self.buffer.pushBack(@intCast(byte));
				self.nextIndex +%= 1;
				_ = internalHeaderOverhead.fetchAdd(1, .monotonic);
			}
			self.buffer.pushBackSlice(data);
			self.nextIndex +%= @intCast(data.len);
		}

		const ReceiveConfirmationResult = struct {
			timestamp: i64,
			packetLen: SequenceIndex,
			considerForCongestionControl: bool,
		};

		pub fn receiveConfirmationAndGetTimestamp(self: *SendBuffer, start: SequenceIndex) ?ReceiveConfirmationResult {
			var result: ?ReceiveConfirmationResult = null;
			for(self.unconfirmedRanges.items, 0..) |range, i| {
				if(range.start == start) {
					result = .{
						.timestamp = range.timestamp,
						.considerForCongestionControl = range.considerForCongestionControl,
						.packetLen = range.len,
					};
					_ = self.unconfirmedRanges.removeIndex(i);
					break;
				}
			}
			var smallestUnconfirmed = self.highestSentIndex;
			for(self.unconfirmedRanges.items) |range| {
				if(smallestUnconfirmed -% range.start > 0) {
					smallestUnconfirmed = range.start;
				}
			}
			for(0..self.lostRanges.len) |i| {
				const range = self.lostRanges.getAtOffset(i) catch unreachable;
				if(smallestUnconfirmed -% range.start > 0) {
					smallestUnconfirmed = range.start;
				}
			}
			self.buffer.discardFront(@intCast(smallestUnconfirmed -% self.fullyConfirmedIndex)) catch unreachable;
			self.fullyConfirmedIndex = smallestUnconfirmed;
			return result;
		}

		pub fn checkForLosses(self: *SendBuffer, time: i64, retransmissionTimeout: i64) LossStatus {
			var hadLoss: bool = false;
			var hadDoubleLoss: bool = false;
			while(true) {
				var range = self.unconfirmedRanges.peek() orelse break;
				if(range.timestamp +% retransmissionTimeout -% time >= 0) break;
				_ = self.unconfirmedRanges.remove();
				if(self.fullyConfirmedIndex == range.start) {
					// In TCP effectively only the second loss of the lowest unconfirmed packet is counted for congestion control
					// This decreases the chance of triggering congestion control from random packet loss
					if(range.wasResentAsFirstPacket) hadDoubleLoss = true;
					hadLoss = true;
					range.wasResentAsFirstPacket = true;
				}
				range.wasResent = true;
				self.lostRanges.pushBack(range);
				_ = packetsResent.fetchAdd(1, .monotonic);
			}
			if(hadDoubleLoss) return .doubleLoss;
			if(hadLoss) return .singleLoss;
			return .noLoss;
		}

		pub fn getNextPacketToSend(self: *SendBuffer, byteIndex: *SequenceIndex, buf: []u8, time: i64, considerForCongestionControl: bool, allowedDelay: i64) ?usize {
			self.unconfirmedRanges.ensureUnusedCapacity(1) catch unreachable;
			// Resend old packet:
			if(self.lostRanges.popFront()) |_range| {
				var range = _range;
				if(range.len > buf.len) { // MTU changed → split the data
					self.lostRanges.pushFront(.{
						.start = range.start +% @as(SequenceIndex, @intCast(buf.len)),
						.len = range.len - @as(SequenceIndex, @intCast(buf.len)),
						.timestamp = range.timestamp,
						.considerForCongestionControl = range.considerForCongestionControl,
					});
					range.len = @intCast(buf.len);
				}

				self.buffer.getSliceAtOffset(@intCast(range.start -% self.fullyConfirmedIndex), buf[0..@intCast(range.len)]) catch unreachable;
				range.timestamp = time;
				byteIndex.* = range.start;
				self.unconfirmedRanges.add(range) catch unreachable;
				return @intCast(range.len);
			}

			if(self.highestSentIndex == self.nextIndex) return null;
			if(self.highestSentIndex +% @as(i32, @intCast(buf.len)) -% self.fullyConfirmedIndex > receiveBufferSize) return null;
			// Send new packet:
			const len: SequenceIndex = @min(self.nextIndex -% self.highestSentIndex, @as(i32, @intCast(buf.len)));
			if(len < buf.len and time -% self.lastUnsentTime < allowedDelay) return null;

			self.buffer.getSliceAtOffset(@intCast(self.highestSentIndex -% self.fullyConfirmedIndex), buf[0..@intCast(len)]) catch unreachable;
			byteIndex.* = self.highestSentIndex;
			self.unconfirmedRanges.add(.{
				.start = self.highestSentIndex,
				.len = len,
				.timestamp = time,
				.considerForCongestionControl = considerForCongestionControl,
			}) catch unreachable;
			self.highestSentIndex +%= len;
			return @intCast(len);
		}
	};

	const Channel = struct { // MARK: Channel
		receiveBuffer: ReceiveBuffer,
		sendBuffer: SendBuffer,
		allowedDelay: i64,
		channelId: ChannelId,

		pub fn init(sequenceIndex: SequenceIndex, delay: i64, id: ChannelId) Channel {
			return .{
				.receiveBuffer = .init(),
				.sendBuffer = .init(sequenceIndex),
				.allowedDelay = delay,
				.channelId = id,
			};
		}

		pub fn deinit(self: *Channel) void {
			self.receiveBuffer.deinit();
			self.sendBuffer.deinit();
		}

		pub fn connect(self: *Channel, remoteStart: SequenceIndex) void {
			std.debug.assert(self.receiveBuffer.buffer.len == 0);
			self.receiveBuffer.availablePosition = remoteStart;
			self.receiveBuffer.currentReadPosition = remoteStart;
		}

		pub fn receive(self: *Channel, conn: *Connection, start: SequenceIndex, data: []const u8) !ReceiveBuffer.ReceiveStatus {
			return self.receiveBuffer.receive(conn, start, data);
		}

		pub fn send(self: *Channel, protocolIndex: u8, data: []const u8, time: i64) !void {
			return self.sendBuffer.insertMessage(protocolIndex, data, time);
		}

		pub fn receiveConfirmationAndGetTimestamp(self: *Channel, start: SequenceIndex) ?SendBuffer.ReceiveConfirmationResult {
			return self.sendBuffer.receiveConfirmationAndGetTimestamp(start);
		}

		pub fn checkForLosses(self: *Channel, conn: *Connection, time: i64) LossStatus {
			const retransmissionTimeout: i64 = @intFromFloat(conn.rttEstimate + 3*conn.rttUncertainty + @as(f32, @floatFromInt(self.allowedDelay)));
			return self.sendBuffer.checkForLosses(time, retransmissionTimeout);
		}

		pub fn sendNextPacketAndGetSize(self: *Channel, conn: *Connection, time: i64, considerForCongestionControl: bool) ?usize {
			var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, conn.mtuEstimate);
			defer writer.deinit();

			writer.writeEnum(ChannelId, self.channelId);

			var byteIndex: SequenceIndex = undefined;
			const packetLen = self.sendBuffer.getNextPacketToSend(&byteIndex, writer.data.items.ptr[5..writer.data.capacity], time, considerForCongestionControl, self.allowedDelay) orelse return null;
			writer.writeInt(SequenceIndex, byteIndex);
			_ = internalHeaderOverhead.fetchAdd(5, .monotonic);
			_ = externalHeaderOverhead.fetchAdd(headerOverhead, .monotonic);
			writer.data.items.len += packetLen;

			_ = packetsSent.fetchAdd(1, .monotonic);
			conn.manager.send(writer.data.items, conn.remoteAddress, null);
			return writer.data.items.len;
		}

		pub fn getStatistics(self: *Channel, unconfirmed: *usize, queued: *usize) void {
			for(self.sendBuffer.unconfirmedRanges.items) |range| {
				unconfirmed.* += @intCast(range.len);
			}
			queued.* = @intCast(self.sendBuffer.nextIndex -% self.sendBuffer.highestSentIndex);
		}
	};

	const ChannelId = enum(u8) { // MARK: ChannelId
		lossy = 0,
		fast = 1,
		slow = 2,
		confirmation = 3,
		init = 4,
		keepalive = 5,
		disconnect = 6,
	};

	const ConfirmationData = struct {
		channel: ChannelId,
		start: SequenceIndex,
		receiveTimeStamp: i64,
	};

	const ConnectionState = enum(u8) {
		awaitingClientConnection,
		awaitingServerResponse,
		awaitingClientAcknowledgement,
		connected,
		disconnectDesired,
	};

	const HandShakeState = enum(u8) {
		start = 0,
		userData = 1,
		assets = 2,
		serverData = 3,
		complete = 255,
	};

	// MARK: fields

	manager: *ConnectionManager,
	user: ?*main.server.User,

	remoteAddress: Address,
	bruteforcingPort: bool = false,
	bruteForcedPortRange: u16 = 0,

	lossyChannel: Channel, // TODO: Actually allow it to be lossy
	fastChannel: Channel,
	slowChannel: Channel,

	hasRttEstimate: bool = false,
	rttEstimate: f32 = 1000*ms,
	rttUncertainty: f32 = 0.0,
	lastRttSampleTime: i64,
	nextPacketTimestamp: i64,
	nextConfirmationTimestamp: i64,
	queuedConfirmations: main.utils.CircularBufferQueue(ConfirmationData),
	mtuEstimate: u16 = minMtu,

	bandwidthEstimateInBytesPerRtt: f32 = minMtu,
	slowStart: bool = true,
	relativeSendTime: i64 = 0,
	relativeIdleTime: i64 = 0,

	connectionState: Atomic(ConnectionState),
	handShakeState: Atomic(HandShakeState) = .init(.start),
	handShakeWaiting: std.Thread.Condition = std.Thread.Condition{},
	lastConnection: i64,

	// To distinguish different connections from the same computer to avoid multiple reconnects
	connectionIdentifier: i64,
	remoteConnectionIdentifier: i64,

	mutex: std.Thread.Mutex = .{},

	pub fn init(manager: *ConnectionManager, ipPort: []const u8, user: ?*main.server.User) !*Connection {
		const result: *Connection = main.globalAllocator.create(Connection);
		errdefer main.globalAllocator.destroy(result);
		result.* = Connection{
			.manager = manager,
			.user = user,
			.remoteAddress = undefined,
			.connectionState = .init(if(user != null) .awaitingClientConnection else .awaitingServerResponse),
			.lastConnection = networkTimestamp(),
			.nextPacketTimestamp = networkTimestamp(),
			.nextConfirmationTimestamp = networkTimestamp(),
			.lastRttSampleTime = networkTimestamp() -% 10_000*ms,
			.queuedConfirmations = .init(main.globalAllocator, 1024),
			.lossyChannel = .init(main.random.nextInt(SequenceIndex, &main.seed), 1*ms, .lossy),
			.fastChannel = .init(main.random.nextInt(SequenceIndex, &main.seed), 10*ms, .fast),
			.slowChannel = .init(main.random.nextInt(SequenceIndex, &main.seed), 100*ms, .slow),
			.connectionIdentifier = networkTimestamp(),
			.remoteConnectionIdentifier = 0,
		};
		errdefer {
			result.lossyChannel.deinit();
			result.fastChannel.deinit();
			result.slowChannel.deinit();
			result.queuedConfirmations.deinit();
		}
		if(result.connectionIdentifier == 0) result.connectionIdentifier = 1;

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

	pub fn deinit(self: *Connection) void {
		self.disconnect();
		self.manager.finishCurrentReceive(); // Wait until all currently received packets are done.
		self.lossyChannel.deinit();
		self.fastChannel.deinit();
		self.slowChannel.deinit();
		self.queuedConfirmations.deinit();
		main.globalAllocator.destroy(self);
	}

	pub fn send(self: *Connection, comptime channel: ChannelId, protocolIndex: u8, data: []const u8) void {
		_ = Protocols.bytesSent[protocolIndex].fetchAdd(data.len, .monotonic);
		self.mutex.lock();
		defer self.mutex.unlock();

		_ = switch(channel) {
			.lossy => self.lossyChannel.send(protocolIndex, data, networkTimestamp()),
			.fast => self.fastChannel.send(protocolIndex, data, networkTimestamp()),
			.slow => self.slowChannel.send(protocolIndex, data, networkTimestamp()),
			else => comptime unreachable,
		} catch {
			std.log.err("Cannot send any more packets. Disconnecting", .{});
			self.disconnect();
		};
	}

	pub fn isConnected(self: *Connection) bool {
		self.mutex.lock();
		defer self.mutex.unlock();

		return self.connectionState.load(.unordered) == .connected;
	}

	fn isServerSide(conn: *Connection) bool {
		return conn.user != null;
	}

	fn handlePacketLoss(self: *Connection, loss: LossStatus) void {
		if(loss == .noLoss) return;
		self.slowStart = false;
		if(loss == .doubleLoss) {
			self.rttEstimate *= 1.5;
			self.bandwidthEstimateInBytesPerRtt /= 2;
			self.bandwidthEstimateInBytesPerRtt = @max(self.bandwidthEstimateInBytesPerRtt, minMtu);
		}
	}

	fn increaseCongestionBandwidth(self: *Connection, packetLen: SequenceIndex) void {
		const fullPacketLen: f32 = @floatFromInt(packetLen + headerOverhead);
		if(self.slowStart) {
			self.bandwidthEstimateInBytesPerRtt += fullPacketLen;
		} else {
			self.bandwidthEstimateInBytesPerRtt += fullPacketLen/self.bandwidthEstimateInBytesPerRtt*@as(f32, @floatFromInt(self.mtuEstimate)) + fullPacketLen/100.0;
		}
	}

	fn receiveConfirmationPacket(self: *Connection, reader: *utils.BinaryReader, timestamp: i64) !void {
		self.mutex.lock();
		defer self.mutex.unlock();

		var minRtt: f32 = std.math.floatMax(f32);
		var maxRtt: f32 = 1000;
		var sumRtt: f32 = 0;
		var numRtt: f32 = 0;
		while(reader.remaining.len != 0) {
			const channel = try reader.readEnum(ChannelId);
			const timeOffset = 2*@as(i64, try reader.readInt(u16));
			const start = try reader.readInt(SequenceIndex);
			const confirmationResult = switch(channel) {
				.lossy => self.lossyChannel.receiveConfirmationAndGetTimestamp(start) orelse continue,
				.fast => self.fastChannel.receiveConfirmationAndGetTimestamp(start) orelse continue,
				.slow => self.slowChannel.receiveConfirmationAndGetTimestamp(start) orelse continue,
				else => return error.Invalid,
			};
			const rtt: f32 = @floatFromInt(@max(1, timestamp -% confirmationResult.timestamp -% timeOffset));
			numRtt += 1;
			sumRtt += rtt;
			minRtt = @min(minRtt, rtt);
			maxRtt = @max(maxRtt, rtt);
			if(confirmationResult.considerForCongestionControl) {
				self.increaseCongestionBandwidth(confirmationResult.packetLen);
			}
		}
		if(numRtt > 0) {
			// Taken mostly from RFC 6298 with some minor changes
			const averageRtt = sumRtt/numRtt;
			const largestDifference = @max(maxRtt - averageRtt, averageRtt - minRtt, @abs(maxRtt - self.rttEstimate), @abs(self.rttEstimate - minRtt));
			const timeDifference: f32 = @floatFromInt(timestamp -% self.lastRttSampleTime);
			const alpha = 1.0 - std.math.pow(f32, 7.0/8.0, timeDifference/self.rttEstimate);
			const beta = 1.0 - std.math.pow(f32, 3.0/4.0, timeDifference/self.rttEstimate);
			self.rttEstimate = (1 - alpha)*self.rttEstimate + alpha*averageRtt;
			self.rttUncertainty = (1 - beta)*self.rttUncertainty + beta*largestDifference;
			self.lastRttSampleTime = timestamp;
			if(!self.hasRttEstimate) { // Kill the 1 second delay caused by the first packet
				self.nextPacketTimestamp = timestamp;
				self.hasRttEstimate = true;
			}
		}
	}

	fn sendConfirmationPacket(self: *Connection, timestamp: i64) void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, self.mtuEstimate);
		defer writer.deinit();

		writer.writeEnum(ChannelId, .confirmation);

		while(self.queuedConfirmations.popFront()) |confirmation| {
			writer.writeEnum(ChannelId, confirmation.channel);
			writer.writeInt(u16, std.math.lossyCast(u16, @divTrunc(timestamp -% confirmation.receiveTimeStamp, 2)));
			writer.writeInt(SequenceIndex, confirmation.start);
			if(writer.data.capacity - writer.data.items.len < @sizeOf(ChannelId) + @sizeOf(u16) + @sizeOf(SequenceIndex)) break;
		}

		_ = internalMessageOverhead.fetchAdd(writer.data.items.len + headerOverhead, .monotonic);
		self.manager.send(writer.data.items, self.remoteAddress, null);
	}

	pub fn receive(self: *Connection, data: []const u8) void {
		self.tryReceive(data) catch |err| {
			std.log.err("Got error while processing received network data: {s}", .{@errorName(err)});
			if(@errorReturnTrace()) |trace| {
				std.log.info("{f}", .{trace});
			}
			std.log.debug("Packet data: {any}", .{data});
			self.disconnect();
		};
	}

	fn tryReceive(self: *Connection, data: []const u8) !void {
		std.debug.assert(self.manager.threadId == std.Thread.getCurrentId());
		var reader = utils.BinaryReader.init(data);
		const channel = try reader.readEnum(ChannelId);
		if(channel == .init) {
			const remoteConnectionIdentifier = try reader.readInt(i64);
			const isAcknowledgement = reader.remaining.len == 0;
			if(isAcknowledgement) {
				switch(self.connectionState.load(.monotonic)) {
					.awaitingClientAcknowledgement => {
						if(self.remoteConnectionIdentifier == remoteConnectionIdentifier) {
							_ = self.connectionState.cmpxchgStrong(.awaitingClientAcknowledgement, .connected, .monotonic, .monotonic);
						}
					},
					else => {},
				}
				return;
			}
			const lossyStart = try reader.readInt(SequenceIndex);
			const fastStart = try reader.readInt(SequenceIndex);
			const slowStart = try reader.readInt(SequenceIndex);
			switch(self.connectionState.load(.monotonic)) {
				.awaitingClientConnection => {
					self.lossyChannel.connect(lossyStart);
					self.fastChannel.connect(fastStart);
					self.slowChannel.connect(slowStart);
					_ = self.connectionState.cmpxchgStrong(.awaitingClientConnection, .awaitingClientAcknowledgement, .monotonic, .monotonic);
					self.remoteConnectionIdentifier = remoteConnectionIdentifier;
				},
				.awaitingServerResponse => {
					self.lossyChannel.connect(lossyStart);
					self.fastChannel.connect(fastStart);
					self.slowChannel.connect(slowStart);
					_ = self.connectionState.cmpxchgStrong(.awaitingServerResponse, .connected, .monotonic, .monotonic);
					self.remoteConnectionIdentifier = remoteConnectionIdentifier;
				},
				.awaitingClientAcknowledgement => {},
				.connected => {
					if(self.remoteConnectionIdentifier != remoteConnectionIdentifier) { // Reconnection attempt
						if(self.user) |user| {
							self.manager.removeConnection(self);
							main.server.disconnect(user);
						} else {
							std.log.err("Server reconnected?", .{});
							self.disconnect();
						}
						return;
					}
				},
				.disconnectDesired => {},
			}
			// Acknowledge the packet on the client:
			if(self.user == null) {
				var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 1 + @sizeOf(i64));
				defer writer.deinit();

				writer.writeEnum(ChannelId, .init);
				writer.writeInt(i64, self.connectionIdentifier);

				_ = internalMessageOverhead.fetchAdd(writer.data.items.len + headerOverhead, .monotonic);
				self.manager.send(writer.data.items, self.remoteAddress, null);
			}
			return;
		}
		if(self.connectionState.load(.monotonic) != .connected) return; // Reject all non-handshake packets until the handshake is done.
		switch(channel) {
			.lossy => {
				const start = try reader.readInt(SequenceIndex);
				if(try self.lossyChannel.receive(self, start, reader.remaining) == .accepted) {
					self.queuedConfirmations.pushBack(.{
						.channel = channel,
						.start = start,
						.receiveTimeStamp = networkTimestamp(),
					});
				}
			},
			.fast => {
				const start = try reader.readInt(SequenceIndex);
				if(try self.fastChannel.receive(self, start, reader.remaining) == .accepted) {
					self.queuedConfirmations.pushBack(.{
						.channel = channel,
						.start = start,
						.receiveTimeStamp = networkTimestamp(),
					});
				}
			},
			.slow => {
				const start = try reader.readInt(SequenceIndex);
				if(try self.slowChannel.receive(self, start, reader.remaining) == .accepted) {
					self.queuedConfirmations.pushBack(.{
						.channel = channel,
						.start = start,
						.receiveTimeStamp = networkTimestamp(),
					});
				}
			},
			.confirmation => {
				try self.receiveConfirmationPacket(&reader, networkTimestamp());
			},
			.init => unreachable,
			.keepalive => {},
			.disconnect => {
				self.disconnect();
			},
		}
		self.lastConnection = networkTimestamp();

		// TODO: Packet statistics
	}

	pub fn processNextPackets(self: *Connection) void {
		const timestamp = networkTimestamp();

		switch(self.connectionState.load(.monotonic)) {
			.awaitingClientConnection => {
				if(timestamp -% self.nextPacketTimestamp < 0) return;
				self.nextPacketTimestamp = timestamp +% 100*ms;
				self.manager.send(&.{@intFromEnum(ChannelId.keepalive)}, self.remoteAddress, null);
			},
			.awaitingServerResponse, .awaitingClientAcknowledgement => {
				// Send the initial packet once every 100 ms.
				if(timestamp -% self.nextPacketTimestamp < 0) return;
				self.nextPacketTimestamp = timestamp +% 100*ms;
				var writer = utils.BinaryWriter.initCapacity(main.stackAllocator, 1 + @sizeOf(i64) + 3*@sizeOf(SequenceIndex));
				defer writer.deinit();

				writer.writeEnum(ChannelId, .init);
				writer.writeInt(i64, self.connectionIdentifier);
				writer.writeInt(SequenceIndex, self.lossyChannel.sendBuffer.fullyConfirmedIndex);
				writer.writeInt(SequenceIndex, self.fastChannel.sendBuffer.fullyConfirmedIndex);
				writer.writeInt(SequenceIndex, self.slowChannel.sendBuffer.fullyConfirmedIndex);
				_ = internalMessageOverhead.fetchAdd(writer.data.items.len + headerOverhead, .monotonic);
				self.manager.send(writer.data.items, self.remoteAddress, null);
				return;
			},
			.connected => {
				if(timestamp -% self.lastConnection -% settings.connectionTimeout > 0) {
					std.log.info("timeout", .{});
					self.disconnect();
					return;
				}
			},
			.disconnectDesired => return,
		}

		self.handlePacketLoss(self.lossyChannel.checkForLosses(self, timestamp));
		self.handlePacketLoss(self.fastChannel.checkForLosses(self, timestamp));
		self.handlePacketLoss(self.slowChannel.checkForLosses(self, timestamp));

		// We don't want to send too many packets at once if there was a period of no traffic.
		if(timestamp -% 10*ms -% self.nextPacketTimestamp > 0) {
			self.relativeIdleTime += timestamp -% 10*ms -% self.nextPacketTimestamp;
			self.nextPacketTimestamp = timestamp -% 10*ms;
		}

		if(self.relativeIdleTime + self.relativeSendTime > @as(i64, @intFromFloat(self.rttEstimate))) {
			self.relativeIdleTime >>= 1;
			self.relativeSendTime >>= 1;
		}

		while(timestamp -% self.nextConfirmationTimestamp > 0 and !self.queuedConfirmations.isEmpty()) {
			self.sendConfirmationPacket(timestamp);
		}

		while(timestamp -% self.nextPacketTimestamp > 0) {
			// Only attempt to increase the congestion bandwidth if we actual use the bandwidth, to prevent unbounded growth
			const considerForCongestionControl = @divFloor(self.relativeSendTime, 2) > self.relativeIdleTime;
			const dataLen = blk: {
				self.mutex.lock();
				defer self.mutex.unlock();
				if(self.lossyChannel.sendNextPacketAndGetSize(self, timestamp, considerForCongestionControl)) |dataLen| break :blk dataLen;
				if(self.fastChannel.sendNextPacketAndGetSize(self, timestamp, considerForCongestionControl)) |dataLen| break :blk dataLen;
				if(self.slowChannel.sendNextPacketAndGetSize(self, timestamp, considerForCongestionControl)) |dataLen| break :blk dataLen;

				break;
			};
			const networkLen: f32 = @floatFromInt(dataLen + headerOverhead);
			const packetTime: i64 = @intFromFloat(@max(1, networkLen/self.bandwidthEstimateInBytesPerRtt*self.rttEstimate));
			self.nextPacketTimestamp +%= packetTime;
			self.relativeSendTime += packetTime;
		}
	}

	pub fn disconnect(self: *Connection) void {
		self.manager.send(&.{@intFromEnum(ChannelId.disconnect)}, self.remoteAddress, null);
		self.connectionState.store(.disconnectDesired, .unordered);
		if(builtin.os.tag == .windows and !self.isServerSide() and main.server.world != null) {
			std.Thread.sleep(10000000); // Windows is too eager to close the socket, without waiting here we get a ConnectionResetByPeer on the other side.
		}
		self.manager.removeConnection(self);
		if(self.user) |user| {
			main.server.disconnect(user);
		} else {
			self.handShakeWaiting.broadcast();
			main.exitToMenu(undefined);
		}
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
		var reader = utils.BinaryReader.init(self.data);
		Protocols.list[self.protocol].?(self.conn, &reader) catch |err| {
			std.log.err("Got error {s} while executing protocol {} with data {any}", .{@errorName(err), self.protocol, self.data}); // TODO: Maybe disconnect on error
		};
	}

	pub fn clean(self: *ProtocolTask) void {
		main.globalAllocator.free(self.data);
		main.globalAllocator.destroy(self);
	}
};
