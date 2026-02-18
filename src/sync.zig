const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const Neighbor = main.chunk.Neighbor;
const Gamemode = main.game.Gamemode;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Inventory = main.items.Inventory;
const InventoryId = Inventory.InventoryId;
const InventoryAndSlot = Inventory.InventoryAndSlot;
const Item = main.items.Item;
const ItemStack = main.items.ItemStack;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

pub const Side = enum { client, server };

pub const ClientSide = struct {
	pub var mutex: std.Thread.Mutex = .{};
	var commands: utils.CircularBufferQueue(Command) = undefined;

	pub fn init() void {
		commands = utils.CircularBufferQueue(Command).init(main.globalAllocator, 256);
	}

	pub fn deinit() void {
		reset();
		commands.deinit();
	}

	pub fn reset() void {
		mutex.lock();
		while (commands.popFront()) |cmd| {
			var reader = BinaryReader.init(&.{});
			cmd.finalize(main.globalAllocator, .client, &reader) catch |err| {
				std.log.err("Got error while cleaning remaining inventory commands: {s}", .{@errorName(err)});
			};
		}
		mutex.unlock();
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
		main.network.protocols.inventory.sendCommand(main.game.world.?.conn, cmd.payload, data);
		commands.pushBack(cmd);
	}

	pub fn receiveConfirmation(reader: *BinaryReader) !void {
		mutex.lock();
		defer mutex.unlock();
		try commands.popFront().?.finalize(main.globalAllocator, .client, reader);
	}

	pub fn receiveFailure() void {
		mutex.lock();
		defer mutex.unlock();
		var tempData = main.List(Command).init(main.stackAllocator);
		defer tempData.deinit();
		while (commands.popBack()) |_cmd| {
			var cmd = _cmd;
			cmd.undo();
			tempData.append(cmd);
		}
		if (tempData.popOrNull()) |_cmd| {
			var cmd = _cmd;
			var reader = BinaryReader.init(&.{});
			cmd.finalize(main.globalAllocator, .client, &reader) catch |err| {
				std.log.err("Got error while cleaning rejected inventory command: {s}", .{@errorName(err)});
			};
		}
		while (tempData.popOrNull()) |_cmd| {
			var cmd = _cmd;
			cmd.do(main.globalAllocator, .client, null, main.game.Player.gamemode.raw) catch unreachable;
			commands.pushBack(cmd);
		}
	}

	pub fn receiveSyncOperation(reader: *BinaryReader) !void {
		mutex.lock();
		defer mutex.unlock();
		var tempData = main.List(Command).init(main.stackAllocator);
		defer tempData.deinit();
		while (commands.popBack()) |_cmd| {
			var cmd = _cmd;
			cmd.undo();
			tempData.append(cmd);
		}
		try Command.SyncOperation.executeFromData(reader);
		while (tempData.popOrNull()) |_cmd| {
			var cmd = _cmd;
			cmd.do(main.globalAllocator, .client, null, main.game.Player.gamemode.raw) catch unreachable;
			commands.pushBack(cmd);
		}
	}

	fn setGamemode(gamemode: Gamemode) void {
		mutex.lock();
		defer mutex.unlock();
		main.game.Player.setGamemode(gamemode);
		var tempData = main.List(Command).init(main.stackAllocator);
		defer tempData.deinit();
		while (commands.popBack()) |_cmd| {
			var cmd = _cmd;
			cmd.undo();
			tempData.append(cmd);
		}
		while (tempData.popOrNull()) |_cmd| {
			var cmd = _cmd;
			cmd.do(main.globalAllocator, .client, null, gamemode) catch unreachable;
			commands.pushBack(cmd);
		}
	}
};

pub const ServerSide = struct { // MARK: ServerSide

	pub fn init() void {
		threadContext = .server;
	}

	pub fn deinit() void {
		threadContext.assertCorrectContext(.server);
		threadContext = .other;
	}

	pub fn executeCommand(payload: Command.Payload, source: ?*main.server.User) void {
		var command = Command{
			.payload = payload,
		};
		command.do(main.globalAllocator, .server, source, if (source) |s| s.gamemode.raw else .creative) catch {
			main.network.protocols.inventory.sendFailure(source.?.conn);
			return;
		};
		if (source != null) {
			const confirmationData = command.confirmationData(main.stackAllocator);
			defer main.stackAllocator.free(confirmationData);
			main.network.protocols.inventory.sendConfirmation(source.?.conn, confirmationData);
		}
		for (command.syncOperations.items) |op| {
			const syncData = op.serialize(main.stackAllocator);
			defer main.stackAllocator.free(syncData);

			const users = op.getUsers(main.stackAllocator);
			defer main.stackAllocator.free(users);

			for (users) |user| {
				if (user == source and op.ignoreSource()) continue;
				main.network.protocols.inventory.sendSyncOperation(user.conn, syncData);
			}
		}
		if (source != null and command.payload == .open) { // Send initial items
			for (command.payload.open.inv._items, 0..) |stack, slot| {
				if (stack.item != .null) {
					const syncOp = Command.SyncOperation{.create = .{
						.inv = .{.inv = command.payload.open.inv, .slot = @intCast(slot)},
						.amount = stack.amount,
						.item = stack.item,
					}};
					const syncData = syncOp.serialize(main.stackAllocator);
					defer main.stackAllocator.free(syncData);
					main.network.protocols.inventory.sendSyncOperation(source.?.conn, syncData);
				}
			}
		}
		var reader = BinaryReader.init(&.{});
		command.finalize(main.globalAllocator, .server, &reader) catch |err| {
			std.log.err("Got error while finalizing command on the server side: {s}", .{@errorName(err)});
		};
	}

	pub fn executeUserCommand(source: *main.server.User, reader: *BinaryReader) !void {
		threadContext.assertCorrectContext(.server);
		const typ = try reader.readEnum(Command.PayloadType);
		@setEvalBranchQuota(100000);
		const payload: Command.Payload = switch (typ) {
			inline else => |_typ| @unionInit(Command.Payload, @tagName(_typ), try @FieldType(Command.Payload, @tagName(_typ)).deserialize(reader, .server, source)),
		};
		executeCommand(payload, source);
	}

	pub fn receiveCommand(source: *main.server.User, reader: *BinaryReader) void {
		source.receiveCommand(reader.remaining);
	}

	fn setGamemode(user: *main.server.User, gamemode: Gamemode) void {
		threadContext.assertCorrectContext(.server);
		user.gamemode.store(gamemode, .monotonic);
		main.network.protocols.genericUpdate.sendGamemode(user.conn, gamemode);
	}
};

pub fn addHealth(health: f32, cause: main.game.DamageType, side: Side, userId: u32) void {
	threadContext.assertCorrectContext(side);
	if (side == .client) {
		ClientSide.executeCommand(.{.addHealth = .{.target = userId, .health = health, .cause = cause}});
	} else {
		ServerSide.executeCommand(.{.addHealth = .{.target = userId, .health = health, .cause = cause}}, null);
	}
}

pub fn setGamemode(user: ?*main.server.User, gamemode: Gamemode) void {
	if (user == null) {
		ClientSide.setGamemode(gamemode);
	} else {
		ServerSide.setGamemode(user.?, gamemode);
	}
}
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
		depositToAny = 11,
		craftFrom = 13,
		clear = 8,
		updateBlock = 9,
		addHealth = 10,
		chatCommand = 12,
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
		depositToAny: DepositToAny,
		craftFrom: CraftFrom,
		clear: Clear,
		updateBlock: UpdateBlock,
		addHealth: AddHealth,
		chatCommand: ChatCommand,
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

	pub const BaseOperation = union(BaseOperationType) {
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
			item: Item = undefined,
			amount: u16,
		},
		create: struct {
			dest: InventoryAndSlot,
			item: Item,
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
			item: Item,
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
			spawnPoint: Vec3d,
		},
		energy: struct {
			target: ?*main.server.User,
			energy: f32,
		},

		pub fn executeFromData(reader: *BinaryReader) !void {
			switch (try deserialize(reader)) {
				.create => |create| {
					if (create.item != .null) {
						create.inv.ref().item = create.item;
					} else if (create.inv.ref().item == .null) {
						return error.Invalid;
					}

					if (create.inv.ref().amount +| create.amount > create.inv.ref().item.stackSize()) {
						return error.Invalid;
					}
					create.inv.ref().amount += create.amount;

					create.inv.inv.update();
				},
				.delete => |delete| {
					if (delete.inv.ref().amount < delete.amount) {
						return error.Invalid;
					}
					delete.inv.ref().amount -= delete.amount;
					if (delete.inv.ref().amount == 0) {
						delete.inv.ref().item = .null;
					}

					delete.inv.inv.update();
				},
				.useDurability => |durability| {
					durability.inv.ref().item.tool.durability -|= durability.durability;
					if (durability.inv.ref().item.tool.durability == 0) {
						durability.inv.ref().item = .null;
						durability.inv.ref().amount = 0;
					}

					durability.inv.inv.update();
				},
				.health => |health| {
					main.game.Player.super.health = std.math.clamp(main.game.Player.super.health + health.health, 0, main.game.Player.super.maxHealth);
				},
				.kill => |kill| {
					main.game.Player.kill(kill.spawnPoint);
				},
				.energy => |energy| {
					main.game.Player.super.energy = std.math.clamp(main.game.Player.super.energy + energy.energy, 0, main.game.Player.super.maxEnergy);
				},
			}
		}

		pub fn getUsers(self: SyncOperation, allocator: NeverFailingAllocator) []*main.server.User {
			switch (self) {
				inline .create, .delete, .useDurability => |data| {
					const users = Inventory.ServerSide.getServerInventory(data.inv.inv.id).users.items;
					const result = allocator.alloc(*main.server.User, users.len);
					for (0..users.len) |i| {
						result[i] = users[i].user;
					}
					return result;
				},
				inline .health, .kill, .energy => |data| {
					const out = allocator.alloc(*main.server.User, 1);
					out[0] = data.target.?;
					return out;
				},
			}
		}

		pub fn ignoreSource(self: SyncOperation) bool {
			return switch (self) {
				.create, .delete, .useDurability, .health, .energy => true,
				.kill => false,
			};
		}

		fn deserialize(reader: *BinaryReader) !SyncOperation {
			const typ = try reader.readEnum(SyncOperationType);

			switch (typ) {
				.create => {
					const out: SyncOperation = .{.create = .{
						.inv = try InventoryAndSlot.read(reader, .client, null),
						.amount = try reader.readInt(u16),
						.item = if (reader.remaining.len > 0) try Item.fromBytes(reader) else .null,
					}};
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
						.health = try reader.readFloat(f32),
					}};
				},
				.kill => {
					return .{.kill = .{
						.target = null,
						.spawnPoint = try reader.readVec(Vec3d),
					}};
				},
				.energy => {
					return .{.energy = .{
						.target = null,
						.energy = try reader.readFloat(f32),
					}};
				},
			}
		}

		pub fn serialize(self: SyncOperation, allocator: NeverFailingAllocator) []const u8 {
			var writer = BinaryWriter.initCapacity(allocator, 13);
			writer.writeEnum(SyncOperationType, self);
			switch (self) {
				.create => |create| {
					create.inv.write(&writer);
					writer.writeInt(u16, create.amount);
					if (create.item != .null) {
						create.item.toBytes(&writer);
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
					writer.writeFloat(f32, health.health);
				},
				.kill => |kill| {
					writer.writeVec(Vec3d, kill.spawnPoint);
				},
				.energy => |energy| {
					writer.writeFloat(f32, energy.energy);
				},
			}
			return writer.data.toOwnedSlice();
		}
	};

	payload: Payload,
	baseOperations: main.ListUnmanaged(BaseOperation) = .{},
	syncOperations: main.ListUnmanaged(SyncOperation) = .{},

	fn serializePayload(self: *Command, allocator: NeverFailingAllocator) []const u8 {
		var writer = BinaryWriter.init(allocator);
		defer writer.deinit();
		switch (self.payload) {
			inline else => |payload| {
				payload.serialize(&writer);
			},
		}
		return writer.data.toOwnedSlice();
	}

	fn do(self: *Command, allocator: NeverFailingAllocator, side: Side, user: ?*main.server.User, gamemode: main.game.Gamemode) error{serverFailure}!void { // MARK: do()
		threadContext.assertCorrectContext(side);
		std.debug.assert(self.baseOperations.items.len == 0); // do called twice without cleaning up
		switch (self.payload) {
			inline else => |payload| {
				try payload.run(.{.allocator = allocator, .cmd = self, .side = side, .user = user, .gamemode = gamemode});
			},
		}
	}

	fn undo(self: *Command) void {
		threadContext.assertCorrectContext(.client);
		// Iterating in reverse order!
		while (self.baseOperations.popOrNull()) |step| {
			switch (step) {
				.move => |info| {
					if (info.amount == 0) continue;
					std.debug.assert(std.meta.eql(info.source.ref().item, info.dest.ref().item) or info.source.ref().item == .null);
					info.source.ref().item = info.dest.ref().item;
					info.source.ref().amount += info.amount;
					info.dest.ref().amount -= info.amount;
					if (info.dest.ref().amount == 0) {
						info.dest.ref().item = .null;
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
					std.debug.assert(info.source.ref().item == .null or std.meta.eql(info.source.ref().item, info.item));
					info.source.ref().item = info.item;
					info.source.ref().amount += info.amount;
					info.source.inv.update();
				},
				.create => |info| {
					std.debug.assert(info.dest.ref().amount >= info.amount);
					info.dest.ref().amount -= info.amount;
					if (info.dest.ref().amount == 0) {
						info.dest.ref().item.deinit();
						info.dest.ref().item = .null;
					}
					info.dest.inv.update();
				},
				.useDurability => |info| {
					std.debug.assert(info.source.ref().item == .null or std.meta.eql(info.source.ref().item, info.item));
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

	fn finalize(self: Command, allocator: NeverFailingAllocator, side: Side, reader: *BinaryReader) !void {
		for (self.baseOperations.items) |step| {
			switch (step) {
				.move, .swap, .create, .addHealth, .addEnergy => {},
				.delete => |info| {
					info.item.deinit();
				},
				.useDurability => |info| {
					if (info.previousDurability <= info.durability) {
						info.item.deinit();
					}
				},
			}
		}
		self.baseOperations.deinit(allocator);
		if (side == .server) {
			self.syncOperations.deinit(allocator);
		} else {
			std.debug.assert(self.syncOperations.capacity == 0);
		}

		switch (self.payload) {
			inline else => |payload| {
				if (@hasDecl(@TypeOf(payload), "finalize")) {
					try payload.finalize(side, reader);
				}
			},
		}
	}

	fn confirmationData(self: *Command, allocator: NeverFailingAllocator) []const u8 {
		switch (self.payload) {
			inline else => |payload| {
				if (@hasDecl(@TypeOf(payload), "confirmationData")) {
					return payload.confirmationData(allocator);
				}
			},
		}
		return &.{};
	}

	fn executeAddOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, amount: u16, item: Item) void {
		if (amount == 0) return;
		if (item == .null) return;
		if (side == .server) {
			self.syncOperations.append(allocator, .{.create = .{
				.inv = inv,
				.amount = amount,
				.item = if (inv.ref().amount == 0) item else .null,
			}});
		}
		std.debug.assert(inv.ref().item == .null or std.meta.eql(inv.ref().item, item));
		inv.ref().item = item;
		inv.ref().amount += amount;
		std.debug.assert(inv.ref().amount <= item.stackSize());
	}

	fn executeRemoveOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, amount: u16) void {
		if (amount == 0) return;
		if (side == .server) {
			self.syncOperations.append(allocator, .{.delete = .{
				.inv = inv,
				.amount = amount,
			}});
		}
		inv.ref().amount -= amount;
		if (inv.ref().amount == 0) {
			inv.ref().item = .null;
		}
	}

	fn executeDurabilityUseOperation(self: *Command, allocator: NeverFailingAllocator, side: Side, inv: InventoryAndSlot, durability: u31) void {
		if (durability == 0) return;
		if (side == .server) {
			self.syncOperations.append(allocator, .{.useDurability = .{
				.inv = inv,
				.durability = durability,
			}});
		}
		inv.ref().item.tool.durability -|= durability;
		if (inv.ref().item.tool.durability == 0) {
			inv.ref().item = .null;
			inv.ref().amount = 0;
		}
	}

	fn executeBaseOperation(self: *Command, allocator: NeverFailingAllocator, _op: BaseOperation, side: Side) void { // MARK: executeBaseOperation()
		threadContext.assertCorrectContext(side);
		var op = _op;
		switch (op) {
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
				info.item = info.source.ref().item;
				info.previousDurability = info.item.tool.durability;
				self.executeDurabilityUseOperation(allocator, side, info.source, info.durability);
				info.source.inv.update();
			},
			.addHealth => |*info| {
				if (side == .server) {
					info.previous = info.target.?.player.health;

					info.target.?.player.health = std.math.clamp(info.target.?.player.health + info.health, 0, info.target.?.player.maxHealth);

					if (info.target.?.player.health <= 0) {
						info.target.?.player.health = info.target.?.player.maxHealth;
						info.cause.sendMessage(info.target.?.name);

						self.syncOperations.append(allocator, .{.kill = .{
							.target = info.target.?,
							.spawnPoint = info.target.?.spawnPos,
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
				if (side == .server) {
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
		for (0..25) |i| {
			if (inv._items[i].amount != 0) {
				self.executeBaseOperation(allocator, .{.delete = .{
					.source = .{.inv = inv, .slot = @intCast(i)},
					.amount = 1,
				}}, side);
			}
		}
	}

	fn canPutIntoWorkbench(source: InventoryAndSlot) bool {
		return switch (source.ref().item) {
			.null => true,
			.baseItem => |item| item.material() != null,
			.tool => false,
		};
	}

	pub const Context = struct {
		allocator: NeverFailingAllocator,
		cmd: *Command,
		side: Side,
		user: ?*main.server.User,
		gamemode: Gamemode,

		pub fn execute(self: Context, _op: BaseOperation) void {
			return self.cmd.executeBaseOperation(self.allocator, _op, self.side);
		}
	};

	const Open = struct { // MARK: Open
		inv: Inventory,
		source: Inventory.Source,

		fn run(_: Open, _: Context) error{serverFailure}!void {}

		fn finalize(self: Open, side: Side, reader: *BinaryReader) !void {
			if (side != .client) return;
			if (reader.remaining.len != 0) {
				const serverId = try reader.readEnum(InventoryId);
				Inventory.ClientSide.mapServerId(serverId, self.inv);
			}
		}

		fn confirmationData(self: Open, allocator: NeverFailingAllocator) []const u8 {
			var writer = BinaryWriter.initCapacity(allocator, 4);
			writer.writeEnum(InventoryId, self.inv.id);
			return writer.data.toOwnedSlice();
		}

		fn serialize(self: Open, writer: *BinaryWriter) void {
			writer.writeEnum(InventoryId, self.inv.id);
			writer.writeInt(usize, self.inv._items.len);
			writer.writeEnum(Inventory.TypeEnum, self.inv.type);
			writer.writeEnum(Inventory.SourceType, self.source);
			switch (self.source) {
				.playerInventory, .hand => |val| {
					writer.writeInt(u32, val);
				},
				.blockInventory => |val| {
					writer.writeVec(Vec3i, val);
				},
				.other => {},
				.alreadyFreed => unreachable,
			}
			switch (self.inv.type) {
				.normal => {},
				.workbench => {
					writer.writeSlice(self.inv.type.workbench.id());
				},
			}
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !Open {
			if (side != .server or user == null) return error.Invalid;
			const id = try reader.readEnum(InventoryId);
			const len = try reader.readInt(u64);
			const typeEnum = try reader.readEnum(Inventory.TypeEnum);
			const sourceType = try reader.readEnum(Inventory.SourceType);
			const source: Inventory.Source = switch (sourceType) {
				.playerInventory => .{.playerInventory = try reader.readInt(u32)},
				.hand => .{.hand = try reader.readInt(u32)},
				.blockInventory => .{.blockInventory = try reader.readVec(Vec3i)},
				.other => .{.other = {}},
				.alreadyFreed => return error.Invalid,
			};
			const typ: Inventory.Type = switch (typeEnum) {
				inline .normal => |tag| tag,
				.workbench => .{.workbench = main.items.ToolTypeIndex.fromId(reader.remaining) orelse return error.Invalid},
			};
			try Inventory.ServerSide.createInventory(user.?, id, len, typ, source);
			return .{
				.inv = Inventory.ServerSide.getInventory(user.?, id) orelse return error.InventoryNotFound,
				.source = source,
			};
		}
	};

	const Close = struct { // MARK: Close
		inv: Inventory,
		allocator: NeverFailingAllocator,

		fn run(_: Close, _: Context) error{serverFailure}!void {}

		fn finalize(self: Close, side: Side, reader: *BinaryReader) !void {
			if (side != .client) return;
			self.inv._deinit(self.allocator, .client);
			if (reader.remaining.len != 0) {
				const serverId = try reader.readEnum(InventoryId);
				Inventory.ClientSide.unmapServerId(serverId, self.inv.id);
			}
		}

		fn serialize(self: Close, writer: *BinaryWriter) void {
			writer.writeEnum(InventoryId, self.inv.id);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !Close {
			if (side != .server or user == null) return error.Invalid;
			const id = try reader.readEnum(InventoryId);
			try Inventory.ServerSide.closeInventory(user.?, id);
			return undefined;
		}
	};

	const DepositOrSwap = struct { // MARK: DepositOrSwap
		dest: InventoryAndSlot,
		source: InventoryAndSlot,

		fn run(self: DepositOrSwap, ctx: Context) error{serverFailure}!void {
			std.debug.assert(self.source.inv.type == .normal);
			if (self.dest.inv.type == .workbench and self.dest.slot != 25 and self.dest.inv.type.workbench.slotInfos()[self.dest.slot].disabled) return;
			if (self.dest.inv.type == .workbench and self.dest.slot == 25) {
				if (self.source.ref().item == .null and self.dest.ref().item != .null) {
					ctx.execute(.{.move = .{
						.dest = self.source,
						.source = self.dest,
						.amount = 1,
					}});
					ctx.cmd.removeToolCraftingIngredients(ctx.allocator, self.dest.inv, ctx.side);
				}
				return;
			}
			if (self.dest.inv.type == .workbench and !canPutIntoWorkbench(self.source)) return;

			const itemDest = self.dest.ref().item;
			const itemSource = self.source.ref().item;
			if (itemDest != .null and itemSource != .null) {
				if (std.meta.eql(itemDest, itemSource)) {
					if (self.dest.ref().amount >= itemDest.stackSize()) return;
					const amount = @min(itemDest.stackSize() - self.dest.ref().amount, self.source.ref().amount);
					ctx.execute(.{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = amount,
					}});
					return;
				}
			}
			if (self.source.inv.type == .workbench and !canPutIntoWorkbench(self.dest)) return;
			ctx.execute(.{.swap = .{
				.dest = self.dest,
				.source = self.source,
			}});
		}

		fn serialize(self: DepositOrSwap, writer: *BinaryWriter) void {
			self.dest.write(writer);
			self.source.write(writer);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !DepositOrSwap {
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

		fn run(self: Deposit, ctx: Context) error{serverFailure}!void {
			if (self.source.inv.type != .normal and self.dest.inv.type != .normal) return error.serverFailure;
			if (self.dest.inv.type == .workbench and (self.dest.slot == 25 or self.dest.inv.type.workbench.slotInfos()[self.dest.slot].disabled)) return;
			if (self.dest.inv.type == .workbench and !canPutIntoWorkbench(self.source)) return;
			const itemSource = self.source.ref().item;
			if (itemSource == .null) return;
			const itemDest = self.dest.ref().item;
			if (itemDest != .null) {
				if (std.meta.eql(itemDest, itemSource)) {
					if (self.dest.ref().amount >= itemDest.stackSize()) return;
					const amount = @min(itemDest.stackSize() - self.dest.ref().amount, self.source.ref().amount, self.amount);
					ctx.execute(.{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = amount,
					}});
				}
			} else {
				const amount = @min(self.amount, self.source.ref().amount);
				ctx.execute(.{.move = .{
					.dest = self.dest,
					.source = self.source,
					.amount = amount,
				}});
			}
		}

		fn serialize(self: Deposit, writer: *BinaryWriter) void {
			self.dest.write(writer);
			self.source.write(writer);
			writer.writeInt(u16, self.amount);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !Deposit {
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

		fn run(self: TakeHalf, ctx: Context) error{serverFailure}!void {
			std.debug.assert(self.dest.inv.type == .normal);
			if (self.source.inv.type == .workbench and self.source.slot != 25 and self.source.inv.type.workbench.slotInfos()[self.source.slot].disabled) return;
			if (self.source.inv.type == .workbench and self.source.slot == 25) {
				if (self.dest.ref().item == .null and self.source.ref().item != .null) {
					ctx.execute(.{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = 1,
					}});
					ctx.cmd.removeToolCraftingIngredients(ctx.allocator, self.source.inv, ctx.side);
				}
				return;
			}
			const itemSource = self.source.ref().item;
			if (itemSource == .null) return;
			const desiredAmount = (1 + self.source.ref().amount)/2;
			const itemDest = self.dest.ref().item;
			if (itemDest != .null) {
				if (std.meta.eql(itemDest, itemSource)) {
					if (self.dest.ref().amount >= itemDest.stackSize()) return;
					const amount = @min(itemDest.stackSize() - self.dest.ref().amount, desiredAmount);
					ctx.execute(.{.move = .{
						.dest = self.dest,
						.source = self.source,
						.amount = amount,
					}});
				}
			} else {
				ctx.execute(.{.move = .{
					.dest = self.dest,
					.source = self.source,
					.amount = desiredAmount,
				}});
			}
		}

		fn serialize(self: TakeHalf, writer: *BinaryWriter) void {
			self.dest.write(writer);
			self.source.write(writer);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !TakeHalf {
			return .{
				.dest = try InventoryAndSlot.read(reader, side, user),
				.source = try InventoryAndSlot.read(reader, side, user),
			};
		}
	};

	const Drop = struct { // MARK: Drop
		source: InventoryAndSlot,
		desiredAmount: u16 = 0xffff,

		fn run(self: Drop, ctx: Context) error{serverFailure}!void {
			if (self.source.ref().item == .null) return;
			if (self.source.inv.type == .workbench and self.source.slot != 25 and self.source.inv.type.workbench.slotInfos()[self.source.slot].disabled) return;
			if (self.source.inv.type == .workbench and self.source.slot == 25) {
				ctx.cmd.removeToolCraftingIngredients(ctx.allocator, self.source.inv, ctx.side);
			}
			const amount = @min(self.source.ref().amount, self.desiredAmount);
			if (ctx.side == .server) {
				const direction = vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -ctx.user.?.player.rot[0]), -ctx.user.?.player.rot[2]);
				main.server.world.?.dropWithCooldown(.{.item = self.source.ref().item.clone(), .amount = amount}, ctx.user.?.player.pos, direction, 20, main.server.updatesPerSec*2);
			}
			ctx.execute(.{.delete = .{
				.source = self.source,
				.amount = amount,
			}});
		}

		fn serialize(self: Drop, writer: *BinaryWriter) void {
			self.source.write(writer);
			if (self.desiredAmount != 0xffff) {
				writer.writeInt(u16, self.desiredAmount);
			}
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !Drop {
			return .{
				.source = try InventoryAndSlot.read(reader, side, user),
				.desiredAmount = reader.readInt(u16) catch 0xffff,
			};
		}
	};

	const FillFromCreative = struct { // MARK: FillFromCreative
		dest: InventoryAndSlot,
		item: Item,
		amount: u16 = 0,

		fn run(self: FillFromCreative, ctx: Context) error{serverFailure}!void {
			if (self.dest.inv.type == .workbench and (self.dest.slot == 25 or self.dest.inv.type.workbench.slotInfos()[self.dest.slot].disabled)) return;
			if (ctx.side == .server and ctx.user != null and ctx.gamemode != .creative) return;
			if (ctx.side == .client and ctx.gamemode != .creative) return;

			if (!self.dest.ref().empty()) {
				ctx.execute(.{.delete = .{
					.source = self.dest,
					.amount = self.dest.ref().amount,
				}});
			}
			if (self.item != .null) {
				ctx.execute(.{.create = .{
					.dest = self.dest,
					.item = self.item,
					.amount = if (self.amount == 0) self.item.stackSize() else self.amount,
				}});
			}
		}

		fn serialize(self: FillFromCreative, writer: *BinaryWriter) void {
			self.dest.write(writer);
			writer.writeInt(u16, self.amount);
			if (self.item != .null) {
				const zon = ZonElement.initObject(main.stackAllocator);
				defer zon.deinit(main.stackAllocator);
				self.item.insertIntoZon(main.stackAllocator, zon);
				const string = zon.toStringEfficient(main.stackAllocator, &.{});
				defer main.stackAllocator.free(string);
				writer.writeSlice(string);
			}
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !FillFromCreative {
			const dest = try InventoryAndSlot.read(reader, side, user);
			const amount = try reader.readInt(u16);
			var item: Item = .null;
			if (reader.remaining.len != 0) {
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
		destinations: Inventory.Inventories,
		source: Inventory,
		dropLocation: Vec3d,

		pub fn init(destinations: []const Inventory.ClientInventory, source: Inventory, dropLocation: Vec3d) DepositOrDrop {
			return .{
				.destinations = .initFromClientInventories(main.globalAllocator, destinations),
				.source = source,
				.dropLocation = dropLocation,
			};
		}

		pub fn initWithInventories(destinations: []const Inventory, source: Inventory, dropLocation: Vec3d) DepositOrDrop {
			return .{
				.destinations = .init(main.globalAllocator, destinations),
				.source = source,
				.dropLocation = dropLocation,
			};
		}

		fn finalize(self: DepositOrDrop, _: Side, _: *BinaryReader) !void {
			self.destinations.deinit(main.globalAllocator);
		}

		pub fn run(self: DepositOrDrop, ctx: Context) error{serverFailure}!void {
			for (self.destinations.inventories) |dest| {
				std.debug.assert(dest.type == .normal);
			}
			var sourceItems = self.source._items;
			if (self.source.type == .workbench) sourceItems = self.source._items[0..25];
			for (sourceItems, 0..) |*sourceStack, sourceSlot| {
				if (sourceStack.item == .null) continue;
				const remainingAmount = self.destinations.putItemsInto(ctx, sourceStack.amount, .{.move = .{.inv = self.source, .slot = @intCast(sourceSlot)}});
				if (remainingAmount == 0) continue;
				if (ctx.side == .server) {
					const direction = if (ctx.user) |_user| vec.rotateZ(vec.rotateX(Vec3f{0, 1, 0}, -_user.player.rot[0]), -_user.player.rot[2]) else Vec3f{0, 0, 0};
					main.server.world.?.drop(sourceStack.clone(), self.dropLocation, direction, 20);
				}
				ctx.execute(.{.delete = .{
					.source = .{.inv = self.source, .slot = @intCast(sourceSlot)},
					.amount = self.source._items[sourceSlot].amount,
				}});
			}
		}

		fn serialize(self: DepositOrDrop, writer: *BinaryWriter) void {
			self.destinations.toBytes(writer);
			writer.writeEnum(InventoryId, self.source.id);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !DepositOrDrop {
			const destinations: Inventory.Inventories = try .fromBytes(main.globalAllocator, reader, side, user);
			errdefer destinations.deinit(main.globalAllocator);
			const sourceId = try reader.readEnum(InventoryId);
			return .{
				.destinations = destinations,
				.source = Inventory.getInventory(sourceId, side, user) orelse return error.InventoryNotFound,
				.dropLocation = (user orelse return error.Invalid).player.pos,
			};
		}
	};

	const DepositToAny = struct { // MARK: DepositToAny
		destinations: Inventory.Inventories,
		source: InventoryAndSlot,
		amount: u16,

		pub fn init(destinations: []const Inventory.ClientInventory, source: InventoryAndSlot, amount: u16) DepositToAny {
			return .{
				.destinations = .initFromClientInventories(main.globalAllocator, destinations),
				.source = source,
				.amount = amount,
			};
		}

		fn finalize(self: DepositToAny, _: Side, _: *BinaryReader) !void {
			self.destinations.deinit(main.globalAllocator);
		}

		fn run(self: DepositToAny, ctx: Context) error{serverFailure}!void {
			for (self.destinations.inventories) |dest| {
				if (dest.type != .normal) return;
			}
			const sourceStack = self.source.ref();
			if (sourceStack.item == .null) return;
			if (self.amount > sourceStack.amount) return;

			_ = self.destinations.putItemsInto(ctx, self.amount, .{.move = self.source});
		}

		fn serialize(self: DepositToAny, writer: *BinaryWriter) void {
			self.destinations.toBytes(writer);
			self.source.write(writer);
			writer.writeInt(u16, self.amount);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !DepositToAny {
			const destinations: Inventory.Inventories = try .fromBytes(main.globalAllocator, reader, side, user);
			errdefer destinations.deinit(main.globalAllocator);
			return .{
				.destinations = destinations,
				.source = try InventoryAndSlot.read(reader, side, user),
				.amount = try reader.readInt(u16),
			};
		}
	};

	const CraftFrom = struct { // MARK: CraftFrom
		destinations: Inventory.Inventories,
		sources: Inventory.Inventories,
		recipe: *const main.items.Recipe,

		pub fn init(destinations: []const Inventory.ClientInventory, sources: []const Inventory.ClientInventory, recipe: *const main.items.Recipe) CraftFrom {
			return .{
				.destinations = .initFromClientInventories(main.globalAllocator, destinations),
				.sources = .initFromClientInventories(main.globalAllocator, sources),
				.recipe = recipe,
			};
		}

		fn finalize(self: CraftFrom, _: Side, _: *BinaryReader) !void {
			self.destinations.deinit(main.globalAllocator);
			self.sources.deinit(main.globalAllocator);
		}

		fn run(self: CraftFrom, ctx: Context) error{serverFailure}!void {
			for (self.destinations.inventories) |dest| if (dest.type != .normal) return;
			for (self.sources.inventories) |source| if (source.type != .normal) return;

			if (self.destinations.canHold(.{.item = .{.baseItem = self.recipe.resultItem}, .amount = self.recipe.resultAmount}) != .yes) return;

			// Can we even craft it?
			outer: for (self.recipe.sourceItems) |requiredItem| {
				var amount: usize = 0;
				// There might be duplicate entries:
				for (self.recipe.sourceItems, self.recipe.sourceAmounts) |otherItem, otherAmount| {
					if (requiredItem == otherItem) amount += otherAmount;
				}
				for (self.sources.inventories) |source| {
					for (source._items) |otherStack| {
						if (otherStack.item == .baseItem and requiredItem == otherStack.item.baseItem) {
							amount -|= otherStack.amount;
							if (amount == 0) continue :outer;
						}
					}
				}
				// Not enough ingredients
				if (amount != 0) return;
			}

			for (self.recipe.sourceItems, self.recipe.sourceAmounts) |requiredItem, requiredAmount| {
				self.sources.removeItems(ctx, requiredAmount, requiredItem);
			}

			const remainingAmount = self.destinations.putItemsInto(ctx, self.recipe.resultAmount, .{.create = .{.baseItem = self.recipe.resultItem}});
			std.debug.assert(remainingAmount == 0);
		}

		fn serialize(self: CraftFrom, writer: *BinaryWriter) void {
			self.destinations.toBytes(writer);
			self.sources.toBytes(writer);
			self.recipe.toBytes(writer);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !CraftFrom {
			const destinations = try Inventory.Inventories.fromBytes(main.globalAllocator, reader, side, user);
			errdefer destinations.deinit(main.globalAllocator);
			const sources = try Inventory.Inventories.fromBytes(main.globalAllocator, reader, side, user);
			errdefer sources.deinit(main.globalAllocator);
			const recipe = try main.items.Recipe.fromBytes(reader);
			return .{
				.destinations = destinations,
				.sources = sources,
				.recipe = recipe,
			};
		}
	};

	const Clear = struct { // MARK: Clear
		inv: Inventory,

		pub fn run(self: Clear, ctx: Context) error{serverFailure}!void {
			var items = self.inv._items;
			if (self.inv.type == .workbench) items = self.inv._items[0..25];
			for (items, 0..) |stack, slot| {
				if (stack.item == .null) continue;

				ctx.execute(.{.delete = .{
					.source = .{.inv = self.inv, .slot = @intCast(slot)},
					.amount = stack.amount,
				}});
			}
		}

		fn serialize(self: Clear, writer: *BinaryWriter) void {
			writer.writeEnum(InventoryId, self.inv.id);
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !Clear {
			const invId = try reader.readEnum(InventoryId);
			return .{
				.inv = Inventory.getInventory(invId, side, user) orelse return error.InventoryNotFound,
			};
		}
	};

	const UpdateBlock = struct { // MARK: UpdateBlock
		source: InventoryAndSlot,
		pos: Vec3i,
		dropLocation: BlockDropLocation,
		oldBlock: Block,
		newBlock: Block,

		const half = @as(Vec3f, @splat(0.5));
		const itemHitBoxMargin: f32 = @floatCast(main.itemdrop.ItemDropManager.radius);
		const itemHitBoxMarginVec: Vec3f = @splat(itemHitBoxMargin);

		const BlockDropLocation = struct {
			dir: Neighbor,
			min: Vec3f,
			max: Vec3f,

			pub fn drop(self: BlockDropLocation, pos: Vec3i, newBlock: Block, _drop: main.blocks.BlockDrop) void {
				if (newBlock.collide()) {
					self.dropOutside(pos, _drop);
				} else {
					self.dropInside(pos, _drop);
				}
			}
			fn dropInside(self: BlockDropLocation, pos: Vec3i, _drop: main.blocks.BlockDrop) void {
				for (_drop.items) |itemStack| {
					main.server.world.?.drop(itemStack.clone(), self.insidePos(pos), self.dropDir(), self.dropVelocity());
				}
			}
			fn insidePos(self: BlockDropLocation, _pos: Vec3i) Vec3d {
				const pos: Vec3d = @floatFromInt(_pos);
				return pos + self.randomOffset();
			}
			fn randomOffset(self: BlockDropLocation) Vec3f {
				const max = @min(@as(Vec3f, @splat(1.0)) - itemHitBoxMarginVec, @max(itemHitBoxMarginVec, self.max - itemHitBoxMarginVec));
				const min = @min(max, @max(itemHitBoxMarginVec, self.min + itemHitBoxMarginVec));
				const center = (max + min)*half;
				const width = (max - min)*half;
				return center + width*main.random.nextFloatVectorSigned(3, &main.seed)*half;
			}
			fn dropOutside(self: BlockDropLocation, pos: Vec3i, _drop: main.blocks.BlockDrop) void {
				for (_drop.items) |itemStack| {
					main.server.world.?.drop(itemStack.clone(), self.outsidePos(pos), self.dropDir(), self.dropVelocity());
				}
			}
			fn outsidePos(self: BlockDropLocation, _pos: Vec3i) Vec3d {
				const pos: Vec3d = @floatFromInt(_pos);
				return pos + self.randomOffset()*self.minor() + self.directionOffset()*self.major() + self.direction()*itemHitBoxMarginVec;
			}
			fn directionOffset(self: BlockDropLocation) Vec3d {
				return half + self.direction()*half;
			}
			inline fn direction(self: BlockDropLocation) Vec3d {
				return @floatFromInt(self.dir.relPos());
			}
			inline fn major(self: BlockDropLocation) Vec3d {
				return @floatFromInt(@abs(self.dir.relPos()));
			}
			inline fn minor(self: BlockDropLocation) Vec3d {
				return @floatFromInt(self.dir.orthogonalComponents());
			}
			fn dropDir(self: BlockDropLocation) Vec3f {
				const randomnessVec: Vec3f = main.random.nextFloatVectorSigned(3, &main.seed)*@as(Vec3f, @splat(0.25));
				const directionVec: Vec3f = @as(Vec3f, @floatCast(self.direction())) + randomnessVec;
				const z: f32 = directionVec[2];
				return vec.normalize(Vec3f{
					directionVec[0],
					directionVec[1],
					if (z < -0.5) 0 else if (z < 0.0) (z + 0.5)*4.0 else z + 2.0,
				});
			}
			fn dropVelocity(self: BlockDropLocation) f32 {
				const velocity = 3.5 + main.random.nextFloatSigned(&main.seed)*0.5;
				if (self.direction()[2] < -0.5) return velocity*0.333;
				return velocity;
			}
		};

		fn run(self: UpdateBlock, ctx: Context) error{serverFailure}!void {
			if (self.source.inv.type != .normal) return;

			const stack = self.source.ref();

			var shouldDropSourceBlockOnSuccess: bool = true;
			const costOfChange = if (ctx.gamemode != .creative) self.oldBlock.canBeChangedInto(self.newBlock, stack.*, &shouldDropSourceBlockOnSuccess) else .yes;

			// Check if we can change it:
			if (!switch (costOfChange) {
				.no => false,
				.yes => true,
				.yes_costsDurability => |_| stack.item == .tool,
				.yes_costsItems => |amount| stack.amount >= amount,
			}) {
				if (ctx.side == .server) {
					// Inform the client of the actual block:
					var writer = BinaryWriter.init(main.stackAllocator);
					defer writer.deinit();

					const actualBlock = main.server.world.?.getBlockAndBlockEntityData(self.pos[0], self.pos[1], self.pos[2], &writer) orelse return;
					main.network.protocols.blockUpdate.send(ctx.user.?.conn, &.{.init(self.pos, actualBlock, writer.data.items)});
				}
				return;
			}

			if (ctx.side == .server) {
				if (main.server.world.?.cmpxchgBlock(self.pos[0], self.pos[1], self.pos[2], self.oldBlock, self.newBlock) != null) {
					// Inform the client of the actual block:
					var writer = BinaryWriter.init(main.stackAllocator);
					defer writer.deinit();

					const actualBlock = main.server.world.?.getBlockAndBlockEntityData(self.pos[0], self.pos[1], self.pos[2], &writer) orelse return;
					main.network.protocols.blockUpdate.send(ctx.user.?.conn, &.{.init(self.pos, actualBlock, writer.data.items)});
					return error.serverFailure;
				}
			}

			// Apply inventory changes:
			switch (costOfChange) {
				.no => unreachable,
				.yes => {},
				.yes_costsDurability => |durability| {
					ctx.execute(.{.useDurability = .{
						.source = self.source,
						.durability = durability,
					}});
				},
				.yes_costsItems => |amount| {
					ctx.execute(.{.delete = .{
						.source = self.source,
						.amount = amount,
					}});
				},
			}
			if (ctx.side == .server and ctx.gamemode != .creative and shouldDropSourceBlockOnSuccess) {
				const dropAmount = self.oldBlock.mode().itemDropsOnChange(self.oldBlock, self.newBlock);
				for (0..dropAmount) |_| {
					for (self.oldBlock.blockDrops()) |drop| {
						if (drop.chance == 1 or main.random.nextFloat(&main.seed) < drop.chance) {
							self.dropLocation.drop(self.pos, self.newBlock, drop);
						}
					}
				}
			}
		}

		fn serialize(self: UpdateBlock, writer: *BinaryWriter) void {
			self.source.write(writer);
			writer.writeVec(Vec3i, self.pos);
			writer.writeEnum(Neighbor, self.dropLocation.dir);
			writer.writeVec(Vec3f, self.dropLocation.min);
			writer.writeVec(Vec3f, self.dropLocation.max);
			writer.writeInt(u32, @as(u32, @bitCast(self.oldBlock)));
			writer.writeInt(u32, @as(u32, @bitCast(self.newBlock)));
		}

		fn deserialize(reader: *BinaryReader, side: Side, user: ?*main.server.User) !UpdateBlock {
			return .{
				.source = try InventoryAndSlot.read(reader, side, user),
				.pos = try reader.readVec(Vec3i),
				.dropLocation = .{
					.dir = try reader.readEnum(Neighbor),
					.min = try reader.readVec(Vec3f),
					.max = try reader.readVec(Vec3f),
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

		pub fn run(self: AddHealth, ctx: Context) error{serverFailure}!void {
			var target: ?*main.server.User = null;

			if (ctx.side == .server) {
				const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
				defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
				for (userList) |user| {
					if (user.id == self.target) {
						target = user;
						break;
					}
				}

				if (target == null) return error.serverFailure;

				if (target.?.gamemode.raw == .creative) return;
			} else {
				if (main.game.Player.gamemode.raw == .creative) return;
			}

			ctx.execute(.{.addHealth = .{
				.target = target,
				.health = self.health,
				.cause = self.cause,
				.previous = if (ctx.side == .server) target.?.player.health else main.game.Player.super.health,
			}});
		}

		fn serialize(self: AddHealth, writer: *BinaryWriter) void {
			writer.writeInt(u32, self.target);
			writer.writeInt(u32, @bitCast(self.health));
			writer.writeEnum(main.game.DamageType, self.cause);
		}

		fn deserialize(reader: *BinaryReader, _: Side, user: ?*main.server.User) !AddHealth {
			const result: AddHealth = .{
				.target = try reader.readInt(u32),
				.health = @bitCast(try reader.readInt(u32)),
				.cause = try reader.readEnum(main.game.DamageType),
			};
			if (user.?.id != result.target) return error.Invalid;
			return result;
		}
	};

	const ChatCommand = struct { // MARK: ChatCommand
		message: []const u8,

		fn finalize(self: ChatCommand, _: Side, _: *BinaryReader) !void {
			main.globalAllocator.free(self.message);
		}

		pub fn run(self: ChatCommand, ctx: Context) error{serverFailure}!void {
			if (ctx.side == .server) {
				const user = ctx.user orelse return;
				if (main.server.world.?.settings.allowCheats) {
					std.log.info("User \"{s}\" executed command \"{s}\"", .{user.name, self.message}); // TODO use color \033[0;32m
					main.server.command.execute(self.message, user);
				} else {
					user.sendRawMessage("Commands are not allowed because cheats are disabled");
				}
			}
		}

		fn serialize(self: ChatCommand, writer: *BinaryWriter) void {
			writer.writeVarInt(usize, self.message.len);
			writer.writeSlice(self.message);
		}

		fn deserialize(reader: *BinaryReader, _: Side, _: ?*main.server.User) !ChatCommand {
			const len = try reader.readVarInt(usize);
			return .{
				.message = main.globalAllocator.dupe(u8, try reader.readSlice(len)),
			};
		}
	};
};

pub threadlocal var threadContext: ThreadContext = .other;
pub const ThreadContext = enum { // MARK: ThreadContext
	other,
	server,
	chunkDeiniting,

	pub fn assertCorrectContext(self: ThreadContext, side: Side) void {
		switch (side) {
			.server => {
				std.debug.assert(self == .server);
			},
			.client => {},
		}
	}
};
