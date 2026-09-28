const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

pub const description = "Clears your inventory/chat";
pub const usage = "/clear <inventory/chat>";

pub const Args = union(enum) {
	@"/clear <target>": struct { target: enum { inventory, chat } },
};

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	switch (args.@"/clear <target>".target) {
		.inventory => main.items.Inventory.server.clearPlayerInventory(user),
		.chat => main.network.protocols.genericUpdate.sendClear(user.conn, .chat),
	}
}
