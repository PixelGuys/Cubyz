const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;
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

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	inline for (@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.exec = &@field(commandList, decl.name).execute,
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
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
		cmd.exec(msg[@min(end + 1, msg.len)..], source);
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub const Coordinate = union(enum) {
	relative: f64, // Relative coordinates are indicated by leading `~`.
	absolute: f64,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!Coordinate {
		const isRelative = arg[0] == '~';
		const numberSlice = if (isRelative) arg[1..] else arg;
		if (isRelative and numberSlice.len == 0) return .{.relative = 0};
		if (isRelative) {
			return .{.relative = std.fmt.parseFloat(f64, numberSlice) catch {
				errorMessage.print(allocator, "Expected number for <{s}>, found \"{s}\"", .{name, numberSlice});
				return error.ParseError;
			}};
		}
		return .{.absolute = std.fmt.parseFloat(f64, numberSlice) catch {
			errorMessage.print(allocator, "Expected number or \"~\" for <{s}>, found \"{s}\"", .{name, arg});
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

// TODO remove after every command which uses it is migrated to the argsparser #3073
fn parseAxis(arg: []const u8, playerPos: f64, source: *User) !f64 {
	const hasTilde = if (arg.len == 0) false else arg[0] == '~';
	const numberSlice = if (hasTilde) arg[1..] else arg;
	if (hasTilde and numberSlice.len == 0) return playerPos;
	const num = std.fmt.parseFloat(f64, numberSlice) catch {
		if (hasTilde) {
			source.sendMessage("#ff0000Expected number, found \"{s}\"", .{numberSlice});
		} else {
			source.sendMessage("#ff0000Expected number or \"~\", found \"{s}\"", .{arg});
		}
		return error.InvalidNumber;
	};

	return std.math.clamp(if (hasTilde) playerPos + num else num, -1e9, 1e9); // TODO: Remove clamp after #310 is implemented
}

// TODO remove after every command which uses it is migrated to the argsparser #3073
pub fn parseCoordinates(split: *std.mem.SplitIterator(u8, .scalar), source: *User) !main.vec.Vec3d {
	return blk: {
		var output: main.vec.Vec3d = undefined;
		inline for (0..3) |i| {
			output[i] = try parseAxis(split.next() orelse {
				source.sendMessage("#ff0000Too few arguments for position", .{});
				return error.TooFewArguments;
			}, source.player().pos[i], source);
		}
		break :blk output;
	};
}

// TODO remove after every command which uses it is migrated to the argsparser #3073
fn parsePlayerIndexAndIncreaseRefCount(playerIndex: []const u8, source: *User) !*User {
	if (!std.ascii.startsWithIgnoreCase(playerIndex, "@")) {
		source.sendMessage("#ff0000Player index specifiers always start with @, found \"{s}\"", .{playerIndex});
		return error.InvalidArg;
	}
	const index = std.fmt.parseInt(usize, playerIndex[1..], 10) catch {
		source.sendMessage("#ff0000Player index must be an integer, found \"{s}\"", .{playerIndex[1..]});
		return error.InvalidArg;
	};
	return main.server.getUserByIndexAndIncreaseRefCount(index) orelse {
		source.sendMessage("#ff0000Player with index {d} not found or not online", .{index});
		return error.InvalidArg;
	};
}

pub const Target = struct {
	user: *User,
	increasedRefCount: bool,

	// TODO remove after every command which uses it is migrated to the argsparser #3073
	pub fn init(split: *std.mem.SplitIterator(u8, .scalar), source: *User) !Target {
		var increasedRefCount = false;
		const user: *User = blk: {
			const userIndex = split.peek() orelse {
				source.sendMessage("#ff0000Too few arguments for command", .{});
				return error.TooFewArguments;
			};
			if (userIndex.len > 0 and userIndex[0] == '@') {
				const user = parsePlayerIndexAndIncreaseRefCount(userIndex, source) catch return error.InvalidArgs;
				increasedRefCount = true;
				_ = split.next();
				break :blk user;
			}
			break :blk source;
		};
		return .{.user = user, .increasedRefCount = increasedRefCount};
	}

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

pub const String = struct {
	string: []const u8,

	pub fn parse(_: NeverFailingAllocator, _: []const u8, arg: []const u8, _: *ListUnmanaged(u8)) error{ParseError}!String {
		return .{.string = arg};
	}
};

pub const PlayerIndex = struct {
	index: usize,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!PlayerIndex {
		if (!std.ascii.startsWithIgnoreCase(arg, "@")) {
			errorMessage.print(allocator, "Expected to start with @ for <{s}>, found \"{s}\"", .{name, arg});
			return error.ParseError;
		}
		return .{.index = std.fmt.parseInt(usize, arg[1..], 10) catch {
			errorMessage.print(allocator, "Expected and integer after @ for <{s}>, found \"{s}\"", .{name, arg[1..]});
			return error.ParseError;
		}};
	}
};
