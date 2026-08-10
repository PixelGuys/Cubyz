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
		permissionGroups: std.AutoHashMapUnmanaged(u32, void),

		pub fn save(self: Component, writer: *BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk) return .discard;
			self.permissions.toBytes(writer);

			writer.writeInt(u32, self.permissionGroups.count());
			var it = self.permissionGroups.keyIterator();
			while (it.next()) |groupId| {
				writer.writeInt(u32, groupId.*);
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

	pub fn getPermissionGroups(entity: Entity) ?*std.AutoHashMapUnmanaged(u32, void) {
		return &(components.get(entity) orelse return null).permissionGroups;
	}

	pub fn hasPermission(entity: Entity, permissionPath: []const u8) bool {
		switch ((getPermissions(entity) orelse return false).hasPermission(permissionPath)) {
			.yes => return true,
			.no => return false,
			.neutral => {},
		}
		var groupIt = (getPermissionGroups(entity).?).keyIterator();
		while (groupIt.next()) |id| {
			const group = main.server.permission.getGroupById(id.*) catch continue; // in theory the group can be removed here. Instead its for now only removed only on load
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

	pub fn addToGroupByName(entity: Entity, groupName: []const u8) error{GroupNotFound}!void {
		const groupId = try main.server.permission.getGroupIdByName(groupName);
		_ = (getPermissionGroups(entity) orelse return).put(main.globalAllocator.allocator, groupId) catch unreachable;
	}

	pub fn addToGroupById(entity: Entity, groupId: u32) error{GroupNotFound}!void {
		_ = try main.server.permission.getGroupById(groupId);
		(getPermissionGroups(entity) orelse return).put(main.globalAllocator.allocator, groupId, {}) catch unreachable;
	}

	pub fn removeFromGroupByName(entity: Entity, groupName: []const u8) bool {
		return removeFromGroupById(entity, main.server.permission.getGroupIdByName(groupName));
	}

	pub fn removeFromGroupById(entity: Entity, id: u32) bool {
		getPermissionGroups(entity).?.remove(id) orelse return false;
		return true;
	}

	pub fn loadFromData(entity: Entity, reader: *BinaryReader, version: u32) main.entity.EntityComponentLoadError!void {
		if (version != entityComponentVersion) return error.InvalidComponentVersion;
		const component = components.add(main.globalAllocator, entity);
		component.permissions = .init(main.globalAllocator);
		component.permissions.fromBytes(reader) catch return error.UnreadableComponentData;
		component.permissionGroups = .empty;
		const len = reader.readInt(u32) catch return;
		for (0..len) |_| {
			const id = reader.readInt(u32) catch return error.UnreadableComponentData;
			addToGroupById(entity, id) catch continue; // if the group is not found we just skip it.
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
