const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const description = "Set edit mask. When used with no mask expression it will clear current mask.";
pub const usage =
	\\/mask <mask>
	\\/mask
;

pub const Args = union(enum) {
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

pub fn execute(args: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	switch (args) {
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
