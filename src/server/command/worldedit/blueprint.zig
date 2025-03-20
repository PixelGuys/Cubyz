const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const openDir = main.files.openDir;
const Dir = main.files.Dir;
const List = main.List;
const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const description = "Input-output operations on blueprints.";
pub const usage =
	\\/blueprint save <file-name>
	\\/blueprint delete <file-name>
	\\/blueprint load <file-name>
	\\/blueprint list
;

const BlueprintSubCommand = enum {
	save,
	delete,
	load,
	list,
	unknown,
	empty,

	fn fromString(string: []const u8) BlueprintSubCommand {
		return std.meta.stringToEnum(BlueprintSubCommand, string) orelse {
			if(string.len == 0) return .empty;
			return .unknown;
		};
	}
};

pub fn execute(args: []const u8, source: *User) void {
	var argsList = List([]const u8).init(main.stackAllocator);
	defer argsList.deinit();

	var splitIterator = std.mem.splitScalar(u8, args, ' ');
	while(splitIterator.next()) |a| {
		argsList.append(a);
	}

	if(argsList.items.len < 1) {
		source.sendMessage("#ff0000Not enough arguments for /blueprint, expected at least 1.", .{});
		return;
	}
	const subcommand = BlueprintSubCommand.fromString(argsList.items[0]);
	switch(subcommand) {
		.save => blueprintSave(argsList.items, source),
		.delete => blueprintDelete(argsList.items, source),
		.load => blueprintLoad(argsList.items, source),
		.list => blueprintList(source),
		.unknown => {
			source.sendMessage("#ff0000Unrecognized subcommand for /blueprint: '{s}'", .{argsList.items[0]});
		},
		.empty => {
			source.sendMessage("#ff0000Missing subcommand for /blueprint, usage: {s} ", .{usage});
		},
	}
}

fn blueprintSave(args: []const []const u8, source: *User) void {
	if(args.len < 2) {
		return source.sendMessage("#ff0000/blueprint save requires file-name argument.", .{});
	}
	if(args.len >= 3) {
		return source.sendMessage("#ff0000Too many arguments for /blueprint save. Expected 1 argument, file-name.", .{});
	}

	if(source.worldEditData.clipboard) |clipboard| {
		const storedBlueprint = clipboard.store(main.stackAllocator);
		defer main.stackAllocator.free(storedBlueprint);

		const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args[1]);
		defer main.stackAllocator.free(fileName);

		var blueprintsDir = openBlueprintsDir(source) orelse return;
		defer blueprintsDir.close();

		blueprintsDir.write(fileName, storedBlueprint) catch |err| {
			return sendWarningAndLog("Failed to write blueprint file '{s}' ({s})", .{fileName, @errorName(err)}, source);
		};

		sendInfoAndLog("Saved clipboard to blueprint file: {s}", .{fileName}, source);
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to save.", .{});
	}
}

fn sendWarningAndLog(comptime fmt: []const u8, args: anytype, user: *User) void {
	std.log.warn(fmt, args);
	user.sendMessage("#ff0000" ++ fmt, args);
}

fn sendInfoAndLog(comptime fmt: []const u8, args: anytype, user: *User) void {
	std.log.info(fmt, args);
	user.sendMessage("#00ff00" ++ fmt, args);
}

fn openBlueprintsDir(source: *User) ?Dir {
	return openDir("blueprints") catch |err| blk: {
		sendWarningAndLog("Failed to open 'blueprints' directory ({s})", .{@errorName(err)}, source);
		break :blk null;
	};
}

fn ensureBlueprintExtension(allocator: NeverFailingAllocator, fileName: []const u8) []const u8 {
	if(!std.ascii.endsWithIgnoreCase(fileName, ".blp")) {
		return std.fmt.allocPrint(allocator.allocator, "{s}.blp", .{fileName}) catch unreachable;
	} else {
		return allocator.dupe(u8, fileName);
	}
}

fn blueprintDelete(args: []const []const u8, source: *User) void {
	if(args.len < 2) {
		return source.sendMessage("#ff0000/blueprint delete requires file-name argument.", .{});
	}
	if(args.len >= 3) {
		return source.sendMessage("#ff0000Too many arguments for /blueprint delete. Expected 1 argument, file-name.", .{});
	}

	const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args[1]);
	defer main.stackAllocator.free(fileName);

	var blueprintsDir = openBlueprintsDir(source) orelse return;
	defer blueprintsDir.close();

	blueprintsDir.dir.deleteFile(fileName) catch |err| {
		return sendWarningAndLog("Failed to delete blueprint file '{s}' ({s})", .{fileName, @errorName(err)}, source);
	};

	sendWarningAndLog("Deleted blueprint file: {s}", .{fileName}, source);
}

fn blueprintList(source: *User) void {
	var blueprintsDir = std.fs.cwd().makeOpenPath("blueprints", .{.iterate = true}) catch |err| {
		return sendWarningAndLog("Failed to open 'blueprints' directory ({s})", .{@errorName(err)}, source);
	};
	defer blueprintsDir.close();

	var directoryIterator = blueprintsDir.iterate();

	while(directoryIterator.next() catch |err| {
		return sendWarningAndLog("Failed to read blueprint directory ({s})", .{@errorName(err)}, source);
	}) |entry| {
		if(entry.kind != .file) break;
		if(!std.ascii.endsWithIgnoreCase(entry.name, ".blp")) break;

		source.sendMessage("#ffffff- {s}", .{entry.name});
	}
}

fn blueprintLoad(args: []const []const u8, source: *User) void {
	if(args.len < 2) {
		return source.sendMessage("#ff0000/blueprint load requires file-name argument.", .{});
	}
	if(args.len >= 3) {
		return source.sendMessage("#ff0000Too many arguments for /blueprint load. Expected 1 argument, file-name.", .{});
	}

	const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args[1]);
	defer main.stackAllocator.free(fileName);

	var blueprintsDir = openBlueprintsDir(source) orelse return;
	defer blueprintsDir.close();

	const storedBlueprint = blueprintsDir.read(main.stackAllocator, fileName) catch |err| {
		sendWarningAndLog("Failed to read blueprint file '{s}' ({s})", .{fileName, @errorName(err)}, source);
		return;
	};
	defer main.stackAllocator.free(storedBlueprint);

	if(source.worldEditData.clipboard) |oldClipboard| {
		oldClipboard.deinit(main.globalAllocator);
	}
	source.worldEditData.clipboard = Blueprint.load(main.globalAllocator, storedBlueprint) catch |err| {
		return sendWarningAndLog("Failed to load blueprint file '{s}' ({s})", .{fileName, @errorName(err)}, source);
	};

	sendInfoAndLog("Loaded blueprint file: {s}", .{fileName}, source);
}
