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
			var nextArgument: ?[]const u8 = null;

			var tempErrorMessage: ListUnmanaged(u8) = .{};
			defer tempErrorMessage.deinit(allocator);

			inline for(s.fields, 1..) |field, count| {
				if(nextArgument == null) {
					nextArgument = split.next();
				}

				@field(result, field.name) = resolveArgument(field.type, allocator, field.name[0..], nextArgument, &tempErrorMessage) orelse {
					if(@typeInfo(field.type) != .optional or count == s.fields.len) {
						errorMessage.appendSlice(allocator, tempErrorMessage.items);
						return null;
					} else {
						@field(result, field.name) = null;
						continue;
					}
				};
				nextArgument = null;
			}

			if(split.next() != null) {
				failWithMessage(allocator, errorMessage, "Too many arguments for command, expected {}", .{s.fields.len});
				return null;
			}

			return result;
		}

		fn resolveArgument(comptime Field: type, allocator: NeverFailingAllocator, name: []const u8, nextArgument: ?[]const u8, errorMessage: *ListUnmanaged(u8)) ?Field {
			switch(@typeInfo(Field)) {
				inline .optional => |optionalInfo| {
					if(nextArgument == null) return null;
					return resolveArgument(optionalInfo.child, allocator, name, nextArgument, errorMessage);
				},
				inline .@"struct" => {
					const arg = nextArgument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return null;
					};
					if(!@hasDecl(Field, "parse")) @compileError("Struct must have a parse function");
					return @field(Field, "parse")(allocator, name, arg, errorMessage);
				},
				inline .@"enum" => {
					const arg = nextArgument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return null;
					};
					return std.meta.stringToEnum(Field, arg) orelse {
						failWithMessage(allocator, errorMessage, "Expected one of {} for <{s}>, found \"{s}\"", .{.{std.meta.fieldNames(Field)}, name, arg});

						return null;
					};
				},
				inline .float => |floatInfo| return {
					const arg = nextArgument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return null;
					};
					return std.fmt.parseFloat(std.meta.Float(floatInfo.bits), arg) catch {
						failWithMessage(allocator, errorMessage, "Expected a number for <{s}>, found \"{s}\"", .{name, arg});
						return null;
					};
				},
				inline .int => |intInfo| {
					const arg = nextArgument orelse {
						failWithMessage(allocator, errorMessage, missingArgumentMessage, .{name});
						return null;
					};
					return std.fmt.parseInt(std.meta.Int(intInfo.signedness, intInfo.bits), arg, 0) catch {
						failWithMessage(allocator, errorMessage, "Expected an integer for <{s}>, found \"{s}\"", .{name, arg});
						return null;
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

		pub fn parse(allocator: NeverFailingAllocator, name: []const u8, arg: []const u8, errorMessage: *ListUnmanaged(u8)) ?Self {
			if(checkExists and !main.server.terrain.biomes.biomesById.contains(arg)) {
				failWithMessage(allocator, errorMessage, "Biome \"{s}\" passed for <{s}> does not exist", .{arg, name});
				return null;
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
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.OnlyX.parse(Test.allocator, "33.0", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
}

test "float negative" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.OnlyX.parse(Test.allocator, "foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == error.ParsingError);
	try std.testing.expect(errors.items.len != 0);
}

test "enum" {
	const ArgParser = Parser(struct {
		cmd: enum(u1) {foo},
	}, .{.commandName = "c"});

	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "foo", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.cmd == .foo);
}

test "float int float" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: f32,
	}, .{.commandName = ""});

	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "33.0 154 -5654.0", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expect(result.success.z == -5654.0);
}

test "float int optional float missing" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: ?f32,
	}, .{.commandName = ""});

	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "33.0 154", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expect(result.success.z == null);
}

test "float optional int biome id missing" {
	const ArgParser = Parser(struct {
		x: f64,
		y: ?i32,
		z: BiomeId(false),
	}, .{.commandName = ""});

	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = ArgParser.parse(Test.allocator, "33.0 cubyz:foo", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);

	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == null);
	try std.testing.expectEqualStrings("cubyz:foo", result.success.z.id);
}

test "float int BiomeId" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"float int BiomeId".parse(Test.allocator, "33.0 154 cubyz:foo", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expectEqualStrings("cubyz:foo", result.success.biome.id);
}

test "float int BiomeId negative shuffled" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"float int BiomeId".parse(Test.allocator, "33.0 cubyz:foo 154", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == error.ParsingError);
	try std.testing.expect(errors.items.len != 0);
}

test "x or xy case x" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "0.9", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x.x == 0.9);
}

test "x or xy case xy" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "0.9 1.0", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.xy.x == 0.9);
	try std.testing.expect(result.success.xy.y == 1.0);
}

test "x or xy negative empty" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len != 0);
	try std.testing.expect(result == error.ParsingError);
}

test "x or xy negative too much" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"Union X or XY".parse(Test.allocator, "1.0 3.0 5.0", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len != 0);
	try std.testing.expect(result == error.ParsingError);
}

test "subCommands foo" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"subCommands foo or bar".parse(Test.allocator, "foo 1.0", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.foo.cmd == .foo);
	try std.testing.expect(result.success.foo.x == 1.0);
}

test "subCommands bar" {
	const errors = ListUnmanaged(u8).init(Test.allocator);
	defer errors.deinit(Test.allocator);

	const result = Test.@"subCommands foo or bar".parse(Test.allocator, "bar 2.0 3.0", &errors);
	defer result.deinit(Test.allocator);

	try std.testing.expect(errors.items.len == 0);
	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.bar.cmd == .bar);
	try std.testing.expect(result.success.bar.x == 2.0);
	try std.testing.expect(result.success.bar.y == 3.0);
}
