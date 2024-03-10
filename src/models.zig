const std = @import("std");

const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const graphics = @import("graphics.zig");
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec2f = vec.Vec2f;

var quadSSBO: graphics.SSBO = undefined;

const QuadInfo = extern struct {
	normal: Vec3f,
	corners: [4]Vec3f,
	cornerUV: [4]Vec2f,
	textureSlot: u32,
};

const Model = struct {
	min: Vec3i,
	max: Vec3i,
	quads: []u16,
};

var nameToIndex: std.StringHashMap(u16) = undefined;

pub fn getModelIndex(string: []const u8) u16 {
	return nameToIndex.get(string) orelse {
		std.log.warn("Couldn't find voxelModel with name: {s}.", .{string});
		return 0;
	};
}

pub var quads: main.List(QuadInfo) = undefined;
pub var models: main.List(Model) = undefined;
pub var fullCube: u16 = undefined;

fn addQuad(info: QuadInfo) u16 {
	const index: u16 = @intCast(quads.items.len);
	quads.append(info);
	return index;
}

// TODO: Allow loading from world assets.
// TODO: Entity models.
pub fn init() void {
	models = main.List(Model).init(main.globalAllocator);
	quads = main.List(QuadInfo).init(main.globalAllocator);

	nameToIndex = std.StringHashMap(u16).init(main.globalAllocator.allocator);

	const cubeIndex: u16 = @intCast(models.items.len);
	nameToIndex.put("cube", cubeIndex) catch unreachable;
	const cube = models.addOne();
	cube.min = .{0, 0, 0};
	cube.max = .{16, 16, 16};
	cube.quads = main.globalAllocator.alloc(u16, 6);
	cube.quads[chunk.Neighbors.dirNegX] = addQuad(.{
		.normal = .{-1, 0, 0},
		.corners = .{.{0, 1, 0}, .{0, 1, 1}, .{0, 0, 0}, .{0, 0, 1}},
		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
		.textureSlot = chunk.Neighbors.dirNegX,
	});
	cube.quads[chunk.Neighbors.dirPosX] = addQuad(.{
		.normal = .{1, 0, 0},
		.corners = .{.{1, 0, 0}, .{1, 0, 1}, .{1, 1, 0}, .{1, 1, 1}},
		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
		.textureSlot = chunk.Neighbors.dirPosX,
	});
	cube.quads[chunk.Neighbors.dirNegY] = addQuad(.{
		.normal = .{0, -1, 0},
		.corners = .{.{0, 0, 0}, .{0, 0, 1}, .{1, 0, 0}, .{1, 0, 1}},
		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
		.textureSlot = chunk.Neighbors.dirNegY,
	});
	cube.quads[chunk.Neighbors.dirPosY] = addQuad(.{
		.normal = .{0, 1, 0},
		.corners = .{.{1, 1, 0}, .{1, 1, 1}, .{0, 1, 0}, .{0, 1, 1}},
		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
		.textureSlot = chunk.Neighbors.dirPosY,
	});
	cube.quads[chunk.Neighbors.dirDown] = addQuad(.{
		.normal = .{0, 0, -1},
		.corners = .{.{0, 1, 0}, .{0, 0, 0}, .{1, 1, 0}, .{1, 0, 0}},
		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
		.textureSlot = chunk.Neighbors.dirDown,
	});
	cube.quads[chunk.Neighbors.dirUp] = addQuad(.{
		.normal = .{0, 0, 1},
		.corners = .{.{1, 1, 1}, .{1, 0, 1}, .{0, 1, 1}, .{0, 0, 1}},
		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
		.textureSlot = chunk.Neighbors.dirUp,
	});
	fullCube = cubeIndex;

	quadSSBO = graphics.SSBO.initStatic(QuadInfo, quads.items);
	quadSSBO.bind(4);
}

pub fn deinit() void {
	quadSSBO.deinit();
	nameToIndex.deinit();
	for(models.items) |model| {
		main.globalAllocator.free(model.quads);
	}
	models.deinit();
	quads.deinit();
}