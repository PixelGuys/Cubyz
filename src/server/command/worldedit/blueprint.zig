const std = @import("std");

const main = @import("main");
const command = main.server.command;
const Source = command.Source;
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const Dir = main.files.Dir;
const ListManaged = main.ListManaged;
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

pub const Args = union(enum) {
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

pub fn execute(args: Args, source: Source) void {
	if (source != .user) {
		source.sendMessage("Command cannot be run without a user", .{});
		return;
	}
	const user = source.user;
	switch (args) {
		.@"/blueprint save <filePath>" => |params| blueprintSave(params.filePath, user),
		.@"/blueprint delete <filePath>" => |params| blueprintDelete(params.filePath, user),
		.@"/blueprint load <filePath>" => |params| blueprintLoad(params.filePath, user),
		.@"/blueprint list" => blueprintList(user),
	}
}

fn blueprintSave(filePath: FilePath, user: *User) void {
	if (user.worldEditData.clipboard) |clipboard| {
		const storedBlueprint = clipboard.store(main.stackAllocator);
		defer main.stackAllocator.free(storedBlueprint);

		var blueprintsDir = openBlueprintsDir(user) orelse return;
		defer blueprintsDir.close();

		blueprintsDir.write(filePath.path, storedBlueprint) catch |err| {
			return sendWarningAndLog("Failed to write blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, user);
		};

		sendInfoAndLog("Saved clipboard to blueprint file: {s}", .{filePath.path}, user);
	} else {
		user.sendMessage("#ff0000Error: No clipboard content to save.", .{});
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

fn openBlueprintsDir(user: *User) ?Dir {
	return main.files.cubyzDir().openDir("blueprints") catch |err| {
		sendWarningAndLog("Failed to open 'blueprints' directory ({s})", .{@errorName(err)}, user);
		return null;
	};
}

fn blueprintDelete(filePath: FilePath, user: *User) void {
	var blueprintsDir = openBlueprintsDir(user) orelse return;
	defer blueprintsDir.close();

	blueprintsDir.deleteFile(filePath.path) catch |err| {
		return sendWarningAndLog("Failed to delete blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, user);
	};

	sendWarningAndLog("Deleted blueprint file: {s}", .{filePath.path}, user);
}

fn blueprintList(user: *User) void {
	var blueprintsDir = main.files.cubyzDir().openIterableDir("blueprints") catch |err| {
		return sendWarningAndLog("Failed to open 'blueprints' directory ({s})", .{@errorName(err)}, user);
	};
	defer blueprintsDir.close();

	var directoryWalker = blueprintsDir.walk(main.stackAllocator);
	defer directoryWalker.deinit();

	while (directoryWalker.next(main.io) catch |err| {
		return sendWarningAndLog("Failed to read blueprint directory ({s})", .{@errorName(err)}, user);
	}) |entry| {
		if (entry.kind != .file) continue;
		if (!std.ascii.endsWithIgnoreCase(entry.basename, ".blp")) continue;

		user.sendMessage("#ffffff- {s}", .{entry.path});
	}
}

fn blueprintLoad(filePath: FilePath, user: *User) void {
	var blueprintsDir = openBlueprintsDir(user) orelse return;
	defer blueprintsDir.close();

	const storedBlueprint = blueprintsDir.read(main.stackAllocator, filePath.path) catch |err| {
		sendWarningAndLog("Failed to read blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, user);
		return;
	};
	defer main.stackAllocator.free(storedBlueprint);

	if (user.worldEditData.clipboard) |oldClipboard| {
		oldClipboard.deinit(main.globalAllocator);
	}
	user.worldEditData.clipboard = Blueprint.load(main.globalAllocator, storedBlueprint) catch |err| {
		return sendWarningAndLog("Failed to load blueprint file '{s}' ({s})", .{filePath.path, @errorName(err)}, user);
	};

	sendInfoAndLog("Loaded blueprint file: {s}", .{filePath.path}, user);
}

const FilePath = struct {
	path: []const u8,

	pub fn parse(arena: NeverFailingAllocator, _: []const u8, arg: []const u8, _: *ListManaged(u8)) error{ParseError}!FilePath {
		return .{.path = ensureBlueprintExtension(arena, arg)};
	}

	fn ensureBlueprintExtension(arena: NeverFailingAllocator, fileName: []const u8) []const u8 {
		if (!std.ascii.endsWithIgnoreCase(fileName, ".blp")) {
			return arena.print("{s}.blp", .{fileName});
		} else {
			return arena.dupe(u8, fileName);
		}
	}
};
