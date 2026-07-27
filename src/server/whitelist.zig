const builtin = @import("builtin");
const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const sync = main.sync;
const Vec3d = main.vec.Vec3d;

pub const AddResult = enum { added, alreadyAllowed };
pub const RemoveResult = enum { blocked, alreadyBlocked };

const EnsureResult = struct { index: usize, wasNew: bool };

fn ensurePlayerRecord(key: []const u8) EnsureResult {
	sync.threadContext.assertCorrectContext(.server);
	const world = main.server.world.?;

	if (world.playerDatabase.get(key)) |index| return .{.index = index, .wasNew = false};

	const index = world.nextPlayerIndex.fetchAdd(1, .monotonic);
	world.playerDatabase.put(main.worldArena.allocator, main.worldArena.dupe(u8, key), index) catch unreachable;

	if (!builtin.is_test) {
		const playersDir = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players", .{world.path}) catch unreachable;
		defer main.stackAllocator.free(playersDir);
		main.files.cubyzDir().makePath(playersDir) catch |err| {
			std.log.err("Couldn't create players directory: {t}", .{err});
		};

		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players/{}.zon", .{world.path, index}) catch unreachable;
		defer main.stackAllocator.free(path);

		const zon: ZonElement = .initObject(main.stackAllocator);
		defer zon.deinit(main.stackAllocator);
		zon.put("publicKey", key);
		const entityZon: ZonElement = .initObject(main.stackAllocator);
		entityZon.put("position", @as(Vec3d, @floatFromInt(world.spawn)));
		zon.put("entity", entityZon);

		main.files.cubyzDir().writeZon(path, zon) catch |err| {
			std.log.err("Couldn't create player file for pre-authorized key {s}: {t}", .{key, err});
		};
	}

	return .{.index = index, .wasNew = true};
}

fn setBlocked(index: usize, value: bool) void {
	sync.threadContext.assertCorrectContext(.server);
	const world = main.server.world.?;

	if (value) {
		world.blockedPlayers.put(main.worldArena.allocator, index, {}) catch unreachable;
	} else {
		_ = world.blockedPlayers.remove(index);
	}

	if (!builtin.is_test) {
		const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players/{}.zon", .{world.path, index}) catch unreachable;
		defer main.stackAllocator.free(path);

		var zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, path) catch .null;
		defer zon.deinit(main.stackAllocator);
		if (zon != .object) {
			zon.deinit(main.stackAllocator);
			zon = ZonElement.initObject(main.stackAllocator);
		}
		zon.put("blocked", value);

		main.files.cubyzDir().writeZon(path, zon) catch |err| {
			std.log.err("Couldn't update blocked state for player {}: {t}", .{index, err});
		};
	}
}

pub fn add(key: []const u8) AddResult {
	const result = ensurePlayerRecord(key);
	const wasBlocked = main.server.world.?.blockedPlayers.contains(result.index);
	if (wasBlocked) setBlocked(result.index, false);
	return if (result.wasNew or wasBlocked) .added else .alreadyAllowed;
}

pub fn remove(key: []const u8) RemoveResult {
	const result = ensurePlayerRecord(key);
	const wasBlocked = main.server.world.?.blockedPlayers.contains(result.index);
	if (!wasBlocked) setBlocked(result.index, true);
	return if (result.wasNew or !wasBlocked) .blocked else .alreadyBlocked;
}

pub fn contains(key: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	const world = main.server.world orelse return false;
	const index = world.playerDatabase.get(key) orelse return false;
	return !world.blockedPlayers.contains(index);
}

test "addContainsRemove" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();

	var testWorld: main.server.ServerWorld = undefined;
	testWorld.playerDatabase = .{};
	testWorld.blockedPlayers = .{};
	testWorld.nextPlayerIndex = .init(0);
	main.server.world = &testWorld;
	defer main.server.world = null;

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

	var testWorld: main.server.ServerWorld = undefined;
	testWorld.playerDatabase = .{};
	testWorld.blockedPlayers = .{};
	testWorld.nextPlayerIndex = .init(0);
	main.server.world = &testWorld;
	defer main.server.world = null;

	try std.testing.expectEqual(.blocked, remove("ed25519:xyz"));
	try std.testing.expectEqual(false, contains("ed25519:xyz"));
	try std.testing.expectEqual(.added, add("ed25519:xyz"));
	try std.testing.expectEqual(true, contains("ed25519:xyz"));
}

test "knownPlayerAllowedByDefaultButBlockable" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();

	var testWorld: main.server.ServerWorld = undefined;
	testWorld.playerDatabase = .{};
	testWorld.blockedPlayers = .{};
	testWorld.nextPlayerIndex = .init(0);
	main.server.world = &testWorld;
	defer main.server.world = null;

	testWorld.playerDatabase.put(main.worldArena.allocator, main.worldArena.dupe(u8, "ed25519:known"), 0) catch unreachable;

	try std.testing.expectEqual(true, contains("ed25519:known"));
	try std.testing.expectEqual(false, contains("ed25519:unknown"));

	try std.testing.expectEqual(.blocked, remove("ed25519:known"));
	try std.testing.expectEqual(false, contains("ed25519:known"));

	try std.testing.expectEqual(.added, add("ed25519:known"));
	try std.testing.expectEqual(true, contains("ed25519:known"));
}
