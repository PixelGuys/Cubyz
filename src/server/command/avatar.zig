const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Change your avatar";
pub const usage = "/avatar <entityTypeID>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /avatar. Expected one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |arg| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /avatar", .{});
			return;
		}
		if (main.entityComponent.entityRenderer.entityModels.get(arg)) |entityModel| {
			if (main.entityComponent.entityRenderer.Server.get(source.id)) |rc| {
				var newRc = rc;
				newRc.customTexturePath = null;
				newRc.model = entityModel;
				main.entityComponent.entityRenderer.Server.put(source.id, newRc);
			}

			for (main.server.connectionManager.connections.items) |value| {
				main.network.protocols.Customization.send(value, source.id, entityModel.id);
			}
			source.sendMessage("#00ff00entityTypeID was changed to {s}.", .{arg});
		} else {
			source.sendMessage("#ff0000entityTypeID {s} doesnt exist", .{arg});
		}
	}
}
