const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const c = graphics.c;
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Mat4f = vec.Mat4f;

const gltf = @cImport({
	@cInclude("cgltf.h");
});

pub const EntityModel = struct {
	vao: graphics.VertexArray = undefined,
	indexCount: c_int,
	texture: main.graphics.Texture,

	const EntityVertex = extern struct {
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

	pub fn initFromGltf(modelPath: []const u8, texturePath: []const u8) !EntityModel {
		var options: gltf.cgltf_options = .{};
		var data: *gltf.cgltf_data = undefined;

		var result = gltf.cgltf_parse_file(&options, @ptrCast(modelPath.ptr), @ptrCast(&data));
		defer gltf.cgltf_free(@ptrCast(data));

		if (result != gltf.cgltf_result_success) {
			return getGltfError(result);
		}

		result = gltf.cgltf_load_buffers(&options, @ptrCast(data), "data:application/octet-stream");
		if (result != gltf.cgltf_result_success) {
			return getGltfError(result);
		}

		result = gltf.cgltf_validate(@ptrCast(data));
		if (result != gltf.cgltf_result_success) {
			return getGltfError(result);
		}

		const texture = main.graphics.Texture.initFromFile(texturePath);

		var vertices = main.List(EntityVertex).init(main.stackAllocator);
		defer vertices.deinit();
		var indices = main.List(u32).init(main.stackAllocator);
		defer indices.deinit();
		var baseVertex: u32 = 0;

		for (data.nodes, 0..data.nodes_count) |node, _| {
			if (node.mesh != null) {
				const finalMat = Mat4f.identity().mul(getHierarchyMatrix(node));

				const primitives = node.mesh.*.primitives;
				for (primitives, 0..node.mesh.*.primitives_count) |primitive, _| {
					if (primitive.type != gltf.cgltf_primitive_type_triangles) {
						std.log.warn("Unsupported primitive type: {d}", .{primitive.type});
						continue;
					}

					const indicesAccessor = primitive.indices.*;
					const vertCount = primitive.attributes[0].data.*.count;
					var indicesSlice = indices.addMany(indicesAccessor.count);
					baseVertex = @intCast(vertices.items.len);
					const vertSlice: []EntityVertex = vertices.addMany(vertCount);
					for (0..indicesAccessor.count) |i| {
						const idx = indicesAccessor.index(i);
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
						_ = positionAttr.float(v, @ptrCast(&p), 3);
						const pos: vec.Vec4f = finalMat.mulVec(.{p[0], p[2], p[1], 1});
						vertSlice[v].pos = .{-pos[0], pos[1], pos[2]};

						var normal: [3]f32 = undefined;
						_ = normalAttr.float(v, @ptrCast(&normal), 3);
						vertSlice[v].normal = .{-normal[0], normal[2], normal[1]};

						var uv: [2]f32 = undefined;
						_ = uvAttr.float(v, @ptrCast(&uv), 2);
						vertSlice[v].uv = .{uv[0], 1 - uv[1]};
					}
				}
			}
		}

		return .{
			.vao = .init(EntityVertex, vertices.items, indices.items),
			.texture = texture,
			.indexCount = @intCast(indices.items.len),
		};
	}

	pub fn initEmpty() EntityModel {
		const texture = graphics.Texture.init();
		texture.generate(graphics.Image.defaultImage);
		return .{
			.vao = .init(EntityVertex, &.{}, &.{}),
			.texture = texture,
			.indexCount = 0,
		};
	}

	fn getHierarchyMatrix(node: gltf.cgltf_node) Mat4f {
		var currentMat = Mat4f.translation(Vec3f{
			node.translation[0],
			node.translation[2],
			node.translation[1],
		});
		currentMat = currentMat.mul(Mat4f.rotationQuat(vec.Vec4f{
			node.rotation[0],
			node.rotation[2],
			node.rotation[1],
			node.rotation[3],
		}));
		currentMat = currentMat.mul(Mat4f.scale(Vec3f{
			node.scale[0],
			node.scale[2],
			node.scale[1],
		}));

		if (node.parent == null) {
			return currentMat;
		}

		return getHierarchyMatrix(node.parent.*).mul(currentMat);
	}

	fn getGltfError(result: c_uint) anyerror {
		return switch (result) {
			1 => error.DataTooShort,
			2 => error.UnknownFormat,
			3 => error.InvalidJson,
			4 => error.InvalidGltf,
			5 => error.InvalidOptions,
			6 => error.FileNotFound,
			7 => error.IoError,
			8 => error.OutOfMemory,
			9 => error.LegacyGltf,
			else => unreachable,
		};
	}

	pub fn bind(self: EntityModel) void {
		self.vao.bind();
		self.texture.bindTo(0);
	}

	pub fn deinit(self: EntityModel) void {
		self.vao.deinit();
		self.texture.deinit();
	}
};
