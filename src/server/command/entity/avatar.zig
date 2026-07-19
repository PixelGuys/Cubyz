const std = @import("std");

const main = @import("main");
const command = main.server.command;
const User = main.server.User;
const model = main.entity.components.@"cubyz:model";

pub const description = "Lookup or change your avatar";
pub const usage =
	\\/avatar
	\\/avatar <entityModel>
;
pub const Args = union(enum) {
	@"/avatar": struct {},
	@"/avatar <entityModel>": struct { entityModel: command.EntityModel },
};

pub fn execute(args: *Args, source: *User) void {
	switch (args.*) {
		.@"/avatar <entityModel>" => |params| {
			model.server.put(source.id, .{
				.entityModel = params.entityModel.index,
			});
			source.sendMessage("#00ff00Your entity model was changed to {s}.", .{params.entityModel.index.get().entityModelId});
		},
		.@"/avatar" => {
			if (model.server.get(source.id)) |rc| {
				source.sendMessage("#00ff00You are a {s}", .{rc.entityModel.get().entityModelId});
			} else source.sendMessage("#ff00ffYou are invisible.", .{});
		},
	}
}
