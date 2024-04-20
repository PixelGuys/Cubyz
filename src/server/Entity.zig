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

fn loadVec3f(json: JsonElement) Vec3f {
	return .{
		json.get(f32, "x", 0),
		json.get(f32, "y", 0),
		json.get(f32, "z", 0),
	};
}

fn loadVec3d(json: JsonElement) Vec3d {
	return .{
		json.get(f64, "x", 0),
		json.get(f64, "y", 0),
		json.get(f64, "z", 0),
	};
}

fn saveVec3(allocator: NeverFailingAllocator, vector: anytype) JsonElement {
	const json = JsonElement.initObject(allocator);
	json.put("x", vector[0]);
	json.put("y", vector[1]);
	json.put("z", vector[2]);
	return json;
}

pub fn loadFrom(self: *@This(), json: JsonElement) void {
	self.pos = loadVec3d(json.getChild("position"));
	self.vel = loadVec3d(json.getChild("velocity"));
	self.rot = loadVec3f(json.getChild("rotation"));
}

pub fn save(self: *@This(), allocator: NeverFailingAllocator) JsonElement {
	const json = JsonElement.initObject(allocator);
	json.put("position", saveVec3(allocator, self.pos));
	json.put("velocity", saveVec3(allocator, self.vel));
	json.put("rotation", saveVec3(allocator, self.rot));
	return json;
}
