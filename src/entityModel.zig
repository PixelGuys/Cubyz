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
	height: f32,
	texturePath: []const u8,
	id: []const u8,

	isLoaded: bool,
	vao: ?graphics.VertexArray = null,
	indexCount: c_int,
	defaultTexture: ?main.graphics.Texture,

	const Vertex = extern struct {
		pos: [3]f32,
		normal: [3]f32,
		uv: [2]f32,

		pub const attributeDescriptions: []const c.VkVertexInputAttributeDescription = &.{
			.{
				.location = 0,
				.format = c.VK_FORMAT_R32G32B32_SFLOAT,
				.offset = @offsetOf(@This(), "pos"),
			},
			.{
				.location = 1,
				.format = c.VK_FORMAT_R32G32B32_SFLOAT,
				.offset = @offsetOf(@This(), "normal"),
			},
			.{
				.location = 2,
				.format = c.VK_FORMAT_R32G32_SFLOAT,
				.offset = @offsetOf(@This(), "uv"),
			},
		};
	};

	pub fn init(assetFolder: []const u8, id: []const u8, zon: ZonElement) EntityModel {
		var self: EntityModel = undefined;
		self.id = main.worldArena.dupe(u8, id);
		self.height = zon.getChild("height").as(f32, 1);
		self.defaultTexture = null;
		self.vao = null;
		self.indexCount = 0;
		self.isLoaded = false;

		// get TexturePath
		{
			self.texturePath = &.{};
			var split = std.mem.splitScalar(u8, id, ':');
			const mod = split.first();
			if (zon.get(?[]const u8, "texture", null)) |texture| {
				self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "{s}/{s}/entityModels/textures/{s}", .{assetFolder, mod, texture}) catch &.{};
				main.files.cubyzDir().dir.access(self.texturePath, .{}) catch {
					main.worldArena.free(self.texturePath);
					self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "assets/{s}/entityModels/textures/{s}", .{mod, texture}) catch &.{};
				};
			}
		}
		return self;
	}

	fn loadModelAndTexture(self: *EntityModel) !void {
		self.defaultTexture = main.graphics.Texture.initFromFile(self.texturePath);

		const fileEnding = ".obj";
		const file = try main.assets.readAsset(main.stackAllocator, "entityModels/models", self.id, fileEnding);
		defer main.stackAllocator.free(file);

		const quadInfos = main.models.Model.loadRawModelDataFromObj(main.stackAllocator, file);
		defer main.stackAllocator.free(quadInfos);
		const vertices = main.stackAllocator.alloc(Vertex, quadInfos.len*4);
		defer main.stackAllocator.free(vertices);
		const indices: []u32 = main.stackAllocator.alloc(u32, quadInfos.len*6);
		defer main.stackAllocator.free(indices);

		for (quadInfos, 0..quadInfos.len) |quad, i| {
			for (0..4) |j| {
				const v = i*4 + j;
				vertices[v].normal = quad.normal;
				vertices[v].pos = quad.corners[j];
				vertices[v].uv = quad.cornerUV[j];
			}
		}

		const lut = [_]u32{0, 2, 1, 1, 2, 3};
		for (0..indices.len) |i| {
			indices[i] = @as(u32, @intCast(i))/6*4 + lut[i%6];
		}

		self.vao = .init(Vertex, vertices, indices);
		self.indexCount = @intCast(indices.len);
	}
	pub fn bind(self: *EntityModel) void {
		self.vao.?.bind();
		self.defaultTexture.?.bindTo(0);
	}
	pub fn deinit(self: *EntityModel) void {
		if (self.defaultTexture) |defaultTexture| {
			defaultTexture.deinit();
		}
		if (self.vao) |vao| {
			vao.deinit();
		}
	}
};

pub const EntityModelIndex = struct {
	index: u32,
	pub fn get(self: EntityModelIndex) *EntityModel {
		std.debug.assert(entityModels.items.len > self.index);
		const rv = &entityModels.items[self.index];
		if (rv.isLoaded)
			return rv;
		// should always exist because of firstEntry in entityModelPalette
		std.debug.assert(entityModels.items.len > 0);
		return &entityModels.items[0];
	}
};

pub var reverseIndices: std.StringHashMapUnmanaged(EntityModelIndex) = .{};
pub var entityModels: main.ListUnmanaged(EntityModel) = .{};

pub fn register(assetFolder: []const u8, id: []const u8, zon: ZonElement) usize {
	const index = entityModels.items.len;
	entityModels.append(main.worldArena, EntityModel.init(assetFolder, id, zon));
	reverseIndices.put(main.worldArena.allocator, id, EntityModelIndex{.index = @truncate(index)}) catch unreachable;
	return index;
}
pub fn reset() void {
	for (entityModels.items) |*model| {
		model.deinit();
	}
	entityModels = .{};
	reverseIndices = .{};
}

pub fn getById(id: []const u8) ?EntityModelIndex {
	if (reverseIndices.get(id)) |result| {
		return result;
	}
	return null;
}
pub fn loadModelsAndTexture() void {
	for (entityModels.items) |*value| {
		value.loadModelAndTexture() catch {
			value.isLoaded = false;
			continue;
		};
		value.isLoaded = true;
	}
}
