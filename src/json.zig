const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const main = @import("main.zig");

const OutOfMemory = Allocator.Error;

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
	JsonArray: *ArrayList(JsonElement),
	JsonObject: *std.StringHashMap(JsonElement),

	pub fn initObject(allocator: Allocator) !JsonElement {
		const map: *std.StringHashMap(JsonElement) = try allocator.create(std.StringHashMap(JsonElement));
		map.* = std.StringHashMap(JsonElement).init(allocator);
		return JsonElement{.JsonObject=map};
	}

	pub fn initArray(allocator: Allocator) !JsonElement {
		const list: *ArrayList(JsonElement) = try allocator.create(ArrayList(JsonElement));
		list.* = ArrayList(JsonElement).init(allocator);
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

	pub fn as(self: *const JsonElement, comptime _type: type, replacement: _type) _type {
		comptime var typeInfo = @typeInfo(_type);
		comptime var innerType = _type;
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
						@compileError("Unsupported type '" ++ @typeName(_type) ++ "'.");
					}
				}
			},
		}
	}

	fn createElementFromRandomType(value: anytype) JsonElement {
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
					return createElementFromRandomType(val);
				} else {
					return JsonElement{.JsonNull={}};
				}
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

	pub fn put(self: *const JsonElement, key: []const u8, value: anytype) !void {
		const result = createElementFromRandomType(value);
		try self.JsonObject.put(try self.JsonObject.allocator.dupe(u8, key), result);
	}

	pub fn putOwnedString(self: *const JsonElement, key: []const u8, value: []const u8) !void {
		const result = JsonElement{.JsonStringOwned = try self.JsonObject.allocator.dupe(u8, value)};
		try self.JsonObject.put(try self.JsonObject.allocator.dupe(u8, key), result);
	}

	pub fn toSlice(self: *const JsonElement) []JsonElement {
		switch(self.*) {
			.JsonArray => |arr| {
				return arr.items;
			},
			else => return &[0]JsonElement{},
		}
	}

	pub fn free(self: *const JsonElement, allocator: Allocator) void {
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

	fn escapeToWriter(writer: std.ArrayList(u8).Writer, string: []const u8) !void {
		for(string) |char| {
			switch(char) {
				'\\' => try writer.writeAll("\\\\"),
				'\n' => try writer.writeAll("\\n"),
				'\"' => try writer.writeAll("\\\""),
				'\t' => try writer.writeAll("\\t"),
				else => try writer.writeByte(char),
			}
		}
	}
	fn writeTabs(writer: std.ArrayList(u8).Writer, tabs: u32) !void {
		for(0..tabs) |_| {
			try writer.writeByte('\t');
		}
	}
	fn recurseToString(json: JsonElement, writer: std.ArrayList(u8).Writer, tabs: u32, comptime visualCharacters: bool) !void {
		switch(json) {
			.JsonInt => |value| {
				try std.fmt.formatInt(value, 10, .lower, .{}, writer);
			},
			.JsonFloat => |value| {
				try std.fmt.formatFloatScientific(value, .{}, writer);
			},
			.JsonBool => |value| {
				if(value) {
					try writer.writeAll("true");
				} else {
					try writer.writeAll("false");
				}
			},
			.JsonNull => {
				try writer.writeAll("null");
			},
			.JsonString, .JsonStringOwned => |value| {
				try writer.writeByte('\"');
				try escapeToWriter(writer, value);
				try writer.writeByte('\"');
			},
			.JsonArray => |array| {
				try writer.writeByte('[');
				for(array.items, 0..) |elem, i| {
					if(i != 0) {
						try writer.writeByte(',');
					}
					if(visualCharacters) try writer.writeByte('\n');
					if(visualCharacters) try writeTabs(writer, tabs + 1);
					try recurseToString(elem, writer, tabs + 1, visualCharacters);
				}
				if(visualCharacters) try writer.writeByte('\n');
				if(visualCharacters) try writeTabs(writer, tabs);
				try writer.writeByte(']');
			},
			.JsonObject => |obj| {
				try writer.writeByte('{');
				var iterator = obj.iterator();
				var first: bool = true;
				while(true) {
					const elem = iterator.next() orelse break;
					if(!first) {
						try writer.writeByte(',');
					}
					if(visualCharacters) try writer.writeByte('\n');
					if(visualCharacters) try writeTabs(writer, tabs + 1);
					try writer.writeByte('\"');
					try writer.writeAll(elem.key_ptr.*);
					try writer.writeByte('\"');
					if(visualCharacters) try writer.writeByte(' ');
					try writer.writeByte(':');
					if(visualCharacters) try writer.writeByte(' ');

					try recurseToString(elem.value_ptr.*, writer, tabs + 1, visualCharacters);
					first = false;
				}
				if(visualCharacters) try writer.writeByte('\n');
				if(visualCharacters) try writeTabs(writer, tabs);
				try writer.writeByte('}');
			},
		}
	}
	pub fn toString(json: JsonElement, allocator: Allocator) ![]const u8 {
		var string = std.ArrayList(u8).init(allocator);
		try recurseToString(json, string.writer(), 0, true);
		return string.toOwnedSlice();
	}

	/// Ignores all the visual characters(spaces, tabs and newlines) and allows adding a custom prefix(which is for example required by networking).
	pub fn toStringEfficient(json: JsonElement, allocator: Allocator, prefix: []const u8) ![]const u8 {
		var string = std.ArrayList(u8).init(allocator);
		try string.appendSlice(prefix);
		try recurseToString(json, string.writer(), 0, false);
		return string.toOwnedSlice();
	}

	pub fn parseFromString(allocator: Allocator, string: []const u8) JsonElement {
		var index: u32 = 0;
		Parser.skipWhitespaces(string, &index);
		return Parser.parseElement(allocator, string, &index) catch {
			std.log.err("Out of memory while trying to parse json.", .{});
			return JsonElement{.JsonNull={}};
		};
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

	fn parseString(allocator: Allocator, chars: []const u8, index: *u32) OutOfMemory![]const u8 {
		var builder: ArrayList(u8) = ArrayList(u8).init(allocator);
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
						try builder.append('\t');
					},
					'n' => {
						try builder.append('\n');
					},
					'r' => {
						try builder.append('\r');
					},
					else => {
						try builder.append(chars[index.*]);
					}
				}
			} else {
				try builder.append(chars[index.*]);
			}
		}
		return builder.toOwnedSlice();
	}

	fn parseArray(allocator: Allocator, chars: []const u8, index: *u32) OutOfMemory!JsonElement {
		const list: *ArrayList(JsonElement) = try allocator.create(ArrayList(JsonElement));
		list.* = ArrayList(JsonElement).init(allocator);
		while(index.* < chars.len) {
			skipWhitespaces(chars, index);
			if(index.* >= chars.len) break;
			if(chars[index.*] == ']') {
				index.* += 1;
				return JsonElement{.JsonArray=list};
			}
			try list.append(try parseElement(allocator, chars, index));
			skipWhitespaces(chars, index);
			if(index.* < chars.len and chars[index.*] == ',') {
				index.* += 1;
			}
		}
		try printError(chars, index.*, "Unexpected end of file in array parsing.");
		return JsonElement{.JsonArray=list};
	}

	fn parseObject(allocator: Allocator, chars: []const u8, index: *u32) OutOfMemory!JsonElement {
		const map: *std.StringHashMap(JsonElement) = try allocator.create(std.StringHashMap(JsonElement));
		map.* = std.StringHashMap(JsonElement).init(allocator);
		while(index.* < chars.len) {
			skipWhitespaces(chars, index);
			if(index.* >= chars.len) break;
			if(chars[index.*] == '}') {
				index.* += 1;
				return JsonElement{.JsonObject=map};
			} else if(chars[index.*] != '\"') {
				try printError(chars, index.*, "Unexpected character in object parsing.");
				index.* += 1;
				continue;
			}
			index.* += 1;
			const key: []const u8 = try parseString(allocator, chars, index);
			skipWhitespaces(chars, index);
			while(index.* < chars.len and chars[index.*] != ':') {
				try printError(chars, index.*, "Unexpected character in object parsing, expected ':'.");
				index.* += 1;
			}
			index.* += 1;
			skipWhitespaces(chars, index);
			const value: JsonElement = try parseElement(allocator, chars, index);
			map.putNoClobber(key, value) catch {
				try printError(chars, index.*, "Duplicate key.");
				allocator.free(key);
			};
			skipWhitespaces(chars, index);
			if(index.* < chars.len and chars[index.*] == ',') {
				index.* += 1;
			}
		}
		try printError(chars, index.*, "Unexpected end of file in object parsing.");
		return JsonElement{.JsonObject=map};
	}

	fn printError(chars: []const u8, index: u32, msg: []const u8) !void {
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
		var lineEnd: u32 = i;
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
	fn parseElement(allocator: Allocator, chars: []const u8, index: *u32) OutOfMemory!JsonElement {
		if(index.* >= chars.len) {
			try printError(chars, index.*, "Unexpected end of file.");
			return JsonElement{.JsonNull={}};
		}
		switch(chars[index.*]) {
			'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '-', '.' => {
				return parseNumber(chars, index);
			},
			't' => { // Value can only be true.
				if(index.* + 3 >= chars.len) {
					try printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'r' or chars[index.*+2] != 'u' or chars[index.*+3] != 'e') {
					try printError(chars, index.*, "Unknown expression, interpreting as true.");
				}
				index.* += 4;
				return JsonElement{.JsonBool=true};
			},
			'f' => { // Value can only be false.
				if(index.* + 4 >= chars.len) {
					try printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'a' or chars[index.*+2] != 'l' or chars[index.*+3] != 's' or chars[index.*+4] != 'e') {
					try printError(chars, index.*, "Unknown expression, interpreting as false.");
				}
				index.* += 5;
				return JsonElement{.JsonBool=false};
			},
			'n' => { // Value can only be null.
				if(index.* + 3 >= chars.len) {
					try printError(chars, index.*, "Unexpected end of file.");
				} else if(chars[index.*+1] != 'u' or chars[index.*+2] != 'l' or chars[index.*+3] != 'l') {
					try printError(chars, index.*, "Unknown expression, interpreting as null.");
				}
				index.* += 4;
				return JsonElement{.JsonNull={}};
			},
			'\"' => {
				index.* += 1;
				return JsonElement{.JsonStringOwned=try parseString(allocator, chars, index)};
			},
			'[' => {
				index.* += 1;
				return try parseArray(allocator, chars, index);
			},
			'{' => {
				index.* += 1;
				return try parseObject(allocator, chars, index);
			},
			else => {
				try printError(chars, index.*, "Unexpected character.");
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
	try std.testing.expectApproxEqAbs((try Parser.parseElement(std.testing.allocator, "1543.234589e10", &index)).JsonFloat, 1543.234589e10, 1.0);
	index = 5;
	try std.testing.expectApproxEqAbs((try Parser.parseElement(std.testing.allocator, "_____0.0000000000675849301354e10abcdfe", &index)).JsonFloat, 0.675849301354, 1e-10);
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
	var result: JsonElement = try Parser.parseElement(std.testing.allocator, "\"abcd\\\"\\\\ħσ→ ↑Φ∫€ ⌬ ε→Π\"", &index);
	try std.testing.expectEqualStrings("abcd\"\\ħσ→ ↑Φ∫€ ⌬ ε→Π", result.as([]const u8, ""));
	result.free(std.testing.allocator);
	index = 0;
	result = try Parser.parseElement(std.testing.allocator, "\"12345", &index);
	try std.testing.expectEqualStrings("12345", result.as([]const u8, ""));
	result.free(std.testing.allocator);

	// Object:
	index = 0;
	result = try Parser.parseElement(std.testing.allocator, "{\"name\": 1}", &index);
	try std.testing.expectEqual(JsonType.JsonObject, result);
	try std.testing.expectEqual(result.JsonObject.get("name"), JsonElement{.JsonInt = 1});
	result.free(std.testing.allocator);
	index = 0;
	result = try Parser.parseElement(std.testing.allocator, "{\"object\":{},}", &index);
	try std.testing.expectEqual(JsonType.JsonObject, result);
	try std.testing.expectEqual(JsonType.JsonObject, result.JsonObject.get("object") orelse JsonType.JsonNull);
	result.free(std.testing.allocator);
	index = 0;
	result = try Parser.parseElement(std.testing.allocator, "{   \"object1\"   :   \"\"  \n, \"object2\"  :\t{\n},\"object3\"   :1.0e4\t,\"\nobject1\":{},\"\tobject1θ\":[],}", &index);
	try std.testing.expectEqual(JsonType.JsonObject, result);
	try std.testing.expectEqual(JsonType.JsonFloat, result.JsonObject.get("object3") orelse JsonType.JsonNull);
	try std.testing.expectEqual(JsonType.JsonStringOwned, result.JsonObject.get("object1") orelse JsonType.JsonNull);
	try std.testing.expectEqual(JsonType.JsonObject, result.JsonObject.get("\nobject1") orelse JsonType.JsonNull);
	try std.testing.expectEqual(JsonType.JsonArray, result.JsonObject.get("\tobject1θ") orelse JsonType.JsonNull);
	result.free(std.testing.allocator);

	//Array:
	index = 0;
	result = try Parser.parseElement(std.testing.allocator, "[\"name\",1]", &index);
	try std.testing.expectEqual(JsonType.JsonArray, result);
	try std.testing.expectEqual(JsonType.JsonStringOwned, result.JsonArray.items[0]);
	try std.testing.expectEqual(JsonElement{.JsonInt=1}, result.JsonArray.items[1]);
	result.free(std.testing.allocator);
	index = 0;
	result = try Parser.parseElement(std.testing.allocator, "[   \"name\"\t1\n,    17.1]", &index);
	try std.testing.expectEqual(JsonType.JsonArray, result);
	try std.testing.expectEqual(JsonType.JsonStringOwned, result.JsonArray.items[0]);
	try std.testing.expectEqual(JsonElement{.JsonInt=1}, result.JsonArray.items[1]);
	try std.testing.expectEqual(JsonElement{.JsonFloat=17.1}, result.JsonArray.items[2]);
	result.free(std.testing.allocator);
}