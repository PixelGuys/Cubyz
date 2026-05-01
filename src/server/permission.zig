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

pub const Group = struct { // MARK: Group
	permissions: Permissions,
	// Each group must have a unique ID to avoid stale membership issues.
	// Example scenario:
	// - User1 joins Group1
	// - Group1 is deleted while User1 is offline (so their data isn’t updated)
	// - A new Group1 is created
	// - When User1 reconnects, they are incorrectly treated as a member of the new Group1
	id: u32,
	updated: bool = false,

	pub fn init(allocator: NeverFailingAllocator) *Group {
		sync.threadContext.assertCorrectContext(.server);
		currentId += 1;
		updatedMetadata = true;
		const self = allocator.create(Group);
		self.* = .{
			.permissions = .init(allocator),
			.id = currentId,
			.updated = true,
		};
		return self;
	}

	pub fn fromZon(allocator: NeverFailingAllocator, zon: ZonElement, id: u32) *Group {
		sync.threadContext.assertCorrectContext(.server);
		const self = allocator.create(Group);
		self.* = .{
			.permissions = .init(allocator),
			.id = id,
		};
		self.permissions.fromZon(zon);
		return self;
	}

	pub fn toZon(self: *Group, allocator: NeverFailingAllocator, zon: *ZonElement) void {
		sync.threadContext.assertCorrectContext(.server);
		self.permissions.toZon(allocator, zon);
	}

	pub fn deinit(self: *Group, allocator: NeverFailingAllocator) void {
		sync.threadContext.assertCorrectContext(.server);
		self.permissions.deinit();
		allocator.destroy(self);
	}

	pub fn addPermission(self: *Group, listType: Permissions.ListType, permissionPath: []const u8) void {
		sync.threadContext.assertCorrectContext(.server);
		self.permissions.addPermission(listType, permissionPath);
		self.updated = true;
	}

	pub fn removePermission(self: *Group, listType: Permissions.ListType, permissionPath: []const u8) bool {
		sync.threadContext.assertCorrectContext(.server);
		const result = self.permissions.removePermission(listType, permissionPath);
		if (result) self.updated = true;
		return result;
	}

	pub fn hasPermission(self: *Group, permissionPath: []const u8) Permissions.PermissionResult {
		sync.threadContext.assertCorrectContext(.server);
		return self.permissions.hasPermission(permissionPath);
	}
};

var groups: std.StringHashMapUnmanaged(*Group) = .{};
var groupDeinitList: main.utils.ConcurrentQueue(u32) = undefined;

var groupsArena: NeverFailingArenaAllocator = undefined;
var currentId: u32 = 0; // Needed to identify groups even after deletion, so that players who join a server after deletion of a group don't automatically join another group witht the same name.
var updatedMetadata: bool = true;

pub fn init(allocator: NeverFailingAllocator, _currentId: u32) void {
	sync.threadContext.assertCorrectContext(.server);
	groupsArena = .init(allocator);
	groupDeinitList = .init(groupsArena.allocator(), 16);
	currentId = _currentId;
}

pub fn deinit() void {
	sync.threadContext.assertCorrectContext(.server);
	groupsArena.deinit();
	groups = .{};
}

pub fn addGroupFromZon(id: u32, zon: ZonElement) void {
	const name = zon.get(?[]const u8, "name", null) orelse {
		std.log.err("Group with id {d} has invalid content skipping", .{id});
		return;
	};
	groups.put(groupsArena.allocator().allocator, groupsArena.allocator().dupe(u8, name), .fromZon(groupsArena.allocator(), zon, id)) catch unreachable;
}

pub fn loadGroups(dir: main.files.Dir) !void {
	const metaDataZon: ZonElement = dir.readToZon(main.stackAllocator, "metadata.zon") catch .initObject(main.stackAllocator);
	defer metaDataZon.deinit(main.stackAllocator);

	init(main.globalAllocator, metaDataZon.get(u32, "currentId", 0));

	var iterator = dir.iterate();
	while (try iterator.next(main.io)) |file| {
		if (file.kind != .file) continue;
		if (!std.mem.endsWith(u8, file.name, ".zon")) continue;

		const zon = try dir.readToZon(main.stackAllocator, file.name);
		defer zon.deinit(main.stackAllocator);
		if (std.mem.eql(u8, file.name, "metadata.zon")) continue;
		const fileNameBase = file.name[0 .. std.mem.findScalar(u8, file.name, '.') orelse unreachable];
		if (fileNameBase[0] == '0' and fileNameBase.len != 1) {
			std.log.err("Group file {s} contains leading zeroes. Skipping.", .{file.name});
			continue;
		}
		const id = std.fmt.parseInt(u32, fileNameBase, 10) catch |err| {
			std.log.err("Couldn't parse group file {s}: {s} Skipping.", .{file.name, @errorName(err)});
			continue;
		};
		addGroupFromZon(id, zon);
	}
}

pub fn saveGroups(allocator: NeverFailingAllocator, groupsPath: []const u8) !void {
	sync.threadContext.assertCorrectContext(.server);

	try saveMetaData(allocator, groupsPath);

	while (groupDeinitList.popFront()) |id| {
		const path = std.fmt.allocPrint(allocator.allocator, "{s}/{d}.zon", .{groupsPath, id}) catch unreachable;
		defer allocator.free(path);
		if (main.files.cubyzDir().hasFile(path)) {
			try main.files.cubyzDir().deleteFile(path);
		}
	}

	var it = groups.iterator();
	while (it.next()) |group| {
		if (!group.value_ptr.*.updated) continue;
		group.value_ptr.*.updated = false;

		const path = std.fmt.allocPrint(allocator.allocator, "{s}/{d}.zon", .{groupsPath, group.value_ptr.*.id}) catch unreachable;
		defer allocator.free(path);
		var groupZon: ZonElement = .initObject(allocator);
		defer groupZon.deinit(allocator);
		groupZon.put("name", group.key_ptr.*);
		group.value_ptr.*.toZon(allocator, &groupZon);
		try main.files.cubyzDir().writeZon(path, groupZon);
	}
}

fn saveMetaData(allocator: NeverFailingAllocator, groupsPath: []const u8) !void {
	if (!updatedMetadata) return;
	updatedMetadata = false;

	const metadatPath = std.fmt.allocPrint(allocator.allocator, "{s}/metadata.zon", .{groupsPath}) catch unreachable;
	defer allocator.free(metadatPath);
	var metadataZon: ZonElement = .initObject(main.stackAllocator);
	defer metadataZon.deinit(main.stackAllocator);
	metadataZon.put("currentId", currentId);
	try main.files.cubyzDir().writeZon(metadatPath, metadataZon);
}

pub fn createGroup(name: []const u8) error{AlreadyExists}!void {
	sync.threadContext.assertCorrectContext(.server);
	const result = groups.getOrPut(groupsArena.allocator().allocator, name) catch unreachable;
	if (result.found_existing) return error.AlreadyExists;

	result.key_ptr.* = groupsArena.allocator().dupe(u8, name);
	result.value_ptr.* = .init(groupsArena.allocator());
}

pub fn getGroup(name: []const u8) error{GroupNotFound}!*Group {
	sync.threadContext.assertCorrectContext(.server);
	return (groups.getPtr(name) orelse return error.GroupNotFound).*;
}

pub fn deleteGroup(name: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	const group = groups.fetchRemove(name) orelse return false;
	groupDeinitList.pushBack(group.value.id);
	return true;
}

// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// MARK: Testing
// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

test "whitePermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");
	try std.testing.expectEqual(.yes, permissions.hasPermission("/command/test"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/command"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/"));
}

test "blacklist" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command");
	permissions.addPermission(.black, "/command/test");

	try std.testing.expectEqual(.no, permissions.hasPermission("/command/test"));
	try std.testing.expectEqual(.yes, permissions.hasPermission("/command"));
	try std.testing.expectEqual(.neutral, permissions.hasPermission("/"));
}

test "deepPermission" {
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

test "rootPermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/");

	try std.testing.expectEqual(.yes, permissions.hasPermission("/command/test"));
}

test "rootBlackPermission" {
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

test "removeNonExistentPermission" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");

	try std.testing.expectEqual(false, permissions.removePermission(.white, "/command/test2"));
}

test "groupCreation" {
	init(main.heap.testingAllocator, 0);
	defer deinit();

	try createGroup("test");
	_ = try getGroup("test");
}

test "groupPermissions" {
	init(main.heap.testingAllocator, 0);
	defer deinit();

	try createGroup("test");
	const group = try getGroup("test");
	group.addPermission(.white, "/command/test");
	try std.testing.expectEqual(Permissions.PermissionResult.yes, group.hasPermission("/command/test"));
}

test "groupRemovePermissions" {
	init(main.heap.testingAllocator, 0);
	defer deinit();

	try createGroup("test");
	const group = try getGroup("test");
	group.addPermission(.white, "/command/test");
	try std.testing.expectEqual(true, group.removePermission(.white, "/command/test"));
}

test "invalidGroup" {
	init(main.heap.testingAllocator, 0);
	defer deinit();

	try createGroup("test");
	try std.testing.expectError(error.GroupNotFound, getGroup("root"));
}

test "invalidGroupEmptyGroups" {
	init(main.heap.testingAllocator, 0);
	defer deinit();

	try std.testing.expectError(error.GroupNotFound, getGroup("root"));
}

test "invalidGroupCreation" {
	init(main.heap.testingAllocator, 0);
	defer deinit();

	try createGroup("test");
	try std.testing.expectError(error.AlreadyExists, createGroup("test"));
}

test "permissionListToFromZon" {
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
