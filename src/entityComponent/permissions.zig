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
		permissionGroups: std.AutoHashMapUnmanaged(main.server.permission.Group, void),

		pub fn save(self: Component, writer: *BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk) return .discard;
			self.permissions.toBytes(writer);

			writer.writeVarInt(usize, self.permissionGroups.count());
			var it = self.permissionGroups.keyIterator();
			while (it.next()) |group| {
				group.toBytes(writer);
			}
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

	pub fn getPermissionGroups(entity: Entity) ?*std.AutoHashMapUnmanaged(main.server.permission.Group, void) {
		return &(components.get(entity) orelse return null).permissionGroups;
	}

	pub fn hasPermission(entity: Entity, permissionPath: []const u8) bool {
		switch ((getPermissions(entity) orelse return false).hasPermission(permissionPath)) {
			.yes => return true,
			.no => return false,
			.neutral => {},
		}
		var groupIt = (getPermissionGroups(entity).?).keyIterator();
		while (groupIt.next()) |group| {
			if (group.hasPermission(permissionPath) == .yes) return true;
		}
		return false;
	}

	pub fn addPermission(entity: Entity, listType: main.server.permission.Permissions.ListType, permissionPath: []const u8) void {
		(getPermissions(entity) orelse return).addPermission(listType, permissionPath);
	}

	pub fn removePermission(entity: Entity, listType: main.server.permission.Permissions.ListType, permissionPath: []const u8) bool {
		return (getPermissions(entity) orelse return false).removePermission(listType, permissionPath);
	}

	pub fn addToGroup(entity: Entity, group: main.server.permission.Group) void {
		(getPermissionGroups(entity) orelse return).put(main.globalAllocator.allocator, group, {}) catch unreachable;
	}

	pub fn removeFromGroup(entity: Entity, group: main.server.permission.Group) bool {
		return getPermissionGroups(entity).?.remove(group);
	}

	pub fn loadFromData(entity: Entity, reader: *BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const component = components.add(main.globalAllocator, entity);
		component.permissions = .init(main.globalAllocator);
		component.permissions.fromBytes(reader) catch return error.UnreadableComponentData;
		component.permissionGroups = .empty;
		const len = reader.readVarInt(usize) catch return;
		for (0..len) |_| {
			const group = main.server.permission.Group.fromBytes(reader) catch |err| {
				if (err == error.GroupNotFound) continue; // if the group is not found we just skip it.
				return error.UnreadableComponentData;
			};
			addToGroup(entity, group);
		}
	}

	pub fn loadEmpty(entity: Entity) void {
		const component = components.add(main.globalAllocator, entity);
		component.permissions = .init(main.globalAllocator);
		component.permissionGroups = .empty;
	}

	pub fn unload(entity: Entity) void {
		var component = components.fetchRemove(entity) catch return;
		component.permissions.deinit();
		component.permissionGroups.deinit(main.globalAllocator.allocator);
	}
};
