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

pub const ENTITY_COMPONENT_VERSION = 0;
// ############################# Client only stuff ################################
pub const Client = struct {
	const RenderComponent = struct {
		entity: u32, // entity
		entityModel: main.entityModel.EntityModelIndex, // model
		customTexture: ?main.graphics.Texture, // for custom textures. i.e Skins
	};
	pub var renderComponents: std.AutoHashMap(u32, RenderComponent) = undefined;

	pub fn init() void {
		renderComponents = .init(main.globalAllocator.allocator);
	}
	pub fn deinit() void {
		renderComponents.deinit();
	}
	pub fn clear() void {
		renderComponents.deinit();
		renderComponents = .init(main.globalAllocator.allocator);
	}
	pub fn register(id: u32, reader: *utils.BinaryReader, version: u32) void {
		_ = version;
		const entityModel = reader.readInt(u32) catch return;
		const customTexture: ?main.graphics.Texture = null;

		renderComponents.put(id, RenderComponent{
			.entity = id,
			.customTexture = customTexture,
			.entityModel = main.entityModel.EntityModelIndex{.index = entityModel},
		}) catch unreachable;
	}
	pub fn unregister(id: u32) void {
		_ = renderComponents.remove(id);
	}
};

// ############################# Server only stuff ################################

pub const Server = struct {
	pub const RenderComponent = struct {
		entity: u32, // entity
		entityModel: main.entityModel.EntityModelIndex, // model
		customTexturePath: ?[]const u8, // customTexture
		fn deinit(self: RenderComponent) void {
			if (self.customTexturePath) |path| {
				main.globalAllocator.free(path);
			}
		}
		pub fn save(self: RenderComponent, writer: *utils.BinaryWriter) void {
			writer.writeInt(u32, self.entityModel.index);
			if (self.customTexturePath) |texutre| {
				writer.writeSliceWithSize(texutre);
			} else writer.writeSliceWithSize("");
		}
	};
	var renderComponents: std.AutoHashMap(u32, RenderComponent) = undefined;
	pub fn init() void {
		renderComponents = .init(main.globalAllocator.allocator);
	}
	pub fn deinit() void {
		var it = renderComponents.valueIterator();
		while (it.next()) |component| {
			component.deinit();
		}
		renderComponents.deinit();
	}
	pub fn registerFromData(entity: u32, reader: *utils.BinaryReader, version: usize) void {
		_ = version;
		const entityModel = reader.readInt(u32) catch return;
		const customTexturePath = reader.readSliceWithSize() catch return;

		registerByIndex(entity, main.entityModel.EntityModelIndex{.index = entityModel}, if (customTexturePath.len == 0) null else customTexturePath);
	}
	pub fn registerByID(entity: u32, entityModelID: []const u8, customTexturePath: ?[]const u8) void {
		registerByIndex(entity, main.entityModel.getTypeById(entityModelID), customTexturePath);
	}
	pub fn registerByIndex(entity: u32, entityModel: main.entityModel.EntityModelIndex, customTexturePath: ?[]const u8) void {
		if (renderComponents.get(entity)) |old| {
			old.deinit();
		}
		renderComponents.put(entity, RenderComponent{
			.entity = entity,
			.customTexturePath = customTexturePath,
			.entityModel = entityModel,
		}) catch unreachable;
	}
	pub fn unregister(id: u32) void {
		_ = renderComponents.remove(id);
	}
	pub fn put(id: u32, renderComponent: RenderComponent) void {
		if (renderComponents.get(id)) |entry| {
			entry.deinit();
		}
		renderComponents.put(id, renderComponent) catch unreachable;
	}
	pub fn get(id: u32) ?RenderComponent {
		return renderComponents.get(id);
	}
};
