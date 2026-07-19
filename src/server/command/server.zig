const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Stop the server.";
pub const usage =
	\\/server <stop/restart>
;

pub const Args = union(enum) {
	@"/server <action>": struct { action: main.server.StopType },
};

pub fn execute(args: Args, source: *User) void {
	if (args.@"/server <action>".action == .restart and !main.settings.launchConfig.headlessServer) {
		source.sendMessage("#ff0000Headfull restart isn't supported yet.", .{});
		return;
	}

	main.server.stop(args.@"/server <action>".action);
}
