const std = @import("std");
const main = @import("main");
const command = main.server.command;
const User = main.server.User;

pub const description = "Add or remove chat prefixes for players.";
pub const usage =
\\/prefix add @<playerIndex> <text>
\\/prefix remove @<playerIndex>
;

const Args = union(enum) {
    @"/prefix add <playerIndex> <text>": struct { add: enum { add }, playerIndex: ?command.PlayerIndex, text: []const u8 },
    @"/prefix remove <playerIndex>": struct { remove: enum { remove }, playerIndex: ?command.PlayerIndex },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/prefix"});

pub fn execute(args: []const u8, source: *User) void {
    if (!source.hasPermission("/command/prefix/admin")) {
        source.sendMessage("#ff0000You do not have permission to manage player prefixes.", .{});
        return;
    }

    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    switch (result) {
        .@"/prefix add <playerIndex> <text>" => |params| {
            const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
            defer target.deinit();

            if (target.user.player().prefix) |old_pref| {
                main.globalAllocator.free(old_pref);
            }

            target.user.player().prefix = main.globalAllocator.dupe(u8, params.text);
            source.sendMessage("#00ff00Successfully assigned prefix to {s}.", .{target.user.name});
            target.user.sendMessage("#00ff00Your chat prefix has been updated to: [{s}]", .{params.text});
        },
        .@"/prefix remove <playerIndex>" => |params| {
            const target = command.Target.fromPlayerIndex(params.playerIndex, source) catch return;
            defer target.deinit();

            if (target.user.player().prefix) |old_pref| {
                main.globalAllocator.free(old_pref);
                target.user.player().prefix = null;
                source.sendMessage("#00ff00Successfully cleared prefix from {s}.", .{target.user.name});
                target.user.sendMessage("#ffff00Your chat prefix has been removed.", .{});
            } else {
                source.sendMessage("#ff0000Player {s} does not currently have a prefix.", .{target.user.name});
            }
        },
    }
}
