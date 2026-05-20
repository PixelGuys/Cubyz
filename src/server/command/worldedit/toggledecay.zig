const std = @import("std");

const main = @import("main");
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

const Args = struct {
	target: Target,
	decayState: State,

	pub fn parse(args: []const u8, source: *User) !Args {
		var argsSplit = std.mem.splitScalar(u8, args, ' ');

		const targetString = argsSplit.next() orelse {
			source.sendMessage("#ff0000Missing required <selection/clipboard> argument.", .{});
			return error.ParsingFailed;
		};
		const target = std.meta.stringToEnum(Target, targetString) orelse {
			source.sendMessage("#ff0000'{s}' as a target specifier was not recognized, use 'selection' or 'clipboard'", .{targetString});
			return error.ParsingFailed;
		};

		const stateString = argsSplit.next() orelse {
			source.sendMessage("#ff0000Missing required <on/off> argument.", .{});
			return error.ParsingFailed;
		};
		const state = std.meta.stringToEnum(State, stateString) orelse {
			source.sendMessage("#ff0000'{s}' as a state specifier was not recognized, use 'on' or 'off'", .{stateString});
			return error.ParsingFailed;
		};

		if (argsSplit.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /toggledecay. Expected two.", .{});
			return error.ParsingFailed;
		}

		return .{.target = target, .decayState = state};
	}
};

pub fn execute(argsString: []const u8, source: *User) void {
	const args = Args.parse(argsString, source) catch return;

	var blueprint: Blueprint = switch (args.target) {
		.selection => blk: {
			const pos1 = source.worldEditData.selectionPosition1 orelse {
				return source.sendMessage("#ff0000Position 1 is not set.", .{});
			};
			const pos2 = source.worldEditData.selectionPosition2 orelse {
				return source.sendMessage("#ff0000Position 2 is not set.", .{});
			};

			const posStart: Vec3i = @min(pos1, pos2);
			const posEnd: Vec3i = @max(pos1, pos2);

			const blueprint = switch (Blueprint.capture(main.globalAllocator, posStart, posEnd)) {
				.success => |bp| bp,
				.failure => |e| {
					source.sendMessage("#ff0000Error while capturing block {}: {s}. Nothing was modified.", .{e.pos, e.message});
					std.log.warn("Error while capturing block {}: {s}. Nothing was modified.", .{e.pos, e.message});
					return;
				},
			};

			source.worldEditData.undoHistory.push(.init(blueprint, posStart, "toggledecay"));
			source.worldEditData.redoHistory.clear();

			break :blk blueprint.clone(main.stackAllocator);
		},
		.clipboard => source.worldEditData.clipboard orelse {
			return source.sendMessage("#ff0000Clipboard is empty.", .{});
		},
	};

	blueprint.apply(args.decayState, toggledecay);

	switch (args.target) {
		.selection => {
			const pos1 = source.worldEditData.selectionPosition1 orelse unreachable;
			const pos2 = source.worldEditData.selectionPosition2 orelse unreachable;

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
