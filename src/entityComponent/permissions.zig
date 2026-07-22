const std = @import("std");

const main = @import("main");
const Entity = main.entity.Entity;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub var entityComponentID: main.entity.EntityComponentId = undefined;
pub const entityComponentVersion = 0;

// ############################# Client only stuff ################################
pub const client = struct {
	pub fn load(entity: Entity, reader: *BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		_ = entity;
		_ = reader;
		_ = version;
	}
	pub fn unload(entity: Entity) void {
		_ = entity;
	}
	pub fn init() void {}
	pub fn deinit() void {}
	pub fn clear() void {}
};
// ############################# Server only stuff ################################
pub const server = struct {
	pub const Component = struct {
		permissions: main.server.permission.Permissions,

		pub fn save(self: Component, writer: *BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk) return .discard;
			self.permissions.toBytes(writer);
			return .save;
		}
	};
	pub var components: main.utils.SparseSet(Component, Entity) = .{};

	pub fn init() void {
		components = .{};
	}

	pub fn deinit() void {
		components.deinit(main.globalAllocator);
	}

	pub fn get(entity: Entity) ?Component {
		return (components.get(entity) orelse return null).*;
	}

	pub fn getPermissions(entity: Entity) ?*main.server.permission.Permissions {
		return &(components.get(entity) orelse return null).permissions;
	}

	pub fn hasPermission(entity: Entity, permissionPath: []const u8) bool {
		return switch ((getPermissions(entity) orelse return false).hasPermission(permissionPath)) {
			.yes => true,
			.no, .neutral => false,
		};
	}

	pub fn loadFromData(entity: Entity, reader: *BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const permissions = &components.add(main.globalAllocator, entity).permissions;
		permissions.* = .init(main.globalAllocator);
		permissions.fromBytes(reader) catch return error.UnreadableComponentData;
	}

	pub fn loadEmpty(entity: Entity) void {
		const permissions = &components.add(main.globalAllocator, entity).permissions;
		permissions.* = .init(main.globalAllocator);
	}

	pub fn unload(entity: Entity) void {
		const permissions = components.fetchRemove(entity) catch return;
		permissions.permissions.deinit();
	}
};
