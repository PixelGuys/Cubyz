const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const c = graphics.c;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

pub var entityComponentID: u32 = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	const RenderComponent = struct {
		entity: u32, // entity
		entityModel: main.entityModel.EntityModelIndex, // model
	};
	pub var renderComponents: main.utils.SparseSet(RenderComponent, main.entity.Entity) = undefined;

	pub fn init() void {
		renderComponents = .{};
	}
	pub fn deinit() void {
		renderComponents.deinit(main.globalAllocator);
	}
	pub fn clear() void {
		renderComponents.deinit(main.globalAllocator);
		renderComponents = .{};
	}
	pub fn load(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = version;
		const entityModel = reader.readInt(u32) catch return;

		const ptr = renderComponents.get(@enumFromInt(entity)) orelse renderComponents.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = RenderComponent{
			.entity = entity,
			.entityModel = main.entityModel.EntityModelIndex{.index = entityModel},
		};
	}
	pub fn unload(entity: u32) void {
		renderComponents.remove(@enumFromInt(entity)) catch {
			std.log.err("entity {} couldn't be unloaded", .{entity});
		};
	}
};

// ############################# Server only stuff ################################

pub const server = struct {
	pub const RenderComponent = struct {
		entity: u32, // entity
		entityModel: main.entityModel.EntityModelIndex, // model
		pub fn save(self: RenderComponent, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeInt(u32, self.entityModel.index);
			return .save;
		}
	};
	var renderComponents: main.utils.SparseSet(RenderComponent, main.entity.Entity) = undefined;
	pub fn init() void {
		renderComponents = .{};
	}
	pub fn deinit() void {
		renderComponents.deinit(main.globalAllocator);
	}
	pub fn loadFromData(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = version;
		const entityModel = reader.readInt(u32) catch return;

		try loadByIndex(entity, main.entityModel.EntityModelIndex{.index = entityModel});
	}
	pub fn loadByID(entity: u32, entityModelID: []const u8) main.entity.EntityComponentLoadError!void {
		std.log.debug("entityType {s}", .{entityModelID});
		try loadByIndex(entity, main.entityModel.getById(entityModelID) orelse main.entityModel.default());
	}
	pub fn loadByIndex(entity: u32, entityModel: main.entityModel.EntityModelIndex) main.entity.EntityComponentLoadError!void {
		const ptr = renderComponents.get(@enumFromInt(entity)) orelse renderComponents.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = RenderComponent{
			.entity = entity,
			.entityModel = entityModel,
		};
	}
	pub fn unload(entity: u32) void {
		renderComponents.remove(@enumFromInt(entity)) catch {
			std.log.err("entity {} couldn't be unloaded", .{entity});
		};
	}
	pub fn put(entity: u32, renderComponent: RenderComponent) void {
		const ptr = renderComponents.get(@enumFromInt(entity)) orelse renderComponents.add(main.globalAllocator, @enumFromInt(entity));
		ptr.* = renderComponent;
	}
	pub fn get(entity: u32) ?*RenderComponent {
		return renderComponents.get(@enumFromInt(entity));
	}
};
  