const std = @import("std");

const main = @import("main");
const vec = main.vec;
const Vec3d = vec.Vec3d;
const User = main.server.User;

pub fn parsePosition(args: *std.mem.SplitIterator(u8, .scalar), source: *User) anyerror!Vec3d {
	return .{try parseOnCoordinate(args.next() orelse return error.TooFewArguments, source.player.pos[0], source), try parseOnCoordinate(args.next() orelse return error.TooFewArguments, source.player.pos[1], source), try parseOnCoordinate(args.next() orelse return error.TooFewArguments, source.player.pos[2], source)};
}

fn parseOnCoordinate(arg: []const u8, playerPos: f64, source: *User) anyerror!f64 {
	const hasTilde = if(arg.len == 0) false else arg[0] == '~';
	const numberSlice = if(hasTilde) arg[1..] else arg;
	const num: f64 = std.fmt.parseFloat(f64, numberSlice) catch ret: {
		if(arg.len > 1 or arg.len == 0) {
			source.sendMessage("#ff0000Expected number or \"~\", found \"{s}\"", .{arg});
			return error.InvalidNumber;
		}
		break :ret 0;
	};

	return if(hasTilde) playerPos + num else num;
}

pub fn parseBool(arg: []const u8) anyerror!bool {
	if(std.mem.eql(u8, arg, "true")) {
		return true;
	} else if(std.mem.eql(u8, arg, "false")) {
		return false;
	}

	return error.InvalidBoolean;
}
