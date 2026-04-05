const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const c = graphics.c;
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Mat4f = vec.Mat4f;

const gltf = @cImport({
	@cInclude("cgltf.h");
});


pub const EntityModel = struct {
	vao: graphics.VertexArray = undefined,
	indexCount: c_int,
	texture: main.graphics.Texture,

	nodeReverse: std.StringHashMap(u16) = undefined,
	nodes: [20]Node = undefined,
	nodeCount: u8 = undefined,

	pub const Node = struct {
		pos: Vec3f,
		rot: Vec4f,
		scale: Vec3f,

		// TODO: add a matrix and a dirty flag
		parent: ?u16 = null,
	};

	const EntityVertex = extern struct {
		pos: [3]f32,
		normal: [3]f32,
		uv: [2]f32,
		nodeID: c_uint,

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
			.{
				.location = 3,
				.format = c.VK_FORMAT_R32_UINT,
				.offset = @offsetOf(@This(), "nodeID"),
			},
		};
	};

	pub fn initFromGltf(modelPath: []const u8, texturePath: []const u8) !EntityModel {
		var options: gltf.cgltf_options = .{};
		var data: *gltf.cgltf_data = undefined;

		var result = gltf.cgltf_parse_file(&options, @ptrCast(modelPath.ptr), @ptrCast(&data));
		if (result == gltf.cgltf_result_file_not_found or result == gltf.cgltf_result_io_error) {
			return getGltfError(result);
		}

		defer gltf.cgltf_free(@ptrCast(data));

		result = gltf.cgltf_load_buffers(&options, @ptrCast(data), "data:application/octet-stream");
		if (result != gltf.cgltf_result_success) return getGltfError(result);

		result = gltf.cgltf_validate(@ptrCast(data));
		if (result != gltf.cgltf_result_success) return getGltfError(result);

		var nodeReverse: std.StringHashMap(u16) = .init(main.globalArena.allocator);
		var nodes: [20]Node = std.mem.zeroes([20]Node);
		var nodeIdx: u8 = 0;

		const texture = main.graphics.Texture.initFromFile(texturePath);

		var vertices = main.List(EntityVertex).init(main.stackAllocator);
		defer vertices.deinit();
		var indices = main.List(u32).init(main.stackAllocator);
		defer indices.deinit();
		var baseVertex: u32 = 0;

		for (data.nodes, 0..data.nodes_count) |node, _| {
			if (node.children_count == 0) continue;

			nodeReverse.put(std.mem.span(node.name), @intCast(nodeIdx)) catch unreachable;
			if (nodeReverse.get(std.mem.span(node.name)) == null) {} else {}

			nodes[nodeIdx] = Node{
				.pos = Vec3f{-node.translation[0], node.translation[2], node.translation[1]},
				.rot = Vec4f{-node.rotation[0], node.rotation[2], node.rotation[1], node.rotation[3]},
				.scale = Vec3f{node.scale[0], node.scale[2], node.scale[1]},
			};
			nodeIdx += 1;
		}
		for (data.nodes, 0..data.nodes_count) |node, _| {
			if (node.children_count == 0 or node.parent == null) continue;

			const curNode = nodeReverse.get(std.mem.span(node.name)).?;
			nodes[curNode].parent = nodeReverse.get(std.mem.span(node.parent.*.name)).?;
		}
		for (data.nodes, 0..data.nodes_count) |node, _| {
			if (node.mesh == null) continue;

			var currentMat = Mat4f.translation(node.translation);
			currentMat = currentMat.mul(Mat4f.rotationQuat(node.rotation));
			currentMat = currentMat.mul(Mat4f.scale(node.scale));
			currentMat = Mat4f.identity().mul(currentMat);

			const primitives = node.mesh.*.primitives;
			for (primitives, 0..node.mesh.*.primitives_count) |primitive, _| {
				if (primitive.type != gltf.cgltf_primitive_type_triangles) {
					std.log.warn("Unsupported primitive type: {d}", .{primitive.type});
					continue;
				}

				const parentNodeID = nodeReverse.get(std.mem.span(node.parent.*.name)).?;

				const indicesAccessor = primitive.indices.*;
				const vertCount = primitive.attributes[0].data.*.count;
				var indicesSlice = indices.addMany(indicesAccessor.count);
				baseVertex = @intCast(vertices.items.len);
				const vertSlice: []EntityVertex = vertices.addMany(vertCount);
				for (0..indicesAccessor.count) |i| {
					const idx = indicesAccessor.index(i);
					indicesSlice[i] = @as(u32, @intCast(idx)) + baseVertex;

					// const modi = @as(i32, @intCast(i)) - 2;
					// if (@mod(modi, 3) == 0) {
					// const temp = indicesSlice[i - 1];
					// indicesSlice[i - 1] = indicesSlice[i];
					// indicesSlice[i] = temp;
					// }
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
					const pos: vec.Vec4f = currentMat.mulVec(.{p[0], p[1], p[2], 1});
					vertSlice[v].pos = .{-pos[0], pos[2], pos[1]};

					var normal: [3]f32 = undefined;
					_ = normalAttr.float(v, @ptrCast(&normal), 3);
					vertSlice[v].normal = .{-normal[0], normal[2], normal[1]};

					var uv: [2]f32 = undefined;
					_ = uvAttr.float(v, @ptrCast(&uv), 2);
					vertSlice[v].uv = .{uv[0], 1 - uv[1]};

					vertSlice[v].nodeID = @intCast(parentNodeID);
				}
			}
		}

		return .{
			.vao = .init(EntityVertex, vertices.items, indices.items),
			.texture = texture,
			.indexCount = @intCast(indices.items.len),

			.nodeReverse = nodeReverse,
			.nodes = nodes,
			.nodeCount = nodeIdx,
		};
	}

	pub fn initEmpty() EntityModel {
		const texture = graphics.Texture.init();
		texture.generate(graphics.Image.defaultImage);
		return .{
			.vao = .init(EntityVertex, &.{}, &.{}),
			.texture = texture,
			.indexCount = 0,

			.nodeReverse = undefined,
			.nodes = std.mem.zeroes([20]Node),
			.nodeCount = 0,
		};
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

	pub fn bind(self: EntityModel) void {
		self.vao.bind();
		self.texture.bindTo(0);
	}

	pub fn deinit(self: *EntityModel) void {
		self.vao.deinit();
		self.texture.deinit();

		self.nodeReverse.deinit();
	}
};
