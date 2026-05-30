const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;
const utils = main.utils;

pub const Options = struct {
	commandName: []const u8,
};

const ResolveMode = enum {
	parse,
	autocomplete,
};

pub fn Parser(comptime T: type, comptime options: Options) type {
	return struct {
		const Self = @This();

		/// Parse the string `args` according to the schema defined in `T` type parameter of the Parser.
		/// Result is returned from this function as a value of type `T`.
		///
		/// Arguments:
		/// - `allocator` - will be used for dynamic allocations of the parsing result returned.
		/// - `args` - unprocessed string containing command arguments without command name.
		/// - `errorMessage` - out parameter used to store and return errors, if any occur. Has to be allocated with stackAllocator.
		pub fn parse(allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!T {
			return resolve(ResolveMode.parse, allocator, args, errorMessage);
		}

		pub fn resolve(
			comptime mode: ResolveMode,
			allocator: NeverFailingAllocator,
			args: []const u8,
			errorMessage: *ListUnmanaged(u8),
		) switch (mode) {
			.autocomplete => AutocompleteResult,
			.parse => error{ParseError}!T,
		} {
			switch (@typeInfo(T)) {
				inline .@"struct" => |s| {
					return resolveStruct(mode, s, allocator, args, errorMessage);
				},
				inline .@"union" => |u| {
					if (u.tag_type == null) @compileError("Union must have a tag type");
					return switch (mode) {
						.autocomplete => autocompleteUnion(u, allocator, args, errorMessage),
						.parse => parseUnion(u, allocator, args, errorMessage),
					};
				},
				else => @compileError("Only structs and unions are supported"),
			}
		}

		fn resolveStruct(
			comptime mode: ResolveMode,
			comptime s: std.builtin.Type.Struct,
			allocator: NeverFailingAllocator,
			args: []const u8,
			errorMessage: *ListUnmanaged(u8),
		) switch (mode) {
			.autocomplete => AutocompleteResult,
			.parse => error{ParseError}!T,
		} {
			var result: T = undefined;
			var tokens: Tokenizer = .init(main.stackAllocator, args);
			defer tokens.deinit(main.stackAllocator);

			var tempErrorMessage: ListUnmanaged(u8) = .{};
			defer tempErrorMessage.deinit(main.stackAllocator);

			var nextArgument = tokens.next() catch |err| return otherError(errorMessage, err);

			inline for (s.fields) |field| {
				const value = resolveArgument(field.type, allocator, field.name[0..], nextArgument, &tempErrorMessage);

				if (value == error.ParseError) {
					if (@typeInfo(field.type) == .optional) {
						@field(result, field.name) = null;
						tempErrorMessage.clearRetainingCapacity();
					} else {
						errorMessage.appendSlice(main.stackAllocator, tempErrorMessage.items);
						return error.ParseError;
					}
				} else {
					@field(result, field.name) = value catch unreachable;
					tempErrorMessage.clearRetainingCapacity();
					nextArgument = tokens.next() catch |err| return otherError(errorMessage, err);
				}
			}

			if (nextArgument != null) {
				errorMessage.print(main.stackAllocator, "Too many arguments for command, expected {}", .{s.fields.len});
				return error.ParseError;
			}

			return result;
		}

		fn otherError(errorMessage: *ListUnmanaged(u8), err: anyerror) error{ParseError} {
			errorMessage.print(main.stackAllocator, "Couldn't parse arguments list: {s}", .{@errorName(err)});
			return error.ParseError;
		}

		fn resolveArgument(comptime Field: type, allocator: NeverFailingAllocator, name: []const u8, argument: ?[]const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!Field {
			const fieldTypeInfo = @typeInfo(Field);
			if (fieldTypeInfo == .optional) {
				if (argument == null) return error.ParseError;
				return resolveArgument(fieldTypeInfo.optional.child, allocator, name, argument, errorMessage) catch |err| {
					return err;
				};
			}

			const arg = argument orelse {
				errorMessage.print(main.stackAllocator, "Missing argument at position <{s}>", .{name});
				return error.ParseError;
			};

			if (Field == []const u8) {
				return arg;
			}

			switch (fieldTypeInfo) {
				inline .@"struct", .@"union" => {
					if (!@hasDecl(Field, "parse")) @compileError("Structs / Unions must have a parse function");
					return @field(Field, "parse")(allocator, name, arg, errorMessage);
				},
				inline .@"enum" => {
					return std.meta.stringToEnum(Field, arg) orelse {
						const str = main.meta.concatComptime("/", std.meta.fieldNames(Field));
						errorMessage.print(main.stackAllocator, "Expected one of {s} for <{s}>, found \"{s}\"", .{str, name, arg});
						return error.ParseError;
					};
				},
				inline .float => |floatInfo| return {
					return std.fmt.parseFloat(std.meta.Float(floatInfo.bits), arg) catch {
						errorMessage.print(main.stackAllocator, "Expected a number for <{s}>, found \"{s}\"", .{name, arg});
						return error.ParseError;
					};
				},
				inline .int => |intInfo| {
					return std.fmt.parseInt(std.meta.Int(intInfo.signedness, intInfo.bits), arg, 0) catch {
						errorMessage.print(main.stackAllocator, "Expected an integer for <{s}>, found \"{s}\"", .{name, arg});
						return error.ParseError;
					};
				},
				inline else => |other| @compileError("Unsupported type " ++ @tagName(other)),
			}
		}

		fn parseUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!T {
			var tempErrorMessage: ListUnmanaged(u8) = .{};
			defer tempErrorMessage.deinit(allocator);

			tempErrorMessage.appendSlice(allocator, "---");

			inline for (u.fields) |field| {
				tempErrorMessage.append(allocator, '\n');
				tempErrorMessage.appendSlice(allocator, field.name);
				tempErrorMessage.append(allocator, '\n');

				const result = Parser(field.type, options).resolve(.parse, allocator, args, &tempErrorMessage);
				if (result != error.ParseError) {
					return @unionInit(T, field.name, result catch unreachable);
				}
				tempErrorMessage.appendSlice(allocator, "\n---");
			}

			errorMessage.appendSlice(allocator, tempErrorMessage.items);
			return error.ParseError;
		}

		fn autocompleteUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8) AutocompleteResult {
			_ = u;
			_ = allocator;
			_ = args;
			return .{};
		}
	};
}

pub const AutocompleteResult = struct {};
// MARK: tests
const Test = struct {
	const OnlyX = Parser(struct { x: f64 }, .{.commandName = ""});

	const @"Union X or XY" = Parser(union(enum) {
		x: struct { x: f64 },
		xy: struct { x: f64, y: f64 },
	}, .{.commandName = ""});

	const @"subCommands foo or bar" = Parser(union(enum) {
		foo: struct { cmd: enum(u1) { foo }, x: f64 },
		bar: struct { cmd: enum(u1) { bar }, x: f64, y: f64 },
	}, .{.commandName = ""});
};

test "no arguments" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Parser(struct {}, .{.commandName = "foo"}).parse(main.stackAllocator, "", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	_ = try resultOrError;
}

test "float" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.OnlyX.parse(main.stackAllocator, "33.0", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.x, 33.0);
}

test "float negative" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.OnlyX.parse(main.stackAllocator, "foo", &errors);

	try std.testing.expectEqualStrings("Expected a number for <x>, found \"foo\"", errors.items);
	try std.testing.expectError(error.ParseError, resultOrError);
}

test "enum" {
	const ArgParser = Parser(struct {
		cmd: enum(u1) { foo },
	}, .{.commandName = "c"});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = ArgParser.parse(main.stackAllocator, "foo", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.cmd, .foo);
}

test "float int float" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: f32,
	}, .{.commandName = ""});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = ArgParser.parse(main.stackAllocator, "33.0 154 -5654.0", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.x, 33.0);
	try std.testing.expectEqual(result.y, 154);
	try std.testing.expectEqual(result.z, -5654.0);
}

test "float int optional float missing" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: ?f32,
	}, .{.commandName = ""});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = ArgParser.parse(main.stackAllocator, "33.0 154", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.x, 33.0);
	try std.testing.expectEqual(result.y, 154);
	try std.testing.expectEqual(result.z, null);
}

test "float int optional float present" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: ?f32,
	}, .{.commandName = ""});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = ArgParser.parse(main.stackAllocator, "33.0 154 0.1", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.x, 33.0);
	try std.testing.expectEqual(result.y, 154);
	try std.testing.expectEqual(result.z, 0.1);
}

test "x or xy case x" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.@"Union X or XY".parse(main.stackAllocator, "0.9", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.x.x, 0.9);
}

test "x or xy case xy" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.@"Union X or XY".parse(main.stackAllocator, "0.9 1.0", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.xy.x, 0.9);
	try std.testing.expectEqual(result.xy.y, 1.0);
}

test "x or xy negative empty" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.@"Union X or XY".parse(main.stackAllocator, "", &errors);

	try std.testing.expectEqualStrings(
		\\---
		\\x
		\\Missing argument at position <x>
		\\---
		\\xy
		\\Missing argument at position <x>
		\\---
	, errors.items);
	try std.testing.expectError(error.ParseError, resultOrError);
}

test "x or xy negative too many args" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.@"Union X or XY".parse(main.stackAllocator, "1.0 3.0 5.0", &errors);

	try std.testing.expectEqualStrings(
		\\---
		\\x
		\\Too many arguments for command, expected 1
		\\---
		\\xy
		\\Too many arguments for command, expected 2
		\\---
	, errors.items);
	try std.testing.expectError(error.ParseError, resultOrError);
}

test "subCommands foo" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.@"subCommands foo or bar".parse(main.stackAllocator, "foo 1.0", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.foo.cmd, .foo);
	try std.testing.expectEqual(result.foo.x, 1.0);
}

test "subCommands bar" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(main.stackAllocator);

	const resultOrError = Test.@"subCommands foo or bar".parse(main.stackAllocator, "bar 2.0 3.0", &errors);

	try std.testing.expectEqualStrings("", errors.items);
	const result = try resultOrError;
	try std.testing.expectEqual(result.bar.cmd, .bar);
	try std.testing.expectEqual(result.bar.x, 2.0);
	try std.testing.expectEqual(result.bar.y, 3.0);
}

const Tokenizer = struct {
	buffer: []const u8,
	index: usize,
	// Buffer used to store string literals. String literals contain escape sequences which have to be resolved
	// Before returning the string to caller.
	stringTokenBuffer: ListUnmanaged(u8),

	pub fn init(allocator: NeverFailingAllocator, buffer: []const u8) Tokenizer {
		return .{
			.buffer = buffer,
			.index = 0,
			.stringTokenBuffer = .initCapacity(allocator, buffer.len),
		};
	}

	pub fn deinit(self: Tokenizer, allocator: NeverFailingAllocator) void {
		self.stringTokenBuffer.deinit(allocator);
	}

	/// Returns a slice containing next token, or null if tokenization is complete.
	/// Slices are owned by Tokenizer.
	pub fn next(self: *Tokenizer) !?[]const u8 {
		self.skipWhitespace();
		if (self.index == self.buffer.len) return null;

		return switch (self.buffer[self.index]) {
			'"', '\'', '`' => try self.nextString(self.index),
			else => self.nextIdentifier(self.index),
		};
	}

	fn skipWhitespace(self: *Tokenizer) void {
		while (self.index < self.buffer.len and std.ascii.isWhitespace(self.buffer[self.index])) : (self.index += 1) {}
	}
	/// Returns a slice containing next string token with escape sequences resolved.
	///
	/// A string has to be enclosed in one of quote type.
	/// Strings support escape sequences with use of \, one for each quote char and
	/// special escape sequence of \\ to create a single \
	fn nextString(self: *Tokenizer, start: usize) ![]const u8 {
		// We fetch the opening quote, this way we always match the right quote type.
		const start_c = self.buffer[start];
		self.index += 1;
		if (self.index == self.buffer.len) return "";

		// We only copy string content chars to self.stringTokenBuffer, so it will likely be desynced from self.buffer
		// therefore we need a separate start index for it.
		const tokenStart = self.stringTokenBuffer.items.len;

		// Escaping always works only on next character, so its enough to toggle a bolean to track escaping.
		var escaped: bool = false;

		while (self.index < self.buffer.len) : (self.index += 1) {
			const c = self.buffer[self.index];
			if (escaped) {
				escaped = false;
				switch (c) {
					'\\', '"', '\'', '`' => {
						self.stringTokenBuffer.appendAssumeCapacity(c);
					},
					'n' => {
						self.stringTokenBuffer.appendAssumeCapacity('\n');
					},
					else => return error.InvalidEscapeSequence,
				}
				continue;
			}
			if (c == '\\') {
				escaped = !escaped;
				continue;
			}

			// We have encountered the matching closing quote and it was not escaped, thats the end of this string.
			// Since we did not append ending quote, nor opening quote to stringTokenBuffer, we don't have to explicitly
			// strip them.
			if (c == start_c) {
				self.index += 1; // We have to skip closing quote!
				return self.stringTokenBuffer.items[tokenStart..];
			}

			self.stringTokenBuffer.appendAssumeCapacity(c);
		}
		// We have exhausted the buffer without encountering string end character.
		return self.stringTokenBuffer.items[tokenStart..];
	}

	fn nextIdentifier(self: *Tokenizer, start: usize) []const u8 {
		while (self.index < self.buffer.len and !std.ascii.isWhitespace(self.buffer[self.index])) : (self.index += 1) {}
		return self.buffer[start..self.index];
	}
};

fn expectEqualOptionalStrings(expectedOptional: ?[]const u8, actualOptional: ?[]const u8) !void {
	if (expectedOptional) |expected| {
		if (actualOptional) |actual| {
			return try std.testing.expectEqualStrings(expected, actual);
		}
		std.debug.print("expected '{s}', got: null", .{expected});
		return try std.testing.expect(expectedOptional == null);
	}
	if (actualOptional) |actual| std.debug.print("expected null, got: '{s}'", .{actual});
	return try std.testing.expect(null == actualOptional);
}

test "Tokenizer: empty string" {
	var t: Tokenizer = .init(main.stackAllocator, "");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{null}) |token| try expectEqualOptionalStrings(token, try t.next());
}

test "Tokenizer: signle identifier" {
	var t: Tokenizer = .init(main.stackAllocator, "foo");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{"foo", null}) |token| try expectEqualOptionalStrings(token, try t.next());
}

test "Tokenizer: series of plain identifiers" {
	var t: Tokenizer = .init(main.stackAllocator, "foo bar spam");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{"foo", "bar", "spam", null}) |token| try expectEqualOptionalStrings(token, try t.next());
}

test "Tokenizer: string double quote" {
	var t: Tokenizer = .init(main.stackAllocator, "\"foo bar\"");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{"foo bar", null}) |token| try expectEqualOptionalStrings(token, try t.next());
}

test "Tokenizer: string double quote with escaped quote" {
	var t: Tokenizer = .init(main.stackAllocator, "\"foo \\\"bar\"");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{"foo \"bar", null}) |token| try expectEqualOptionalStrings(token, try t.next());
}

test "Tokenizer: string invalid escape sequence" {
	var t: Tokenizer = .init(main.stackAllocator, "\"\\k\"");
	defer t.deinit(main.stackAllocator);
	try std.testing.expectError(error.InvalidEscapeSequence, t.next());
}

test "Tokenizer: identifiers and string double quote" {
	var t: Tokenizer = .init(main.stackAllocator, "foo \"bar spam\" foo2");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{"foo", "bar spam", "foo2", null}) |token| try expectEqualOptionalStrings(token, try t.next());
}

test "Tokenizer: strings different quotes" {
	var t: Tokenizer = .init(main.stackAllocator, "'foo 1' \"bar 2\" `spam 3`");
	defer t.deinit(main.stackAllocator);
	for ([_]?[]const u8{"foo 1", "bar 2", "spam 3", null}) |token| try expectEqualOptionalStrings(token, try t.next());
}
