const builtin = @import("builtin");
const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const sync = main.sync;

const PlayerRecord = struct { playerIndex: usize, blocked: bool };

var playerDatabase: std.StringHashMapUnmanaged(PlayerRecord) = undefined;
var localPlayerIndex: usize = undefined;
var nextPlayerIndex: std.atomic.Value(usize) = undefined;
var worldPath: []const u8 = undefined;

var mutex: main.utils.Mutex = .{};

fn init(path: []const u8, loadedLocalPlayerIndex: usize) void {
	sync.threadContext.assertCorrectContext(.server);
	worldPath = main.worldArena.dupe(u8, path);
	localPlayerIndex = loadedLocalPlayerIndex;
	playerDatabase = .{};
	nextPlayerIndex = .init(0);
}

pub fn loadPlayerLoginInfo(dir: main.files.Dir, path: []const u8, loadedLocalPlayerIndex: usize) !void {
	init(path, loadedLocalPlayerIndex);

	var playerDir = try dir.openIterableDir("players");
	defer playerDir.close();
	var iterator = playerDir.iterate();
	while (try iterator.next(main.io)) |file| {
		if (file.kind == .file and std.mem.endsWith(u8, file.name, ".zon")) {
			const zon = try playerDir.readToZon(main.stackAllocator, file.name);
			defer zon.deinit(main.stackAllocator);
			const fileNameBase = file.name[0..std.mem.findScalar(u8, file.name, '.').?];
			if (fileNameBase[0] == '0' and fileNameBase.len != 1) {
				std.log.err("Player file {s} contains leading zeroes. Skipping.", .{file.name});
				continue;
			}
			const index = std.fmt.parseInt(usize, fileNameBase, 10) catch |err| {
				std.log.err("Couldn't parse player file {s}: {s} Skipping.", .{file.name, @errorName(err)});
				continue;
			};
			_ = nextPlayerIndex.fetchMax(index + 1, .monotonic);
			const blocked = zon.get(bool, "blocked") orelse false;
			if (zon.get([]const u8, "publicKey")) |key| {
				const keyType = key[0 .. std.mem.findScalar(u8, key, ':') orelse {
					std.log.err("Player file {s} has invalid key entry {s}: Type is missing. Skipping.", .{file.name, key});
					continue;
				}];
				_ = std.meta.stringToEnum(main.network.authentication.KeyTypeEnum, keyType) orelse {
					std.log.err("Player file {s} has invalid key type {s}. Skipping.", .{file.name, keyType});
					continue;
				};
				playerDatabase.put(main.worldArena.allocator, main.worldArena.dupe(u8, key), .{.playerIndex = index, .blocked = blocked}) catch unreachable;
			} else if (index != localPlayerIndex) {
				const name = zon.get([]const u8, "name") orelse {
					std.log.err("Couldn't read player file {s}. Skipping.", .{file.name});
					continue;
				};
				const fullEntry = main.worldArena.print("name:{s}", .{name});
				playerDatabase.put(main.worldArena.allocator, fullEntry, .{.playerIndex = index, .blocked = blocked}) catch unreachable;
			}
		}
	}
}

pub fn getLocalPlayerIndex() usize {
	return localPlayerIndex;
}

pub fn lookupIndex(key: []const u8) ?usize {
	mutex.lock();
	defer mutex.unlock();
	const entry = playerDatabase.get(key) orelse return null;
	return entry.playerIndex;
}

pub fn isEmpty() bool {
	mutex.lock();
	defer mutex.unlock();
	return playerDatabase.size == 0;
}

pub fn allocateNewIndex() usize {
	mutex.lock();
	defer mutex.unlock();
	return nextPlayerIndex.fetchAdd(1, .monotonic);
}

pub fn rebindKey(oldPublicKeyFromFile: ?[]const u8, oldNameFromFile: ?[]const u8, newKey: []const u8, index: usize) void {
	sync.threadContext.assertCorrectContext(.server);
	mutex.lock();
	defer mutex.unlock();
	var blocked = false;
	if (oldPublicKeyFromFile) |publicKey| {
		blocked = playerDatabase.fetchRemove(publicKey).?.value.blocked;
	} else {
		removeOld: {
			const nameEntry = main.stackAllocator.print("name:{s}", .{oldNameFromFile orelse break :removeOld});
			defer main.stackAllocator.free(nameEntry);
			if (playerDatabase.fetchRemove(nameEntry)) |kv| blocked = kv.value.blocked;
		}
	}
	playerDatabase.put(main.worldArena.allocator, main.worldArena.dupe(u8, newKey), .{.playerIndex = index, .blocked = blocked}) catch unreachable;
}

fn saveNewPlayer(key: []const u8, index: usize) void {
	const playersDir = main.stackAllocator.print("saves/{s}/players", .{worldPath});
	defer main.stackAllocator.free(playersDir);
	main.files.cubyzDir().makePath(playersDir) catch |err| {
		std.log.err("Couldn't create players directory: {t}", .{err});
	};

	const path = main.stackAllocator.print("saves/{s}/players/{}.zon", .{worldPath, index});
	defer main.stackAllocator.free(path);

	const zon: ZonElement = .initObject(main.stackAllocator);
	defer zon.deinit(main.stackAllocator);
	zon.put("publicKey", key);

	main.files.cubyzDir().writeZon(path, zon) catch |err| {
		std.log.err("Couldn't create player file for pre-authorized key {s}: {t}", .{key, err});
	};
}

const EnsureResult = struct { entry: *PlayerRecord, wasNew: bool };

fn ensurePlayerRecord(key: []const u8) EnsureResult {
	sync.threadContext.assertCorrectContext(.server);

	const result = playerDatabase.getOrPut(main.worldArena.allocator, key) catch unreachable;
	if (result.found_existing) return .{.entry = result.value_ptr, .wasNew = false};

	result.key_ptr.* = main.worldArena.dupe(u8, key);
	result.value_ptr.* = .{.playerIndex = nextPlayerIndex.fetchAdd(1, .monotonic), .blocked = false};

	if (!builtin.is_test) {
		saveNewPlayer(key, result.value_ptr.playerIndex);
	}

	return .{.entry = result.value_ptr, .wasNew = true};
}

fn saveBlocked(index: usize, value: bool) void {
	if (builtin.is_test) return;
	sync.threadContext.assertCorrectContext(.server);

	const path = main.stackAllocator.print("saves/{s}/players/{}.zon", .{worldPath, index});
	defer main.stackAllocator.free(path);

	var zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, path) catch .null;
	defer zon.deinit(main.stackAllocator);
	if (zon != .object) {
		zon.deinit(main.stackAllocator);
		zon = .initObject(main.stackAllocator);
	}
	zon.put("blocked", value);

	main.files.cubyzDir().writeZon(path, zon) catch |err| {
		std.log.err("Couldn't update blocked state for player {}: {t}", .{index, err});
	};
}

const AddResult = enum { added, alreadyAllowed };

pub fn add(key: []const u8) AddResult {
	mutex.lock();
	defer mutex.unlock();
	const result = ensurePlayerRecord(key);
	const wasBlocked = result.entry.blocked;
	result.entry.blocked = false;
	if (wasBlocked) saveBlocked(result.entry.playerIndex, false);
	return if (result.wasNew or wasBlocked) .added else .alreadyAllowed;
}

const BlockResult = enum { blocked, alreadyBlocked };

pub fn block(key: []const u8) BlockResult {
	mutex.lock();
	defer mutex.unlock();
	const result = ensurePlayerRecord(key);
	const wasBlocked = result.entry.blocked;
	result.entry.blocked = true;
	if (!wasBlocked) saveBlocked(result.entry.playerIndex, true);
	return if (result.wasNew or !wasBlocked) .blocked else .alreadyBlocked;
}

pub fn isAllowedToJoin(key: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	mutex.lock();
	defer mutex.unlock();
	const entry = playerDatabase.get(key) orelse return false;
	return !entry.blocked;
}

test "addContainsRemove" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();

	init("test", 0);

	try std.testing.expectEqual(false, isAllowedToJoin("ed25519:abc"));
	try std.testing.expectEqual(.added, add("ed25519:abc"));
	try std.testing.expectEqual(.alreadyAllowed, add("ed25519:abc"));
	try std.testing.expectEqual(true, isAllowedToJoin("ed25519:abc"));
	try std.testing.expectEqual(.blocked, block("ed25519:abc"));
	try std.testing.expectEqual(.alreadyBlocked, block("ed25519:abc"));
	try std.testing.expectEqual(false, isAllowedToJoin("ed25519:abc"));
}

test "addUnblocks" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();

	init("test", 0);

	try std.testing.expectEqual(.blocked, block("ed25519:xyz"));
	try std.testing.expectEqual(false, isAllowedToJoin("ed25519:xyz"));
	try std.testing.expectEqual(.added, add("ed25519:xyz"));
	try std.testing.expectEqual(true, isAllowedToJoin("ed25519:xyz"));
}

test "knownPlayerAllowedByDefaultButBlockable" {
	main.heap.allocators.createWorldArena();
	defer main.heap.allocators.destroyWorldArena();

	init("test", 0);

	playerDatabase.put(main.worldArena.allocator, main.worldArena.dupe(u8, "ed25519:known"), .{.playerIndex = 0, .blocked = false}) catch unreachable;

	try std.testing.expectEqual(true, isAllowedToJoin("ed25519:known"));
	try std.testing.expectEqual(false, isAllowedToJoin("ed25519:unknown"));

	try std.testing.expectEqual(.blocked, block("ed25519:known"));
	try std.testing.expectEqual(false, isAllowedToJoin("ed25519:known"));

	try std.testing.expectEqual(.added, add("ed25519:known"));
	try std.testing.expectEqual(true, isAllowedToJoin("ed25519:known"));
}
