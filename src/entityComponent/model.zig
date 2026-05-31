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
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");
const root = @This();

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		entityModel: main.entityModel.EntityModelIndex,
	};
	pub var components: main.utils.SparseSet(Component, main.entity.Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		components.clear();
	}
	pub fn load(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0)
			return error.InvalidComponentVersion;

		const entityModel = reader.readVarInt(u32) catch return error.UnreadableComponentData;

		const ptr = components.get(@enumFromInt(entity)) orelse components.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = Component{
			.entityModel = .{.index = entityModel},
		};
	}
	pub fn unload(entity: u32) void {
		components.remove(@enumFromInt(entity)) catch {};
	}
	pub fn get(entity: u32) ?*Component {
		return components.get(@enumFromInt(entity));
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
	var components: main.utils.SparseSet(Component, main.entity.Entity) = undefined;
	pub fn init() void {
		components = .{};
	}
	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}
	pub fn loadFromData(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0)
			return error.InvalidComponentVersion;
		const entityModel = reader.readVarInt(u32) catch return error.UnreadableComponentData;

		put(entity, Component{
			.entityModel = .{.index = entityModel},
		});
	}
	pub fn unload(entity: u32) void {
		components.remove(@enumFromInt(entity)) catch {};
	}
	pub fn put(entity: u32, renderComponent: Component) void {
		const ptr = components.get(@enumFromInt(entity)) orelse components.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = renderComponent;
		main.entity.server.transmitChange(root, entity);
	}
	pub fn get(entity: u32) ?*const Component {
		return components.get(@enumFromInt(entity));
	}
};
