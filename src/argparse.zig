const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;

pub fn Parser(comptime T: type, comptime callback: ?fn(self: T) anyerror!void) type {
	return struct {
		const Self = @This();
		pub const Args = T;

		pub fn parse(allocator: NeverFailingAllocator, args: []const u8) !ParseResult(T) {
			const result = _parse(allocator, args);
			if(callback != null and result == .success) {
				try callback.?(result.success);
			}
			return result;
		}
		pub fn _parse(allocator: NeverFailingAllocator, args: []const u8) ParseResult(T) {
			switch(@typeInfo(T)) {
				inline .@"struct" => |s| {
					return parseStruct(s, allocator, args);
				},
				inline .@"union" => |u| {
					if(u.tag_type == null) @compileError("Union must have a tag type");
					return parseUnion(u, allocator, args);
				},
				else => @compileError("Only structs and unions are supported"),
			}
		}
		fn parseStruct(comptime s: std.builtin.Type.Struct, allocator: NeverFailingAllocator, args: []const u8) ParseResult(T) {
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
						inline .@"struct" => {
							if(!@hasDecl(Field, "parse")) @compileError("Struct must have a parse function");
							return try @field(Field, "parse")(arg);
						},
						inline .@"enum" => return std.meta.stringToEnum(Field, arg) orelse return error.InvalidEnum,
						inline .float => |floatInfo| return try std.fmt.parseFloat(std.meta.Float(floatInfo.bits), arg),
						inline .int => |intInfo| return try std.fmt.parseInt(std.meta.Int(intInfo.signedness, intInfo.bits), arg, 0),
						inline else => |other| @compileError("Unsupported type " ++ @tagName(other)),
					}
				},
			}
		}
		fn parseUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8) ParseResult(T) {
			var failureMessages: ListUnmanaged([]const u8) = .{};
			defer {
				for(failureMessages.items[1..]) |item| {
					allocator.free(item);
				}
				failureMessages.deinit(allocator);
			}

			failureMessages.ensureCapacity(allocator, u.fields.len + 1);
			failureMessages.appendAssumeCapacity("Provided argument list didn't match any of the valid alternative interpretations of command argument list.");

			inline for(u.fields) |field| {
				const fieldResult = Parser(field.type, null)._parse(allocator, args);
				if(fieldResult == .success) {
					return .{.success = @unionInit(T, field.name, fieldResult.success)};
				}
				failureMessages.appendAssumeCapacity(fieldResult.failure.message);
			}

			const message = join(allocator, '\n', failureMessages.items);
			return .{.failure = .{.message = message}};
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

		pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			if(self == .failure) {
				allocator.free(self.failure.message);
			}
		}
	};
}

// TODO: This could check if biome ID is valid, either always or with generic flag.
pub const BiomeId = struct {
	id: []const u8,

	pub fn parse(arg: []const u8) !BiomeId {
		return .{.id = arg};
	}
};

const Test = struct {
	var testingAllocator = main.heap.ErrorHandlingAllocator.init(std.testing.allocator);
	var allocator = testingAllocator.allocator();

	const OnlyX = Parser(struct {x: f64}, null);

	const @"float int BiomeId" = Parser(struct {
		x: f32,
		y: u64,
		biome: BiomeId,
	}, null);

	const @"Union X or XY" = Parser(union(enum) {
		x: struct {x: f64},
		xy: struct {x: f64, y: f64},
	}, null);

	const @"subCommands foo or bar" = Parser(union(enum) {
		foo: struct {cmd: enum(u1) {foo}, x: f64},
		bar: struct {cmd: enum(u1) {bar}, x: f64, y: f64},
	}, null);

	const CallbackParserArgs = struct {x: f64};

	const CallbackParser = Parser(CallbackParserArgs, testCallback);

	pub fn testCallback(self: CallbackParserArgs) !void {
		try std.testing.expect(self.x == 1.0);
		return error.CallbackTestExecutionSignal;
	}
};

test "float" {
	const result = try Test.OnlyX.parse(Test.allocator, "33.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
}

test "float negative" {
	const result = try Test.OnlyX.parse(Test.allocator, "foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "enum" {
	const ArgParser = Parser(struct {
		cmd: enum(u1) {foo},
	}, null);

	const result = try ArgParser.parse(Test.allocator, "foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.cmd == .foo);
}

test "float int float" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: f32,
	}, null);

	const result = try ArgParser.parse(Test.allocator, "33.0 154 -5654.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expect(result.success.z == -5654.0);
}

test "float int BiomeId" {
	const result = try Test.@"float int BiomeId".parse(Test.allocator, "33.0 154 cubyz:foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expectEqualStrings("cubyz:foo", result.success.biome.id);
}

test "float int BiomeId negative shuffled" {
	const result = try Test.@"float int BiomeId".parse(Test.allocator, "33.0 cubyz:foo 154");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "x or xy case x" {
	const result = try Test.@"Union X or XY".parse(Test.allocator, "0.9");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x.x == 0.9);
}

test "x or xy case xy" {
	const result = try Test.@"Union X or XY".parse(Test.allocator, "0.9 1.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.xy.x == 0.9);
	try std.testing.expect(result.success.xy.y == 1.0);
}

test "x or xy negative empty" {
	const result = try Test.@"Union X or XY".parse(Test.allocator, "");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "x or xy negative too much" {
	const result = try Test.@"Union X or XY".parse(Test.allocator, "1.0 3.0 5.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "subCommands foo" {
	const result = try Test.@"subCommands foo or bar".parse(Test.allocator, "foo 1.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.foo.cmd == .foo);
	try std.testing.expect(result.success.foo.x == 1.0);
}

test "subCommands bar" {
	const result = try Test.@"subCommands foo or bar".parse(Test.allocator, "bar 2.0 3.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.bar.cmd == .bar);
	try std.testing.expect(result.success.bar.x == 2.0);
	try std.testing.expect(result.success.bar.y == 3.0);
}

test "callback" {
	try std.testing.expectError(error.CallbackTestExecutionSignal, Test.CallbackParser.parse(Test.allocator, "1.0"));
}
