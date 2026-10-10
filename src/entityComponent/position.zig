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

pub fn getPosition(entity: Entity, side: main.sync.Side) ?Vec3d {
	return switch (side) {
		.client => client.getPosition(entity),
		.server => server.getPosition(entity),
	};
}
pub fn setPosition(entity: Entity, givenPosition: Vec3d, side: main.sync.Side) void {
	return switch (side) {
		.client => client.setPosition(entity, givenPosition),
		.server => server.setPosition(entity, givenPosition),
	};
}

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		position: Vec3d,
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
	pub fn find(entity: Entity, defaultPos: Vec3d) *Component {
		return (components.get(entity) orelse {
			const position = components.add(main.globalAllocator, entity);
			position.position = defaultPos;
			return position;
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
			.position = reader.readVec(Vec3d) catch return error.UnreadableComponentData,
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}

	fn getPosition(entity: Entity) ?Vec3d {
		const positionComponent = components.get(entity) orelse return null;
		return positionComponent.position;
	}
	fn setPosition(entity: Entity, givenPosition: Vec3d) void {
		const positionComponent = components.get(entity) orelse return;
		positionComponent.position = givenPosition;
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		position: Vec3d,
		pub fn save(self: *Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeVec(Vec3d, self.position);
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
	pub fn find(entity: Entity, defaultPos: Vec3d) *Component {
		return (components.get(entity) orelse {
			const position = components.add(main.globalAllocator, entity);
			position.position = defaultPos;
			return position;
		});
	}

	pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.position = reader.readVec(Vec3d) catch return error.UnreadableComponentData,
		};
	}
	pub fn loadFromValues(entity: Entity, position: Vec3d) void {
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.position = position,
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}

	fn getPosition(entity: Entity) ?Vec3d {
		const positionComponent = components.get(entity) orelse return null;
		return positionComponent.position;
	}
	fn setPosition(entity: Entity, givenPosition: Vec3d) void {
		const positionComponent = components.get(entity) orelse return;
		positionComponent.position = givenPosition;
	}
};
