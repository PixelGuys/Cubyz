const Args = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

vector: Vector,

/// On WASI without libc, this is `void` because the environment has to be
/// queried and heap-allocated at runtime.
pub const Vector = switch (native_os) {
    .windows => []const u16, // WTF-16 encoded
    .wasi => switch (builtin.link_libc) {
        false => void,
        true => []const [*:0]const u8,
    },
    .freestanding, .other => void,
    else => []const [*:0]const u8,
};

/// Cross-platform access to command line one argument at a time.
pub const Iterator = struct {
    const Inner = switch (native_os) {
        .windows => Windows,
        .wasi => if (builtin.link_libc) Posix else Wasi,
        else => Posix,
    };

    inner: Inner,

    /// Initialize the args iterator. Consider using `initAllocator` instead
    /// for cross-platform compatibility.
    pub fn init(a: Args) Iterator {
        if (native_os == .wasi) @compileError("In WASI, use initAllocator instead.");
        if (native_os == .windows) @compileError("In Windows, use initAllocator instead.");
        return .{ .inner = .init(a) };
    }

    pub const InitError = Inner.InitError;

    /// You must deinitialize iterator's internal buffers by calling `deinit` when done.
    pub fn initAllocator(a: Args, gpa: Allocator) InitError!Iterator {
        if (native_os == .wasi and !builtin.link_libc) {
            return .{ .inner = try .init(gpa) };
        }
        if (native_os == .windows) {
            return .{ .inner = try .init(gpa, a.vector) };
        }

        return .{ .inner = .init(a) };
    }

    /// Return subsequent argument, or `null` if no more remaining.
    ///
    /// Returned slice is pointing to the iterator's internal buffer.
    /// On Windows, the result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
    /// On other platforms, the result is an opaque sequence of bytes with no particular encoding.
    pub fn next(it: *Iterator) ?[:0]const u8 {
        return it.inner.next();
    }

    /// Parse past 1 argument without capturing it.
    /// Returns `true` if skipped an arg, `false` if we are at the end.
    pub fn skip(it: *Iterator) bool {
        return it.inner.skip();
    }

    /// Required to release resources if the iterator was initialized with
    /// `initAllocator` function.
    pub fn deinit(it: *Iterator) void {
        // Unless we're targeting WASI or Windows, this is a no-op.
        if (native_os == .wasi and !builtin.link_libc) it.inner.deinit();
        if (native_os == .windows) it.inner.deinit();
    }

    /// Iterator that implements the Windows command-line parsing algorithm.
    ///
    /// The implementation is intended to be compatible with the post-2008 C runtime,
    /// but is *not* intended to be compatible with `CommandLineToArgvW` since
    /// `CommandLineToArgvW` uses the pre-2008 parsing rules.
    ///
    /// This iterator faithfully implements the parsing behavior observed from the C runtime with
    /// one exception: if the command-line string is empty, the iterator will immediately complete
    /// without returning any arguments (whereas the C runtime will return a single argument
    /// representing the name of the current executable).
    ///
    /// The essential parts of the algorithm are described in Microsoft's documentation:
    ///
    /// - https://learn.microsoft.com/en-us/cpp/cpp/main-function-command-line-args?view=msvc-170#parsing-c-command-line-arguments
    ///
    /// David Deley explains some additional undocumented quirks in great detail:
    ///
    /// - https://daviddeley.com/autohotkey/parameters/parameters.htm#WINCRULES
    pub const Windows = struct {
        allocator: Allocator,
        /// Encoded as WTF-16 LE.
        cmd_line: []const u16,
        index: usize = 0,
        /// Owned by the iterator. Long enough to hold contiguous NUL-terminated slices
        /// of each argument encoded as WTF-8.
        buffer: []u8,
        start: usize = 0,
        end: usize = 0,

        pub const InitError = error{OutOfMemory};

        /// `cmd_line_w` *must* be a WTF16-LE-encoded string.
        ///
        /// The iterator stores and uses `cmd_line_w`, so its memory must be valid for
        /// at least as long as the returned Windows.
        pub fn init(gpa: Allocator, cmd_line_w: []const u16) Windows.InitError!Windows {
            const wtf8_len = std.unicode.calcWtf8Len(cmd_line_w);

            // This buffer must be large enough to contain contiguous NUL-terminated slices
            // of each argument.
            // - During parsing, the length of a parsed argument will always be equal to
            //   to less than its unparsed length
            // - The first argument needs one extra byte of space allocated for its NUL
            //   terminator, but for each subsequent argument the necessary whitespace
            //   between arguments guarantees room for their NUL terminator(s).
            const buffer = try gpa.alloc(u8, wtf8_len + 1);
            errdefer gpa.free(buffer);

            return .{
                .allocator = gpa,
                .cmd_line = cmd_line_w,
                .buffer = buffer,
            };
        }

        /// Returns the next argument and advances the iterator. Returns `null` if at the end of the
        /// command-line string. The iterator owns the returned slice.
        /// The result is encoded as [WTF-8](https://wtf-8.codeberg.page/).
        pub fn next(self: *Windows) ?[:0]const u8 {
            return self.nextWithStrategy(next_strategy);
        }

        /// Skips the next argument and advances the iterator. Returns `true` if an argument was
        /// skipped, `false` if at the end of the command-line string.
        pub fn skip(self: *Windows) bool {
            return self.nextWithStrategy(skip_strategy);
        }

        const next_strategy = struct {
            const T = ?[:0]const u8;

            const eof = null;

            /// Returns '\' if any backslashes are emitted, otherwise returns `last_emitted_code_unit`.
            fn emitBackslashes(self: *Windows, count: usize, last_emitted_code_unit: ?u16) ?u16 {
                for (0..count) |_| {
                    self.buffer[self.end] = '\\';
                    self.end += 1;
                }
                return if (count != 0) '\\' else last_emitted_code_unit;
            }

            /// If `last_emitted_code_unit` and `code_unit` form a surrogate pair, then
            /// the previously emitted high surrogate is overwritten by the codepoint encoded
            /// by the surrogate pair, and `null` is returned.
            /// Otherwise, `code_unit` is emitted and returned.
            fn emitCharacter(self: *Windows, code_unit: u16, last_emitted_code_unit: ?u16) ?u16 {
                // Because we are emitting WTF-8, we need to
                // check to see if we've emitted two consecutive surrogate
                // codepoints that form a valid surrogate pair in order
                // to ensure that we're always emitting well-formed WTF-8
                // (https://wtf-8.codeberg.page/#concatenating).
                //
                // If we do have a valid surrogate pair, we need to emit
                // the UTF-8 sequence for the codepoint that they encode
                // instead of the WTF-8 encoding for the two surrogate pairs
                // separately.
                //
                // This is relevant when dealing with a WTF-16 encoded
                // command line like this:
                // "<0xD801>"<0xDC37>
                // which would get parsed and converted to WTF-8 as:
                // <0xED><0xA0><0x81><0xED><0xB0><0xB7>
                // but instead, we need to recognize the surrogate pair
                // and emit the codepoint it encodes, which in this
                // example is U+10437 (𐐷), which is encoded in UTF-8 as:
                // <0xF0><0x90><0x90><0xB7>
                if (last_emitted_code_unit != null and
                    std.unicode.utf16IsLowSurrogate(code_unit) and
                    std.unicode.utf16IsHighSurrogate(last_emitted_code_unit.?))
                {
                    const codepoint = std.unicode.utf16DecodeSurrogatePair(&.{ last_emitted_code_unit.?, code_unit }) catch unreachable;

                    // Unpaired surrogate is 3 bytes long
                    const dest = self.buffer[self.end - 3 ..];
                    const len = std.unicode.utf8Encode(codepoint, dest) catch unreachable;
                    // All codepoints that require a surrogate pair (> U+FFFF) are encoded as 4 bytes
                    assert(len == 4);
                    self.end += 1;
                    return null;
                }

                const wtf8_len = std.unicode.wtf8Encode(code_unit, self.buffer[self.end..]) catch unreachable;
                self.end += wtf8_len;
                return code_unit;
            }

            fn yieldArg(self: *Windows) [:0]const u8 {
                self.buffer[self.end] = 0;
                const arg = self.buffer[self.start..self.end :0];
                self.end += 1;
                self.start = self.end;
                return arg;
            }
        };

        const skip_strategy = struct {
            const T = bool;

            const eof = false;

            fn emitBackslashes(_: *Windows, _: usize, last_emitted_code_unit: ?u16) ?u16 {
                return last_emitted_code_unit;
            }

            fn emitCharacter(_: *Windows, _: u16, last_emitted_code_unit: ?u16) ?u16 {
                return last_emitted_code_unit;
            }

            fn yieldArg(_: *Windows) bool {
                return true;
            }
        };

        fn nextWithStrategy(self: *Windows, comptime strategy: type) strategy.T {
            var last_emitted_code_unit: ?u16 = null;
            // The first argument (the executable name) uses different parsing rules.
            if (self.index == 0) {
                if (self.cmd_line.len == 0 or self.cmd_line[0] == 0) {
                    // Immediately complete the iterator.
                    // The C runtime would return the name of the current executable here.
                    return strategy.eof;
                }

                var inside_quotes = false;
                while (true) : (self.index += 1) {
                    const char = if (self.index != self.cmd_line.len)
                        std.mem.littleToNative(u16, self.cmd_line[self.index])
                    else
                        0;
                    switch (char) {
                        0 => {
                            return strategy.yieldArg(self);
                        },
                        '"' => {
                            inside_quotes = !inside_quotes;
                        },
                        ' ', '\t' => {
                            if (inside_quotes) {
                                last_emitted_code_unit = strategy.emitCharacter(self, char, last_emitted_code_unit);
                            } else {
                                self.index += 1;
                                return strategy.yieldArg(self);
                            }
                        },
                        else => {
                            last_emitted_code_unit = strategy.emitCharacter(self, char, last_emitted_code_unit);
                        },
                    }
                }
            }

            // Skip spaces and tabs. The iterator completes if we reach the end of the string here.
            while (true) : (self.index += 1) {
                const char = if (self.index != self.cmd_line.len)
                    std.mem.littleToNative(u16, self.cmd_line[self.index])
                else
                    0;
                switch (char) {
                    0 => return strategy.eof,
                    ' ', '\t' => continue,
                    else => break,
                }
            }

            // Parsing rules for subsequent arguments:
            //
            // - The end of the string always terminates the current argument.
            // - When not in 'inside_quotes' mode, a space or tab terminates the current argument.
            // - 2n backslashes followed by a quote emit n backslashes (note: n can be zero).
            //   If in 'inside_quotes' and the quote is immediately followed by a second quote,
            //   one quote is emitted and the other is skipped, otherwise, the quote is skipped
            //   and 'inside_quotes' is toggled.
            // - 2n + 1 backslashes followed by a quote emit n backslashes followed by a quote.
            // - n backslashes not followed by a quote emit n backslashes.
            var backslash_count: usize = 0;
            var inside_quotes = false;
            while (true) : (self.index += 1) {
                const char = if (self.index != self.cmd_line.len)
                    std.mem.littleToNative(u16, self.cmd_line[self.index])
                else
                    0;
                switch (char) {
                    0 => {
                        last_emitted_code_unit = strategy.emitBackslashes(self, backslash_count, last_emitted_code_unit);
                        return strategy.yieldArg(self);
                    },
                    ' ', '\t' => {
                        last_emitted_code_unit = strategy.emitBackslashes(self, backslash_count, last_emitted_code_unit);
                        backslash_count = 0;
                        if (inside_quotes) {
                            last_emitted_code_unit = strategy.emitCharacter(self, char, last_emitted_code_unit);
                        } else return strategy.yieldArg(self);
                    },
                    '"' => {
                        const char_is_escaped_quote = backslash_count % 2 != 0;
                        last_emitted_code_unit = strategy.emitBackslashes(self, backslash_count / 2, last_emitted_code_unit);
                        backslash_count = 0;
                        if (char_is_escaped_quote) {
                            last_emitted_code_unit = strategy.emitCharacter(self, '"', last_emitted_code_unit);
                        } else {
                            if (inside_quotes and
                                self.index + 1 != self.cmd_line.len and
                                std.mem.littleToNative(u16, self.cmd_line[self.index + 1]) == '"')
                            {
                                last_emitted_code_unit = strategy.emitCharacter(self, '"', last_emitted_code_unit);
                                self.index += 1;
                            } else {
                                inside_quotes = !inside_quotes;
                            }
                        }
                    },
                    '\\' => {
                        backslash_count += 1;
                    },
                    else => {
                        last_emitted_code_unit = strategy.emitBackslashes(self, backslash_count, last_emitted_code_unit);
                        backslash_count = 0;
                        last_emitted_code_unit = strategy.emitCharacter(self, char, last_emitted_code_unit);
                    },
                }
            }
        }

        /// Frees the iterator's copy of the command-line string and all previously returned
        /// argument slices.
        pub fn deinit(self: *Windows) void {
            self.allocator.free(self.buffer);
        }
    };

    pub const Posix = struct {
        remaining: Vector,

        pub const InitError = error{};

        pub fn init(a: Args) Posix {
            return .{ .remaining = a.vector };
        }

        pub fn next(it: *Posix) ?[:0]const u8 {
            if (it.remaining.len == 0) return null;
            const arg = it.remaining[0];
            it.remaining = it.remaining[1..];
            return std.mem.sliceTo(arg, 0);
        }

        pub fn skip(it: *Posix) bool {
            if (it.remaining.len == 0) return false;
            it.remaining = it.remaining[1..];
            return true;
        }
    };

    pub const Wasi = struct {
        allocator: Allocator,
        index: usize,
        args: [][:0]u8,

        pub const InitError = error{OutOfMemory} || std.posix.UnexpectedError;

        /// You must call deinit to free the internal buffer of the
        /// iterator after you are done.
        pub fn init(allocator: Allocator) Wasi.InitError!Wasi {
            const fetched_args = try Wasi.internalInit(allocator);
            return Wasi{
                .allocator = allocator,
                .index = 0,
                .args = fetched_args,
            };
        }

        fn internalInit(allocator: Allocator) Wasi.InitError![][:0]u8 {
            var count: usize = undefined;
            var buf_size: usize = undefined;

            switch (std.os.wasi.args_sizes_get(&count, &buf_size)) {
                .SUCCESS => {},
                else => |err| return std.posix.unexpectedErrno(err),
            }

            if (count == 0) {
                return &[_][:0]u8{};
            }

            const argv = try allocator.alloc([*:0]u8, count);
            defer allocator.free(argv);

            const argv_buf = try allocator.alloc(u8, buf_size);

            switch (std.os.wasi.args_get(argv.ptr, argv_buf.ptr)) {
                .SUCCESS => {},
                else => |err| return std.posix.unexpectedErrno(err),
            }

            var result_args = try allocator.alloc([:0]u8, count);
            var i: usize = 0;
            while (i < count) : (i += 1) {
                result_args[i] = std.mem.sliceTo(argv[i], 0);
            }

            return result_args;
        }

        pub fn next(self: *Wasi) ?[:0]const u8 {
            if (self.index == self.args.len) return null;

            const arg = self.args[self.index];
            self.index += 1;
            return arg;
        }

        pub fn skip(self: *Wasi) bool {
            if (self.index == self.args.len) return false;

            self.index += 1;
            return true;
        }

        /// Call to free the internal buffer of the iterator.
        pub fn deinit(self: *Wasi) void {
            // Nothing is allocated when there are no args
            if (self.args.len == 0) return;

            const last_item = self.args[self.args.len - 1];
            const last_byte_addr = @intFromPtr(last_item.ptr) + last_item.len + 1; // null terminated
            const first_item_ptr = self.args[0].ptr;
            const len = last_byte_addr - @intFromPtr(first_item_ptr);
            self.allocator.free(first_item_ptr[0..len]);
            self.allocator.free(self.args);
        }
    };
};

/// Holds the command-line arguments, with the program name as the first entry.
/// Use `iterateAllocator` for cross-platform code.
pub fn iterate(a: Args) Iterator {
    return .init(a);
}

/// You must deinitialize iterator's internal buffers by calling `deinit` when
/// done.
pub fn iterateAllocator(a: Args, gpa: Allocator) Iterator.InitError!Iterator {
    return .initAllocator(a, gpa);
}

pub const ToSliceError = Iterator.Windows.InitError || Iterator.Wasi.InitError;

/// Returned value may reference several allocations and may point into `a`.
/// Thefore, an arena-style allocator must be used.
///
/// * On Windows, the result is encoded as
///   [WTF-8](https://wtf-8.codeberg.page/).
/// * On other platforms, the result is an opaque sequence of bytes with no
///   particular encoding.
///
/// See also:
/// * `iterate`
/// * `iterateAllocator`
pub fn toSlice(a: Args, arena: Allocator) ToSliceError![]const [:0]const u8 {
    if (native_os == .windows) {
        var it = try a.iterateAllocator(arena);
        var contents: std.ArrayList(u8) = .empty;
        var slice_list: std.ArrayList(usize) = .empty;
        while (it.next()) |arg| {
            try contents.appendSlice(arena, arg[0 .. arg.len + 1]);
            try slice_list.append(arena, arg.len);
        }
        const contents_slice = contents.items;
        const slice_sizes = slice_list.items;
        const slice_list_bytes = std.math.mul(usize, @sizeOf([]u8), slice_sizes.len) catch return error.OutOfMemory;
        const total_bytes = std.math.add(usize, slice_list_bytes, contents_slice.len) catch return error.OutOfMemory;
        const buf = try arena.alignedAlloc(u8, .of([]u8), total_bytes);
        errdefer arena.free(buf);

        const result_slice_list = std.mem.bytesAsSlice([:0]u8, buf[0..slice_list_bytes]);
        const result_contents = buf[slice_list_bytes..];
        @memcpy(result_contents[0..contents_slice.len], contents_slice);

        var contents_index: usize = 0;
        for (slice_sizes, 0..) |len, i| {
            const new_index = contents_index + len;
            result_slice_list[i] = result_contents[contents_index..new_index :0];
            contents_index = new_index + 1;
        }

        return result_slice_list;
    } else if (native_os == .wasi and !builtin.link_libc) {
        var count: usize = undefined;
        var buf_size: usize = undefined;

        switch (std.os.wasi.args_sizes_get(&count, &buf_size)) {
            .SUCCESS => {},
            else => |err| return std.posix.unexpectedErrno(err),
        }

        if (count == 0) return &.{};

        const argv = try arena.alloc([*:0]u8, count);
        const argv_buf = try arena.alloc(u8, buf_size);

        switch (std.os.wasi.args_get(argv.ptr, argv_buf.ptr)) {
            .SUCCESS => {},
            else => |err| return std.posix.unexpectedErrno(err),
        }

        const args = try arena.alloc([:0]const u8, count);
        for (args, argv) |*dst, src| dst.* = std.mem.sliceTo(src, 0);
        return args;
    } else {
        const args = try arena.alloc([:0]const u8, a.vector.len);
        for (args, a.vector) |*dst, src| dst.* = std.mem.sliceTo(src, 0);
        return args;
    }
}

test "Iterator.Windows" {
    const t = testIteratorWindows;

    try t(
        \\"C:\Program Files\zig\zig.exe" run .\src\main.zig -target x86_64-windows-gnu -O ReleaseSafe -- --emoji=🗿 --eval="new Regex(\"Dwayne \\\"The Rock\\\" Johnson\")"
    , &.{
        \\C:\Program Files\zig\zig.exe
        ,
        \\run
        ,
        \\.\src\main.zig
        ,
        \\-target
        ,
        \\x86_64-windows-gnu
        ,
        \\-O
        ,
        \\ReleaseSafe
        ,
        \\--
        ,
        \\--emoji=🗿
        ,
        \\--eval=new Regex("Dwayne \"The Rock\" Johnson")
        ,
    });

    // Empty
    try t("", &.{});

    // Separators
    try t("aa bb cc", &.{ "aa", "bb", "cc" });
    try t("aa\tbb\tcc", &.{ "aa", "bb", "cc" });
    try t("aa\nbb\ncc", &.{"aa\nbb\ncc"});
    try t("aa\r\nbb\r\ncc", &.{"aa\r\nbb\r\ncc"});
    try t("aa\rbb\rcc", &.{"aa\rbb\rcc"});
    try t("aa\x07bb\x07cc", &.{"aa\x07bb\x07cc"});
    try t("aa\x7Fbb\x7Fcc", &.{"aa\x7Fbb\x7Fcc"});
    try t("aa🦎bb🦎cc", &.{"aa🦎bb🦎cc"});

    // Leading/trailing whitespace
    try t("  ", &.{""});
    try t("  aa  bb  ", &.{ "", "aa", "bb" });
    try t("\t\t", &.{""});
    try t("\t\taa\t\tbb\t\t", &.{ "", "aa", "bb" });
    try t("\n\n", &.{"\n\n"});
    try t("\n\naa\n\nbb\n\n", &.{"\n\naa\n\nbb\n\n"});

    // Executable name with quotes/backslashes
    try t("\"aa bb\tcc\ndd\"", &.{"aa bb\tcc\ndd"});
    try t("\"", &.{""});
    try t("\"\"", &.{""});
    try t("\"\"\"", &.{""});
    try t("\"\"\"\"", &.{""});
    try t("\"\"\"\"\"", &.{""});
    try t("aa\"bb\"cc\"dd", &.{"aabbccdd"});
    try t("aa\"bb cc\"dd", &.{"aabb ccdd"});
    try t("\"aa\\\"bb\"", &.{"aa\\bb"});
    try t("\"aa\\\\\"", &.{"aa\\\\"});
    try t("aa\\\"bb", &.{"aa\\bb"});
    try t("aa\\\\\"bb", &.{"aa\\\\bb"});

    // Arguments with quotes/backslashes
    try t(". \"aa bb\tcc\ndd\"", &.{ ".", "aa bb\tcc\ndd" });
    try t(". aa\" \"bb\"\t\"cc\"\n\"dd\"", &.{ ".", "aa bb\tcc\ndd" });
    try t(". ", &.{"."});
    try t(". \"", &.{ ".", "" });
    try t(". \"\"", &.{ ".", "" });
    try t(". \"\"\"", &.{ ".", "\"" });
    try t(". \"\"\"\"", &.{ ".", "\"" });
    try t(". \"\"\"\"\"", &.{ ".", "\"\"" });
    try t(". \"\"\"\"\"\"", &.{ ".", "\"\"" });
    try t(". \" \"", &.{ ".", " " });
    try t(". \" \"\"", &.{ ".", " \"" });
    try t(". \" \"\"\"", &.{ ".", " \"" });
    try t(". \" \"\"\"\"", &.{ ".", " \"\"" });
    try t(". \" \"\"\"\"\"", &.{ ".", " \"\"" });
    try t(". \" \"\"\"\"\"\"", &.{ ".", " \"\"\"" });
    try t(". \\\"", &.{ ".", "\"" });
    try t(". \\\"\"", &.{ ".", "\"" });
    try t(". \\\"\"\"", &.{ ".", "\"" });
    try t(". \\\"\"\"\"", &.{ ".", "\"\"" });
    try t(". \\\"\"\"\"\"", &.{ ".", "\"\"" });
    try t(". \\\"\"\"\"\"\"", &.{ ".", "\"\"\"" });
    try t(". \" \\\"", &.{ ".", " \"" });
    try t(". \" \\\"\"", &.{ ".", " \"" });
    try t(". \" \\\"\"\"", &.{ ".", " \"\"" });
    try t(". \" \\\"\"\"\"", &.{ ".", " \"\"" });
    try t(". \" \\\"\"\"\"\"", &.{ ".", " \"\"\"" });
    try t(". \" \\\"\"\"\"\"\"", &.{ ".", " \"\"\"" });
    try t(". aa\\bb\\\\cc\\\\\\dd", &.{ ".", "aa\\bb\\\\cc\\\\\\dd" });
    try t(". \\\\\\\"aa bb\"", &.{ ".", "\\\"aa", "bb" });
    try t(". \\\\\\\\\"aa bb\"", &.{ ".", "\\\\aa bb" });

    // From https://learn.microsoft.com/en-us/cpp/cpp/main-function-command-line-args#results-of-parsing-command-lines
    try t(
        \\foo.exe "abc" d e
    , &.{ "foo.exe", "abc", "d", "e" });
    try t(
        \\foo.exe a\\b d"e f"g h
    , &.{ "foo.exe", "a\\\\b", "de fg", "h" });
    try t(
        \\foo.exe a\\\"b c d
    , &.{ "foo.exe", "a\\\"b", "c", "d" });
    try t(
        \\foo.exe a\\\\"b c" d e
    , &.{ "foo.exe", "a\\\\b c", "d", "e" });
    try t(
        \\foo.exe a"b"" c d
    , &.{ "foo.exe", "ab\" c d" });

    // From https://daviddeley.com/autohotkey/parameters/parameters.htm#WINCRULESEX
    try t("foo.exe CallMeIshmael", &.{ "foo.exe", "CallMeIshmael" });
    try t("foo.exe \"Call Me Ishmael\"", &.{ "foo.exe", "Call Me Ishmael" });
    try t("foo.exe Cal\"l Me I\"shmael", &.{ "foo.exe", "Call Me Ishmael" });
    try t("foo.exe CallMe\\\"Ishmael", &.{ "foo.exe", "CallMe\"Ishmael" });
    try t("foo.exe \"CallMe\\\"Ishmael\"", &.{ "foo.exe", "CallMe\"Ishmael" });
    try t("foo.exe \"Call Me Ishmael\\\\\"", &.{ "foo.exe", "Call Me Ishmael\\" });
    try t("foo.exe \"CallMe\\\\\\\"Ishmael\"", &.{ "foo.exe", "CallMe\\\"Ishmael" });
    try t("foo.exe a\\\\\\b", &.{ "foo.exe", "a\\\\\\b" });
    try t("foo.exe \"a\\\\\\b\"", &.{ "foo.exe", "a\\\\\\b" });

    // Surrogate pair encoding of 𐐷 separated by quotes.
    // Encoded as WTF-16:
    // "<0xD801>"<0xDC37>
    // Encoded as WTF-8:
    // "<0xED><0xA0><0x81>"<0xED><0xB0><0xB7>
    // During parsing, the quotes drop out and the surrogate pair
    // should end up encoded as its normal UTF-8 representation.
    try t("foo.exe \"\xed\xa0\x81\"\xed\xb0\xb7", &.{ "foo.exe", "𐐷" });
}

fn testIteratorWindows(cmd_line: []const u8, expected_args: []const []const u8) !void {
    const cmd_line_w = try std.unicode.wtf8ToWtf16LeAllocZ(testing.allocator, cmd_line);
    defer testing.allocator.free(cmd_line_w);

    // next
    {
        var it = try Iterator.Windows.init(testing.allocator, cmd_line_w);
        defer it.deinit();

        for (expected_args) |expected| {
            if (it.next()) |actual| {
                try testing.expectEqualStrings(expected, actual);
            } else {
                return error.TestUnexpectedResult;
            }
        }
        try testing.expect(it.next() == null);
    }

    // skip
    {
        var it = try Iterator.Windows.init(testing.allocator, cmd_line_w);
        defer it.deinit();

        for (0..expected_args.len) |_| {
            try testing.expect(it.skip());
        }
        try testing.expect(!it.skip());
    }
}

test "general parsing" {
    try testGeneralCmdLine("a   b\tc d", &.{ "a", "b", "c", "d" });
    try testGeneralCmdLine("\"abc\" d e", &.{ "abc", "d", "e" });
    try testGeneralCmdLine("a\\\\\\b d\"e f\"g h", &.{ "a\\\\\\b", "de fg", "h" });
    try testGeneralCmdLine("a\\\\\\\"b c d", &.{ "a\\\"b", "c", "d" });
    try testGeneralCmdLine("a\\\\\\\\\"b c\" d e", &.{ "a\\\\b c", "d", "e" });
    try testGeneralCmdLine("a   b\tc \"d f", &.{ "a", "b", "c", "d f" });
    try testGeneralCmdLine("j k l\\", &.{ "j", "k", "l\\" });
    try testGeneralCmdLine("\"\" x y z\\\\", &.{ "", "x", "y", "z\\\\" });

    try testGeneralCmdLine("\".\\..\\zig-cache\\build\" \"bin\\zig.exe\" \".\\..\" \".\\..\\zig-cache\" \"--help\"", &.{
        ".\\..\\zig-cache\\build",
        "bin\\zig.exe",
        ".\\..",
        ".\\..\\zig-cache",
        "--help",
    });

    try testGeneralCmdLine(
        \\ 'foo' "bar"
    , &.{ "'foo'", "bar" });
}

fn testGeneralCmdLine(input_cmd_line: []const u8, expected_args: []const []const u8) !void {
    var it = try IteratorGeneral(.{}).init(std.testing.allocator, input_cmd_line);
    defer it.deinit();
    for (expected_args) |expected_arg| {
        const arg = it.next().?;
        try testing.expectEqualStrings(expected_arg, arg);
    }
    try testing.expect(it.next() == null);
}

/// Optional parameters for `IteratorGeneral`
pub const IteratorGeneralOptions = struct {
    comments: bool = false,
    single_quotes: bool = false,
};

/// A general Iterator to parse a string into a set of arguments
pub fn IteratorGeneral(comptime options: IteratorGeneralOptions) type {
    return struct {
        allocator: Allocator,
        index: usize = 0,
        cmd_line: []const u8,

        /// Should the cmd_line field be free'd (using the allocator) on deinit()?
        free_cmd_line_on_deinit: bool,

        /// buffer MUST be long enough to hold the cmd_line plus a null terminator.
        /// buffer will we free'd (using the allocator) on deinit()
        buffer: []u8,
        start: usize = 0,
        end: usize = 0,

        pub const Self = @This();

        pub const InitError = error{OutOfMemory};

        /// cmd_line_utf8 MUST remain valid and constant while using this instance
        pub fn init(allocator: Allocator, cmd_line_utf8: []const u8) InitError!Self {
            const buffer = try allocator.alloc(u8, cmd_line_utf8.len + 1);
            errdefer allocator.free(buffer);

            return Self{
                .allocator = allocator,
                .cmd_line = cmd_line_utf8,
                .free_cmd_line_on_deinit = false,
                .buffer = buffer,
            };
        }

        /// cmd_line_utf8 will be free'd (with the allocator) on deinit()
        pub fn initTakeOwnership(allocator: Allocator, cmd_line_utf8: []const u8) InitError!Self {
            const buffer = try allocator.alloc(u8, cmd_line_utf8.len + 1);
            errdefer allocator.free(buffer);

            return Self{
                .allocator = allocator,
                .cmd_line = cmd_line_utf8,
                .free_cmd_line_on_deinit = true,
                .buffer = buffer,
            };
        }

        // Skips over whitespace in the cmd_line.
        // Returns false if the terminating sentinel is reached, true otherwise.
        // Also skips over comments (if supported).
        fn skipWhitespace(self: *Self) bool {
            while (true) : (self.index += 1) {
                const character = if (self.index != self.cmd_line.len) self.cmd_line[self.index] else 0;
                switch (character) {
                    0 => return false,
                    ' ', '\t', '\r', '\n' => continue,
                    '#' => {
                        if (options.comments) {
                            while (true) : (self.index += 1) {
                                switch (self.cmd_line[self.index]) {
                                    '\n' => break,
                                    0 => return false,
                                    else => continue,
                                }
                            }
                            continue;
                        } else {
                            break;
                        }
                    },
                    else => break,
                }
            }
            return true;
        }

        pub fn skip(self: *Self) bool {
            if (!self.skipWhitespace()) {
                return false;
            }

            var backslash_count: usize = 0;
            var in_quote = false;
            while (true) : (self.index += 1) {
                const character = if (self.index != self.cmd_line.len) self.cmd_line[self.index] else 0;
                switch (character) {
                    0 => return true,
                    '"', '\'' => {
                        if (!options.single_quotes and character == '\'') {
                            backslash_count = 0;
                            continue;
                        }
                        const quote_is_real = backslash_count % 2 == 0;
                        if (quote_is_real) {
                            in_quote = !in_quote;
                        }
                    },
                    '\\' => {
                        backslash_count += 1;
                    },
                    ' ', '\t', '\r', '\n' => {
                        if (!in_quote) {
                            return true;
                        }
                        backslash_count = 0;
                    },
                    else => {
                        backslash_count = 0;
                        continue;
                    },
                }
            }
        }

        /// Returns a slice of the internal buffer that contains the next argument.
        /// Returns null when it reaches the end.
        pub fn next(self: *Self) ?[:0]const u8 {
            if (!self.skipWhitespace()) {
                return null;
            }

            var backslash_count: usize = 0;
            var in_quote = false;
            while (true) : (self.index += 1) {
                const character = if (self.index != self.cmd_line.len) self.cmd_line[self.index] else 0;
                switch (character) {
                    0 => {
                        self.emitBackslashes(backslash_count);
                        self.buffer[self.end] = 0;
                        const token = self.buffer[self.start..self.end :0];
                        self.end += 1;
                        self.start = self.end;
                        return token;
                    },
                    '"', '\'' => {
                        if (!options.single_quotes and character == '\'') {
                            self.emitBackslashes(backslash_count);
                            backslash_count = 0;
                            self.emitCharacter(character);
                            continue;
                        }
                        const quote_is_real = backslash_count % 2 == 0;
                        self.emitBackslashes(backslash_count / 2);
                        backslash_count = 0;

                        if (quote_is_real) {
                            in_quote = !in_quote;
                        } else {
                            self.emitCharacter('"');
                        }
                    },
                    '\\' => {
                        backslash_count += 1;
                    },
                    ' ', '\t', '\r', '\n' => {
                        self.emitBackslashes(backslash_count);
                        backslash_count = 0;
                        if (in_quote) {
                            self.emitCharacter(character);
                        } else {
                            self.buffer[self.end] = 0;
                            const token = self.buffer[self.start..self.end :0];
                            self.end += 1;
                            self.start = self.end;
                            return token;
                        }
                    },
                    else => {
                        self.emitBackslashes(backslash_count);
                        backslash_count = 0;
                        self.emitCharacter(character);
                    },
                }
            }
        }

        fn emitBackslashes(self: *Self, emit_count: usize) void {
            var i: usize = 0;
            while (i < emit_count) : (i += 1) {
                self.emitCharacter('\\');
            }
        }

        fn emitCharacter(self: *Self, char: u8) void {
            self.buffer[self.end] = char;
            self.end += 1;
        }

        /// Call to free the internal buffer of the iterator.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);

            if (self.free_cmd_line_on_deinit) {
                self.allocator.free(self.cmd_line);
            }
        }
    };
}

test "response file arg parsing" {
    try testResponseFileCmdLine(
        \\a b
        \\c d\
    , &.{ "a", "b", "c", "d\\" });
    try testResponseFileCmdLine("a b c d\\", &.{ "a", "b", "c", "d\\" });

    try testResponseFileCmdLine(
        \\j
        \\ k l # this is a comment \\ \\\ \\\\ "none" "\\" "\\\"
        \\ "m" #another comment
        \\
    , &.{ "j", "k", "l", "m" });

    try testResponseFileCmdLine(
        \\ "" q ""
        \\ "r s # t" "u\" v" #another comment
        \\
    , &.{ "", "q", "", "r s # t", "u\" v" });

    try testResponseFileCmdLine(
        \\ -l"advapi32" a# b#c d#
        \\e\\\
    , &.{ "-ladvapi32", "a#", "b#c", "d#", "e\\\\\\" });

    try testResponseFileCmdLine(
        \\ 'foo' "bar"
    , &.{ "foo", "bar" });
}

fn testResponseFileCmdLine(input_cmd_line: []const u8, expected_args: []const []const u8) !void {
    var it = try IteratorGeneral(.{ .comments = true, .single_quotes = true })
        .init(std.testing.allocator, input_cmd_line);
    defer it.deinit();
    for (expected_args) |expected_arg| {
        const arg = it.next().?;
        try testing.expectEqualStrings(expected_arg, arg);
    }
    try testing.expect(it.next() == null);
}
