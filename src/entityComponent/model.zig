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
	pub fn load(id: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = version;
		const entityModel = reader.readInt(u32) catch return;
		const customTexture: ?main.graphics.Texture = null;

		renderComponents.put(id, RenderComponent{
			.entity = id,
			.customTexture = customTexture,
			.entityModel = main.entityModel.EntityModelIndex{.index = entityModel},
		}) catch unreachable;
	}
	pub fn unload(id: u32) void {
		_ = renderComponents.remove(id);
	}
};

// ############################# Server only stuff ################################

pub const server = struct {
	pub const RenderComponent = struct {
		entity: u32, // entity
		entityModel: main.entityModel.EntityModelIndex, // model
		customTexturePath: ?[]const u8, // customTexture
		fn deinit(self: RenderComponent) void {
			if (self.customTexturePath) |path| {
				main.globalAllocator.free(path);
			}
		}
		pub fn save(self: RenderComponent, writer: *utils.BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			_ = audience;
			writer.writeInt(u32, self.entityModel.index);
			if (self.customTexturePath) |texutre| {
				writer.writeSliceWithSize(texutre);
			} else writer.writeSliceWithSize("");
			return .save;
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
	pub fn loadFromData(entity: u32, reader: *utils.BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = version;
		const entityModel = reader.readInt(u32) catch return;
		const customTexturePath = reader.readSliceWithSize() catch return;

		try loadByIndex(entity, main.entityModel.EntityModelIndex{.index = entityModel}, if (customTexturePath.len == 0) null else customTexturePath);
	}
	pub fn loadByID(entity: u32, entityModelID: []const u8, customTexturePath: ?[]const u8) main.entity.EntityComponentLoadError!void {
		try loadByIndex(entity, main.entityModel.getTypeById(entityModelID), customTexturePath);
	}
	pub fn loadByIndex(entity: u32, entityModel: main.entityModel.EntityModelIndex, customTexturePath: ?[]const u8) main.entity.EntityComponentLoadError!void {
		if (renderComponents.get(entity)) |old| {
			old.deinit();
		}
		renderComponents.put(entity, RenderComponent{
			.entity = entity,
			.customTexturePath = customTexturePath,
			.entityModel = entityModel,
		}) catch return main.entity.EntityComponentLoadError.Memory;
	}
	pub fn unload(id: u32) void {
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
