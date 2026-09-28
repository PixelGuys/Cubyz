const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const Entity = main.entity.Entity;
const ServerChunk = chunk.ServerChunk;
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
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;

const c = @import("c");

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

const defaultHealthAmmount = 8;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		health: f32,
		maxHealth: f32,
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		components.clear();
	}

	pub fn get(entity: Entity) ?*Component {
		return (components.get(entity) orelse return null);
	}
	pub fn getHealth(entity: Entity) ?f32 {
		return (components.get(entity) orelse return null).health;
	}
	pub fn getMaxHealth(entity: Entity) ?f32 {
		return (components.get(entity) orelse return null).maxHealth;
	}

	pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		var ptr: *Component = undefined;
		if (components.get(entity)) |p| {
			ptr = p;
		} else {
			ptr = components.add(main.globalAllocator, entity);
		}

		ptr.* = Component{
			.health = reader.readFloat(f32) catch return error.UnreadableComponentData,
			.maxHealth = reader.readFloat(f32) catch return error.UnreadableComponentData,
		};
	}
	pub fn unload(entity: Entity) void {
		_ = entity;
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		health: f32,
		maxHealth: f32,
		pub fn save(self: *Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeFloat(f32, self.health);
			writer.writeFloat(f32, self.maxHealth);
			return .save;
		}
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}

	pub fn get(entity: Entity) ?*Component {
		return (components.get(entity) orelse return null);
	}
	pub fn getHealth(entity: Entity) ?f32 {
		return (components.get(entity) orelse return null).health;
	}
	pub fn getMaxHealth(entity: Entity) ?f32 {
		return (components.get(entity) orelse return null).maxHealth;
	}
	pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.health = reader.readFloat(f32) catch return error.UnreadableComponentData,
			.maxHealth = reader.readFloat(f32) catch return error.UnreadableComponentData,
		};
	}
	pub fn loadFromNumber(entity: Entity, number: f32) void {
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.health = number,
			.maxHealth = number,
		};
	}
	pub fn unload(entity: Entity) void {
		_ = entity;
	}
};
