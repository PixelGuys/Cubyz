const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Lists all connected players.";
pub const usage =
	\\/list
;

pub const Args = union(enum) {
	@"/list": struct {},
};

pub fn execute(_: Args, source: Source) void {
	const userList = main.server.getUserList(main.stackAllocator);
	defer main.stackAllocator.free(userList);

	var msg: main.ListManaged(u8) = .init(main.stackAllocator);
	defer msg.deinit();
	msg.print("#ffff00{} player(s) online:\n", .{userList.len});
	for (userList) |user| {
		msg.print("§#ffffff{f}\n", .{user.*});
	}
	_ = msg.pop();
	source.sendMessage("{s}", .{msg.items});
}
