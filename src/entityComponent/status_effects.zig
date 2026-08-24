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
const AppliedStatusEffects = main.statusEffects.AppliedStatusEffects;

const c = @import("c");

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		statusEffects: AppliedStatusEffects,
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		components.clear();
	}

	pub fn getStatusEffects(entity: Entity) ?*AppliedStatusEffects {
		return &(components.get(entity) orelse return null).statusEffects;
	}

	pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const statusEffects = &components.add(main.globalAllocator, entity).statusEffects;
		statusEffects.* = statusEffects.init(main.globalAllocator);
		statusEffects.fromBytes(reader) catch return error.UnreadableComponentData;
	}
	pub fn unload(entity: Entity) void {
		const statusEffects = components.fetchRemove(entity) catch return;
		statusEffects.statusEffects.deinit();
	}

	pub fn updateStatusEffects(entity: *main.server.Entity, deltaTime: f64) void {
		const statusEffects = &(components.get(main.game.Player.id) orelse return).statusEffects;
		for (statusEffects.statusEffects.items) |status| {
			const foundStatus = main.statusEffects.StatusEffect.fromInt(status.id);
			std.log.err("what? {} {} {}", .{statusEffects.statusEffects.items.len, status, foundStatus.onUpdate()});
			_ = foundStatus.onUpdate().run(.{.entity = entity, .deltaTime = deltaTime});
		}
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		statusEffects: AppliedStatusEffects,
		pub fn save(self: Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk and audience != .playerHimself) return .discard;
			self.statusEffects.toBytes(writer);
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

	pub fn get(entity: Entity) ?Component {
		return (components.get(entity) orelse return null).*;
	}
	pub fn getStatusEffects(entity: Entity) ?*AppliedStatusEffects {
		return &(components.get(entity) orelse return null).statusEffects;
	}
	pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const statusEffects = &components.add(main.globalAllocator, entity).statusEffects;
		statusEffects.* = statusEffects.init(main.globalAllocator);
		statusEffects.fromBytes(reader) catch return error.UnreadableComponentData;
	}
	pub fn loadEmpty(entity: Entity) void {
		const statusEffects = &components.add(main.globalAllocator, entity).statusEffects;
		statusEffects.* = statusEffects.init(main.globalAllocator);
	}
	pub fn unload(entity: Entity) void {
		const statusEffects = components.fetchRemove(entity) catch return;
		statusEffects.statusEffects.deinit();
	}
};
