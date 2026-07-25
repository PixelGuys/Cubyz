const builtin = @import("builtin");
const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const sync = main.sync;

var allowed: std.StringHashMapUnmanaged(void) = .{};
var blocked: std.StringHashMapUnmanaged(void) = .{};

pub fn init() void {
	sync.threadContext.assertCorrectContext(.server);
	allowed = .{};
	blocked = .{};
}

pub fn deinit() void {
	sync.threadContext.assertCorrectContext(.server);
	allowed = .{};
	blocked = .{};
}

pub fn load(dir: main.files.Dir) void {
	sync.threadContext.assertCorrectContext(.server);
	init();

	const zon = dir.readToZon(main.stackAllocator, "whitelist.zon") catch .null;
	defer zon.deinit(main.stackAllocator);

	loadSet(&allowed, zon.getChild("allowed"));
	loadSet(&blocked, zon.getChild("blocked"));
}

fn loadSet(set: *std.StringHashMapUnmanaged(void), zon: ZonElement) void {
	for (zon.toSlice()) |item| {
		const key = item.as([]const u8) orelse continue;
		set.put(main.worldArena.allocator, main.worldArena.dupe(u8, key), {}) catch unreachable;
	}
}

fn save() void {
	if (builtin.is_test) return;
	sync.threadContext.assertCorrectContext(.server);

	const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/whitelist.zon", .{main.server.world.?.path}) catch unreachable;
	defer main.stackAllocator.free(path);

	var zon: ZonElement = .initObject(main.stackAllocator);
	defer zon.deinit(main.stackAllocator);
	zon.put("allowed", setToZon(allowed));
	zon.put("blocked", setToZon(blocked));

	main.files.cubyzDir().writeZon(path, zon) catch |err| {
		std.log.err("Couldn't save whitelist: {t}", .{err});
	};
}

fn setToZon(set: std.StringHashMapUnmanaged(void)) ZonElement {
	const zon: ZonElement = .initArray(main.stackAllocator);
	var it = set.keyIterator();
	while (it.next()) |key| {
		zon.append(key.*);
	}
	return zon;
}

pub const AddResult = enum { added, alreadyAllowed };
pub const RemoveResult = enum { blocked, alreadyBlocked };

pub fn add(key: []const u8) AddResult {
	sync.threadContext.assertCorrectContext(.server);
	const wasBlocked = blocked.remove(key);
	const result = allowed.getOrPut(main.worldArena.allocator, key) catch unreachable;
	if (!result.found_existing) result.key_ptr.* = main.worldArena.dupe(u8, key);
	const changed = wasBlocked or !result.found_existing;
	if (changed) save();
	return if (changed) .added else .alreadyAllowed;
}

pub fn remove(key: []const u8) RemoveResult {
	sync.threadContext.assertCorrectContext(.server);
	const wasAllowed = allowed.remove(key);
	const result = blocked.getOrPut(main.worldArena.allocator, key) catch unreachable;
	if (!result.found_existing) result.key_ptr.* = main.worldArena.dupe(u8, key);
	const changed = wasAllowed or !result.found_existing;
	if (changed) save();
	return if (changed) .blocked else .alreadyBlocked;
}

pub fn contains(key: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	if (blocked.contains(key)) return false;
	if (allowed.contains(key)) return true;
	if (main.server.world) |world| return world.playerDatabase.contains(key);
	return false;
}

test "addContainsRemove" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();
	init();
	defer deinit();

	try std.testing.expectEqual(false, contains("ed25519:abc"));
	try std.testing.expectEqual(.added, add("ed25519:abc"));
	try std.testing.expectEqual(.alreadyAllowed, add("ed25519:abc"));
	try std.testing.expectEqual(true, contains("ed25519:abc"));
	try std.testing.expectEqual(.blocked, remove("ed25519:abc"));
	try std.testing.expectEqual(.alreadyBlocked, remove("ed25519:abc"));
	try std.testing.expectEqual(false, contains("ed25519:abc"));
}

test "addUnblocks" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();
	init();
	defer deinit();

	try std.testing.expectEqual(.blocked, remove("ed25519:xyz"));
	try std.testing.expectEqual(false, contains("ed25519:xyz"));
	try std.testing.expectEqual(.added, add("ed25519:xyz"));
	try std.testing.expectEqual(true, contains("ed25519:xyz"));
}

test "containsFallsBackToPlayerDatabaseAndBlockOverridesIt" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();
	init();
	defer deinit();

	var testWorld: main.server.ServerWorld = undefined;
	testWorld.playerDatabase = .{};
	defer testWorld.playerDatabase.deinit(main.heap.testingAllocator.allocator);
	testWorld.playerDatabase.put(main.heap.testingAllocator.allocator, "ed25519:known", 0) catch unreachable;

	main.server.world = &testWorld;
	defer main.server.world = null;

	try std.testing.expectEqual(true, contains("ed25519:known"));
	try std.testing.expectEqual(false, contains("ed25519:unknown"));

	try std.testing.expectEqual(.blocked, remove("ed25519:known"));
	try std.testing.expectEqual(false, contains("ed25519:known"));

	try std.testing.expectEqual(.added, add("ed25519:known"));
	try std.testing.expectEqual(true, contains("ed25519:known"));
}
