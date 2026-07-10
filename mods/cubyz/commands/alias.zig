const std = @import("std");

const main = @import("main");
const User = main.server.User;
const command = main.server.command;

pub const description = "Manually assign or remove a short alias for a full command ID.";
pub const usage =
    \\/alias <shortName> <fullCommandId>
    \\/alias remove <shortName>
;

const Args = union(enum) {
    @"/alias <shortName> <fullCommandId>": struct { shortName: []const u8, fullId: []const u8 },
    @"/alias remove <shortName>": struct { shortName: []const u8 },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/alias"});

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    switch (result) {
        .@"/alias <shortName> <fullCommandId>" => |params| {
            if (std.mem.eql(u8, params.shortName, "alias")) {
                source.sendMessage("#ff0000Cannot reassign the \"/alias\" command's own name", .{});
                return;
            }

            if (std.mem.indexOfAny(u8, params.shortName, ":/") != null) {
                source.sendMessage("#ff0000Alias name \"{s}\" cannot contain ':' or '/'", .{params.shortName});
                return;
            }

            if (!command.registeredCommands.contains(params.fullId)) {
                source.sendMessage("#ff0000Unknown command ID \"{s}\"", .{params.fullId});
                return;
            }

            const ownedFull = main.globalAllocator.dupe(u8, params.fullId);
            const putResult = command.userAliases.getOrPut(main.globalAllocator.dupe(u8, params.shortName)) catch unreachable;
            if (putResult.found_existing) {
                source.sendMessage("#ffff00Alias \"/{s}\" was pointing to \"/{s}\", now points to \"/{s}\"", .{params.shortName, putResult.value_ptr.*, params.fullId});
                main.globalAllocator.free(putResult.value_ptr.*);
            } else {
                source.sendMessage("#00ff00Alias \"/{s}\" now points to \"/{s}\"", .{params.shortName, params.fullId});
            }
            putResult.value_ptr.* = ownedFull;
        },
        .@"/alias remove <shortName>" => |params| {
            const removed = command.userAliases.fetchRemove(params.shortName) orelse {
                source.sendMessage("#ff0000No alias named \"/{s}\" exists", .{params.shortName});
                return;
            };
            main.globalAllocator.free(removed.key);
            main.globalAllocator.free(removed.value);
            source.sendMessage("#00ff00Alias \"/{s}\" removed", .{params.shortName});
        },
    }
}
