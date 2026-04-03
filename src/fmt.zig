const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

pub inline fn bufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) std.fmt.BufPrintError![]u8 {
	if (builtin.is_test) return std.fmt.bufPrint(buf, fmt, args);
	var runtimeArgs: [args.len]FormatArg = undefined;
	inline for (0..args.len) |i| {
		runtimeArgs[i] = .fromAnytype(@TypeOf(args[i]), &args[i]);
	}
	return bufPrintRuntime(buf, fmt, &runtimeArgs);
}

pub noinline fn bufPrintRuntime(buf: []u8, fmt: []const u8, args: []const FormatArg) std.fmt.BufPrintError![]u8 {
	var writer: std.Io.Writer = .fixed(buf);
	format(&writer, fmt, args) catch return error.NoSpaceLeft;
	return writer.buffered();
}

pub const FormatArg = union(enum) {
	int: i128,
	uint: u128,
	f16: f16,
	f32: f32,
	f64: f64,
	f80: f80,
	f128: f128,
	string: []const u8,
	nullTerminatedString: [*:0]const u8,
	formatFunction: struct { val: *const anyopaque, function: *const fn (*const anyopaque, *std.Io.Writer) std.Io.Writer.Error!void },
	err: anyerror,
	anyFormatFunction: struct { val: *const anyopaque, function: *const fn (*const anyopaque, *std.Io.Writer) std.Io.Writer.Error!void },

	pub inline fn fromAnytype(T: type, val: *const T) FormatArg {
		switch (@typeInfo(T)) {
			.comptime_int => return .{.int = val.*},
			.int => |int| {
				if (int.signedness == .unsigned) {
					return .{.uint = val.*};
				}
				return .{.int = val.*};
			},
			.comptime_float => return .{.f128 = val.*},
			.float => return @unionInit(FormatArg, @typeName(T), val.*),
			.pointer => |ptr| {
				if (ptr.size == .one and @typeInfo(ptr.child) == .array and @typeInfo(ptr.child).array.child == u8) return .{.string = val.*};
				if (ptr.size == .slice and ptr.child == u8) return .{.string = val.*};
				if ((ptr.size == .many or ptr.size == .c) and ptr.child == u8) return .{.nullTerminatedString = val.*};

				if (ptr.size == .one) return .fromAnytype(ptr.child, val.*);
			},
			.@"struct", .@"enum", .@"union", .@"opaque" => {
				if (@hasDecl(T, "format")) {
					const typeErasedFormat = struct {
						fn typeErasedFormat(ptr: *const anyopaque, writer: *std.Io.Writer) std.Io.Writer.Error!void {
							return T.format(@as(*const T, @ptrCast(@alignCast(ptr))).*, writer);
						}
					}.typeErasedFormat;
					return .{.formatFunction = .{.val = val, .function = typeErasedFormat}};
				}
			},
			.error_set => return .{.err = val.*},
			else => {},
		}

		// Not sure what to do with the rest, so I'll just assume 'any'.
		const genericFormat = struct {
			fn genericFormat(ptr: *const anyopaque, writer: *std.Io.Writer) std.Io.Writer.Error!void {
				try writer.print("{any}", .{@as(*const T, @ptrCast(@alignCast(ptr))).*});
			}
		}.genericFormat;
		return .{.anyFormatFunction = .{.val = val, .function = genericFormat}};
	}
};

pub const Placeholder = struct { // Copied from std.fmt.Placeholder and adjusted for runtime parsing
	specifierArg: []const u8,
	fill: u8,
	alignment: std.fmt.Alignment,
	argPos: ?usize,
	width: ?usize,
	precision: ?usize,

	pub fn parse(bytes: []const u8) !Placeholder {
		var parser: std.fmt.Parser = .{.bytes = bytes, .i = 0};
		const argPos = parser.number();
		const specifierArg = parser.until(':');
		if (parser.char()) |b| {
			if (b != ':') {
				std.log.err("expected : or }}, found '{c}'", .{b});
				return error.UnexpectedCharacter;
			}
		}

		// Parse the fill byte, if present.
		//
		// When the width field is also specified, the fill byte must
		// be followed by an alignment specifier, unless it's '0' (zero)
		// (in which case it's handled as part of the width specifier).
		var fill: ?u8 = if (parser.peek(1)) |b|
			switch (b) {
				'<', '^', '>' => parser.char(),
				else => null,
			}
		else
			null;

		// Parse the alignment parameter
		const alignment: ?std.fmt.Alignment = if (parser.peek(0)) |b| init: {
			switch (b) {
				'<', '^', '>' => {
					// consume the character
					break :init switch (parser.char().?) {
						'<' => .left,
						'^' => .center,
						else => .right,
					};
				},
				else => break :init null,
			}
		} else null;

		// When none of the fill character and the alignment specifier have
		// been provided, check whether the width starts with a zero.
		if (fill == null and alignment == null) {
			fill = if (parser.peek(0) == '0') '0' else null;
		}

		// Parse the width parameter
		const width = parser.number();

		// Skip the dot, if present
		if (parser.char()) |b| {
			if (b != '.') {
				std.log.err("expected . or }}, found '{c}'", .{b});
				return error.UnexpectedCharacter;
			}
		}

		// Parse the precision parameter
		const precision = parser.number();

		if (parser.char()) |b| {
			std.log.err("extraneous trailing character '{c}'", .{b});
			return error.UnexpectedCharacter;
		}

		return .{
			.specifierArg = specifierArg,
			.fill = fill orelse ' ',
			.alignment = alignment orelse .right,
			.argPos = argPos,
			.width = width,
			.precision = precision,
		};
	}
};

pub noinline fn format(writer: *std.Io.Writer, formatString: []const u8, args: []const FormatArg) std.Io.Writer.Error!void {
	var i: usize = 0;
	var argState: std.fmt.ArgState = .{.args_len = args.len};
	while (i < formatString.len) {
		if (formatString[i] != '{' and formatString[i] != '}') {
			try writer.writeByte(formatString[i]);
			i += 1;
			continue;
		}
		if (formatString[i] == '}') {
			if (i + 1 < formatString.len and formatString[i + 1] == '}') {
				try writer.writeByte(formatString[i]);
				i += 2;
				continue;
			}
			std.log.err("Could not find opening {{ of format string: '{s}'", .{formatString});
		}
		if (formatString[i] == '{') {
			if (i + 1 < formatString.len and formatString[i + 1] == '{') {
				try writer.writeByte(formatString[i]);
				i += 2;
				continue;
			}
			const end = std.mem.findScalar(u8, formatString[i..], '}') orelse {
				std.log.err("Could not find closing }} of format string: '{s}'", .{formatString});
				return;
			};
			const placeholderRaw = formatString[i + 1 .. (i + end)];
			i += end + 1;
			const placeholder = Placeholder.parse(placeholderRaw) catch |err| {
				std.log.err("Unable to parse format placeholder {s} of format string {s}: {s}", .{placeholderRaw, formatString, @errorName(err)});
				return;
			};
			const options: std.fmt.Options = .{
				.alignment = placeholder.alignment,
				.fill = placeholder.fill,
				.precision = placeholder.precision,
				.width = placeholder.width,
			};
			const arg = argState.nextArg(placeholder.argPos) orelse {
				std.log.err("Not enough arguments for format string: '{s}', only has {} arguments", .{formatString, args.len});
				return;
			};
			try formatValue(writer, placeholder.specifierArg, options, args[arg], formatString);
		}
	}
	if (argState.hasUnusedArgs()) {
		std.log.err("Format string '{s}' doesn't use all arguments.", .{formatString});
	}
}

fn formatValue(writer: *std.Io.Writer, formatSpecifier: []const u8, options: std.fmt.Options, arg: FormatArg, formatString: []const u8) !void {
	switch (arg) {
		inline .f16, .f32, .f64, .f80, .f128 => |number| {
			const allowedSpecifiers: []const []const u8 = &.{"", "d", "x", "X", "e", "E", "any"};
			inline for (allowedSpecifiers) |allowed| {
				if (std.mem.eql(u8, allowed, formatSpecifier)) {
					try writer.printValue(allowed, options, number, std.options.fmt_max_depth);
					return;
				}
			}
			std.log.err("Format specifier '{s}' not supported for type float.", .{formatSpecifier});
		},
		inline .int, .uint => |number| {
			const allowedSpecifiers: []const []const u8 = &.{"", "d", "b", "o", "x", "X", "any"};
			inline for (allowedSpecifiers) |allowed| {
				if (std.mem.eql(u8, allowed, formatSpecifier)) {
					try writer.printValue(allowed, options, number, std.options.fmt_max_depth);
					return;
				}
			}
			std.log.err("Format specifier '{s}' not supported for type int.", .{formatSpecifier});
		},
		inline .string, .nullTerminatedString => |string| {
			const allowedSpecifiers: []const []const u8 = &.{"x", "X", "s", "b64", "any"};
			inline for (allowedSpecifiers) |allowed| {
				if (std.mem.eql(u8, allowed, formatSpecifier)) {
					try writer.printValue(allowed, options, string, std.options.fmt_max_depth);
					return;
				}
			}
			std.log.err("Format specifier '{s}' not supported for type string.", .{formatSpecifier});
		},
		.formatFunction => |fun| {
			if (std.mem.eql(u8, formatSpecifier, "f")) {
				try fun.function(fun.val, writer);
				return;
			}
			std.log.err("Format specifier '{s}' not supported. Please specify '{{f}}'. To use '{{any}}', please wrap the argument in an anonymous tuple. Format string: {s}", .{formatSpecifier, formatString});
		},
		.anyFormatFunction => |fun| {
			if (std.mem.eql(u8, formatSpecifier, "any") or std.mem.eql(u8, formatSpecifier, "") or std.mem.eql(u8, formatSpecifier, "?")) {
				try fun.function(fun.val, writer);
				return;
			}
			if (std.mem.eql(u8, formatSpecifier, "*")) {
				try fun.function(fun.val, writer);
				try writer.writeByte('@');
				try writer.printValue("x", .{}, @intFromPtr(fun.val), std.options.fmt_max_depth);
				return;
			}
			std.log.err("Format specifier '{s}' not supported. Please specify '{{any}}' or '{{}}'. Format string: {s}", .{formatSpecifier, formatString});
		},
		.err => |err| {
			const allowedSpecifiers: []const []const u8 = &.{"", "t", "any"};
			inline for (allowedSpecifiers) |allowed| {
				if (std.mem.eql(u8, allowed, formatSpecifier)) {
					try writer.printValue(allowed, options, err, std.options.fmt_max_depth);
					return;
				}
			}
			std.log.err("Format specifier '{s}' not supported for type error.", .{formatSpecifier});
		},
	}
}
