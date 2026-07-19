const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Clears your inventory/chat";
pub const usage = "/clear <inventory/chat>";

pub const Args = union(enum) {
	@"/clear <target>": struct { target: enum { inventory, chat } },
};

pub fn execute(args: Args, source: *User) void {
	switch (args.@"/clear <target>".target) {
		.inventory => main.items.Inventory.server.clearPlayerInventory(source),
		.chat => main.network.protocols.genericUpdate.sendClear(source.conn, .chat),
	}
}
