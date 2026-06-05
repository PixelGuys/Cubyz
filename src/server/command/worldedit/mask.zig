const std = @import("std");

const main = @import("main");
const command = main.server.command;
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

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.List(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	defer result.deinit(main.stackAllocator);

	switch (result) {
		.@"/mask <mask>" => |cmd| {
			source.worldEditData.mask = cmd.mask.mask.clone(main.globalAllocator);
			source.sendMessage("#00ff00Mask set.", .{});
		},
		.@"/mask" => {
			if (source.worldEditData.mask) |mask| mask.deinit(main.globalAllocator);
			source.worldEditData.mask = null;
			source.sendMessage("#00ff00Mask cleared.", .{});
		},
	}
}
