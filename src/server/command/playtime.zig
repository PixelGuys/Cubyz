const std = @import("std");
const main = @import("main");
const command = main.server.command;
const User = main.server.User;
const ZonElement = main.ZonElement;
const files = main.files;

pub const description = "Check your playtime.";
pub const usage = "\\/playtime\n\\/playtime list";

const Args = union(enum) {
    @"/playtime <action>": struct { action: enum { list } },
    @"/playtime": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/playtime"});

const LeaderboardEntry = struct {
    name: []const u8,
    playtime: u64,
    fn compare(_: void, a: LeaderboardEntry, b: LeaderboardEntry) bool { return a.playtime > b.playtime; }
};

fn getLivePlaytime(prof: anytype) u64 {
    const cur = @as(i64, @intCast(@divTrunc(main.timestamp().toNanoseconds(), 1000000000)));
    const session = if (cur > prof.login_time) cur - prof.login_time else 0;
    return prof.playtime + @as(u64, @intCast(session));
}

pub fn execute(args: []const u8, source: *User) void {
    var errorMessage: main.List(u8) = .empty;
    defer errorMessage.deinit(main.stackAllocator);

    const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
        source.sendMessage("#ff0000{s}", .{errorMessage.items});
        return;
    };

    const world = main.server.world.?;

    switch (result) {
        .@"/playtime" => {
            const total = getLivePlaytime(source.player());
            source.sendMessage("#00ff00Your total playtime: #ffff00{}h {}m", .{ total / 3600, (total % 3600) / 60 });
        },
        .@"/playtime <action>" => |params| switch (params.action) {
            .list => {
                source.sendMessage("#ffff00- Server Playtime Leaderboard -", .{});
                var leader_list: main.List(LeaderboardEntry) = .empty;
                defer {
                    for (leader_list.items) |e| main.stackAllocator.free(e.name);
                    leader_list.deinit(main.stackAllocator);
                }

                world.saveAllPlayers() catch {};
                const folder_path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players", .{world.path}) catch unreachable;
                defer main.stackAllocator.free(folder_path);

                var playerDir = files.cubyzDir().openIterableDir(folder_path) catch return;
                defer playerDir.close();

                var iterator = playerDir.iterate();
                while (iterator.next(main.io) catch null) |file| {
                    if (file.kind != .file or !std.mem.endsWith(u8, file.name, ".zon")) continue;

                        const path = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/players/{s}", .{world.path, file.name}) catch unreachable;
                        defer main.stackAllocator.free(path);

                    const playerData = files.cubyzDir().readToZon(main.stackAllocator, path) catch continue;
                    defer playerData.deinit(main.stackAllocator);

                    const name = playerData.get([]const u8, "name") orelse "Unknown Player";
                    const entityZon = playerData.getChildOrNull("entity") orelse continue;
                    var accumulated = entityZon.get(u64, "playtime") orelse 0;

                    const online_users = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
                    for (online_users) |u| {
                        if (std.mem.eql(u8, u.name, name)) {
                            accumulated = getLivePlaytime(u.player());
                            break;
                        }
                    }
                    main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, online_users);

                    leader_list.append(main.stackAllocator, .{ .name = main.stackAllocator.dupe(u8, name), .playtime = accumulated });
                }

                std.mem.sort(LeaderboardEntry, leader_list.items, {}, LeaderboardEntry.compare);

                const display_count = @min(@as(usize, 10), leader_list.items.len);
                for (0..display_count) |i| {
                    const entry = leader_list.items[i];
                    source.sendMessage("#00ff00{}. #ffff00{s} §#00ff00- {}h {}m", .{ i + 1, entry.name, entry.playtime / 3600, (entry.playtime % 3600) / 60 });
                }
            },
        },
    }
}
