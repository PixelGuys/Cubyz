const std = @import("std");
const main = @import("main");
const User = main.server.User;

pub const description = "Manage, list, and teleport to your saved home locations.";
pub const usage =
\\/home <name>
\\/home add <name>
\\/home remove <name>
\\/home list
\\/home spawn <name>
;

const Args = union(enum) {
    @"/home": struct {
        raw_args: ?[]const u8 = null,
    },
};
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/home"});

// --- ASHFRAME CUSTOM (home) ---
const MAX_HOMES = 3;

pub fn execute(args: []const u8, source: *User) void {
    const clean_args = std.mem.trim(u8, args, &std.ascii.whitespace);

    if (clean_args.len == 0) {
        source.sendMessage("#ffff00Usage:\n{s}", .{usage});
        return;
    }

    var token_iter = std.mem.tokenizeScalar(u8, clean_args, ' ');
    const subcommand = token_iter.next() orelse return;

    const prof = source.player();

    // 1. /home list
    if (std.mem.eql(u8, subcommand, "list")) {
        var count: usize = 0;
        var list_msg: std.ArrayList(u8) = std.ArrayList(u8).empty;
        defer list_msg.deinit(main.stackAllocator.allocator);

        list_msg.appendSlice(main.stackAllocator.allocator, "#00ff00Your Saved Homes:") catch {};

        for (prof.home_names, 0..) |opt_name, i| {
            if (opt_name) |hn| {
                if (prof.home_pos[i] != null) {
                    count += 1;
                    var format_buf: [64]u8 = undefined;
                    const line = std.fmt.bufPrint(&format_buf, "\n - {s}", .{hn}) catch continue;
                    list_msg.appendSlice(main.stackAllocator.allocator, line) catch {};
                }
            }
        }

        if (count == 0) {
            source.sendMessage("#ff0000You do not have any homes saved yet.", .{});
        } else {
            source.sendMessage("{s}", .{list_msg.items});
        }
        return;
    }

    // 1.5. /home spawn <name>
    if (std.mem.eql(u8, subcommand, "spawn")) {
        const name = token_iter.next() orelse {
            source.sendMessage("#ff0000Usage: /home spawn <name>", .{});
            return;
        };

        var found_slot: ?usize = null;
        for (prof.home_names, 0..) |opt_name, i| {
            if (opt_name) |hn| {
                if (std.mem.eql(u8, hn, name)) {
                    found_slot = i;
                    break;
                }
            }
        }

        if (found_slot) |slot| {
            if (prof.home_pos[slot] != null) {
                prof.spawn_home_index = slot;
                source.sendMessage("#00ff00Set home '{s}' as your active respawn point on death!", .{name});
            } else {
                source.sendMessage("#ff0000Error: Home '{s}' has no coordinates set.", .{name});
            }
        } else {
            source.sendMessage("#ff0000No home matching '{s}' was found.", .{name});
        }
        return;
    }

    // 2. /home add <name>
    if (std.mem.eql(u8, subcommand, "add")) {
        const name = token_iter.next() orelse {
            source.sendMessage("#ff0000Usage: /home add <name>", .{});
            return;
        };

        if (std.mem.eql(u8, name, "list") or std.mem.eql(u8, name, "add") or std.mem.eql(u8, name, "remove")) {
            source.sendMessage("#ff0000Error: You cannot name a home '{s}'.", .{name});
            return;
        }

        var existing_slot: ?usize = null;
        var empty_slot: ?usize = null;

        // Scan slots
        for (prof.home_names, 0..) |opt_name, i| {
            if (opt_name) |hn| {
                if (std.mem.eql(u8, hn, name)) {
                    existing_slot = i;
                    break;
                }
            } else if (empty_slot == null) {
                empty_slot = i;
            }
        }

        if (existing_slot) |slot| {
            prof.home_pos[slot] = prof.pos;
            source.sendMessage("#00ff00Home '{s}' updated to current position!", .{name});
        } else if (empty_slot) |slot| {
            prof.home_pos[slot] = prof.pos;
            prof.home_names[slot] = main.globalAllocator.dupe(u8, name);
            source.sendMessage("#00ff00Home '{s}' saved! ({}/{} slots filled).", .{name, slot + 1, MAX_HOMES});
        } else {
            source.sendMessage("#ff0000Error: You have hit the limit of {} homes maximum. Remove one first.", .{MAX_HOMES});
        }
        return;
    }

    // 3. /home remove <name>
    if (std.mem.eql(u8, subcommand, "remove")) {
        const name = token_iter.next() orelse {
            source.sendMessage("#ff0000Usage: /home remove <name>", .{});
            return;
        };

        var found_slot: ?usize = null;
        for (prof.home_names, 0..) |opt_name, i| {
            if (opt_name) |hn| {
                if (std.mem.eql(u8, hn, name)) {
                    found_slot = i;
                    break;
                }
            }
        }

        if (found_slot) |slot| {
            prof.home_pos[slot] = null;
            if (prof.home_names[slot]) |old_str| {
                main.globalAllocator.free(old_str);
            }
            prof.home_names[slot] = null;
            source.sendMessage("#00ff00Home '{s}' has been successfully removed.", .{name});
        } else {
            source.sendMessage("#ff0000No home matching '{s}' was found.", .{name});
        }
        return;
    }

    // 4. /home <name> (Teleporting)
    var target_slot: ?usize = null;
    for (prof.home_names, 0..) |opt_name, i| {
        if (opt_name) |hn| {
            if (std.mem.eql(u8, hn, subcommand)) {
                target_slot = i;
                break;
            }
        }
    }

    if (target_slot) |slot| {
        if (prof.home_pos[slot]) |hp| {
            prof.back_pos = prof.pos;
            prof.pos = hp;
            main.network.protocols.genericUpdate.sendTPCoordinates(source.conn, hp);
            source.sendMessage("#00ff00Teleporting to home '{s}'...", .{subcommand});
            return;
        }
    }

    source.sendMessage("#ff0000Home '{s}' does not exist.", .{subcommand});
}
// --- ASHFRAME CUSTOM (home) ---
