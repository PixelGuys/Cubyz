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
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const c = @import("c");

interpolatedValues: utils.GenericInterpolation(6) = undefined,
_interpolationPos: [6]f64 = undefined,
_interpolationVel: [6]f64 = undefined,

width: f64,
height: f64,

pos: Vec3d = undefined,
rot: Vec3f = undefined,

id: u32,
name: []const u8,
playerIndex: ?usize, // TODO extract into own component #2760

pub fn init(self: *@This(), zon: ZonElement, allocator: NeverFailingAllocator) !void {
	self.* = @This(){
		.id = zon.get(u32, "id", std.math.maxInt(u32)),
		.width = zon.get(f64, "width", 1),
		.height = zon.get(f64, "height", 1),
		.name = allocator.dupe(u8, zon.get([]const u8, "name", "")),
		.playerIndex = zon.get(?usize, "playerIndex", null),
	};
	self._interpolationPos = [_]f64{
		self.pos[0],
		self.pos[1],
		self.pos[2],
		@floatCast(self.rot[0]),
		@floatCast(self.rot[1]),
		@floatCast(self.rot[2]),
	};
	self._interpolationVel = @splat(0);
	self.interpolatedValues.init(&self._interpolationPos, &self._interpolationVel);

	if (zon.getChildOrNull("components")) |components| {
		try main.entity.loadComponentsFromBase64(components.as([]const u8, ""), self.id, .client);
	}
}

pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
	main.entity.client.removeAllComponents(self.id);
	allocator.free(self.name);
}

pub fn getRenderPosition(self: *const @This()) Vec3d {
	return Vec3d{self.pos[0], self.pos[1], self.pos[2]};
}

pub fn updatePosition(self: *@This(), pos: *const [6]f64, vel: *const [6]f64, time: i16) void {
	self.interpolatedValues.updatePosition(pos, vel, time);
}

pub fn update(self: *@This(), time: i16, lastTime: i16) void {
	self.interpolatedValues.update(time, lastTime);
	self.pos[0] = self.interpolatedValues.outPos[0];
	self.pos[1] = self.interpolatedValues.outPos[1];
	self.pos[2] = self.interpolatedValues.outPos[2];
	self.rot[0] = @floatCast(self.interpolatedValues.outPos[3]);
	self.rot[1] = @floatCast(self.interpolatedValues.outPos[4]);
	self.rot[2] = @floatCast(self.interpolatedValues.outPos[5]);
}

pub fn format(self: *const @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
	if (main.settings.showPlayerIndexWithName and self.playerIndex != null) {
		try self.formatWithPlayerIndex(writer);
	} else {
		try writer.print("{s}", .{self.name});
	}
}

pub fn formatWithPlayerIndex(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
	std.debug.assert(self.playerIndex != null);
	try writer.print("{s}@{d}", .{self.name, self.playerIndex.?});
}
