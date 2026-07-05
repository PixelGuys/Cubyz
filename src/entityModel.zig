const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const CoordinateSystem = vec.CoordinateSystem;
const Quat = vec.Quat;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");

pub const EntityModel = struct {
	height: f32,
	texturePath: []const u8,
	modelId: ?[]const u8,
	entityModelId: []const u8,

	nodeIndexMap: std.StringHashMap(u16) = undefined,
	nodes: []Node = undefined,
	nodePivots: []Mat4f = undefined,
	nodeCount: u16,

	vao: ?graphics.VertexArray = null,
	indexCount: c_int,
	defaultTexture: ?main.graphics.Texture,
	coordinateSystem: CoordinateSystem,

	pub const Node = struct {
		parent: ?u16 = null,
	};

	pub const Vertex = extern struct {
		pos: [3]f32,
		normal: [3]f32,
		uv: [2]f32,
		nodeId: c_uint,

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
				.offset = @offsetOf(@This(), "nodeId"),
			},
		};
	};

	const NodeRemap = struct { depth: u16, gltfNodeIdx: u32 };

	pub fn init(assetFolder: []const u8, entityModelId: []const u8, index: EntityModelIndex, zon: ZonElement) EntityModel {
		var self: EntityModel = undefined;
		if (zon.get([]const u8, "model")) |modelId| {
			self.modelId = main.worldArena.dupe(u8, modelId);
		} else {
			self.modelId = null;
		}
		self.entityModelId = main.worldArena.dupe(u8, entityModelId);
		self.height = zon.get(f32, "height") orelse 1;
		self.defaultTexture = null;
		self.vao = null;
		self.indexCount = 0;
		self.coordinateSystem = zon.get(CoordinateSystem, "coordinateSystem") orelse .right_handed_z_up;

		self.nodeIndexMap = .init(main.worldArena.allocator);
		self.nodes = main.worldArena.alloc(Node, 0);
		self.nodePivots = main.worldArena.alloc(Mat4f, 0);
		self.nodeCount = 0;

		if (zon.getChildOrNull("isPlayerModel")) |isPlayerModel| {
			if (isPlayerModel.as(bool) orelse false) {
				playerEntityModels.append(main.worldArena, index);
			}
		}

		var isPlayerModel = false;
		const tags = main.Tag.loadTagsFromZon(main.worldArena, zon.getChild("tags"));
		for (tags) |tag| {
			if (tag == .playerModel) {
				isPlayerModel = true;
			}
		}

		if (isPlayerModel) {
			playerEntityModels.append(main.worldArena, index);
		}

		// get TexturePath
		{
			self.texturePath = &.{};
			const fileEnding = ".png";
			if (zon.get([]const u8, "defaultTexture")) |texture| {
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
		const newNodes = main.worldArena.alloc(Node, self.nodes.len);
		@memcpy(newNodes, self.nodes);
		const newNodePivots = main.worldArena.alloc(Mat4f, self.nodePivots.len);
		@memcpy(newNodePivots, self.nodePivots);
		return .{
			.height = self.height,
			.texturePath = main.worldArena.dupe(u8, self.texturePath),
			.modelId = if (self.modelId) |modelId| main.worldArena.dupe(u8, modelId) else null,
			.entityModelId = main.worldArena.dupe(u8, self.entityModelId),
			.vao = null,
			.indexCount = 0,
			.defaultTexture = null,
			.coordinateSystem = self.coordinateSystem,
			.nodeIndexMap = self.nodeIndexMap.clone() catch unreachable,
			.nodes = newNodes,
			.nodePivots = newNodePivots,
			.nodeCount = self.nodeCount,
		};
	}

	fn loadModelAndTexture(self: *EntityModel) !void {
		self.defaultTexture = main.graphics.Texture.initFromFile(self.texturePath);
		if (self.modelId == null) return error.NoModelSpecified;

		const file = try main.assets.readAsset(main.stackAllocator, "entityModels/models", self.modelId.?, ".glb");
		defer main.stackAllocator.free(file);

		var options: c.cgltf_options = .{};
		var data: *c.cgltf_data = undefined;

		var result = c.cgltf_parse(&options, @ptrCast(file.ptr), @intCast(file.len), @ptrCast(&data));
		if (result != c.cgltf_result_success) {
			std.log.err("GLTF Parse error: {s}", .{@errorName(getGltfError(result))});
			return getGltfError(result);
		}

		defer c.cgltf_free(@ptrCast(data));

		result = c.cgltf_load_buffers(&options, @ptrCast(data), "data:application/octet-stream");
		if (result != c.cgltf_result_success) {
			std.log.err("GLTF Load buffers error: {s}", .{@errorName(getGltfError(result))});
			return getGltfError(result);
		}

		result = c.cgltf_validate(@ptrCast(data));
		if (result != c.cgltf_result_success) {
			std.log.err("GLTF Validation error: {s}", .{@errorName(getGltfError(result))});
			return getGltfError(result);
		}

		var vertices: main.List(Vertex) = .empty;
		defer vertices.deinit(main.stackAllocator);
		var indices: main.List(u32) = .empty;
		defer indices.deinit(main.stackAllocator);
		var baseVertex: u32 = 0;

		var nodeDepthRemap: main.List(NodeRemap) = .empty;
		defer nodeDepthRemap.deinit(main.stackAllocator);

		var nodeIdx: u16 = 0;
		for (data.nodes, 0..data.nodes_count) |node, gltfNodeIdx| {
			if (node.children_count == 0) continue;
			nodeDepthRemap.append(main.stackAllocator, .{
				.depth = getHierarchyDepth(node, 0),
				.gltfNodeIdx = @intCast(gltfNodeIdx),
			});

			nodeIdx += 1;
		}
		const nodeCount = nodeIdx;

		std.mem.sort(NodeRemap, nodeDepthRemap.items, {}, compareDepth);

		self.nodes = main.worldArena.alloc(Node, nodeCount);
		self.nodePivots = main.worldArena.alloc(Mat4f, nodeCount);

		for (nodeDepthRemap.items, 0..) |nodeRemap, i| {
			const node = data.nodes[nodeRemap.gltfNodeIdx];

			const nameC = std.mem.span(node.name);
			const name = main.globalArena.alloc(u8, nameC.len);
			@memcpy(name, nameC);
			self.nodeIndexMap.put(name, @intCast(i)) catch unreachable;

			var pivotMat = Mat4f.translation(self.coordinateSystem.convertVec(node.translation, @splat(0)));
			pivotMat = pivotMat.mul(Mat4f.rotationQuat(self.coordinateSystem.convertQuat(node.rotation)));
			pivotMat = pivotMat.mul(Mat4f.scale(self.coordinateSystem.convertScale(node.scale)));

			self.nodes[i] = Node{};
			self.nodePivots[i] = pivotMat;
		}

		for (nodeDepthRemap.items, 0..) |nodeRemap, i| {
			const node = data.nodes[nodeRemap.gltfNodeIdx];
			if (node.parent == null) continue;

			self.nodes[i].parent = self.nodeIndexMap.get(std.mem.span(node.parent.*.name)).?;
		}

		for (data.nodes[0..data.nodes_count]) |node| {
			if (node.mesh != null) {
				var finalMat = Mat4f.translation(self.coordinateSystem.convertVec(node.translation, @splat(0)));
				finalMat = finalMat.mul(Mat4f.rotationQuat(self.coordinateSystem.convertQuat(node.rotation)));
				finalMat = finalMat.mul(Mat4f.scale(self.coordinateSystem.convertScale(node.scale)));

				const parentNodeID = if (node.parent) |p| self.nodeIndexMap.get(std.mem.span(p.*.name)).? else 0;

				const primitives = node.mesh.*.primitives;
				for (primitives[0..node.mesh.*.primitives_count]) |primitive| {
					if (primitive.type != c.cgltf_primitive_type_triangles) {
						std.log.warn("Unsupported primitive type: {d}", .{primitive.type});
						continue;
					}

					const indicesAccessor = primitive.indices.*;
					const vertCount = primitive.attributes[0].data.*.count;
					var indicesSlice = indices.addMany(main.stackAllocator, indicesAccessor.count);
					baseVertex = @intCast(vertices.items.len);
					const vertSlice: []Vertex = vertices.addMany(main.stackAllocator, vertCount);

					for (0..indicesAccessor.count) |i| {
						const idx = indicesAccessor.read_index(i);
						indicesSlice[i] = @as(u32, @intCast(idx)) + baseVertex;
					}

					var positionAttr: c.cgltf_accessor = undefined;
					var normalAttr: c.cgltf_accessor = undefined;
					var uvAttr: c.cgltf_accessor = undefined;
					for (primitive.attributes, 0..primitive.attributes_count) |attrib, _| {
						const attribAccessor = attrib.data.*;

						switch (attrib.type) {
							c.cgltf_attribute_type_position => positionAttr = attribAccessor,
							c.cgltf_attribute_type_normal => normalAttr = attribAccessor,
							c.cgltf_attribute_type_texcoord => uvAttr = attribAccessor,
							else => continue,
						}
					}

					for (0..positionAttr.count) |v| {
						var p: [3]f32 = undefined;
						_ = positionAttr.read_float(v, @ptrCast(&p), 3);
						const p2 = self.coordinateSystem.convertVec(p, @splat(0));
						const pos: vec.Vec4f = finalMat.mulVec(.{p2[0], p2[1], p2[2], 1});
						vertSlice[v].pos = vec.xyz(pos);

						var normal: [3]f32 = undefined;
						_ = normalAttr.read_float(v, @ptrCast(&normal), 3);
						vertSlice[v].normal = self.coordinateSystem.convertVec(normal, @splat(0));

						var uv: [2]f32 = undefined;
						_ = uvAttr.read_float(v, @ptrCast(&uv), 2);
						vertSlice[v].uv = .{uv[0], 1 - uv[1]};

						vertSlice[v].nodeId = @intCast(parentNodeID);
					}
				}
			}
		}

		self.vao = .init(Vertex, vertices.items, indices.items);
		self.indexCount = @intCast(indices.items.len);
		self.nodeCount = nodeIdx;
	}

	fn compareDepth(_: void, lhs: NodeRemap, rhs: NodeRemap) bool {
		return lhs.depth < rhs.depth;
	}

	fn getHierarchyDepth(node: c.cgltf_node, depth: u16) u16 {
		if (node.parent == null) {
			return depth;
		}

		return getHierarchyDepth(node.parent.*, depth + 1);
	}

	fn getGltfError(result: c.cgltf_result) error{ DataTooShort, UnknownFormat, InvalidJson, InvalidGltf, InvalidOptions, FileNotFound, IoError, OutOfMemory, LegacyGltf } {
		return switch (result) {
			c.cgltf_result_data_too_short => error.DataTooShort,
			c.cgltf_result_unknown_format => error.UnknownFormat,
			c.cgltf_result_invalid_json => error.InvalidJson,
			c.cgltf_result_invalid_gltf => error.InvalidGltf,
			c.cgltf_result_invalid_options => error.InvalidOptions,
			c.cgltf_result_file_not_found => error.FileNotFound,
			c.cgltf_result_io_error => error.IoError,
			c.cgltf_result_out_of_memory => error.OutOfMemory,
			c.cgltf_result_legacy_gltf => error.LegacyGltf,
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

pub var playerEntityModels: main.List(EntityModelIndex) = .empty;

pub var reverseIndices: std.StringHashMapUnmanaged(EntityModelIndex) = .{};
pub var entityModels: main.List(EntityModel) = .empty;

pub fn register(assetFolder: []const u8, entityModelId: []const u8, zon: ZonElement) EntityModelIndex {
	const index = EntityModelIndex{.index = @intCast(entityModels.items.len)};
	entityModels.append(main.worldArena, EntityModel.init(assetFolder, entityModelId, index, zon));
	reverseIndices.put(main.worldArena.allocator, entityModelId, index) catch unreachable;
	return index;
}
pub fn reset() void {
	for (entityModels.items) |*model| {
		model.deinit();
	}
	entityModels = .empty;
	reverseIndices = .{};
	playerEntityModels = .empty;
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
