const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;
const model = main.entity.components.@"cubyz:model";

pub const description = "Lookup or change your avatar";
pub const usage =
	\\/avatar
	\\/avatar <entityModelId>
;
const Args = union(enum) {
	@"/avatar <entityModelId>": struct { entityModelIndex: ?command.EntityModelIndex },
};
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/avatar"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	if (result.@"/avatar <entityModelId>".entityModelIndex) |entityModelIndex| {
		model.server.put(source.id, .{
			.entityModel = entityModelIndex.index,
		});
		source.sendMessage("#00ff00You're EntityModel was changed to {s}.", .{entityModelIndex.index.get().entityModelId});

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
	} else {
		if (model.server.get(source.id)) |rc| {
			source.sendMessage("#00ff00You are a {s}", .{rc.entityModel.get().entityModelId});
		} else source.sendMessage("#ff00ffYou are invisible.", .{});
		return;
	}
}
