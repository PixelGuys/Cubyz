const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const c = graphics.c;

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

	pub fn initFromObj(modelPath: []const u8, texturePath: []const u8) EntityModel {
		const modelFile = main.files.cwd().read(main.stackAllocator, modelPath) catch |err| blk: {
			std.log.err("Error while reading player model from path {s}: {s}", .{modelPath, @errorName(err)});
			break :blk &.{};
		};
		defer main.stackAllocator.free(modelFile);
		const quadInfos = main.models.Model.loadRawModelDataFromObj(main.stackAllocator, modelFile);
		defer main.stackAllocator.free(quadInfos);

		const vertices = main.stackAllocator.alloc(EntityVertex, quadInfos.len*4);
		defer main.stackAllocator.free(vertices);
		const indices: []u32 = main.stackAllocator.alloc(u32, quadInfos.len*6);
		defer main.stackAllocator.free(indices);

		const texture = main.graphics.Texture.initFromFile(texturePath);

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

		return .{
			.vao = .init(EntityVertex, vertices, indices),
			.texture = texture,
			.indexCount = @intCast(indices.len),
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
