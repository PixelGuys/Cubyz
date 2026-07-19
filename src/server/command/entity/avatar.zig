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

pub fn execute(args: Args, _source: Source) void {
	if (_source != .user) {
		_source.sendMessage("Command doesn't support running from console", .{});
		return;
	}
	const source = _source.user;
	switch (args) {
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
