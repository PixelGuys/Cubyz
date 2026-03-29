const std = @import("std");
const main = @import("main.zig");
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

pub const components = @import("entityComponent/_list.zig");
pub const systems = @import("entitySystem/_list.zig");

pub const EntityNetworkData = struct {
	id: u32,
	pos: Vec3d,
	vel: Vec3d,
	rot: Vec3f,
};
pub const Side = enum { ClientSide, ServerSide };

// Analogous to Protocols.
const EntityComponentVTable = struct {
	server: *const fn (id: u32, reader: *main.utils.BinaryReader, version: u32) anyerror!void,
	client: *const fn (id: u32, reader: *main.utils.BinaryReader, version: u32) anyerror!void,
};
var receiveList: [256]?EntityComponentVTable = @splat(null);

pub fn initComponent() void {
	inline for (@typeInfo(components).@"struct".decls) |decl| {
		@field(components, decl.name).client.init();
		const id = @field(components, decl.name).entityComponentID;
		if (receiveList[id] == null) {
			receiveList[id] = .{
				.server = @field(components, decl.name).server.loadFromData,
				.client = @field(components, decl.name).client.load,
			};
		} else {
			std.log.err("entity components: Duplicate list id {}.", .{id});
		}
	}
}
pub fn deinitComponent() void {
	receiveList = @splat(null);
}

pub const client = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).client.init();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.init();
		}
		main.client.entity_manager.init();
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).client.deinit();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.deinit();
		}
		main.client.entity_manager.deinit();
	}
	pub fn clear() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.clear();
		}
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).client.clear();
		}
		main.client.entity_manager.clear();
	}
};
pub const server = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).server.init();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decls) |decl| {
			@field(components, decl.name).server.deinit();
		}
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.deinit();
		}
	}
	pub fn update() void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).server.update();
		}
	}
	pub fn componentsToBase64(allocator: main.heap.NeverFailingAllocator, entityID: u32, audience: main.entity.AudienceInfo) main.utils.Base64 {
		var writer = main.utils.BinaryWriter.init(allocator);
		defer writer.deinit();

		inline for (@typeInfo(main.entity.components).@"struct".decls) |decl| {
			if (@field(main.entity.components, decl.name).server.get(entityID)) |component| {
				var writerComponent = main.utils.BinaryWriter.init(allocator);
				defer writerComponent.deinit();

				if (component.save(&writerComponent, audience)) {
					writer.writeVarInt(u32, @field(main.entity.components, decl.name).entityComponentID);
					writer.writeVarInt(u32, @field(main.entity.components, decl.name).entityComponentVersion);
					writer.writeSliceWithSize(writerComponent.data.items);
				}
			}
		}
		const base64 = main.utils.Base64.toBase64(allocator, writer.data.items);
		return base64;
	}

	pub fn componentsRemoveAll(id: u32) void {
		const list = main.entity.components;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			@field(list, decl.name).server.unload(id);
		}
	}
};

pub fn loadComponentsFromBase64(base64Data: []const u8, id: u32, comptime side: Side) void {
	if (main.utils.fromBase64(main.stackAllocator, base64Data) catch null) |data| {
		defer main.stackAllocator.free(data);

		var reader = main.utils.BinaryReader.init(data);
		while (reader.remaining.len != 0) {
			const componentID: u32 = reader.readVarInt(u32) catch @panic("Couldn't read componentID correctly.");
			const componentVersion: u32 = reader.readVarInt(u32) catch @panic("Couldn't read componentVersion correctly.");
			const componentData = reader.readSliceWithSize() catch @panic("Couldn't read ComponentData");

			var componentReader = main.utils.BinaryReader.init(componentData);
			if (receiveList[componentID]) |vtable| {
				switch (side) {
					.ServerSide => vtable.server(id, &componentReader, componentVersion) catch @panic("Couldn't parse componentData (server side)"),
					.ClientSide => vtable.client(id, &componentReader, componentVersion) catch @panic("Couldn't parse componentData (client side)"),
				}
			} else {
				std.log.err("unknown Component ID {} ", .{componentID});
			}
		}
	}
}

// Depending on who the audience is, we want to serialize different informations.
pub const AudienceInfo = enum {
	disk,
	playerHimself,
	playerNearby,
	playerFaraway,
};
