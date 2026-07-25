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
		permissionGroups: std.StringHashMapUnmanaged(*main.server.permission.Group),

		pub fn save(self: Component, writer: *BinaryWriter, audience: main.entity.AudienceInfo) main.entity.ComponentSaveBehaviour {
			if (audience != .disk) return .discard;
			self.permissions.toBytes(writer);

			writer.writeInt(u32, self.permissionGroups.count());
			var it = self.permissionGroups.iterator();
			while (it.next()) |entry| {
				writer.writeSliceWithSize(entry.key_ptr.*);
				writer.writeInt(u32, entry.value_ptr.*.id);
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

	pub fn getPermissionGroups(entity: Entity) ?*std.StringHashMapUnmanaged(*main.server.permission.Group) {
		return &(components.get(entity) orelse return null).permissionGroups;
	}

	pub fn hasPermission(entity: Entity, permissionPath: []const u8) bool {
		switch ((getPermissions(entity) orelse return false).hasPermission(permissionPath)) {
			.yes => return true,
			.no => return false,
			.neutral => {},
		}
		var groupIt = (getPermissionGroups(entity).?).valueIterator();
		while (groupIt.next()) |group| {
			if (group.*.hasPermission(permissionPath) == .yes) return true;
		}
		return false;
	}

	pub fn addPermission(entity: Entity, listType: main.server.permission.Permissions.ListType, permissionPath: []const u8) void {
		(getPermissions(entity) orelse return).addPermission(listType, permissionPath);
	}

	pub fn removePermission(entity: Entity, listType: main.server.permission.Permissions.ListType, permissionPath: []const u8) bool {
		return (getPermissions(entity) orelse return false).removePermission(listType, permissionPath);
	}

	pub fn addToGroup(entity: Entity, groupName: []const u8) error{GroupNotFound}!void {
		const group = try main.server.permission.getGroup(groupName);
		const result = (getPermissionGroups(entity) orelse return).getOrPut(main.globalAllocator.allocator, groupName) catch unreachable;
		if (!result.found_existing) {
			result.key_ptr.* = main.globalAllocator.dupe(u8, groupName);
			result.value_ptr.* = group;
		}
	}

	pub fn removeFromGroup(entity: Entity, groupName: []const u8) bool {
		const groupNamePtr = (getPermissionGroups(entity) orelse return false).getKey(groupName) orelse return false;
		_ = getPermissionGroups(entity).?.remove(groupName);
		main.globalAllocator.free(groupNamePtr);
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
			const name = reader.readSliceWithSize() catch return error.UnreadableComponentData;
			const group = main.server.permission.getGroup(name) catch {
				_ = reader.readInt(u32) catch return error.UnreadableComponentData;
				continue;
			};
			if (group.id != reader.readInt(u32) catch return error.UnreadableComponentData) continue;
			addToGroup(entity, name) catch unreachable; // we already proven that the group exists
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
		var permissionGroupsIterator = component.permissionGroups.keyIterator();
		while (permissionGroupsIterator.next()) |key| {
			main.globalAllocator.free(key.*);
		}
		component.permissionGroups.deinit(main.globalAllocator.allocator);
	}
};
