const std = @import("std");

const graphics = @import("graphics.zig");
const main = @import("main.zig");

var voxelModelSSBO: graphics.SSBO = undefined;

pub const paletteSize: u4 = 8;
pub const modelShift: u4 = 4;
pub const modelSize: u16 = @as(u16, 1) << modelShift;
pub const modelMask: u16 = modelSize - 1;

const VoxelModel = extern struct {
	minX: u32,
	maxX: u32,
	minY: u32,
	maxY: u32,
	minZ: u32,
	maxZ: u32,
	bitPackedData: [modelSize*modelSize*modelSize/8]u32,

	pub fn init(self: *VoxelModel, distributionFunction: *const fn(u16, u16, u16) ?u4) void {
		std.mem.set(u32, &self.bitPackedData, 0);
		self.minX = 16;
		self.minY = 16;
		self.minZ = 16;
		self.maxX = 0;
		self.maxY = 0;
		self.maxZ = 0;
		var x: u16 = 0;
		while(x < modelSize): (x += 1) {
			var y: u16 = 0;
			while(y < modelSize): (y += 1) {
				var z: u16 = 0;
				while(z < modelSize): (z += 1) {
					var isSolid = distributionFunction(x, y, z);
					var voxelIndex = (x << 2*modelShift) + (y << modelShift) + z;
					var shift = 4*@intCast(u5, voxelIndex & 7);
					var arrayIndex = voxelIndex >> 3;
					if(isSolid) |palette| {
						std.debug.assert(palette < paletteSize);
						self.minX = @min(self.minX, x);
						self.minY = @min(self.minY, y);
						self.minZ = @min(self.minZ, z);
						self.maxX = @max(self.maxX, x+1);
						self.maxY = @max(self.maxY, y+1);
						self.maxZ = @max(self.maxZ, z+1);
						self.bitPackedData[arrayIndex] |= @as(u32, paletteSize - 1 - palette) << shift;
					} else {
						self.bitPackedData[arrayIndex] |= @as(u32, paletteSize) << shift;
					}
				}
			}
		}
		// TODO: Use floodfill for this.
		var i: u32 = paletteSize;
		while(i < 14) : (i += 1) {
			x = 0;
			while(x < modelSize): (x += 1) {
				var y: u16 = 0;
				while(y < modelSize): (y += 1) {
					var z: u16 = 0;
					outer:
					while(z < modelSize): (z += 1) {
						var voxelIndex = (x << 2*modelShift) + (y << modelShift) + z;
						var shift = 4*@intCast(u5, voxelIndex & 7);
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
									var neighborShift = 4*@intCast(u5, neighborVoxelIndex & 7);
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
	return 0;
}

fn fence(_x: u16, _y: u16, _z: u16) ?u4 {
	var x = @max(@as(i32, _x)-8, -@as(i32, _x)+7);
	var y = @max(@as(i32, _y)-8, -@as(i32, _y)+7);
	var z = @max(@as(i32, _z)-8, -@as(i32, _z)+7);
	if(x < 2 and z < 2) return 0;
	if(y < 5 and y >= 2) {
		if(x == 0 or z == 0) return 0;
	}
	return null;
}

fn log(_x: u16, _y: u16, _z: u16) ?u4 {
	var x = @intToFloat(f32, _x) - 7.5;
	var y = @intToFloat(f32, _y) - 7.5;
	var z = @intToFloat(f32, _z) - 7.5;
	_ = y;
	if(x*x + z*z < 5.5*5.5) return 0;
	if(x*x + z*z < 6.5*6.5) return 1;
	return null;
}

fn octahedron(_x: u16, _y: u16, _z: u16) ?u4 {
	var x = _x;
	var y = _y;
	var z = _z;
	if((x == 0 or x == 15) and (y == 0 or y == 15)) return 0;
	if((x == 0 or x == 15) and (z == 0 or z == 15)) return 0;
	if((z == 0 or z == 15) and (y == 0 or y == 15)) return 0;
	x = @min(x, 15 - x);
	y = @min(y, 15 - y);
	z = @min(z, 15 - z);
	if(x + y + z > 16) return 0;
	return null;
}

var nameToIndex: std.StringHashMap(u16) = undefined;

pub fn getModelIndex(string: []const u8) u16 {
	return nameToIndex.get(string) orelse {
		std.log.err("Couldn't find voxelModel with name: {s}.", .{string});
		return 0;
	};
}

pub var voxelModels: std.ArrayList(VoxelModel) = undefined;

// TODO: Allow loading from world assets.
// TODO: Editable player models.
pub fn init() !void {
	voxelModelSSBO = graphics.SSBO.init();
	voxelModelSSBO.bind(4);

	voxelModels = std.ArrayList(VoxelModel).init(main.threadAllocator);

	nameToIndex = std.StringHashMap(u16).init(main.threadAllocator);

	try nameToIndex.put("cube", @intCast(u16, voxelModels.items.len));
	(try voxelModels.addOne()).init(cube);

	try nameToIndex.put("log", @intCast(u16, voxelModels.items.len));
	(try voxelModels.addOne()).init(log);

	try nameToIndex.put("fence", @intCast(u16, voxelModels.items.len));
	(try voxelModels.addOne()).init(fence);

	try nameToIndex.put("octahedron", @intCast(u16, voxelModels.items.len));
	(try voxelModels.addOne()).init(octahedron);

	voxelModelSSBO.bufferData(VoxelModel, voxelModels.items);
}

pub fn deinit() void {
	voxelModelSSBO.deinit();
	nameToIndex.deinit();
	voxelModels.deinit();
}