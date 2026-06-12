const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const Entity = main.entity.Entity;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");
const Self = @This();

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		entityModel: main.entityModel.EntityModelIndex,
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		components.clear();
	}
	pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0) return error.InvalidComponentVersion;

		const entityModel = reader.readVarInt(u32) catch return error.UnreadableComponentData;

		const ptr = components.get(entity) orelse components.add(main.globalAllocator, entity);
		ptr.* = Component{
			.entityModel = .{.index = entityModel},
		};
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}
	pub fn get(entity: Entity) ?*Component {
		return components.get(entity);
	}
};

// ############################# Server only stuff ################################

pub const server = struct {
	pub const Component = struct {
		entityModel: main.entityModel.EntityModelIndex,
		pub fn save(self: Component, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeVarInt(u32, self.entityModel.index);
			return .save;
		}
	};
	var components: main.utils.SparseSet(Component, Entity) = undefined;
	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn loadFromData(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0) return error.InvalidComponentVersion;
		const entityModel = reader.readVarInt(u32) catch return error.UnreadableComponentData;

		put(entity, Component{
			.entityModel = .{.index = entityModel},
		});
	}
	pub fn unload(entity: Entity) void {
		components.remove(entity) catch {};
	}
	pub fn put(entity: Entity, renderComponent: Component) void {
		const ptr = components.get(entity) orelse components.add(main.globalAllocator, entity);
		ptr.* = renderComponent;
		main.entity.server.transmitChange(Self, entity);
	}
	pub fn get(entity: Entity) ?*const Component {
		return components.get(entity);
	}
};
