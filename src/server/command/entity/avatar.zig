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
const Args = union(enum) {
	@"/avatar": struct {},
	@"/avatar <entityModel>": struct { entityModel: command.EntityModel },
};
const ArgParser = main.argparse.Parser(Args, .{.commandName = "/avatar"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: main.ListUnmanaged(u8) = .{};
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};

	switch (result) {
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
