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

const gltf = @cImport({
	@cInclude("cgltf.h");
});

pub const EntityModel = struct {
	height: f32,
	texturePath: []const u8,
	modelId: ?[]const u8,

	vao: ?graphics.VertexArray = null,
	indexCount: c_int,
	defaultTexture: ?main.graphics.Texture,
	coordinateSystem: CoordinateSystem,

	pub const CoordinateSystem = enum {
		right_handed_z_up,
		right_handed_y_up,
		left_handed_z_up,
		left_handed_y_up,
	};

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
		self.coordinateSystem = zon.get(CoordinateSystem, "coordinateSystem", .right_handed_z_up);

		// get TexturePath
		{
			self.texturePath = &.{};
			const fileEnding = ".png";
			if (zon.get(?[]const u8, "defaultTexture", null)) |texture| {
				var split = std.mem.splitScalar(u8, texture, ':');
				const mod = split.first();
				const textureName = split.next() orelse unreachable;
				self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "{s}/{s}/entityModels/textures/{s}{s}", .{assetFolder, mod, textureName, fileEnding}) catch unreachable;
				main.files.cubyzDir().dir.access(main.io, self.texturePath, .{}) catch {
					main.worldArena.free(self.texturePath);
					self.texturePath = std.fmt.allocPrint(main.worldArena.allocator, "assets/{s}/entityModels/textures/{s}{s}", .{mod, textureName, fileEnding}) catch unreachable;
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
			.coordinateSystem = self.coordinateSystem,
		};
	}

	fn loadModelAndTexture(self: *EntityModel) !void {
		self.defaultTexture = main.graphics.Texture.initFromFile(self.texturePath);
		if (self.modelId == null)
			return error.NoModelSpecified;

		const file = try main.assets.readAsset(main.stackAllocator, "entityModels/models", self.modelId.?, ".glb");
		defer main.stackAllocator.free(file);

		var options: gltf.cgltf_options = .{};
		var data: *gltf.cgltf_data = undefined;

		var result = gltf.cgltf_parse(&options, @ptrCast(file.ptr), @intCast(file.len), @ptrCast(&data));
		if (result != gltf.cgltf_result_success) {
			std.log.err("GLTF Parse error: {s}", .{@errorName(getGltfError(result))});
			return getGltfError(result);
		}

		defer gltf.cgltf_free(@ptrCast(data));

		result = gltf.cgltf_load_buffers(&options, @ptrCast(data), "data:application/octet-stream");
		if (result != gltf.cgltf_result_success) {
			std.log.err("GLTF Load buffers error: {s}", .{@errorName(getGltfError(result))});
			return getGltfError(result);
		}

		result = gltf.cgltf_validate(@ptrCast(data));
		if (result != gltf.cgltf_result_success) {
			std.log.err("GLTF Validation error: {s}", .{@errorName(getGltfError(result))});
			return getGltfError(result);
		}

		var vertices = main.List(Vertex).init(main.stackAllocator);
		defer vertices.deinit();
		var indices = main.List(u32).init(main.stackAllocator);
		defer indices.deinit();
		var baseVertex: u32 = 0;

		for (data.nodes[0..data.nodes_count]) |node| {
			if (node.mesh != null) {
				const finalMat = getHierarchyMatrix(node, self.coordinateSystem);

				const primitives = node.mesh.*.primitives;
				for (primitives[0..node.mesh.*.primitives_count]) |primitive| {
					if (primitive.type != gltf.cgltf_primitive_type_triangles) {
						std.log.warn("Unsupported primitive type: {d}", .{primitive.type});
						continue;
					}

					const indicesAccessor = primitive.indices.*;
					const vertCount = primitive.attributes[0].data.*.count;
					var indicesSlice = indices.addMany(indicesAccessor.count);
					baseVertex = @intCast(vertices.items.len);
					const vertSlice: []Vertex = vertices.addMany(vertCount);

					for (0..indicesAccessor.count) |i| {
						const idx = indicesAccessor.read_index(i);
						indicesSlice[i] = @as(u32, @intCast(idx)) + baseVertex;
					}

					var positionAttr: gltf.cgltf_accessor = undefined;
					var normalAttr: gltf.cgltf_accessor = undefined;
					var uvAttr: gltf.cgltf_accessor = undefined;
					for (primitive.attributes, 0..primitive.attributes_count) |attrib, _| {
						const attribAccessor = attrib.data.*;

						switch (attrib.type) {
							gltf.cgltf_attribute_type_position => positionAttr = attribAccessor,
							gltf.cgltf_attribute_type_normal => normalAttr = attribAccessor,
							gltf.cgltf_attribute_type_texcoord => uvAttr = attribAccessor,
							else => continue,
						}
					}

					for (0..positionAttr.count) |v| {
						var p: [3]f32 = undefined;
						_ = positionAttr.read_float(v, @ptrCast(&p), 3);
						const p2 = convertCoordinateSystemVec(p, self.coordinateSystem);
						const pos: vec.Vec4f = finalMat.mulVec(.{p2[0], p2[1], p2[2], 1});
						vertSlice[v].pos = vec.xyz(pos);

						var normal: [3]f32 = undefined;
						_ = normalAttr.read_float(v, @ptrCast(&normal), 3);
						vertSlice[v].normal = convertCoordinateSystemVec(normal, self.coordinateSystem);

						var uv: [2]f32 = undefined;
						_ = uvAttr.read_float(v, @ptrCast(&uv), 2);
						vertSlice[v].uv = .{uv[0], 1 - uv[1]};
					}
				}
			}
		}

		self.vao = .init(Vertex, vertices.items, indices.items);
		self.indexCount = @intCast(indices.items.len);
	}

	fn convertCoordinateSystemVec(v: Vec3f, sys: CoordinateSystem) Vec3f {
		return switch (sys) {
			.right_handed_z_up => Vec3f{v[0], v[1], v[2]},
			.right_handed_y_up => Vec3f{v[0], v[2], -v[1]},
			.left_handed_z_up => Vec3f{-v[0], v[1], v[2]},
			.left_handed_y_up => Vec3f{-v[0], v[2], v[1]},
		};
	}

	fn convertCoordinateSystemQuat(q: Vec4f, sys: CoordinateSystem) Vec4f {
		return switch (sys) {
			.right_handed_z_up => Vec4f{q[0], q[1], q[2], q[3]},
			.right_handed_y_up => Vec4f{q[0], q[2], -q[1], q[3]},
			.left_handed_z_up => Vec4f{-q[0], q[1], q[2], q[3]},
			.left_handed_y_up => Vec4f{-q[0], q[2], q[1], q[3]},
		};
	}

	fn convertCoordinateSystemScale(s: Vec3f, sys: CoordinateSystem) Vec3f {
		return switch (sys) {
			.right_handed_z_up, .left_handed_z_up => Vec3f{s[0], s[1], s[2]},
			.right_handed_y_up, .left_handed_y_up => Vec3f{s[0], s[2], s[1]},
		};
	}

	fn getHierarchyMatrix(node: gltf.cgltf_node, sys: CoordinateSystem) Mat4f {
		var currentMat = Mat4f.translation(convertCoordinateSystemVec(node.translation, sys));
		currentMat = currentMat.mul(Mat4f.rotationQuat(convertCoordinateSystemQuat(node.rotation, sys)));
		currentMat = currentMat.mul(Mat4f.scale(convertCoordinateSystemScale(node.scale, sys)));

		if (node.parent == null) {
			return currentMat;
		}

		return getHierarchyMatrix(node.parent.*, sys).mul(currentMat);
	}

	fn getGltfError(result: gltf.cgltf_result) anyerror {
		return switch (result) {
			gltf.cgltf_result_data_too_short => error.DataTooShort,
			gltf.cgltf_result_unknown_format => error.UnknownFormat,
			gltf.cgltf_result_invalid_json => error.InvalidJson,
			gltf.cgltf_result_invalid_gltf => error.InvalidGltf,
			gltf.cgltf_result_invalid_options => error.InvalidOptions,
			gltf.cgltf_result_file_not_found => error.FileNotFound,
			gltf.cgltf_result_io_error => error.IoError,
			gltf.cgltf_result_out_of_memory => error.OutOfMemory,
			gltf.cgltf_result_legacy_gltf => error.LegacyGltf,
			else => unreachable,
		};
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
	return null;
}
pub fn default() EntityModelIndex {
	if (reverseIndices.get("cubyz:missing")) |result| {
		return result;
	}
	@panic("Not even cubyz:missing is available to fallback to!");
}
pub fn loadModelsAndTexture() void {
	for (entityModels.items) |*value| {
		value.loadModelAndTexture() catch {
			value.deinit();
			value.* = default().get().cloneMetaData();
			value.loadModelAndTexture() catch unreachable;
			continue;
		};
	}
}
