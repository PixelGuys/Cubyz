const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Clears your inventory/chat";
pub const usage = "/clear <inventory/chat>";

const Args = union(enum) {
	@"/clear <target>": struct { target: enum { inventory, chat } },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/clear"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result.@"/clear <target>".target) {
		.inventory => main.items.Inventory.server.clearPlayerInventory(source),
		.chat => main.network.protocols.genericUpdate.sendClear(source.conn, .chat),
	}
}
