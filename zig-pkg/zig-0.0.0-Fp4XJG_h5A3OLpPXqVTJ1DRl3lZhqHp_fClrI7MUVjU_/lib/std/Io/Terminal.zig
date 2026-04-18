/// Abstraction for writing to a stream that might support terminal escape
/// codes.
const Terminal = @This();

const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const std = @import("std");
const Io = std.Io;
const File = std.Io.File;

writer: *Io.Writer,
mode: Mode,

pub const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    dim,
    bold,
    reset,
};

pub const Mode = union(enum) {
    no_color,
    escape_codes,
    windows_api: WindowsApi,

    pub const WindowsApi = if (!is_windows) noreturn else struct {
        io: Io,
        file: File,
        reset_attributes: u16,
    };

    /// Detect suitable TTY configuration options for the given file (commonly
    /// stdout/stderr).
    ///
    /// Will attempt to enable ANSI escape code support if necessary/possible.
    ///
    /// * `NO_COLOR` indicates whether "NO_COLOR" environment variable is
    ///   present and non-empty.
    /// * `CLICOLOR_FORCE` indicates whether "CLICOLOR_FORCE" environment
    ///   variable is present and non-empty.
    pub fn detect(io: Io, file: File, NO_COLOR: bool, CLICOLOR_FORCE: bool) Io.Cancelable!Mode {
        const force_color: ?bool = if (NO_COLOR) false else if (CLICOLOR_FORCE) true else null;
        if (force_color == false) return .no_color;

        if (file.enableAnsiEscapeCodes(io)) |_| {
            return .escape_codes;
        } else |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.NotTerminalDevice, error.Unexpected => {},
        }

        if (is_windows and try file.isTty(io)) {
            var get_console_info = std.os.windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
            switch (try get_console_info.operate(io, file)) {
                .SUCCESS => return .{ .windows_api = .{
                    .io = io,
                    .file = file,
                    .reset_attributes = get_console_info.Data.wAttributes,
                } },
                else => {},
            }
        }
        return if (force_color == true) .escape_codes else .no_color;
    }
};

pub const SetColorError = Io.Cancelable || Io.UnexpectedError || Io.Writer.Error;

pub fn setColor(t: Terminal, color: Color) SetColorError!void {
    switch (t.mode) {
        .no_color => return,
        .escape_codes => {
            const color_string = switch (color) {
                .black => "\x1b[30m",
                .red => "\x1b[31m",
                .green => "\x1b[32m",
                .yellow => "\x1b[33m",
                .blue => "\x1b[34m",
                .magenta => "\x1b[35m",
                .cyan => "\x1b[36m",
                .white => "\x1b[37m",
                .bright_black => "\x1b[90m",
                .bright_red => "\x1b[91m",
                .bright_green => "\x1b[92m",
                .bright_yellow => "\x1b[93m",
                .bright_blue => "\x1b[94m",
                .bright_magenta => "\x1b[95m",
                .bright_cyan => "\x1b[96m",
                .bright_white => "\x1b[97m",
                .bold => "\x1b[1m",
                .dim => "\x1b[2m",
                .reset => "\x1b[0m",
            };
            try t.writer.writeAll(color_string);
        },
        .windows_api => |wa| {
            const windows = std.os.windows;
            const attributes: windows.WORD = switch (color) {
                .black => 0,
                .red => windows.FOREGROUND_RED,
                .green => windows.FOREGROUND_GREEN,
                .yellow => windows.FOREGROUND_RED | windows.FOREGROUND_GREEN,
                .blue => windows.FOREGROUND_BLUE,
                .magenta => windows.FOREGROUND_RED | windows.FOREGROUND_BLUE,
                .cyan => windows.FOREGROUND_GREEN | windows.FOREGROUND_BLUE,
                .white => windows.FOREGROUND_RED | windows.FOREGROUND_GREEN | windows.FOREGROUND_BLUE,
                .bright_black => windows.FOREGROUND_INTENSITY,
                .bright_red => windows.FOREGROUND_RED | windows.FOREGROUND_INTENSITY,
                .bright_green => windows.FOREGROUND_GREEN | windows.FOREGROUND_INTENSITY,
                .bright_yellow => windows.FOREGROUND_RED | windows.FOREGROUND_GREEN | windows.FOREGROUND_INTENSITY,
                .bright_blue => windows.FOREGROUND_BLUE | windows.FOREGROUND_INTENSITY,
                .bright_magenta => windows.FOREGROUND_RED | windows.FOREGROUND_BLUE | windows.FOREGROUND_INTENSITY,
                .bright_cyan => windows.FOREGROUND_GREEN | windows.FOREGROUND_BLUE | windows.FOREGROUND_INTENSITY,
                .bright_white, .bold => windows.FOREGROUND_RED | windows.FOREGROUND_GREEN | windows.FOREGROUND_BLUE | windows.FOREGROUND_INTENSITY,
                // "dim" is not supported using basic character attributes, but let's still make it do *something*.
                // This matches the old behavior of TTY.Color before the bright variants were added.
                .dim => windows.FOREGROUND_INTENSITY,
                .reset => wa.reset_attributes,
            };
            try t.writer.flush();
            var set_text_attribute = windows.CONSOLE.USER_IO.SET_TEXT_ATTRIBUTE(attributes);
            switch (try set_text_attribute.operate(wa.io, wa.file)) {
                .SUCCESS => {},
                else => |status| return windows.unexpectedStatus(status),
            }
        },
    }
}
