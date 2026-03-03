const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "summons an entity";
pub const usage = "/summon <entityTypeID> ?<name>";

pub fn execute(args: []const u8, source: *User) void {
	if (args.len == 0) {
		source.sendMessage("#ff0000Too few arguments for command /summon. Expected one argument.", .{});
		return;
	}
	var split = std.mem.splitScalar(u8, args, ' ');

	var valueEntityType: []const u8 = undefined;
	var valueName: ?[]const u8 = null;
	if (split.next()) |entTypeName| {
		valueEntityType = entTypeName;
	}
	if (split.next()) |name| {
		valueName = name;
	}
	if (split.next() != null) {
		source.sendMessage("#ff0000Too many arguments for command /summon", .{});
		return;
	}
	if (main.entity.clientEntityTypes.get(valueEntityType)) |entityType| {
		const id = main.server.EntitySystem.add();
		const summoned = main.server.EntitySystem.getEntity(id);
		summoned.* = source.player().clone();
		summoned.entityType = entityType;

		if (valueName) |name| {
			if (summoned.name) |old| {
				main.globalAllocator.free(old);
			}
			summoned.name = main.globalAllocator.dupe(u8, name);
		}

		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.deinit(main.stackAllocator);
		main.server.EntitySystem.getEntityBasicInfo(id, zonArray.array);
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);

		for (main.server.connectionManager.connections.items) |value| {
			main.network.protocols.entity.send(value, data);
		}

		source.sendMessage("#00ff00summoned {s}.", .{valueEntityType});
	} else {
		source.sendMessage("#ff0000entityTypeID {s} doesnt exist", .{valueEntityType});
	}
}
