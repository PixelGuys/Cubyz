const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const copy = @import("copy.zig");

const List = main.List;
const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Operate on blueprints.";
pub const usage = "//blueprint <save|delete|load|list>";
pub const commandNameOverride: ?[]const u8 = "/blueprint";


const BlueprintSubCommand = enum {
	save,
	delete,
	load,
	list,
	none,

	fn fromString(string: []const u8) BlueprintSubCommand {
		return std.meta.stringToEnum(BlueprintSubCommand, string) orelse {
			return .none;
		};
	}
};


pub fn execute(args: []const u8, source: *User) void {
	var argsList = List([]const u8).init(main.stackAllocator);
	defer argsList.deinit();

	var splitIterator = std.mem.splitSequence(u8, args, " ");
	while(splitIterator.next()) |a| {
		argsList.append(main.stackAllocator.dupe(u8, a));
	}

	if(argsList.items.len < 1) {
		source.sendMessage("#ff0000Not enough arguments for //blueprint, expected at least 1.", .{});
		return;
	}
	const subcommand = BlueprintSubCommand.fromString(argsList.items[0]);
	_ = switch(subcommand) {
		.save => blueprintSave(argsList, source),
		.delete => blueprintDelete(argsList, source),
		.load => blueprintLoad(argsList, source),
		.list => blueprintList(argsList, source),
		.none => {
			source.sendMessage("#ff0000Unrecognized subcommand for //blueprint: '{s}'", .{argsList.items[0]});
		},
	} catch |err| {
		source.sendMessage("#ff0000Error: {s}", .{@errorName(err)});
	};

	for(argsList.items) |arg| {
		main.stackAllocator.free(arg);
	}
}

fn blueprintSave(args: List([]const u8), source: *User) !void {
	if(args.items.len < 2) {
		source.sendMessage("#ff0000//blueprint save requires FILENAME argument.", .{});
		return;
	}
	if(args.items.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for //blueprint save. Expected 1 argument, FILENAME.", .{});
		return;
	}
	if(copy.clipboard) |clipboard| {
		const zon = clipboard.toZon(main.stackAllocator);
		defer zon.deinit(main.stackAllocator);

		var fileName: []const u8 = args.items[1];
		if(!std.ascii.endsWithIgnoreCase(fileName, ".zig.zon")) {
			fileName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}.zig.zon", .{fileName}) catch unreachable;
		} else {
			fileName = main.stackAllocator.dupe(u8, fileName);
		}
		defer main.stackAllocator.free(fileName);

		var savesDir = try std.fs.cwd().openDir("saves", .{});
		defer savesDir.close();

		var thisSaveDir = try savesDir.openDir(main.server.world.?.name, .{});
		defer thisSaveDir.close();

		_ = thisSaveDir.makeDir("blueprints") catch null;

		var blueprintsDir = main.files.Dir.init(try thisSaveDir.openDir("blueprints", .{}));
		defer blueprintsDir.close();

		std.log.info("Saving clipboard to file: {s}", .{fileName});
		source.sendMessage("Saving clipboard to file: {s}", .{fileName});

		blueprintsDir.writeZon(fileName, zon) catch |err| {
			std.log.err("Error saving clipboard to file: {s}", .{@errorName(err)});
			source.sendMessage("#ff0000Error saving clipboard to file: {s}", .{@errorName(err)});
		};
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to save.", .{});
	}
}

fn blueprintDelete(_: List([]const u8), source: *User) void {
	source.sendMessage("#ff0000//blueprint delete not implemented.", .{});
}

fn blueprintLoad(_: List([]const u8), source: *User) void {
	source.sendMessage("#ff0000//blueprint load not implemented.", .{});
}

fn blueprintList(_: List([]const u8), source: *User) void {
	source.sendMessage("#ff0000//blueprint list not implemented.", .{});
}
