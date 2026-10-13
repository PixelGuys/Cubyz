const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const Blueprint = main.blueprint.Blueprint;

pub const description =
	\\Paste clipboard content to current player position.
	\\-v|--keep-void - Preserve void blocks. By default, void blocks are not preserved.
;
pub const usage = "/paste [-v|--keep-void]";

pub const Args = union(enum) {
	@"/paste [-v|--keep-void]": struct { void: ?enum { @"-v", @"--keep-void" } },
};

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	if (user.worldEditData.clipboard) |clipboard| {
		const pos: Vec3i = @floor(user.player().pos);
		user.sendMessage("Pasting: {}", .{pos});

		const selection: Blueprint.Selection = .initFromExtent(pos, clipboard.extent());
		const undo = Blueprint.capture(main.globalAllocator, selection);
		switch (undo) {
			.success => |blueprint| {
				user.worldEditData.undoHistory.push(.init(blueprint, pos, "paste"));
				user.worldEditData.redoHistory.clear();
			},
			.failure => {
				user.sendMessage("#ff0000Error: Could not capture undo history.", .{});
			},
		}

		clipboard.paste(pos, .{.preserveVoid = args.@"/paste [-v|--keep-void]".void != null});
	} else {
		user.sendMessage("#ff0000Error: No clipboard content to paste.", .{});
	}
}
