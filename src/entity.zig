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

pub const EntityComponentLoadError = error{
	DecodingBase64,
	UnreadableId,
	UnreadableVersion,
	UnreadableComponentData,
	UnknownComponentId,
	InvalidComponentVersion,
};
pub const Entity = enum(u32) {
	noValue = std.math.maxInt(u32),
	_,
};
pub const EntityComponentId = u32;
const EntityComponentVTable = struct {
	serverLoad: *const fn (entityId: u32, reader: *main.utils.BinaryReader, version: u32) EntityComponentLoadError!void,
	clientLoad: *const fn (entityId: u32, reader: *main.utils.BinaryReader, version: u32) EntityComponentLoadError!void,
	serverUnload: *const fn (entityId: u32) void,
	clientUnload: *const fn (entityId: u32) void,
};
var componentList: []?EntityComponentVTable = undefined;

pub fn initComponents() void {
	var tmpComponentList: main.ListUnmanaged(?EntityComponentVTable) = .{};
	inline for (@typeInfo(components).@"struct".decls) |decl| {
		@field(components, decl.name).client.init();
		const componentId = @field(components, decl.name).entityComponentID;

		if (tmpComponentList.items.len <= componentId) {
			tmpComponentList.appendNTimes(main.worldArena, null, componentId + 1 - tmpComponentList.items.len);
		}
		if (tmpComponentList.items[componentId] == null) {
			tmpComponentList.items[componentId] = .{
				.serverLoad = @field(components, decl.name).server.loadFromData,
				.clientLoad = @field(components, decl.name).client.load,
				.serverUnload = @field(components, decl.name).server.unload,
				.clientUnload = @field(components, decl.name).client.unload,
			};
		} else {
			std.log.err("entity components: Duplicate list id {}.", .{componentId});
		}
	}
	componentList = tmpComponentList.items;
}
pub fn deinitComponents() void {
	componentList = undefined;
}
pub fn loadComponent(comptime side: main.sync.Side, componentId: EntityComponentId, entityId: u32, componentData: []const u8, componentVersion: u32) EntityComponentLoadError!void {
	if (componentId >= componentList.len) {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
	var componentReader = main.utils.BinaryReader.init(componentData);
	if (componentList[componentId]) |vtable| {
		switch (side) {
			.server => vtable.serverLoad(entityId, &componentReader, componentVersion) catch |err| {
				return err;
			},
			.client => vtable.clientLoad(entityId, &componentReader, componentVersion) catch |err| {
				return err;
			},
		}
	} else {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
}
pub fn unloadComponent(comptime side: main.sync.Side, componentId: EntityComponentId, entityId: u32) EntityComponentLoadError!void {
	if (componentId >= componentList.len) {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
	if (componentList[componentId]) |vtable| {
		switch (side) {
			.server => vtable.serverUnload(entityId),
			.client => vtable.clientUnload(entityId),
		}
	} else {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
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
	pub fn removeAllComponents(id: u32) void {
		const list = main.entity.components;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			@field(list, decl.name).client.unload(id);
		}
	}
	pub fn render(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d, deltaTime: f64) void {
		main.client.entity_manager.update();
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.render(projMatrix, ambientLight, playerPos, deltaTime);
		}
	}
	pub fn renderHud(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
		inline for (@typeInfo(systems).@"struct".decls) |decl| {
			@field(systems, decl.name).client.renderHud(projMatrix, ambientLight, playerPos);
		}
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
	pub fn componentsToBase64(allocator: main.heap.NeverFailingAllocator, entityId: u32, audience: main.entity.AudienceInfo) main.utils.Base64 {
		var writer = main.utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();

		inline for (@typeInfo(main.entity.components).@"struct".decls) |decl| {
			if (@field(main.entity.components, decl.name).server.get(entityId)) |component| {
				var writerComponent = main.utils.BinaryWriter.init(main.stackAllocator);
				defer writerComponent.deinit();

				if (component.save(&writerComponent, audience) == .save) {
					writer.writeVarInt(u32, @field(main.entity.components, decl.name).entityComponentID);
					writer.writeVarInt(u32, @field(main.entity.components, decl.name).entityComponentVersion);
					writer.writeSliceWithSize(writerComponent.data.items);
				}
			}
		}
		return main.utils.Base64.toBase64(allocator, writer.data.items);
	}

	pub fn removeAllComponents(entityId: u32) void {
		const list = main.entity.components;
		inline for (@typeInfo(list).@"struct".decls) |decl| {
			@field(list, decl.name).server.unload(entityId);
		}
	}
};

pub fn loadComponentsFromBase64(base64Data: []const u8, entityId: u32, comptime side: main.sync.Side) EntityComponentLoadError!void {
	const data = main.utils.fromBase64(main.stackAllocator, base64Data) catch return EntityComponentLoadError.DecodingBase64;
	defer main.stackAllocator.free(data);

	var reader = main.utils.BinaryReader.init(data);
	var lastError: EntityComponentLoadError!void = {};
	while (reader.remaining.len != 0) {
		const componentId: EntityComponentId = reader.readVarInt(EntityComponentId) catch return EntityComponentLoadError.UnreadableId;
		const componentVersion: u32 = reader.readVarInt(u32) catch return EntityComponentLoadError.UnreadableVersion;
		const componentData = reader.readSliceWithSize() catch return EntityComponentLoadError.UnreadableComponentData;

		lastError = loadComponent(side, componentId, entityId, componentData, componentVersion);
	}
	return lastError;
}

// Depending on who the audience is, we want to serialize different informations.
pub const AudienceInfo = enum {
	disk,
	playerHimself,
	playerNearby,
	playerFaraway,
};

pub const ComponentSaveBehaviour = enum {
	save,
	discard,
};
