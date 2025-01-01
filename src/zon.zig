const std = @import("std");

const main = @import("main.zig");
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const List = main.List;

pub const ZonElement = union(enum) { // MARK: Zon
	int: i64,
	float: f64,
	string: []const u8,
	stringOwned: []const u8,
	bool: bool,
	null: void,
	array: *List(ZonElement),
	object: *std.StringHashMap(ZonElement),

	pub fn initObject(allocator: NeverFailingAllocator) ZonElement {
		const map = allocator.create(std.StringHashMap(ZonElement));
		map.* = .init(allocator.allocator);
		return .{.object = map};
	}

	pub fn initArray(allocator: NeverFailingAllocator) ZonElement {
		const list = allocator.create(List(ZonElement));
		list.* = .init(allocator);
		return .{.array = list};
	}

	pub fn getAtIndex(self: *const ZonElement, comptime _type: type, index: usize, replacement: _type) _type {
		if(self.* != .array) {
			return replacement;
		} else {
			if(index < self.array.items.len) {
				return self.array.items[index].as(_type, replacement);
			} else {
				return replacement;
			}
		}
	}

	pub fn getChildAtIndex(self: *const ZonElement, index: usize) ZonElement {
		if(self.* != .array) {
			return .null;
		} else {
			if(index < self.array.items.len) {
				return self.array.items[index];
			} else {
				return .null;
			}
		}
	}

	pub fn get(self: *const ZonElement, comptime _type: type, key: []const u8, replacement: _type) _type {
		if(self.* != .object) {
			return replacement;
		} else {
			if(self.object.get(key)) |elem| {
				return elem.as(_type, replacement);
			} else {
				return replacement;
			}
		}
	}

	pub fn getChild(self: *const ZonElement, key: []const u8) ZonElement {
		if(self.* != .object) {
			return .null;
		} else {
			if(self.object.get(key)) |elem| {
				return elem;
			} else {
				return .null;
			}
		}
	}

	pub fn as(self: *const ZonElement, comptime T: type, replacement: T) T {
		comptime var typeInfo : std.builtin.Type = @typeInfo(T);
		comptime var innerType = T;
		inline while(typeInfo == .optional) {
			innerType = typeInfo.optional.child;
			typeInfo = @typeInfo(innerType);
		}
		switch(typeInfo) {
			.int => {
				switch(self.*) {
					.int => return std.math.cast(innerType, self.int) orelse replacement,
					.float => return std.math.lossyCast(innerType, std.math.round(self.float)),
					else => return replacement,
				}
			},
			.float => {
				switch(self.*) {
					.int => return @floatFromInt(self.int),
					.float => return @floatCast(self.float),
					else => return replacement,
				}
			},
			.vector => {
				const len = typeInfo.vector.len;
				const elems = self.toSlice();
				if(elems.len != len) return replacement;
				var result: innerType = undefined;
				if(innerType == T) result = replacement;
				inline for(0..len) |i| {
					if(innerType == T) {
						result[i] = elems[i].as(typeInfo.vector.child, result[i]);
					} else {
						result[i] = elems[i].as(?typeInfo.vector.child, null) orelse return replacement;
					}
				}
				return result;
			},
			else => {
				switch(innerType) {
					[]const u8 => {
						switch(self.*) {
							.string => return self.string,
							.stringOwned => return self.stringOwned,
							else => return replacement,
						}
					},
					bool => {
						switch(self.*) {
							.bool => return self.bool,
							else => return replacement,
						}
					},
					else => {
						@compileError("Unsupported type '" ++ @typeName(T) ++ "'.");
					}
				}
			},
		}
	}

	fn createElementFromRandomType(value: anytype, allocator: std.mem.Allocator) ZonElement {
		switch(@typeInfo(@TypeOf(value))) {
			.void => return .null,
			.null => return .null,
			.bool => return .{.bool = value},
			.int, .comptime_int => return .{.int = @intCast(value)},
			.float, .comptime_float => return .{.float = @floatCast(value)},
			.@"union" => {
				if(@TypeOf(value) == ZonElement) {
					return value;
				} else {
					@compileError("Unknown value type.");
				}
			},
			.pointer => |ptr| {
				if(ptr.child == u8 and ptr.size == .Slice) {
					return .{.string = value};
				} else {
					const childInfo = @typeInfo(ptr.child);
					if(ptr.size == .One and childInfo == .array and childInfo.array.child == u8) {
						return .{.string = value};
					} else {
						@compileError("Unknown value type.");
					}
				}
			},
			.optional => {
				if(value) |val| {
					return createElementFromRandomType(val, allocator);
				} else {
					return .null;
				}
			},
			.vector => {
				const len = @typeInfo(@TypeOf(value)).vector.len;
				const result = initArray(main.utils.NeverFailingAllocator{.allocator = allocator, .IAssertThatTheProvidedAllocatorCantFail = {}});
				result.array.ensureCapacity(len);
				inline for(0..len) |i| {
					result.array.appendAssumeCapacity(createElementFromRandomType(value[i], allocator));
				}
				return result;
			},
			else => {
				if(@TypeOf(value) == ZonElement) {
					return value;
				} else {
					@compileError("Unknown value type.");
				}
			},
		}
	}

	pub fn put(self: *const ZonElement, key: []const u8, value: anytype) void {
		const result = createElementFromRandomType(value, self.object.allocator);
		self.object.put(self.object.allocator.dupe(u8, key) catch unreachable, result) catch unreachable;
	}

	pub fn putOwnedString(self: *const ZonElement, key: []const u8, value: []const u8) void {
		const result = ZonElement{.stringOwned = self.object.allocator.dupe(u8, value) catch unreachable};
		self.object.put(self.object.allocator.dupe(u8, key) catch unreachable, result) catch unreachable;
	}

	pub fn toSlice(self: *const ZonElement) []ZonElement {
		switch(self.*) {
			.array => |arr| {
				return arr.items;
			},
			else => return &.{},
		}
	}

	pub fn deinit(self: *const ZonElement, allocator: NeverFailingAllocator) void {
		switch(self.*) {
			.int, .float, .bool, .null, .string => return,
			.stringOwned => {
				allocator.free(self.stringOwned);
			},
			.array => {
				for(self.array.items) |*elem| {
					elem.deinit(allocator);
				}
				self.array.clearAndFree();
				allocator.destroy(self.array);
			},
			.object => {
				var iterator = self.object.iterator();
				while(true) {
					const elem = iterator.next() orelse break;
					allocator.free(elem.key_ptr.*);
					elem.value_ptr.deinit(allocator);
				}
				self.object.clearAndFree();
				allocator.destroy(self.object);
			},
		}
	}

	pub fn isNull(self: *const ZonElement) bool {
		return self.* == .null;
	}

	fn escape(list: *List(u8), string: []const u8) void {
		for(string) |char| {
			switch(char) {
				'\\' => list.appendSlice("\\\\"),
				'\n' => list.appendSlice("\\n"),
				'\"' => list.appendSlice("\\\""),
				'\t' => list.appendSlice("\\t"),
				else => list.append(char),
			}
		}
	}
	fn writeTabs(list: *List(u8), tabs: u32) void {
		for(0..tabs) |_| {
			list.append('\t');
		}
	}
	fn isValidIdentifierName(str: []const u8) bool {
		if(str.len == 0) return false;
		if(!std.ascii.isAlphabetic(str[0]) and str[0] != '_') return false;
		for(str[1..]) |c| {
			if(!std.ascii.isAlphanumeric(c) and c != '_') return false;
		}
		return true;
	}
	fn recurseToString(zon: ZonElement, list: *List(u8), tabs: u32, comptime visualCharacters: bool) void {
		switch(zon) {
			.int => |value| {
				std.fmt.formatInt(value, 10, .lower, .{}, list.writer()) catch unreachable;
			},
			.float => |value| {
				var buf: [std.fmt.format_float.bufferSize(.scientific, @TypeOf(value))]u8 = undefined;
				list.appendSlice(std.fmt.format_float.formatFloat(&buf, value, .{.mode = .scientific}) catch unreachable);
			},
			.bool => |value| {
				if(value) {
					list.appendSlice("true");
				} else {
					list.appendSlice("false");
				}
			},
			.null => {
				list.appendSlice("null");
			},
			.string, .stringOwned => |value| {
				if(isValidIdentifierName(value)) {
					// Can use an enum literal:
					list.append('.');
					list.appendSlice(value);
				} else {
					list.append('\"');
					escape(list, value);
					list.append('\"');
				}
			},
			.array => |array| {
				if(visualCharacters) list.append('.');
				list.append('{');
				for(array.items, 0..) |elem, i| {
					if(i != 0) {
						list.append(',');
					}
					if(visualCharacters) list.append('\n');
					if(visualCharacters) writeTabs(list, tabs + 1);
					recurseToString(elem, list, tabs + 1, visualCharacters);
				}
				if(visualCharacters and array.items.len != 0) list.append(',');
				if(visualCharacters) list.append('\n');
				if(visualCharacters) writeTabs(list, tabs);
				list.append('}');
			},
			.object => |obj| {
				if(visualCharacters) list.append('.');
				list.append('{');
				var iterator = obj.iterator();
				var first: bool = true;
				while(true) {
					const elem = iterator.next() orelse break;
					if(!first) {
						list.append(',');
					}
					if(visualCharacters) list.append('\n');
					if(visualCharacters) writeTabs(list, tabs + 1);
					if(isValidIdentifierName(elem.key_ptr.*)) {
						if(visualCharacters) list.append('.');
						list.appendSlice(elem.key_ptr.*);
					} else {
						if(visualCharacters) list.append('@');
						list.append('\"');
						escape(list, elem.key_ptr.*);
						list.append('\"');
					}
					if(visualCharacters) list.append(' ');
					list.append('=');
					if(visualCharacters) list.append(' ');

					recurseToString(elem.value_ptr.*, list, tabs + 1, visualCharacters);
					first = false;
				}
				if(visualCharacters and !first) list.append(',');
				if(visualCharacters) list.append('\n');
				if(visualCharacters) writeTabs(list, tabs);
				list.append('}');
			},
		}
	}
	pub fn toString(zon: ZonElement, allocator: NeverFailingAllocator) []const u8 {
		var string = List(u8).init(allocator);
		recurseToString(zon, &string, 0, true);
		return string.toOwnedSlice();
	}

	/// Ignores all the visual characters(spaces, tabs and newlines) and allows adding a custom prefix(which is for example required by networking).
	pub fn toStringEfficient(zon: ZonElement, allocator: NeverFailingAllocator, prefix: []const u8) []const u8 {
		var string = List(u8).init(allocator);
		string.appendSlice(prefix);
		recurseToString(zon, &string, 0, false);
		return string.toOwnedSlice();
	}

	pub fn parseFromString(allocator: NeverFailingAllocator, string: []const u8) ZonElement {
		var index: u32 = 0;
		Parser.skipWhitespaces(string, &index);
		return Parser.parseElement(allocator, string, &index);
	}
};

const Parser = struct { // MARK: Parser
	/// All whitespaces from unicode 14.
	const whitespaces = [_][]const u8 {"\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}", "\u{0020}", "\u{0085}", "\u{00A0}", "\u{1680}", "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}"};

	fn skipWhitespaces(chars: []const u8, index: *u32) void {
		outerLoop:
		while(index.* < chars.len) {
			whitespaceLoop:
			for(whitespaces) |whitespace| {
				for(whitespace, 0..) |char, i| {
					if(char != chars[index.* + i]) {
						continue :whitespaceLoop;
					}
				}
				index.* += @intCast(whitespace.len);
				continue :outerLoop;
			}
			// Next character is no whitespace.
			return;
		}
	}

	/// Assumes that the region starts with a number character ('+', '-', '.' or a digit).
	fn parseNumber(chars: []const u8, index: *u32) ZonElement {
		var sign: i2 = 1;
		if(chars[index.*] == '-') {
			sign = -1;
			index.* += 1;
		} else if(chars[index.*] == '+') {
			index.* += 1;
		}
		var intPart: i64 = 0;
		if(index.*+1 < chars.len and chars[index.*] == '0' and chars[index.*+1] == 'x') {
			// Parse hex int
			index.* += 2;
			while(index.* < chars.len): (index.* += 1) {
				switch(chars[index.*]) {
					'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
						intPart = (chars[index.*] - '0') +% intPart*%16;
					},
					'a', 'b', 'c', 'd', 'e', 'f' => {
						intPart = (chars[index.*] - 'a' + 10) +% intPart*%16;
					},
					'A', 'B', 'C', 'D', 'E', 'F' => {
						intPart = (chars[index.*] - 'A' + 10) +% intPart*%16;
					},
					else => {
						break;
					}
				}
			}
			return .{.int = sign*intPart};
		}
		while(index.* < chars.len): (index.* += 1) {
			switch(chars[index.*]) {
				'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
					intPart = (chars[index.*] - '0') +% intPart*%10;
				},
				else => {
					break;
				}
			}
		}
		if(index.* >= chars.len or (chars[index.*] != '.' and chars[index.*] != 'e' and chars[index.*] != 'E')) { // This is an int
			return .{.int = sign*intPart};
		}
		// So this is a float apparently.

		var floatPart: f64 = 0;
		var currentFactor: f64 = 0.1;
		if(chars[index.*] == '.') {
			index.* += 1;
			while(index.* < chars.len): (index.* += 1) {
				switch(chars[index.*]) {
					'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
						floatPart += @as(f64, @floatFromInt(chars[index.*] - '0'))*currentFactor;
						currentFactor *= 0.1;
					},
					else => {
						break;
					}
				}
			}
		}
		var exponent: i64 = 0;
		var exponentSign: i2 = 1;
		if(index.* < chars.len and (chars[index.*] == 'e' or chars[index.*] == 'E')) {
			index.* += 1;
			if(index.* < chars.len and chars[index.*] == '-') {
				exponentSign = -1;
				index.* += 1;
			} else if(index.* < chars.len and chars[index.*] == '+') {
				index.* += 1;
			}
			while(index.* < chars.len): (index.* += 1) {
				switch(chars[index.*]) {
					'0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
						exponent = (chars[index.*] - '0') +% exponent*%10;
					},
					else => {
						break;
					}
				}
			}
		}
		return .{.float = @as(f64, @floatFromInt(sign))*(@as(f64, @floatFromInt(intPart)) + floatPart)*std.math.pow(f64, 10, @as(f64, @floatFromInt(exponentSign*exponent)))};
	}

	fn parseString(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) []const u8 {
		var builder = List(u8).init(allocator);
		while(index.* < chars.len): (index.* += 1) {
			if(chars[index.*] == '\"') {
				index.* += 1;
				break;
			} else if(chars[index.*] == '\\') {
				index.* += 1;
				if(index.* >= chars.len)
					break;
				switch(chars[index.*]) {
					't' => {
						builder.append('\t');
					},
					'n' => {
						builder.append('\n');
					},
					'r' => {
						builder.append('\r');
					},
					else => {
						builder.append(chars[index.*]);
					}
				}
			} else {
				builder.append(chars[index.*]);
			}
		}
		return builder.toOwnedSlice();
	}

	fn parseIdentifierOrStringOrEnumLiteral(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) []const u8 {
		var builder = List(u8).init(allocator);
		if(index.* == chars.len) return &.{};
		if(chars[index.*] == '@') {
			index.* += 1;
		}
		if(index.* == chars.len) return &.{};
		if(chars[index.*] == '"') {
			index.* += 1;
			return parseString(allocator, chars, index);
		}
		while(index.* < chars.len): (index.* += 1) {
			switch(chars[index.*]) {
				'a'...'z', 'A'...'Z', '0'...'9', '_' => |c| builder.append(c),
				else => break,
			}
		}
		return builder.toOwnedSlice();
	}

	fn parseArray(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) ZonElement {
		const list = allocator.create(List(ZonElement));
		list.* = .init(allocator);
		while(index.* < chars.len) {
			skipWhitespaces(chars, index);
			if(index.* >= chars.len) break;
			if(chars[index.*] == '}') {
				index.* += 1;
				return .{.array = list};
			}
			list.append(parseElement(allocator, chars, index));
			skipWhitespaces(chars, index);
			if(index.* < chars.len and chars[index.*] == ',') {
				index.* += 1;
			}
		}
		printError(chars, index.*, "Unexpected end of file in array parsing.");
		return .{.array=list};
	}

	fn parseObject(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) ZonElement {
		const map = allocator.create(std.StringHashMap(ZonElement));
		map.* = .init(allocator.allocator);
		while(index.* < chars.len) {
			skipWhitespaces(chars, index);
			if(index.* >= chars.len) break;
			if(chars[index.*] == '}') {
				index.* += 1;
				return .{.object = map};
			}
			if(chars[index.*] == '.') index.* += 1; // Just ignoring the dot in front of identifiers, the file might as well not have for all I care.
			const key: []const u8 = parseIdentifierOrStringOrEnumLiteral(allocator, chars, index);
			skipWhitespaces(chars, index);
			while(index.* < chars.len and chars[index.*] != '=') {
				printError(chars, index.*, "Unexpected character in object parsing, expected '='.");
				index.* += 1;
			}
			index.* += 1;
			skipWhitespaces(chars, index);
			const value: ZonElement = parseElement(allocator, chars, index);
			if(map.fetchPut(key, value) catch unreachable) |old| {
				printError(chars, index.*, "Duplicate key.");
				allocator.free(old.key);
				old.value.deinit(allocator);
			}
			skipWhitespaces(chars, index);
			if(index.* < chars.len and chars[index.*] == ',') {
				index.* += 1;
			}
		}
		printError(chars, index.*, "Unexpected end of file in object parsing.");
		return .{.object = map};
	}

	fn printError(chars: []const u8, index: u32, msg: []const u8) void {
		var lineNumber: u32 = 1;
		var lineStart: u32 = 0;
		var i: u32 = 0;
		while(i < index and i < chars.len): (i += 1) {
			if(chars[i] == '\n') {
				lineNumber += 1;
				lineStart = i;
			}
		}
		while(i < chars.len): (i += 1) {
			if(chars[i] == '\n') {
				break;
			}
		}
		const lineEnd: u32 = i;
		std.log.warn("Error in line {}: {s}", .{lineNumber, msg});
		std.log.warn("{s}", .{chars[lineStart..lineEnd]});
		// Mark the position:
		var message: [512]u8 = undefined;
		i = lineStart;
		var outputI: u32 = 0;
		while(i < index and i < chars.len): (i += 1) {
			if((chars[i] & 128) != 0 and (chars[i] & 64) == 0) {
				// Not the start of a utf8 character
				continue;
			}
			if(chars[i] == '\t') {
				message[outputI] = '\t';
			} else {
				message[outputI] = ' ';
			}
			outputI += 1;
			if(outputI >= message.len) {
				return; // 512 characters is too long for this output to be helpful.
			}
		}
		message[outputI] = '^';
		outputI += 1;
		std.log.warn("{s}", .{message[0..outputI]});
	}

	/// Assumes that the region starts with a non-space character.
	fn parseElement(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) ZonElement {
		if(index.* >= chars.len) {
			printError(chars, index.*, "Unexpected end of file.");
			return .null;
		}
		sw: switch(chars[index.*]) {
			'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '-' => {
				return parseNumber(chars, index);
			},
			't' => { // Value can only be true.
				if(index.* + 3 >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'r' or chars[index.*+2] != 'u' or chars[index.*+3] != 'e') {
					printError(chars, index.*, "Unknown expression, interpreting as true.");
				}
				index.* += 4;
				return .{.bool = true};
			},
			'f' => { // Value can only be false.
				if(index.* + 4 >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'a' or chars[index.*+2] != 'l' or chars[index.*+3] != 's' or chars[index.*+4] != 'e') {
					printError(chars, index.*, "Unknown expression, interpreting as false.");
				}
				index.* += 5;
				return .{.bool = false};
			},
			'n' => { // Value can only be null.
				if(index.* + 3 >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'u' or chars[index.*+2] != 'l' or chars[index.*+3] != 'l') {
					printError(chars, index.*, "Unknown expression, interpreting as null.");
				}
				index.* += 4;
				return .{.null = {}};
			},
			'\"' => {
				index.* += 1;
				return .{.stringOwned = parseString(allocator, chars, index)};
			},
			'.' => {
				index.* += 1;
				if(index.* >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
					return .null;
				}
				if(chars[index.*] == '{') continue :sw '{';
				if(std.ascii.isDigit(chars[index.*])) {
					index.* -= 1;
					return parseNumber(chars, index);
				}
				return .{.stringOwned = parseIdentifierOrStringOrEnumLiteral(allocator, chars, index)};
			},
			'{' => {
				index.* += 1;
				skipWhitespaces(chars, index);
				var foundEqualSign: bool = false;
				var i: usize = index.*;
				while(i < chars.len) : (i += 1) {
					if(chars[i] == '"') {
						i += 1;
						while(chars[i] != '"' and i < chars.len) {
							if(chars[i] == '\\') i += 1;
							i += 1;
						}
						continue;
					}
					if(chars[i] == ',' or chars[i] == '{') break;
					if(chars[i] == '=') {
						foundEqualSign = true;
						break;
					}
				}
				if(foundEqualSign) {
					return parseObject(allocator, chars, index);
				} else {
					return parseArray(allocator, chars, index);
				}
			},
			else => {
				printError(chars, index.*, "Unexpected character.");
				index.* += 1;
				return .null;
			}
		}
	}
};



// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// MARK: Testing
// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

test "skipWhitespaces" {
	var index: u32 = 0;
	var testString: []const u8 = "  fbdn  ";
	Parser.skipWhitespaces(testString, &index);
	try std.testing.expectEqual(index, 2);
	testString = "\nĦŊ@Λħŋ";
	index = 0;
	Parser.skipWhitespaces(testString, &index);
	try std.testing.expectEqual(index, 1);
	testString = "\tβρδ→øβν";
	index = 0;
	Parser.skipWhitespaces(testString, &index);
	try std.testing.expectEqual(index, 1);
	testString = "\t  \n \t  a lot of whitespaces";
	index = 0;
	Parser.skipWhitespaces(testString, &index);
	try std.testing.expectEqual(index, 8);
	testString = " unicode whitespace";
	index = 0;
	Parser.skipWhitespaces(testString, &index);
	try std.testing.expectEqual(index, 3);
	testString = "starting     in the middle";
	index = 8;
	Parser.skipWhitespaces(testString, &index);
	try std.testing.expectEqual(index, 13);
}

test "number parsing" {
	// Integers:
	var index: u32 = 0;
	try std.testing.expectEqual(Parser.parseNumber("0", &index), ZonElement{.int = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("+0", &index), ZonElement{.int = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("abcd", &index), ZonElement{.int = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("-0+1", &index), ZonElement{.int = 0});
	index = 5;
	try std.testing.expectEqual(Parser.parseNumber(" abcd185473896", &index), ZonElement{.int = 185473896});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0xff34786056.0", &index), ZonElement{.int = 0xff34786056});
	// Floats:
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0.0", &index), ZonElement{.float = 0.0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0e10e10", &index), ZonElement{.float = 0.0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("-0.0.0", &index), ZonElement{.float = 0.0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0xabcd.0e10+-+-", &index), ZonElement{.int = 0xabcd});
	index = 0;
	try std.testing.expectApproxEqAbs(Parser.parseNumber("1.234589e10", &index).float, 1.234589e10, 1.0);
	index = 5;
	try std.testing.expectApproxEqAbs(Parser.parseNumber("_____0.0000000000234589e10abcdfe", &index).float, 0.234589, 1e-10);
}

test "element parsing" {
	var wrap = main.utils.ErrorHandlingAllocator.init(std.testing.allocator);
	const allocator = wrap.allocator();
	// Integers:
	var index: u32 = 0;
	try std.testing.expectEqual(Parser.parseElement(allocator, "0", &index), ZonElement{.int = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(allocator, "0xff34786056.0, true", &index), ZonElement{.int = 0xff34786056});
	// Floats:
	index = 10;
	try std.testing.expectEqual(Parser.parseElement(allocator, ".{.abcd = 0.0,}", &index), ZonElement{.float = 0.0});
	index = 0;
	try std.testing.expectApproxEqAbs((Parser.parseElement(allocator, "1543.234589e10", &index)).float, 1543.234589e10, 1.0);
	index = 5;
	try std.testing.expectApproxEqAbs((Parser.parseElement(allocator, "_____0.0000000000675849301354e10abcdfe", &index)).float, 0.675849301354, 1e-10);
	// Null:
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(allocator, "null", &index), ZonElement{.null={}});
	// true:
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(allocator, "true", &index), ZonElement{.bool=true});
	// false:
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(allocator, "false", &index), ZonElement{.bool=false});

	// String:
	index = 0;
	var result: ZonElement = Parser.parseElement(allocator, "\"abcd\\\"\\\\ħσ→ ↑Φ∫€ ⌬ ε→Π\"", &index);
	try std.testing.expectEqualStrings("abcd\"\\ħσ→ ↑Φ∫€ ⌬ ε→Π", result.as([]const u8, ""));
	result.deinit(allocator);
	index = 0;
	result = Parser.parseElement(allocator, "\"12345", &index);
	try std.testing.expectEqualStrings("12345", result.as([]const u8, ""));
	result.deinit(allocator);

	// Object:
	index = 0;
	result = Parser.parseElement(allocator, ".{.name = 1}", &index);
	try std.testing.expectEqual(.object, std.meta.activeTag(result));
	try std.testing.expectEqual(result.object.get("name"), ZonElement{.int = 1});
	result.deinit(allocator);
	index = 0;
	result = Parser.parseElement(allocator, ".{@\"object\"=.{},}", &index);
	try std.testing.expectEqual(.object, std.meta.activeTag(result));
	try std.testing.expectEqual(.array, std.meta.activeTag(result.object.get("object") orelse .null));
	result.deinit(allocator);
	index = 0;
	result = Parser.parseElement(allocator, ".{   .object1   =   \"\"  \n, .object2  =\t.{\n},.object3   =1.0e4\t,@\"\nobject1\"=.{},@\"\tobject1θ\"=.{},}", &index);
	try std.testing.expectEqual(.object, std.meta.activeTag(result));
	try std.testing.expectEqual(.float, std.meta.activeTag(result.object.get("object3") orelse .null));
	try std.testing.expectEqual(.stringOwned, std.meta.activeTag(result.object.get("object1") orelse .null));
	try std.testing.expectEqual(.array, std.meta.activeTag(result.object.get("\nobject1") orelse .null));
	try std.testing.expectEqual(.array, std.meta.activeTag(result.object.get("\tobject1θ") orelse .null));
	result.deinit(allocator);

	//Array:
	index = 0;
	result = Parser.parseElement(allocator, ".{.name,1}", &index);
	try std.testing.expectEqual(.array, std.meta.activeTag(result));
	try std.testing.expectEqual(.stringOwned, std.meta.activeTag(result.array.items[0]));
	try std.testing.expectEqual(ZonElement{.int=1}, result.array.items[1]);
	result.deinit(allocator);
	index = 0;
	result = Parser.parseElement(allocator, ".{   \"name\"\t1\n,    17.1}", &index);
	try std.testing.expectEqual(.array, std.meta.activeTag(result));
	try std.testing.expectEqual(.stringOwned, std.meta.activeTag(result.array.items[0]));
	try std.testing.expectEqual(ZonElement{.int=1}, result.array.items[1]);
	try std.testing.expectEqual(ZonElement{.float=17.1}, result.array.items[2]);
	result.deinit(allocator);
}