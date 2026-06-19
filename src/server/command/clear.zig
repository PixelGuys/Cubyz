const std = @import("std");

const main = @import("main");
const Source = main.server.command.Source;

pub const description = "Clears your inventory/chat";
pub const usage = "/clear <inventory/chat>";

const Args = union(enum) {
	@"/clear <target>": struct { target: enum { inventory, chat } },
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/clear"});

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

	switch (result.@"/clear <target>".target) {
		.inventory => main.items.Inventory.server.clearPlayerInventory(source),
		.chat => main.network.protocols.genericUpdate.sendClear(source.conn, .chat),
	}
}
