const std = @import("std");

const main = @import("main");
const Degrees = main.rotation.Degrees;
const Source = main.server.command.Source;

pub const description = "rotate clipboard content around Z axis counterclockwise.";
pub const usage =
	\\/rotate
	\\/rotate <0/90/180/270>
;

const Args = union(enum) {
	@"/rotate": struct {},
	@"/rotate <rotation>": struct { rotation: Degrees },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/rotate"});

pub fn execute(args: []const u8, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
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
	switch (result) {
		.@"/rotate" => source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, .@"90"),
		.@"/rotate <rotation>" => |params| source.worldEditData.clipboard = current.rotateZ(main.globalAllocator, params.rotation),
	}
}
