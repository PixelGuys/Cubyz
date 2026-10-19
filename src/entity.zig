const std = @import("std");
const main = @import("main.zig");
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

pub const components = @import("entityComponent/_list.zig");

pub const EntityNetworkData = struct {
	id: main.entity.Entity,
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
	serverLoad: *const fn (entity: Entity, reader: *main.utils.BinaryReader, version: u32) EntityComponentLoadError!void,
	clientLoad: *const fn (entity: Entity, reader: *main.utils.BinaryReader, version: u32) EntityComponentLoadError!void,
	serverUnload: *const fn (entity: Entity) void,
	clientUnload: *const fn (entity: Entity) void,
};
var componentList: []?EntityComponentVTable = undefined;

pub fn initComponents() void {
	var tmpComponentList: main.List(?EntityComponentVTable) = .empty;
	inline for (@typeInfo(components).@"struct".decl_names) |decl| {
		@field(components, decl).client.init();
		const componentId = @field(components, decl).entityComponentID;

		if (tmpComponentList.items.len <= componentId) {
			tmpComponentList.appendNTimes(main.worldArena, null, componentId + 1 - tmpComponentList.items.len);
		}
		if (tmpComponentList.items[componentId] == null) {
			tmpComponentList.items[componentId] = .{
				.serverLoad = @field(components, decl).server.loadFromData,
				.clientLoad = @field(components, decl).client.load,
				.serverUnload = @field(components, decl).server.unload,
				.clientUnload = @field(components, decl).client.unload,
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
pub fn loadComponent(comptime side: main.sync.Side, componentId: EntityComponentId, entity: Entity, componentData: []const u8, componentVersion: u32) EntityComponentLoadError!void {
	if (componentId >= componentList.len) {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
	var componentReader = main.utils.BinaryReader.init(componentData);
	if (componentList[componentId]) |vtable| {
		switch (side) {
			.server => vtable.serverLoad(entity, &componentReader, componentVersion) catch |err| {
				return err;
			},
			.client => vtable.clientLoad(entity, &componentReader, componentVersion) catch |err| {
				return err;
			},
		}
	} else {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
}
pub fn unloadComponent(comptime side: main.sync.Side, componentId: EntityComponentId, entity: Entity) EntityComponentLoadError!void {
	if (componentId >= componentList.len) {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
	if (componentList[componentId]) |vtable| {
		switch (side) {
			.server => vtable.serverUnload(entity),
			.client => vtable.clientUnload(entity),
		}
	} else {
		std.log.err("unknown Component Id {} ", .{componentId});
		return error.UnknownComponentId;
	}
}

pub const client = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decl_names) |decl| {
			@field(components, decl).client.init();
		}
		main.client.entity_manager.init();
	}
	pub fn deinit() void {
		main.client.entity_manager.deinit();
		inline for (@typeInfo(components).@"struct".decl_names) |decl| {
			@field(components, decl).client.deinit();
		}
	}
	pub fn clear() void {
		main.client.entity_manager.clear();
		inline for (@typeInfo(components).@"struct".decl_names) |decl| {
			@field(components, decl).client.clear();
		}
	}
	pub fn removeAllComponents(entity: Entity) void {
		const list = main.entity.components;
		inline for (@typeInfo(list).@"struct".decl_names) |decl| {
			@field(list, decl).client.unload(entity);
		}
	}
};
pub const server = struct {
	pub fn init() void {
		inline for (@typeInfo(components).@"struct".decl_names) |decl| {
			@field(components, decl).server.init();
		}
	}
	pub fn deinit() void {
		inline for (@typeInfo(components).@"struct".decl_names) |decl| {
			@field(components, decl).server.deinit();
		}
	}
	pub fn componentsToBase64(allocator: main.heap.NeverFailingAllocator, entity: Entity, audience: main.entity.AudienceInfo) main.utils.Base64 {
		var writer = main.utils.BinaryWriter.init(main.stackAllocator);
		defer writer.deinit();

		inline for (@typeInfo(main.entity.components).@"struct".decl_names) |decl| {
			if (@field(main.entity.components, decl).server.get(entity)) |component| {
				var writerComponent = main.utils.BinaryWriter.init(main.stackAllocator);
				defer writerComponent.deinit();

				if (component.save(&writerComponent, audience) == .save) {
					writer.writeVarInt(u32, @field(main.entity.components, decl).entityComponentID);
					writer.writeVarInt(u32, @field(main.entity.components, decl).entityComponentVersion);
					writer.writeSliceWithSize(writerComponent.data.items);
				}
			}
		}
		return main.utils.Base64.toBase64(allocator, writer.data.items);
	}

	pub fn removeAllComponents(entity: Entity) void {
		const list = main.entity.components;
		inline for (@typeInfo(list).@"struct".decl_names) |decl| {
			@field(list, decl).server.unload(entity);
		}
	}

	pub fn transmitChange(EntityComponent: type, entity: Entity) void {
		var binaryWriter = main.utils.BinaryWriter.init(main.stackAllocator);
		defer binaryWriter.deinit();

		const users = main.server.getUserList(main.stackAllocator);
		defer main.stackAllocator.free(users);

		if (EntityComponent.server.get(entity)) |ptr| {
			if (ptr.save(&binaryWriter, .playerNearby) == .save) {
				for (users) |user| {
					main.network.protocols.EntityComponentUpdate.load(user.conn, entity, EntityComponent.entityComponentID, EntityComponent.entityComponentVersion, binaryWriter.data.items);
				}
			}
		} else {
			for (users) |user| {
				main.network.protocols.EntityComponentUpdate.unload(user.conn, entity, EntityComponent.entityComponentID);
			}
		}
	}
};

pub fn loadComponentsFromBase64(base64Data: []const u8, entity: Entity, comptime side: main.sync.Side) EntityComponentLoadError!void {
	const data = main.utils.fromBase64(main.stackAllocator, base64Data) catch return EntityComponentLoadError.DecodingBase64;
	defer main.stackAllocator.free(data);

	var reader = main.utils.BinaryReader.init(data);
	var lastError: EntityComponentLoadError!void = {};
	while (reader.remaining.len != 0) {
		const componentId: EntityComponentId = reader.readVarInt(EntityComponentId) catch return EntityComponentLoadError.UnreadableId;
		const componentVersion: u32 = reader.readVarInt(u32) catch return EntityComponentLoadError.UnreadableVersion;
		const componentData = reader.readSliceWithSize() catch return EntityComponentLoadError.UnreadableComponentData;

		lastError = loadComponent(side, componentId, entity, componentData, componentVersion);
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
