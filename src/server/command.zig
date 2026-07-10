const std = @import("std");

const main = @import("main");
const Blueprint = main.blueprint.Blueprint;
const Mask = main.blueprint.Mask;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const List = main.List;
const User = main.server.User;

pub const commands = @import("commands");
const allDecls = @typeInfo(commands).@"struct".decls;

pub const Command = struct {
	exec: *const fn (args: []const u8, source: *User) void,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
	permissionPath: []const u8,
};

pub var registeredCommands: std.StringHashMap(Command) = undefined;
var aliases: std.StringHashMap([]const u8) = undefined;
pub var userAliases: std.StringHashMap([]const u8) = undefined;

fn shortAliasOf(comptime fullName: []const u8) []const u8 {
	const afterSlash = if (std.mem.lastIndexOfScalar(u8, fullName, '/')) |idx| fullName[idx + 1 ..] else fullName;
	return if (std.mem.indexOfScalar(u8, afterSlash, ':')) |idx| afterSlash[idx + 1 ..] else afterSlash;
}

const commandAliases: [allDecls.len][]const u8 = blk: {
	@setEvalBranchQuota(1_000_000);
	var result: [allDecls.len][]const u8 = undefined;
	for (allDecls, 0..) |decl, i| result[i] = shortAliasOf(decl.name);
	break :blk result;
};

const aliasIsUnique: [allDecls.len]bool = blk: {
	@setEvalBranchQuota(1_000_000);
	var result: [allDecls.len]bool = undefined;
	for (commandAliases, 0..) |alias, i| {
		var count: usize = 0;
		for (commandAliases) |other| {
			if (std.mem.eql(u8, alias, other)) count += 1;
		}
		result[i] = count == 1;
	}
	break :blk result;
};

pub fn init() void {
	registeredCommands = .init(main.globalAllocator.allocator);
	aliases = .init(main.globalAllocator.allocator);
	userAliases = .init(main.globalAllocator.allocator);

	inline for (allDecls, 0..) |decl, i| {
		const commandAlias = commandAliases[i];
		const isUniqueAlias = aliasIsUnique[i];

		registeredCommands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commands, decl.name).description,
			.usage = @field(commands, decl.name).usage,
			.exec = &@field(commands, decl.name).execute,
			.permissionPath = "/command/" ++ decl.name,
		}) catch unreachable;

		if (isUniqueAlias) {
			aliases.put(commandAlias, decl.name) catch unreachable;
			std.log.debug("Registered command '/{s}' (alias '/{s}')", .{decl.name, commandAlias});
		} else {
			std.log.debug("Registered command '/{s}' (no alias, conflicts with another mod)", .{decl.name});
		}
	}
}

pub fn deinit() void {
	registeredCommands.deinit();
	aliases.deinit();
	var it = userAliases.iterator();
	while (it.next()) |entry| {
		main.globalAllocator.free(entry.key_ptr.*);
		main.globalAllocator.free(entry.value_ptr.*);
	}
	userAliases.deinit();
}

fn resolveCommand(command: []const u8) ?Command {
	if (registeredCommands.get(command)) |cmd| return cmd;
	if (userAliases.get(command)) |fullId| return registeredCommands.get(fullId);
	if (aliases.get(command)) |fullId| return registeredCommands.get(fullId);
	return null;
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if (resolveCommand(command)) |cmd| {
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

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *List(u8)) error{ParseError}!Coordinate {
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

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *List(u8)) error{ParseError}!PlayerIndex {
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

pub const BiomeId = struct {
	biome: *const main.server.terrain.biomes.Biome,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, args: []const u8, errorMessage: *List(u8)) error{ParseError}!@This() {
		return .{.biome = main.server.terrain.biomes.getByIdOptional(args) orelse {
			errorMessage.print(allocator, "Couldn't find biome for <{s}> with id \"{s}\"", .{name, args});
			return error.ParseError;
		}};
	}
};

pub const EntityModel = struct {
	index: main.entityModel.EntityModelIndex,

	pub fn parse(allocator: NeverFailingAllocator, name: []const u8, args: []const u8, errorMessage: *List(u8)) error{ParseError}!EntityModel {
		if (main.entityModel.getById(args)) |entityModel| {
			return .{.index = entityModel};
		} else {
			errorMessage.print(allocator, "Couldn't find EntityModel for <{s}> with id \"{s}\"", .{name, args});
			return error.ParseError;
		}
	}
};

pub const MaskExpression = struct {
	mask: Mask,

	pub fn parse(allocator: NeverFailingAllocator, _: []const u8, args: []const u8, errorMessage: *List(u8)) error{ParseError}!MaskExpression {
		return .{.mask = Mask.initFromString(allocator, args) catch |err| {
			errorMessage.print(allocator, "Couldn't parse mask: {s}", .{@errorName(err)});
			return error.ParseError;
		}};
	}

	pub fn deinit(self: MaskExpression, allocator: NeverFailingAllocator) void {
		self.mask.deinit(allocator);
	}
};
