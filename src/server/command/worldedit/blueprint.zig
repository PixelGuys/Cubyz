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
		source.sendMessage("#ff0000/blueprint save requires file-name argument.", .{});
		return;
	}
	if(args.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for /blueprint save. Expected 1 argument, file-name.", .{});
		return;
	}

	if(source.worldEditData.clipboard) |clipboard| {
		var file = BlueprintFile.init(main.stackAllocator, args[1], source) catch return;
		defer file.deinit(main.stackAllocator);
		file.write(clipboard) catch return;
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to save.", .{});
	}
}

const BlueprintFile = struct {
	fileName: []const u8,
	blueprintsDir: Dir,
	source: *User,

	pub fn init(allocator: NeverFailingAllocator, fileName: []const u8, source: *User) !BlueprintFile {
		const blueprintsDir = openDir("blueprints") catch |err| {
			std.log.warn("Failed to open 'blueprints' directory ({s})", .{@errorName(err)});
			source.sendMessage("#ff0000Failed to open 'blueprints' directory ({s})", .{@errorName(err)});
			return error.Failed;
		};
		return BlueprintFile{
			.fileName = ensureBlueprintExtension(allocator, fileName),
			.blueprintsDir = blueprintsDir,
			.source = source,
		};
	}

	pub fn deinit(self: *BlueprintFile, allocator: NeverFailingAllocator) void {
		self.blueprintsDir.close();
		allocator.free(self.fileName);
	}

	pub fn write(self: BlueprintFile, bp: Blueprint) !void {
		const storedBlueprint = bp.store(main.stackAllocator);
		defer main.stackAllocator.free(storedBlueprint);

		self.blueprintsDir.write(self.fileName, storedBlueprint) catch |err| {
			std.log.warn("Failed to write blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			self.source.sendMessage("#ff0000Failed to write blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			return error.Failed;
		};

		std.log.info("Saved clipboard to blueprint file: {s}", .{self.fileName});
		self.source.sendMessage("#00ff00Saved clipboard to blueprint file: {s}", .{self.fileName});
	}

	pub fn delete(self: BlueprintFile) !void {
		self.blueprintsDir.dir.deleteFile(self.fileName) catch |err| {
			std.log.warn("Failed to delete blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			self.source.sendMessage("#ff0000Failed to delete blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			return error.Failed;
		};

		std.log.info("Deleted blueprint file: {s}", .{self.fileName});
		self.source.sendMessage("#ff0000Deleted blueprint file: {s}", .{self.fileName});
	}

	pub fn load(self: BlueprintFile, allocator: NeverFailingAllocator) ?Blueprint {
		const storedBlueprint = self.blueprintsDir.read(main.stackAllocator, self.fileName) catch |err| {
			std.log.warn("Failed to read blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			self.source.sendMessage("#ff0000Failed to read blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			return null;
		};
		defer main.stackAllocator.free(storedBlueprint);

		const bp = Blueprint.load(allocator, storedBlueprint) catch |err| blk: {
			std.log.warn("Failed to load blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			self.source.sendMessage("#ff0000Failed to load blueprint file '{s}' ({s})", .{self.fileName, @errorName(err)});
			break :blk null;
		};

		std.log.info("Loaded blueprint file: {s}", .{self.fileName});
		self.source.sendMessage("#00ff00Loaded blueprint file: {s}", .{self.fileName});

		return bp;
	}
};

fn ensureBlueprintExtension(allocator: NeverFailingAllocator, fileName: []const u8) []const u8 {
	if(!std.ascii.endsWithIgnoreCase(fileName, ".blp")) {
		return std.fmt.allocPrint(allocator.allocator, "{s}.blp", .{fileName}) catch unreachable;
	} else {
		return allocator.dupe(u8, fileName);
	}
}

fn blueprintDelete(args: []const []const u8, source: *User) void {
	if(args.len < 2) {
		source.sendMessage("#ff0000/blueprint delete requires file-name argument.", .{});
		return;
	}
	if(args.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for /blueprint delete. Expected 1 argument, file-name.", .{});
		return;
	}

	var file = BlueprintFile.init(main.stackAllocator, args[1], source) catch return;
	defer file.deinit(main.stackAllocator);
	file.delete() catch return;
}

fn blueprintList(source: *User) void {
	var blueprintsDir = std.fs.cwd().makeOpenPath("blueprints", .{.iterate = true}) catch |err| {
		std.log.warn("Failed to open 'blueprints' directory ({s})", .{@errorName(err)});
		source.sendMessage("#ff0000Failed to open 'blueprints' directory ({s})", .{@errorName(err)});
		return;
	};
	defer blueprintsDir.close();

	var directoryIterator = blueprintsDir.iterate();

	while(directoryIterator.next() catch |err| {
		std.log.warn("Failed to read blueprint directory ({s})", .{@errorName(err)});
		source.sendMessage("#ff0000Failed to read blueprint directory ({s})", .{@errorName(err)});
		return;
	}) |entry| {
		if(entry.kind != .file) break;
		if(!std.ascii.endsWithIgnoreCase(entry.name, ".blp")) break;

		source.sendMessage("#ffffff- {s}", .{entry.name});
	}
}

fn blueprintLoad(args: []const []const u8, source: *User) void {
	if(args.len < 2) {
		source.sendMessage("#ff0000/blueprint load requires file-name argument.", .{});
		return;
	}
	if(args.len >= 3) {
		source.sendMessage("#ff0000Too many arguments for /blueprint load. Expected 1 argument, file-name.", .{});
		return;
	}

	var file = BlueprintFile.init(main.stackAllocator, args[1], source) catch return;
	defer file.deinit(main.stackAllocator);
	const loadedBlueprint = file.load(main.globalAllocator) orelse return;

	if(source.worldEditData.clipboard) |oldClipboard| {
		oldClipboard.deinit(main.globalAllocator);
	}
	source.worldEditData.clipboard = loadedBlueprint;
}
