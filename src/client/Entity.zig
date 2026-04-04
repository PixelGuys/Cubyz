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
const EntityModel = main.models.EntityModel;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const BinaryReader = main.utils.BinaryReader;

interpolatedValues: utils.GenericInterpolation(6) = undefined,
_interpolationPos: [6]f64 = undefined,
_interpolationVel: [6]f64 = undefined,

width: f64,
height: f64,

pos: Vec3d = undefined,
rot: Vec3f = undefined,

model: EntityModel = undefined,
nodes: [20]EntityModel.Node = undefined,
matrices: [20]Mat4f = undefined,

id: u32,
name: []const u8,
playerIndex: usize, // TODO extract into own component #2760

pub fn init(self: *@This(), zon: ZonElement, allocator: NeverFailingAllocator) void {
	self.* = @This(){
		.id = zon.get(u32, "id", std.math.maxInt(u32)),
		.width = zon.get(f64, "width", 1),
		.height = zon.get(f64, "height", 1),
		.name = allocator.dupe(u8, zon.get([]const u8, "name", "")),
		.playerIndex = zon.get(usize, "playerIndex", std.math.maxInt(usize)),
	};
	
	self.rot = Vec3f{0, 0, 0};
	self.pos = Vec3d{0, 0, 0};
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


	self.model = main.client.entity_manager.model;
	for (0..self.model.nodeCount) |i| {
		self.nodes[i] = self.model.nodes[i];
	}

	for (0..self.model.nodeCount) |i| {
		self.matrices[i] = getHierarchyMatrix(self.nodes, self.nodes[i]);
	}
}

pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
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

	// var iter = self.model.nodeReverse.keyIterator();
	// while (iter.next()) |k| {
	// std.debug.print("\n\"{s}\"", .{k});
	// }

	// const nodeId = self.model.nodeReverse.get("Head").?;
	
	self.nodes[6].rot = vec.quatFromAxisAngle(Vec3f{1, 0, 0}, self.rot[0]);
	self.matrices[6] = getHierarchyMatrix(self.nodes, self.nodes[6]);
}

fn getHierarchyMatrix(nodes: [20]EntityModel.Node, node: EntityModel.Node) Mat4f {
	var currentMat = Mat4f.translation(Vec3f{
		node.pos[0],
		node.pos[1],
		node.pos[2],
	});
	currentMat = currentMat.mul(Mat4f.rotationQuat(vec.Vec4f{
		node.rot[0],
		node.rot[1],
		node.rot[2],
		node.rot[3],
	}));
	currentMat = currentMat.mul(Mat4f.scale(Vec3f{
		node.scale[0],
		node.scale[1],
		node.scale[2],
	}));

	if (node.parent == null) {
		return currentMat;
	}

	return getHierarchyMatrix(nodes, nodes[node.parent.?]).mul(currentMat);
}

pub fn format(self: *const @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
	if (main.settings.showPlayerIndexWithName) {
		try writer.print("{s}@{d}", .{self.name, self.playerIndex});
	} else {
		try writer.print("{s}", .{self.name});
	}
}
