const std = @import("std");

const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const graphics = @import("graphics.zig");
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec2f = vec.Vec2f;
const FaceData = main.renderer.chunk_meshing.FaceData;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

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
	internalQuads: []u16,
	neighborFacingQuads: [6][]u16,

	fn getFaceNeighbor(quad: *const QuadInfo) ?u3 {
		var allZero: @Vector(3, bool) = .{true, true, true};
		var allOne: @Vector(3, bool) = .{true, true, true};
		for(quad.corners) |corner| {
			allZero = @select(bool, allZero, corner == Vec3f{0, 0, 0}, allZero); // vector and TODO: #14306
			allOne = @select(bool, allOne, corner == Vec3f{1, 1, 1}, allOne); // vector and TODO: #14306
		}
		if(allZero[0]) return Neighbors.dirNegX;
		if(allZero[1]) return Neighbors.dirNegY;
		if(allZero[2]) return Neighbors.dirDown;
		if(allOne[0]) return Neighbors.dirPosX;
		if(allOne[1]) return Neighbors.dirPosY;
		if(allOne[2]) return Neighbors.dirUp;
		return null;
	}

	fn init(self: *Model, allocator: NeverFailingAllocator, quadInfos: []const QuadInfo) void {
		var amounts: [6]usize = .{0, 0, 0, 0, 0, 0};
		var internalAmount: usize = 0;
		for(quadInfos) |*quad| {
			if(getFaceNeighbor(quad)) |neighbor| {
				amounts[neighbor] += 1;
			} else {
				internalAmount += 1;
			}
		}

		for(0..6) |i| {
			self.neighborFacingQuads[i] = allocator.alloc(u16, amounts[i]);
		}
		self.internalQuads = allocator.alloc(u16, internalAmount);

		var indices: [6]usize = .{0, 0, 0, 0, 0, 0};
		var internalIndex: usize = 0;
		for(quadInfos) |_quad| {
			var quad = _quad;
			if(getFaceNeighbor(&quad)) |neighbor| {
				for(&quad.corners) |*corner| {
					corner.* -= quad.normal;
				}
				const quadIndex = addQuad(quad);
				self.neighborFacingQuads[neighbor][indices[neighbor]] = quadIndex;
				indices[neighbor] += 1;
			} else {
				const quadIndex = addQuad(quad);
				self.internalQuads[internalIndex] = quadIndex;
				internalIndex += 1;
			}
		}
	}

	fn deinit(self: *const Model, allocator: NeverFailingAllocator) void {
		for(0..6) |i| {
			allocator.free(self.neighborFacingQuads[i]);
		}
		allocator.free(self.internalQuads);
	}

	fn appendQuadsToList(quadList: []const u16, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		for(quadList) |quadIndex| {
			const texture = main.blocks.meshes.textureIndex(block, quads.items[quadIndex].textureSlot);
			list.append(allocator, FaceData.init(texture, quadIndex, x, y, z, backFace));
		}
	}

	pub fn appendInternalQuadsToList(self: *const Model, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		appendQuadsToList(self.internalQuads, list, allocator, block, x, y, z, backFace);
	}

	pub fn appendNeighborFacingQuadsToList(self: *const Model, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, neighbor: u3, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		appendQuadsToList(self.neighborFacingQuads[neighbor], list, allocator, block, x, y, z, backFace);
	}
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

fn addQuad(info: QuadInfo) u16 { // TODO: Merge duplicates
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
	cube.init(main.globalAllocator, &.{
		.{
			.normal = .{-1, 0, 0},
			.corners = .{.{0, 1, 0}, .{0, 1, 1}, .{0, 0, 0}, .{0, 0, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = chunk.Neighbors.dirNegX,
		},
		.{
			.normal = .{1, 0, 0},
			.corners = .{.{1, 0, 0}, .{1, 0, 1}, .{1, 1, 0}, .{1, 1, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = chunk.Neighbors.dirPosX,
		},
		.{
			.normal = .{0, -1, 0},
			.corners = .{.{0, 0, 0}, .{0, 0, 1}, .{1, 0, 0}, .{1, 0, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = chunk.Neighbors.dirNegY,
		},
		.{
			.normal = .{0, 1, 0},
			.corners = .{.{1, 1, 0}, .{1, 1, 1}, .{0, 1, 0}, .{0, 1, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = chunk.Neighbors.dirPosY,
		},
		.{
			.normal = .{0, 0, -1},
			.corners = .{.{0, 1, 0}, .{0, 0, 0}, .{1, 1, 0}, .{1, 0, 0}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = chunk.Neighbors.dirDown,
		},
		.{
			.normal = .{0, 0, 1},
			.corners = .{.{1, 1, 1}, .{1, 0, 1}, .{0, 1, 1}, .{0, 0, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = chunk.Neighbors.dirUp,
		},
	});
	fullCube = cubeIndex;

	const crossModelIndex: u16 = @intCast(models.items.len);
	nameToIndex.put("cross", crossModelIndex) catch unreachable;
	const cross = models.addOne();
	cross.min = .{0, 0, 0};
	cross.max = .{16, 16, 16};
	cross.init(main.globalAllocator, &.{
		.{
			.normal = .{-std.math.sqrt1_2, std.math.sqrt1_2, 0},
			.corners = .{.{1, 1, 0}, .{1, 1, 1}, .{0, 0, 0}, .{0, 0, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = 0,
		},
		.{
			.normal = .{std.math.sqrt1_2, -std.math.sqrt1_2, 0},
			.corners = .{.{0, 0, 0}, .{0, 0, 1}, .{1, 1, 0}, .{1, 1, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = 0,
		},
		.{
			.normal = .{-std.math.sqrt1_2, -std.math.sqrt1_2, 0},
			.corners = .{.{0, 1, 0}, .{0, 1, 1}, .{1, 0, 0}, .{1, 0, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = 0,
		},
		.{
			.normal = .{std.math.sqrt1_2, std.math.sqrt1_2, 0},
			.corners = .{.{1, 0, 0}, .{1, 0, 1}, .{0, 1, 0}, .{0, 1, 1}},
			.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
			.textureSlot = 0,
		},
	});

	quadSSBO = graphics.SSBO.initStatic(QuadInfo, quads.items);
	quadSSBO.bind(4);
}

pub fn deinit() void {
	quadSSBO.deinit();
	nameToIndex.deinit();
	for(models.items) |model| {
		model.deinit(main.globalAllocator);
	}
	models.deinit();
	quads.deinit();
}