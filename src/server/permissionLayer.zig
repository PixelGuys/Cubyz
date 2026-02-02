const std = @import("std");

const main = @import("main");
const server = main.server;
const User = server.User;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

fn fillMapHelper(allocator: NeverFailingAllocator, map: *std.StringHashMapUnmanaged(void), permissionPath: []const u8) void {
	if (map.contains(permissionPath)) return;
	const duped = allocator.dupe(u8, permissionPath);
	map.put(allocator.allocator, duped, {}) catch unreachable;
}

fn fillMap(allocator: NeverFailingAllocator, map: *std.StringHashMapUnmanaged(void), zon: ZonElement) void {
	if (zon != .array) return;

	for (zon.array.items) |item| {
		switch (item) {
			.string => |string| fillMapHelper(allocator, map, string),
			.stringOwned => |string| fillMapHelper(allocator, map, string),
			else => {},
		}
	}
}

fn mapToZon(allocator: NeverFailingAllocator, map: *std.StringHashMapUnmanaged(void)) ZonElement {
	var zon: ZonElement = .initArray(allocator);

	var it = map.keyIterator();
	while (it.next()) |key| {
		zon.append(key.*);
	}
	return zon;
}

pub const Permissions = struct {
	pub const ListType = enum {
		white,
		black,
	};

	allocator: NeverFailingAllocator,
	permissionWhiteList: std.StringHashMapUnmanaged(void) = .{},
	permissionBlackList: std.StringHashMapUnmanaged(void) = .{},

	pub fn deinit(self: *Permissions) void {
		var it = self.permissionWhiteList.keyIterator();
		while (it.next()) |key| {
			self.allocator.free(key.*);
		}
		self.permissionWhiteList.deinit(self.allocator.allocator);
		it = self.permissionBlackList.keyIterator();
		while (it.next()) |key| {
			self.allocator.free(key.*);
		}
		self.permissionBlackList.deinit(self.allocator.allocator);
	}

	const PermissionResult = enum {
		yes,
		no,
		neutral,
	};

	pub fn list(self: *Permissions, listType: ListType) *std.StringHashMapUnmanaged(void) {
		return switch (listType) {
			.white => &self.permissionWhiteList,
			.black => &self.permissionBlackList,
		};
	}

	pub fn fillList(self: *Permissions, listType: ListType, zon: ZonElement) void {
		fillMap(self.allocator, self.list(listType), zon);
	}

	pub fn listToZon(self: *Permissions, allocator: NeverFailingAllocator, listType: ListType) ZonElement {
		return mapToZon(allocator, self.list(listType));
	}

	pub fn addPermission(self: *Permissions, listType: ListType, permissionPath: []const u8) void {
		self.list(listType).put(self.allocator.allocator, self.allocator.dupe(u8, permissionPath), {}) catch unreachable;
	}

	pub fn removePermission(self: *Permissions, listType: ListType, permissionPath: []const u8) bool {
		const _key = self.list(listType).getKeyPtr(permissionPath);
		if (_key) |key| {
			const slice = key.*;
			_ = self.list(listType).remove(permissionPath);
			self.allocator.free(slice);
			return true;
		}
		return false;
	}

	pub fn hasPermission(self: *Permissions, permissionPath: []const u8) PermissionResult {
		var it = std.mem.splitBackwardsScalar(u8, permissionPath, '/');
		var current = permissionPath;

		while (it.next()) |path| {
			if (self.permissionBlackList.contains(current)) return .no;
			if (self.permissionWhiteList.contains(current)) return .yes;

			const len = current.len -| (path.len + 1);
			current = permissionPath[0..len];
		}
		return if (self.permissionWhiteList.contains("/")) .yes else .neutral;
	}
};

pub const PermissionGroup = struct {
	allocator: NeverFailingAllocator,
	permissions: Permissions,
	members: std.StringHashMapUnmanaged(void) = .{},

	pub fn init(allocator: NeverFailingAllocator) PermissionGroup {
		return .{
			.allocator = allocator,
			.permissions = .{.allocator = allocator},
		};
	}

	pub fn deinit(self: *PermissionGroup) void {
		self.permissions.deinit();
		var it = self.members.keyIterator();
		while (it.next()) |key| {
			self.allocator.free(key.*);
		}
		self.members.deinit(self.allocator.allocator);
	}

	pub fn hasPermission(self: *PermissionGroup, permissionPath: []const u8) Permissions.PermissionResult {
		return self.permissions.hasPermission(permissionPath);
	}

	pub fn addUser(self: *PermissionGroup, user: *User) void {
		self.members.put(self.allocator.allocator, self.allocator.dupe(u8, user.name), {}) catch unreachable;
	}
};

pub var groups: std.StringHashMap(PermissionGroup) = undefined;

pub fn groupsToZon(allocator: NeverFailingAllocator) ZonElement {
	var zon: ZonElement = .initObject(allocator);
	var it = groups.iterator();
	while (it.next()) |group| {
		var groupZon: ZonElement = .initObject(allocator);
		groupZon.put("permissionWhiteList", group.value_ptr.permissions.listToZon(allocator, .white));
		groupZon.put("permissionBlackList", group.value_ptr.permissions.listToZon(allocator, .black));
		groupZon.put("members", mapToZon(allocator, &group.value_ptr.members));
		zon.put(group.key_ptr.*, groupZon);
	}
	return zon;
}

pub fn fillGroups(allocator: NeverFailingAllocator, zon: ZonElement) void {
	if (zon != .object) return;

	var it = zon.object.iterator();
	while (it.next()) |entry| {
		createGroup(entry.key_ptr.*, allocator) catch {};
		const group = groups.getPtr(entry.key_ptr.*).?;
		group.permissions.fillList(.white, entry.value_ptr.getChild("permissionWhiteList"));
		group.permissions.fillList(.black, entry.value_ptr.getChild("permissionBlackList"));
		fillMap(group.allocator, &group.members, entry.value_ptr.getChild("members"));
	}
}

pub fn init(allocator: NeverFailingAllocator) void {
	groups = .init(allocator.allocator);
}

pub fn deinit() void {
	var it = groups.iterator();
	while (it.next()) |entry| {
		groups.allocator.free(entry.key_ptr.*);
		entry.value_ptr.deinit();
	}
	groups.deinit();
}

pub fn createGroup(name: []const u8, allocator: NeverFailingAllocator) error{AlreadyExists}!void {
	if (groups.contains(name)) return error.AlreadyExists;
	groups.put(allocator.dupe(u8, name), .init(allocator)) catch unreachable;
}

pub fn deleteGroup(name: []const u8) bool {
	const users = server.getUserListAndIncreaseRefCount(main.globalAllocator);
	for (users) |user| {
		const _key = user.permissionGroups.getKeyPtr(name);
		if (_key) |key| {
			const slice = key.*;
			_ = user.permissionGroups.remove(name);
			main.globalAllocator.free(slice);
		}
	}
	server.freeUserListAndDecreaseRefCount(main.globalAllocator, users);
	if (groups.getEntry(name)) |entry| {
		entry.value_ptr.deinit();
		const slice = entry.key_ptr.*;
		_ = groups.remove(name);
		groups.allocator.free(slice);
		return true;
	}
	return false;
}

pub fn addGroupPermission(name: []const u8, listType: Permissions.ListType, permissionPath: []const u8) error{GroupNotFound}!void {
	if (groups.getPtr(name)) |group| {
		group.permissions.addPermission(listType, permissionPath);
	} else return error.GroupNotFound;
}

pub fn removeGroupPermission(name: []const u8, listType: Permissions.ListType, permissionPath: []const u8) error{GroupNotFound}!bool {
	if (groups.getPtr(name)) |group| {
		return group.permissions.removePermission(listType, permissionPath);
	} else return error.GroupNotFound;
}

pub fn addUserToGroup(user: *User, name: []const u8) error{GroupNotFound}!void {
	if (groups.getPtr(name)) |group| {
		user.permissionGroups.put(main.globalAllocator.allocator, main.globalAllocator.dupe(u8, name), group) catch unreachable;
		group.addUser(user);
	} else return error.GroupNotFound;
}

pub fn removeUserNameFromGroup(userName: []const u8, groupName: []const u8) error{ GroupNotFound, UserNotInGroup }!void {
	if (groups.getPtr(groupName)) |group| {
		const _member = group.members.getKeyPtr(userName);
		if (_member) |member| {
			const slice = member.*;
			_ = group.members.remove(userName);
			group.allocator.free(slice);
		} else return error.UserNotInGroup;
	} else return error.GroupNotFound;
}

pub fn removeUserFromGroup(user: *User, name: []const u8) error{ GroupNotFound, UserNotInGroup }!void {
	const _key = user.permissionGroups.getKeyPtr(name);
	if (_key) |key| {
		const slice = key.*;
		_ = user.permissionGroups.remove(name);
		main.globalAllocator.free(slice);
	} else return error.UserNotInGroup;
	try removeUserNameFromGroup(user.name, name);
}

pub fn addUserToGroupList(user: *User, allocator: NeverFailingAllocator, zon: ZonElement) void {
	if (zon != .array) return;

	for (zon.array.items) |item| {
		if (groups.getPtr(item.stringOwned)) |group| {
			if (!group.members.contains(user.name)) continue;
			user.permissionGroups.put(allocator.allocator, allocator.dupe(u8, item.stringOwned), group) catch unreachable;
		}
	}
}

pub fn zonFromGroupList(user: *User, allocator: NeverFailingAllocator) ZonElement {
	var zon: ZonElement = .initArray(allocator);
	var it = user.permissionGroups.keyIterator();
	while (it.next()) |key| {
		zon.append(key.*);
	}
	return zon;
}

pub fn userHasPermission(user: *User, permissionPath: []const u8) bool {
	switch (user.permissions.hasPermission(permissionPath)) {
		.yes => return true,
		.no => return false,
		.neutral => {},
	}

	var groupIt = user.permissionGroups.valueIterator();
	while (groupIt.next()) |group| {
		if (group.*.hasPermission(permissionPath) == .yes) return true;
	}
	return false;
}

test "GroupWhitePermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/command/test");

	try std.testing.expectEqual(.yes, group.hasPermission("/command/test"));
}

test "GroupBlacklist" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/command");
	try addGroupPermission("test", .black, "/command/test");

	try std.testing.expectEqual(.no, group.hasPermission("/command/test"));
	try std.testing.expectEqual(.yes, group.hasPermission("/command"));
}

test "GroupDeepPermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/server/command/testing/test");

	try std.testing.expectEqual(.yes, group.hasPermission("/server/command/testing/test"));
	try std.testing.expectEqual(.neutral, group.hasPermission("/server/command/testing"));
	try std.testing.expectEqual(.neutral, group.hasPermission("/server/command"));
	try std.testing.expectEqual(.neutral, group.hasPermission("/server"));
	try std.testing.expectEqual(.neutral, group.hasPermission("/server/command/testing/test2"));
}

test "GroupRootPermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/");

	try std.testing.expectEqual(.yes, group.hasPermission("/command/test"));
}

test "GroupAddRemovePermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/command/test");

	try std.testing.expectEqual(true, group.permissions.removePermission(.white, "/command/test"));
}

test "inValidGroupPermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	try std.testing.expectError(error.GroupNotFound, addGroupPermission("root", .white, "/command/test"));
}

test "inValidGroupPermissionEmptyGroups" {
	init(main.heap.testingAllocator);
	defer deinit();

	try std.testing.expectError(error.GroupNotFound, addGroupPermission("root", .white, "/command/test"));
}

test "inValidGroupCreation" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	try std.testing.expectError(error.AlreadyExists, createGroup("test", main.heap.testingAllocator));
}

test "listToFromZon" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	var group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/command/test");
	try addGroupPermission("test", .white, "/command/spawn");

	const zon = group.permissions.listToZon(main.heap.testingAllocator, .white);
	defer zon.deinit(main.heap.testingAllocator);

	var testPermissions: Permissions = .{.allocator = main.heap.testingAllocator};
	defer testPermissions.deinit();

	testPermissions.fillList(.white, zon);

	try std.testing.expectEqual(2, testPermissions.permissionWhiteList.size);

	var it = testPermissions.permissionWhiteList.keyIterator();
	while (it.next()) |item| {
		try std.testing.expectEqual(true, group.permissions.permissionWhiteList.contains(item.*));
	}
}
