const std = @import("std");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ListUnmanaged = main.ListUnmanaged;

pub fn Parser(comptime T: type) type {
	return struct {
		const Self = @This();
		pub const Args = T;

		pub fn parse(allocator: NeverFailingAllocator, args: []const u8) ParseResult(T) {
			return resolve(false, allocator, args);
		}

		pub fn autocomplete(allocator: NeverFailingAllocator, args: []const u8) AutocompleteResult {
			return resolve(true, allocator, args);
		}

		pub fn resolve(comptime doAutocomplete: bool, allocator: NeverFailingAllocator, args: []const u8) if(doAutocomplete) AutocompleteResult else ParseResult(T) {
			switch(@typeInfo(T)) {
				inline .@"struct" => |s| {
					return resolveStruct(doAutocomplete, s, allocator, args);
				},
				inline .@"union" => |u| {
					if(u.tag_type == null) @compileError("Union must have a tag type");
					return if(doAutocomplete) autocompleteUnion(u, allocator, args) else parseUnion(u, allocator, args);
				},
				else => @compileError("Only structs and unions are supported"),
			}
		}

		fn resolveStruct(comptime doAutocomplete: bool, comptime s: std.builtin.Type.Struct, allocator: NeverFailingAllocator, args: []const u8) if(doAutocomplete) AutocompleteResult else ParseResult(T) {
			var result: T = undefined;

			var split = std.mem.splitScalar(u8, args, ' ');
			var offset: usize = 0;
			var count: usize = 0;

			inline for(s.fields) |field| {
				const _arg = split.next();
				defer {
					if(_arg) |arg| offset += arg.len + 1;
					count += 1;
				}

				@field(result, field.name) = resolveArgument(field.type, _arg) catch |err| {
					const message = std.fmt.allocPrint(allocator.allocator, "Failed to parse argument {} due to error {s} (offset {})", .{count, @errorName(err), offset}) catch unreachable;
					return .initWithFailure(allocator, message);
				};
			}

			if(split.next() != null) {
				return .initWithFailure(allocator, std.fmt.allocPrint(allocator.allocator, "Too many arguments for command, expected {}", .{count}) catch unreachable);
			}

			return .{.success = result};
		}

		fn resolveArgument(comptime Field: type, _arg: ?[]const u8) !Field {
			switch(@typeInfo(Field)) {
				inline .optional => |optionalInfo| {
					if(_arg == null) return null;
					return try resolveArgument(optionalInfo.child, _arg);
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

		fn autocompleteArgument(comptime Field: type, allocator: NeverFailingAllocator, _arg: ?[]const u8) AutocompleteResult {
			const arg = _arg orelse return .{};
			switch(@typeInfo(Field)) {
				inline .@"struct" => {
					if(!@hasDecl(Field, "autocomplete")) @compileError("Struct must have a parse function");
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

		fn parseUnion(comptime u: std.builtin.Type.Union, allocator: NeverFailingAllocator, args: []const u8) ParseResult(T) {
			var result: ParseResult(T) = .initWithFailure(allocator, allocator.dupe(u8, "Provided argument list didn't match any of the valid alternative interpretations of command argument list."));

			inline for(u.fields) |field| {
				var fieldResult = Parser(field.type).resolve(false, allocator, args);
				defer fieldResult.deinit(allocator);

				if(fieldResult == .success) {
					result.deinit(allocator);
					return .{.success = @unionInit(T, field.name, fieldResult.success)};
				}
				result.failure.messages.append(allocator, std.fmt.allocPrint(allocator.allocator, "\n{s}", .{field.name}) catch unreachable);
				result.failure.takeMessages(allocator, &fieldResult.failure);
			}

			return result;
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

pub fn ParseResult(comptime SuccessT: type) type {
	return union(enum) {
		const Self = @This();

		failure: struct {
			const Failure = @This();

			messages: ListUnmanaged([]const u8),

			pub fn takeMessages(self: *Failure, allocator: NeverFailingAllocator, other: *Failure) void {
				for(other.messages.items) |message| {
					self.messages.append(allocator, message);
				}
				other.messages.clearAndFree(allocator);
			}

			pub fn deinit(self: Failure, allocator: NeverFailingAllocator) void {
				for(self.messages.items) |message| {
					allocator.free(message);
				}
				self.messages.deinit(allocator);
			}
		},
		success: SuccessT,

		pub fn initWithFailure(allocator: NeverFailingAllocator, message: []const u8) Self {
			var self: Self = .{.failure = .{.messages = .initCapacity(allocator, 1)}};
			self.failure.messages.append(allocator, message);
			return self;
		}

		pub fn deinit(self: Self, allocator: NeverFailingAllocator) void {
			if(self == .failure) {
				self.failure.deinit(allocator);
			}
		}
	};
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

// TODO: This could check if biome ID is valid, either always or with generic flag.
pub const BiomeId = struct {
	id: []const u8,

	pub fn parse(arg: []const u8) !BiomeId {
		if(!main.server.terrain.biomes.biomesById.contains(arg)) return error.InvalidBiomeId;
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

const Test = struct {
	var testingAllocator = main.heap.ErrorHandlingAllocator.init(std.testing.allocator);
	var allocator = testingAllocator.allocator();

	const OnlyX = Parser(struct {x: f64});

	const @"float int BiomeId" = Parser(struct {
		x: f32,
		y: u64,
		biome: BiomeId,
	});

	const @"Union X or XY" = Parser(union(enum) {
		x: struct {x: f64},
		xy: struct {x: f64, y: f64},
	});

	const @"subCommands foo or bar" = Parser(union(enum) {
		foo: struct {cmd: enum(u1) {foo}, x: f64},
		bar: struct {cmd: enum(u1) {bar}, x: f64, y: f64},
	});
};

test "float" {
	const result = Test.OnlyX.parse(Test.allocator, "33.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
}

test "float negative" {
	const result = Test.OnlyX.parse(Test.allocator, "foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "enum" {
	const ArgParser = Parser(struct {
		cmd: enum(u1) {foo},
	});

	const result = ArgParser.parse(Test.allocator, "foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.cmd == .foo);
}

test "float int float" {
	const ArgParser = Parser(struct {
		x: f64,
		y: i32,
		z: f32,
	});

	const result = ArgParser.parse(Test.allocator, "33.0 154 -5654.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expect(result.success.z == -5654.0);
}

test "float int BiomeId" {
	const result = Test.@"float int BiomeId".parse(Test.allocator, "33.0 154 cubyz:foo");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x == 33.0);
	try std.testing.expect(result.success.y == 154);
	try std.testing.expectEqualStrings("cubyz:foo", result.success.biome.id);
}

test "float int BiomeId negative shuffled" {
	const result = Test.@"float int BiomeId".parse(Test.allocator, "33.0 cubyz:foo 154");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "x or xy case x" {
	const result = Test.@"Union X or XY".parse(Test.allocator, "0.9");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.x.x == 0.9);
}

test "x or xy case xy" {
	const result = Test.@"Union X or XY".parse(Test.allocator, "0.9 1.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.xy.x == 0.9);
	try std.testing.expect(result.success.xy.y == 1.0);
}

test "x or xy negative empty" {
	const result = Test.@"Union X or XY".parse(Test.allocator, "");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "x or xy negative too much" {
	const result = Test.@"Union X or XY".parse(Test.allocator, "1.0 3.0 5.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .failure);
}

test "subCommands foo" {
	const result = Test.@"subCommands foo or bar".parse(Test.allocator, "foo 1.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.foo.cmd == .foo);
	try std.testing.expect(result.success.foo.x == 1.0);
}

test "subCommands bar" {
	const result = Test.@"subCommands foo or bar".parse(Test.allocator, "bar 2.0 3.0");
	defer result.deinit(Test.allocator);

	try std.testing.expect(result == .success);
	try std.testing.expect(result.success.bar.cmd == .bar);
	try std.testing.expect(result.success.bar.x == 2.0);
	try std.testing.expect(result.success.bar.y == 3.0);
}
