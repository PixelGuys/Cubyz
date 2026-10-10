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

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		velocity: Vec3d,
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
	pub fn find(entity: Entity, defaultVel: Vec3d) *Component {
		return (components.get(entity) orelse {
			const velocity = components.add(main.globalAllocator, entity);
			velocity.velocity = defaultVel;
			return velocity;
		});
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
			.velocity = reader.readVec(Vec3d) catch return error.UnreadableComponentData,
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}

	pub fn getVelocity(entity: Entity) ?Vec3d {
		const velocityComponent = components.get(entity) orelse return null;
		return velocityComponent.velocity;
	}
	pub fn setVelocity(entity: Entity, givenVelocity: Vec3d) void {
		const velocityComponent = components.get(entity) orelse return;
		velocityComponent.velocity = givenVelocity;
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		velocity: Vec3d,
		pub fn save(self: *Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeVec(Vec3d, self.velocity);
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
	pub fn find(entity: Entity, defaultVel: Vec3d) *Component {
		return (components.get(entity) orelse {
			const velocity = components.add(main.globalAllocator, entity);
			velocity.velocity = defaultVel;
			return velocity;
		});
	}
	pub fn getVelocity(entity: Entity) ?Vec3d {
		const velocityComponent = components.get(entity) orelse return null;
		return velocityComponent.velocity;
	}
	pub fn setVelocity(entity: Entity, givenVelocity: Vec3d) void {
		const velocityComponent = components.get(entity) orelse return;
		velocityComponent.velocity = givenVelocity;
	}
	pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.velocity = reader.readVec(Vec3d) catch return error.UnreadableComponentData,
		};
	}
	pub fn loadFromValues(entity: Entity, velocity: Vec3d) void {
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.velocity = velocity,
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}
};
