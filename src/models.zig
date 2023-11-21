const std = @import("std");

const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const graphics = @import("graphics.zig");
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;

var voxelModelSSBO: graphics.SSBO = undefined;

pub const modelShift: u4 = 4;
pub const modelSize: u16 = @as(u16, 1) << modelShift;
pub const modelMask: u16 = modelSize - 1;

const VoxelModel = extern struct {
	min: Vec3i,
	max: Vec3i,
	bitPackedData: [modelSize*modelSize*modelSize/32]u32,
	bitPackedTexture: [modelSize*modelSize*modelSize/8]u32,

	pub fn init(self: *VoxelModel, distributionFunction: *const fn(u4, u4, u4) ?u4) void {
		if(@sizeOf(VoxelModel) != 16 + 16 + modelSize*modelSize*modelSize*4/32 + modelSize*modelSize*modelSize*4/8) @compileError("Expected Vec3i to have 16 byte alignment.");
		@memset(&self.bitPackedData, 0);
		@memset(&self.bitPackedTexture, 0);
		self.min = @splat(16);
		self.max = @splat(0);
		for(0..modelSize) |_x| {
			const x: u4 = @intCast(_x);
			for(0..modelSize) |_y| {
				const y: u4 = @intCast(_y);
				for(0..modelSize) |_z| {
					const z: u4 = @intCast(_z);
					const isSolid = distributionFunction(x, y, z);
					const voxelIndex = (_x << 2*modelShift) + (_y << modelShift) + _z;
					const shift = @as(u5, @intCast(voxelIndex & 31));
					const arrayIndex = voxelIndex >> 5;
					const shiftTexture = 4*@as(u5, @intCast(voxelIndex & 7));
					const arrayIndexTexture = voxelIndex >> 3;
					if(isSolid) |texture| {
						std.debug.assert(texture <= 6);
						self.min = @min(self.min, Vec3i{x, y, z});
						self.max = @max(self.max, Vec3i{x, y, z});
						self.bitPackedData[arrayIndex] &= ~(@as(u32, 1) << shift);
						self.bitPackedTexture[arrayIndexTexture] |= @as(u32, texture) << shiftTexture;
					} else {
						self.bitPackedData[arrayIndex] |= @as(u32, 1) << shift;
					}
				}
			}
		}
		self.max += @splat(1);
	}
};

fn cube(_: u4, _: u4, _: u4) ?u4 {
	return 6;
}

const Fence = struct {
	fn fence0(_x: u4, _y: u4, _z: u4) ?u4 {
		const x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		const y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		const z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		_ = y;
		if(x < 2 and z < 2) return 6;
		return null;
	}

	fn fence1(_x: u4, _y: u4, _z: u4) ?u4 {
		const x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		const y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		const z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0 and _x < 8) return 6;
		}
		return null;
	}

	fn fence2_neighbor(_x: u4, _y: u4, _z: u4) ?u4 {
		const x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		const y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		const z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0 and _x < 8) return 6;
			if(_z < 8 and x == 0) return 6;
		}
		return null;
	}

	fn fence2_oppose(_x: u4, _y: u4, _z: u4) ?u4 {
		const x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		const y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		const z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0) return 6;
		}
		return null;
	}

	fn fence3(_x: u4, _y: u4, _z: u4) ?u4 {
		const x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		const y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		const z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0 and _x >= 8) return 6;
			if(x == 0) return 6;
		}
		return null;
	}

	fn fence4(_x: u4, _y: u4, _z: u4) ?u4 {
		const x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		const y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		const z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(x == 0 or z == 0) return 6;
		}
		return null;
	}
};

fn log(_x: u4, _y: u4, _z: u4) ?u4 {
	const x = @as(f32, @floatFromInt(_x)) - 7.5;
	const y = @as(f32, @floatFromInt(_y)) - 7.5;
	const z = @as(f32, @floatFromInt(_z)) - 7.5;
	if(x*x + z*z < 7.2*7.2) {
		if(y > 0) return Neighbors.dirUp;
		return Neighbors.dirDown;
	}
	if(x*x + z*z < 8.0*8.0) {
		if(@abs(x) > @abs(z)) {
			if(x < 0) return Neighbors.dirNegX;
			return Neighbors.dirPosX;
		} else {
			if(z < 0) return Neighbors.dirNegZ;
			return Neighbors.dirPosZ;
		}
	}
	return null;
}

fn sphere(_x: u4, _y: u4, _z: u4) ?u4 {
	const x = @as(f32, @floatFromInt(_x)) - 7.5;
	const y = @as(f32, @floatFromInt(_y)) - 7.5;
	const z = @as(f32, @floatFromInt(_z)) - 7.5;
	if(x*x + y*y + z*z < 8.0*8.0) {
		return 6;
	}
	return null;
}

fn grass(x: u4, y: u4, z: u4) ?u4 {
	var seed = main.random.initSeed2D(542642, .{x, z});
	var val = main.random.nextFloat(&seed);
	val *= val*16;
	if(val > @as(f32, @floatFromInt(y))) {
		return 6;
	}
	return null;
}

fn octahedron(_x: u4, _y: u4, _z: u4) ?u4 {
	var x = _x;
	var y = _y;
	var z = _z;
	if((x == 0 or x == 15) and (y == 0 or y == 15)) return 6;
	if((x == 0 or x == 15) and (z == 0 or z == 15)) return 6;
	if((z == 0 or z == 15) and (y == 0 or y == 15)) return 6;
	x = @min(x, 15 - x);
	y = @min(y, 15 - y);
	z = @min(z, 15 - z);
	if(x + y + z > 16) return 6;
	return null;
}

var nameToIndex: std.StringHashMap(u16) = undefined;

pub fn getModelIndex(string: []const u8) u16 {
	return nameToIndex.get(string) orelse {
		std.log.warn("Couldn't find voxelModel with name: {s}.", .{string});
		return 0;
	};
}

pub var voxelModels: std.ArrayList(VoxelModel) = undefined;
pub var fullCube: u16 = 0;

// TODO: Allow loading from world assets.
// TODO: Editable player models.
pub fn init() !void {
	voxelModels = std.ArrayList(VoxelModel).init(main.globalAllocator);

	nameToIndex = std.StringHashMap(u16).init(main.globalAllocator);

	try nameToIndex.put("cube", @intCast(voxelModels.items.len));
	fullCube = @intCast(voxelModels.items.len);
	(try voxelModels.addOne()).init(cube);

	try nameToIndex.put("log", @intCast(voxelModels.items.len));
	(try voxelModels.addOne()).init(log);

	try nameToIndex.put("fence", @intCast(voxelModels.items.len));
	(try voxelModels.addOne()).init(Fence.fence0);
	(try voxelModels.addOne()).init(Fence.fence1);
	(try voxelModels.addOne()).init(Fence.fence2_neighbor);
	(try voxelModels.addOne()).init(Fence.fence2_oppose);
	(try voxelModels.addOne()).init(Fence.fence3);
	(try voxelModels.addOne()).init(Fence.fence4);

	try nameToIndex.put("sphere", @intCast(voxelModels.items.len));
	(try voxelModels.addOne()).init(sphere);

	try nameToIndex.put("grass", @intCast(voxelModels.items.len));
	(try voxelModels.addOne()).init(grass);

	try nameToIndex.put("octahedron", @intCast(voxelModels.items.len));
	(try voxelModels.addOne()).init(octahedron);

	voxelModelSSBO = graphics.SSBO.initStatic(VoxelModel, voxelModels.items);
	voxelModelSSBO.bind(4);
}

pub fn deinit() void {
	voxelModelSSBO.deinit();
	nameToIndex.deinit();
	voxelModels.deinit();
}