const std = @import("std");
const main = @import("main");
const User = main.server.User;
const chunk = main.chunk;

pub const description = "Configure chest security, view status, or share access.";
pub const usage =
\\/lock - Shows available subcommands
\\/lock status - Checks security of the target chest
\\/lock private - Restricts chest to yourself
\\/lock public - Opens chest to everyone
\\/lock add <player_name> - Whitelists a friend to access this chest
;

pub fn execute(args: []const u8, source: *User) void {
    const clean_args = std.mem.trim(u8, args, &std.ascii.whitespace);

    // 1. Root command
    if (clean_args.len == 0) {
        source.sendMessage("#ffff00--- Chest Lock Choices ---", .{});
        source.sendMessage("#ffffff/lock private - Protect chest", .{});
        source.sendMessage("#ffffff/lock public - Unprotect / Clear rules", .{});
        source.sendMessage("#ffffff/lock status - View ownership details", .{});
        source.sendMessage("#ffffff/lock add <name> - Grant a friend access", .{});
        return;
    }

    // Scan for chest position underneath/around the player
    const prof = source.player();
    const wx: i32 = @intFromFloat(@floor(prof.pos[0]));
    const wy: i32 = @intFromFloat(@floor(prof.pos[1]));
    const wz: i32 = @intFromFloat(@floor(prof.pos[2]));
    const world = main.server.world.?;

    var found_x: i32 = wx;
    var found_y: i32 = wy;
    var found_z: i32 = wz;
    var chest_found = false;

    outer: for (0..3) |dx| {
        for (0..5) |dy| {
            for (0..3) |dz| {
                const tx = wx + @as(i32, @intCast(dx)) - 1;
                const ty = wy + @as(i32, @intCast(dy)) - 2;
                const tz = wz + @as(i32, @intCast(dz)) - 1;
                if (world.getBlock(tx, ty, tz)) |b| {
                    if (std.mem.startsWith(u8, b.id(), "cubyz:chest")) {
                        found_x = tx;
                        found_y = ty;
                        found_z = tz;
                        chest_found = true;
                        break :outer;
                    }
                }
            }
        }
    }

    if (!chest_found) {
        source.sendMessage("#ff0000Error: Stand right next to or on top of a chest.", .{});
        return;
    }

    const globalPos = main.vec.Vec3i{ found_x, found_y, found_z };
    const storage = @import("../storage.zig");
    const player_key: []const u8 = source.newKeyString orelse source.name;

    // 2. Handle "/lock status"
    if (std.mem.eql(u8, clean_args, "status")) {
        if (storage.chest_locks.get(globalPos)) |lock| {
            const rule_str = if (lock.lock_type == 1) "PRIVATE" else "PUBLIC";
            source.sendMessage("#00ffff--- Chest Status ---", .{});
            source.sendMessage("#ffffffAccess: {s}", .{rule_str});
            source.sendMessage("#ffffffOwner: {s}", .{lock.owner_key});
            if (lock.allowed_keys.len > 0) {
                source.sendMessage("#ffffffShared With: {s}", .{lock.allowed_keys});
            }
        } else {
            source.sendMessage("#00ff00This chest is completely unowned and free to claim.", .{});
        }
        return;
    }

    // 3. Handle "/lock add <player_name>"
    if (std.mem.startsWith(u8, clean_args, "add ")) {
        const friend_name = std.mem.trim(u8, clean_args[4..], &std.ascii.whitespace);
        if (friend_name.len == 0) {
            source.sendMessage("#ff0000Specify a player name! Usage: /lock add <name>", .{});
            return;
        }

        if (storage.chest_locks.get(globalPos)) |lock| {
            if (!std.mem.eql(u8, player_key, lock.owner_key)) {
                source.sendMessage("#ff0000You do not own this chest!", .{});
                return;
            }


            const server_mod = @import("../server.zig");
            const userList = server_mod.getUserListAndIncreaseRefCount(main.stackAllocator);
            defer server_mod.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);

            var opt_friend_key: ?[]const u8 = null;
            for (userList) |u| {
                if (std.mem.eql(u8, u.name, friend_name)) {
                    opt_friend_key = u.newKeyString orelse u.name;
                    break;
                }
            }

            const friend_key = opt_friend_key orelse friend_name;

            var new_allowed: []const u8 = "";
            if (lock.allowed_keys.len == 0) {
                new_allowed = main.globalAllocator.dupe(u8, friend_key);
            } else {
                new_allowed = std.fmt.allocPrint(main.globalAllocator.allocator, "{s},{s}", .{lock.allowed_keys, friend_key}) catch friend_key;
                main.globalAllocator.free(lock.allowed_keys);
            }

            var updated_lock = lock;
            updated_lock.allowed_keys = new_allowed;
            storage.chest_locks.put(globalPos, updated_lock) catch {};

            source.sendMessage("#00ff00Successfully granted chest access to {s}!", .{friend_name});
            baseChunkUpdate(found_x, found_y, found_z);
        } else {
            source.sendMessage("#ff0000Claim the chest first using /lock private", .{});
        }
        return;
    }

    var lock_type: u8 = 1;
    if (std.mem.eql(u8, clean_args, "public")) {
        lock_type = 0;
    }

    if (storage.chest_locks.get(globalPos)) |lock| {
        if (!std.mem.eql(u8, player_key, lock.owner_key)) {
            source.sendMessage("#ff0000This chest belongs to another player!", .{});
            return;
        }

        main.globalAllocator.free(lock.owner_key);
        main.globalAllocator.free(lock.allowed_keys);
        _ = storage.chest_locks.remove(globalPos);

        if (lock_type == 0) {
            source.sendMessage("#00ff00Chest configuration cleared! It is now PUBLIC.", .{});
            baseChunkUpdate(found_x, found_y, found_z);
            return;
        }
    }

    const allocated_key = main.globalAllocator.dupe(u8, player_key);
    const empty_allowed = main.globalAllocator.dupe(u8, "");

    storage.chest_locks.put(globalPos, .{
        .owner_key = allocated_key,
        .lock_type = lock_type,
        .allowed_keys = empty_allowed,
    }) catch {
        main.globalAllocator.free(allocated_key);
        main.globalAllocator.free(empty_allowed);
        return;
    };

    baseChunkUpdate(found_x, found_y, found_z);
    source.sendMessage("#00ff00Chest successfully registered! Access: PRIVATE.", .{});
}

fn baseChunkUpdate(found_x: i32, found_y: i32, found_z: i32) void {
    const world_mod = @import("../world.zig");
    const baseChunk = world_mod.ChunkManager.getOrGenerateChunkAndIncreaseRefCount(.{
        .wx = found_x & ~@as(i32, chunk.chunkMask),
        .wy = found_y & ~@as(i32, chunk.chunkMask),
        .wz = found_z & ~@as(i32, chunk.chunkMask),
        .voxelSize = 1,
    });
    defer baseChunk.decreaseRefCount();
    baseChunk.mutex.lock();
    baseChunk.setChanged();
    baseChunk.mutex.unlock();
}
