const std = @import("std");

const main = @import("main");

const ecs = main.ecs;

const vec = main.vec;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const ZonElement = main.ZonElement;

pub const id = "transform_networking";

pub fn onServerUpdate() void {
	var entityData: main.List(main.entity.EntityNetworkData) = .init(main.stackAllocator);
	defer entityData.deinit();

	for (main.ecs.componentStorage.transform.dense.items) |items| {
		entityData.append(.{
			.id = items.value.id,
			.pos = items.value.pos,
			.vel = items.value.vel,
			.rot = items.value.rot,
		});
	}
	
	const userList = main.server.getUserListAndIncreaseRefCount(main.stackAllocator);
	defer main.server.freeUserListAndDecreaseRefCount(main.stackAllocator, userList);
	for(userList) |user| {
		main.network.Protocols.entityPosition.send(user.conn, user.getTransform().pos, entityData.items, &.{});
	}
	entityData.clearAndFree(main.globalAllocator);
}