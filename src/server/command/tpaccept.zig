const std = @import("std");
const main = @import("main");
const User = main.server.User;

pub const description = "Accept a pending teleport request.";
pub const usage = "\\/tpaccept";

const Args = union(enum) { @"/tpaccept": struct {} };
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/tpaccept"});

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    _ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    const target_prof = source.player();
    const sender_index = target_prof.tpa_request_from orelse {
        source.sendMessage("#ff0000You have no pending teleport requests.", .{});
        return;
    };

    const online_users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
    defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, online_users);

    for (online_users) |u| {
        if (u.playerIndex == sender_index) {
            u.player().back_pos = u.player().pos;
            u.player().pos = target_prof.pos;
            main.network.protocols.genericUpdate.sendTPCoordinates(u.conn, target_prof.pos);

            u.sendMessage("#00ff00Teleport request accepted. Teleporting...", .{});
            source.sendMessage("#00ff00Accepted teleport request from {s}.", .{u.name});

            target_prof.tpa_request_from = null;
            return;
        }
    }

    source.sendMessage("#ff0000The player who sent the request is no longer online.", .{});
    target_prof.tpa_request_from = null;
}
