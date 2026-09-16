const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;

pub const description = "Stop the server.";
pub const usage =
	\\/server <stop/restart>
;

pub const Args = union(enum) {
	@"/server <action>": struct { action: main.server.StopType },
};

pub fn execute(args: Args, source: Source) void {
	if (args.@"/server <action>".action == .restart and !main.settings.launchConfig.headlessServer) {
		source.sendMessage("#ff0000Headfull restart isn't supported yet.", .{});
		return;
	}

	main.server.stop(args.@"/server <action>".action);
}
