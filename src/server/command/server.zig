const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Stop the server.";
pub const usage =
	\\/server <stop/restart> ?world
;

const Args = union(enum) {
	@"/server <stop>": struct { action: enum { stop } },
	@"/server <restart> <worldName>": struct { action: enum { restart }, worldName: ?[]const u8 },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/server"});

pub fn checkIfExist(worldName: []const u8, source: *User) bool {
	var dir = main.files.cubyzDir().openIterableDir("saves") catch |err| {
		source.sendMessage("#ff0000Encountered error while trying to open saves folder:{s}", .{@errorName(err)});
		return false;
	};
	defer dir.close();

	var iterator = dir.iterate();
	while (iterator.next(main.io) catch |err| {
		source.sendMessage("#ff0000Encountered error while iterating over saves folder:{s}", .{@errorName(err)});
		return false;
	}) |entry| {
		if (entry.kind == .directory) {
			const worldInfoPath = std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/world.zig.zon", .{entry.name}) catch unreachable;
			defer main.stackAllocator.free(worldInfoPath);
			const worldInfo = main.files.cubyzDir().readToZon(main.stackAllocator, worldInfoPath) catch |err| {
				std.log.err("Couldn't open save {s}: {s}", .{worldInfoPath, @errorName(err)});
				continue;
			};
			defer worldInfo.deinit(main.stackAllocator);

			if (std.mem.eql(u8, worldName, worldInfo.get([]const u8, "name", entry.name))) return true;
		}
	}
	source.sendMessage("#ff0000World with this name doesn't exist", .{});
	return false;
}

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	switch (result) {
		.@"/server <stop>" => {},
		.@"/server <restart> <worldName>" => |param| {
			if (param.worldName) |worldName| {
				if (checkIfExist(worldName, source) == false) return;
				main.reload.storeWorldName(worldName);
			}

			main.server.restart.store(true, .release);
		},
	}
	main.server.running.store(false, .release);
}
