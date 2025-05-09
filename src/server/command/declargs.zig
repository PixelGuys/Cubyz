const std = @import("std");

pub const End = struct {
	pub fn parse(args: []const u8) !End {
		if(args.len != 0) return error.ExtraArgument;
		return End{};
	}
};

pub fn Flag(comptime _flag: u8, comptime NextT: type) type {
	return struct {
		pub const flag = _flag;

		value: bool,
		next: NextT,
	};
}

pub fn Float(comptime NextT: type) type {
	return struct {
		const Self = @This();

		value: f64,
		next: NextT,

		pub fn parse(args: []const u8) !Self {
			const endIndex = std.mem.indexOfScalar(u8, args, ' ') orelse args.len;
			if(endIndex == 0) return error.MissingArgument;
			const offset: usize = if(args.len == endIndex) 0 else 1;
			const value = try std.fmt.parseFloat(f64, args[0..endIndex]);
			return .{.value = value, .next = try NextT.parse(args[endIndex + offset ..])};
		}
	};
}

pub fn BiomeId(comptime NextT: type) type {
	return struct {
		const Self = @This();

		value: []const u8,
		next: NextT,

		pub fn parse(args: []const u8) !Self {
			const endIndex = std.mem.indexOfScalar(u8, args, ' ') orelse args.len;
			if(endIndex == 0) return error.MissingArgument;
			const offset: usize = if(args.len == endIndex) 0 else 1;
			return .{.value = args[0..endIndex], .next = try NextT.parse(args[endIndex + offset ..])};
		}
	};
}

pub fn Alternative(comptime FirstNextT: type, comptime SecondNextT: type) type {
	return union(enum) {
		const Self = @This();
		first: FirstNextT,
		second: SecondNextT,

		pub fn parse(args: []const u8) !Self {
			return .{.first = FirstNextT.parse(args) catch {
				return .{.second = try SecondNextT.parse(args)};
			}};
		}
	};
}
