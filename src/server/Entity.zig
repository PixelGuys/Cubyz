const std = @import("std");

const main = @import("root");
const JsonElement = main.JsonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pos: Vec3d = .{0, 0, 0},
vel: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},
// TODO: Health and hunger
// TODO: Name

pub fn loadFrom(self: *@This(), json: JsonElement) void {
	self.pos = json.get(Vec3d, "position", .{0, 0, 0});
	self.vel = json.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = json.get(Vec3f, "rotation", .{0, 0, 0});
}

pub fn save(self: *@This(), allocator: NeverFailingAllocator) JsonElement {
	const json = JsonElement.initObject(allocator);
	json.put("position", self.pos);
	json.put("velocity", self.vel);
	json.put("rotation", self.rot);
	return json;
}
