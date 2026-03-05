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
// TODO: Name

pub fn loadFrom(self: *@This(), id: u32, zon: ZonElement, comptime side: Side) void {
	self.id = id;
	self.pos = zon.get(Vec3d, "position", .{0, 0, 0});
	self.vel = zon.get(Vec3d, "velocity", .{0, 0, 0});
	self.rot = zon.get(Vec3f, "rotation", .{0, 0, 0});
	self.health = zon.get(f32, "health", self.maxHealth);
	self.energy = zon.get(f32, "energy", self.maxEnergy);
	if (zon.getChildOrNull("components")) |components| {
		const list = main.entityComponent;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			if (components.get(?[]const u8, decl.name, null)) |base64| {
				if (main.utils.fromBase64(main.stackAllocator, base64) catch null) |data| {
					defer main.stackAllocator.free(data);

					var reader = main.utils.BinaryReader.init(data);
					const version = reader.readVarInt(u32) catch std.math.maxInt(u32);

					if (side == .ServerSide) {
						@field(list, decl.name).Server.registerFromData(id, &reader, version);
					} else if (side == .ClientSide) {
						@field(list, decl.name).Client.register(id, &reader, version);
					}
				}
			}
		}
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
	copy.* = self.*;
	copy.name = if (self.name) |name| main.globalAllocator.dupe(u8, name) else null;
	copy.id = originalID;
}

pub fn save(self: *const @This(), allocator: NeverFailingAllocator) ZonElement {
	const zon = ZonElement.initObject(allocator);
	zon.put("position", self.pos);
	zon.put("velocity", self.vel);
	zon.put("rotation", self.rot);
	zon.put("health", self.health);
	zon.put("energy", self.energy);
	const components = ZonElement.initObject(allocator);
	{
		const list = main.entityComponent;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			if (@field(list, decl.name).Server.get(self.id)) |component| {
				var writer = main.utils.BinaryWriter.init(allocator);
				defer writer.deinit();

				writer.writeVarInt(u32, @field(list, decl.name).ENTITY_COMPONENT_VERSION);
				component.save(&writer);

				var base64 = main.utils.Base64.toBase64(allocator, writer.data.items);
				defer base64.deinit(allocator);

				components.putOwnedString(decl.name, base64.getEncodedMessage());
			}
		}
	}
	zon.put("components", components);

	if (self.name) |name|
		zon.put("name", name);
	return zon;
}
pub fn deinit(self: *@This(), comptime side: Side) void {
	if (self.name) |name| {
		main.globalAllocator.free(name);
		self.name = null;
	}
	if (side == .ServerSide) {
		const list = main.entityComponent;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			@field(list, decl.name).Server.unregister(self.id);
		}
	}
}
