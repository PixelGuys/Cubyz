const std = @import("std");

const main = @import("main");

const list = @import("heightmapOps");

pub const HeightmapOp = struct {
	run: *const fn(roughnessValue: f32, hillsValue: f32, mountainsValue: f32, roughness: f32, hills: f32, mountains: f32) f32,
};

var heightmapOps: std.StringHashMap(HeightmapOp) = undefined;

// MARK: init/register

pub fn init() void {
	heightmapOps = .init(main.globalAllocator.allocator);
	inline for(@typeInfo(list).@"struct".decls) |declaration| {
		register(declaration.name, @field(list, declaration.name));
	}
}

pub fn deinit() void {
	heightmapOps.deinit();
}

pub fn getByID(id: []const u8) *HeightmapOp {
	if(heightmapOps.getPtr(id)) |mode| return mode;
	std.log.err("Could not find heightmapOp {s}. Using cubyz:default instead.", .{id});
	return heightmapOps.getPtr("cubyz:default").?;
}

pub fn register(comptime id: []const u8, comptime Op: type) void {
	const result: HeightmapOp = HeightmapOp{.run = Op.run};
	heightmapOps.putNoClobber(id, result) catch unreachable;
}
