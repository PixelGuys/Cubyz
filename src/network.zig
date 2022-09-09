const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("main.zig");
const game = @import("game.zig");
const settings = @import("settings.zig");

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
	externalAddress: ?Address = null,
	online: bool = false,
	running: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(true),

	connections: std.ArrayList(*Connection) = undefined,
	requests: std.ArrayList(*Request) = undefined,

	gpa: std.heap.GeneralPurposeAllocator(.{}),
	allocator: std.mem.Allocator = undefined,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},

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
		if(online) {
			result.makeOnline();
		}
		return result;
	}

	pub fn deinit(self: *ConnectionManager) void {
		self.running.store(false, .Monotonic);
		self.thread.join();
		Socket.deinit(self.socket);

		for(self.connections.items) |conn| {
			conn.disconnect();
		}
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
		if(!self.online) {
			self.externalAddress = STUN.requestAddress(self);
			self.online = true;
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
		self.mutex.lock();
		defer self.mutex.unlock();
		
		for(self.connections.items) |conn| {
			if(conn.remoteAddress.ip == source.ip) {
				if(conn.bruteforcingPort) {
					conn.remoteAddress.port = source.port;
					conn.bruteforcingPort = false;
				}
				if(conn.remoteAddress.port == source.port) {
					try conn.receive(data);
					return;
				}
			}
		}
		// Check if it's part of an active request:
		for(self.requests.items) |request| {
			if(request.address.ip == source.ip and request.address.port == source.port) {
				request.data = try self.allocator.dupe(u8, data);
				request.requestNotifier.signal();
				return;
			}
		}
		if(self.externalAddress != null and source.ip == self.externalAddress.?.ip and source.port == self.externalAddress.?.port) return;
		// TODO: Reduce the number of false alarms in the short period after a disconnect.
		std.log.warn("Unknown connection from address: {}", .{source});
		std.log.debug("Message: {any}", .{data});
	}

	pub fn run(self: *ConnectionManager) !void {
		var gpa = std.heap.GeneralPurposeAllocator(.{}){};
		main.threadAllocator = gpa.allocator();
		defer if(gpa.deinit()) {
			@panic("Memory leak");
		};

		var lastTime = std.time.milliTimestamp();
		while(self.running.load(.Monotonic)) {
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
						conn.disconnect();
						self.mutex.lock();
					} else {
						try conn.sendKeepAlive();
						i += 1;
					}
				}
				if(self.connections.items.len == 0 and self.externalAddress != null) {
					// Send a message to external ip, to keep the port open:
					var data = [1]u8{0};
					try self.send(&data, self.externalAddress.?);
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

const Protocol = struct {
	id: u8,
	const keepAlive: u8 = 0;
	const important: u8 = 0xff;
}; // TODO


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
	lastReceivedPackets: [65536]?[]const u8 = undefined,
	lastIndex: u32 = 0,

	lastIncompletePacket: u32 = 0,

	lastKeepAliveSent: u32 = 0,
	lastKeepAliveReceived: u32 = 0,
	otherKeepAliveReceived: u32 = 0,

	disconnected: bool = false,
	handShakeComplete: bool = false,
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
		self.disconnect();
		self.unconfirmedPackets.deinit();
		self.receivedPackets[0].deinit();
		self.receivedPackets[1].deinit();
		self.receivedPackets[2].deinit();
		var gpa = self.gpa;
		gpa.allocator().destroy(self);
		if(gpa.deinit()) {
			@panic("Memory leak in connection.");
		}
	}

	fn flush(self: *Connection) !void {
		if(self.streamPosition == importantHeaderSize) return; // Don't send empty packets.
		// Fill the header:
		self.streamBuffer[0] = Protocol.important;
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

	fn writeByteToStream(self: *Connection, data: u8) void {
		self.streamBuffer[self.streamPosition] = data;
		self.streamPosition += 1;
		if(self.streamPosition == self.streamBuffer.length) {
			self.flush();
		}
	}

	pub fn sendImportant(self: *Connection, source: Protocol, data: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();

		if(self.disconnected) return;
		self.writeByteToStream(source.id);
		var processedLength = data.len;
		while(processedLength > 0x7f) {
			self.writeByteToStream(@intCast(u8, processedLength & 0x7f) | 0x80);
			processedLength >>= 7;
		}
		self.writeByteToStream(@intCast(u8, processedLength & 0x7f));

		var remaining: []const u8 = data;
		while(remaining.len != 0) {
			var copyableSize = @minimum(remaining.len, self.streamBuffer.len - self.streamPosition);
			std.mem.copy(u8, self.streamBuffer, remaining[0..copyableSize]);
			remaining = remaining[copyableSize..];
			self.streamPosition += copyableSize;
			if(self.streamPosition == self.streamBuffer.len) {
				self.flush();
			}
		}
	}

	pub fn sendUnimportant(self: *Connection, source: Protocol, data: []const u8) !void {
		self.mutex.lock();
		defer self.mutex.unlock();

		if(self.disconnected) return;
		std.debug.assert(data.len + 1 < maxPacketSize);
		var fullData = try main.threadAllocator.alloc(u8, data.len + 1);
		defer main.threadAllocator.free(fullData);
		fullData[0] = source.id;
		std.mem.copy(u8, fullData[1..], data);
		self.manager.send(fullData, self.remoteAddress);
	}

	fn receiveKeepAlive(self: *Connection, data: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();

		self.otherKeepAliveReceived = std.mem.readIntBig(u32, data[0..4]);
		self.lastKeepAliveReceived = std.mem.readIntBig(u32, data[4..8]);
		var remaining: []const u8 = data[8..];
		while(remaining.len >= 8) {
			var start = std.mem.readIntBig(u32, data[0..4]);
			var len = std.mem.readIntBig(u32, data[4..8]);
			var j: usize = 0;
			while(j < self.unconfirmedPackets.items.len): (j += 1) {
				var diff = self.unconfirmedPackets.items[j].id -% start;
				if(diff < len) {
					_ = self.unconfirmedPackets.swapRemove(j);
					j -= 1;
				}
			}
		}
	}

	fn sendKeepAlive(self: *Connection) !void {
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
		output[0] = Protocol.keepAlive;
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
			if(self.lastKeepAliveReceived - packet.lastKeepAliveSentBefore >= 2) {
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
		self.mutex.lock();
		defer self.mutex.unlock();

		while(true) {
			var id = self.lastIncompletePacket;
			var receivedPacket = self.lastReceivedPackets[id & 65535] orelse return;
			var newIndex = self.lastIndex;
			var protocol = receivedPacket[newIndex];
			newIndex += 1;
			// TODO:
			_ = protocol;
//				if(Cubyz.world == null && protocol != Protocols.HANDSHAKE.id)
//					return;

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
				dataAvailable = @minimum(self.lastReceivedPackets[id & 65535].?.len - newIndex, remaining.len);
				std.mem.copy(u8, remaining, self.lastReceivedPackets[id & 65535].?[newIndex..dataAvailable]);
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
			// TODO:
//			Protocols.bytesReceived[protocol & 0xff] += data.length + 1;
//			Protocols.list[protocol].receive(this, data, 0, data.length);
		}
	}

	pub fn receive(self: *Connection, data: []const u8) !void {
		const protocol = data[0];
		// TODO:
		//if(!self.handShakeComplete and protocol != Protocols.HANDSHAKE.id and protocol != Protocol.KEEP_ALIVE and protocol != Protocol.important) {
		//	return; // Reject all non-handshake packets until the handshake is done.
		//}
		self.lastConnection = std.time.milliTimestamp();
		// TODO:
//		Protocols.bytesReceived[protocol & 0xff] += len + 20 + 8; // Including IP header and udp header
//		Protocols.packetsReceived[protocol & 0xff]++;
		if(protocol == Protocol.important) {
			var id = std.mem.readIntBig(u32, data[1..5]);
			if(self.handShakeComplete and id == 0) { // Got a new "first" packet from client. So the client tries to reconnect, but we still think it's connected.
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
			if(id - self.lastIncompletePacket >= 65536) {
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
		} else if(protocol == Protocol.keepAlive) {
			self.receiveKeepAlive(data[1..]);
		} else {
			// TODO: Protocols.list[protocol & 0xff].receive(this, data, 1, len - 1);
		}
	}

	pub fn disconnect(self: *Connection) void {
		// Send 3 disconnect packages to the other side, just to be sure.
		// If all of them don't get through then there is probably a network issue anyways which would lead to a timeout.
		// TODO:
//		Protocols.DISCONNECT.disconnect(this);
//		try {Thread.sleep(10);} catch(Exception e) {}
//		Protocols.DISCONNECT.disconnect(this);
//		try {Thread.sleep(10);} catch(Exception e) {}
//		Protocols.DISCONNECT.disconnect(this);
		self.disconnected = true;
		self.manager.removeConnection(self);
		std.log.info("Disconnected", .{});
	}
};