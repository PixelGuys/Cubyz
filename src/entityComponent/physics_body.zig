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
	correctSideCheck(side);
	return switch (side) {
		.client => client.getPosition(entity),
		.server => server.getPosition(entity),
	};
}
pub fn getPositionPointer(entity: Entity, side: main.sync.Side) ?*Vec3d {
	correctSideCheck(side);
	return switch (side) {
		.client => &(client.get(entity) orelse return null).position,
		.server => &(server.get(entity) orelse return null).position,
	};
}
pub fn setPosition(entity: Entity, givenPosition: Vec3d, side: main.sync.Side) void {
	correctSideCheck(side);
	return switch (side) {
		.client => client.setPosition(entity, givenPosition),
		.server => server.setPosition(entity, givenPosition),
	};
}
pub fn getVelocity(entity: Entity, side: main.sync.Side) ?Vec3d {
	correctSideCheck(side);
	return switch (side) {
		.client => client.getVelocity(entity),
		.server => server.getVelocity(entity),
	};
}
pub fn getVelocityPointer(entity: Entity, side: main.sync.Side) ?*Vec3d {
	correctSideCheck(side);
	return switch (side) {
		.client => &(client.get(entity) orelse return null).velocity,
		.server => &(server.get(entity) orelse return null).velocity,
	};
}
pub fn setVelocity(entity: Entity, givenVelocity: Vec3d, side: main.sync.Side) void {
	correctSideCheck(side);
	return switch (side) {
		.client => client.setVelocity(entity, givenVelocity),
		.server => server.setVelocity(entity, givenVelocity),
	};
}
pub fn getRotation(entity: Entity, side: main.sync.Side) ?Vec3f {
	correctSideCheck(side);
	return switch (side) {
		.client => client.getRotation(entity),
		.server => server.getRotation(entity),
	};
}
pub fn getRotationPointer(entity: Entity, side: main.sync.Side) ?*Vec3f {
	correctSideCheck(side);
	return switch (side) {
		.client => &(client.get(entity) orelse return null).roation,
		.server => &(server.get(entity) orelse return null).roation,
	};
}
pub fn setRotation(entity: Entity, givenRotation: Vec3f, side: main.sync.Side) void {
	correctSideCheck(side);
	return switch (side) {
		.client => client.setRotation(entity, givenRotation),
		.server => server.setRotation(entity, givenRotation),
	};
}

fn correctSideCheck(side: main.sync.Side) void {
	if ((main.sync.threadContext == .client) and (side == .server)) {
		std.log.debug("trying to use a server component on the client side", .{});
		unreachable;
	}
	if ((main.sync.threadContext == .server) and (side == .client)) {
		std.log.debug("trying to use a client component on the server side", .{});
		unreachable;
	}
}


// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		position: Vec3d,
		velocity: Vec3d,
		rotation: Vec3f,
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
			.velocity = reader.readVec(Vec3d) catch return error.UnreadableComponentData,
			.rotation = reader.readVec(Vec3f) catch return error.UnreadableComponentData,
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}

	fn getPosition(entity: Entity) ?Vec3d {
		const component = components.get(entity) orelse return null;
		return component.position;
	}
	fn setPosition(entity: Entity, givenPosition: Vec3d) void {
		const component = components.get(entity) orelse return;
		component.position = givenPosition;
	}
	fn getVelocity(entity: Entity) ?Vec3d {
		const component = components.get(entity) orelse return null;
		return component.velocity;
	}
	fn setVelocity(entity: Entity, givenVelocity: Vec3d) void {
		const component = components.get(entity) orelse return;
		component.velocity = givenVelocity;
	}
	fn getRotation(entity: Entity) ?Vec3f {
		const component = components.get(entity) orelse return null;
		return component.rotation;
	}
	fn setRotation(entity: Entity, givenRotation: Vec3f) void {
		const component = components.get(entity) orelse return;
		component.rotation = givenRotation;
	}
};

// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		position: Vec3d,
		velocity: Vec3d,
		rotation: Vec3f,
		pub fn save(self: *Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeVec(Vec3d, self.position);
			writer.writeVec(Vec3d, self.velocity);
			writer.writeVec(Vec3d, self.rotation);
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
			.velocity = reader.readVec(Vec3d) catch return error.UnreadableComponentData,
			.rotation = reader.readVec(Vec3f) catch return error.UnreadableComponentData,
		};
	}
	pub fn loadFromPosition(entity: Entity, position: Vec3d) void {
		const ptr: *Component = components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.position = position,
			.velocity = .{0, 0, 0},
			.rotation = .{0, 0, 0},
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}

	fn getPosition(entity: Entity) ?Vec3d {
		const component = components.get(entity) orelse return null;
		return component.position;
	}
	fn setPosition(entity: Entity, givenPosition: Vec3d) void {
		const component = components.get(entity) orelse return;
		component.position = givenPosition;
	}
	fn getVelocity(entity: Entity) ?Vec3d {
		const component = components.get(entity) orelse return null;
		return component.velocity;
	}
	fn setVelocity(entity: Entity, givenVelocity: Vec3d) void {
		const component = components.get(entity) orelse return;
		component.velocity = givenVelocity;
	}
	fn getRotation(entity: Entity) ?Vec3f {
		const component = components.get(entity) orelse return null;
		return component.rotation;
	}
	fn setRotation(entity: Entity, givenRotation: Vec3f) void {
		const component = components.get(entity) orelse return;
		component.rotation = givenRotation;
	}
};
