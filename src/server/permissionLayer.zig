const std = @import("std");

const main = @import("main");
const server = main.server;
const User = server.User;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const ListType = enum {
	white,
	black,
};

pub const PermissionGroup = struct {
	allocator: NeverFailingAllocator,
	permissionWhiteList: std.StringHashMapUnmanaged(void) = .{},
	permissionBlackList: std.StringHashMapUnmanaged(void) = .{},

	pub fn deinit(self: *PermissionGroup) void {
		self.permissionWhiteList.deinit(self.allocator.allocator);
		self.permissionBlackList.deinit(self.allocator.allocator);
	}

	pub fn hasPermission(self: *PermissionGroup, permissionPath: []const u8) bool {
		var it = std.mem.splitBackwardsScalar(u8, permissionPath, '/');
		var current = permissionPath;

		while (it.next()) |path| {
			if (self.permissionBlackList.contains(current)) return false;
			if (self.permissionWhiteList.contains(current)) return true;

			const len = current.len -| (path.len + 1);
			current = permissionPath[0..len];
		}
		return false;
	}
};

pub var groups: std.StringHashMap(PermissionGroup) = undefined;

pub fn init(allocator: NeverFailingAllocator) void {
	groups = .init(allocator.allocator);
}

pub fn deinit() void {
	var it = groups.iterator();
	while (it.next()) |entry| {
		entry.value_ptr.deinit();
	}
	groups.deinit();
}

pub fn createGroup(name: []const u8, allocator: NeverFailingAllocator) error{Invalid}!void {
	if (groups.contains(name)) return error.Invalid;
	groups.put(name, .{.allocator = allocator}) catch unreachable;
}

pub fn deleteGroup(name: []const u8) bool {
	const users = server.getUserListAndIncreaseRefCount(main.globalAllocator);
	for (users) |user| {
		_ = user.permissionGroups.remove(name);
	}
	server.freeUserListAndDecreaseRefCount(main.globalAllocator, users);
	if (groups.getPtr(name)) |group| {
		group.deinit();
	}
	return groups.remove(name);
}

pub fn addGroupPermission(name: []const u8, listType: ListType, permissionPath: []const u8) error{Invalid}!void {
	if (groups.getPtr(name)) |group| {
		switch (listType) {
			.white => group.permissionWhiteList.put(group.allocator.allocator, permissionPath, {}) catch unreachable,
			.black => group.permissionBlackList.put(group.allocator.allocator, permissionPath, {}) catch unreachable,
		}
	} else return error.Invalid;
}

pub fn addUserPermission(user: *User, allocator: NeverFailingAllocator, listType: ListType, permissionPath: []const u8) void {
	switch (listType) {
		.white => user.permissionWhiteList.put(allocator.allocator, permissionPath, {}) catch unreachable,
		.black => user.permissionBlackList.put(allocator.allocator, permissionPath, {}) catch unreachable,
	}
}

pub fn addUserToGroup(user: *User, allocator: NeverFailingAllocator, name: []const u8) error{Invalid}!void {
	if (groups.getPtr(name)) |group| {
		user.permissionGroups.put(allocator.allocator, name, group) catch unreachable;
	} else {
		return error.Invalid;
	}
}

pub fn hasPermission(user: *User, permissionPath: []const u8) bool {
	var it = std.mem.splitBackwardsScalar(u8, permissionPath, '/');
	var current = permissionPath;

	while (it.next()) |path| {
		if (user.permissionBlackList.contains(current)) return false;
		if (user.permissionWhiteList.contains(current)) return true;

		const len = current.len -| (path.len + 1);
		current = permissionPath[0..len];
	}

	var groupIt = user.permissionGroups.valueIterator();
	while (groupIt.next()) |group| {
		if (group.*.hasPermission(permissionPath)) return true;
	}

	return false;
}

test "GroupWhitePermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "command/test");

	try std.testing.expectEqual(true, group.hasPermission("command/test"));
}

test "GroupBlacklist" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "command");
	try addGroupPermission("test", .black, "command/test");

	try std.testing.expectEqual(false, group.hasPermission("command/test"));
	try std.testing.expectEqual(true, group.hasPermission("command"));
}

test "GroupDeepPermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "server/command/testing/test");

	try std.testing.expectEqual(true, group.hasPermission("server/command/testing/test"));
	try std.testing.expectEqual(false, group.hasPermission("server/command/testing"));
	try std.testing.expectEqual(false, group.hasPermission("server/command"));
	try std.testing.expectEqual(false, group.hasPermission("server"));
	try std.testing.expectEqual(false, group.hasPermission("server/command/testing/test2"));
}

test "inValidGroupPermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	try std.testing.expectError(error.Invalid, addGroupPermission("root", .white, "command/test"));
}

test "inValidGroupPermissionEmptyGroups" {
	init(main.heap.testingAllocator);
	defer deinit();

	try std.testing.expectError(error.Invalid, addGroupPermission("root", .white, "command/test"));
}

test "inValidGroupCreation" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	try std.testing.expectError(error.Invalid, createGroup("test", main.heap.testingAllocator));
}
