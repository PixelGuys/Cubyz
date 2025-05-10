const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;

const Behavior = enum {
	alternative,
	subCommand,
};

pub fn Parser(comptime T: type) type {
	return struct {
		const Self = @This();

		pub fn parse(allocator: NeverFailingAllocator, args: []const u8) !ParseResult(T) {
			switch(@typeInfo(T)) {
				inline .@"struct" => |s| {
					if(s.layout != .@"packed") @compileError("Struct must be packed");
					if(@hasDecl(T, "behavior")) @compileError("Struct can't have a behavior flag");
					return parseStruct(s, allocator, args);
				},
				inline .@"union" => |u| {
					if(u.tag_type == null) @compileError("Union must have a tag type");
					if(!@hasDecl(T, "behavior")) @compileError("Union must have a behavior flag");
					return parseUnion(u, allocator, args);
				},
				else => unreachable,
			}
		}
		fn parseStruct(comptime s: std.builtin.Type.Struct, allocator: NeverFailingAllocator, args: []const u8) !ParseResult(T) {
			var result: T = undefined;

			var split = std.mem.splitScalar(u8, args, ' ');
			var offset: usize = 0;
			var count: usize = 0;

			inline for(s.fields) |field| {
				if(!std.mem.eql(u8, field.name, "flags")) {
					const _arg = split.next();
					defer {
						if(_arg) |arg| offset += arg.len + 1;
						count += 1;
					}

					@field(result, field.name) = parseArgument(field.type, _arg) catch |err| {
						const message = std.fmt.allocPrint(allocator.allocator, "Failed to parse argument {} due to error {s} (offset {})", .{count, @errorName(err), offset}) catch unreachable;
						return .{.failure = .{.message = message}};
					};
				}
			}

			if(split.next() != null) {
				const message = std.fmt.allocPrint(allocator.allocator, "Too many arguments for command, expected {}", .{count}) catch unreachable;
				return .{.failure = .{.message = message}};
			}

			if(@hasDecl(T, "callback")) {
				return try @field(result, "callback")(result);
			}
			return .{.success = result};
		}
		fn parseArgument(comptime Field: type, _arg: ?[]const u8) !Field {
			switch(@typeInfo(Field)) {
				inline .optional => |optionalInfo| {
					if(_arg == null) return null;
					return try parseArgument(optionalInfo.child, _arg);
				},
				else => |fieldInfo| {
					const arg = _arg orelse return error.MissingArgument;
					switch(fieldInfo) {
						inline .@"struct" => |structInfo| {
							if(!@hasDecl(structInfo, "parse")) @compileError("Struct must have a parse function");
							return try @field(Field, "parse")(arg);
						},
						inline .float => |floatInfo| return try std.fmt.parseFloat(std.meta.Float(floatInfo.bits), arg),
						inline .int => |intInfo| return try std.fmt.parseInt(std.meta.Int(intInfo.signedness, intInfo.bits), arg, 0),
						inline else => |other| @compileError("Unsupported type " ++ @tagName(other)),
					}
				},
			}
		}
		fn parseUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8) !ParseResult(T) {
			const behavior = @field(u, "behavior");
			var result: ParseResult(T) = undefined;

			const failureMessages: ListUnmanaged([]const u8) = .{};
			defer {
				for(failureMessages.items[1..]) |item| {
					allocator.free(item);
				}
				failureMessages.deinit();
			}

			failureMessages.ensureCapacity(allocator, u.fields.len + 1);
			failureMessages.appendAssumeCapacity("Provided argument list didn't match any of the valid alternative interpretations of command argument list.");

			inline for(u.fields) |field| {
				result = switch(behavior) {
					.alternative => try parseAlternative(field, allocator, args),
					.subCommand => try parseSubCommand(field, allocator, args),
				};
				if(result == .success) return result;
				failureMessages.appendAssumeCapacity(result.failure.message);
			}

			const message = join(allocator, '\n', failureMessages.items);
			return .{.failure = .{.message = message}};
		}
		fn parseAlternative(comptime s: std.builtin.Type.UnionField, allocator: NeverFailingAllocator, args: []const u8) !ParseResult(T) {
			return Parser(s.type).parse(allocator, args);
		}
		fn parseSubCommand(comptime s: std.builtin.Type.UnionField, allocator: NeverFailingAllocator, args: []const u8) !ParseResult(T) {
			var split = std.mem.splitScalar(u8, args, ' ');
			const arg = split.next();
			if(arg == null) {
				const message = std.fmt.allocPrint(allocator.allocator, "Expected subcommand name {s}, nothing found", .{s.name}) catch unreachable;
				return .{.failure = .{.message = message}};
			}
			if(!std.mem.eql(u8, arg, s.name)) {
				const message = std.fmt.allocPrint(allocator.allocator, "Expected subcommand name {s}, found {s}", .{s.name, arg}) catch unreachable;
				return .{.failure = .{.message = message}};
			}
			return Parser(s.type).parse(allocator, split.rest());
		}
	};
}

pub fn join(allocator: NeverFailingAllocator, char: u8, args: [][]const u8) []const u8 {
	var totalLength: usize = 0;
	for(args) |arg| {
		totalLength += arg.len;
	}
	totalLength += args.len - 1;

	const result = allocator.alloc(u8, totalLength);
	var offset: usize = 0;

	for(args) |arg| {
		@memcpy(result[offset .. offset + arg.len], arg);
		offset += arg.len;
		if(offset < totalLength) {
			result[offset] = char;
			offset += 1;
		}
	}

	return result;
}

pub fn ParseResult(comptime SuccessT: type) type {
	return union(enum) {
		failure: struct {
			message: []const u8,
		},
		success: SuccessT,
	};
}

pub const BiomeId = struct {
	id: []const u8,

	pub fn parse(arg: []const u8) !BiomeId {
		return .{.id = arg};
	}
};

const Test = struct {
	var testingAllocator = main.heap.ErrorHandlingAllocator.init(std.testing.allocator);
	var allocator = testingAllocator.allocator();

	const OnlyX = Parser(packed struct {
		x: f64,
	});
};

test "parse float" {
	const result = try Test.OnlyX.parse(Test.allocator, "33.0");

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
}

test "parse float negative" {
	const result = try Test.OnlyX.parse(Test.allocator, "33.0");

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
}

test "parse float int float" {
	const ArgParser = Parser(packed struct {
		x: f64,
		y: i32,
		z: f32,
	});

	const result = try ArgParser.parse(Test.allocator, "33.0 154 -5654.0");

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expect(result.success.z == -5654.0);
}
