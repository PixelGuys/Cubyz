const std = @import("std");

const main = @import("main");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const Dir = main.files.Dir;
const List = main.List;
const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const description = "Input-output operations on blueprints.";
pub const usage =
	\\/blueprint save <filePath>
	\\/blueprint delete <filePath>
	\\/blueprint load <filePath>
	\\/blueprint list
;

const Args = union(enum) {
	@"/blueprint save <filePath>": struct {
		_: enum { save },
		filePath: FilePath,

		fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			self.filePath.deinit(allocator);
		}
	},
	@"/blueprint delete <filePath>": struct {
		_: enum { delete },
		filePath: FilePath,

		fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			self.filePath.deinit(allocator);
		}
	},
	@"/blueprint load <filePath>": struct {
		_: enum { load },
		filePath: FilePath,

		fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			self.filePath.deinit(allocator);
		}
	},
	@"/blueprint list": struct {
		_: enum { list },

		fn deinit(_: @This(), _: NeverFailingAllocator) void {}
	},

	fn deinit(self: Args, allocator: NeverFailingAllocator) void {
		switch (self) {
			inline else => |field| field.deinit(allocator),
		}
	}
};

const ArgParser = main.argparse.Parser(Args, .{.commandName = "/blueprint"});

pub fn execute(args: []const u8, source: *User) void {
	var errorMessage: List(u8) = .empty;
	defer errorMessage.deinit(main.stackAllocator);

	const result = ArgParser.parse(main.stackAllocator, args, &errorMessage) catch {
		source.sendMessage("#ff0000{s}", .{errorMessage.items});
		return;
	};
	defer result.deinit(main.stackAllocator);

	switch (result) {
		.@"/blueprint save <filePath>" => |params| blueprintSave(params.filePath, source),
		.@"/blueprint delete <filePath>" => |params| blueprintDelete(params.filePath, source),
		.@"/blueprint load <filePath>" => |params| blueprintLoad(params.filePath, source),
		.@"/blueprint list" => blueprintList(source),
	}
}

fn blueprintSave(filePath: FilePath, source: *User) void {
	if (source.worldEditData.clipboard) |clipboard| {
		const storedBlueprint = clipboard.store(main.stackAllocator);
		defer main.stackAllocator.free(storedBlueprint);

		var blueprintsDir = openBlueprintsDir(source) orelse return;
		defer blueprintsDir.close();

		blueprintsDir.write(filePath.path, storedBlueprint) catch |err| {
			return sendWarningAndLog("Failed to write blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, source);
		};

		sendInfoAndLog("Saved clipboard to blueprint file: {s}", .{filePath.path}, source);
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
	return main.files.cubyzDir().openDir("blueprints") catch |err| {
		sendWarningAndLog("Failed to open 'blueprints' directory ({s})", .{@errorName(err)}, source);
		return null;
	};
}

fn blueprintDelete(filePath: FilePath, source: *User) void {
	var blueprintsDir = openBlueprintsDir(source) orelse return;
	defer blueprintsDir.close();

	blueprintsDir.deleteFile(filePath.path) catch |err| {
		return sendWarningAndLog("Failed to delete blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, source);
	};

	sendWarningAndLog("Deleted blueprint file: {s}", .{filePath.path}, source);
}

fn blueprintList(source: *User) void {
	var blueprintsDir = main.files.cubyzDir().openIterableDir("blueprints") catch |err| {
		return sendWarningAndLog("Failed to open 'blueprints' directory ({s})", .{@errorName(err)}, source);
	};
	defer blueprintsDir.close();

	var directoryIterator = blueprintsDir.iterate();

	while (directoryIterator.next(main.io) catch |err| {
		return sendWarningAndLog("Failed to read blueprint directory ({s})", .{@errorName(err)}, source);
	}) |entry| {
		if (entry.kind != .file) break;
		if (!std.ascii.endsWithIgnoreCase(entry.name, ".blp")) break;

		source.sendMessage("#ffffff- {s}", .{entry.name});
	}
}

fn blueprintLoad(filePath: FilePath, source: *User) void {
	var blueprintsDir = openBlueprintsDir(source) orelse return;
	defer blueprintsDir.close();

	const storedBlueprint = blueprintsDir.read(main.stackAllocator, filePath.path) catch |err| {
		sendWarningAndLog("Failed to read blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, source);
		return;
	};
	defer main.stackAllocator.free(storedBlueprint);

	if (source.worldEditData.clipboard) |oldClipboard| {
		oldClipboard.deinit(main.globalAllocator);
	}
	source.worldEditData.clipboard = Blueprint.load(main.globalAllocator, storedBlueprint) catch |err| {
		return sendWarningAndLog("Failed to load blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, source);
	};

	sendInfoAndLog("Loaded blueprint file: {s}", .{filePath.path}, source);
}

const FilePath = struct {
	path: []const u8,

	pub fn deinit(self: FilePath, allocator: NeverFailingAllocator) void {
		allocator.free(self.path);
	}

	pub fn parse(allocator: NeverFailingAllocator, _: []const u8, arg: []const u8, _: *List(u8)) error{ParseError}!FilePath {
		return .{.path = ensureBlueprintExtension(allocator, arg)};
	}

	fn ensureBlueprintExtension(allocator: NeverFailingAllocator, fileName: []const u8) []const u8 {
		if (!std.ascii.endsWithIgnoreCase(fileName, ".blp")) {
			return std.fmt.allocPrint(allocator.allocator, "{s}.blp", .{fileName}) catch unreachable;
		} else {
			return allocator.dupe(u8, fileName);
		}
	}
};
