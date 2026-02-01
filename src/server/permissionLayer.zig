const std = @import("std");

const main = @import("main");
const server = main.server;
const User = server.User;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

pub const ListType = enum {
	white,
	black,
};

pub fn listToZon(allocator: NeverFailingAllocator, list: std.StringHashMapUnmanaged(void)) ZonElement {
	var zon: ZonElement = .initArray(allocator);
	var it = list.keyIterator();
	while (it.next()) |key| {
		zon.append(key.*);
	}
	return zon;
}

pub fn fillList(allocator: NeverFailingAllocator, list: *std.StringHashMapUnmanaged(void), zon: ZonElement) void {
	if (zon != .array) return;

	for (zon.array.items) |item| {
		switch (item) {
			.string => |string| {
				list.put(allocator.allocator, allocator.dupe(u8, string), {}) catch continue;
			},
			.stringOwned => |string| {
				list.put(allocator.allocator, allocator.dupe(u8, string), {}) catch continue;
			},
			else => {},
		}
	}
}

pub const PermissionGroup = struct {
	allocator: NeverFailingAllocator,
	permissionWhiteList: std.StringHashMapUnmanaged(void) = .{},
	permissionBlackList: std.StringHashMapUnmanaged(void) = .{},

	pub fn deinit(self: *PermissionGroup) void {
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

	pub fn hasPermission(self: *PermissionGroup, permissionPath: []const u8) PermissionResult {
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

pub var groups: std.StringHashMap(PermissionGroup) = undefined;

pub fn groupsToZon(allocator: NeverFailingAllocator) ZonElement {
	var zon: ZonElement = .initObject(allocator);
	var it = groups.iterator();
	while (it.next()) |group| {
		var groupZon: ZonElement = .initObject(allocator);
		groupZon.put("permissionWhiteList", listToZon(allocator, group.value_ptr.permissionWhiteList));
		groupZon.put("permissionBlackList", listToZon(allocator, group.value_ptr.permissionBlackList));
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
		fillList(allocator, &group.permissionWhiteList, entry.value_ptr.getChild("permissionWhiteList"));
		fillList(allocator, &group.permissionBlackList, entry.value_ptr.getChild("permissionBlackList"));
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

pub fn createGroup(name: []const u8, allocator: NeverFailingAllocator) error{Invalid}!void {
	if (groups.contains(name)) return error.Invalid;
	groups.put(allocator.dupe(u8, name), .{.allocator = allocator}) catch unreachable;
}

pub fn deleteGroup(name: []const u8) bool {
	const users = server.getUserListAndIncreaseRefCount(main.globalAllocator);
	for (users) |user| {
		const _key = user.permissionGroups.getKeyPtr(name);
		if (_key) |key| {
			_ = user.permissionGroups.remove(name);
			main.globalAllocator.free(key.*);
		}
	}
	server.freeUserListAndDecreaseRefCount(main.globalAllocator, users);
	if (groups.getEntry(name)) |entry| {
		_ = groups.remove(name);
		groups.allocator.free(entry.key_ptr.*);
		entry.value_ptr.deinit();
		return true;
	}
	return false;
}

pub fn addGroupPermission(name: []const u8, listType: ListType, permissionPath: []const u8) error{Invalid}!void {
	if (groups.getPtr(name)) |group| {
		switch (listType) {
			.white => group.permissionWhiteList.put(group.allocator.allocator, group.allocator.dupe(u8, permissionPath), {}) catch unreachable,
			.black => group.permissionBlackList.put(group.allocator.allocator, group.allocator.dupe(u8, permissionPath), {}) catch unreachable,
		}
	} else return error.Invalid;
}

pub fn addUserPermission(user: *User, allocator: NeverFailingAllocator, listType: ListType, permissionPath: []const u8) void {
	switch (listType) {
		.white => user.permissions.permissionWhiteList.put(allocator.allocator, allocator.dupe(u8, permissionPath), {}) catch unreachable,
		.black => user.permissions.permissionBlackList.put(allocator.allocator, allocator.dupe(u8, permissionPath), {}) catch unreachable,
	}
}

pub fn addUserToGroup(user: *User, allocator: NeverFailingAllocator, name: []const u8) error{Invalid}!void {
	if (groups.getPtr(name)) |group| {
		user.permissionGroups.put(allocator.allocator, allocator.dupe(u8, name), group) catch unreachable;
	} else {
		return error.Invalid;
	}
}

pub fn addUserToGroupList(user: *User, allocator: NeverFailingAllocator, zon: ZonElement) void {
	if (zon != .array) return;

	for (zon.array.items) |item| {
		addUserToGroup(user, allocator, item.stringOwned) catch {};
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

pub fn hasPermission(user: *User, permissionPath: []const u8) bool {
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

test "inValidGroupPermission" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	try std.testing.expectError(error.Invalid, addGroupPermission("root", .white, "/command/test"));
}

test "inValidGroupPermissionEmptyGroups" {
	init(main.heap.testingAllocator);
	defer deinit();

	try std.testing.expectError(error.Invalid, addGroupPermission("root", .white, "/command/test"));
}

test "inValidGroupCreation" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	try std.testing.expectError(error.Invalid, createGroup("test", main.heap.testingAllocator));
}

test "listToFromZon" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test", main.heap.testingAllocator);
	const group = groups.getPtr("test").?;
	try addGroupPermission("test", .white, "/command/test");
	try addGroupPermission("test", .white, "/command/spawn");

	const zon = listToZon(main.heap.testingAllocator, groups.get("test").?.permissionWhiteList);
	defer zon.deinit(main.heap.testingAllocator);

	var testList: std.StringHashMapUnmanaged(void) = .{};
	defer {
		var it = testList.keyIterator();
		while (it.next()) |key| {
			main.heap.testingAllocator.free(key.*);
		}
		testList.deinit(main.heap.testingAllocator.allocator);
	}

	fillList(main.heap.testingAllocator, &testList, zon);

	try std.testing.expectEqual(2, testList.size);

	var it = testList.keyIterator();
	while (it.next()) |item| {
		try std.testing.expectEqual(true, group.permissionWhiteList.contains(item.*));
	}
}
