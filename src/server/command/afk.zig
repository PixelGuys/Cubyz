const std = @import("std");
const main = @import("main");
const User = main.server.User;

pub const description = "Toggle your Away From Keyboard status.";
pub const usage = "\\/afk";

const Args = union(enum) { @"/afk": struct {} };
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/afk"});

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    _ = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    var player_profile = source.player();
    player_profile.is_afk = !player_profile.is_afk;

    if (player_profile.is_afk) {
        main.server.sendMessage("{s}§#aaaaaa is now AFK", .{source.name});
    } else {
        main.server.sendMessage("{s}§#00ff00 is no longer AFK", .{source.name});
    }
}
