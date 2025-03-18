const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const openDir = main.files.openDir;
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
	other,
	empty,

	fn fromString(string: []const u8) BlueprintSubCommand {
		return std.meta.stringToEnum(BlueprintSubCommand, string) orelse {
			if(string.len == 0) return .empty;
			return .other;
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
	_ = switch(subcommand) {
		.save => blueprintSave(argsList.items, source),
		.delete => blueprintDelete(argsList.items, source),
		.load => blueprintLoad(argsList.items, source),
		.list => blueprintList(source),
		.other => {
			source.sendMessage("#ff0000Unrecognized subcommand for /blueprint: '{s}'", .{argsList.items[0]});
		},
		.empty => {
			source.sendMessage("#ff0000Missing subcommand for **/blueprint**, usage: {s} ", .{usage});
		},
	} catch |err| {
		std.log.info("Error: {s}", .{@errorName(err)});
		source.sendMessage("#ff0000Error: {s}", .{@errorName(err)});
	};
}

fn blueprintSave(args: []const []const u8, source: *User) !void {
	if(args.len < 2) {
		source.sendMessage("#ff0000**/blueprint save** requires FILENAME argument.", .{});
		return;
	}
	if(args.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for **/blueprint save**. Expected 1 argument, FILENAME.", .{});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	if(source.commandData.clipboard) |clipboard| {
		const storedBlueprint = clipboard.store(main.stackAllocator);
		defer main.stackAllocator.free(storedBlueprint);

		const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args[1]);
		defer main.stackAllocator.free(fileName);

		var blueprintsDir = try openDir("blueprints");
		defer blueprintsDir.close();

		try blueprintsDir.write(fileName, storedBlueprint);

		std.log.info("Saved clipboard to blueprint file: {s}", .{fileName});
		source.sendMessage("#00ff00Saved clipboard to blueprint file: {s}", .{fileName});
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to save.", .{});
	}
}

fn ensureBlueprintExtension(allocator: NeverFailingAllocator, fileName: []const u8) []const u8 {
	if(!std.ascii.endsWithIgnoreCase(fileName, ".blp")) {
		return std.fmt.allocPrint(allocator.allocator, "{s}.blp", .{fileName}) catch unreachable;
	} else {
		return allocator.dupe(u8, fileName);
	}
}

fn blueprintDelete(args: []const []const u8, source: *User) !void {
	if(args.len < 2) {
		source.sendMessage("#ff0000**/blueprint delete** requires FILENAME argument.", .{});
		return;
	}
	if(args.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for **/blueprint delete**. Expected 1 argument, FILENAME.", .{});
		return;
	}

	const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args[1]);
	defer main.stackAllocator.free(fileName);

	var blueprintsDir = try openDir("blueprints");
	defer blueprintsDir.close();

	try blueprintsDir.dir.deleteFile(fileName);

	std.log.info("Deleted blueprint file: {s}", .{fileName});
	source.sendMessage("#ff0000Deleted blueprint file: {s}", .{fileName});
}

fn blueprintList(source: *User) !void {
	var blueprintsDir = try std.fs.cwd().makeOpenPath("blueprints", .{.iterate = true});
	defer blueprintsDir.close();

	var directoryIterator = blueprintsDir.iterate();
	var index: i32 = 0;

	while(try directoryIterator.next()) |entry| {
		if(entry.kind != .file) break;
		if(!std.ascii.endsWithIgnoreCase(entry.name, ".blp")) break;

		source.sendMessage("#ffffff{}#00ff00 {s}", .{index, entry.name});
		index += 1;
	}
}

fn blueprintLoad(args: []const []const u8, source: *User) !void {
	if(args.len < 2) {
		source.sendMessage("#ff0000**/blueprint load** requires FILENAME argument.", .{});
		return;
	}
	if(args.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for **/blueprint load**. Expected 1 argument, FILENAME.", .{});
		return;
	}

	const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args[1]);
	defer main.stackAllocator.free(fileName);

	std.fs.cwd().makeDir("blueprints") catch {};
	var blueprintsDir = try openDir("blueprints");
	defer blueprintsDir.close();

	const storedBlueprint = try blueprintsDir.read(main.stackAllocator, fileName);
	defer main.stackAllocator.free(storedBlueprint);

	source.mutex.lock();
	if(source.commandData.clipboard != null) {
		source.commandData.clipboard.?.deinit(main.globalAllocator);
	}
	source.commandData.clipboard = try Blueprint.load(main.globalAllocator, storedBlueprint);
	source.mutex.unlock();

	std.log.info("Loaded blueprint file: {s}", .{fileName});
	source.sendMessage("#00ff00Loaded blueprint file: {s}", .{fileName});
}
