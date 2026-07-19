const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

pub const description = "Clears your inventory/chat";
pub const usage = "/clear <inventory/chat>";

pub const Args = union(enum) {
	@"/clear <target>": struct { target: enum { inventory, chat } },
};

pub fn execute(args: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	switch (args.@"/clear <target>".target) {
		.inventory => main.items.Inventory.server.clearPlayerInventory(source),
		.chat => main.network.protocols.genericUpdate.sendClear(source.conn, .chat),
	}
}
