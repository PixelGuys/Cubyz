const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Count block(s) appearance(s) in selection.";
pub const usage =
	\\/count <blockId>
	\\/count
;

pub const Args = union(enum) {
	@"/count": struct { block: ?command.BlockId },
};

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	const selection = command.getCurrentSelection(user) catch return;

	var result = Blueprint.capture(main.stackAllocator, selection);

	switch (result) {
		.success => |*blueprint| {
			defer blueprint.deinit(main.stackAllocator);

			var context: std.AutoHashMapUnmanaged(u16, u32) = .{};
			defer context.deinit(main.stackAllocator.allocator);

			blueprint.apply(&context, countBlocks);

			if (args.@"/count".block) |block| {
				const count = context.get(block.block.typ) orelse 0;
				user.sendMessage("#ffff00{s} #ffffff{d}", .{block.block.id(), count});
			} else {
				var iterator = context.iterator();
				while (iterator.next()) |next| {
					user.sendMessage("#ffff00{s} #ffffff{d}", .{(Block{.typ = next.key_ptr.*, .data = 0}).id(), next.value_ptr.*});
				}
			}
		},
		.failure => |e| {
			user.sendMessage("#ff0000Error while capturing block {}: {s}", .{e.pos, e.message});
			std.log.warn("Error while capturing block {}: {s}", .{e.pos, e.message});
		},
	}
}

fn countBlocks(context: *std.AutoHashMapUnmanaged(u16, u32), current: Block) Block {
	const result = context.getOrPut(main.stackAllocator.allocator, current.typ) catch unreachable;
	if (result.found_existing) {
		result.value_ptr.* = result.value_ptr.* + 1;
	} else {
		result.value_ptr.* = 1;
	}
	return current;
}
