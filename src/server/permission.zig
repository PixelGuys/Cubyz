const builtin = @import("builtin");
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

	pub fn fromBytes(self: *PermissionMap, arena: NeverFailingAllocator, reader: *main.utils.BinaryReader) !void {
		sync.threadContext.assertCorrectContext(.server);
		const len = try reader.readInt(u32);
		self.map.ensureUnusedCapacity(arena.allocator, len) catch unreachable;
		for (0..len) |_| {
			const read = try reader.readSliceWithSize();
			if (read.len == 0 or read[0] != '/') return error.Invalid;
			self.map.putAssumeCapacity(arena.dupe(u8, read), {});
		}
	}

	pub fn toBytes(self: PermissionMap, writer: *main.utils.BinaryWriter) void {
		sync.threadContext.assertCorrectContext(.server);
		writer.writeInt(u32, self.map.count());

		var it = self.map.keyIterator();
		while (it.next()) |key| {
			writer.writeSliceWithSize(key.*);
		}
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

	pub fn deinit(self: Permissions) void {
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

	pub fn fromBytes(self: *Permissions, reader: *main.utils.BinaryReader) !void {
		sync.threadContext.assertCorrectContext(.server);
		try self.list(.white).fromBytes(self.arena.allocator(), reader);
		try self.list(.black).fromBytes(self.arena.allocator(), reader);
	}

	pub fn toBytes(self: Permissions, writer: *main.utils.BinaryWriter) void {
		sync.threadContext.assertCorrectContext(.server);
		self.whitelist.toBytes(writer);
		self.blacklist.toBytes(writer);
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
	name: []const u8,

	fn init(allocator: NeverFailingAllocator, name: []const u8) *Group {
		sync.threadContext.assertCorrectContext(.server);
		saveMetaData(allocator) catch |err| {
			std.log.err("Couldn't save permission groups metadata: {t}", .{err});
		};
		const self = allocator.create(Group);
		self.* = .{
			.permissions = .init(allocator),
			.name = name,
		};
		self.save(allocator);
		return self;
	}

	fn deinit(self: *Group, allocator: NeverFailingAllocator) void {
		sync.threadContext.assertCorrectContext(.server);
		allocator.free(self.name);
		self.permissions.deinit();
		allocator.destroy(self);
	}

	pub fn fromBytes(allocator: NeverFailingAllocator, reader: *main.utils.BinaryReader) !*Group {
		const version = try reader.readInt(u8);
		if (version != 0) return error.UnsupportedVersion;

		const self = allocator.create(Group);
		errdefer allocator.destroy(self);
		self.* = .{
			.permissions = .init(allocator),
			.name = allocator.dupe(u8, try reader.readSliceWithSize()),
		};
		try self.permissions.fromBytes(reader);
		return self;
	}

	pub fn toBytes(self: *Group, writer: *main.utils.BinaryWriter) void {
		sync.threadContext.assertCorrectContext(.server);
		const version = 0;
		writer.writeInt(u8, version);
		writer.writeSliceWithSize(self.name);
		self.permissions.toBytes(writer);
	}

	fn save(self: *Group, allocator: NeverFailingAllocator) void {
		if (builtin.is_test) return;
		sync.threadContext.assertCorrectContext(.server);
		const path = allocator.print("saves/{s}/permission/{d}.group", .{main.server.world.?.path, self.id});
		defer allocator.free(path);

		const writer: main.utils.BinaryWriter = .init(allocator);
		defer writer.deinit();

		self.toBytes(&writer);
		main.files.cubyzDir().write(path, writer.data.items) catch |err| {
			std.log.err("Couldn't save permission group: {s} {t}", .{self.name, err});
		};
	}

	pub fn addPermission(self: *Group, allocator: NeverFailingAllocator, listType: Permissions.ListType, permissionPath: []const u8) void {
		sync.threadContext.assertCorrectContext(.server);
		self.permissions.addPermission(listType, permissionPath);
		self.save(allocator);
	}

	pub fn removePermission(self: *Group, allocator: NeverFailingAllocator, listType: Permissions.ListType, permissionPath: []const u8) bool {
		sync.threadContext.assertCorrectContext(.server);
		const result = self.permissions.removePermission(listType, permissionPath);
		if (result) self.save(allocator);
		return result;
	}

	pub fn hasPermission(self: *Group, permissionPath: []const u8) Permissions.PermissionResult {
		sync.threadContext.assertCorrectContext(.server);
		return self.permissions.hasPermission(permissionPath);
	}
};

// Each group must have a unique ID to avoid stale membership issues.
// Example scenario:
// - User1 joins Group1
// - Group1 is deleted while User1 is offline (so their data isn’t updated)
// - A new Group1 is created
// - When User1 reconnects, they are incorrectly treated as a member of the new Group1
var groups: main.ListManaged(?*Group) = undefined;
var groupNameToIdMap: std.StringHashMapUnmanaged(u32) = .{};

var groupsArena: NeverFailingArenaAllocator = undefined;

pub fn init(allocator: NeverFailingAllocator) void {
	sync.threadContext.assertCorrectContext(.server);
	groupsArena = .init(allocator);
	groups = .init(groupsArena.allocator());
	groupNameToIdMap = .{};
}

pub fn deinit() void {
	sync.threadContext.assertCorrectContext(.server);
	groupsArena.deinit();
	groups = undefined;
	groupNameToIdMap = .{};
}

pub fn addGroupFromBin(id: usize, data: []const u8) void {
	var reader: main.utils.BinaryReader = .init(data);
	const group = Group.fromBytes(groupsArena.allocator(), &reader) catch |err| {
		std.log.err("Group with id {d} has invalid content skipping: {t}", .{id, err});
		groups.append(null);
		return;
	};
	groupNameToIdMap.put(groupsArena.allocator().allocator, group.name, @truncate(groups.items.len)) catch unreachable;
	groups.append(group);
}

pub fn loadGroups(dir: main.files.Dir) !void {
	const metaDataZon: ZonElement = dir.readToZon(main.stackAllocator, "metadata.zon") catch .initObject(main.stackAllocator);
	defer metaDataZon.deinit(main.stackAllocator);

	init(main.globalAllocator);
	const currentId = metaDataZon.get(u32, "currentId") orelse 0;
	groups.ensureCapacity(currentId);

	for (0..currentId) |id| {
		const path = main.stackAllocator.print("{d}.group", .{id});
		defer main.stackAllocator.free(path);

		if (!dir.hasFile(path)) {
			groups.append(null);
			continue;
		}
		const data = try dir.read(main.stackAllocator, path);
		addGroupFromBin(id, data);
	}
}

fn saveMetaData(allocator: NeverFailingAllocator) !void {
	if (builtin.is_test) return;
	const metadatPath = allocator.print("saves/{s}/permission/metadata.zon", .{main.server.world.?.path});
	defer allocator.free(metadatPath);
	var metadataZon: ZonElement = .initObject(main.stackAllocator);
	defer metadataZon.deinit(main.stackAllocator);
	metadataZon.put("currentId", @as(u32, @truncate(groups.items.len)));
	try main.files.cubyzDir().writeZon(metadatPath, metadataZon);
}

pub fn createGroup(name: []const u8) error{AlreadyExists}!void {
	sync.threadContext.assertCorrectContext(.server);

	const result = groupNameToIdMap.getOrPut(groupsArena.allocator().allocator, name) catch unreachable;
	if (result.found_existing) return error.AlreadyExists;

	result.key_ptr.* = groupsArena.allocator().dupe(u8, name);
	result.value_ptr.* = @truncate(groups.items.len);
	groups.append(Group.init(groupsArena.allocator(), result.key_ptr.*));
}

pub fn getGroupByName(name: []const u8) error{GroupNotFound}!*Group {
	sync.threadContext.assertCorrectContext(.server);
	return groups.items[groupNameToIdMap.get(name) orelse return error.GroupNotFound].?;
}

pub fn getGroupById(id: u32) error{GroupNotFound}!*Group {
	sync.threadContext.assertCorrectContext(.server);
	return groups.items[id] orelse error.GroupNotFound;
}

pub fn getGroupIdByName(name: []const u8) error{GroupNotFound}!u32 {
	sync.threadContext.assertCorrectContext(.server);
	return groupNameToIdMap.get(name) orelse error.GroupNotFound;
}

pub fn deleteGroup(allocator: NeverFailingAllocator, name: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	const groupId = (groupNameToIdMap.fetchRemove(name) orelse return false).value;
	groups.items[groupId] = null;

	const path = allocator.print("saves/{s}/permission/{d}.group", .{main.server.world.?.path, groupId});
	defer allocator.free(path);
	main.files.cubyzDir().deleteFile(path) catch |err| {
		std.log.err("Couldn't delete group file even though it exits: {t}", .{err});
	};
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
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test");
	_ = try getGroupByName("test");
}

test "groupPermissions" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test");
	const group = try getGroupByName("test");
	group.addPermission(main.heap.testingAllocator, .white, "/command/test");
	try std.testing.expectEqual(Permissions.PermissionResult.yes, group.hasPermission("/command/test"));
}

test "groupRemovePermissions" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test");
	const group = try getGroupByName("test");
	group.addPermission(main.heap.testingAllocator, .white, "/command/test");
	try std.testing.expectEqual(true, group.removePermission(main.heap.testingAllocator, .white, "/command/test"));
}

test "invalidGroup" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test");
	try std.testing.expectError(error.GroupNotFound, getGroupByName("root"));
}

test "invalidGroupEmptyGroups" {
	init(main.heap.testingAllocator);
	defer deinit();

	try std.testing.expectError(error.GroupNotFound, getGroupByName("root"));
}

test "invalidGroupCreation" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test");
	try std.testing.expectError(error.AlreadyExists, createGroup("test"));
}

test "permissionListToFromBytes" {
	var permissions: Permissions = .init(main.heap.testingAllocator);
	defer permissions.deinit();

	permissions.addPermission(.white, "/command/test");
	permissions.addPermission(.white, "/command/spawn");

	var writer = main.utils.BinaryWriter.init(main.heap.testingAllocator);
	defer writer.deinit();
	permissions.toBytes(&writer);

	var testPermissions: Permissions = .init(main.heap.testingAllocator);
	defer testPermissions.deinit();

	var reader: main.utils.BinaryReader = .init(writer.data.items);
	try testPermissions.fromBytes(&reader);

	try std.testing.expectEqual(2, testPermissions.whitelist.map.size);

	var it = testPermissions.whitelist.map.keyIterator();
	while (it.next()) |item| {
		try std.testing.expectEqual(true, permissions.whitelist.map.contains(item.*));
	}
}

test "permissionGroupToFromBytes" {
	init(main.heap.testingAllocator);
	defer deinit();

	try createGroup("test");
	const group = try getGroupByName("test");

	group.addPermission(main.heap.testingAllocator, .white, "/command/test");
	group.addPermission(main.heap.testingAllocator, .white, "/command/spawn");

	var writer: main.utils.BinaryWriter = .init(main.heap.testingAllocator);
	defer writer.deinit();
	group.toBytes(&writer);

	var reader: main.utils.BinaryReader = .init(writer.data.items);
	var testGroup: *Group = try .fromBytes(main.heap.testingAllocator, &reader);
	defer testGroup.deinit(main.heap.testingAllocator);

	try std.testing.expectEqual(2, testGroup.permissions.whitelist.map.size);

	var it = testGroup.permissions.whitelist.map.keyIterator();
	while (it.next()) |item| {
		try std.testing.expectEqual(true, group.permissions.whitelist.map.contains(item.*));
	}
}
