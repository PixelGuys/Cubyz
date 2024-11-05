const std = @import("std");

const main = @import("main.zig");
const BaseItem = main.items.BaseItem;
const Item = main.items.Item;
const ItemStack = main.items.ItemStack;
const Tool = main.items.Tool;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const ZonElement = main.ZonElement;



const Side = enum{client, server};

pub const Sync = struct { // MARK: Sync

	pub const ClientSide = struct {
		var mutex: std.Thread.Mutex = .{};
		var commands: main.utils.CircularBufferQueue(Command) = undefined;
		var maxId: u32 = 0;
		var freeIdList: main.List(u32) = undefined;
		var serverToClientMap: std.AutoHashMap(u32, Inventory) = undefined;

		pub fn init() void {
			commands = main.utils.CircularBufferQueue(Command).init(main.globalAllocator, 256);
			freeIdList = .init(main.globalAllocator);
			serverToClientMap = .init(main.globalAllocator.allocator);
		}

		pub fn deinit() void {
			mutex.lock();
			while(commands.dequeue()) |cmd| {
				cmd.finalize(main.globalAllocator, .client, &.{});
			}
			mutex.unlock();
			commands.deinit();
			std.debug.assert(freeIdList.items.len == maxId); // leak
			freeIdList.deinit();
			serverToClientMap.deinit();
		}

		pub fn executeCommand(payload: Command.Payload) void {
			var cmd: Command = .{
				.payload = payload,
			};

			mutex.lock();
			defer mutex.unlock();
			cmd.do(main.globalAllocator, .client, null);
			const data = cmd.serializePayload(main.stackAllocator);
			defer main.stackAllocator.free(data);
			main.network.Protocols.inventory.sendCommand(main.game.world.?.conn, cmd.payload, data);
			commands.enqueue(cmd);
		}

		pub fn undo() void {
			if(commands.dequeue_front()) |_cmd| {
				var cmd = _cmd;
				mutex.lock();
				defer mutex.unlock();
				cmd.undo();
				cmd.undoSteps.deinit(main.globalAllocator); // TODO: This should be put on some kind of redo queue once the testing phase is over.
			}
		}

		fn nextId() u32 {
			mutex.lock();
			defer mutex.unlock();
			if(freeIdList.popOrNull()) |id| {
				return id;
			}
			defer maxId += 1;
			return maxId;
		}

		fn freeId(id: u32) void {
			main.utils.assertLocked(&mutex);
			freeIdList.append(id);
		}

		fn mapServerId(serverId: u32, inventory: Inventory) void {
			serverToClientMap.put(serverId, inventory) catch unreachable;
		}

		fn unmapServerId(serverId: u32, clientId: u32) void {
			std.debug.assert(serverToClientMap.fetchRemove(serverId).?.value.id == clientId);
		}

		fn getInventory(serverId: u32) ?Inventory {
			main.utils.assertLocked(&mutex);
			return serverToClientMap.get(serverId);
		}

		pub fn receiveConfirmation(data: []const u8) void {
			mutex.lock();
			defer mutex.unlock();
			commands.dequeue().?.finalize(main.globalAllocator, .client, data);
		}

		pub fn receiveSyncOperation(data: []const u8) !void {
			mutex.lock();
			defer mutex.unlock();
			var tempData = main.List(Command).init(main.stackAllocator);
			defer tempData.deinit();
			while(commands.dequeue_front()) |_cmd| {
				var cmd = _cmd;
				cmd.undo();
				tempData.append(cmd);
			}
			try Command.SyncOperation.executeFromData(data);
			while(tempData.popOrNull()) |_cmd| {
				var cmd = _cmd;
				cmd.do(main.globalAllocator, .client, null);
				commands.enqueue(cmd);
			}
		}
	};

	pub const ServerSide = struct {
		const ServerInventory = struct {
			inv: Inventory,
			users: main.ListUnmanaged(*main.server.User),
			source: Source,

			fn init(len: usize, typ: Inventory.Type, source: Source) ServerInventory {
				return .{
					.inv = Inventory._init(main.globalAllocator, len, typ, .server),
					.users = .{},
					.source = source,
				};
			}

			fn deinit(self: *ServerInventory) void {
				std.debug.assert(self.users.items.len == 0);
				self.users.deinit(main.globalAllocator);
				self.inv._deinit(main.globalAllocator, .server);
				self.inv._items.len = 0;
			}

			fn addUser(self: *ServerInventory, user: *main.server.User, clientId: u32) void {
				main.utils.assertLocked(&mutex);
				self.users.append(main.globalAllocator, user);
				user.inventoryClientToServerIdMap.put(clientId, self.inv.id) catch unreachable;
			}

			fn removeUser(self: *ServerInventory, user: *main.server.User, clientId: u32) void {
				main.utils.assertLocked(&mutex);
				_ = self.users.swapRemove(std.mem.indexOfScalar(*main.server.User, self.users.items, user).?);
				std.debug.assert(user.inventoryClientToServerIdMap.fetchRemove(clientId).?.value == self.inv.id);
				if(self.users.items.len == 0) {
					self.deinit();
				}
			}
		};
		var mutex: std.Thread.Mutex = .{};

		var inventories: main.List(ServerInventory) = undefined;
		var maxId: u32 = 0;
		var freeIdList: main.List(u32) = undefined;

		pub fn init() void {
			inventories = .initCapacity(main.globalAllocator, 256);
			freeIdList = .init(main.globalAllocator);
		}

		pub fn deinit() void {
			std.debug.assert(freeIdList.items.len == maxId); // leak
			freeIdList.deinit();
			inventories.deinit();
		}

		pub fn disconnectUser(user: *main.server.User) void {
			mutex.lock();
			defer mutex.unlock();
			while(true) {
				// Reinitializing the iterator in the loop to allow for removal:
				var iter = user.inventoryClientToServerIdMap.keyIterator();
				const clientId = iter.next() orelse break;
				closeInventory(user, clientId.*) catch unreachable;
			}
		}

		fn nextId() u32 {
			main.utils.assertLocked(&mutex);
			if(freeIdList.popOrNull()) |id| {
				return id;
			}
			defer maxId += 1;
			_ = inventories.addOne();
			return maxId;
		}

		fn freeId(id: u32) void {
			main.utils.assertLocked(&mutex);
			freeIdList.append(id);
		}

		pub fn receiveCommand(source: *main.server.User, data: []const u8) !void {
			mutex.lock();
			defer mutex.unlock();
			const typ: Command.PayloadType = @enumFromInt(data[0]);
			@setEvalBranchQuota(100000);
			const payload: Command.Payload = switch(typ) {
				inline else => |_typ| @unionInit(Command.Payload, @tagName(_typ), try std.meta.FieldType(Command.Payload, _typ).deserialize(data[1..], .server, source)),
			};
			var command = Command {
				.payload = payload,
			};
			command.do(main.globalAllocator, .server, source);
			const confirmationData = command.confirmationData(main.stackAllocator);
			defer main.stackAllocator.free(confirmationData);
			main.network.Protocols.inventory.sendConfirmation(source.conn, confirmationData);
			for(command.syncOperations.items) |op| {
				const syncData = op.serialize(main.stackAllocator);
				defer main.stackAllocator.free(syncData);
				for(inventories.items[op.inv.inv.id].users.items) |otherUser| {
					if(otherUser == source) continue;
					main.network.Protocols.inventory.sendSyncOperation(otherUser.conn, syncData);
				}
			}
			if(command.payload == .open) { // Send initial items
				for(command.payload.open.inv._items, 0..) |stack, slot| {
					if(stack.item != null) {
						const syncOp = Command.SyncOperation {
							.inv = .{.inv = command.payload.open.inv, .slot = @intCast(slot)},
							.amount = stack.amount,
							.item = stack.item,
						};
						const syncData = syncOp.serialize(main.stackAllocator);
						defer main.stackAllocator.free(syncData);
						main.network.Protocols.inventory.sendSyncOperation(source.conn, syncData);
					}
				}
			}
			command.finalize(main.globalAllocator, .server, &.{});
		}

		fn createInventory(user: *main.server.User, clientId: u32, len: usize, typ: Inventory.Type, source: Source) void {
			main.utils.assertLocked(&mutex);
			switch(source) {
				.sharedTestingInventory => {
					for(inventories.items) |*inv| {
						if(std.meta.eql(inv.source, source)) {
							inv.addUser(user, clientId);
							return;
						}
					}
				},
				.playerInventory, .other => {},
			}
			const inventory = ServerInventory.init(len, typ, source);
			inventories.items[inventory.inv.id] = inventory;
			inventories.items[inventory.inv.id].addUser(user, clientId);
		}

		fn closeInventory(user: *main.server.User, clientId: u32) !void {
			main.utils.assertLocked(&mutex);
			const serverId = user.inventoryClientToServerIdMap.get(clientId) orelse return error.Invalid;
			inventories.items[serverId].removeUser(user, clientId);
		}

		fn getInventory(user: *main.server.User, clientId: u32) ?Inventory {
			main.utils.assertLocked(&mutex);
			const serverId = user.inventoryClientToServerIdMap.get(clientId) orelse return null;
			return inventories.items[serverId].inv;
		}
	};

	pub fn executeCommand(payload: Command.Payload) void {
		ClientSide.executeCommand(payload);
	}

	pub fn getInventory(id: u32, side: Side, user: ?*main.server.User) ?Inventory {
		return switch(side) {
			.client => ClientSide.getInventory(id),
			.server => ServerSide.getInventory(user.?, id),
		};
	}
};

pub const Command = struct { // MARK: Command
	pub const PayloadType = enum(u8) {
		open = 0,
		close = 1,
		depositOrSwap = 2,
		deposit = 3,
		takeHalf = 4,
		drop = 5,
		fillFromCreative = 6,
		depositOrDrop = 7,
	};
	pub const Payload = union(PayloadType) {
		open: Open,
		close: Close,
		depositOrSwap: DepositOrSwap,
		deposit: Deposit,
		takeHalf: TakeHalf,
		drop: Drop,
		fillFromCreative: FillFromCreative,
		depositOrDrop: DepositOrDrop,
	};

	const BaseOperationType = enum(u8) {
		move = 0,
		swap = 1,
		delete = 2,
		create = 3,
	};

	const InventoryAndSlot = struct {
		inv: Inventory,
		slot: u32,

		fn ref(self: InventoryAndSlot) *ItemStack {
			return &self.inv._items[self.slot];
		}

		fn write(self: InventoryAndSlot, data: *[8]u8) void {
			std.mem.writeInt(u32, data[0..4], self.inv.id, .big);
			std.mem.writeInt(u32, data[4..8], self.slot, .big);
		}

		fn read(data: *const [8]u8, side: Side, user: ?*main.server.User) !InventoryAndSlot {
			const id = std.mem.readInt(u32, data[0..4], .big);
			return .{
				.inv = Sync.getInventory(id, side, user) orelse return error.Invalid,
				.slot = std.mem.readInt(u32, data[4..8], .big),
			};
		}
	};

	const BaseOperation = union(BaseOperationType) {
		move: struct {
			dest: InventoryAndSlot,
			source: InventoryAndSlot,
			amount: u16,
		},
		swap: struct {
			dest: InventoryAndSlot,
			source: InventoryAndSlot,
		},
		delete: struct {
			source: InventoryAndSlot,
			item: ?Item = undefined,
			amount: u16,
		},
		create: struct {
			dest: InventoryAndSlot,
			item: ?Item,
			amount: u16,
		},
	};

	const SyncOperation = struct {
		// Since the client doesn't know about all inventories, we can only use create(+amount)/delete(-amount) operations to apply the server side updates.
		inv: InventoryAndSlot,
		amount: i32,
		item: ?Item,

		pub fn executeFromData(data: []const u8) !void {
			std.debug.assert(data.len >= 12);
			var self = SyncOperation {
				.inv = try InventoryAndSlot.read(data[0..8], .client, null),
				.amount = std.mem.readInt(i32, data[8..12], .big),
				.item = null,
			};
			if(data.len > 12) {
				const zon = ZonElement.parseFromString(main.stackAllocator, data[12..]);
				defer zon.free(main.stackAllocator);
				self.item = try Item.init(zon);
			}
			std.log.debug("{any} {s}", .{data[0..12], data[12..]});
			if(self.amount > 0) { // Create
				if(self.item) |item| {
					self.inv.ref().item = item;
				} else if(self.inv.ref().item == null) {
					return error.Invalid;
				}
				if(self.inv.ref().amount +| self.amount > self.inv.ref().item.?.stackSize()) {
					return error.Invalid;
				}
				self.inv.ref().amount += @intCast(self.amount);
			} else { // Delete
				if(self.inv.ref().amount < -self.amount) {
					return error.Invalid;
				}
				self.inv.ref().amount -= @intCast(-self.amount);
				if(self.inv.ref().amount == 0) {
					self.inv.ref().item = null;
				}
			}

			self.inv.inv.update();
		}

		pub fn serialize(self: SyncOperation, allocator: NeverFailingAllocator) []const u8 {
			var data = main.List(u8).initCapacity(allocator, 12);
			self.inv.write(data.addMany(8)[0..8]);
			std.mem.writeInt(i32, data.addMany(4)[0..4], self.amount, .big);
			if(self.item) |item| {
				const zon = ZonElement.initObject(main.stackAllocator);
				defer zon.free(main.stackAllocator);
				item.insertIntoZon(main.stackAllocator, zon);
				const string = zon.toStringEfficient(main.stackAllocator, &.{});
				defer main.stackAllocator.free(string);
				data.appendSlice(string);
			}
			return data.toOwnedSlice();
		}
	};

	payload: Payload,
	baseOperations: main.ListUnmanaged(BaseOperation) = .{},
	syncOperations: main.ListUnmanaged(SyncOperation) = .{},

	fn serializePayload(self: *Command, allocator: NeverFailingAllocator) []const u8 {
		var list = main.List(u8).init(allocator);
		switch(self.payload) {
			inline else => |payload| {
				payload.serialize(&list);
			},
		}
		return list.toOwnedSlice();
	}

	fn do(self: *Command, allocator: NeverFailingAllocator, side: Side, user: ?*main.server.User) void {
		std.debug.assert(self.baseOperations.items.len == 0); // do called twice without cleaning up
		switch(self.payload) {
			inline else => |payload| {
				payload.run(allocator, self, side, user);
			},
		}
	}

	fn undo(self: *Command) void {
		// Iterating in reverse order!
		while(self.baseOperations.popOrNull()) |step| {
			switch(step) {
				.move => |info| {
					if(info.amount == 0) continue;
					std.debug.assert(std.meta.eql(info.source.ref().item, info.dest.ref().item) or info.source.ref().item == null);
					info.source.ref().item = info.dest.ref().item;
					info.source.ref().amount += info.amount;
					info.dest.ref().amount -= info.amount;
					if(info.dest.ref().amount == 0) {
						info.dest.ref().item = null;
					}
					info.source.inv.update();
					info.dest.inv.update();
				},
				.swap => |info| {
					const temp = info.dest.ref().*;
					info.dest.ref().* = info.source.ref().*;
					info.source.ref().* = temp;
					info.source.inv.update();
					info.dest.inv.update();
				},
				.delete => |info| {
					std.debug.assert(info.source.ref().item == null or std.meta.eql(info.source.ref().item, info.item));
					info.source.ref().item = info.item;
					info.source.ref().amount += info.amount;
					info.source.inv.update();
				},
				.create => |info| {
					std.debug.assert(info.dest.ref().amount >= info.amount);
					info.dest.ref().amount -= info.amount;
					if(info.dest.ref().amount == 0) {
						info.dest.ref().item.?.deinit();
						info.dest.ref().item = null;
					}
					info.dest.inv.update();
				},
			}
		}
	}

	fn finalize(self: Command, allocator: NeverFailingAllocator, side: Side, data: []const u8) void {
		for(self.baseOperations.items) |step| {
			switch(step) {
				.move, .swap, .create => {},
				.delete => |info| {
					info.item.?.deinit();
				},
			}
		}
		self.baseOperations.deinit(allocator);
		if(side == .server) {
			self.syncOperations.deinit(allocator);
		} else {
			std.debug.assert(self.syncOperations.capacity == 0);
		}

		switch(self.payload) {
			inline else => |payload| {
				if(@hasDecl(@TypeOf(payload), "finalize")) {
					payload.finalize(side, data);
				}
			},
		}
	}

	fn confirmationData(self: *Command, allocator: NeverFailingAllocator) []const u8 {
		switch(self.payload) {
			inline else => |payload| {
				if(@hasDecl(@TypeOf(payload), "confirmationData")) {
					return payload.confirmationData(allocator);
				}
			},
		}
		return &.{};
	}

	fn executeAddOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, amount: u16, item: ?Item) void {
		if(amount == 0) return;
		if(item == null) return;
		if(side == .server) {
			self.syncOperations.append(allocator, .{
				.inv = inv,
				.amount = amount,
				.item = if(inv.ref().amount == 0) item else null,
			});
		}
		std.debug.assert(inv.ref().item == null or std.meta.eql(inv.ref().item.?, item.?));
		inv.ref().item = item.?;
		inv.ref().amount += amount;
		std.debug.assert(inv.ref().amount <= item.?.stackSize());
	}

	fn executeRemoveOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, amount: u16) void {
		if(amount == 0) return;
		if(side == .server) {
			self.syncOperations.append(allocator, .{
				.inv = inv,
				.amount = -@as(i32, amount),
				.item = null,
			});
		}
		inv.ref().amount -= amount;
		if(inv.ref().amount == 0) {
			inv.ref().item = null;
		}
	}

	fn executeBaseOperation(self: *Command, allocator: NeverFailingAllocator, _op: BaseOperation, side: Side) void {
		var op = _op;
		switch(op) {
			.move => |info| {
				self.executeAddOperation(allocator, side, info.dest, info.amount, info.source.ref().item);
				self.executeRemoveOperation(allocator, side, info.source, info.amount);
				info.source.inv.update();
				info.dest.inv.update();
			},
			.swap => |info| {
				const oldDestStack = info.dest.ref().*;
				const oldSourceStack = info.source.ref().*;
				self.executeRemoveOperation(allocator, side, info.source, oldSourceStack.amount);
				self.executeRemoveOperation(allocator, side, info.dest, oldDestStack.amount);
				self.executeAddOperation(allocator, side, info.source, oldDestStack.amount, oldDestStack.item);
				self.executeAddOperation(allocator, side, info.dest, oldSourceStack.amount, oldSourceStack.item);
				info.source.inv.update();
				info.dest.inv.update();
			},
			.delete => |*info| {
				info.item = info.source.ref().item;
				self.executeRemoveOperation(allocator, side, info.source, info.amount);
				info.source.inv.update();
			},
			.create => |info| {
				self.executeAddOperation(allocator, side, info.dest, info.amount, info.item);
				info.dest.inv.update();
			},
		}
		self.baseOperations.append(allocator, op);
	}

	fn removeToolCraftingIngredients(self: *Command, allocator: NeverFailingAllocator, inv: Inventory, side: Side) void {
		std.debug.assert(inv.type == .workbench);
		for(0..25) |i| {
			if(inv._items[i].amount != 0) {
				self.executeBaseOperation(allocator, .{.delete = .{
					.source = .{.inv = inv, .slot = @intCast(i)},
					.amount = 1,
				}}, side);
			}
		}
	}

	fn canPutIntoWorkbench(source: InventoryAndSlot) bool {
		if(source.ref().item) |item| {
			if(item != .baseItem) return false;
			return item.baseItem.material != null;
		}
		return true;
	}

	fn tryCraftingTo(self: *Command, allocator: NeverFailingAllocator, dest: InventoryAndSlot, source: InventoryAndSlot, side: Side, user: ?*main.server.User) void {
		std.debug.assert(source.inv.type == .crafting);
		std.debug.assert(dest.inv.type == .normal);
		if(source.slot != source.inv._items.len - 1) return;
		if(dest.ref().item != null and !std.meta.eql(dest.ref().item, source.ref().item)) return;
		if(dest.ref().amount + source.ref().amount > source.ref().item.?.stackSize()) return;

		const playerInventory: Inventory = switch(side) {
			.client => main.game.Player.inventory,
			.server => blk: {
				if(user) |_user| {
					var it = _user.inventoryClientToServerIdMap.valueIterator();
					while(it.next()) |serverId| {
						const serverInventory = &Sync.ServerSide.inventories.items[serverId.*];
						if(serverInventory.source == .playerInventory)
							break :blk serverInventory.inv;
					}
				}
				return;
			},
		};

		// Can we even craft it?
		for(source.inv._items[0..source.slot]) |requiredStack| {
			var amount: usize = 0;
			// There might be duplicate entries:
			for(source.inv._items[0..source.slot]) |otherStack| {
				if(std.meta.eql(requiredStack.item, otherStack.item))
					amount += otherStack.amount;
			}
			for(playerInventory._items) |otherStack| {
				if(std.meta.eql(requiredStack.item, otherStack.item))
					amount -|= otherStack.amount;
			}
			// Not enough ingredients
			if(amount != 0)
				return;
		}

		// Craft it
		for(source.inv._items[0..source.slot]) |requiredStack| {
			var remainingAmount: usize = requiredStack.amount;
			for(playerInventory._items, 0..) |*otherStack, i| {
				if(std.meta.eql(requiredStack.item, otherStack.item)) {
					const amount = @min(remainingAmount, otherStack.amount);
					self.executeBaseOperation(allocator, .{.delete = .{
						.source = .{.inv = playerInventory, .slot = @intCast(i)},
						.amount = amount,
					}}, side);
					remainingAmount -= amount;
					if(remainingAmount == 0) break;
				}
			}
			std.debug.assert(remainingAmount == 0);
		}
		self.executeBaseOperation(allocator, .{.create = .{
			.dest = dest,
			.amount = source.ref().amount,
			.item = source.ref().item,
		}}, side);
	}

	const Open = struct {
		inv: Inventory,
		source: Source,

		fn run(_: Open, _: NeverFailingAllocator, _: *Command, _: Side, _: ?*main.server.User) void {}

		fn finalize(self: Open, side: Side, data: []const u8) void {
			if(side != .client) return;
			if(data.len >= 4) {
				const serverId = std.mem.readInt(u32, data[0..4], .big);
				Sync.ClientSide.mapServerId(serverId, self.inv);
			}
		}

		fn confirmationData(self: Open, allocator: NeverFailingAllocator) []const u8 {
			const data = allocator.alloc(u8, 4);
			std.mem.writeInt(u32, data[0..4], self.inv.id, .big);
			return data;
		}

		fn serialize(self: Open, data: *main.List(u8)) void {
			std.mem.writeInt(u32, data.addMany(4)[0..4], self.inv.id, .big);
			std.mem.writeInt(usize, data.addMany(8)[0..8], self.inv._items.len, .big);
			data.append(@intFromEnum(self.inv.type));
			data.append(@intFromEnum(self.source));
			switch(self.source) {
				.playerInventory, .sharedTestingInventory, .other => {},
			}
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !Open {
			if(data.len < 14) return error.Invalid;
			if(side != .server or user == null) return error.Invalid;
			const id = std.mem.readInt(u32, data[0..4], .big);
			const len = std.mem.readInt(usize, data[4..12], .big);
			const typ: Inventory.Type = @enumFromInt(data[12]);
			const sourceType: SourceType = @enumFromInt(data[13]);
			const source: Source = switch(sourceType) {
				.playerInventory => .{.playerInventory = {}},
				.sharedTestingInventory => .{.sharedTestingInventory = {}},
				.other => .{.other = {}},
			};
			Sync.ServerSide.createInventory(user.?, id, len, typ, source);
			return .{
				.inv = Sync.ServerSide.getInventory(user.?, id) orelse return error.Invalid,
				.source = source,
			};
		}
	};

	const Close = struct {
		inv: Inventory,
		allocator: NeverFailingAllocator,

		fn run(_: Close, _: NeverFailingAllocator, _: *Command, _: Side, _: ?*main.server.User) void {}

		fn finalize(self: Close, side: Side, data: []const u8) void {
			if(side != .client) return;
			self.inv._deinit(self.allocator, .client);
			if(data.len >= 4) {
				const serverId = std.mem.readInt(u32, data[0..4], .big);
				Sync.ClientSide.unmapServerId(serverId, self.inv.id);
			}
		}

		fn serialize(self: Close, data: *main.List(u8)) void {
			std.mem.writeInt(u32, data.addMany(4)[0..4], self.inv.id, .big);
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !Close {
			if(data.len != 4) return error.Invalid;
			if(side != .server or user == null) return error.Invalid;
			const id = std.mem.readInt(u32, data[0..4], .big);
			try Sync.ServerSide.closeInventory(user.?, id);
			return undefined;
		}
	};

	const DepositOrSwap = struct {
		dest: InventoryAndSlot,
		source: InventoryAndSlot,

		fn run(self: DepositOrSwap, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User) void {
			std.debug.assert(self.source.inv.type == .normal);
			if(self.dest.inv.type == .creative) {
				FillFromCreative.run(.{.dest = self.source, .item = self.dest.ref().item}, allocator, cmd, side, user);
				return;
			}
			if(self.dest.inv.type == .crafting) {
				cmd.tryCraftingTo(allocator, self.source, self.dest, side, user);
				return;
			}
			if(self.dest.inv.type == .workbench and self.dest.slot == 25) {
				if(self.source.ref().item == null and self.dest.ref().item != null) {
					cmd.executeBaseOperation(allocator, .{.move = .{
						.dest = self.source,
						.source = self.dest,
						.amount = 1,
					}}, side);
					cmd.removeToolCraftingIngredients(allocator, self.dest.inv, side);
				}
				return;
			}
			if(self.dest.inv.type == .workbench and !canPutIntoWorkbench(self.source)) return;

			if(self.dest.ref().item) |itemDest| {
				if(self.source.ref().item) |itemSource| {
					if(std.meta.eql(itemDest, itemSource)) {
						if(self.dest.ref().amount >= itemDest.stackSize()) return;
						const amount = @min(itemDest.stackSize() - self.dest.ref().amount, self.source.ref().amount);
						cmd.executeBaseOperation(allocator, .{.move = .{
							.dest = self.dest,
							.source = self.source,
							.amount = amount,
						}}, side);
						return;
					}
				}
			}
			if(self.source.inv.type == .workbench and !canPutIntoWorkbench(self.dest)) return;
			cmd.executeBaseOperation(allocator, .{.swap = .{
				.dest = self.dest,
				.source = self.source,
			}}, side);
		}

		fn serialize(self: DepositOrSwap, data: *main.List(u8)) void {
			self.dest.write(data.addMany(8)[0..8]);
			self.source.write(data.addMany(8)[0..8]);
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !DepositOrSwap {
			if(data.len != 16) return error.Invalid;
			return .{
				.dest = try InventoryAndSlot.read(data[0..8], side, user),
				.source = try InventoryAndSlot.read(data[8..16], side, user),
			};
		}
	};

	const Deposit = struct {
		dest: InventoryAndSlot,
		source: InventoryAndSlot,
		amount: u16,

		fn run(self: Deposit, allocator: NeverFailingAllocator, cmd: *Command, side: Side, _: ?*main.server.User) void {
			std.debug.assert(self.source.inv.type == .normal);
			if(self.dest.inv.type == .creative) return;
			if(self.dest.inv.type == .crafting) return;
			if(self.dest.inv.type == .workbench and self.dest.slot == 25) return;
			if(self.dest.inv.type == .workbench and !canPutIntoWorkbench(self.source)) return;
			const itemSource = self.source.ref().item orelse return;
			if(self.dest.ref().item) |itemDest| {
				if(std.meta.eql(itemDest, itemSource)) {
					if(self.dest.ref().amount >= itemDest.stackSize()) return;
					const amount = @min(itemDest.stackSize() - self.dest.ref().amount, self.source.ref().amount, self.amount);
					cmd.executeBaseOperation(allocator, .{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = amount,
					}}, side);
				}
			} else {
				cmd.executeBaseOperation(allocator, .{.move = .{
					.dest = self.dest,
					.source = self.source,
					.amount = self.amount,
				}}, side);
			}
		}

		fn serialize(self: Deposit, data: *main.List(u8)) void {
			self.dest.write(data.addMany(8)[0..8]);
			self.source.write(data.addMany(8)[0..8]);
			std.mem.writeInt(u16, data.addMany(2)[0..2], self.amount, .big);
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !Deposit {
			if(data.len != 18) return error.Invalid;
			return .{
				.dest = try InventoryAndSlot.read(data[0..8], side, user),
				.source = try InventoryAndSlot.read(data[8..16], side, user),
				.amount = std.mem.readInt(u16, data[16..18], .big),
			};
		}
	};

	const TakeHalf = struct {
		dest: InventoryAndSlot,
		source: InventoryAndSlot,

		fn run(self: TakeHalf, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User) void {
			std.debug.assert(self.dest.inv.type == .normal);
			if(self.source.inv.type == .creative) {
				if(self.dest.ref().item == null) {
					const item = self.source.ref().item;
					FillFromCreative.run(.{.dest = self.dest, .item = item}, allocator, cmd, side, user);
				}
				return;
			}
			if(self.source.inv.type == .crafting) {
				cmd.tryCraftingTo(allocator, self.dest, self.source, side, user);
				return;
			}
			if(self.source.inv.type == .workbench and self.source.slot == 25) {
				if(self.dest.ref().item == null and self.source.ref().item != null) {
					cmd.executeBaseOperation(allocator, .{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = 1,
					}}, side);
					cmd.removeToolCraftingIngredients(allocator, self.dest.inv, side);
				}
				return;
			}
			const itemSource = self.source.ref().item orelse return;
			const desiredAmount = (1 + self.source.ref().amount)/2;
			if(self.dest.ref().item) |itemDest| {
				if(std.meta.eql(itemDest, itemSource)) {
					if(self.dest.ref().amount >= itemDest.stackSize()) return;
					const amount = @min(itemDest.stackSize() - self.dest.ref().amount, desiredAmount);
					cmd.executeBaseOperation(allocator, .{ .move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = amount,
					}}, side);
				}
			} else {
				cmd.executeBaseOperation(allocator, .{ .move = .{
					.dest = self.dest,
					.source = self.source,
					.amount = desiredAmount,
				}}, side);
			}
		}

		fn serialize(self: TakeHalf, data: *main.List(u8)) void {
			self.dest.write(data.addMany(8)[0..8]);
			self.source.write(data.addMany(8)[0..8]);
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !TakeHalf {
			if(data.len != 16) return error.Invalid;
			return .{
				.dest = try InventoryAndSlot.read(data[0..8], side, user),
				.source = try InventoryAndSlot.read(data[8..16], side, user),
			};
		}
	};

	const Drop = struct {
		source: InventoryAndSlot,
		desiredAmount: u16 = 0xffff,

		fn run(self: Drop, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User) void {
			if(self.source.inv.type == .creative) return;
			if(self.source.ref().item == null) return;
			if(self.source.inv.type == .crafting) {
				if(self.source.slot != self.source.inv._items.len - 1) return;
				var _items: [1]ItemStack = .{.{.item = null, .amount = 0}};
				const temp: Inventory = .{
					.type = .normal,
					._items = &_items,
					.id = undefined,
				};
				cmd.tryCraftingTo(allocator, .{.inv = temp, .slot = 0}, self.source, side, user);
				std.debug.assert(cmd.baseOperations.pop().create.dest.inv._items.ptr == temp._items.ptr); // Remove the extra step from undo list (we cannot undo dropped items)
				if(_items[0].item != null) {
					if(side == .server) {
						const direction = vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -user.?.player.rot[0]), -user.?.player.rot[2]);
						main.server.world.?.drop(_items[0], user.?.player.pos, direction, 20);
					}
				}
				return;
			}
			if(self.source.inv.type == .workbench and self.source.slot == 25) {
				cmd.removeToolCraftingIngredients(allocator, self.source.inv, side);
			}
			if(side == .server) {
				const direction = vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -user.?.player.rot[0]), -user.?.player.rot[2]);
				main.server.world.?.drop(self.source.ref().*, user.?.player.pos, direction, 20);
			}
			cmd.executeBaseOperation(allocator, .{.delete = .{
				.source = self.source,
				.amount = @min(self.source.ref().amount, self.desiredAmount),
			}}, side);
		}

		fn serialize(self: Drop, data: *main.List(u8)) void {
			self.source.write(data.addMany(8)[0..8]);
			if(self.desiredAmount != 0xffff) {
				std.mem.writeInt(u16, data.addMany(2)[0..2], self.desiredAmount, .big);
			}
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !Drop {
			if(data.len != 8 and data.len != 10) return error.Invalid;
			return .{
				.source = try InventoryAndSlot.read(data[0..8], side, user),
				.desiredAmount = if(data.len == 10) std.mem.readInt(u16, data[8..10], .big) else 0xffff,
			};
		}
	};

	const FillFromCreative = struct {
		dest: InventoryAndSlot,
		item: ?Item,
		amount: u16 = 0,

		fn run(self: FillFromCreative, allocator: NeverFailingAllocator, cmd: *Command, side: Side, _: ?*main.server.User) void {
			if(self.dest.inv.type == .workbench and self.dest.slot == 25) return;

			if(!self.dest.ref().empty()) {
				cmd.executeBaseOperation(allocator, .{.delete = .{
					.source = self.dest,
					.amount = self.dest.ref().amount,
				}}, side);
			}
			if(self.item) |_item| {
				cmd.executeBaseOperation(allocator, .{.create = .{
					.dest = self.dest,
					.item = _item,
					.amount = if(self.amount == 0) _item.stackSize() else self.amount,
				}}, side);
			}
		}

		fn serialize(self: FillFromCreative, data: *main.List(u8)) void {
			self.dest.write(data.addMany(8)[0..8]);
			std.mem.writeInt(u16, data.addMany(2)[0..2], self.amount, .big);
			if(self.item) |item| {
				const zon = ZonElement.initObject(main.stackAllocator);
				defer zon.free(main.stackAllocator);
				item.insertIntoZon(main.stackAllocator, zon);
				const string = zon.toStringEfficient(main.stackAllocator, &.{});
				defer main.stackAllocator.free(string);
				data.appendSlice(string);
			}
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !FillFromCreative {
			if(data.len < 10) return error.Invalid;
			const amount = std.mem.readInt(u16, data[8..10], .big);
			var item: ?Item = null;
			if(data.len > 10) {
				const zon = ZonElement.parseFromString(main.stackAllocator, data[10..]);
				defer zon.free(main.stackAllocator);
				item = try Item.init(zon);
			}
			return .{
				.dest = try InventoryAndSlot.read(data[0..8], side, user),
				.item = item,
				.amount = amount,
			};
		}
	};

	const DepositOrDrop = struct {
		dest: Inventory,
		source: Inventory,

		pub fn run(self: DepositOrDrop, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User) void {
			std.debug.assert(self.dest.type == .normal);
			if(self.source.type == .creative) return;
			if(self.source.type == .crafting) return;
			var sourceItems = self.source._items;
			if(self.source.type == .workbench) sourceItems = self.source._items[0..25];
			outer: for(sourceItems, 0..) |*sourceStack, sourceSlot| {
				if(sourceStack.item == null) continue;
				for(self.dest._items, 0..) |*destStack, destSlot| {
					if(std.meta.eql(destStack.item, sourceStack.item)) {
						const amount = @min(destStack.item.?.stackSize() - destStack.amount, sourceStack.amount);
						cmd.executeBaseOperation(allocator, .{.move = .{
							.dest = .{.inv = self.dest, .slot = @intCast(destSlot)},
							.source = .{.inv = self.source, .slot = @intCast(sourceSlot)},
							.amount = amount,
						}}, side);
						if(sourceStack.amount == 0) {
							continue :outer;
						}
					}
				}
				for(self.dest._items, 0..) |*destStack, destSlot| {
					if(destStack.item == null) {
						cmd.executeBaseOperation(allocator, .{.swap = .{
							.dest = .{.inv = self.dest, .slot = @intCast(destSlot)},
							.source = .{.inv = self.source, .slot = @intCast(sourceSlot)},
						}}, side);
						continue :outer;
					}
				}
				if(side == .server) {
					const direction = vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -user.?.player.rot[0]), -user.?.player.rot[2]);
					main.server.world.?.drop(sourceStack.*, user.?.player.pos, direction, 20);
				}
				cmd.executeBaseOperation(allocator, .{.delete = .{
					.source = .{.inv = self.source, .slot = @intCast(sourceSlot)},
					.amount = self.source._items[sourceSlot].amount,
				}}, side);
			}
		}

		fn serialize(self: DepositOrDrop, data: *main.List(u8)) void {
			std.mem.writeInt(u32, data.addMany(4)[0..4], self.dest.id, .big);
			std.mem.writeInt(u32, data.addMany(4)[0..4], self.source.id, .big);
		}

		fn deserialize(data: []const u8, side: Side, user: ?*main.server.User) !DepositOrDrop {
			if(data.len != 8) return error.Invalid;
			const destId = std.mem.readInt(u32, data[0..4], .big);
			const sourceId = std.mem.readInt(u32, data[4..8], .big);
			return .{
				.dest = Sync.getInventory(destId, side, user) orelse return error.Invalid,
				.source = Sync.getInventory(sourceId, side, user) orelse return error.Invalid,
			};
		}
	};
};

const SourceType = enum(u8) {
	playerInventory = 0,
	sharedTestingInventory = 1,
	other = 0xff, // TODO: List every type separately here.
};
const Source = union(SourceType) {
	playerInventory: void,
	sharedTestingInventory: void,
	other: void,
};

const Inventory = @This();

const Type = enum(u8) {
	normal = 0,
	creative = 1,
	crafting = 2,
	workbench = 3,
};
type: Type,
id: u32,
_items: []ItemStack,

pub fn init(allocator: NeverFailingAllocator, _size: usize, _type: Type, source: Source) Inventory {
	const self = _init(allocator, _size, _type, .client);
	Sync.executeCommand(.{.open = .{.inv = self, .source = source}});
	return self;
}

fn _init(allocator: NeverFailingAllocator, _size: usize, _type: Type, side: Side) Inventory {
	if(_type == .workbench) std.debug.assert(_size == 26);
	const self = Inventory{
		.type = _type,
		._items = allocator.alloc(ItemStack, _size),
		.id = switch(side) {
			.client => Sync.ClientSide.nextId(),
			.server => Sync.ServerSide.nextId(),
		},
	};
	for(self._items) |*item| {
		item.* = ItemStack{};
	}
	return self;
}

pub fn deinit(self: Inventory, allocator: NeverFailingAllocator) void {
	Sync.executeCommand(.{.close = .{.inv = self, .allocator = allocator}});
}

fn _deinit(self: Inventory, allocator: NeverFailingAllocator, side: Side) void {
	switch(side) {
		.client => Sync.ClientSide.freeId(self.id),
		.server => Sync.ServerSide.freeId(self.id),
	}
	for(self._items) |*item| {
		item.deinit();
	}
	allocator.free(self._items);
}

fn update(self: Inventory) void {
	if(self.type == .workbench) {
		self._items[self._items.len - 1].deinit();
		self._items[self._items.len - 1].clear();
		var availableItems: [25]?*const BaseItem = undefined;
		var nonEmpty: bool = false;
		for(0..25) |i| {
			if(self._items[i].item != null and self._items[i].item.? == .baseItem) {
				availableItems[i] = self._items[i].item.?.baseItem;
				nonEmpty = true;
			} else {
				availableItems[i] = null;
			}
		}
		if(nonEmpty) {
			self._items[self._items.len - 1].item = Item{.tool = Tool.initFromCraftingGrid(availableItems, @intCast(std.time.nanoTimestamp() & 0xffffffff))}; // TODO
			self._items[self._items.len - 1].amount = 1;
		}
	}
}

pub fn depositOrSwap(dest: Inventory, destSlot: u32, carried: Inventory) void {
	Sync.executeCommand(.{.depositOrSwap = .{.dest = .{.inv = dest, .slot = destSlot}, .source = .{.inv = carried, .slot = 0}}});
}

pub fn deposit(dest: Inventory, destSlot: u32, carried: Inventory, amount: u16) void {
	Sync.executeCommand(.{.deposit = .{.dest = .{.inv = dest, .slot = destSlot}, .source = .{.inv = carried, .slot = 0}, .amount = amount}});
}

pub fn takeHalf(source: Inventory, sourceSlot: u32, carried: Inventory) void {
	Sync.executeCommand(.{.takeHalf = .{.dest = .{.inv = carried, .slot = 0}, .source = .{.inv = source, .slot = sourceSlot}}});
}

pub fn distribute(carried: Inventory, destinationInventories: []const Inventory, destinationSlots: []const u32) void {
	const amount = carried._items[0].amount/destinationInventories.len;
	if(amount == 0) return;
	for(0..destinationInventories.len) |i| {
		destinationInventories[i].deposit(destinationSlots[i], carried, @intCast(amount));
	}
}

pub fn depositOrDrop(dest: Inventory, source: Inventory) void {
	Sync.executeCommand(.{.depositOrDrop = .{.dest = dest, .source = source}});
}

pub fn dropStack(source: Inventory, sourceSlot: u32) void {
	Sync.executeCommand(.{.drop = .{.source = .{.inv = source, .slot = sourceSlot}}});
}

pub fn dropOne(source: Inventory, sourceSlot: u32) void {
	Sync.executeCommand(.{.drop = .{.source = .{.inv = source, .slot = sourceSlot}, .desiredAmount = 1}});
}

pub fn fillFromCreative(dest: Inventory, destSlot: u32, item: ?Item) void {
	Sync.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = dest, .slot = destSlot}, .item = item}});
}

pub fn fillAmountFromCreative(dest: Inventory, destSlot: u32, item: ?Item, amount: u16) void {
	Sync.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = dest, .slot = destSlot}, .item = item, .amount = amount}});
}

pub fn placeBlock(self: Inventory, slot: u32, unlimitedBlocks: bool) void {
	main.renderer.MeshSelection.placeBlock(&self._items[slot], unlimitedBlocks);
}

pub fn breakBlock(self: Inventory, slot: u32) void {
	main.renderer.MeshSelection.breakBlock(&self._items[slot]);
}

pub fn size(self: Inventory) usize {
	return self._items.len;
}

pub fn getItem(self: Inventory, slot: usize) ?Item {
	return self._items[slot].item;
}

pub fn getStack(self: Inventory, slot: usize) ItemStack {
	return self._items[slot];
}

pub fn getAmount(self: Inventory, slot: usize) u16 {
	return self._items[slot].amount;
}

pub fn save(self: Inventory, allocator: NeverFailingAllocator) ZonElement {
	const zonObject = ZonElement.initObject(allocator);
	zonObject.put("capacity", self._items.len);
	for(self._items, 0..) |stack, i| {
		if(!stack.empty()) {
			var buf: [1024]u8 = undefined;
			zonObject.put(buf[0..std.fmt.formatIntBuf(&buf, i, 10, .lower, .{})], stack.store(allocator));
		}
	}
	return zonObject;
}

pub fn loadFromZon(self: Inventory, zon: ZonElement) void {
	for(self._items, 0..) |*stack, i| {
		stack.clear();
		var buf: [1024]u8 = undefined;
		const stackZon = zon.getChild(buf[0..std.fmt.formatIntBuf(&buf, i, 10, .lower, .{})]);
		if(stackZon == .object) {
			stack.item = Item.init(stackZon) catch |err| {
				const msg = stackZon.toStringEfficient(main.stackAllocator, "");
				defer main.stackAllocator.free(msg);
				std.log.err("Couldn't find item {s}: {s}", .{msg, @errorName(err)});
				stack.clear();
				continue;
			};
			stack.amount = stackZon.get(u16, "amount", 0);
		}
	}
}