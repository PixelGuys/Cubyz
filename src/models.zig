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
	bitPackedData: [modelSize*modelSize*modelSize/8]u32,

	pub fn init(self: *VoxelModel, distributionFunction: *const fn(u16, u16, u16) ?u4) void {
		if(@sizeOf(VoxelModel) != 16 + 16 + modelSize*modelSize*modelSize*4/8) @compileError("Expected Vec3i to have 16 byte alignment.");
		@memset(&self.bitPackedData, 0);
		self.min = @splat(16);
		self.max = @splat(0);
		var x: u16 = 0;
		while(x < modelSize): (x += 1) {
			var y: u16 = 0;
			while(y < modelSize): (y += 1) {
				var z: u16 = 0;
				while(z < modelSize): (z += 1) {
					var isSolid = distributionFunction(x, y, z);
					var voxelIndex = (x << 2*modelShift) + (y << modelShift) + z;
					var shift = 4*@as(u5, @intCast(voxelIndex & 7));
					var arrayIndex = voxelIndex >> 3;
					if(isSolid) |texture| {
						std.debug.assert(texture <= 6);
						self.min = @min(self.min, Vec3i{x, y, z});
						self.max = @max(self.max, Vec3i{x+1, y+1, z+1});
						self.bitPackedData[arrayIndex] |= @as(u32, 6 - texture) << shift;
					} else {
						self.bitPackedData[arrayIndex] |= @as(u32, 7) << shift;
					}
				}
			}
		}
		// TODO: Use floodfill for this.
		var i: u32 = 7;
		while(i < 14) : (i += 1) {
			x = 0;
			while(x < modelSize): (x += 1) {
				var y: u16 = 0;
				while(y < modelSize): (y += 1) {
					var z: u16 = 0;
					outer:
					while(z < modelSize): (z += 1) {
						var voxelIndex = (x << 2*modelShift) + (y << modelShift) + z;
						var shift = 4*@as(u5, @intCast(voxelIndex & 7));
						var arrayIndex = voxelIndex >> 3;
						var data = self.bitPackedData[arrayIndex]>>shift & 15;
						if(data <= i) continue;
						var dx: u2 = 0;
						while(dx < 3) : (dx += 1) {
							if(dx == 0 and x == 0) continue;
							if(dx + x - 1 >= 16) continue;
							var dy: u2 = 0;
							while(dy < 3) : (dy += 1) {
								if(dy == 0 and y == 0) continue;
								if(dy + y - 1 >= 16) continue;
								var dz: u2 = 0;
								while(dz < 3) : (dz += 1) {
									if(dz == 0 and z == 0) continue;
									if(dz + z - 1 >= 16) continue;
									var nx = x + dx - 1;
									var ny = y + dy - 1;
									var nz = z + dz - 1;
									var neighborVoxelIndex = (nx << 2*modelShift) + (ny << modelShift) + nz;
									var neighborShift = 4*@as(u5, @intCast(neighborVoxelIndex & 7));
									var neighborArrayIndex = neighborVoxelIndex >> 3;
									var neighborData = self.bitPackedData[neighborArrayIndex]>>neighborShift & 15;
									if(neighborData < data) continue :outer;
								}
							}
						}
						data += 1;
						self.bitPackedData[arrayIndex] &= ~(@as(u32, 15) << shift);
						self.bitPackedData[arrayIndex] |= @as(u32, data) << shift;
					}
				}
			}
		}
	}
};

fn cube(_: u16, _: u16, _: u16) ?u4 {
	return 6;
}

const Fence = struct {
	fn fence0(_x: u16, _y: u16, _z: u16) ?u4 {
		var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		_ = y;
		if(x < 2 and z < 2) return 6;
		return null;
	}

	fn fence1(_x: u16, _y: u16, _z: u16) ?u4 {
		var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0 and _x < 8) return 6;
		}
		return null;
	}

	fn fence2_neighbor(_x: u16, _y: u16, _z: u16) ?u4 {
		var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0 and _x < 8) return 6;
			if(_z < 8 and x == 0) return 6;
		}
		return null;
	}

	fn fence2_oppose(_x: u16, _y: u16, _z: u16) ?u4 {
		var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0) return 6;
		}
		return null;
	}

	fn fence3(_x: u16, _y: u16, _z: u16) ?u4 {
		var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(z == 0 and _x >= 8) return 6;
			if(x == 0) return 6;
		}
		return null;
	}

	fn fence4(_x: u16, _y: u16, _z: u16) ?u4 {
		var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
		var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
		var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
		if(x < 2 and z < 2) return 6;
		if(y < 5 and y >= 2) {
			if(x == 0 or z == 0) return 6;
		}
		return null;
	}
};

fn log(_x: u16, _y: u16, _z: u16) ?u4 {
	var x = @as(f32, @floatFromInt(_x)) - 7.5;
	var y = @as(f32, @floatFromInt(_y)) - 7.5;
	var z = @as(f32, @floatFromInt(_z)) - 7.5;
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

fn octahedron(_x: u16, _y: u16, _z: u16) ?u4 {
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
	voxelModelSSBO = graphics.SSBO.init();
	voxelModelSSBO.bind(4);

	voxelModels = std.ArrayList(VoxelModel).init(main.threadAllocator);

	nameToIndex = std.StringHashMap(u16).init(main.threadAllocator);

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

	try nameToIndex.put("octahedron", @intCast(voxelModels.items.len));
	(try voxelModels.addOne()).init(octahedron);

	voxelModelSSBO.bufferData(VoxelModel, voxelModels.items);
}

pub fn deinit() void {
	voxelModelSSBO.deinit();
	nameToIndex.deinit();
	voxelModels.deinit();
}