const std = @import("std");

const main = @import("main");
const User = main.server.User;

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const Mask = main.blueprint.Mask;

pub const description = "Set global or per brush edit mask. When used with no mask expression it will clear current mask.";
pub const usage =
	\\/mask brush <mask>
	\\/mask brush
	\\/mask global <mask>
	\\/mask global
;

const SubCommands = enum {brush, global};

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');
	const first = split.first();
	switch(std.meta.stringToEnum(SubCommands, first) orelse {
		source.sendMessage("#ff0000Unknown subcommand: '{s}'", .{first});
		return;
	}) {
		.brush => brush(split.rest(), source),
		.global => global(split.rest(), source),
	}
}

pub fn brush(args: []const u8, source: *User) void {
	if(args.len == 0) {
		source.sendMessage("Brushes are not implemented yet.", .{});
		return;
	}
	const mask = Mask.initFromString(main.globalAllocator, args) catch |err| {
		source.sendMessage("#ff0000Error parsing mask: {}", .{err});
		return;
	};
	source.sendMessage("Brushes are not implemented yet.", .{});
	mask.deinit(main.globalAllocator);
}

pub fn global(args: []const u8, source: *User) void {
	if(args.len == 0) {
		if(source.worldEditData.mask) |mask| mask.deinit(main.globalAllocator);
		source.worldEditData.mask = null;
		source.sendMessage("#00ff00Mask cleared.", .{});
		return;
	}
	const mask = Mask.initFromString(main.globalAllocator, args) catch |err| {
		source.sendMessage("#ff0000Error parsing mask: {}", .{err});
		return;
	};
	source.worldEditData.mask = mask;
	source.sendMessage("#00ff00Mask set.", .{});
}
