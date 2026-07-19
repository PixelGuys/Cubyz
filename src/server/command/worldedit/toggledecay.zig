const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const Vec3i = main.vec.Vec3i;
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Pattern = main.blueprint.Pattern;

pub const description = "Enable/disable decay on decayable blocks.";
pub const usage =
	\\/toggledecay <selection/clipboard> <on/off>
;

const Target = enum { selection, clipboard };

const State = enum {
	on,
	off,
};

pub const Args = union(enum) {
	@"/toggledecay <target> <state>": struct {
		target: Target,
		state: State,
	},
};

pub fn execute(args: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	var blueprint: Blueprint = switch (args.@"/toggledecay <target> <state>".target) {
		.selection => blk: {
			const selection = command.getCurrentSelection(source) catch return;
			const blueprint = switch (Blueprint.capture(main.globalAllocator, selection)) {
				.success => |bp| bp,
				.failure => |e| {
					source.sendMessage("#ff0000Error while capturing block {}: {s}. Nothing was modified.", .{e.pos, e.message});
					std.log.warn("Error while capturing block {}: {s}. Nothing was modified.", .{e.pos, e.message});
					return;
				},
			};

			source.worldEditData.undoHistory.push(.init(blueprint, selection.minPos, "toggledecay"));
			source.worldEditData.redoHistory.clear();

			break :blk blueprint.clone(main.stackAllocator);
		},
		.clipboard => source.worldEditData.clipboard orelse {
			return source.sendMessage("#ff0000Clipboard is empty.", .{});
		},
	};

	blueprint.apply(args.@"/toggledecay <target> <state>".state, toggledecay);

	switch (args.@"/toggledecay <target> <state>".target) {
		.selection => {
			const pos1 = source.worldEditData.selectionPosition1.?;
			const pos2 = source.worldEditData.selectionPosition2.?;

			const posStart: Vec3i = @min(pos1, pos2);

			blueprint.paste(posStart, .{.preserveVoid = true});
			blueprint.deinit(main.stackAllocator);

			return source.sendMessage("#00ff00Selection modified. History entry created.", .{});
		},
		.clipboard => {
			return source.sendMessage("#00ff00Clipboard modified.", .{});
		},
	}
}

pub fn toggledecay(decayState: State, current: Block) Block {
	if (current.mode() == main.rotation.getByID("cubyz:branch")) {
		var branchData = main.rotation.rotations.@"cubyz:branch".BranchData.init(current.data);
		branchData.placedByHuman = decayState == .off;
		return .{.typ = current.typ, .data = @as(u7, @bitCast(branchData))};
	}
	if (current.mode() == main.rotation.getByID("cubyz:decayable")) {
		return .{.typ = current.typ, .data = @intFromBool(decayState == .off)};
	}
	return current;
}
