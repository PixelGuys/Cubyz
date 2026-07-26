const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
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

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	switch (args) {
		.@"/avatar <entityModel>" => |params| {
			model.server.put(user.id, .{
				.entityModel = params.entityModel.index,
			});
			user.sendMessage("#00ff00Your entity model was changed to {s}.", .{params.entityModel.index.get().entityModelId});
		},
		.@"/avatar" => {
			if (model.server.get(user.id)) |rc| {
				user.sendMessage("#00ff00You are a {s}", .{rc.entityModel.get().entityModelId});
			} else user.sendMessage("#ff00ffYou are invisible.", .{});
		},
	}
}
