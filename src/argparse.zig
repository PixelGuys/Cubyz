const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;
const utils = main.utils;

pub const Options = struct {
	commandName: []const u8,
};

pub fn Parser(comptime T: type, comptime options: Options) type {
	return struct {
		const Self = @This();

		pub fn parse(allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) ?T {
			return resolve(false, allocator, args, errorMessage);
		}

		pub fn autocomplete(allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) AutocompleteResult {
			return resolve(true, allocator, args, errorMessage);
		}

		pub fn resolve(comptime doAutocomplete: bool, allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) if(doAutocomplete) AutocompleteResult else ?T {
			switch(@typeInfo(T)) {
				inline .@"struct" => |s| {
					return resolveStruct(doAutocomplete, s, allocator, args, errorMessage);
				},
				inline .@"union" => |u| {
					if(u.tag_type == null) @compileError("Union must have a tag type");
					return if(doAutocomplete) autocompleteUnion(u, allocator, args, errorMessage) else parseUnion(u, allocator, args, errorMessage);
				},
				else => @compileError("Only structs and unions are supported"),
			}
		}

		fn resolveStruct(comptime doAutocomplete: bool, comptime s: std.builtin.Type.Struct, allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) if(doAutocomplete) AutocompleteResult else ?T {
			var result: T = undefined;
			var split = std.mem.splitScalar(u8, args, ' ');

			var tempErrorMessage: ListUnmanaged(u8) = .{};
			defer tempErrorMessage.deinit(allocator);

			var nextArgument: ?[]const u8 = split.next();

			inline for(s.fields) |field| {
				const value = resolveArgument(field.type, allocator, field.name[0..], nextArgument, &tempErrorMessage);

				if(value == error.ParseError) {
					if(@typeInfo(field.type) == .optional) {
						@field(result, field.name) = null;
						tempErrorMessage.clearRetainingCapacity();
					} else {
						errorMessage.appendSlice(allocator, tempErrorMessage.items);
						return null;
					}
				} else {
					@field(result, field.name) = value catch unreachable;
					tempErrorMessage.clearRetainingCapacity();
					nextArgument = split.next();
				}
			}

			if(split.next() != null) {
				failWithMessage(allocator, errorMessage, "Too many arguments for command, expected {}", .{s.fields.len});
				return null;
			}

			return result;
		}

		fn resolveArgument(comptime Field: type, allocator: NeverFailingAllocator, name: []const u8, argument: ?[]const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!Field {
			switch(@typeInfo(Field)) {
				inline .optional => |optionalInfo| {
					if(argument == null) return error.ParseError;
					return resolveArgument(optionalInfo.child, allocator, name, argument, errorMessage) catch |err| {
						return err;
					};
				},
				inline .@"struct" => {
					const arg = argument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return error.ParseError;
					};
					if(!@hasDecl(Field, "parse")) @compileError("Struct must have a parse function");
					return @field(Field, "parse")(allocator, name, arg, errorMessage);
				},
				inline .@"enum" => {
					const arg = argument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return error.ParseError;
					};
					return std.meta.stringToEnum(Field, arg) orelse {
						failWithMessage(allocator, errorMessage, "Expected one of {} for <{s}>, found \"{s}\"", .{.{std.meta.fieldNames(Field)}, name, arg});
						return error.ParseError;
					};
				},
				inline .float => |floatInfo| return {
					const arg = argument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return error.ParseError;
					};
					return std.fmt.parseFloat(std.meta.Float(floatInfo.bits), arg) catch {
						failWithMessage(allocator, errorMessage, "Expected a number for <{s}>, found \"{s}\"", .{name, arg});
						return error.ParseError;
					};
				},
				inline .int => |intInfo| {
					const arg = argument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return error.ParseError;
					};
					return std.fmt.parseInt(std.meta.Int(intInfo.signedness, intInfo.bits), arg, 0) catch {
						failWithMessage(allocator, errorMessage, "Expected an integer for <{s}>, found \"{s}\"", .{name, arg});
						return error.ParseError;
					};
				},
				inline else => |other| @compileError("Unsupported type " ++ @tagName(other)),
			}
		}

		const missingArgumentMessage = "Missing argument at position <{s}>";

		fn autocompleteArgument(comptime Field: type, allocator: NeverFailingAllocator, _arg: ?[]const u8) AutocompleteResult {
			const arg = _arg orelse return .{};
			switch(@typeInfo(Field)) {
				inline .@"struct" => {
					if(!@hasDecl(Field, "autocomplete")) @compileError("Struct must have an autocomplete function");
					return try @field(Field, "autocomplete")(allocator, arg);
				},
				inline .@"enum" => {
					var result: AutocompleteResult = .{};
					inline for(std.meta.fieldNames(Field)) |fieldName| {
						if(!std.mem.startsWith(u8, fieldName, arg)) continue;
						result.suggestions.append(allocator, allocator.dupe(u8, fieldName));
					}
					return result;
				},
				inline else => return .{},
			}
		}

		fn parseUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8, errorMessage: *ListUnmanaged(u8)) ?T {
			var tempErrorMessage: ListUnmanaged(u8) = .{};
			defer tempErrorMessage.deinit(allocator);

			tempErrorMessage.appendSlice(allocator, "---");

			inline for(u.fields) |field| {
				tempErrorMessage.append(allocator, '\n');
				tempErrorMessage.appendSlice(allocator, field.name);
				tempErrorMessage.append(allocator, '\n');

				const result = Parser(field.type, options).resolve(false, allocator, args, &tempErrorMessage);
				if(result) |value| {
					return @unionInit(T, field.name, value);
				}
				tempErrorMessage.appendSlice(allocator, "\n---");
			}

			errorMessage.appendSlice(allocator, tempErrorMessage.items);
			return null;
		}

		fn autocompleteUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8) AutocompleteResult {
			var result: AutocompleteResult = .{};

			inline for(u.fields) |field| {
				var completion = Parser(field.type).resolve(true, allocator, args);
				defer completion.deinit(allocator);

				result.takeSuggestions(allocator, &completion);
			}

			return result;
		}
	};
}

fn failWithMessage(allocator: NeverFailingAllocator, errorMessage: *ListUnmanaged(u8), comptime fmt: []const u8, args: anytype) void {
	const msg = std.fmt.allocPrint(allocator.allocator, fmt, args) catch unreachable;
	defer allocator.free(msg);
	errorMessage.appendSlice(allocator, msg);
}

pub const AutocompleteResult = struct {
	suggestions: ListUnmanaged([]const u8) = .{},

	pub fn takeSuggestions(self: *AutocompleteResult, allocator: NeverFailingAllocator, other: *AutocompleteResult) void {
		for(other.suggestions.items) |message| {
			self.suggestions.append(allocator, message);
		}
		other.suggestions.clearAndFree(allocator);
	}

	pub fn deinit(self: AutocompleteResult, allocator: NeverFailingAllocator) void {
		for(self.suggestions.items) |item| {
			allocator.free(item);
		}
		self.suggestions.deinit(allocator);
	}
};

pub fn BiomeId(comptime checkExists: bool) type {
	return struct {
		const Self = @This();

		id: []const u8,

		pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListUnmanaged(u8)) error{ParseError}!Self {
			if(checkExists and !main.server.terrain.biomes.biomesById.contains(arg)) {
				failWithMessage(allocator, errorMessage, "Biome \"{s}\" passed for <{s}> does not exist", .{arg, name});
				return error.ParseError;
			}
			return .{.id = arg};
		}

		pub fn autocomplete(allocator: NeverFailingAllocator, arg: []const u8) AutocompleteResult {
			var result: AutocompleteResult = .{};
			var iterator = main.server.terrain.biomes.biomesById.keyIterator();
			while(iterator.next()) |biomeId| {
				const id = biomeId.*;
				if(!std.mem.startsWith(u8, id, arg)) continue;
				if(id.len == arg.len) continue;
				result.suggestions.append(allocator, allocator.dupe(u8, id[arg.len..]));
			}
			return result;
		}
	};
}

const Test = struct {
	var testingAllocator = main.heap.ErrorHandlingAllocator.init(std.testing.allocator);
	var allocator = testingAllocator.allocator();

	const OnlyX = Parser(struct {x: f64}, .{.commandName = ""});

	const @"float int BiomeId" = Parser(struct {
		x: f32,
		y: u64,
		biome: BiomeId(false),
	}, .{.commandName = ""});

	const @"Union X or XY" = Parser(union(enum) {
		x: struct {x: f64},
		xy: struct {x: f64, y: f64},
	}, .{.commandName = ""});

	const @"subCommands foo or bar" = Parser(union(enum) {
		foo: struct {cmd: enum(u1) {foo}, x: f64},
		bar: struct {cmd: enum(u1) {bar}, x: f64, y: f64},
	}, .{.commandName = ""});
};

test "float" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.OnlyX.parse(Test.allocator, "33.0", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.x == 33.0);
}

test "float negative" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.OnlyX.parse(Test.allocator, "foo", &errors);

	try std.testing.expect(result == null);
	try std.testing.expect(errors.items.len != 0);
}

test "enum" {
	const ArgParser = Parser(struct {
		cmd: enum(u1) {foo},
	}, .{.commandName = "c"});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "foo", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.cmd == .foo);
}

test "float int float" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: f32,
	}, .{.commandName = ""});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "33.0 154 -5654.0", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.x == 33.0);
	try std.testing.expect(result.?.y == 154);
	try std.testing.expect(result.?.z == -5654.0);
}

test "float int optional float missing" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: ?f32,
	}, .{.commandName = ""});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "33.0 154", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.x == 33.0);
	try std.testing.expect(result.?.y == 154);
	try std.testing.expect(result.?.z == null);
}

test "float optional int biome id missing" {
	const ArgParser = Parser(struct {
		x: f64,
		y: ?i32,
		z: BiomeId(false),
	}, .{.commandName = ""});

	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "33.0 cubyz:foo", &errors);

	try std.testing.expect(result == null);
	try std.testing.expect(errors.items.len != 0);
	@panic(errors.items);
	// try std.testing.expect(errors.items.len == 0);
	// try std.testing.expect(result != null);

	// try std.testing.expect(result.?.x == 33.0);
	// try std.testing.expect(result.?.y == null);
	// try std.testing.expectEqualStrings("cubyz:foo", result.?.z.id);
}

test "float int BiomeId" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"float int BiomeId".parse(Test.allocator, "33.0 154 cubyz:foo", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.x == 33.0);
	try std.testing.expect(result.?.y == 154);
	try std.testing.expectEqualStrings("cubyz:foo", result.?.biome.id);
}

test "float int BiomeId negative shuffled" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"float int BiomeId".parse(Test.allocator, "33.0 cubyz:foo 154", &errors);

	try std.testing.expect(result == null);
	try std.testing.expect(errors.items.len != 0);
}

test "x or xy case x" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "0.9", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.x.x == 0.9);
}

test "x or xy case xy" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "0.9 1.0", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.xy.x == 0.9);
	try std.testing.expect(result.?.xy.y == 1.0);
}

test "x or xy negative empty" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "", &errors);

	try std.testing.expect(errors.items.len != 0);
	try std.testing.expect(result == null);
}

test "x or xy negative too much" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "1.0 3.0 5.0", &errors);

	try std.testing.expect(errors.items.len != 0);
	try std.testing.expect(result == null);
}

test "subCommands foo" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"subCommands foo or bar".parse(Test.allocator, "foo 1.0", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.foo.cmd == .foo);
	try std.testing.expect(result.?.foo.x == 1.0);
}

test "subCommands bar" {
	var errors: ListUnmanaged(u8) = .{};
	defer errors.deinit(Test.allocator);

	const result = Test.@"subCommands foo or bar".parse(Test.allocator, "bar 2.0 3.0", &errors);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result != null);
	try std.testing.expect(result.?.bar.cmd == .bar);
	try std.testing.expect(result.?.bar.x == 2.0);
	try std.testing.expect(result.?.bar.y == 3.0);
}
