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
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const EntityModel = main.entityModel.EntityModel;

const c = @import("c");
const Self = @This();

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const Component = struct {
		entityModel: main.entityModel.EntityModelIndex,

		bufferAllocation: graphics.SubAllocation = .{.len = 0, .start = 0},
		nodes: []EntityModel.Node = undefined,
		matrices: []Mat4f = undefined,

		pub fn deinit(self: Component) void {
			main.globalAllocator.free(self.nodes);
			main.globalAllocator.free(self.matrices);

			main.entity.systems.modelRenderer.client.nodeBuffer.free(self.bufferAllocation);
		}
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {}
	pub fn deinit() void {
        // for (components.dense.items) |comp| {
        //     comp.deinit();
        // }
        components.deinit(main.globalAllocator);
    }
    pub fn clear() void {
		// for (components.dense.items) |comp| {
        //     comp.deinit();
        // }
        components.clear();
    }
	pub fn load(entity: Entity, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != 0) return error.InvalidComponentVersion;

		const entityModel = reader.readVarInt(u32) catch return error.UnreadableComponentData;

		var ptr: *Component = undefined;
		if (components.get(entity)) |p| {
			ptr = p;
			ptr.deinit();
		} else {
			ptr =  components.add(main.globalAllocator, entity);
			std.log.debug("ELSEEEEEEEEEE {d} {d}", .{@intFromEnum(entity), components.dense.items.len});
		}
		ptr.* = Component{
			.entityModel = .{.index = entityModel},
		};
		const model = ptr.entityModel.get();

		ptr.nodes = main.globalAllocator.alloc(EntityModel.Node, model.nodeCount);
		@memcpy(ptr.nodes, model.nodes);
		ptr.matrices = main.globalAllocator.alloc(Mat4f, model.nodeCount);
	}
	pub fn unload(entity: Entity) void {
		const ptr = components.fetchRemove(entity) catch return;
		ptr.deinit();
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
