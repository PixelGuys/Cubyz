const std = @import("std");

const main = @import("main");
const utils = main.utils;
const game = main.game;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;
const BinaryWriter = main.utils.BinaryWriter;

const items = main.items;
const ItemStack = items.ItemStack;
const Inventory = items.Inventory;
const random = main.random;

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		accessories: Inventory.ClientInventory,
	};
	pub var components: main.utils.SparseSet(Component, main.entity.Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		for (components.dense.items) |accessories| accessories.accessories.deinit(main.globalAllocator);
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		for (components.dense.items) |accessories| accessories.accessories.deinit(main.globalAllocator);
		components.clear();
	}

	pub fn getAccessories(entityId: u32) ?*Inventory.ClientInventory {
		return &(components.get(@enumFromInt(entityId)) orelse return null).accessories;
	}

	pub fn load(entityId: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const accessories = &components.add(main.globalAllocator, @enumFromInt(entityId)).accessories;
		accessories.* = .init(main.globalAllocator, items.accessory_slots.getTotalSlotCount(), .serverShared, .{.playerAccessories = entityId}, .{});
		accessories.super.fromBytes(reader);
	}

	pub fn unload(entityId: u32) void {
		const accessories = components.fetchRemove(@enumFromInt(entityId)) catch return;
		accessories.accessories.deinit(main.globalAllocator);
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		accessories: Inventory.InventoryId,
		pub fn save(self: Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk and audience != .playerHimself) return .discard;
			self.accessories.toBytes(writer);
			return .save;
		}
	};
	pub var components: main.utils.SparseSet(Component, main.entity.Entity) = .{};

	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		for (components.dense.items) |bag| bag.accessories.deinit();
		components.deinit(main.globalAllocator);
	}

	pub fn get(entityId: u32) ?Component {
		return (components.get(@enumFromInt(entityId)) orelse return null).*;
	}
	pub fn getBag(entityId: u32) ?*Inventory.BagInventory {
		return &(components.get(@enumFromInt(entityId)) orelse return null).accessories;
	}
	pub fn loadFromData(entityId: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const accessories = &components.add(main.globalAllocator, @enumFromInt(entityId)).accessories;
		accessories.* = Inventory.ServerSide.createExternallyManagedInventory(items.accessory_slots.getTotalSlotCount(), .{.playerAccessories = entityId}, reader, .{});
	}
	pub fn loadEmpty(entityId: u32) void {
		const accessories = &components.add(main.globalAllocator, @enumFromInt(entityId)).accessories;
		accessories.* = Inventory.ServerSide.createExternallyManagedInventory(items.accessory_slots.getTotalSlotCount(), .{.playerAccessories = entityId}, utils.BinaryReader.init(.{}), .{});
	}
	pub fn unload(entityId: u32) void {
		const accessories = components.fetchRemove(@enumFromInt(entityId)) catch return;
		accessories.accessories.deinit();
	}
};
