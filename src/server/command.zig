const std = @import("std");

const main = @import("main");
const Blueprint = main.blueprint.Blueprint;
const Mask = main.blueprint.Mask;
const Pattern = main.blueprint.Pattern;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListManaged = main.ListManaged;
const User = main.server.User;
pub const commandList = @import("command/_list.zig");

pub const Command = struct {
	exec: *const fn (args: []const u8, source: *User) void,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
	permissionPath: []const u8,
};

pub var commands: std.StringHashMap(Command) = undefined;

fn initExecutionFn(comptime name: []const u8) *const fn (args: []const u8, source: *User) void {
	return struct {
		const ArgPaser = main.argparse.Parser(@field(commandList, name).Args, .{.commandName = name});
		fn exec(msg: []const u8, source: *User) void {
			var arena: main.heap.NeverFailingArenaAllocator = .init(main.stackAllocator);
			defer arena.deinit();
			var errorMessage: main.ListManaged(u8) = .init(arena.allocator());
			const result = ArgPaser.parse(arena.allocator(), msg, &errorMessage) catch {
				source.sendMessage("#ff0000{s}", .{errorMessage.items});
				return;
			};
			@field(commandList, name).execute(result, source);
		}
	}.exec;
}

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	inline for (@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.exec = initExecutionFn(decl.name),
			.permissionPath = "/command/" ++ decl.name,
		}) catch unreachable;
		std.log.debug("Registered command: '/{s}'", .{decl.name});
	}
}

pub fn deinit() void {
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if (commands.get(command)) |cmd| {
		if (!source.hasPermission(cmd.permissionPath)) {
			source.sendMessage("#ff0000No permission to use Command \"{s}\"", .{command});
			return;
		}
		cmd.exec(msg[@min(end + 1, msg.len)..], source);
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub const Coordinate = union(enum) {
	relative: f64, // Relative coordinates are indicated by leading `~`.
	absolute: f64,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!Coordinate {
		_ = allocator; // autofix
		const isRelative = arg[0] == '~';
		const numberSlice = if (isRelative) arg[1..] else arg;
		if (isRelative and numberSlice.len == 0) return .{.relative = 0};
		if (isRelative) {
			return .{.relative = std.fmt.parseFloat(f64, numberSlice) catch {
				errorMessage.print("Expected number for <{s}>, found \"{s}\"", .{name, numberSlice});
				return error.ParseError;
			}};
		}
		return .{.absolute = std.fmt.parseFloat(f64, numberSlice) catch {
			errorMessage.print("Expected number or \"~\" for <{s}>, found \"{s}\"", .{name, arg});
			return error.ParseError;
		}};
	}
};

pub fn resolveCoordinates(x: Coordinate, y: Coordinate, z: Coordinate, player: *User) main.vec.Vec3d {
	return .{
		// TODO: Remove clamp after #310 is implemented
		std.math.clamp(if (x == .relative) player.player().pos[0] + x.relative else x.absolute, -1e9, 1e9),
		std.math.clamp(if (y == .relative) player.player().pos[1] + y.relative else y.absolute, -1e9, 1e9),
		std.math.clamp(if (z == .relative) player.player().pos[2] + z.relative else z.absolute, -1e9, 1e9),
	};
}

pub const Target = struct {
	user: *User,
	increasedRefCount: bool,

	pub fn fromPlayerIndex(arg: ?PlayerIndex, source: *User) !Target {
		const playerIndex = arg orelse return .{
			.user = source,
			.increasedRefCount = false,
		};
		return .{
			.user = main.server.getUserByIndexAndIncreaseRefCount(playerIndex.index) orelse {
				source.sendMessage("#ff0000Player with index {d} not found or not online", .{playerIndex.index});
				return error.InvalidArg;
			},
			.increasedRefCount = true,
		};
	}

	pub fn deinit(self: Target) void {
		if (self.increasedRefCount) self.user.decreaseRefCount();
	}
};

/// Get current selection from user data. This function will output appropriate error to chat upon failure.
pub fn getCurrentSelection(source: *User) !Blueprint.Selection {
	const pos1 = source.worldEditData.selectionPosition1 orelse {
		source.sendMessage("#ff0000Position 1 isn't set", .{});
		return error.SelectionPartiallyUnset;
	};
	const pos2 = source.worldEditData.selectionPosition2 orelse {
		source.sendMessage("#ff0000Position 2 isn't set", .{});
		return error.SelectionPartiallyUnset;
	};
	return .initFromInclusive(pos1, pos2);
}

pub const PlayerIndex = struct {
	index: usize,

	pub fn parse(_: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!PlayerIndex {
		if (!std.ascii.startsWithIgnoreCase(arg, "@")) {
			errorMessage.print("Expected to start with @ for <{s}>, found \"{s}\"", .{name, arg});
			return error.ParseError;
		}
		return .{.index = std.fmt.parseInt(usize, arg[1..], 10) catch {
			errorMessage.print("Expected and integer after @ for <{s}>, found \"{s}\"", .{name, arg[1..]});
			return error.ParseError;
		}};
	}
};

pub const BiomeId = struct {
	biome: *const main.server.terrain.biomes.Biome,

	pub fn parse(_: NeverFailingAllocator, name: []const u8, args: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!@This() {
		return .{.biome = main.server.terrain.biomes.getByIdOptional(args) orelse {
			errorMessage.print("Couldn't find biome for <{s}> with id \"{s}\"", .{name, args});
			return error.ParseError;
		}};
	}
};

pub const EntityModel = struct {
	index: main.entityModel.EntityModelIndex,

	pub fn parse(_: NeverFailingAllocator, name: []const u8, args: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!EntityModel {
		if (main.entityModel.getById(args)) |entityModel| {
			return .{.index = entityModel};
		} else {
			errorMessage.print("Couldn't find EntityModel for <{s}> with id \"{s}\"", .{name, args});
			return error.ParseError;
		}
	}
};

pub const MaskExpression = struct {
	mask: Mask,

	pub fn parse(arena: NeverFailingAllocator, _: []const u8, args: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!MaskExpression {
		return .{.mask = Mask.initFromString(arena, args) catch |err| {
			errorMessage.print("Couldn't parse mask: {s}", .{@errorName(err)});
			return error.ParseError;
		}};
	}
};

pub const PatternExpression = struct {
	pattern: Pattern,

	pub fn parse(arena: NeverFailingAllocator, _: []const u8, args: []const u8, errorMessage: *ListManaged(u8)) error{ParseError}!PatternExpression {
		return .{.pattern = Pattern.initFromString(arena, args) catch |err| {
			errorMessage.print("Couldn't parse pattern: {s}", .{@errorName(err)});
			return error.ParseError;
		}};
	}
};
