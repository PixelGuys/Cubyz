const std = @import("std");

const main = @import("main.zig");
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const List = main.List;

const JsonType = enum(u8) {
	JsonInt,
	JsonFloat,
	JsonString,
	JsonStringOwned,
	JsonBool,
	JsonNull,
	JsonArray,
	JsonObject
};
pub const JsonElement = union(JsonType) {
	JsonInt: i64,
	JsonFloat: f64,
	JsonString: []const u8,
	JsonStringOwned: []const u8,
	JsonBool: bool,
	JsonNull: void,
	JsonArray: *List(JsonElement),
	JsonObject: *std.StringHashMap(JsonElement),

	pub fn initObject(allocator: NeverFailingAllocator) JsonElement {
		const map: *std.StringHashMap(JsonElement) = allocator.create(std.StringHashMap(JsonElement));
		map.* = std.StringHashMap(JsonElement).init(allocator.allocator);
		return JsonElement{.JsonObject=map};
	}

	pub fn initArray(allocator: NeverFailingAllocator) JsonElement {
		const list: *List(JsonElement) = allocator.create(List(JsonElement));
		list.* = List(JsonElement).init(allocator);
		return JsonElement{.JsonArray=list};
	}

	pub fn getAtIndex(self: *const JsonElement, comptime _type: type, index: usize, replacement: _type) _type {
		if(self.* != .JsonArray) {
			return replacement;
		} else {
			if(index < self.JsonArray.items.len) {
				return self.JsonArray.items[index].as(_type, replacement);
			} else {
				return replacement;
			}
		}
	}

	pub fn getChildAtIndex(self: *const JsonElement, index: usize) JsonElement {
		if(self.* != .JsonArray) {
			return JsonElement{.JsonNull={}};
		} else {
			if(index < self.JsonArray.items.len) {
				return self.JsonArray.items[index];
			} else {
				return JsonElement{.JsonNull={}};
			}
		}
	}

	pub fn get(self: *const JsonElement, comptime _type: type, key: []const u8, replacement: _type) _type {
		if(self.* != .JsonObject) {
			return replacement;
		} else {
			if(self.JsonObject.get(key)) |elem| {
				return elem.as(_type, replacement);
			} else {
				return replacement;
			}
		}
	}

	pub fn getChild(self: *const JsonElement, key: []const u8) JsonElement {
		if(self.* != .JsonObject) {
			return JsonElement{.JsonNull={}};
		} else {
			if(self.JsonObject.get(key)) |elem| {
				return elem;
			} else {
				return JsonElement{.JsonNull={}};
			}
		}
	}

	pub fn as(self: *const JsonElement, comptime T: type, replacement: T) T {
		comptime var typeInfo : std.builtin.Type = @typeInfo(T);
		comptime var innerType = T;
		inline while(typeInfo == .Optional) {
			innerType = typeInfo.Optional.child;
			typeInfo = @typeInfo(innerType);
		}
		switch(typeInfo) {
			.Int => {
				switch(self.*) {
					.JsonInt => return std.math.cast(innerType, self.JsonInt) orelse replacement,
					.JsonFloat => return std.math.lossyCast(innerType, std.math.round(self.JsonFloat)),
					else => return replacement,
				}
			},
			.Float => {
				switch(self.*) {
					.JsonInt => return @floatFromInt(self.JsonInt),
					.JsonFloat => return @floatCast(self.JsonFloat),
					else => return replacement,
				}
			},
			.Vector => {
				const len = typeInfo.Vector.len;
				const elems = self.toSlice();
				if(elems.len != len) return replacement;
				var result: innerType = undefined;
				if(innerType == T) result = replacement;
				inline for(0..len) |i| {
					if(innerType == T) {
						result[i] = elems[i].as(typeInfo.Vector.child, result[i]);
					} else {
						result[i] = elems[i].as(?typeInfo.Vector.child, null) orelse return replacement;
					}
				}
				return result;
			},
			else => {
				switch(innerType) {
					[]const u8 => {
						switch(self.*) {
							.JsonString => return self.JsonString,
							.JsonStringOwned => return self.JsonStringOwned,
							else => return replacement,
						}
					},
					bool => {
						switch(self.*) {
							.JsonBool => return self.JsonBool,
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

	fn createElementFromRandomType(value: anytype, allocator: std.mem.Allocator) JsonElement {
		switch(@typeInfo(@TypeOf(value))) {
			.Void => return JsonElement{.JsonNull={}},
			.Null => return JsonElement{.JsonNull={}},
			.Bool => return JsonElement{.JsonBool=value},
			.Int, .ComptimeInt => return JsonElement{.JsonInt=@intCast(value)},
			.Float, .ComptimeFloat => return JsonElement{.JsonFloat=@floatCast(value)},
			.Union => {
				if(@TypeOf(value) == JsonElement) {
					return value;
				} else {
					@compileError("Unknown value type.");
				}
			},
			.Pointer => |ptr| {
				if(ptr.child == u8 and ptr.size == .Slice) {
					return JsonElement{.JsonString=value};
				} else {
					const childInfo = @typeInfo(ptr.child);
					if(ptr.size == .One and childInfo == .Array and childInfo.Array.child == u8) {
						return JsonElement{.JsonString=value};
					} else {
						@compileError("Unknown value type.");
					}
				}
			},
			.Optional => {
				if(value) |val| {
					return createElementFromRandomType(val, allocator);
				} else {
					return JsonElement{.JsonNull={}};
				}
			},
			.Vector => {
				const len = @typeInfo(@TypeOf(value)).Vector.len;
				const result = initArray(main.utils.NeverFailingAllocator{.allocator = allocator, .IAssertThatTheProvidedAllocatorCantFail = {}});
				result.JsonArray.ensureCapacity(len);
				inline for(0..len) |i| {
					result.JsonArray.appendAssumeCapacity(createElementFromRandomType(value[i], allocator));
				}
				return result;
			},
			else => {
				if(@TypeOf(value) == JsonElement) {
					return value;
				} else {
					@compileError("Unknown value type.");
				}
			},
		}
	}

	pub fn put(self: *const JsonElement, key: []const u8, value: anytype) void {
		const result = createElementFromRandomType(value, self.JsonObject.allocator);
		self.JsonObject.put(self.JsonObject.allocator.dupe(u8, key) catch unreachable, result) catch unreachable;
	}

	pub fn putOwnedString(self: *const JsonElement, key: []const u8, value: []const u8) void {
		const result = JsonElement{.JsonStringOwned = self.JsonObject.allocator.dupe(u8, value) catch unreachable};
		self.JsonObject.put(self.JsonObject.allocator.dupe(u8, key) catch unreachable, result) catch unreachable;
	}

	pub fn toSlice(self: *const JsonElement) []JsonElement {
		switch(self.*) {
			.JsonArray => |arr| {
				return arr.items;
			},
			else => return &[0]JsonElement{},
		}
	}

	pub fn free(self: *const JsonElement, allocator: NeverFailingAllocator) void {
		switch(self.*) {
			.JsonInt, .JsonFloat, .JsonBool, .JsonNull, .JsonString => return,
			.JsonStringOwned => {
				allocator.free(self.JsonStringOwned);
			},
			.JsonArray => {
				for(self.JsonArray.items) |*elem| {
					elem.free(allocator);
				}
				self.JsonArray.clearAndFree();
				allocator.destroy(self.JsonArray);
			},
			.JsonObject => {
				var iterator = self.JsonObject.iterator();
				while(true) {
					const elem = iterator.next() orelse break;
					allocator.free(elem.key_ptr.*);
					elem.value_ptr.free(allocator);
				}
				self.JsonObject.clearAndFree();
				allocator.destroy(self.JsonObject);
			},
		}
	}

	pub fn isNull(self: *const JsonElement) bool {
		return self.* == .JsonNull;
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
	fn recurseToString(json: JsonElement, list: *List(u8), tabs: u32, comptime visualCharacters: bool) void {
		switch(json) {
			.JsonInt => |value| {
				std.fmt.formatInt(value, 10, .lower, .{}, list.writer()) catch unreachable;
			},
			.JsonFloat => |value| {
				var buf: [std.fmt.format_float.bufferSize(.scientific, @TypeOf(value))]u8 = undefined;
				list.appendSlice(std.fmt.format_float.formatFloat(&buf, value, .{.mode = .scientific}) catch unreachable);
			},
			.JsonBool => |value| {
				if(value) {
					list.appendSlice("true");
				} else {
					list.appendSlice("false");
				}
			},
			.JsonNull => {
				list.appendSlice("null");
			},
			.JsonString, .JsonStringOwned => |value| {
				list.append('\"');
				escape(list, value);
				list.append('\"');
			},
			.JsonArray => |array| {
				list.append('[');
				for(array.items, 0..) |elem, i| {
					if(i != 0) {
						list.append(',');
					}
					if(visualCharacters) list.append('\n');
					if(visualCharacters) writeTabs(list, tabs + 1);
					recurseToString(elem, list, tabs + 1, visualCharacters);
				}
				if(visualCharacters) list.append('\n');
				if(visualCharacters) writeTabs(list, tabs);
				list.append(']');
			},
			.JsonObject => |obj| {
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
					list.append('\"');
					list.appendSlice(elem.key_ptr.*);
					list.append('\"');
					if(visualCharacters) list.append(' ');
					list.append(':');
					if(visualCharacters) list.append(' ');

					recurseToString(elem.value_ptr.*, list, tabs + 1, visualCharacters);
					first = false;
				}
				if(visualCharacters) list.append('\n');
				if(visualCharacters) writeTabs(list, tabs);
				list.append('}');
			},
		}
	}
	pub fn toString(json: JsonElement, allocator: NeverFailingAllocator) []const u8 {
		var string = List(u8).init(allocator);
		recurseToString(json, &string, 0, true);
		return string.toOwnedSlice();
	}

	/// Ignores all the visual characters(spaces, tabs and newlines) and allows adding a custom prefix(which is for example required by networking).
	pub fn toStringEfficient(json: JsonElement, allocator: NeverFailingAllocator, prefix: []const u8) []const u8 {
		var string = List(u8).init(allocator);
		string.appendSlice(prefix);
		recurseToString(json, &string, 0, false);
		return string.toOwnedSlice();
	}

	pub fn parseFromString(allocator: NeverFailingAllocator, string: []const u8) JsonElement {
		var index: u32 = 0;
		Parser.skipWhitespaces(string, &index);
		return Parser.parseElement(allocator, string, &index);
	}
};

const Parser = struct {
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
	fn parseNumber(chars: []const u8, index: *u32) JsonElement {
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
			return JsonElement{.JsonInt = sign*intPart};
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
			return JsonElement{.JsonInt = sign*intPart};
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
		return JsonElement{.JsonFloat = @as(f64, @floatFromInt(sign))*(@as(f64, @floatFromInt(intPart)) + floatPart)*std.math.pow(f64, 10, @as(f64, @floatFromInt(exponentSign*exponent)))};
	}

	fn parseString(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) []const u8 {
		var builder: List(u8) = List(u8).init(allocator);
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

	fn parseArray(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) JsonElement {
		const list: *List(JsonElement) = allocator.create(List(JsonElement));
		list.* = List(JsonElement).init(allocator);
		while(index.* < chars.len) {
			skipWhitespaces(chars, index);
			if(index.* >= chars.len) break;
			if(chars[index.*] == ']') {
				index.* += 1;
				return JsonElement{.JsonArray=list};
			}
			list.append(parseElement(allocator, chars, index));
			skipWhitespaces(chars, index);
			if(index.* < chars.len and chars[index.*] == ',') {
				index.* += 1;
			}
		}
		printError(chars, index.*, "Unexpected end of file in array parsing.");
		return JsonElement{.JsonArray=list};
	}

	fn parseObject(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) JsonElement {
		const map: *std.StringHashMap(JsonElement) = allocator.create(std.StringHashMap(JsonElement));
		map.* = std.StringHashMap(JsonElement).init(allocator.allocator);
		while(index.* < chars.len) {
			skipWhitespaces(chars, index);
			if(index.* >= chars.len) break;
			if(chars[index.*] == '}') {
				index.* += 1;
				return JsonElement{.JsonObject=map};
			} else if(chars[index.*] != '\"') {
				printError(chars, index.*, "Unexpected character in object parsing.");
				index.* += 1;
				continue;
			}
			index.* += 1;
			const key: []const u8 = parseString(allocator, chars, index);
			skipWhitespaces(chars, index);
			while(index.* < chars.len and chars[index.*] != ':') {
				printError(chars, index.*, "Unexpected character in object parsing, expected ':'.");
				index.* += 1;
			}
			index.* += 1;
			skipWhitespaces(chars, index);
			const value: JsonElement = parseElement(allocator, chars, index);
			if(map.fetchPut(key, value) catch unreachable) |old| {
				printError(chars, index.*, "Duplicate key.");
				allocator.free(old.key);
				old.value.free(allocator);
			}
			skipWhitespaces(chars, index);
			if(index.* < chars.len and chars[index.*] == ',') {
				index.* += 1;
			}
		}
		printError(chars, index.*, "Unexpected end of file in object parsing.");
		return JsonElement{.JsonObject=map};
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
	fn parseElement(allocator: NeverFailingAllocator, chars: []const u8, index: *u32) JsonElement {
		if(index.* >= chars.len) {
			printError(chars, index.*, "Unexpected end of file.");
			return JsonElement{.JsonNull={}};
		}
		switch(chars[index.*]) {
			'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '-', '.' => {
				return parseNumber(chars, index);
			},
			't' => { // Value can only be true.
				if(index.* + 3 >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'r' or chars[index.*+2] != 'u' or chars[index.*+3] != 'e') {
					printError(chars, index.*, "Unknown expression, interpreting as true.");
				}
				index.* += 4;
				return JsonElement{.JsonBool=true};
			},
			'f' => { // Value can only be false.
				if(index.* + 4 >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'a' or chars[index.*+2] != 'l' or chars[index.*+3] != 's' or chars[index.*+4] != 'e') {
					printError(chars, index.*, "Unknown expression, interpreting as false.");
				}
				index.* += 5;
				return JsonElement{.JsonBool=false};
			},
			'n' => { // Value can only be null.
				if(index.* + 3 >= chars.len) {
					printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'u' or chars[index.*+2] != 'l' or chars[index.*+3] != 'l') {
					printError(chars, index.*, "Unknown expression, interpreting as null.");
				}
				index.* += 4;
				return JsonElement{.JsonNull={}};
			},
			'\"' => {
				index.* += 1;
				return JsonElement{.JsonStringOwned = parseString(allocator, chars, index)};
			},
			'[' => {
				index.* += 1;
				return parseArray(allocator, chars, index);
			},
			'{' => {
				index.* += 1;
				return parseObject(allocator, chars, index);
			},
			else => {
				printError(chars, index.*, "Unexpected character.");
				return JsonElement{.JsonNull={}};
			}
		}
	}
};



// ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// TESTING
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
	try std.testing.expectEqual(Parser.parseNumber("0", &index), JsonElement{.JsonInt = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("+0", &index), JsonElement{.JsonInt = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("abcd", &index), JsonElement{.JsonInt = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("-0+1", &index), JsonElement{.JsonInt = 0});
	index = 5;
	try std.testing.expectEqual(Parser.parseNumber(" abcd185473896", &index), JsonElement{.JsonInt = 185473896});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0xff34786056.0", &index), JsonElement{.JsonInt = 0xff34786056});
	// Floats:
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0.0", &index), JsonElement{.JsonFloat = 0.0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0e10e10", &index), JsonElement{.JsonFloat = 0.0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("-0.0.0", &index), JsonElement{.JsonFloat = 0.0});
	index = 0;
	try std.testing.expectEqual(Parser.parseNumber("0xabcd.0e10+-+-", &index), JsonElement{.JsonInt = 0xabcd});
	index = 0;
	try std.testing.expectApproxEqAbs(Parser.parseNumber("1.234589e10", &index).JsonFloat, 1.234589e10, 1.0);
	index = 5;
	try std.testing.expectApproxEqAbs(Parser.parseNumber("_____0.0000000000234589e10abcdfe", &index).JsonFloat, 0.234589, 1e-10);
}

test "element parsing" {
	// Integers:
	var index: u32 = 0;
	try std.testing.expectEqual(Parser.parseElement(std.testing.allocator, "0", &index), JsonElement{.JsonInt = 0});
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(std.testing.allocator, "0xff34786056.0, true", &index), JsonElement{.JsonInt = 0xff34786056});
	// Floats:
	index = 9;
	try std.testing.expectEqual(Parser.parseElement(std.testing.allocator, "{\"abcd\": 0.0,}", &index), JsonElement{.JsonFloat = 0.0});
	index = 0;
	try std.testing.expectApproxEqAbs((Parser.parseElement(std.testing.allocator, "1543.234589e10", &index)).JsonFloat, 1543.234589e10, 1.0);
	index = 5;
	try std.testing.expectApproxEqAbs((Parser.parseElement(std.testing.allocator, "_____0.0000000000675849301354e10abcdfe", &index)).JsonFloat, 0.675849301354, 1e-10);
	// Null:
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(std.testing.allocator, "null", &index), JsonElement{.JsonNull={}});
	// true:
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(std.testing.allocator, "true", &index), JsonElement{.JsonBool=true});
	// false:
	index = 0;
	try std.testing.expectEqual(Parser.parseElement(std.testing.allocator, "false", &index), JsonElement{.JsonBool=false});

	// String:
	index = 0;
	var result: JsonElement = Parser.parseElement(std.testing.allocator, "\"abcd\\\"\\\\ħσ→ ↑Φ∫€ ⌬ ε→Π\"", &index);
	try std.testing.expectEqualStrings("abcd\"\\ħσ→ ↑Φ∫€ ⌬ ε→Π", result.as([]const u8, ""));
	result.free(std.testing.allocator);
	index = 0;
	result = Parser.parseElement(std.testing.allocator, "\"12345", &index);
	try std.testing.expectEqualStrings("12345", result.as([]const u8, ""));
	result.free(std.testing.allocator);

	// Object:
	index = 0;
	result = Parser.parseElement(std.testing.allocator, "{\"name\": 1}", &index);
	try std.testing.expectEqual(JsonType.JsonObject, result);
	try std.testing.expectEqual(result.JsonObject.get("name"), JsonElement{.JsonInt = 1});
	result.free(std.testing.allocator);
	index = 0;
	result = Parser.parseElement(std.testing.allocator, "{\"object\":{},}", &index);
	try std.testing.expectEqual(JsonType.JsonObject, result);
	try std.testing.expectEqual(JsonType.JsonObject, result.JsonObject.get("object") orelse JsonType.JsonNull);
	result.free(std.testing.allocator);
	index = 0;
	result = Parser.parseElement(std.testing.allocator, "{   \"object1\"   :   \"\"  \n, \"object2\"  :\t{\n},\"object3\"   :1.0e4\t,\"\nobject1\":{},\"\tobject1θ\":[],}", &index);
	try std.testing.expectEqual(JsonType.JsonObject, result);
	try std.testing.expectEqual(JsonType.JsonFloat, result.JsonObject.get("object3") orelse JsonType.JsonNull);
	try std.testing.expectEqual(JsonType.JsonStringOwned, result.JsonObject.get("object1") orelse JsonType.JsonNull);
	try std.testing.expectEqual(JsonType.JsonObject, result.JsonObject.get("\nobject1") orelse JsonType.JsonNull);
	try std.testing.expectEqual(JsonType.JsonArray, result.JsonObject.get("\tobject1θ") orelse JsonType.JsonNull);
	result.free(std.testing.allocator);

	//Array:
	index = 0;
	result = Parser.parseElement(std.testing.allocator, "[\"name\",1]", &index);
	try std.testing.expectEqual(JsonType.JsonArray, result);
	try std.testing.expectEqual(JsonType.JsonStringOwned, result.JsonArray.items[0]);
	try std.testing.expectEqual(JsonElement{.JsonInt=1}, result.JsonArray.items[1]);
	result.free(std.testing.allocator);
	index = 0;
	result = Parser.parseElement(std.testing.allocator, "[   \"name\"\t1\n,    17.1]", &index);
	try std.testing.expectEqual(JsonType.JsonArray, result);
	try std.testing.expectEqual(JsonType.JsonStringOwned, result.JsonArray.items[0]);
	try std.testing.expectEqual(JsonElement{.JsonInt=1}, result.JsonArray.items[1]);
	try std.testing.expectEqual(JsonElement{.JsonFloat=17.1}, result.JsonArray.items[2]);
	result.free(std.testing.allocator);
}