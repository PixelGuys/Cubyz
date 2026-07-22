const std = @import("std");
const main = @import("main");
const User = main.server.User;

pub const description = "Lists all online players and their IDs.";
pub const usage = "\\/players";

const Args = union(enum) { @"/players": struct {} };
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/players"});

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    _ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    const online_users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
    defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, online_users);

    if (online_users.len == 0) {
        source.sendMessage("#ffff00There are no players online.", .{});
        return;
    }

    source.sendMessage("#00ff00--- Online Players ({d}) ---", .{online_users.len});

    for (online_users) |u| {
        source.sendMessage("#ffffff- {s} #aaaaaa(@{d})", .{ u.name, u.playerIndex });
    }
}
