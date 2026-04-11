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
	modelId: ?[]const u8,

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

	pub fn init(assetFolder: []const u8, zon: ZonElement) EntityModel {
		var self: EntityModel = undefined;
		if (zon.get(?[]const u8, "model", null)) |modelId| {
			self.modelId = main.worldArena.dupe(u8, modelId);
		} else {
			self.modelId = null;
		}
		self.height = zon.getChild("height").as(f32, 1);
		self.defaultTexture = null;
		self.vao = null;
		self.indexCount = 0;

		// get TexturePath
		{
			self.texturePath = &.{};
			if (zon.get(?[]const u8, "defaultTexture", null)) |texture| {
				var split = std.mem.splitScalar(u8, texture, ':');
				const mod = split.first();
				const textureName = split.next() orelse unreachable;
				self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "{s}/{s}/entityModels/textures/{s}", .{assetFolder, mod, textureName}) catch unreachable;
				main.files.cubyzDir().dir.access(self.texturePath, .{}) catch {
					main.worldArena.free(self.texturePath);
					self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "assets/{s}/entityModels/textures/{s}", .{mod, textureName}) catch unreachable;
				};
			}
		}
		return self;
	}

	pub fn deinit(self: *EntityModel) void {
		if (self.defaultTexture) |defaultTexture| {
			defaultTexture.deinit();
		}
		if (self.vao) |vao| {
			vao.deinit();
		}
	}

	fn cloneMetaData(self: *EntityModel) EntityModel {
		return .{
			.height = self.height,
			.texturePath = main.worldArena.dupe(u8, self.texturePath),
			.modelId = if (self.modelId) |modelId| main.worldArena.dupe(u8, modelId) else null,
			.vao = null,
			.indexCount = 0,
			.defaultTexture = null,
		};
	}

	fn loadModelAndTexture(self: *EntityModel) !void {
		self.defaultTexture = main.graphics.Texture.initFromFile(self.texturePath);
		if (self.modelId == null)
			return error.NoModelSpecified;

		const fileEnding = ".obj";
		const file = try main.assets.readAsset(main.stackAllocator, "entityModels/models", self.modelId.?, fileEnding);
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
};

pub const EntityModelIndex = struct {
	index: u32,
	pub fn get(self: EntityModelIndex) *EntityModel {
		std.debug.assert(entityModels.items.len > self.index);
		return &entityModels.items[self.index];
	}
};

pub var reverseIndices: std.StringHashMapUnmanaged(EntityModelIndex) = .{};
pub var entityModels: main.ListUnmanaged(EntityModel) = .{};

pub fn register(assetFolder: []const u8, entityModelId: []const u8, zon: ZonElement) usize {
	const index = entityModels.items.len;
	entityModels.append(main.worldArena, EntityModel.init(assetFolder, zon));
	reverseIndices.put(main.worldArena.allocator, entityModelId, EntityModelIndex{.index = @truncate(index)}) catch unreachable;
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
	if (reverseIndices.get("cubyz:missing")) |result| {
		return result;
	}
	return null;
}
pub fn loadModelsAndTexture() void {
	for (entityModels.items) |*value| {
		value.loadModelAndTexture() catch {
			value.deinit();
			value.* = getById("cubyz:missing").?.get().cloneMetaData();
			value.loadModelAndTexture() catch unreachable;
			continue;
		};
	}
}
