const builtin = @import("builtin");
const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const ZonElement = main.ZonElement;
const sync = main.sync;

pub var enabled: bool = false;

var arena: NeverFailingArenaAllocator = undefined;
var entries: std.StringHashMapUnmanaged(void) = .{};

pub fn init(allocator: NeverFailingAllocator) void {
	sync.threadContext.assertCorrectContext(.server);
	arena = .init(allocator);
	entries = .{};
	enabled = false;
}

pub fn deinit() void {
	sync.threadContext.assertCorrectContext(.server);
	arena.deinit();
	entries = .{};
}

pub fn load(dir: main.files.Dir) void {
	sync.threadContext.assertCorrectContext(.server);
	init(main.globalAllocator);

	const zon = dir.readToZon(main.stackAllocator, "whitelist.zon") catch .null;
	defer zon.deinit(main.stackAllocator);

	enabled = zon.get(bool, "enabled") orelse false;
	for (zon.getChild("keys").toSlice()) |item| {
		const key = item.as([]const u8) orelse continue;
		entries.put(arena.allocator().allocator, arena.allocator().dupe(u8, key), {}) catch unreachable;
	}
}

fn save() void {
	if (builtin.is_test) return;
	sync.threadContext.assertCorrectContext(.server);

	const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/whitelist.zon", .{main.server.world.?.path}) catch unreachable;
	defer main.stackAllocator.free(path);

	var zon: ZonElement = .initObject(main.stackAllocator);
	defer zon.deinit(main.stackAllocator);
	zon.put("enabled", enabled);

	const keysZon: ZonElement = .initArray(main.stackAllocator);
	var it = entries.keyIterator();
	while (it.next()) |key| {
		keysZon.append(key.*);
	}
	zon.put("keys", keysZon);

	main.files.cubyzDir().writeZon(path, zon) catch |err| {
		std.log.err("Couldn't save whitelist: {t}", .{err});
	};
}

pub fn setEnabled(value: bool) void {
	sync.threadContext.assertCorrectContext(.server);
	enabled = value;
	save();
}

pub fn add(key: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	const result = entries.getOrPut(arena.allocator().allocator, key) catch unreachable;
	if (result.found_existing) return false;
	result.key_ptr.* = arena.allocator().dupe(u8, key);
	save();
	return true;
}

pub fn remove(key: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	const result = entries.remove(key);
	if (result) save();
	return result;
}

pub fn contains(key: []const u8) bool {
	sync.threadContext.assertCorrectContext(.server);
	return entries.contains(key);
}

test "addContainsRemove" {
	init(main.heap.testingAllocator);
	defer deinit();

	try std.testing.expectEqual(false, contains("ed25519:abc"));
	try std.testing.expectEqual(true, add("ed25519:abc"));
	try std.testing.expectEqual(false, add("ed25519:abc"));
	try std.testing.expectEqual(true, contains("ed25519:abc"));
	try std.testing.expectEqual(true, remove("ed25519:abc"));
	try std.testing.expectEqual(false, remove("ed25519:abc"));
	try std.testing.expectEqual(false, contains("ed25519:abc"));
}

test "disabledByDefault" {
	init(main.heap.testingAllocator);
	defer deinit();

	try std.testing.expectEqual(false, enabled);
	setEnabled(true);
	try std.testing.expectEqual(true, enabled);
}
