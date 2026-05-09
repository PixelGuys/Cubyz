const std = @import("std");

const main = @import("main");
const BaseItem = main.items.BaseItem;
const Block = main.blocks.Block;
const Item = main.items.Item;
const ItemStack = main.items.ItemStack;
const ProceduralItem = main.items.ProceduralItem;
const utils = main.utils;
const BinaryWriter = utils.BinaryWriter;
const BinaryReader = utils.BinaryReader;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const sync = main.sync;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;
const Neighbor = main.chunk.Neighbor;
const BaseItemIndex = main.items.BaseItemIndex;
const ProceduralItemTypeIndex = main.items.ProceduralItemTypeIndex;

pub const InventoryId = enum(u32) { _ };

pub const client = struct { // MARK: client
	var maxId: InventoryId = @enumFromInt(0);
	var freeIdList: main.List(InventoryId) = undefined;
	var serverToClientMap: std.AutoHashMap(InventoryId, Inventory) = undefined;

	pub fn init() void {
		freeIdList = .init(main.globalAllocator);
		serverToClientMap = .init(main.globalAllocator.allocator);
	}

	pub fn deinit() void {
		std.debug.assert(freeIdList.items.len == @intFromEnum(maxId)); // leak
		freeIdList.deinit();
		serverToClientMap.deinit();
	}

	fn nextId() InventoryId {
		main.sync.client.mutex.lock();
		defer main.sync.client.mutex.unlock();
		if (freeIdList.popOrNull()) |id| {
			return id;
		}
		defer maxId = @enumFromInt(@intFromEnum(maxId) + 1);
		return maxId;
	}

	fn freeId(id: InventoryId) void {
		sync.threadContext.assertCorrectContext(.client);
		main.sync.client.mutex.assertLocked();
		freeIdList.append(id);
	}

	pub fn mapServerId(serverId: InventoryId, inventory: Inventory) void {
		main.sync.client.mutex.assertLocked();
		serverToClientMap.put(serverId, inventory) catch unreachable;
	}

	pub fn unmapServerId(serverId: InventoryId, clientId: InventoryId) void {
		main.sync.client.mutex.assertLocked();
		std.debug.assert(serverToClientMap.fetchRemove(serverId).?.value.id == clientId);
	}

	pub fn unmapServerIdByClientId(clientId: InventoryId) void {
		main.sync.client.mutex.assertLocked();
		const serverId = blk: {
			var it = serverToClientMap.iterator();
			while (it.next()) |entry| {
				if (entry.value_ptr.id == clientId) break :blk entry.key_ptr.*;
			}
			return;
		};
		unmapServerId(serverId, clientId);
	}

	fn getInventory(serverId: InventoryId) ?Inventory {
		main.sync.client.mutex.assertLocked();
		return serverToClientMap.get(serverId);
	}

	fn getInventoryByClientId(clientId: InventoryId) ?Inventory {
		main.sync.client.mutex.assertLocked();
		var it = serverToClientMap.valueIterator();
		while (it.next()) |inv| {
			if (inv.id == clientId) return inv.*;
		}
		return null;
	}
};

pub const server = struct { // MARK: server
	const ServerInventory = struct {
		inv: Inventory,
		users: main.ListUnmanaged(struct { user: *main.server.User, cliendId: InventoryId }),
		source: Source,
		managed: Managed,

		const Managed = enum { internallyManaged, externallyManaged };

		fn init(len: usize, source: Source, managed: Managed, callbacks: Callbacks) ServerInventory {
			inventoryCreationMutex.assertLocked();
			return .{
				.inv = Inventory._init(main.globalAllocator, len, source, .server, callbacks),
				.users = .{},
				.source = source,
				.managed = managed,
			};
		}

		fn deinit(self: *ServerInventory) void {
			inventoryCreationMutex.assertLocked();
			while (self.users.items.len != 0) {
				self.removeUser(self.users.items[0].user, self.users.items[0].cliendId);
			}
			self.users.deinit(main.globalAllocator);
			self.inv._deinit(main.globalAllocator, .server);
			self.inv._items.len = 0;
			self.source = .alreadyFreed;
			self.managed = .internallyManaged;
		}

		fn addUser(self: *ServerInventory, user: *main.server.User, clientId: InventoryId) void {
			sync.threadContext.assertCorrectContext(.server);
			self.users.append(main.globalAllocator, .{.user = user, .cliendId = clientId});
			user.inventoryClientToServerIdMap.put(clientId, self.inv.id) catch unreachable;
			if (self.users.items.len == 1) {
				if (self.inv.callbacks.onFirstOpenCallback) |cb| {
					cb(self.inv.source);
				}
			}
		}

		fn removeUser(self: *ServerInventory, user: *main.server.User, clientId: InventoryId) void {
			sync.threadContext.assertCorrectContext(.server);
			var index: usize = undefined;
			for (self.users.items, 0..) |userData, i| {
				if (userData.user == user) {
					index = i;
					break;
				}
			}
			_ = self.users.swapRemove(index);
			std.debug.assert(user.inventoryClientToServerIdMap.fetchRemove(clientId).?.value == self.inv.id);
			if (self.users.items.len == 0) {
				if (self.inv.callbacks.onLastCloseCallback) |cb| {
					cb(self.inv.source);
				}
				if (self.managed == .internallyManaged) {
					inventoryCreationMutex.lock();
					defer inventoryCreationMutex.unlock();
					self.deinit();
				}
			}
		}
	};

	var inventories: main.utils.VirtualList(ServerInventory, 1 << 24) = undefined;
	var maxId: InventoryId = @enumFromInt(0);
	var freeIdList: main.List(InventoryId) = undefined;
	var inventoryCreationMutex: main.utils.Mutex = .{};

	pub fn init() void {
		inventories = .init();
		freeIdList = .init(main.globalAllocator);
	}

	pub fn deinit() void {
		for (inventories.items()) |inv| {
			if (inv.source != .alreadyFreed) {
				std.log.err("Leaked inventory with source {}", .{inv.source});
			}
		}
		std.debug.assert(freeIdList.items.len == @intFromEnum(maxId)); // leak
		freeIdList.deinit();
		inventories.deinit();
		maxId = @enumFromInt(0);
	}

	pub fn disconnectUser(user: *main.server.User) void {
		sync.threadContext.assertCorrectContext(.server);
		while (true) {
			// Reinitializing the iterator in the loop to allow for removal:
			var iter = user.inventoryClientToServerIdMap.keyIterator();
			const clientId = iter.next() orelse break;
			closeInventory(user, clientId.*) catch unreachable;
		}
	}

	fn nextId() InventoryId {
		inventoryCreationMutex.assertLocked();
		if (freeIdList.popOrNull()) |id| {
			return id;
		}
		defer maxId = @enumFromInt(@intFromEnum(maxId) + 1);
		_ = inventories.addOne();
		return maxId;
	}

	fn freeId(id: InventoryId) void {
		inventoryCreationMutex.assertLocked();
		freeIdList.append(id);
	}

	pub fn createExternallyManagedInventory(len: usize, source: Source, data: *BinaryReader, callbacks: Callbacks) InventoryId {
		inventoryCreationMutex.lock();
		defer inventoryCreationMutex.unlock();
		const inventory = ServerInventory.init(len, source, .externallyManaged, callbacks);
		inventories.items()[@intFromEnum(inventory.inv.id)] = inventory;
		inventory.inv.fromBytes(data);
		return inventory.inv.id;
	}

	pub fn destroyExternallyManagedInventory(invId: InventoryId) void {
		switch (sync.threadContext) {
			.server => {},
			.chunkDeiniting => std.debug.assert(inventories.items()[@intFromEnum(invId)].users.items.len == 0), // There should be no users here, since chunks shouldn't be deinited while players are still interacting with them.
			else => unreachable,
		}
		std.debug.assert(inventories.items()[@intFromEnum(invId)].managed == .externallyManaged);

		inventoryCreationMutex.lock();
		defer inventoryCreationMutex.unlock();
		inventories.items()[@intFromEnum(invId)].deinit();
	}

	pub fn destroyAndDropExternallyManagedInventory(invId: InventoryId, pos: Vec3i) void {
		sync.threadContext.assertCorrectContext(.server);
		std.debug.assert(inventories.items()[@intFromEnum(invId)].managed == .externallyManaged);
		const inv = &inventories.items()[@intFromEnum(invId)];
		for (inv.inv._items) |*itemStack| {
			if (itemStack.amount == 0) continue;
			main.server.world.?.drop(
				itemStack.*,
				@as(Vec3d, @floatFromInt(pos)) + main.random.nextDoubleVector(3, &main.seed),
				main.random.nextFloatVectorSigned(3, &main.seed),
				0.1,
			);
			itemStack.* = .{};
		}
		inventoryCreationMutex.lock();
		defer inventoryCreationMutex.unlock();
		inv.deinit();
	}

	pub fn createInventory(user: *main.server.User, clientId: InventoryId, len: usize, source: Source) !void {
		sync.threadContext.assertCorrectContext(.server);
		var callbacks: Callbacks = .{};
		switch (source) {
			.blockInventory, .playerInventory, .hand => {
				switch (source) {
					.playerInventory, .hand => |id| {
						if (id != user.id) {
							std.log.err("Player {f} tried to access the inventory of another player.", .{user});
							return error.Invalid;
						}
					},
					else => {},
				}
				inventoryCreationMutex.lock();
				defer inventoryCreationMutex.unlock();
				for (inventories.items()) |*inv| {
					if (std.meta.eql(inv.source, source)) {
						inv.addUser(user, clientId);
						return;
					}
				}
				return error.Invalid;
			},
			.workbench => {
				const workbench_close_callback = struct {
					fn callback(callbackSource: Source) void {
						std.debug.assert(callbackSource == .workbench);
						const workbenchInventory = getInventoryFromSource(callbackSource) orelse @panic("Could not find workbench Inventory");
						const playerInventory = server.getInventoryFromSource(.{.playerInventory = callbackSource.workbench.playerId}) orelse @panic("Could not find player Inventory");

						const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
						defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
						for (userList) |callbackUser| {
							if (callbackUser.id == callbackSource.workbench.playerId) {
								sync.server.executeCommand(.{.depositOrDrop = .initWithInventories(&.{playerInventory}, workbenchInventory, callbackUser.player().pos)}, null);
								break;
							}
						}
					}
				};
				callbacks.onLastCloseCallback = &workbench_close_callback.callback;
			},
			.other => {},
			.alreadyFreed => unreachable,
		}

		inventoryCreationMutex.lock();
		const inventory = ServerInventory.init(len, source, .internallyManaged, callbacks);
		inventoryCreationMutex.unlock();

		inventories.items()[@intFromEnum(inventory.inv.id)] = inventory;
		inventories.items()[@intFromEnum(inventory.inv.id)].addUser(user, clientId);

		switch (source) {
			.blockInventory => unreachable, // Should be loaded by the block entity
			.playerInventory, .hand => unreachable, // Should be loaded on player creation
			.other => {},
			.workbench => {},
			.alreadyFreed => unreachable,
		}
	}

	pub fn closeInventory(user: *main.server.User, clientId: InventoryId) !void {
		sync.threadContext.assertCorrectContext(.server);
		const serverId = user.inventoryClientToServerIdMap.get(clientId) orelse return error.InventoryNotFound;
		inventories.items()[@intFromEnum(serverId)].removeUser(user, clientId);
	}

	pub fn getInventory(user: *main.server.User, clientId: InventoryId) ?Inventory {
		sync.threadContext.assertCorrectContext(.server);
		const serverId = user.inventoryClientToServerIdMap.get(clientId) orelse return null;
		return inventories.items()[@intFromEnum(serverId)].inv;
	}

	pub fn getInventoryFromSource(source: Source) ?Inventory {
		sync.threadContext.assertCorrectContext(.server);
		inventoryCreationMutex.lock();
		defer inventoryCreationMutex.unlock();
		for (inventories.items()) |inv| {
			if (std.meta.eql(inv.source, source)) {
				return inv.inv;
			}
		}
		return null;
	}

	pub fn getInventoryFromId(serverId: InventoryId) Inventory {
		sync.threadContext.assertCorrectContext(.server);
		return inventories.items()[@intFromEnum(serverId)].inv;
	}

	pub fn getServerInventory(serverId: InventoryId) ServerInventory {
		sync.threadContext.assertCorrectContext(.server);
		return inventories.items()[@intFromEnum(serverId)];
	}

	pub fn clearPlayerInventory(user: *main.server.User) void {
		sync.threadContext.assertCorrectContext(.server);
		var inventoryIdIterator = user.inventoryClientToServerIdMap.valueIterator();
		while (inventoryIdIterator.next()) |inventoryId| {
			if (inventories.items()[@intFromEnum(inventoryId.*)].source == .playerInventory) {
				sync.server.executeCommand(.{.clear = .{.inv = inventories.items()[@intFromEnum(inventoryId.*)].inv}}, null);
			}
		}
	}

	pub fn tryCollectingToPlayerInventory(user: *main.server.User, itemStack: *ItemStack) void {
		if (itemStack.item == .null) return;
		sync.threadContext.assertCorrectContext(.server);
		var inventoryIdIterator = user.inventoryClientToServerIdMap.valueIterator();
		outer: while (inventoryIdIterator.next()) |inventoryId| {
			if (inventories.items()[@intFromEnum(inventoryId.*)].source == .playerInventory) {
				const inv = inventories.items()[@intFromEnum(inventoryId.*)].inv;
				for (inv._items, 0..) |invStack, slot| {
					if (std.meta.eql(invStack.item, itemStack.item)) {
						const amount = @min(itemStack.item.stackSize() - invStack.amount, itemStack.amount);
						if (amount == 0) continue;
						sync.server.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = inv, .slot = @intCast(slot)}, .item = itemStack.item, .amount = invStack.amount + amount}}, null);
						itemStack.amount -= amount;
						if (itemStack.amount == 0) break :outer;
					}
				}
				for (inv._items, 0..) |invStack, slot| {
					if (invStack.item == .null) {
						sync.server.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = inv, .slot = @intCast(slot)}, .item = itemStack.item, .amount = itemStack.amount}}, null);
						itemStack.amount = 0;
						break :outer;
					}
				}
			}
		}
		if (itemStack.amount == 0) itemStack.item = .null;
	}
};

pub fn getInventory(id: InventoryId, side: sync.Side, user: ?*main.server.User) ?Inventory {
	sync.threadContext.assertCorrectContext(side);
	return switch (side) {
		.client => client.getInventory(id),
		.server => server.getInventory(user.?, id),
	};
}

pub const Callbacks = struct {
	onUpdateCallback: ?*const fn (Source) void = null,
	onFirstOpenCallback: ?*const fn (Source) void = null,
	onLastCloseCallback: ?*const fn (Source) void = null,
};

pub const SourceType = enum(u8) {
	alreadyFreed = 0,
	playerInventory = 1,
	hand = 3,
	blockInventory = 5,
	workbench = 6,
	other = 0xff, // TODO: List every type separately here.
};
pub const Source = union(SourceType) {
	alreadyFreed: void,
	playerInventory: u32,
	hand: u32,
	blockInventory: Vec3i,
	workbench: struct { playerId: u32, proceduralItemIndex: ProceduralItemTypeIndex },
	other: void,
};

pub const ClientInventory = struct { // MARK: ClientInventory
	const ClientType = union(enum) {
		serverShared: void,
		creative: void,
		crafting: *const main.items.Recipe,
		workbenchResult: InventoryId,
	};
	super: Inventory,
	type: ClientType,

	pub fn init(allocator: NeverFailingAllocator, _size: usize, clientType: ClientType, source: Source, callbacks: Callbacks) ClientInventory {
		const self: ClientInventory = .{
			.super = Inventory._init(allocator, _size, source, .client, callbacks),
			.type = clientType,
		};
		if (clientType == .serverShared) {
			sync.client.executeCommand(.{.open = .{.inv = self.super, .source = source}});
		}
		return self;
	}

	pub fn deinit(self: ClientInventory, allocator: NeverFailingAllocator) void {
		if (main.game.world.?.connected) {
			sync.client.executeCommand(.{.close = .{.inv = self.super, .allocator = allocator}});
		} else {
			main.sync.client.mutex.lock();
			defer main.sync.client.mutex.unlock();
			self.super._deinit(allocator, .client);
		}
	}

	pub fn depositOrSwap(dest: ClientInventory, destSlot: u32, carried: ClientInventory) void {
		std.debug.assert(carried.type == .serverShared);
		if (dest.type == .creative) {
			carried.fillFromCreative(0, dest.getItem(destSlot));
			return;
		}
		std.debug.assert(dest.type == .serverShared);
		main.sync.client.executeCommand(.{.depositOrSwap = .{.dest = .{.inv = dest.super, .slot = destSlot}, .source = .{.inv = carried.super, .slot = 0}}});
	}

	pub fn deposit(dest: ClientInventory, destSlot: u32, source: ClientInventory, sourceSlot: u32, amount: u16) void {
		if (source.type == .creative) {
			std.debug.assert(dest.type == .serverShared);
			dest.fillFromCreative(destSlot, source.getItem(sourceSlot));
			return;
		}
		std.debug.assert(source.type == .serverShared);
		main.sync.client.executeCommand(.{.deposit = .{.dest = .{.inv = dest.super, .slot = destSlot}, .source = .{.inv = source.super, .slot = sourceSlot}, .amount = amount}});
	}

	pub fn takeHalf(source: ClientInventory, sourceSlot: u32, carried: ClientInventory) void {
		if (carried.type == .creative) {
			carried.fillFromCreative(0, source.getItem(sourceSlot));
			return;
		}
		std.debug.assert(carried.type == .serverShared);
		main.sync.client.executeCommand(.{.takeHalf = .{.dest = .{.inv = carried.super, .slot = 0}, .source = .{.inv = source.super, .slot = sourceSlot}}});
	}

	pub fn distribute(carried: ClientInventory, destinationInventories: []const ClientInventory, destinationSlots: []const u32) void {
		const amount = carried.getAmount(0)/destinationInventories.len;
		if (amount == 0) return;
		for (0..destinationInventories.len) |i| {
			destinationInventories[i].deposit(destinationSlots[i], carried, 0, @intCast(amount));
		}
	}

	pub fn depositOrDrop(source: ClientInventory, destinations: []const ClientInventory) void {
		for (destinations) |dest| std.debug.assert(dest.type == .serverShared);
		std.debug.assert(source.type != .creative);
		main.sync.client.executeCommand(.{.depositOrDrop = .init(destinations, source.super, undefined)});
	}

	pub fn depositToAny(source: ClientInventory, sourceSlot: u32, destinations: []const ClientInventory, amount: u16) void {
		std.debug.assert(source.type == .serverShared);
		main.sync.client.executeCommand(.{.depositToAny = .init(destinations, .{.inv = source.super, .slot = sourceSlot}, amount)});
	}

	pub fn dropStack(source: ClientInventory, sourceSlot: u32) void {
		if (source.type != .serverShared) return;
		main.sync.client.executeCommand(.{.drop = .{.source = .{.inv = source.super, .slot = sourceSlot}}});
	}

	pub fn dropOne(source: ClientInventory, sourceSlot: u32) void {
		if (source.type != .serverShared) return;
		main.sync.client.executeCommand(.{.drop = .{.source = .{.inv = source.super, .slot = sourceSlot}, .desiredAmount = 1}});
	}

	pub fn fillFromCreative(dest: ClientInventory, destSlot: u32, item: Item) void {
		main.sync.client.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = dest.super, .slot = destSlot}, .item = item}});
	}

	pub fn fillAmountFromCreative(dest: ClientInventory, destSlot: u32, item: Item, amount: u16) void {
		main.sync.client.executeCommand(.{.fillFromCreative = .{.dest = .{.inv = dest.super, .slot = destSlot}, .item = item, .amount = amount}});
	}

	pub fn fillAnyFromCreative(destinations: []const ClientInventory, item: Item, amount: u16) void {
		main.sync.client.executeCommand(.{.fillAnyFromCreative = .init(destinations, item, amount)});
	}

	pub fn craftFrom(source: ClientInventory, destinations: []const ClientInventory, craftingInv: ClientInventory) void {
		std.debug.assert(source.type == .serverShared);
		for (destinations) |inv| std.debug.assert(inv.type == .serverShared);
		std.debug.assert(craftingInv.type == .crafting);

		main.sync.client.executeCommand(.{.craftFrom = .init(destinations, &.{source}, craftingInv.type.crafting)});
	}

	pub fn craftProceduralItem(source: ClientInventory, destinations: []const ClientInventory) void {
		std.debug.assert(source.type == .workbenchResult);
		for (destinations) |inv| std.debug.assert(inv.type == .serverShared);
		const workbenchInv = blk: {
			main.sync.client.mutex.lock();
			defer main.sync.client.mutex.unlock();
			break :blk client.getInventoryByClientId(source.type.workbenchResult);
		} orelse return;

		main.sync.client.executeCommand(.{.craftProceduralItem = .init(destinations, workbenchInv)});
	}

	pub fn placeBlock(self: ClientInventory, slot: u32) void {
		std.debug.assert(self.type == .serverShared);
		main.renderer.MeshSelection.placeBlock(self, slot);
	}

	pub fn breakBlock(self: ClientInventory, slot: u32, deltaTime: f64) void {
		std.debug.assert(self.type == .serverShared);
		main.renderer.MeshSelection.breakBlock(self, slot, deltaTime);
	}

	pub fn size(self: ClientInventory) usize {
		return self.super.size();
	}

	pub fn getItem(self: ClientInventory, slot: usize) Item {
		return self.super.getItem(slot);
	}

	pub fn getStack(self: ClientInventory, slot: usize) ItemStack {
		return self.super.getStack(slot);
	}

	pub fn getAmount(self: ClientInventory, slot: usize) u16 {
		return self.super.getAmount(slot);
	}
};

const Inventory = @This(); // MARK: Inventory

id: InventoryId,
_items: []ItemStack,
source: Source,
callbacks: Callbacks,

fn _init(allocator: NeverFailingAllocator, _size: usize, source: Source, side: sync.Side, callbacks: Callbacks) Inventory {
	const self = Inventory{
		._items = allocator.alloc(ItemStack, _size),
		.id = switch (side) {
			.client => client.nextId(),
			.server => server.nextId(),
		},
		.source = source,
		.callbacks = callbacks,
	};
	for (self._items) |*item| {
		item.* = ItemStack{};
	}
	return self;
}

pub fn _deinit(self: Inventory, allocator: NeverFailingAllocator, side: sync.Side) void {
	switch (side) {
		.client => client.freeId(self.id),
		.server => server.freeId(self.id),
	}
	for (self._items) |*item| {
		item.deinit();
	}
	allocator.free(self._items);
}

pub fn update(self: Inventory) void {
	if (self.callbacks.onUpdateCallback) |cb| cb(self.source);
}

pub fn size(self: Inventory) usize {
	return self._items.len;
}

pub fn getItem(self: Inventory, slot: usize) Item {
	return self._items[slot].item;
}

pub fn getStack(self: Inventory, slot: usize) ItemStack {
	return self._items[slot];
}

pub fn getAmount(self: Inventory, slot: usize) u16 {
	return self._items[slot].amount;
}

pub const CanHoldReturn = union(enum) {
	yes: void,
	remainingAmount: u16,
};

pub fn canHold(self: Inventory, sourceStack: ItemStack) CanHoldReturn {
	if (sourceStack.amount == 0) return .yes;
	if (self.source == .workbench and !sync.Command.canPutIntoWorkbench(sourceStack.item)) return .{.remainingAmount = sourceStack.amount};

	var remainingAmount = sourceStack.amount;
	for (self._items, 0..) |*destStack, destSlot| {
		if (self.source == .workbench and self.source.workbench.proceduralItemIndex.slotInfos()[destSlot].disabled) continue;
		if (std.meta.eql(destStack.item, sourceStack.item) or destStack.item == .null) {
			const amount = @min(sourceStack.item.stackSize() - destStack.amount, remainingAmount);
			remainingAmount -= amount;
			if (remainingAmount == 0) return .yes;
		}
	}
	return .{.remainingAmount = remainingAmount};
}

pub fn toBytes(self: Inventory, writer: *BinaryWriter) void {
	writer.writeVarInt(u32, @intCast(self._items.len));
	for (self._items) |stack| {
		stack.toBytes(writer);
	}
}

pub fn fromBytes(self: Inventory, reader: *BinaryReader) void {
	var remainingCount = reader.readVarInt(u32) catch 0;
	for (self._items) |*stack| {
		if (remainingCount == 0) {
			stack.* = .{};
			continue;
		}
		remainingCount -= 1;
		stack.* = ItemStack.fromBytes(reader) catch |err| {
			std.log.err("Failed to read item stack from bytes: {s}", .{@errorName(err)});
			stack.* = .{};
			continue;
		};
	}
	for (0..remainingCount) |_| {
		var stack = ItemStack.fromBytes(reader) catch continue;
		if (stack.item != .null) {
			std.log.err("Lost {} of {s}", .{stack.amount, stack.item.id().?});
		}
		stack.deinit();
	}
}

pub const InventoryAndSlot = struct {
	inv: Inventory,
	slot: u32,

	pub fn ref(self: InventoryAndSlot) *ItemStack {
		return &self.inv._items[self.slot];
	}

	pub fn write(self: InventoryAndSlot, writer: *BinaryWriter) void {
		writer.writeEnum(InventoryId, self.inv.id);
		writer.writeInt(u32, self.slot);
	}

	pub fn read(reader: *BinaryReader, side: sync.Side, user: ?*main.server.User) !InventoryAndSlot {
		const id = try reader.readEnum(InventoryId);
		const result: InventoryAndSlot = .{
			.inv = Inventory.getInventory(id, side, user) orelse return error.InventoryNotFound,
			.slot = try reader.readInt(u32),
		};
		if (result.slot >= result.inv._items.len) return error.Invalid;
		return result;
	}
};

pub const BagInventory = struct { // MARK: BagInventory
	sizeLimit: u32,
	slots: main.List(ItemStack),

	pub fn init(allocator: NeverFailingAllocator, sizeLimit: u32) BagInventory {
		return .{
			.sizeLimit = sizeLimit,
			.slots = .init(allocator),
		};
	}

	pub fn deinit(self: BagInventory) void {
		for (self.slots.items) |*item| {
			item.deinit();
		}
		self.slots.deinit();
	}

	pub fn fromBytes(self: *BagInventory, reader: *BinaryReader) !void {
		const amount = try reader.readVarInt(u32);
		for (0..amount) |_| {
			self.slots.append(try .fromBytes(reader));
		}
	}

	pub fn toBytes(self: BagInventory, writer: *BinaryWriter) void {
		writer.writeVarInt(u32, @intCast(self.slots.items.len));
		for (self.slots.items) |item| {
			item.toBytes(writer);
		}
	}

	/// returns the remaining amount
	pub fn push(self: *BagInventory, stack_: ItemStack) u16 {
		var stack = stack_;
		if (self.slots.items.len != 0 and std.meta.eql(self.slots.items[self.slots.items.len - 1].item, stack.item)) {
			const amount = @min(stack.amount, stack.item.stackSize() - self.slots.items[self.slots.items.len - 1].amount);
			self.slots.items[self.slots.items.len - 1].amount += amount;
			stack.amount -= amount;
		}
		if (self.slots.items.len >= self.sizeLimit) {
			return stack.amount;
		}
		if (stack.amount != 0) self.slots.append(stack);
		return 0;
	}

	pub fn pop(self: *BagInventory) ItemStack {
		return self.slots.popOrNull() orelse .{};
	}

	pub fn peek(self: BagInventory, offsetFromTop: usize) ItemStack {
		if (offsetFromTop >= self.slots.items.len) return .{};
		return self.slots.items[self.slots.items.len - 1 - offsetFromTop];
	}
};

pub const Inventories = struct { // MARK: Inventories
	inventories: []const Inventory,

	pub fn init(alloctor: NeverFailingAllocator, inventories: []const Inventory) Inventories {
		return .{
			.inventories = alloctor.dupe(Inventory, inventories),
		};
	}

	pub fn initFromClientInventories(alloctor: NeverFailingAllocator, clientInventories: []const Inventory.ClientInventory) Inventories {
		const copy = alloctor.alloc(Inventory, clientInventories.len);
		for (copy, clientInventories) |*d, s| d.* = s.super;
		return .{
			.inventories = copy,
		};
	}

	pub fn fromBytes(allocator: NeverFailingAllocator, reader: *BinaryReader, side: sync.Side, user: ?*main.server.User) !Inventories {
		const inventoryCount = try reader.readVarInt(usize);
		if (inventoryCount == 0) return error.Invalid;
		if (inventoryCount*@sizeOf(InventoryId) >= reader.remaining.len) return error.Invalid;

		const inventories = allocator.alloc(Inventory, inventoryCount);
		errdefer allocator.free(inventories);

		for (inventories) |*inv| {
			const invId = try reader.readEnum(InventoryId);
			inv.* = Inventory.getInventory(invId, side, user) orelse return error.InventoryNotFound;
		}
		return .{
			.inventories = inventories,
		};
	}

	pub fn deinit(self: Inventories, alloctor: NeverFailingAllocator) void {
		alloctor.free(self.inventories);
	}

	pub fn toBytes(self: Inventories, writer: *BinaryWriter) void {
		writer.writeVarInt(usize, self.inventories.len);
		for (self.inventories) |inv| {
			writer.writeEnum(InventoryId, inv.id);
		}
	}

	pub fn canHold(self: Inventories, itemStack: ItemStack) Inventory.CanHoldReturn {
		var remainingAmount = itemStack.amount;
		for (self.inventories) |dest| {
			remainingAmount = switch (dest.canHold(.{.item = itemStack.item, .amount = remainingAmount})) {
				.yes => return .yes,
				.remainingAmount => |amount| amount,
			};
		}
		return .{.remainingAmount = remainingAmount};
	}

	const Provider = union(enum) {
		move: InventoryAndSlot,
		create: Item,
		bag: *BagInventory,

		pub fn getBaseOperation(provider: Provider, dest: InventoryAndSlot, amount: u16) sync.Command.BaseOperation {
			return switch (provider) {
				.move => |slot| .{.move = .{
					.dest = dest,
					.amount = amount,
					.source = slot,
				}},
				.create => |item| .{.create = .{
					.dest = dest,
					.amount = amount,
					.item = item,
				}},
				.bag => |bag| .{.takeFromBag = .{
					.dest = dest,
					.amount = amount,
					.source = bag,
				}},
			};
		}

		pub fn getItem(provider: Provider) Item {
			return switch (provider) {
				.move => |slot| slot.ref().item,
				.create => |item| item,
				.bag => |bag| bag.peek(0).item,
			};
		}
	};

	pub fn putItemsInto(self: Inventories, ctx: sync.Command.Context, itemAmount: u16, provider: Provider) u16 {
		const item = provider.getItem();
		var remainingAmount = itemAmount;
		var selectedEmptySlot: ?u32 = null;
		var selectedEmptyInv: ?Inventory = null;

		outer: for (self.inventories) |dest| {
			if (dest.source == .workbench and !sync.Command.canPutIntoWorkbench(item)) continue;
			var emptySlot: ?u32 = null;
			var hasItem = false;
			for (dest._items, 0..) |*destStack, destSlot| {
				if (dest.source == .workbench and dest.source.workbench.proceduralItemIndex.slotInfos()[destSlot].disabled) continue;
				if (destStack.item == .null and emptySlot == null) {
					emptySlot = @intCast(destSlot);
					if (selectedEmptySlot == null) {
						selectedEmptySlot = emptySlot;
						selectedEmptyInv = dest;
					}
				}
				if (std.meta.eql(destStack.item, item)) {
					hasItem = true;
					const amount = @min(item.stackSize() - destStack.amount, remainingAmount);
					if (amount == 0) continue;
					ctx.execute(provider.getBaseOperation(.{.inv = dest, .slot = @intCast(destSlot)}, amount));
					remainingAmount -= amount;
					if (remainingAmount == 0) break :outer;
				}
			}
			if (emptySlot != null and hasItem) {
				ctx.execute(provider.getBaseOperation(.{.inv = dest, .slot = emptySlot.?}, remainingAmount));
				remainingAmount = 0;
				break :outer;
			}
		}
		if (remainingAmount > 0 and selectedEmptySlot != null) {
			ctx.execute(provider.getBaseOperation(.{.inv = selectedEmptyInv.?, .slot = selectedEmptySlot.?}, remainingAmount));
			remainingAmount = 0;
		}
		return remainingAmount;
	}

	pub fn removeItems(self: Inventories, ctx: sync.Command.Context, itemAmount: u16, baseItem: main.items.BaseItemIndex) void {
		var fullSlot: ?u32 = null;
		var fullInv: ?Inventory = null;
		var remainingAmount: usize = itemAmount;
		for (self.inventories) |source| {
			for (0..source._items.len) |reverseIndex| {
				const i: usize = source._items.len - reverseIndex - 1;
				const otherStack: *ItemStack = &source._items[i];
				if (otherStack.item == .baseItem and baseItem == otherStack.item.baseItem) {
					if (otherStack.amount == otherStack.item.stackSize()) {
						if (fullSlot == null) {
							fullSlot = @intCast(i);
							fullInv = source;
						}
						continue;
					}
					const amount = @min(remainingAmount, otherStack.amount);
					ctx.execute(.{.delete = .{
						.source = .{.inv = source, .slot = @intCast(i)},
						.amount = amount,
					}});
					remainingAmount -= amount;
					if (remainingAmount == 0) return;
				}
			}
		}
		if (remainingAmount > 0 and fullSlot != null) {
			ctx.execute(.{.delete = .{
				.source = .{.inv = fullInv.?, .slot = fullSlot.?},
				.amount = @min(remainingAmount, baseItem.stackSize()),
			}});
		}
	}
};
