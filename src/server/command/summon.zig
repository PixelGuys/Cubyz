const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const description = "Summons an entity";
pub const usage = "/summon";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len != 0) {
		source.sendMessage("#ff0000Too many arguments for command /summon. Expected no arguments.", .{});
		return;
	}

    const id = main.server.User.increaseId();

    var entity: main.server.Entity = .{
        .pos = source.player.pos,
        .vel = @splat(0),
        .rot = @splat(0),
        .health = 8,
        .maxHealth = 8,
        .energy = 8,
        .maxEnergy = 8,
        .entityType = main.entity.getTypeById("cubyz:snail"),
        .id = id,
    };

    const list = main.ZonElement.initArray(main.stackAllocator);
    defer list.deinit(main.stackAllocator);

    const data = entity.save(main.stackAllocator);
    data.put("id", id);
    data.put("name", "Silly Guy");

    list.append(data);

    const updateData = list.toStringEfficient(main.stackAllocator, &.{});
    defer main.stackAllocator.free(updateData);

    const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
    defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
    for(userList) |user| {
        main.network.Protocols.entity.send(user.conn, updateData);
    }

    _ = main.server.world.?.addEntity(entity);
}
