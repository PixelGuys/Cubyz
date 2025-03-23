const std = @import("std");

const main = @import("main.zig");
const BaseItem = main.items.BaseItem;
const Block = main.blocks.Block;
const Item = main.items.Item;
const ItemStack = main.items.ItemStack;
const Tool = main.items.Tool;
const utils = main.utils;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

const Gamemode = main.game.Gamemode;

const Side = enum {client, server};

pub const Sync = struct { // MARK: Sync

	pub const ClientSide = struct {
		pub var mutex: std.Thread.Mutex = .{};
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
				var reader = utils.BinaryReader.init(&.{}, main.network.networkEndian);
				cmd.finalize(main.globalAllocator, .client, &reader) catch |err| {
					std.log.err("Got error while cleaning remaining inventory commands: {s}", .{@errorName(err)});
				};
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
			cmd.do(main.globalAllocator, .client, null, main.game.Player.gamemode.raw) catch unreachable;
			const data = cmd.serializePayload(main.stackAllocator);
			defer main.stackAllocator.free(data);
			main.network.Protocols.inventory.sendCommand(main.game.world.?.conn, cmd.payload, data);
			commands.enqueue(cmd);
		}

		pub fn undo() void {
			mutex.lock();
			defer mutex.unlock();
			if(commands.dequeue_front()) |_cmd| {
				var cmd = _cmd;
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
			main.utils.assertLocked(&mutex);
			serverToClientMap.put(serverId, inventory) catch unreachable;
		}

		fn unmapServerId(serverId: u32, clientId: u32) void {
			main.utils.assertLocked(&mutex);
			std.debug.assert(serverToClientMap.fetchRemove(serverId).?.value.id == clientId);
		}

		fn getInventory(serverId: u32) ?Inventory {
			main.utils.assertLocked(&mutex);
			return serverToClientMap.get(serverId);
		}

		pub fn receiveConfirmation(reader: *utils.BinaryReader) !void {
			mutex.lock();
			defer mutex.unlock();
			try commands.dequeue().?.finalize(main.globalAllocator, .client, reader);
		}

		pub fn receiveFailure() void {
			mutex.lock();
			defer mutex.unlock();
			var tempData = main.List(Command).init(main.stackAllocator);
			defer tempData.deinit();
			while(commands.dequeue_front()) |_cmd| {
				var cmd = _cmd;
				cmd.undo();
				tempData.append(cmd);
			}
			if(tempData.popOrNull()) |_cmd| {
				var cmd = _cmd;
				var reader = utils.BinaryReader.init(&.{}, main.network.networkEndian);
				cmd.finalize(main.globalAllocator, .client, &reader) catch |err| {
					std.log.err("Got error while cleaning rejected inventory command: {s}", .{@errorName(err)});
				};
			}
			while(tempData.popOrNull()) |_cmd| {
				var cmd = _cmd;
				cmd.do(main.globalAllocator, .client, null, main.game.Player.gamemode.raw) catch unreachable;
				commands.enqueue(cmd);
			}
		}

		pub fn receiveSyncOperation(reader: *utils.BinaryReader) !void {
			mutex.lock();
			defer mutex.unlock();
			var tempData = main.List(Command).init(main.stackAllocator);
			defer tempData.deinit();
			while(commands.dequeue_front()) |_cmd| {
				var cmd = _cmd;
				cmd.undo();
				tempData.append(cmd);
			}
			try Command.SyncOperation.executeFromData(reader);
			while(tempData.popOrNull()) |_cmd| {
				var cmd = _cmd;
				cmd.do(main.globalAllocator, .client, null, main.game.Player.gamemode.raw) catch unreachable;
				commands.enqueue(cmd);
			}
		}

		fn setGamemode(gamemode: Gamemode) void {
			mutex.lock();
			defer mutex.unlock();
			main.game.Player.setGamemode(gamemode);
			var tempData = main.List(Command).init(main.stackAllocator);
			defer tempData.deinit();
			while(commands.dequeue_front()) |_cmd| {
				var cmd = _cmd;
				cmd.undo();
				tempData.append(cmd);
			}
			while(tempData.popOrNull()) |_cmd| {
				var cmd = _cmd;
				cmd.do(main.globalAllocator, .client, null, gamemode) catch unreachable;
				commands.enqueue(cmd);
			}
		}
	};

	pub const ServerSide = struct { // MARK: ServerSide
		const ServerInventory = struct {
			inv: Inventory,
			users: main.ListUnmanaged(*main.server.User),
			source: Source,

			fn init(len: usize, typ: Inventory.Type, source: Source) ServerInventory {
				main.utils.assertLocked(&mutex);
				return .{
					.inv = Inventory._init(main.globalAllocator, len, typ, .server),
					.users = .{},
					.source = source,
				};
			}

			fn deinit(self: *ServerInventory) void {
				main.utils.assertLocked(&mutex);
				std.debug.assert(self.users.items.len == 0);
				self.users.deinit(main.globalAllocator);
				self.inv._deinit(main.globalAllocator, .server);
				self.inv._items.len = 0;
				self.source = .alreadyFreed;
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
		pub var mutex: std.Thread.Mutex = .{};

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
			maxId = 0;
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

		fn executeCommand(payload: Command.Payload, source: ?*main.server.User) void {
			var command = Command{
				.payload = payload,
			};
			command.do(main.globalAllocator, .server, source, if(source) |s| s.gamemode.raw else .creative) catch {
				main.network.Protocols.inventory.sendFailure(source.?.conn);
				return;
			};
			if(source != null) {
				const confirmationData = command.confirmationData(main.stackAllocator);
				defer main.stackAllocator.free(confirmationData);
				main.network.Protocols.inventory.sendConfirmation(source.?.conn, confirmationData);
			}
			for(command.syncOperations.items) |op| {
				const syncData = op.serialize(main.stackAllocator);
				defer main.stackAllocator.free(syncData);

				const users = op.getUsers(main.stackAllocator);
				defer main.stackAllocator.free(users);

				for(users) |user| {
					if(user == source and op.ignoreSource()) continue;
					main.network.Protocols.inventory.sendSyncOperation(user.conn, syncData);
				}
			}
			if(source != null and command.payload == .open) { // Send initial items
				for(command.payload.open.inv._items, 0..) |stack, slot| {
					if(stack.item != null) {
						const syncOp = Command.SyncOperation{.create = .{
							.inv = .{.inv = command.payload.open.inv, .slot = @intCast(slot)},
							.amount = stack.amount,
							.item = stack.item,
						}};
						const syncData = syncOp.serialize(main.stackAllocator);
						defer main.stackAllocator.free(syncData);
						main.network.Protocols.inventory.sendSyncOperation(source.?.conn, syncData);
					}
				}
			}
			var reader = utils.BinaryReader.init(&.{}, main.network.networkEndian);
			command.finalize(main.globalAllocator, .server, &reader) catch |err| {
				std.log.err("Got error while finalizing command on the server side: {s}", .{@errorName(err)});
			};
		}

		pub fn receiveCommand(source: *main.server.User, reader: *utils.BinaryReader) !void {
			mutex.lock();
			defer mutex.unlock();
			const typ = try reader.readEnum(Command.PayloadType);
			@setEvalBranchQuota(100000);
			const payload: Command.Payload = switch(typ) {
				inline else => |_typ| @unionInit(Command.Payload, @tagName(_typ), try std.meta.FieldType(Command.Payload, _typ).deserialize(reader, .server, source)),
			};
			executeCommand(payload, source);
		}

		fn createInventory(user: *main.server.User, clientId: u32, len: usize, typ: Inventory.Type, source: Source) void {
			main.utils.assertLocked(&mutex);
			switch(source) {
				.sharedTestingInventory, .recipe => {
					for(inventories.items) |*inv| {
						if(std.meta.eql(inv.source, source)) {
							inv.addUser(user, clientId);
							return;
						}
					}
				},
				.playerInventory, .hand, .other => {},
				.alreadyFreed => unreachable,
			}
			const inventory = ServerInventory.init(len, typ, source);

			switch(source) {
				.sharedTestingInventory => {},
				.playerInventory, .hand => {
					const dest: []u8 = main.stackAllocator.alloc(u8, std.base64.url_safe.Encoder.calcSize(user.name.len));
					defer main.stackAllocator.free(dest);
					const hashedName = std.base64.url_safe.Encoder.encode(dest, user.name);

					const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players/{s}.zig.zon", .{main.server.world.?.name, hashedName}) catch unreachable;
					defer main.stackAllocator.free(path);

					const playerData = main.files.readToZon(main.stackAllocator, path) catch .null;
					defer playerData.deinit(main.stackAllocator);

					const inventoryZon = playerData.getChild(@tagName(source));

					inventory.inv.loadFromZon(inventoryZon);
				},
				.recipe => |recipe| {
					for(0..recipe.sourceAmounts.len) |i| {
						inventory.inv._items[i].amount = recipe.sourceAmounts[i];
						inventory.inv._items[i].item = .{.baseItem = recipe.sourceItems[i]};
					}
					inventory.inv._items[inventory.inv._items.len - 1].amount = recipe.resultAmount;
					inventory.inv._items[inventory.inv._items.len - 1].item = .{.baseItem = recipe.resultItem};
				},
				.other => {},
				.alreadyFreed => unreachable,
			}

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

		pub fn getInventoryFromSource(source: Source) ?Inventory {
			main.utils.assertLocked(&mutex);
			for(inventories.items) |inv| {
				if(std.meta.eql(inv.source, source)) {
					return inv.inv;
				}
			}
			return null;
		}

		pub fn clearPlayerInventory(user: *main.server.User) void {
			mutex.lock();
			defer mutex.unlock();
			var inventoryIdIterator = user.inventoryClientToServerIdMap.valueIterator();
			while(inventoryIdIterator.next()) |inventoryId| {
				if(inventories.items[inventoryId.*].source == .playerInventory) {
					executeCommand(.{.clear = .{.inv = inventories.items[inventoryId.*].inv}}, null);
				}
			}
		}

		pub fn tryCollectingToPlayerInventory(user: *main.server.User, itemStack: *ItemStack) void {
			if(itemStack.item == null) return;
			mutex.lock();
			defer mutex.unlock();
			var inventoryIdIterator = user.inventoryClientToServerIdMap.valueIterator();
			outer: while(inventoryIdIterator.next()) |inventoryId| {
				if(inventories.items[inventoryId.*].source == .playerInventory) {
					const inv = inventories.items[inventoryId.*].inv;
					for(inv._items, 0..) |invStack, slot| {
						if(std.meta.eql(invStack.item, itemStack.item)) {
							const amount = @min(itemStack.item.?.stackSize() - invStack.amount, itemStack.amount);
							if(amount == 0) continue;
							executeCommand(.{.fillFromCreative = .{.dest = .{.inv = inv, .slot = @intCast(slot)}, .item = itemStack.item, .amount = invStack.amount + amount}}, null);
							itemStack.amount -= amount;
							if(itemStack.amount == 0) break :outer;
						}
					}
					for(inv._items, 0..) |invStack, slot| {
						if(invStack.item == null) {
							executeCommand(.{.fillFromCreative = .{.dest = .{.inv = inv, .slot = @intCast(slot)}, .item = itemStack.item, .amount = itemStack.amount}}, null);
							itemStack.amount = 0;
							break :outer;
						}
					}
				}
			}
			if(itemStack.amount == 0) itemStack.item = null;
		}

		fn setGamemode(user: *main.server.User, gamemode: Gamemode) void {
			mutex.lock();
			defer mutex.unlock();
			user.gamemode.store(gamemode, .monotonic);
			main.network.Protocols.genericUpdate.sendGamemode(user.conn, gamemode);
		}
	};

	pub fn addHealth(health: f32, cause: main.game.DamageType, side: Side, id: u32) void {
		if(side == .client) {
			Sync.ClientSide.executeCommand(.{.addHealth = .{.target = id, .health = health, .cause = cause}});
		} else {
			Sync.ServerSide.executeCommand(.{.addHealth = .{.target = id, .health = health, .cause = cause}}, null);
		}
	}

	pub fn getInventory(id: u32, side: Side, user: ?*main.server.User) ?Inventory {
		return switch(side) {
			.client => ClientSide.getInventory(id),
			.server => ServerSide.getInventory(user.?, id),
		};
	}

	pub fn setGamemode(user: ?*main.server.User, gamemode: Gamemode) void {
		if(user == null) {
			ClientSide.setGamemode(gamemode);
		} else {
			ServerSide.setGamemode(user.?, gamemode);
		}
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
		clear = 8,
		updateBlock = 9,
		addHealth = 10,
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
		clear: Clear,
		updateBlock: UpdateBlock,
		addHealth: AddHealth,
	};

	const BaseOperationType = enum(u8) {
		move = 0,
		swap = 1,
		delete = 2,
		create = 3,
		useDurability = 4,
		addHealth = 5,
		addEnergy = 6,
	};

	const InventoryAndSlot = struct {
		inv: Inventory,
		slot: u32,

		fn ref(self: InventoryAndSlot) *ItemStack {
			return &self.inv._items[self.slot];
		}

		fn write(self: InventoryAndSlot, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.inv.id);
			writer.writeInt(u32, self.slot);
		}

		fn read(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !InventoryAndSlot {
			const id = try reader.readInt(u32);
			return .{
				.inv = Sync.getInventory(id, side, user) orelse return error.Invalid,
				.slot = try reader.readInt(u32),
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
		useDurability: struct {
			source: InventoryAndSlot,
			item: main.items.Item = undefined,
			durability: u31,
			previousDurability: u32 = undefined,
		},
		addHealth: struct {
			target: ?*main.server.User,
			health: f32,
			cause: main.game.DamageType,
			previous: f32,
		},
		addEnergy: struct {
			target: ?*main.server.User,
			energy: f32,
			previous: f32,
		},
	};

	const SyncOperationType = enum(u8) {
		create = 0,
		delete = 1,
		useDurability = 2,
		health = 3,
		kill = 4,
		energy = 5,
	};

	const SyncOperation = union(SyncOperationType) { // MARK: SyncOperation
		// Since the client doesn't know about all inventories, we can only use create(+amount)/delete(-amount) and use durability operations to apply the server side updates.
		create: struct {
			inv: InventoryAndSlot,
			amount: u16,
			item: ?Item,
		},
		delete: struct {
			inv: InventoryAndSlot,
			amount: u16,
		},
		useDurability: struct {
			inv: InventoryAndSlot,
			durability: u32,
		},
		health: struct {
			target: ?*main.server.User,
			health: f32,
		},
		kill: struct {
			target: ?*main.server.User,
		},
		energy: struct {
			target: ?*main.server.User,
			energy: f32,
		},

		pub fn executeFromData(reader: *utils.BinaryReader) !void {
			switch(try deserialize(reader)) {
				.create => |create| {
					if(create.item) |item| {
						create.inv.ref().item = item;
					} else if(create.inv.ref().item == null) {
						return error.Invalid;
					}

					if(create.inv.ref().amount +| create.amount > create.inv.ref().item.?.stackSize()) {
						return error.Invalid;
					}
					create.inv.ref().amount += create.amount;

					create.inv.inv.update();
				},
				.delete => |delete| {
					if(delete.inv.ref().amount < delete.amount) {
						return error.Invalid;
					}
					delete.inv.ref().amount -= delete.amount;
					if(delete.inv.ref().amount == 0) {
						delete.inv.ref().item = null;
					}

					delete.inv.inv.update();
				},
				.useDurability => |durability| {
					durability.inv.ref().item.?.tool.durability -|= durability.durability;
					if(durability.inv.ref().item.?.tool.durability == 0) {
						durability.inv.ref().item = null;
						durability.inv.ref().amount = 0;
					}

					durability.inv.inv.update();
				},
				.health => |health| {
					main.game.Player.super.health = std.math.clamp(main.game.Player.super.health + health.health, 0, main.game.Player.super.maxHealth);
				},
				.kill => {
					main.game.Player.kill();
				},
				.energy => |energy| {
					main.game.Player.super.energy = std.math.clamp(main.game.Player.super.energy + energy.energy, 0, main.game.Player.super.maxEnergy);
				},
			}
		}

		pub fn getUsers(self: SyncOperation, allocator: NeverFailingAllocator) []*main.server.User {
			switch(self) {
				inline .create, .delete, .useDurability => |data| {
					return allocator.dupe(*main.server.User, Sync.ServerSide.inventories.items[data.inv.inv.id].users.items);
				},
				inline .health, .kill, .energy => |data| {
					const out = allocator.alloc(*main.server.User, 1);
					out[0] = data.target.?;
					return out;
				},
			}
		}

		pub fn ignoreSource(self: SyncOperation) bool {
			return switch(self) {
				.create, .delete, .useDurability, .health, .energy => true,
				.kill => false,
			};
		}

		fn deserialize(reader: *utils.BinaryReader) !SyncOperation {
			const typ = try reader.readEnum(SyncOperationType);

			switch(typ) {
				.create => {
					var out: SyncOperation = .{.create = .{
						.inv = try InventoryAndSlot.read(reader, .client, null),
						.amount = try reader.readInt(u16),
						.item = null,
					}};

					if(reader.remaining.len != 0) {
						const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
						defer zon.deinit(main.stackAllocator);
						out.create.item = try Item.init(zon);
					}

					return out;
				},
				.delete => {
					const out: SyncOperation = .{.delete = .{
						.inv = try InventoryAndSlot.read(reader, .client, null),
						.amount = try reader.readInt(u16),
					}};

					return out;
				},
				.useDurability => {
					const out: SyncOperation = .{.useDurability = .{
						.inv = try InventoryAndSlot.read(reader, .client, null),
						.durability = try reader.readInt(u32),
					}};

					return out;
				},
				.health => {
					return .{.health = .{
						.target = null,
						.health = @bitCast(try reader.readInt(u32)),
					}};
				},
				.kill => {
					return .{.kill = .{
						.target = null,
					}};
				},
				.energy => {
					return .{.energy = .{
						.target = null,
						.energy = @bitCast(try reader.readInt(u32)),
					}};
				},
			}
		}

		pub fn serialize(self: SyncOperation, allocator: NeverFailingAllocator) []const u8 {
			var writer = utils.BinaryWriter.initCapacity(allocator, main.network.networkEndian, 13);
			writer.writeEnum(SyncOperationType, self);
			switch(self) {
				.create => |create| {
					create.inv.write(&writer);
					writer.writeInt(u16, create.amount);
					if(create.item) |item| {
						const zon = ZonElement.initObject(main.stackAllocator);
						defer zon.deinit(main.stackAllocator);
						item.insertIntoZon(main.stackAllocator, zon);
						const string = zon.toStringEfficient(main.stackAllocator, &.{});
						defer main.stackAllocator.free(string);
						writer.writeSlice(string);
					}
				},
				.delete => |delete| {
					delete.inv.write(&writer);
					writer.writeInt(u16, delete.amount);
				},
				.useDurability => |durability| {
					durability.inv.write(&writer);
					writer.writeInt(u32, durability.durability);
				},
				.health => |health| {
					writer.writeInt(u32, @bitCast(health.health));
				},
				.kill => {},
				.energy => |energy| {
					writer.writeInt(u32, @bitCast(energy.energy));
				},
			}
			return writer.data.toOwnedSlice();
		}
	};

	payload: Payload,
	baseOperations: main.ListUnmanaged(BaseOperation) = .{},
	syncOperations: main.ListUnmanaged(SyncOperation) = .{},

	fn serializePayload(self: *Command, allocator: NeverFailingAllocator) []const u8 {
		var writer = utils.BinaryWriter.init(allocator, main.network.networkEndian);
		defer writer.deinit();
		switch(self.payload) {
			inline else => |payload| {
				payload.serialize(&writer);
			},
		}
		return writer.data.toOwnedSlice();
	}

	fn do(self: *Command, allocator: NeverFailingAllocator, side: Side, user: ?*main.server.User, gamemode: main.game.Gamemode) error{serverFailure}!void { // MARK: do()
		std.debug.assert(self.baseOperations.items.len == 0); // do called twice without cleaning up
		switch(self.payload) {
			inline else => |payload| {
				try payload.run(allocator, self, side, user, gamemode);
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
				.useDurability => |info| {
					std.debug.assert(info.source.ref().item == null or std.meta.eql(info.source.ref().item, info.item));
					info.source.ref().item = info.item;
					info.item.tool.durability = info.previousDurability;
					info.source.inv.update();
				},
				.addHealth => |info| {
					main.game.Player.super.health = info.previous;
				},
				.addEnergy => |info| {
					main.game.Player.super.energy = info.previous;
				},
			}
		}
	}

	fn finalize(self: Command, allocator: NeverFailingAllocator, side: Side, reader: *utils.BinaryReader) !void {
		for(self.baseOperations.items) |step| {
			switch(step) {
				.move, .swap, .create, .addHealth, .addEnergy => {},
				.delete => |info| {
					info.item.?.deinit();
				},
				.useDurability => |info| {
					if(info.previousDurability <= info.durability) {
						info.item.deinit();
					}
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
					try payload.finalize(side, reader);
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
			self.syncOperations.append(allocator, .{.create = .{
				.inv = inv,
				.amount = amount,
				.item = if(inv.ref().amount == 0) item else null,
			}});
		}
		std.debug.assert(inv.ref().item == null or std.meta.eql(inv.ref().item.?, item.?));
		inv.ref().item = item.?;
		inv.ref().amount += amount;
		std.debug.assert(inv.ref().amount <= item.?.stackSize());
	}

	fn executeRemoveOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, amount: u16) void {
		if(amount == 0) return;
		if(side == .server) {
			self.syncOperations.append(allocator, .{.delete = .{
				.inv = inv,
				.amount = amount,
			}});
		}
		inv.ref().amount -= amount;
		if(inv.ref().amount == 0) {
			inv.ref().item = null;
		}
	}

	fn executeDurabilityUseOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, durability: u31) void {
		if(durability == 0) return;
		if(side == .server) {
			self.syncOperations.append(allocator, .{.useDurability = .{
				.inv = inv,
				.durability = durability,
			}});
		}
		inv.ref().item.?.tool.durability -|= durability;
		if(inv.ref().item.?.tool.durability == 0) {
			inv.ref().item = null;
			inv.ref().amount = 0;
		}
	}

	fn executeBaseOperation(self: *Command, allocator: NeverFailingAllocator, _op: BaseOperation, side: Side) void { // MARK: executeBaseOperation()
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
			.useDurability => |*info| {
				info.item = info.source.ref().item.?;
				info.previousDurability = info.item.tool.durability;
				self.executeDurabilityUseOperation(allocator, side, info.source, info.durability);
				info.source.inv.update();
			},
			.addHealth => |*info| {
				if(side == .server) {
					info.previous = info.target.?.player.health;

					info.target.?.player.health = std.math.clamp(info.target.?.player.health + info.health, 0, info.target.?.player.maxHealth);

					if(info.target.?.player.health <= 0) {
						info.target.?.player.health = info.target.?.player.maxHealth;
						info.cause.sendMessage(info.target.?.name);

						self.syncOperations.append(allocator, .{.kill = .{
							.target = info.target.?,
						}});
					} else {
						self.syncOperations.append(allocator, .{.health = .{
							.target = info.target.?,
							.health = info.health,
						}});
					}
				} else {
					info.previous = main.game.Player.super.health;
					main.game.Player.super.health = std.math.clamp(main.game.Player.super.health + info.health, 0, main.game.Player.super.maxHealth);
				}
			},
			.addEnergy => |*info| {
				if(side == .server) {
					info.previous = info.target.?.player.energy;

					info.target.?.player.energy = std.math.clamp(info.target.?.player.energy + info.energy, 0, info.target.?.player.maxEnergy);
					self.syncOperations.append(allocator, .{.energy = .{
						.target = info.target.?,
						.energy = info.energy,
					}});
				} else {
					info.previous = main.game.Player.super.energy;
					main.game.Player.super.energy = std.math.clamp(main.game.Player.super.energy + info.energy, 0, main.game.Player.super.maxEnergy);
				}
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

	fn tryCraftingTo(self: *Command, allocator: NeverFailingAllocator, dest: InventoryAndSlot, source: InventoryAndSlot, side: Side, user: ?*main.server.User) void { // MARK: tryCraftingTo()
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

	const Open = struct { // MARK: Open
		inv: Inventory,
		source: Source,

		fn run(_: Open, _: NeverFailingAllocator, _: *Command, _: Side, _: ?*main.server.User, _: Gamemode) error{serverFailure}!void {}

		fn finalize(self: Open, side: Side, reader: *utils.BinaryReader) !void {
			if(side != .client) return;
			if(reader.remaining.len != 0) {
				const serverId = try reader.readInt(u32);
				Sync.ClientSide.mapServerId(serverId, self.inv);
			}
		}

		fn confirmationData(self: Open, allocator: NeverFailingAllocator) []const u8 {
			var writer = utils.BinaryWriter.initCapacity(allocator, main.network.networkEndian, 4);
			writer.writeInt(u32, self.inv.id);
			return writer.data.toOwnedSlice();
		}

		fn serialize(self: Open, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.inv.id);
			writer.writeInt(usize, self.inv._items.len);
			writer.writeEnum(TypeEnum, self.inv.type);
			writer.writeEnum(SourceType, self.source);
			switch(self.source) {
				.playerInventory, .hand => |val| {
					writer.writeInt(u32, val);
				},
				.recipe => |val| {
					writer.writeInt(u16, val.resultAmount);
					writer.writeWithDelimiter(val.resultItem.id, 0);
					for(0..val.sourceItems.len) |i| {
						writer.writeInt(u16, val.sourceAmounts[i]);
						writer.writeWithDelimiter(val.sourceItems[i].id, 0);
					}
				},
				.sharedTestingInventory, .other => {},
				.alreadyFreed => unreachable,
			}
			switch(self.inv.type) {
				.normal, .creative, .crafting => {},
				.workbench => {
					writer.writeSlice(self.inv.type.workbench.id);
				},
			}
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !Open {
			if(side != .server or user == null) return error.Invalid;
			const id = try reader.readInt(u32);
			const len = try reader.readInt(u64);
			const typeEnum = try reader.readEnum(TypeEnum);
			const sourceType = try reader.readEnum(SourceType);
			const source: Source = switch(sourceType) {
				.playerInventory => .{.playerInventory = try reader.readInt(u32)},
				.sharedTestingInventory => .{.sharedTestingInventory = {}},
				.hand => .{.hand = try reader.readInt(u32)},
				.recipe => .{
					.recipe = blk: {
						var itemList = main.List(struct {amount: u16, item: *const main.items.BaseItem}).initCapacity(main.stackAllocator, len);
						defer itemList.deinit();
						while(reader.remaining.len >= 2) {
							const resultAmount = try reader.readInt(u16);
							const itemId = try reader.readUntilDelimiter(0);
							const resultItem = main.items.getByID(itemId) orelse return error.Invalid;
							itemList.append(.{.amount = resultAmount, .item = resultItem});
						}
						if(itemList.items.len != len) return error.Invalid;
						// Find the recipe in our list:
						outer: for(main.items.recipes()) |*recipe| {
							if(recipe.resultAmount == itemList.items[0].amount and recipe.resultItem == itemList.items[0].item and recipe.sourceItems.len == itemList.items.len - 1) {
								for(itemList.items[1..], 0..) |item, i| {
									if(item.amount != recipe.sourceAmounts[i] or item.item != recipe.sourceItems[i]) continue :outer;
								}
								break :blk recipe;
							}
						}
						return error.Invalid;
					},
				},
				.other => .{.other = {}},
				.alreadyFreed => unreachable,
			};
			const typ: Type = switch(typeEnum) {
				inline .normal, .creative, .crafting => |tag| tag,
				.workbench => .{.workbench = main.items.getToolTypeByID(reader.remaining) orelse return error.Invalid},
			};
			Sync.ServerSide.createInventory(user.?, id, len, typ, source);
			return .{
				.inv = Sync.ServerSide.getInventory(user.?, id) orelse return error.Invalid,
				.source = source,
			};
		}
	};

	const Close = struct { // MARK: Close
		inv: Inventory,
		allocator: NeverFailingAllocator,

		fn run(_: Close, _: NeverFailingAllocator, _: *Command, _: Side, _: ?*main.server.User, _: Gamemode) error{serverFailure}!void {}

		fn finalize(self: Close, side: Side, reader: *utils.BinaryReader) !void {
			if(side != .client) return;
			self.inv._deinit(self.allocator, .client);
			if(reader.remaining.len != 0) {
				const serverId = try reader.readInt(u32);
				Sync.ClientSide.unmapServerId(serverId, self.inv.id);
			}
		}

		fn serialize(self: Close, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.inv.id);
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !Close {
			if(side != .server or user == null) return error.Invalid;
			const id = try reader.readInt(u32);
			try Sync.ServerSide.closeInventory(user.?, id);
			return undefined;
		}
	};

	const DepositOrSwap = struct { // MARK: DepositOrSwap
		dest: InventoryAndSlot,
		source: InventoryAndSlot,

		fn run(self: DepositOrSwap, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User, gamemode: Gamemode) error{serverFailure}!void {
			std.debug.assert(self.source.inv.type == .normal);
			if(self.dest.inv.type == .creative) {
				try FillFromCreative.run(.{.dest = self.source, .item = self.dest.ref().item}, allocator, cmd, side, user, gamemode);
				return;
			}
			if(self.dest.inv.type == .crafting) {
				cmd.tryCraftingTo(allocator, self.source, self.dest, side, user);
				return;
			}
			if(self.dest.inv.type == .workbench and self.dest.slot != 25 and self.dest.inv.type.workbench.slotInfos[self.dest.slot].disabled) return;
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

		fn serialize(self: DepositOrSwap, writer: *utils.BinaryWriter) void {
			self.dest.write(writer);
			self.source.write(writer);
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !DepositOrSwap {
			return .{
				.dest = try InventoryAndSlot.read(reader, side, user),
				.source = try InventoryAndSlot.read(reader, side, user),
			};
		}
	};

	const Deposit = struct { // MARK: Deposit
		dest: InventoryAndSlot,
		source: InventoryAndSlot,
		amount: u16,

		fn run(self: Deposit, allocator: NeverFailingAllocator, cmd: *Command, side: Side, _: ?*main.server.User, _: Gamemode) error{serverFailure}!void {
			std.debug.assert(self.source.inv.type == .normal);
			if(self.dest.inv.type == .creative) return;
			if(self.dest.inv.type == .crafting) return;
			if(self.dest.inv.type == .workbench and (self.dest.slot == 25 or self.dest.inv.type.workbench.slotInfos[self.dest.slot].disabled)) return;
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

		fn serialize(self: Deposit, writer: *utils.BinaryWriter) void {
			self.dest.write(writer);
			self.source.write(writer);
			writer.writeInt(u16, self.amount);
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !Deposit {
			return .{
				.dest = try InventoryAndSlot.read(reader, side, user),
				.source = try InventoryAndSlot.read(reader, side, user),
				.amount = try reader.readInt(u16),
			};
		}
	};

	const TakeHalf = struct { // MARK: TakeHalf
		dest: InventoryAndSlot,
		source: InventoryAndSlot,

		fn run(self: TakeHalf, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User, gamemode: Gamemode) error{serverFailure}!void {
			std.debug.assert(self.dest.inv.type == .normal);
			if(self.source.inv.type == .creative) {
				if(self.dest.ref().item == null) {
					const item = self.source.ref().item;
					try FillFromCreative.run(.{.dest = self.dest, .item = item}, allocator, cmd, side, user, gamemode);
				}
				return;
			}
			if(self.source.inv.type == .crafting) {
				cmd.tryCraftingTo(allocator, self.dest, self.source, side, user);
				return;
			}
			if(self.source.inv.type == .workbench and self.source.slot != 25 and self.source.inv.type.workbench.slotInfos[self.source.slot].disabled) return;
			if(self.source.inv.type == .workbench and self.source.slot == 25) {
				if(self.dest.ref().item == null and self.source.ref().item != null) {
					cmd.executeBaseOperation(allocator, .{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = 1,
					}}, side);
					cmd.removeToolCraftingIngredients(allocator, self.source.inv, side);
				}
				return;
			}
			const itemSource = self.source.ref().item orelse return;
			const desiredAmount = (1 + self.source.ref().amount)/2;
			if(self.dest.ref().item) |itemDest| {
				if(std.meta.eql(itemDest, itemSource)) {
					if(self.dest.ref().amount >= itemDest.stackSize()) return;
					const amount = @min(itemDest.stackSize() - self.dest.ref().amount, desiredAmount);
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
					.amount = desiredAmount,
				}}, side);
			}
		}

		fn serialize(self: TakeHalf, writer: *utils.BinaryWriter) void {
			self.dest.write(writer);
			self.source.write(writer);
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !TakeHalf {
			return .{
				.dest = try InventoryAndSlot.read(reader, side, user),
				.source = try InventoryAndSlot.read(reader, side, user),
			};
		}
	};

	const Drop = struct { // MARK: Drop
		source: InventoryAndSlot,
		desiredAmount: u16 = 0xffff,

		fn run(self: Drop, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User, _: Gamemode) error{serverFailure}!void {
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
						main.server.world.?.dropWithCooldown(_items[0], user.?.player.pos, direction, 20, main.server.updatesPerSec*2);
					}
				}
				return;
			}
			if(self.source.inv.type == .workbench and self.source.slot != 25 and self.source.inv.type.workbench.slotInfos[self.source.slot].disabled) return;
			if(self.source.inv.type == .workbench and self.source.slot == 25) {
				cmd.removeToolCraftingIngredients(allocator, self.source.inv, side);
			}
			const amount = @min(self.source.ref().amount, self.desiredAmount);
			if(side == .server) {
				const direction = vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -user.?.player.rot[0]), -user.?.player.rot[2]);
				main.server.world.?.dropWithCooldown(.{.item = self.source.ref().item.?.clone(), .amount = amount}, user.?.player.pos, direction, 20, main.server.updatesPerSec*2);
			}
			cmd.executeBaseOperation(allocator, .{.delete = .{
				.source = self.source,
				.amount = amount,
			}}, side);
		}

		fn serialize(self: Drop, writer: *utils.BinaryWriter) void {
			self.source.write(writer);
			if(self.desiredAmount != 0xffff) {
				writer.writeInt(u16, self.desiredAmount);
			}
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !Drop {
			return .{
				.source = try InventoryAndSlot.read(reader, side, user),
				.desiredAmount = reader.readInt(u16) catch 0xffff,
			};
		}
	};

	const FillFromCreative = struct { // MARK: FillFromCreative
		dest: InventoryAndSlot,
		item: ?Item,
		amount: u16 = 0,

		fn run(self: FillFromCreative, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User, mode: Gamemode) error{serverFailure}!void {
			if(self.dest.inv.type == .workbench and (self.dest.slot == 25 or self.dest.inv.type.workbench.slotInfos[self.dest.slot].disabled)) return;
			if(side == .server and user != null and mode != .creative) return;
			if(side == .client and mode != .creative) return;

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

		fn serialize(self: FillFromCreative, writer: *utils.BinaryWriter) void {
			self.dest.write(writer);
			writer.writeInt(u16, self.amount);
			if(self.item) |item| {
				const zon = ZonElement.initObject(main.stackAllocator);
				defer zon.deinit(main.stackAllocator);
				item.insertIntoZon(main.stackAllocator, zon);
				const string = zon.toStringEfficient(main.stackAllocator, &.{});
				defer main.stackAllocator.free(string);
				writer.writeSlice(string);
			}
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !FillFromCreative {
			const dest = try InventoryAndSlot.read(reader, side, user);
			const amount = try reader.readInt(u16);
			var item: ?Item = null;
			if(reader.remaining.len != 0) {
				const zon = ZonElement.parseFromString(main.stackAllocator, null, reader.remaining);
				defer zon.deinit(main.stackAllocator);
				item = try Item.init(zon);
			}
			return .{
				.dest = dest,
				.item = item,
				.amount = amount,
			};
		}
	};

	const DepositOrDrop = struct { // MARK: DepositOrDrop
		dest: Inventory,
		source: Inventory,

		pub fn run(self: DepositOrDrop, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User, _: Gamemode) error{serverFailure}!void {
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
					main.server.world.?.drop(sourceStack.clone(), user.?.player.pos, direction, 20);
				}
				cmd.executeBaseOperation(allocator, .{.delete = .{
					.source = .{.inv = self.source, .slot = @intCast(sourceSlot)},
					.amount = self.source._items[sourceSlot].amount,
				}}, side);
			}
		}

		fn serialize(self: DepositOrDrop, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.dest.id);
			writer.writeInt(u32, self.source.id);
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !DepositOrDrop {
			const destId = try reader.readInt(u32);
			const sourceId = try reader.readInt(u32);
			return .{
				.dest = Sync.getInventory(destId, side, user) orelse return error.Invalid,
				.source = Sync.getInventory(sourceId, side, user) orelse return error.Invalid,
			};
		}
	};

	const Clear = struct { // MARK: Clear
		inv: Inventory,

		pub fn run(self: Clear, allocator: NeverFailingAllocator, cmd: *Command, side: Side, _: ?*main.server.User, _: Gamemode) error{serverFailure}!void {
			if(self.inv.type == .creative) return;
			if(self.inv.type == .crafting) return;
			var items = self.inv._items;
			if(self.inv.type == .workbench) items = self.inv._items[0..25];
			for(items, 0..) |stack, slot| {
				if(stack.item == null) continue;

				cmd.executeBaseOperation(allocator, .{.delete = .{
					.source = .{.inv = self.inv, .slot = @intCast(slot)},
					.amount = stack.amount,
				}}, side);
			}
		}

		fn serialize(self: Clear, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.inv.id);
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !Clear {
			const invId = try reader.readInt(u32);
			return .{
				.inv = Sync.getInventory(invId, side, user) orelse return error.Invalid,
			};
		}
	};

	const UpdateBlock = struct { // MARK: UpdateBlock
		source: InventoryAndSlot,
		pos: Vec3i,
		oldBlock: Block,
		newBlock: Block,

		fn run(self: UpdateBlock, allocator: NeverFailingAllocator, cmd: *Command, side: Side, user: ?*main.server.User, gamemode: Gamemode) error{serverFailure}!void {
			if(self.source.inv.type != .normal) return;

			const stack = self.source.ref();

			var shouldDropSourceBlockOnSuccess: bool = true;
			const costOfChange = if(gamemode != .creative) self.oldBlock.canBeChangedInto(self.newBlock, stack.*, &shouldDropSourceBlockOnSuccess) else .yes;

			// Check if we can change it:
			if(!switch(costOfChange) {
				.no => false,
				.yes => true,
				.yes_costsDurability => |durability| stack.item != null and stack.item.? == .tool and stack.item.?.tool.durability >= durability,
				.yes_costsItems => |amount| stack.amount >= amount,
				.yes_dropsItems => true,
			}) {
				if(side == .server) {
					// Inform the client of the actual block:
					main.network.Protocols.blockUpdate.send(user.?.conn, self.pos[0], self.pos[1], self.pos[2], main.server.world.?.getBlock(self.pos[0], self.pos[1], self.pos[2]) orelse return);
				}
				return;
			}

			if(side == .server) {
				if(main.server.world.?.cmpxchgBlock(self.pos[0], self.pos[1], self.pos[2], self.oldBlock, self.newBlock)) |actualBlock| {
					// Inform the client of the actual block:
					main.network.Protocols.blockUpdate.send(user.?.conn, self.pos[0], self.pos[1], self.pos[2], actualBlock);
					return error.serverFailure;
				}
			}

			// Apply inventory changes:
			switch(costOfChange) {
				.no => unreachable,
				.yes => {},
				.yes_costsDurability => |durability| {
					cmd.executeBaseOperation(allocator, .{.useDurability = .{
						.source = self.source,
						.durability = durability,
					}}, side);
				},
				.yes_costsItems => |amount| {
					cmd.executeBaseOperation(allocator, .{.delete = .{
						.source = self.source,
						.amount = amount,
					}}, side);
				},
				.yes_dropsItems => |amount| {
					if(side == .server and gamemode != .creative) {
						for(0..amount) |_| {
							for(self.newBlock.blockDrops()) |drop| {
								if(drop.chance == 1 or main.random.nextFloat(&main.seed) < drop.chance) {
									blockDrop(self.pos, drop);
								}
							}
						}
					}
				},
			}

			if(side == .server and gamemode != .creative and self.oldBlock.typ != self.newBlock.typ and shouldDropSourceBlockOnSuccess) {
				for(self.oldBlock.blockDrops()) |drop| {
					if(drop.chance == 1 or main.random.nextFloat(&main.seed) < drop.chance) {
						blockDrop(self.pos, drop);
					}
				}
			}
		}

		fn blockDrop(pos: Vec3i, drop: main.blocks.BlockDrop) void {
			for(drop.items) |itemStack| {
				const dropPos = @as(Vec3d, @floatFromInt(pos)) + @as(Vec3d, @splat(0.5)) + main.random.nextDoubleVectorSigned(3, &main.seed)*@as(Vec3d, @splat(0.5 - main.itemdrop.ItemDropManager.radius));
				const dir = vec.normalize(main.random.nextFloatVectorSigned(3, &main.seed));
				main.server.world.?.drop(itemStack.clone(), dropPos, dir, main.random.nextFloat(&main.seed)*1.5);
			}
		}

		fn serialize(self: UpdateBlock, writer: *utils.BinaryWriter) void {
			self.source.write(writer);
			writer.writeInt(i32, self.pos[0]);
			writer.writeInt(i32, self.pos[1]);
			writer.writeInt(i32, self.pos[2]);
			writer.writeInt(u32, @as(u32, @bitCast(self.oldBlock)));
			writer.writeInt(u32, @as(u32, @bitCast(self.newBlock)));
		}

		fn deserialize(reader: *utils.BinaryReader, side: Side, user: ?*main.server.User) !UpdateBlock {
			return .{
				.source = try InventoryAndSlot.read(reader, side, user),
				.pos = .{
					try reader.readInt(i32),
					try reader.readInt(i32),
					try reader.readInt(i32),
				},
				.oldBlock = @bitCast(try reader.readInt(u32)),
				.newBlock = @bitCast(try reader.readInt(u32)),
			};
		}
	};

	const AddHealth = struct { // MARK: AddHealth
		target: u32,
		health: f32,
		cause: main.game.DamageType,

		pub fn run(self: AddHealth, allocator: NeverFailingAllocator, cmd: *Command, side: Side, _: ?*main.server.User, _: Gamemode) error{serverFailure}!void {
			var target: ?*main.server.User = null;

			if(side == .server) {
				const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
				defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
				for(userList) |user| {
					if(user.id == self.target) {
						target = user;
						break;
					}
				}

				if(target == null) return error.serverFailure;

				if(target.?.gamemode.raw == .creative) return;
			} else {
				if(main.game.Player.gamemode.raw == .creative) return;
			}

			cmd.executeBaseOperation(allocator, .{.addHealth = .{
				.target = target,
				.health = self.health,
				.cause = self.cause,
				.previous = if(side == .server) target.?.player.health else main.game.Player.super.health,
			}}, side);
		}

		fn serialize(self: AddHealth, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.target);
			writer.writeInt(u32, @bitCast(self.health));
			writer.writeEnum(main.game.DamageType, self.cause);
		}

		fn deserialize(reader: *utils.BinaryReader, _: Side, _: ?*main.server.User) !AddHealth {
			return .{
				.target = try reader.readInt(u32),
				.health = @bitCast(try reader.readInt(u32)),
				.cause = try reader.readEnum(main.game.DamageType),
			};
		}
	};
};

const SourceType = enum(u8) {
	alreadyFreed = 0,
	playerInventory = 1,
	sharedTestingInventory = 2,
	hand = 3,
	recipe = 4,
	other = 0xff, // TODO: List every type separately here.
};
const Source = union(SourceType) {
	alreadyFreed: void,
	playerInventory: u32,
	sharedTestingInventory: void,
	hand: u32,
	recipe: *const main.items.Recipe,
	other: void,
};

const Inventory = @This(); // MARK: Inventory

const TypeEnum = enum(u8) {
	normal = 0,
	creative = 1,
	crafting = 2,
	workbench = 3,
};
const Type = union(TypeEnum) {
	normal: void,
	creative: void,
	crafting: void,
	workbench: *const main.items.ToolType,
};
type: Type,
id: u32,
_items: []ItemStack,

pub fn init(allocator: NeverFailingAllocator, _size: usize, _type: Type, source: Source) Inventory {
	const self = _init(allocator, _size, _type, .client);
	Sync.ClientSide.executeCommand(.{.open = .{.inv = self, .source = source}});
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
	if(main.game.world.?.connected) {
		Sync.ClientSide.executeCommand(.{.close = .{.inv = self, .allocator = allocator}});
	} else {
		Sync.ClientSide.mutex.lock();
		defer Sync.ClientSide.mutex.unlock();
		self._deinit(allocator, .client);
	}
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
		var hasAllMandatory: bool = true;

		for(0..25) |i| {
			if(self._items[i].item != null and self._items[i].item.? == .baseItem) {
				availableItems[i] = self._items[i].item.?.baseItem;
			} else {
				if(!self.type.workbench.slotInfos[i].optional and !self.type.workbench.slotInfos[i].disabled)
					hasAllMandatory = false;
				availableItems[i] = null;
			}
		}
		if(hasAllMandatory) {
			var hash = std.hash.Crc32.init();
			for(availableItems) |item| {
				if(item != null) {
					hash.update(item.?.id);
				} else {
					hash.update("none");
				}
			}
			self._items[self._items.len - 1].item = Item{.tool = Tool.initFromCraftingGrid(availableItems, hash.final(), self.type.workbench)};
			self._items[self._items.len - 1].amount = 1;
		}
	}
}

pub fn depositOrSwap(dest: Inventory, destSlot: u32, carried: Inventory) void {
	Sync.ClientSide.executeCommand(.{.depositOrSwap = .{.dest = .{.inv = dest, .slot = destSlot}, .source = .{.inv = carried, .slot = 0}}});
}

pub fn deposit(dest: Inventory, destSlot: u32, carried: Inventory, amount: u16) void {
	Sync.ClientSide.executeCommand(.{.deposit = .{.dest = .{.inv = dest, .slot = destSlot}, .source = .{.inv = carried, .slot = 0}, .amount = amount}});
}

pub fn takeHalf(source: Inventory, sourceSlot: u32, carried: Inventory) void {
	Sync.ClientSide.executeCommand(.{.takeHalf = .{.dest = .{.inv = carried, .slot = 0}, .source = .{.inv = source, .slot = sourceSlot}}});
}

pub fn distribute(carried: Inventory, destinationInventories: []const Inventory, destinationSlots: []const u32) void {
	const amount = carried._items[0].amount/destinationInventories.len;
	if(amount == 0) return;
	for(0..destinationInventories.len) |i| {
		destinationInventories[i].deposit(destinationSlots[i], carried, @intCast(amount));
	}
}

pub fn depositOrDrop(dest: Inventory, source: Inventory) void {
	Sync.ClientSide.executeCommand(.{.depositOrDrop = .{.dest = dest, .source = source}});
}

pub fn dropStack(source: Inventory, sourceSlot: u32) void {
	Sync.ClientSide.executeCommand(.{.drop = .{.source = .{.inv = source, .slot = sourceSlot}}});
}

pub fn dropOne(source: Inventory, sourceSlot: u32) void {
	Sync.ClientSide.executeCommand(.{.drop = .{.source = .{.inv = source, .slot = sourceSlot}, .desiredAmount = 1}});
}

pub fn fillFromCreative(dest: Inventory, destSlot: u32, item: ?Item) void {
	Sync.ClientSide.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = dest, .slot = destSlot}, .item = item}});
}

pub fn fillAmountFromCreative(dest: Inventory, destSlot: u32, item: ?Item, amount: u16) void {
	Sync.ClientSide.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = dest, .slot = destSlot}, .item = item, .amount = amount}});
}

pub fn placeBlock(self: Inventory, slot: u32) void {
	main.renderer.MeshSelection.placeBlock(self, slot);
}

pub fn breakBlock(self: Inventory, slot: u32, deltaTime: f64) void {
	main.renderer.MeshSelection.breakBlock(self, slot, deltaTime);
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
