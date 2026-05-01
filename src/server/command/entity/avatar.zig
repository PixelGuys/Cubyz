const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Change your avatar";
pub const usage = "/avatar <entityTypeID>";

const model = main.entity.components.@"cubyz:model";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		if (model.server.get(source.id)) |rc| {
			source.sendMessage("#00ff00You are a {s}", .{rc.entityModel.get().entityModelId});
		} else source.sendMessage("#ff00ffYou are invisible.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');
	if (split.next()) |entityModelId| {
		if (split.next() != null) {
			source.sendMessage("#ff0000Too many arguments for command /avatar", .{});
			return;
		}
		if (main.entityModel.getById(entityModelId)) |entityModel| {
			model.server.put(source.id, .{
				.entityModel = entityModel,
			});
			source.sendMessage("#00ff00EntityModelId was changed to {s}.", .{entityModelId});
		} else {
			source.sendMessage("#ff0000EntityModelId {s} doesnt exist", .{entityModelId});
		}
		// transmit
		if (model.server.get(source.id)) |rc| {
			var binaryWriter = main.utils.BinaryWriter.init(main.stackAllocator);
			defer binaryWriter.deinit();
			if (rc.save(&binaryWriter, .playerNearby) == .save) {
				for (main.server.connectionManager.connections.items) |conn| {
					main.network.protocols.EntityComponentUpdate.load(conn, source.id, model.entityComponentID, model.entityComponentVersion, binaryWriter.data.items);
				}
			}
		}
	}
}
