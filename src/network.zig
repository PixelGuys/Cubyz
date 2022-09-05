const std = @import("std");

const main = @import("main.zig");
const game = @import("game.zig");
const settings = @import("settings.zig");

//TODO: Might want to use SSL or something similar to encode the message

const LinuxSocket = struct {
	const c = @cImport({
		@cInclude("sys/socket.h");
		@cInclude("netinet/in.h");
		@cInclude("sys/types.h");
		@cInclude("unistd.h");
		@cInclude("string.h");
		@cInclude("errno.h");
		@cInclude("stdio.h");
		@cInclude("arpa/inet.h");
	});

	socketID: u31,

	fn checkError(comptime msg: []const u8, result: c_int) !u31 {
		if(result == -1) {
			std.log.warn(msg, .{c.__errno_location().*});
			return error.SocketError;
		}
		return @intCast(u31, result);
	}

	fn init(localPort: u16) !LinuxSocket {
		var socketID: u31 = undefined;
		socketID = try checkError("Socket creation failed with error: {}", c.socket(c.AF_INET, c.SOCK_DGRAM, c.IPPROTO_UDP));
		errdefer _ = checkError("Error while closing socket: {}", c.close(socketID)) catch 0;
		var bindingAddr: c.sockaddr_in = undefined;
		bindingAddr.sin_family = c.AF_INET;
		bindingAddr.sin_port = c.htons(localPort);
		bindingAddr.sin_addr.s_addr = c.inet_addr("127.0.0.1");
		bindingAddr.sin_zero = [_]u8{0} ** 8;
		_ = try checkError("Socket binding failed with error: {}", c.bind(socketID, @ptrCast(*c.sockaddr, &bindingAddr), @sizeOf(c.sockaddr_in))); // TODO: Use the next higher port, when the port is already in use.
		return LinuxSocket{.socketID = socketID};
	}

	fn deinit(self: LinuxSocket) void {
		_ = checkError("Error while closing socket: {}", c.close(self.socketID)) catch 0;
	}
};

pub const Address = struct {
	ip: []const u8,
	port: u16,
};

pub const ConnectionManager = struct {
	socket: LinuxSocket = undefined,
	thread: std.Thread = undefined,
	online: bool = false,

	pub fn init(localPort: u16, online: bool) !ConnectionManager {
		_ = online; //TODO
		var result = ConnectionManager{};
		result.socket = try LinuxSocket.init(localPort);
		errdefer LinuxSocket.deinit(result.socket);

		result.thread = try std.Thread.spawn(.{}, run, .{result});
		if(online) {
			result.makeOnline();
		}
		return result;
	}

	pub fn deinit(self: ConnectionManager) void {
		LinuxSocket.deinit(self.socket);
		self.thread.join();
	}

	pub fn makeOnline(self: *ConnectionManager) void {
		if(!self.online) {
			// TODO:
//			externalIPPort = STUN.requestIPPort(this);
//			String[] ipPort;
//			if(externalIPPort.contains("?")) {
//				ipPort = externalIPPort.split(":\\?");
//			} else {
//				ipPort = externalIPPort.split(":");
//			}
//			try {
//				externalAddress = InetAddress.getByName(ipPort[0]);
//			} catch(UnknownHostException e) {
//				Logger.error(e);
//				throw new IllegalArgumentException("externalIPPort is invalid.");
//			}
//			externalPort = Integer.parseInt(ipPort[1]);
			self.online = true;
		}
	}

	pub fn run(self: ConnectionManager) void {
		var gpa = std.heap.GeneralPurposeAllocator(.{}){};
		main.threadAllocator = gpa.allocator();
		defer if(gpa.deinit()) {
			@panic("Memory leak");
		};

		_ = self; // TODO
	}

	pub fn send(self: ConnectionManager, data: []const u8, target: Address) void {
		// TODO
		_ = self;
		_ = data;
		_ = target;
	}
};
//	sockID = c.socket(c.AF_INET, c.SOCK_DGRAM, c.IPPROTO_UDP);
//	defer _ = c.close(sockID);
//	_ = c.memset(&otherAddr, 0, @sizeOf(c.sockaddr_in));
//	otherAddr.sin_family = c.AF_INET;
//	otherAddr.sin_port = c.htons(40001);
//	otherAddr.sin_addr.s_addr = c.inet_addr("???.???.???.???");
//	var myAddr: c.sockaddr_in = undefined;
//	_ = c.memset(&myAddr, 0, @sizeOf(c.sockaddr_in));
//	myAddr.sin_family = c.AF_INET;
//	myAddr.sin_port = c.htons(40001);
//	myAddr.sin_addr.s_addr = c.inet_addr("192.168.178.60");
//
//	_ = errorCheck(c.bind(sockID, @ptrCast(*c.sockaddr, &myAddr), @sizeOf(c.sockaddr_in)));
//	
//	_ = std.Thread.spawn(.{}, keepAlive, .{}) catch null;
//public final class UDPConnectionManager extends Thread {
//	private final DatagramPacket receivedPacket;
//	public final ArrayList<UDPConnection> connections = new ArrayList<>();
//	private final ArrayList<DatagramPacket> requests = new ArrayList<>();
//	private volatile boolean running = true;
//	public String externalIPPort = null;
//	private InetAddress externalAddress = null;
//	private int externalPort = 0;
//
//	public void send(DatagramPacket packet) {
//		try {
//			socket.send(packet);
//		} catch(IOException e) {
//			Logger.error(e);
//		}
//	}
//
//	public byte[] sendRequest(DatagramPacket packet, long timeout) {
//		send(packet);
//		byte[] request = packet.getData();
//		synchronized(requests) {
//			requests.add(packet);
//		}
//		synchronized(packet) {
//			try {
//				packet.wait(timeout);
//			} catch(InterruptedException e) {}
//		}
//		synchronized(requests) {
//			requests.remove(packet);
//		}
//		if(packet.getData() == request) {
//			return null;
//		} else {
//			return packet.getData();
//		}
//	}
//
//	public void addConnection(UDPConnection connection) {
//		synchronized(connections) {
//			connections.add(connection);
//		}
//	}
//
//	public void removeConnection(UDPConnection connection) {
//		synchronized(connections) {
//			connections.remove(connection);
//		}
//	}
//
//	public void cleanup() {
//		while(!connections.isEmpty()) {
//			connections.get(0).disconnect();
//		}
//		running = false;
//		if(Thread.currentThread() != this) {
//			interrupt();
//			try {
//				join();
//			} catch(InterruptedException e) {
//				Logger.error(e);
//			}
//		}
//		socket.close();
//	}
//
//	private void onReceive() {
//		byte[] data = receivedPacket.getData();
//		int len = receivedPacket.getLength();
//		InetAddress addr = receivedPacket.getAddress();
//		int port = receivedPacket.getPort();
//		for(UDPConnection connection : connections) {
//			if(connection.remoteAddress.equals(addr)) {
//				if(connection.bruteforcingPort) { // brute-forcing the port was successful.
//					connection.remotePort = port;
//					connection.bruteforcingPort = false;
//				}
//				if(connection.remotePort == port) {
//					connection.receive(data, len);
//					return;
//				}
//			}
//		}
//		// Check if it's part of an active request:
//		synchronized(requests) {
//			for(DatagramPacket packet : requests) {
//				if(packet.getAddress().equals(addr) && packet.getPort() == port) {
//					packet.setData(Arrays.copyOf(data, len));
//					synchronized(packet) {
//						packet.notify();
//					}
//					return;
//				}
//			}
//		}
//		if(addr.equals(externalAddress) && port == externalPort) return;
//		if(addr.toString().contains("127.0.0.1")) return;
//		Logger.warning("Unknown connection from address: " + addr+":"+port);
//		Logger.debug("Message: "+Arrays.toString(Arrays.copyOf(data, len)));
//	}
//
//	@Override
//	public void run() {
//		assert Thread.currentThread() == this : "UDPConnectionManager.run() shouldn't be called by anyone.";
//		try {
//			socket.setSoTimeout(100);
//			long lastTime = System.currentTimeMillis();
//			while (running) {
//				try {
//					socket.receive(receivedPacket);
//					onReceive();
//				} catch(SocketTimeoutException e) {
//					// No message within the last ~100 ms.
//				}
//
//				// Send a keep-alive packet roughly every 100 ms:
//				if(System.currentTimeMillis() - lastTime > 100 && running) {
//					lastTime = System.currentTimeMillis();
//					for(UDPConnection connection : connections.toArray(new UDPConnection[0])) {
//						if(lastTime - connection.lastConnection > CONNECTION_TIMEOUT && connection.isConnected()) {
//							Logger.info("timeout");
//							// Timeout a connection if it was connect at some point. New connections are not timed out because that could annoy players(having to restart the connection several times).
//							connection.disconnect();
//						} else {
//							connection.sendKeepAlive();
//						}
//					}
//					if(connections.isEmpty() && externalAddress != null) {
//						// Send a message to external ip, to keep the port open:
//						DatagramPacket packet = new DatagramPacket(new byte[0], 0);
//						packet.setAddress(externalAddress);
//						packet.setPort(externalPort);
//						packet.setLength(0);
//						send(packet);
//					}
//				}
//			}
//		} catch (Exception e) {
//			Logger.crash(e);
//		}
//	}
//}

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

	manager: ConnectionManager,

	gpa: std.heap.GeneralPurposeAllocator(.{}),
	allocator: std.mem.Allocator,

	remoteAddress: Address,
	bruteforcingPort: bool = false,
	bruteForcedPortRange: u16 = 0,

	streamBuffer: [maxImportantPacketSize]u8 = undefined,
	streamPosition: u32 = importantHeaderSize,
	messageID: u32 = 0,
	unconfirmedPackets: std.ArrayList(UnconfirmedPacket),
	receivedPackets: [3]std.ArrayList(u32),
	lastReceivedPackets: [65536]?[]const u8 = undefined,
	lastIndex: u32 = 0,

	lastIncompletePacket: u32 = 0,

	lastKeepAliveSent: u32 = 0,
	lastKeepAliveReceived: u32 = 0,
	otherKeepAliveReceived: u32 = 0,

	disconnected: bool = false,
	handShakeComplete: bool = false,
	lastConnection: i64 = 0,

	mutex: std.Thread.Mutex = std.Thread.Mutex{},

	pub fn init(manager: ConnectionManager, ipPort: []const u8) !*Connection {
		var gpa = std.heap.GeneralPurposeAllocator(.{}){};
		var result: *Connection = try gpa.allocator().create(Connection);
		result.* = Connection {
			.manager = manager,
			.gpa = gpa,
			.allocator = undefined,
			.remoteAddress = undefined,
			.unconfirmedPackets = std.ArrayList(UnconfirmedPacket).init(gpa.allocator()),
			.receivedPackets = [3]std.ArrayList(u32){
				std.ArrayList(u32).init(gpa.allocator()),
				std.ArrayList(u32).init(gpa.allocator()),
				std.ArrayList(u32).init(gpa.allocator()),
			},
		};
		result.allocator = result.gpa.allocator(); // The right reference(the one that isn't on the stack) needs to be used passed!
		var splitter = std.mem.split(u8, ipPort, ":");
		result.remoteAddress.ip = try result.allocator.dupe(u8, splitter.first());
		var port = splitter.rest();
		if(port.len != 0 and port[0] == '?') {
			result.bruteforcingPort = true;
			port = port[1..];
		}
		result.remoteAddress.port = std.fmt.parseUnsigned(u16, port, 10) catch blk: {
			std.log.warn("Could not parse port \"{s}\". Using default port instead.", .{port});
			break :blk settings.defaultPort;
		};

		// TODO: manager.addConnection(this);
		return result;
	}

	pub fn deinit(self: *Connection) void {
		self.unconfirmedPackets.deinit();
		self.receivedPackets[0].deinit();
		self.receivedPackets[1].deinit();
		self.receivedPackets[2].deinit();
		self.allocator.free(self.remoteAddress.ip);
		var gpa = self.gpa;
		gpa.allocator().destroy(self);
		if(gpa.deinit()) {
			@panic("Memory leak in connection.");
		}
	}

	fn flush(self: *Connection) !void {
		self.mutex.lock();
		defer self.mutex.unlock();

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
		self.manager.send(packet.data, self.remoteAddress);
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

	fn sendKeepAlive(self: *Connection) void {
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
				for(runLengthEncodingStarts) |start, reg| {
					var diff = packetID -% start;
					if(diff < runLengthEncodingLengths.items[reg]) continue;
					if(diff == runLengthEncodingLengths.items[reg]) {
						leftRegion = reg;
					}
					if(diff == std.math.maxInt(u32)) {
						rightRegion == reg;
					}
				}
				if(leftRegion) |left| {
					if(rightRegion) |right| {
						// Needs to combine the regions:
						runLengthEncodingLengths.items[left] += runLengthEncodingLengths.items[right] + 1;
						runLengthEncodingStarts.swapRemove(right);
						runLengthEncodingLengths.swapRemove(right);
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
		var remaining: []const u8 = output[9..];
		for(runLengthEncodingStarts) |_, i| {
			std.mem.writeIntBig(u32, remaining[0..4], self.runLengthEncodingStarts.items[i]);
			std.mem.writeIntBig(u32, remaining[4..8], self.runLengthEncodingLengths.items[i]);
			remaining = remaining[8..];
		}
		self.manager.send(output, self.remoteAddress);

		// Resend packets that didn't receive confirmation within the last 2 keep-alive signals.
		for(self.unconfirmedPackets.items) |*packet| {
			if(self.lastKeepAliveReceived - packet.lastKeepAliveSentBefore >= 2) {
				packetsSent += 1;
				packetsResent += 1;
				self.manager.send(packet.data, self.remoteAddress);
				packet.lastKeepAliveSentBefore = self.lastKeepAliveSent;
			}
		}
		self.flush();
		if(self.bruteforcingPort) {
			// This is called every 100 ms, so if I send 10 requests it shouldn't be too bad.
			var i: u16 = 0;
			while(i < 5): (i += 1) {
				var data = [0]u8{};
				if(self.remoteAddress.port +% self.bruteForcedPortRange != 0) {
					self.manager.send(data, Address{self.remoteAddress.ip, self.remoteAddress.port +% self.bruteForcedPortRange});
				}
				if(self.remoteAddress.port - self.bruteForcedPortRange != 0) {
					self.manager.send(data, Address{self.remoteAddress.ip, self.remoteAddress.port -% self.bruteForcedPortRange});
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
			var shift: u32 = 0;
			while(true) {
				if(newIndex == receivedPacket.len) {
					newIndex = 0;
					id += 1;
					receivedPacket = self.lastReceivedPackets[id & 65535] orelse return;
				}
				var nextByte = receivedPacket[newIndex];
				newIndex += 1;
				len |= (nextByte & 0x7f) << shift;
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
				newIndex += dataAvailable;
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

	pub fn receive(self: *Connection, data: []const u8) void {
		self.mutex.lock();
		defer self.mutex.unlock();

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
			self.lastReceivedPackets[id & 65535] = self.allocator.dupe(data[importantHeaderSize..]);
			// Check if a message got completed:
			self.collectPackets();
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
		// TODO: manager.removeConnection(self);
		std.log.info("Disconnected");
	}
};