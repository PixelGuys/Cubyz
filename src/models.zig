const std = @import("std");

const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const graphics = @import("graphics.zig");
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;

var modelSSBO: graphics.SSBO = undefined;

const Model = extern struct {
	min: Vec3i, // TODO: Should contain a list of quads instead, with vertex positions.
	max: Vec3i,
	// TODO
};

var nameToIndex: std.StringHashMap(u16) = undefined;

pub fn getModelIndex(string: []const u8) u16 {
	return nameToIndex.get(string) orelse {
		std.log.warn("Couldn't find voxelModel with name: {s}.", .{string});
		return 0;
	};
}

pub var models: std.ArrayList(Model) = undefined;
pub var fullCube: u16 = 0;

// TODO: Allow loading from world assets.
// TODO: Entity models.
pub fn init() void {
	models = std.ArrayList(Model).init(main.globalAllocator.allocator);

	nameToIndex = std.StringHashMap(u16).init(main.globalAllocator.allocator);

	nameToIndex.put("cube", @intCast(models.items.len)) catch unreachable;
	fullCube = @intCast(models.items.len);
	models.append(.{.min = .{0, 0, 0}, .max = .{16, 16, 16}}) catch unreachable;

	modelSSBO = graphics.SSBO.initStatic(Model, models.items);
	modelSSBO.bind(4);
}

pub fn deinit() void {
	modelSSBO.deinit();
	nameToIndex.deinit();
	models.deinit();
}