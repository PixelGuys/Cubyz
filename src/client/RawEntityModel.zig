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

isGenerated: bool,

vao: graphics.VertexArray = undefined,
indexCount: c_int,
quadInfos: []main.models.QuadInfo,

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

pub fn init(data: []const u8) @This() {
	return .{
		.isGenerated = false,
		.vao = undefined,
		.indexCount = 0,
		.quadInfos = main.models.Model.loadRawModelDataFromObj(main.worldArena, data),
	};
}
pub fn generateGraphics(self: *@This()) void {
	if (self.isGenerated)
		return;
	const quadInfos = self.quadInfos;
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
	self.isGenerated = true;
}
pub fn bind(self: *@This()) void {
	self.vao.bind();
}
pub fn deinit(self: @This()) void {
	self.vao.deinit();
}
