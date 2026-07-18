const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Degrees = main.rotation.Degrees;

pub const description = "rotate clipboard content around Z axis counterclockwise.";
pub const usage =
	\\/rotate
	\\/rotate <0/90/180/270>
;

const Args = union(enum) {
	@"/rotate <rotation>": struct { rotation: ?Degrees },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/rotate"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	if (source.worldEditData.clipboard == null) {
		source.sendMessage("#ff0000Error: No clipboard content to rotate.", .{});
		return;
	}
	const current = source.worldEditData.clipboard.?;
	defer current.deinit(main.globalAllocator);
	source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, result.@"/rotate <rotation>".rotation orelse .@"90");
}
