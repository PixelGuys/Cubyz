const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Side = enum { ClientSide, ServerSide };

pos: Vec3d = .{0, 0, 0},
vel: Vec3d = .{0, 0, 0},
rot: Vec3f = .{0, 0, 0},

health: f32 = 8,
maxHealth: f32 = 8,
energy: f32 = 8,
maxEnergy: f32 = 8,
inUse: bool = false,
name: ?[]const u8 = null,
id: u32 = 0,

pub fn loadFrom(self: *@This(), id: u32, zon: ZonElement, comptime side: main.sync.Side) !void {
	self.id = id;
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.energy = zon.get(f32, "energy", self.maxEnergy);
	if (zon.getChildOrNull("components")) |components| {
		try main.entity.loadComponentsFromBase64(components.as([]const u8, ""), self.id, side);
	}

	if (zon.getChildOrNull("name")) |name| {
		if (self.name) |oldname| {
			main.globalAllocator.free(oldname);
		}
		self.name = main.globalAllocator.dupe(u8, name.as([]const u8, "invalid name"));
	}
}
pub fn clone(self: *@This(), copy: *@This()) void {
	const originalID = copy.id;
	if(copy.name)|name|{
		main.globalAllocator.free(name);
	}
	copy.* = self.*;
	copy.name = if (self.name) |name| main.globalAllocator.dupe(u8, name) else null;
	copy.id = originalID;
}

pub fn save(self: *const @This(), allocator: NeverFailingAllocator, audience: main.entity.AudienceInfo) ZonElement {
	const zon = ZonElement.initObject(allocator);
	zon.put("position", self.pos);
	zon.put("velocity", self.vel);
	zon.put("rotation", self.rot);
	zon.put("health", self.health);
	zon.put("energy", self.energy);
	zon.put("id", self.id);

	var base64 = main.entity.server.componentsToBase64(allocator, self.id, audience);
	defer base64.deinit(allocator);
	zon.putOwnedString("components", base64.getEncodedMessage());

	if (self.name) |name|
		zon.put("name", name);
	return zon;
}
pub fn deinit(self: *@This(), comptime side: main.sync.Side) void {
	if (self.name) |name| {
		main.globalAllocator.free(name);
		self.name = null;
	}
	if (side == .server) {
		main.entity.server.removeAllComponents(self.id);
	}
}
