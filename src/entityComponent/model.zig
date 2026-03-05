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

pub const EntityModel = struct {
	buffer: ?main.graphics.SSBO,
	size: c_int = 0,
	defaultTexture: ?main.graphics.Texture,
	height: f32,

	texturePath: []const u8,
	modelID: []const u8,
	id: []const u8,

	pub fn init(assetFolder: []const u8, id: []const u8, zon: ZonElement) EntityModel {
		var self: EntityModel = undefined;
		self.id = main.worldArena.dupe(u8, id);
		self.height = zon.getChild("height").as(f32, 1);
		self.defaultTexture = null;
		self.buffer = null;

		// get TexturePath
		{
			var split = std.mem.splitScalar(u8, id, ':');
			const mod = split.first();
			self.texturePath = &.{};
			if (zon.get(?[]const u8, "texture", null)) |texture| {
				self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "{s}/{s}/entity/textures/{s}", .{assetFolder, mod, texture}) catch &.{};
				std.fs.cwd().access(self.texturePath, .{}) catch {
					self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "assets/{s}/entity/textures/{s}", .{mod, texture}) catch &.{};
				};
			}
		}
		self.modelID = main.worldArena.dupe(u8, zon.getChild("model").as([]const u8, "cubyz:entity/missing"));
		return self;
	}
	fn deinit(self: *const EntityModel) void {
		if (self.buffer) |buffer| {
			buffer.deinit();
		}
		if (self.texture) |texture| {
			texture.deinit();
		}
	}
	fn generateGraphics(self: *EntityModel) void {
		self.defaultTexture = main.graphics.Texture.initFromFile(self.texturePath);

		const quadInfos = main.assets.rawModelData.get(self.modelID) orelse unreachable;
		self.buffer = .initStatic(main.models.QuadInfo, quadInfos);
		self.size = @intCast(quadInfos.len);
	}
	pub fn bind(self: *EntityModel) void {
		if (self.buffer == null) {
			self.generateGraphics();
		}
		self.buffer.?.bind(11);
	}
};
pub var entityModels: std.StringHashMapUnmanaged(*EntityModel) = .{};

pub fn loadWorldAsset(assetFolder: []const u8, assets: *main.assets.Assets) void {
	var entityModelIterator = assets.entityType.iterator();
	main.entityComponent.model.entityModels = .{};
	while (entityModelIterator.next()) |it| {
		const model = main.worldArena.create(main.entityComponent.model.EntityModel);
		model.* = main.entityComponent.model.EntityModel.init(assetFolder, it.key_ptr.*, it.value_ptr.*);
		main.entityComponent.model.entityModels.put(main.worldArena.allocator, it.key_ptr.*, model) catch continue;
	}
}

// ############################# Client only stuff ################################
pub const Client = struct {
	const RenderComponent = struct {
		entity: u32, // entity
		model: *EntityModel, // model
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
	pub fn register(id: u32, comp: ZonElement) void {
		const modelID = comp.get([]const u8, "model", "cubyz:missing");
		const customTexture: ?main.graphics.Texture = null;
		const model = entityModels.get(modelID) orelse {
			std.debug.print("EntityModel {s} wasn't found", .{modelID});
			return;
		};
		renderComponents.put(id, RenderComponent{
			.entity = id,
			.customTexture = customTexture,
			.model = model,
		}) catch unreachable;
	}
	pub fn unregister(id: u32) void {
		_ = renderComponents.remove(id);
	}
	pub fn changeEntityModel(id: u32, entityModel: []const u8) void {
		if (entityModels.get(entityModel)) |entModel| {
			if (renderComponents.get(id)) |rc| {
				var newRc = rc;
				newRc.customTexture = null;
				newRc.model = entModel;
				renderComponents.put(id, newRc) catch unreachable;
			}
		}
	}
};

// ############################# Server only stuff ################################

pub const Server = struct {
	pub const RenderComponent = struct {
		entity: u32, // entity
		model: *EntityModel, // model
		customTexturePath: ?[]const u8, // customTexture
		fn deinit(self: RenderComponent) void {
			if (self.customTexturePath) |path| {
				main.globalAllocator.free(path);
			}
		}
		pub fn save(self: RenderComponent, allocator: NeverFailingAllocator) ZonElement {
			var obj = ZonElement.initObject(allocator);
			obj.put("model", self.model.id);
			if (self.customTexturePath) |texutre| {
				obj.putOwnedString("customTexture", texutre);
			}
			return obj;
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
	pub fn register(entity: u32, zon: ZonElement) void {
		const modelID = zon.get([]const u8, "model", "cubyz:missing");
		const customTexturePath = zon.get(?[]const u8, "customTexture", null);

		const model = entityModels.get(modelID) orelse {
			std.debug.print("EntityModel {s} wasn't found", .{modelID});
			return;
		};
		if (renderComponents.get(entity)) |old| {
			old.deinit();
		}
		renderComponents.put(entity, RenderComponent{
			.entity = entity,
			.customTexturePath = customTexturePath,
			.model = model,
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
