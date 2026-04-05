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
const Model = main.Model.Model;

pub const EntityModel = struct {
	model: Model,
	defaultTexture: ?main.graphics.Texture,

	height: f32,
	texturePath: []const u8,
	modelID: []const u8,
	id: []const u8,

	pub fn init(assetFolder: []const u8, id: []const u8, zon: ZonElement) EntityModel {
		var self: EntityModel = undefined;
		self.id = main.globalAllocator.dupe(u8, id);
		self.height = zon.getChild("height").as(f32, 1);
		self.defaultTexture = null;
		self.model = .init();

		// get TexturePath
		{
			var split = std.mem.splitScalar(u8, id, ':');
			const mod = split.first();
			self.texturePath = &.{};
			if (zon.get(?[]const u8, "texture", null)) |texture| {
				self.texturePath = std.fmt.allocPrint(main.globalAllocator.allocator, "{s}/{s}/entityModels/textures/{s}", .{assetFolder, mod, texture}) catch &.{};
				std.fs.cwd().access(self.texturePath, .{}) catch {
					self.texturePath = std.fmt.allocPrint(main.globalAllocator.allocator, "assets/{s}/entityModels/textures/{s}", .{mod, texture}) catch &.{};
				};
			}
		}
		self.modelID = main.globalAllocator.dupe(u8, zon.getChild("model").as([]const u8, "cubyz:missing"));
		return self;
	}
	fn generateGraphics(self: *EntityModel) void {
		self.defaultTexture = main.graphics.Texture.initFromFile(self.texturePath);
		self.model.generateGraphics(self.modelID);
	}
	pub fn bind(self: *EntityModel) void {
		if (!self.model.isGenerated) {
			self.generateGraphics();
		}
		self.model.bind();
		self.defaultTexture.?.bindTo(0);
	}

	pub fn deinit(self: *EntityModel) void {
		self.model.deinit();
		if (self.defaultTexture) |defaultTexture| {
			defaultTexture.deinit();
		}
		main.globalAllocator.free(self.id);
		if (self.texturePath.len > 0)
			main.globalAllocator.free(self.texturePath);
		main.globalAllocator.free(self.modelID);
	}
};

pub const EntityModelIndex = struct {
	index: u32,
	pub fn get(self: EntityModelIndex) *EntityModel {
		if (entityModels.items.len > self.index)
			return &entityModels.items[self.index];
		// should always exist because of firstEntry in entityModelPalette
		std.debug.assert(entityModels.items.len > 0);
		return &entityModels.items[0];
	}
};

pub var reverseIndices: std.StringHashMapUnmanaged(EntityModelIndex) = .{};
pub var entityModels: main.ListUnmanaged(EntityModel) = .{};

pub fn register(assetFolder: []const u8, id: []const u8, zon: ZonElement) usize {
	const index = entityModels.items.len;
	const entityModel = entityModels.addOne(main.worldArena);
	entityModel.* = EntityModel.init(assetFolder, id, zon);
	reverseIndices.put(main.worldArena.allocator, id, EntityModelIndex{.index = @truncate(index)}) catch unreachable;
	return index;
}
pub fn reset() void {
	entityModels = .{};
	reverseIndices = .{};
}

pub fn hasRegistered(id: []const u8) bool {
	return reverseIndices.contains(id);
}

pub fn getTypeById(id: []const u8) EntityModelIndex {
	if (reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.err("Couldn't find entityModel {s}. Replacing it with cubyz:missing ...", .{id});
		return EntityModelIndex{.index = 0};
	}
}

pub fn getTypeByIdOrNull(id: []const u8) ?EntityModelIndex {
	if (reverseIndices.get(id)) |result| {
		return result;
	}
	return null;
}
