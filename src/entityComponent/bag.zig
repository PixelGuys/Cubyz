const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const blocks = main.blocks;
const chunk_zig = main.chunk;
const ServerChunk = chunk_zig.ServerChunk;
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;

const c = @import("c");

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

const playerBagSizeLimit = 120;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		bag: items.Inventory.BagInventory,
	};
	pub var components: main.utils.SparseSet(Component, main.entity.Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		for (components.dense.items) |bag| bag.bag.deinit();
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		for (components.dense.items) |bag| bag.bag.deinit();
		components.clear();
	}

	pub fn getBag(entityId: u32) ?*items.Inventory.BagInventory {
		return &(components.get(@enumFromInt(entityId)) orelse return null).bag;
	}

	pub fn load(entityId: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const bag = &components.add(main.globalAllocator, @enumFromInt(entityId)).bag;
		bag.* = .init(main.globalAllocator, playerBagSizeLimit);
		bag.fromBytes(reader) catch return error.UnreadableComponentData;
	}
	pub fn unload(entityId: u32) void {
		const bag = components.fetchRemove(@enumFromInt(entityId)) catch return;
		bag.bag.deinit();
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		bag: items.Inventory.BagInventory,
		pub fn save(self: Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk and audience != .playerHimself) return .discard;
			self.bag.toBytes(writer);
			return .save;
		}
	};
	pub var components: main.utils.SparseSet(Component, main.entity.Entity) = .{};

	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		for (components.dense.items) |bag| bag.bag.deinit();
		components.deinit(main.globalAllocator);
	}

	pub fn get(entityId: u32) ?Component {
		return (components.get(@enumFromInt(entityId)) orelse return null).*;
	}
	pub fn getBag(entityId: u32) ?*items.Inventory.BagInventory {
		return &(components.get(@enumFromInt(entityId)) orelse return null).bag;
	}
	pub fn loadFromData(entityId: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const bag = &components.add(main.globalAllocator, @enumFromInt(entityId)).bag;
		bag.* = .init(main.globalAllocator, playerBagSizeLimit);
		bag.fromBytes(reader) catch return error.UnreadableComponentData;
	}
	pub fn loadEmpty(entityId: u32) void {
		const bag = &components.add(main.globalAllocator, @enumFromInt(entityId)).bag;
		bag.* = .init(main.globalAllocator, playerBagSizeLimit);
	}
	pub fn unload(entityId: u32) void {
		const bag = components.fetchRemove(@enumFromInt(entityId)) catch return;
		bag.bag.deinit();
	}
};
