const std = @import("std");
const main = @import("main");
const User = main.server.User;

pub const description = "Request to teleport to another player.";
pub const usage = "\\/tpa <player>";

const Args = union(enum) { @"/tpa <target>": struct { target: []const u8 } };
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/tpa"});

/// --- ASHFRAME CUSTOM (Name Filtering) ---
fn cleanColorCodes(allocator: std.mem.Allocator, name: []const u8) []const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < name.len) {
        if (std.mem.startsWith(u8, name[i..], "§")) {
            i += 1;
            if (i < name.len and name[i] == '#') {
                i += 7;
            }
            continue;
        }
        result.append(allocator, name[i]) catch {};
        i += 1;
    }
    return result.toOwnedSlice(allocator) catch name;
}
// --- ASHFRAME CUSTOM (Name Filtering) ---

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    const target_str = switch (result) {
        .@"/tpa <target>" => |p| p.target,
    };

    var target_user: ?*User = null;

    if (std.ascii.startsWithIgnoreCase(target_str, "@")) {
        const cleanIndexStr = std.mem.trim(u8, target_str[1..], &std.ascii.whitespace);
        if (std.fmt.parseInt(usize, cleanIndexStr, 10)) |index| {
            target_user = main.server.getUserByIndexAndIncreaseRefCount(index);
        } else |_| {}
    } else {
        const online_users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
        defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, online_users);

        const clean_target = cleanColorCodes(main.stackAllocator.allocator, target_str);
        defer main.stackAllocator.allocator.free(clean_target);

        var exactMatchFound = false;
        var partialMatches: usize = 0;

        // Pass 1: Look for exact name string match (ignoring style rules/case)
        for (online_users) |u| {
            const clean_user_name = cleanColorCodes(main.stackAllocator.allocator, u.name);
            defer main.stackAllocator.allocator.free(clean_user_name);

            if (std.ascii.eqlIgnoreCase(clean_user_name, clean_target)) {
                u.increaseRefCount();
                target_user = u;
                exactMatchFound = true;
                break;
            }
        }

        // Pass 2: Fall back to sub-string checks if no absolute match is hit
        if (!exactMatchFound) {
            for (online_users) |u| {
                const clean_user_name = cleanColorCodes(main.stackAllocator.allocator, u.name);
                defer main.stackAllocator.allocator.free(clean_user_name);

                if (std.ascii.indexOfIgnoreCase(clean_user_name, clean_target) != null) {
                    partialMatches += 1;
                    target_user = u;
                }
            }

            if (partialMatches != 1) {
                target_user = null;
            } else if (target_user) |u| {
                u.increaseRefCount();
            }
        }
    }

    if (target_user) |u| {
        defer u.decreaseRefCount();

        if (u.playerIndex == source.playerIndex) {
            source.sendMessage("#ff0000You cannot teleport to yourself!", .{});
            return;
        }

        u.player().tpa_request_from = @intCast(source.playerIndex);
        source.sendMessage("#00ff00Teleport request sent to {s}.", .{u.name});
        u.sendMessage("#ffff00{s} wants to teleport to you. Type #00ff00/tpaccept #ffff00to accept.", .{source.name});
    } else {
        source.sendMessage("#ff0000Player '{s}' not found or offline.", .{target_str});
    }
}
