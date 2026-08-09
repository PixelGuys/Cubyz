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
				const TypAndCount = struct { typ: u16, count: u32 };
				var items: main.List(TypAndCount) = .empty;
				defer items.deinit(main.stackAllocator);

				var iterator = context.iterator();
				while (iterator.next()) |next| items.append(main.stackAllocator, .{.typ = next.key_ptr.*, .count = next.value_ptr.*});

				std.sort.insertion(TypAndCount, items.items, {}, struct {
					fn lessThan(_: void, a: TypAndCount, b: TypAndCount) bool {
						return a.count > b.count;
					}
				}.lessThan);

				for (items.items) |item| {
					user.sendMessage("#ffffff{d: <6} #ffff00{s}", .{item.count, (Block{.typ = item.typ, .data = 0}).id()});
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
		result.value_ptr.* += 1;
	} else {
		result.value_ptr.* = 1;
	}
	return current;
}
