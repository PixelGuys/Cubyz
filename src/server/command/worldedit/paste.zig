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

const Args = union(enum) {
	@"/paste [-v|--keep-void]": struct { void: ?enum { @"-v", @"--keep-void" } },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/paste"});

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

	if (source.worldEditData.clipboard) |clipboard| {
		const pos: Vec3i = @floor(source.player().pos);
		source.sendMessage("Pasting: {}", .{pos});

		const selection: Blueprint.Selection = .initFromExtent(pos, clipboard.extent());
		const undo = Blueprint.capture(main.globalAllocator, selection);
		switch (undo) {
			.success => |blueprint| {
				source.worldEditData.undoHistory.push(.init(blueprint, pos, "paste"));
				source.worldEditData.redoHistory.clear();
			},
			.failure => {
				source.sendMessage("#ff0000Error: Could not capture undo history.", .{});
			},
		}

		clipboard.paste(pos, .{.preserveVoid = result.@"/paste [-v|--keep-void]".void != null});
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to paste.", .{});
	}
}
