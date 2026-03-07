const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Change your avatar";
pub const usage = "/avatar <entityTypeID>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		if (main.entityComponent.model.Server.get(source.id)) |rc| {
			source.sendMessage("#00ff00You are a {s}", .{rc.entityModel.get().id});
		} else source.sendMessage("#ff00ffYou are a invisible.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |entityModelID| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /avatar", .{});
			return;
		}
		if (main.entityModel.getTypeByIdOrNull(entityModelID)) |entityModel| {
			if (main.entityComponent.model.Server.get(source.id)) |rc| {
				var newRc = rc;
				newRc.customTexturePath = null;
				newRc.entityModel = entityModel;
				main.entityComponent.model.Server.put(source.id, newRc);
			}
			main.entityComponent.model.Server.put(source.id, .{
				.entity = source.id,
				.customTexturePath = null,
				.entityModel = entityModel,
			});
			source.sendMessage("#00ff00entityTypeID was changed to {s}.", .{entityModelID});
		} else {
			source.sendMessage("#ff0000entityTypeID {s} doesnt exist", .{entityModelID});
		}
		// transmit
		if (main.entityComponent.model.Server.get(source.id)) |rc| {
			var binaryWriter = main.utils.BinaryWriter.init(main.stackAllocator);
			defer binaryWriter.deinit();
			rc.save(&binaryWriter);

			for (main.server.connectionManager.connections.items) |conn| {
				main.network.protocols.EntityComponentUpdate.set(conn, source.id, "model", main.entityComponent.model.ENTITY_COMPONENT_VERSION, binaryWriter.data.items);
			}
		}
	}
}
