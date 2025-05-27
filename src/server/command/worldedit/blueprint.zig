const std = @import("std");

const main = @import("main");
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
	\\/blueprint save <id> [--scope/-s <remote|local|game|world>]
	\\/blueprint delete <id> [--scope/-s <remote|local|game|world>]
	\\/blueprint load <id> [--scope/-s <remote|local|game|world>]
	\\/blueprint list [--scope/-s <remote|local|game|world>]
;

const BlueprintSubCommand = enum {
	save,
	delete,
	load,
	list,
};

const StorageScope = enum {
	remote,
	local,
	game,
	world,
};

pub const ParsedId = struct {
	addon: []const u8,
	asset: []const u8,
	params: []const u8,

	pub fn parse(id: []const u8) !ParsedId {
		var self: ParsedId = undefined;
		var split = std.mem.splitScalar(u8, id, ':');

		self.addon = split.next() orelse "";
		for(0..self.addon.len) |i| {
			if(!std.ascii.isAlphanumeric(self.addon[i])) return error.InvalidAddonName;
		}
		self.asset = split.next() orelse "";
		for(0..self.asset.len) |i| {
			const c = self.asset[i];
			if(!std.ascii.isAlphanumeric(c) and c != '/') return error.InvalidAssetName;
		}
		self.params = split.next() orelse "";

		return self;
	}
};

const CommandParams = struct {
	command: ?BlueprintSubCommand = null,
	id: ?[]const u8 = null,
	scope: StorageScope = .remote,

	pub fn getPath(self: CommandParams, allocator: main.heap.NeverFailingAllocator) ![]const u8 {
		const parsed = try ParsedId.parse(self.id.?);

		switch(self.scope) {
			.remote => return std.fmt.allocPrint(allocator.allocator, "./blueprints/{s}/{s}.blp", .{parsed.addon, parsed.asset}),
			.local => return std.fmt.allocPrint(allocator.allocator, "./blueprints/{s}/{s}.blp", .{parsed.addon, parsed.asset}),
			.game => return std.fmt.allocPrint(allocator.allocator, "./assets/{s}/blueprints/{s}.blp", .{parsed.addon, parsed.asset}),
			.world => return std.fmt.allocPrint(allocator.allocator, "./saves/{s}/assets/{s}/blueprints/{s}.blp", .{main.server.world.?.name, parsed.addon, parsed.asset}),
		}
	}
};

pub fn execute(args: []const u8, source: *User) void {
	var params = CommandParams{};

	var splitIterator = std.mem.splitScalar(u8, args, ' ');
	const command = splitIterator.next() orelse {
		return source.sendMessage("#ff0000Missing subcommand for '/blueprint', usage: {s}", .{usage});
	};
	params.command = std.meta.stringToEnum(BlueprintSubCommand, command) orelse {
		return source.sendMessage("#ff0000Invalid subcommand for '/blueprint': '{s}', usage: {s}", .{command, usage});
	};
	while(splitIterator.next()) |next| {
		if(std.mem.eql(u8, next, "--scope") or std.mem.eql(u8, next, "-s")) {
			const scope = splitIterator.next() orelse {
				return source.sendMessage("#ff0000Missing argument for '--scope' option, usage: {s}", .{usage});
			};
			params.scope = std.meta.stringToEnum(StorageScope, scope) orelse {
				return source.sendMessage("#ff0000Invalid scope '{s}', usage: {s}", .{@tagName(params.scope), usage});
			};
			continue;
		}
		if(params.id == null) {
			params.id = next;
			continue;
		}
		return source.sendMessage("#ff0000Too many arguments for /blueprint command, usage: {s}", .{usage});
	}

	switch(params.command.?) {
		.save => blueprintSave(params, source),
		.delete => blueprintDelete(params, source),
		.load => blueprintLoad(params, source),
		.list => blueprintList(params, source),
	}
}

fn blueprintSave(params: CommandParams, source: *User) void {
	if(params.id == null) {
		return source.sendMessage("#ff0000'/blueprint save' requires blueprint id argument.", .{});
	}
	if(source.worldEditData.clipboard) |clipboard| {
		const filePath: []const u8 = params.getPath(main.stackAllocator) catch |err| {
			return source.sendWarningAndLog("Failed to determine path for blueprint file '{s}' ({s})", .{params.id.?, @errorName(err)});
		};
		defer main.stackAllocator.free(filePath);

		switch(params.scope) {
			.local => main.network.Protocols.genericUpdate.sendBlueprintSave(source.conn, filePath, clipboard),
			.remote, .game, .world => {
				const storedBlueprint = clipboard.store(main.stackAllocator);
				defer main.stackAllocator.free(storedBlueprint);

				var split = std.mem.splitBackwardsScalar(u8, filePath, '/');
				const fileName = split.first();
				const fileDir = split.rest();

				var dir = main.files.openDir(fileDir) catch |err| {
					return source.sendWarningAndLog("Failed to open directory '{s}' ({s})", .{fileDir, @errorName(err)});
				};
				defer dir.close();

				dir.write(fileName, storedBlueprint) catch |err| {
					return source.sendWarningAndLog("Failed to write blueprint file '{s}' ({s})", .{filePath, @errorName(err)});
				};
			},
		}
		source.sendInfoAndLog("Saved clipboard to blueprint to file: '{s}'", .{filePath});
	} else {
		source.sendMessage("#ff0000Error: No clipboard content to save.", .{});
	}
}

fn blueprintDelete(params: CommandParams, source: *User) void {
	if(params.id == null) {
		return source.sendMessage("#ff0000'/blueprint delete' requires blueprint id argument.", .{});
	}
	const filePath: []const u8 = params.getPath(main.stackAllocator) catch |err| {
		return source.sendWarningAndLog("Failed to determine path for blueprint file '{s}' ({s})", .{params.id.?, @errorName(err)});
	};
	defer main.stackAllocator.free(filePath);

	switch(params.scope) {
		.local => main.network.Protocols.genericUpdate.sendBlueprintDelete(source.conn, filePath),
		.remote, .game, .world => {
			std.fs.cwd().deleteFile(filePath) catch |err| {
				return source.sendWarningAndLog("Failed to delete blueprint file '{s}' ({s})", .{filePath, @errorName(err)});
			};
			source.sendInfoAndLog("Deleted blueprint file: '{s}'", .{filePath});
		},
	}
}

fn blueprintList(params: CommandParams, source: *User) void {
	switch(params.scope) {
		.local => main.network.Protocols.genericUpdate.sendBlueprintListRequest(source.conn),
		.remote => {
			var blueprintsDir = std.fs.cwd().openDir("blueprints", .{.iterate = true}) catch return;
			defer blueprintsDir.close();

			var isEmpty = true;

			var iterator = blueprintsDir.iterate();
			while(iterator.next() catch return) |addon| {
				if(addon.kind != .directory) continue;

				var addonDir = blueprintsDir.openDir(addon.name, .{.iterate = true}) catch continue;
				defer addonDir.close();

				var walker = addonDir.walk(main.stackAllocator.allocator) catch continue;
				defer walker.deinit();

				while(walker.next() catch continue) |entry| {
					if(entry.kind != .file) continue;

					var split = std.mem.splitBackwardsScalar(u8, entry.path, '.');
					_ = split.first();
					source.sendMessage("#ffffff{s}:{s}", .{addon.name, split.rest()});

					isEmpty = false;
				}
			}
			if(isEmpty) {
				source.sendInfoAndLog("No blueprints found.", .{});
			}
		},
		.world, .game => {
			const assetsPath = switch(params.scope) {
				.game => main.stackAllocator.allocator.dupe(u8, "assets") catch unreachable,
				.world => std.fmt.allocPrint(main.stackAllocator.allocator, "saves/{s}/assets", .{main.server.world.?.name}) catch unreachable,
				else => unreachable,
			};
			defer main.stackAllocator.free(assetsPath);

			var assetsDir = std.fs.cwd().openDir(assetsPath, .{.iterate = true}) catch return;
			defer assetsDir.close();

			var isEmpty = true;

			var iterator = assetsDir.iterate();
			while(iterator.next() catch return) |addon| {
				if(addon.kind != .directory) continue;

				var addonDir = assetsDir.openDir(addon.name, .{.iterate = true}) catch continue;
				defer addonDir.close();

				var blueprintsDir = addonDir.openDir("blueprints", .{.iterate = true}) catch continue;
				defer blueprintsDir.close();

				var walker = blueprintsDir.walk(main.stackAllocator.allocator) catch continue;
				defer walker.deinit();

				while(walker.next() catch continue) |entry| {
					if(entry.kind != .file) continue;

					var split = std.mem.splitBackwardsScalar(u8, entry.path, '.');
					_ = split.first();
					source.sendMessage("#ffffff{s}:{s}", .{addon.name, split.rest()});

					isEmpty = false;
				}
			}
			if(isEmpty) {
				source.sendInfoAndLog("No blueprints found.", .{});
			}
		},
	}
}

fn blueprintLoad(params: CommandParams, source: *User) void {
	if(params.id == null) {
		return source.sendMessage("#ff0000'/blueprint load' requires blueprint id argument.", .{});
	}
	const filePath: []const u8 = params.getPath(main.stackAllocator) catch |err| {
		return source.sendWarningAndLog("Failed to determine path for blueprint file '{s}' ({s})", .{params.id.?, @errorName(err)});
	};
	defer main.stackAllocator.free(filePath);

	switch(params.scope) {
		.local => main.network.Protocols.genericUpdate.sendBlueprintLoadRequest(source.conn, filePath),
		.remote, .game, .world => {
			var blueprintFile = std.fs.cwd().openFile(filePath, .{.mode = .read_only}) catch |err| {
				return source.sendWarningAndLog("Failed to open blueprint file '{s}' ({s})", .{filePath, @errorName(err)});
			};
			defer blueprintFile.close();

			const raw = blueprintFile.readToEndAlloc(main.stackAllocator.allocator, std.math.maxInt(usize)) catch |err| {
				return source.sendWarningAndLog("Failed to write blueprint to file '{s}' ({s})", .{filePath, @errorName(err)});
			};
			defer main.stackAllocator.free(raw);

			const blueprint = Blueprint.load(main.globalAllocator, raw) catch |err| {
				return source.sendWarningAndLog("Failed to load blueprint from file '{s}' ({s})", .{filePath, @errorName(err)});
			};

			const oldClipboard = source.worldEditData.clipboard;
			source.worldEditData.clipboard = blueprint;

			if(oldClipboard) |_oldClipboard| {
				_oldClipboard.deinit(main.globalAllocator);
			}
		},
	}
	source.sendInfoAndLog("Saved clipboard to blueprint to file: '{s}'", .{filePath});
}
