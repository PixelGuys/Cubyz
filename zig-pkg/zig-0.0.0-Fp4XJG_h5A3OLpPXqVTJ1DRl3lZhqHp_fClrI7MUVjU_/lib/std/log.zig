//! std.log is a standardized interface for logging which allows for the logging
//! of programs and libraries using this interface to be formatted and filtered
//! by the implementer of the `std.options.logFn` function.
//!
//! Each log message has an associated scope enum, which can be used to give
//! context to the logging. The logging functions in std.log implicitly use a
//! scope of .default.
//!
//! A logging namespace using a custom scope can be created using the
//! std.log.scoped function, passing the scope as an argument; the logging
//! functions in the resulting struct use the provided scope parameter.
//! For example, a library called 'libfoo' might use
//! `const log = std.log.scoped(.libfoo);` to use .libfoo as the scope of its
//! log messages.
//!
//! For an example implementation of the `logFn` function, see `defaultLog`,
//! which is the default implementation. It outputs to stderr, using color if
//! supported. Its output looks like this:
//! ```
//! error: this is an error
//! error(scope): this is an error with a non-default scope
//! warning: this is a warning
//! info: this is an informative message
//! debug: this is a debugging message
//! ```

const std = @import("std.zig");
const builtin = @import("builtin");

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

    /// Returns a string literal of the given level in full text form.
    pub fn asText(comptime self: Level) []const u8 {
        return switch (self) {
            .err => "error",
            .warn => "warning",
            .info => "info",
            .debug => "debug",
        };
    }
};

/// The default log level is based on build mode.
pub const default_level: Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
};

pub const ScopeLevel = struct {
    scope: @EnumLiteral(),
    level: Level,
};

fn log(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (comptime !logEnabled(level, scope)) return;

    std.options.logFn(level, scope, format, args);
}

/// Determine if a specific log message level and scope combination are enabled for logging.
pub fn logEnabled(comptime level: Level, comptime scope: @EnumLiteral()) bool {
    inline for (std.options.log_scope_levels) |scope_level| {
        if (scope_level.scope == scope) return @intFromEnum(level) <= @intFromEnum(scope_level.level);
    }
    return @intFromEnum(level) <= @intFromEnum(std.options.log_level);
}

pub const terminalMode = std.Options.logTerminalMode;

pub fn defaultTerminalMode() std.Io.Terminal.Mode {
    const stderr = std.debug.lockStderr(&.{}).terminal();
    std.debug.unlockStderr();
    return stderr.mode;
}

/// The default implementation for the log function. Custom log functions may
/// forward log messages to this function.
///
/// Uses a 64-byte buffer for formatted printing which is flushed before this
/// function returns.
pub fn defaultLog(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();
    return defaultLogFileTerminal(level, scope, format, args, stderr) catch {};
}

pub fn defaultLogFileTerminal(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
    t: std.Io.Terminal,
) std.Io.Writer.Error!void {
    t.setColor(switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    }) catch {};
    t.setColor(.bold) catch {};
    try t.writer.writeAll(level.asText());
    t.setColor(.reset) catch {};
    t.setColor(.dim) catch {};
    t.setColor(.bold) catch {};
    if (scope != .default) try t.writer.print("({t})", .{scope});
    try t.writer.writeAll(": ");
    t.setColor(.reset) catch {};
    try t.writer.print(format ++ "\n", args);
}

/// Returns a scoped logging namespace that logs all messages using the scope
/// provided here.
pub fn scoped(comptime scope: @EnumLiteral()) type {
    return struct {
        /// Log an error message. This log level is intended to be used
        /// when something has gone wrong. This might be recoverable or might
        /// be followed by the program exiting.
        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @branchHint(.cold);
            log(.err, scope, format, args);
        }

        /// Log a warning message. This log level is intended to be used if
        /// it is uncertain whether something has gone wrong or not, but the
        /// circumstances would be worth investigating.
        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.warn, scope, format, args);
        }

        /// Log an info message. This log level is intended to be used for
        /// general messages about the state of the program.
        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.info, scope, format, args);
        }

        /// Log a debug message. This log level is intended to be used for
        /// messages which are only useful for debugging.
        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.debug, scope, format, args);
        }
    };
}

pub const default_log_scope = .default;

/// The default scoped logging namespace.
pub const default = scoped(default_log_scope);

/// Log an error message using the default scope. This log level is intended to
/// be used when something has gone wrong. This might be recoverable or might
/// be followed by the program exiting.
pub const err = default.err;

/// Log a warning message using the default scope. This log level is intended
/// to be used if it is uncertain whether something has gone wrong or not, but
/// the circumstances would be worth investigating.
pub const warn = default.warn;

/// Log an info message using the default scope. This log level is intended to
/// be used for general messages about the state of the program.
pub const info = default.info;

/// Log a debug message using the default scope. This log level is intended to
/// be used for messages which are only useful for debugging.
pub const debug = default.debug;
