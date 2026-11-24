const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const model = main.entity.components.@"cubyz:model";

pub const description = "Lookup or change your avatar";
pub const usage =
	\\/summon <x> <y> <z>
;
pub const Args = union(enum) {
	@"/summon <x> <y> <z>": struct {
		x: command.Coordinate,
		y: command.Coordinate,
		z: command.Coordinate,
	},
};

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}

	const params = args.@"/summon <x> <y> <z>";
	const entityPos = command.resolveCoordinates(params.x, params.y, params.z, source) catch return;

	const entity = main.entity.assignEntityWithNextFreeId();
	if (main.entity.components.@"cubyz:model".server.get(entity) == null) {
		if (main.entityModel.playerEntityModels.items.len != 0) {
			const defaultModel = main.entityModel.playerEntityModels.items[main.random.nextIntBounded(u32, &main.seed, @intCast(main.entityModel.playerEntityModels.items.len))];
			main.entity.components.@"cubyz:model".server.put(entity, .{.entityModel = defaultModel});
		}
	}
	var serverEntity = main.server.Entity.createEmptyServerEntity(entity);
	serverEntity.pos = entityPos;
	serverEntity.name = "summoned entity";

	const userList = main.server.getUserList(main.stackAllocator);
	defer main.stackAllocator.free(userList);
	// Let the other clients know about this new one.
	{
		const zonArray = main.ZonElement.initArray(main.stackAllocator);
		defer zonArray.deinit(main.stackAllocator);

		const entityZon = serverEntity.save(main.stackAllocator, .playerNearby);
		zonArray.array.append(entityZon);
		const data = zonArray.toStringEfficient(main.stackAllocator, &.{});
		defer main.stackAllocator.free(data);
		for (userList) |other| {
			main.network.protocols.entity.send(other.conn, data);
		}
	}
}
