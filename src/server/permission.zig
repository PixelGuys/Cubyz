const std = @import("std");

const main = @import("main");
const server = main.server;
const User = server.User;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const ZonElement = main.ZonElement;
const sync = main.sync;

const PermissionMap = struct { // MARK: PermissionMap
	map: std.StringHashMapUnmanaged(void) = .{},

	pub fn fromZon(self: *PermissionMap, arena: NeverFailingAllocator, zon: ZonElement) void {
		sync.threadContext.assertCorrectContext(.server);
		for (zon.toSlice()) |item| {
			const string = item.as(?[]const u8, null) orelse continue;
			self.put(arena, string);
		}
	}

	pub fn toZon(self: *PermissionMap, arena: NeverFailingAllocator) ZonElement {
		sync.threadContext.assertCorrectContext(.server);
		const zon: ZonElement = .initArray(arena);

		var it = self.map.keyIterator();
		while (it.next()) |key| {
			zon.append(key.*);
		}
		return zon;
	}

	pub fn put(self: *PermissionMap, arena: NeverFailingAllocator, key: []const u8) void {
		const result = self.map.getOrPut(arena.allocator, key) catch unreachable;
		if (!result.found_existing) result.key_ptr.* = arena.dupe(u8, key);
	}
};

pub const Permissions = struct { // MARK: Permissions
	pub const ListType = enum {
		white,
		black,
	};

	arena: NeverFailingArenaAllocator,
	whitelist: PermissionMap = .{},
	blacklist: PermissionMap = .{},

	pub fn init(allocator: NeverFailingAllocator) Permissions {
		return .{
			.arena = .init(allocator),
		};
	}

	pub fn deinit(self: *Permissions) void {
		sync.threadContext.assertCorrectContext(.server);
		self.arena.deinit();
	}

	const PermissionResult = enum {
		yes,
		no,
		neutral,
	};

	fn list(self: *Permissions, listType: ListType) *PermissionMap {
		return switch (listType) {
			.white => &self.whitelist,
			.black => &self.blacklist,
		};
	}

	pub fn fromZon(self: *Permissions, zon: ZonElement) void {
		sync.threadContext.assertCorrectContext(.server);
		self.list(.white).fromZon(self.arena.allocator(), zon.getChild("permissionWhitelist"));
		self.list(.black).fromZon(self.arena.allocator(), zon.getChild("permissionBlacklist"));
	}

	pub fn toZon(self: *Permissions, allocator: NeverFailingAllocator, zon: *ZonElement) void {
		sync.threadContext.assertCorrectContext(.server);
		zon.put("permissionWhitelist", self.list(.white).toZon(allocator));
		zon.put("permissionBlacklist", self.list(.black).toZon(allocator));
	}

	pub fn addPermission(self: *Permissions, listType: ListType, permissionPath: []const u8) void {
		sync.threadContext.assertCorrectContext(.server);
		self.list(listType).put(self.arena.allocator(), permissionPath);
	}

	pub fn removePermission(self: *Permissions, listType: ListType, permissionPath: []const u8) bool {
		sync.threadContext.assertCorrectContext(.server);
		return self.list(listType).map.remove(permissionPath);
	}

	pub fn hasPermission(self: *Permissions, permissionPath: []const u8) PermissionResult {
		sync.threadContext.assertCorrectContext(.server);
		var current = permissionPath;

		while (std.mem.lastIndexOfScalar(u8, current, '/')) |nextPos| {
			if (self.blacklist.map.contains(current)) return .no;
			if (self.whitelist.map.contains(current)) return .yes;

			current = permissionPath[0..nextPos];
		}
		return if (self.whitelist.map.contains("/")) .yes else .neutral;
	}
};

pub const PermissionGroup = struct { // MARK: PermissionGroup
	permissions: Permissions,
	id: u32,

	pub fn init(allocator: NeverFailingAllocator) PermissionGroup {
		sync.threadContext.assertCorrectContext(.server);
		currentId += 1;
		return .{
			.permissions = .init(allocator),
			.id = currentId,
		};
	}

	pub fn deinit(self: *PermissionGroup) void {
		sync.threadContext.assertCorrectContext(.server);
		self.permissions.deinit();
	}

	pub fn hasPermission(self: *PermissionGroup, permissionPath: []const u8) Permissions.PermissionResult {
		return self.permissions.hasPermission(permissionPath);
	}
};

var groups: std.StringHashMapUnmanaged(PermissionGroup) = .{};
var groupsArena: NeverFailingArenaAllocator = undefined;
var currentId: u32 = 0;

pub fn init(allocator: NeverFailingAllocator, _zon: ?ZonElement) void {
	groupsArena = .init(allocator);
	const zon = _zon orelse return;
	currentId = zon.get(u32, "currentId", 0);

	if (zon.getChild("groups") != .object) return;
	var it = zon.getChild("groups").object.iterator();
	while (it.next()) |entry| {
		groups.put(groupsArena.allocator().allocator, groupsArena.allocator().dupe(u8, entry.key_ptr.*), .{
			.id = entry.value_ptr.get(u32, "id", 0),
			.permissions = .init(groupsArena.allocator()),
		}) catch unreachable;

		const group = groups.getPtr(entry.key_ptr.*).?;
		group.permissions.fromZon(entry.value_ptr.*);
	}
}

pub fn deinit() void {
	groupsArena.deinit();
	groups = .{};
}

pub fn groupsToZon(allocator: NeverFailingAllocator) ZonElement {
	var zon: ZonElement = .initObject(allocator);
	zon.put("currentId", currentId);

	var groupsZon: ZonElement = .initObject(allocator);
	var it = groups.iterator();
	while (it.next()) |group| {
		var groupZon: ZonElement = .initObject(allocator);
		groupZon.put("id", group.value_ptr.id);
		group.value_ptr.permissions.toZon(allocator, &groupZon);
		groupsZon.put(group.key_ptr.*, groupZon);
	}
	zon.put("groups", groupsZon);
	return zon;
}

pub fn createGroup(name: []const u8) error{AlreadyExists}!void {
	sync.threadContext.assertCorrectContext(.server);
	const result = groups.getOrPut(groupsArena.allocator().allocator, name) catch unreachable;
	if (result.found_existing) return error.AlreadyExists;

	result.key_ptr.* = groupsArena.allocator().dupe(u8, name);
	result.value_ptr.* = .init(groupsArena.allocator());
}

pub fn getGroup(name: []const u8) error{GroupNotFound}!*PermissionGroup {
	return groups.getPtr(name) orelse return error.GroupNotFound;
}

pub fn deleteGroup(name: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	const users = server.getUserListAndIncreaseRefCount(main.globalAllocator);
	for (users) |user| {
		const key = user.permissionGroups.getKeyPtr(name) orelse continue;
		const slice = key.*;
		_ = user.permissionGroups.remove(name);
		main.globalAllocator.free(slice);
	}
	server.freeUserListAndDecreaseRefCount(main.globalAllocator, users);
	return groups.remove(name);
}

// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// MARK: Testing
// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

test "WhitePermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");
	try std.testing.expectEqual(.yes, permissions.hasPermission("/command/test"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/command"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/"));
}

test "Blacklist" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command");
	permissions.addPermission(.black, "/command/test");

	try std.testing.expectEqual(.no, permissions.hasPermission("/command/test"));
	try std.testing.expectEqual(.yes, permissions.hasPermission("/command"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/"));
}

test "DeepPermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/server/command/testing/test");

	try std.testing.expectEqual(.yes, permissions.hasPermission("/server/command/testing/test"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/server/command/testing"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/server/command"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/server"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/server/command/testing/test2"));
}

test "RootPermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/");

	try std.testing.expectEqual(.yes, permissions.hasPermission("/command/test"));
}

test "RootBlackPermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/");
	permissions.addPermission(.black, "/command/test");

	try std.testing.expectEqual(.no, permissions.hasPermission("/command/test"));
	try std.testing.expectEqual(.yes, permissions.hasPermission("/command/test2"));
}

test "addRemovePermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");

	try std.testing.expectEqual(true, permissions.removePermission(.white, "/command/test"));
}

test "RemoveNonExistentPermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");

	try std.testing.expectEqual(false, permissions.removePermission(.white, "/command/test2"));
}

test "invalidGroupPermission" {
	init(main.heap.testingAllocator, null);
	defer deinit();

	try createGroup("test");
	try std.testing.expectError(error.GroupNotFound, getGroup("root"));
}

test "invalidGroupPermissionEmptyGroups" {
	init(main.heap.testingAllocator, null);
	defer deinit();

	try std.testing.expectError(error.GroupNotFound, getGroup("root"));
}

test "invalidGroupCreation" {
	init(main.heap.testingAllocator, null);
	defer deinit();

	try createGroup("test");
	try std.testing.expectError(error.AlreadyExists, createGroup("test"));
}

test "PermissionListToFromZon" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");
	permissions.addPermission(.white, "/command/spawn");

	const zon = permissions.whitelist.toZon(main.heap.testingAllocator);
	defer zon.deinit(main.heap.testingAllocator);

	var testPermissions: Permissions = .init(main.heap.testingAllocator);
	defer testPermissions.deinit();

	testPermissions.whitelist.fromZon(testPermissions.arena.allocator(), zon);

	try std.testing.expectEqual(2, testPermissions.whitelist.map.size);

	var it = testPermissions.whitelist.map.keyIterator();
	while (it.next()) |item| {
		try std.testing.expectEqual(true, permissions.whitelist.map.contains(item.*));
	}
}
