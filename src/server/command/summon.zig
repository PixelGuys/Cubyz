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

    source.sendMessage("#ff0000/summon is not implemented yet.", .{});
	
	_ = main.ecs.addEntity(main.entity.getTypeById("cubyz:snail"));
}
