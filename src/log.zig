const std = @import("std");
const main = @import("main");
const files = main.files;
const fmt = main.fmt;
const graphics = main.graphics;
const gui = main.gui;
const List = main.List;
const settings = main.settings;

pub const Level = enum {
	/// Error: something has gone wrong. This might be recoverable or might
	/// be followed by the program exiting.
	err,
	/// Warning: it is uncertain if something has gone wrong or not, but the
	/// circumstances would be worth investigating.
	warn,
	/// Info: general messages about the state of the program.
	info,
	/// Debug: messages only useful for debugging.
	debug,
	/// server messages
	server,
	/// chat messages
	chat,

	fn isColorCoded(self: Level) bool {
		return self == .chat or self == .server;
	}

	fn fromStdLevel(level: std.log.Level) Level {
		return switch (level) {
			.err => .err,
			.warn => .warn,
			.info => .info,
			.debug => .debug,
		};
	}
};

var logFile: ?std.Io.File = undefined;
var logFileTs: ?std.Io.File = undefined;
var supportsANSIColors: bool = undefined;
var openingErrorWindow: bool = false;

pub fn logFn(
	comptime level: std.log.Level,
	comptime _: @EnumLiteral(),
	comptime format: []const u8,
	args: anytype,
) void {
	var runtimeArgs: [args.len]fmt.FormatArg = undefined;
	inline for (0..args.len) |i| {
		runtimeArgs[i] = .fromAnytype(@TypeOf(args[i]), &args[i]);
	}

	runtimeLogFn(.fromStdLevel(level), format, &runtimeArgs);
}

noinline fn runtimeLogFn(level: Level, format: []const u8, args: []const fmt.FormatArg) void {
	var buf: [65536]u8 = undefined;
	var writer: std.Io.Writer = .fixed(&buf);
	fmt.format(&writer, format, args) catch {
		std.log.err("Truncated long log message.", .{});
	};

	const color: []const u8 = switch (level) {
		.err => "\x1b[31m",
		.info => "",
		.warn => "\x1b[33m",
		.debug => "\x1b[37;44m",
		.server => "\x1b[34mserver\x1b[0m: ",
		.chat => "\x1b[36mchat\x1b[0m: ",
	};
	const colorReset = "\x1b[0m\n";
	const filePrefix = switch (level) {
		.err => "error",
		.warn => "warning",
		.info => "info",
		.debug => "debug",
		.server => "server",
		.chat => "chat",
	};
	const fileSuffix = "\n";

	logToFile("[{s}]: {s}{s}", .{filePrefix, writer.buffered(), fileSuffix});
	if (supportsANSIColors) {
		logToStdErr(level, "{s}{s}{s}", .{color, writer.buffered(), colorReset});
	} else {
		logToStdErr(level, "[{s}]: {s}{s}", .{filePrefix, writer.buffered(), fileSuffix});
	}

	if (level == .err and !openingErrorWindow and !settings.launchConfig.headlessServer) {
		openingErrorWindow = true;
		gui.openWindow("error_prompt");
		openingErrorWindow = false;
	}
}

pub fn init() void {
	logFile = null;
	files.cwd().makePath("logs") catch |err| {
		std.log.err("Couldn't create logs folder: {s}", .{@errorName(err)});
		return;
	};
	logFile = std.Io.Dir.cwd().createFile(main.io, "logs/latest.log", .{}) catch |err| {
		std.log.err("Couldn't create logs/latest.log: {s}", .{@errorName(err)});
		return;
	};

	const _timestamp = std.Io.Clock.Timestamp.now(main.io, .real).raw;

	const _path_str = std.fmt.allocPrint(main.stackAllocator.allocator, "logs/ts_{}.log", .{_timestamp.nanoseconds}) catch unreachable;
	defer main.stackAllocator.free(_path_str);

	logFileTs = std.Io.Dir.cwd().createFile(main.io, _path_str, .{}) catch |err| {
		std.log.err("Couldn't create {s}: {s}", .{_path_str, @errorName(err)});
		return;
	};

	supportsANSIColors = std.Io.File.stdout().supportsAnsiEscapeCodes(main.io) catch unreachable;
}

pub fn deinit() void {
	if (logFile) |_logFile| {
		_logFile.close(main.io);
		logFile = null;
	}

	if (logFileTs) |_logFileTs| {
		_logFileTs.close(main.io);
		logFileTs = null;
	}
}

fn logToFile(comptime format: []const u8, args: anytype) void {
	var buf: [65536]u8 = undefined;
	var fba = std.heap.FixedBufferAllocator.init(&buf);
	const allocator = fba.allocator();

	const string = std.fmt.allocPrint(allocator, format, args) catch format;
	(logFile orelse return).writeStreamingAll(main.io, string) catch {};
	(logFileTs orelse return).writeStreamingAll(main.io, string) catch {};
}

fn logToStdErr(level: Level, comptime format: []const u8, args: anytype) void {
	var buf: [65536]u8 = undefined;
	var fba = std.heap.FixedBufferAllocator.init(&buf);
	const allocator = fba.allocator();

	const _string = std.fmt.allocPrint(allocator, format, args) catch format;
	const string = if (level.isColorCoded() and supportsANSIColors) convertColorToANSI(main.stackAllocator, _string) else _string;
	defer if (level.isColorCoded() and supportsANSIColors) main.stackAllocator.free(string);

	const writer = std.debug.lockStderr(&.{});
	defer std.debug.unlockStderr();
	nosuspend writer.file_writer.interface.writeAll(string) catch {};
}

fn convertColorToANSI(allocator: main.heap.NeverFailingAllocator, text: []const u8) []const u8 {
	var list: List(u8) = .empty;

	var parser = graphics.TextBuffer.Parser{
		.unicodeIterator = std.unicode.Utf8Iterator{.bytes = text, .i = 0},
		.currentFontEffect = .{},
		.parsedText = .init(allocator),
		.fontEffects = .init(allocator),
		.characterIndex = .init(allocator),
		.showControlCharacters = false,
	};
	defer parser.fontEffects.deinit();
	defer parser.parsedText.deinit();
	defer parser.characterIndex.deinit();
	parser.parse();

	var currentFontEffect: graphics.TextBuffer.FontEffect = .{};
	for (parser.parsedText.items, parser.fontEffects.items) |unicodeChar, fontEffect| {
		// add actual text at the end
		defer {
			var testBuff: [4]u8 = undefined;
			const len = std.unicode.utf8Encode(@intCast(unicodeChar), &testBuff) catch unreachable;
			list.appendSlice(allocator, testBuff[0..len]);
		}
		if (fontEffect == currentFontEffect) continue;

		list.appendSlice(allocator, "\x1b[");
		defer {
			std.debug.assert(list.items[list.items.len - 1] == ';');
			list.items[list.items.len - 1] = 'm';
		}

		if (fontEffect.color != currentFontEffect.color) {
			list.appendSlice(allocator, "38;2;");
			for ([3]u5{16, 8, 0}) |shift| {
				list.print(allocator, "{d};", .{@as(u8, @truncate(fontEffect.color >> shift))});
			}
		}
		if (fontEffect.bold != currentFontEffect.bold) {
			if (currentFontEffect.bold) {
				list.appendSlice(allocator, "22;");
			} else {
				list.appendSlice(allocator, "1;");
			}
		}
		if (fontEffect.italic != currentFontEffect.italic) {
			if (currentFontEffect.italic) {
				list.appendSlice(allocator, "23;");
			} else {
				list.appendSlice(allocator, "3;");
			}
		}
		if (fontEffect.strikethrough != currentFontEffect.strikethrough) {
			if (currentFontEffect.strikethrough) {
				list.appendSlice(allocator, "29;");
			} else {
				list.appendSlice(allocator, "9;");
			}
		}
		if (fontEffect.underline != currentFontEffect.underline) {
			if (currentFontEffect.underline) {
				list.appendSlice(allocator, "24;");
			} else {
				list.appendSlice(allocator, "4;");
			}
		}
		currentFontEffect = fontEffect;
	}
	return list.toOwnedSlice(allocator);
}

pub fn server(comptime format: []const u8, args: anytype) void {
	var runtimeArgs: [args.len]fmt.FormatArg = undefined;
	inline for (0..args.len) |i| {
		runtimeArgs[i] = .fromAnytype(@TypeOf(args[i]), &args[i]);
	}
	runtimeLogFn(.server, format, &runtimeArgs);
}

pub fn chat(comptime format: []const u8, args: anytype) void {
	var runtimeArgs: [args.len]fmt.FormatArg = undefined;
	inline for (0..args.len) |i| {
		runtimeArgs[i] = .fromAnytype(@TypeOf(args[i]), &args[i]);
	}
	runtimeLogFn(.chat, format, &runtimeArgs);
}
