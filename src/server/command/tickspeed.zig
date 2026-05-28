const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Get or set the server's random tickrate, measured in blocks per chunk per tick.";
pub const usage =
	\\/tickspeed
	\\/tickspeed <rate>
;

const Args = union(enum) {
	@"/tickspeed <rate>": struct { rate: u32 },
	@"/tickspeed": struct {},
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/tickspeed"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
		.@"/tickspeed <rate>" => |tickSpeed| main.server.world.?.tickSpeed.store(tickSpeed.rate, .monotonic),
		.@"/tickspeed" => {},
	}
	source.sendMessage("#ffff00{}", .{main.server.world.?.tickSpeed.load(.monotonic)});
}
