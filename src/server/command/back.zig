const std = @import("std");
const main = @import("main");
const User = main.server.User;

pub const description = "Teleport back to your last location before death or teleportation.";
pub const usage = "\\/back";

const Args = union(enum) { @"/back": struct {} };
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/back"});

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    _ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    // Grab the position directly from the player's entity profile
    const target_pos = source.player().back_pos orelse {
        source.sendMessage("#ff0000You do not have a previous location to return to.", .{});
        return;
    };

    // Teleport the player
    main.network.protocols.genericUpdate.sendTPCoordinates(source.conn, target_pos);
    source.sendMessage("#00ff00Teleported back to your previous location.", .{});

    // Clear the position so it can only be used once
    source.player().back_pos = null;
}
