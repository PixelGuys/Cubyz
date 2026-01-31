const std = @import("std");

const main = @import("main");
const server = main.server;
const User = server.User;

pub const ListType = enum {
	white,
	black,
};

pub const PermissionGroup = struct {
	permissionWhiteList: std.StringHashMapUnmanaged(void) = .{},
	permissionBlackList: std.StringHashMapUnmanaged(void) = .{},

	pub fn deinit(self: *PermissionGroup) void {
		self.permissionWhiteList.deinit(main.globalAllocator.allocator);
		self.permissionBlackList.deinit(main.globalAllocator.allocator);
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

pub fn init() void {
	groups = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	var it = groups.iterator();
	while (it.next()) |entry| {
		entry.value_ptr.deinit();
	}
	groups.deinit();
}

pub fn createGroup(name: []const u8) error{Invalid}!void {
	if (groups.contains(name)) return error.Invalid;
	groups.put(name, .{}) catch unreachable;
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
			.white => group.permissionWhiteList.put(main.globalAllocator.allocator, permissionPath, {}) catch unreachable,
			.black => group.permissionBlackList.put(main.globalAllocator.allocator, permissionPath, {}) catch unreachable,
		}
	}
}

pub fn addUserPermission(user: *User, listType: ListType, permissionPath: []const u8) void {
	switch (listType) {
		.white => user.permissionWhiteList.put(main.globalAllocator.allocator, permissionPath, {}) catch unreachable,
		.black => user.permissionBlackList.put(main.globalAllocator.allocator, permissionPath, {}) catch unreachable,
	}
}

pub fn addUserToGroup(user: *User, name: []const u8) error{Invalid}!void {
	if (groups.getPtr(name)) |group| {
		user.permissionGroups.put(main.globalAllocator.allocator, name, group) catch unreachable;
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
