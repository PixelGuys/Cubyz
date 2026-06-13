const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const User = main.server.User;

pub const description = "Set edit mask. When used with no mask expression it will clear current mask.";
pub const usage =
	\\/mask <mask>
	\\/mask
;

const Args = union(enum) {
	@"/mask": struct {
		fn deinit(_: @This(), _: NeverFailingAllocator) void {}
	},
	@"/mask <mask>": struct {
		mask: command.MaskExpression,

		fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			self.mask.deinit(allocator);
		}
	},

	fn deinit(self: Args, allocator: NeverFailingAllocator) void {
		switch (self) {
			inline else => |object| object.deinit(allocator),
		}
	}
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/mask"});

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
	defer result.deinit(main.stackAllocator);

	if (source.worldEditData.mask) |mask| mask.deinit(main.globalAllocator);

	switch (result) {
		.@"/mask <mask>" => |cmd| {
			source.worldEditData.mask = cmd.mask.mask.clone(main.globalAllocator);
			source.sendMessage("#00ff00Mask set.", .{});
		},
		.@"/mask" => {
			source.worldEditData.mask = null;
			source.sendMessage("#00ff00Mask cleared.", .{});
		},
	}
}
