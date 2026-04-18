const Environ = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;
const unicode = std.unicode;
const posix = std.posix;
const mem = std.mem;

/// Unmodified, unprocessed data provided by the operating system.
block: Block,

pub const empty: Environ = .{ .block = .empty };

/// On WASI without libc, this is `void` because the environment has to be
/// queried and heap-allocated at runtime.
///
/// On Windows, the memory pointed at by the PEB changes when the environment
/// is modified, so a long-lived pointer cannot be used. Therefore, on this
/// operating system `void` is also used.
pub const Block = switch (native_os) {
    .windows => GlobalBlock,
    .wasi, .emscripten => switch (builtin.link_libc) {
        false => GlobalBlock,
        true => PosixBlock,
    },
    .freestanding, .other => GlobalBlock,
    else => PosixBlock,
};

pub const GlobalBlock = struct {
    use_global: bool,

    pub const empty: GlobalBlock = .{ .use_global = false };
    pub const global: GlobalBlock = .{ .use_global = true };

    pub fn deinit(_: GlobalBlock, _: Allocator) void {}

    pub fn isEmpty(block: GlobalBlock) bool {
        return !block.use_global;
    }
};

pub const PosixBlock = struct {
    slice: [:null]const ?[*:0]const u8,

    pub const empty: PosixBlock = .{ .slice = &.{} };

    pub fn deinit(block: PosixBlock, gpa: Allocator) void {
        for (block.slice) |entry| gpa.free(mem.span(entry.?));
        gpa.free(block.slice);
    }

    pub fn isEmpty(block: PosixBlock) bool {
        return block.slice.len == 0;
    }

    pub const View = struct {
        slice: []const [*:0]const u8,

        pub fn isEmpty(v: View) bool {
            return v.slice.len == 0;
        }
    };
    pub fn view(block: PosixBlock) View {
        return .{ .slice = @ptrCast(block.slice) };
    }
};

pub const WindowsBlock = struct {
    slice: [:0]const u16,

    pub const empty: WindowsBlock = .{ .slice = &.{0} };

    pub fn deinit(block: WindowsBlock, gpa: Allocator) void {
        gpa.free(block.slice);
    }

    pub fn isEmpty(block: WindowsBlock) bool {
        return block.slice[0] == 0;
    }

    pub const View = struct {
        ptr: [*:0]const u16,

        pub fn isEmpty(v: View) bool {
            return v.ptr[0] == 0;
        }
    };
    pub fn view(block: WindowsBlock) View {
        return .{ .ptr = block.slice.ptr };
    }
};

pub const Map = struct {
    array_hash_map: ArrayHashMap,
    allocator: Allocator,

    const ArrayHashMap = std.ArrayHashMapUnmanaged([]const u8, []const u8, EnvNameHashContext, false);

    pub const Size = usize;

    pub const EnvNameHashContext = struct {
        pub fn hash(self: @This(), s: []const u8) u32 {
            _ = self;
            switch (native_os) {
                else => return std.array_hash_map.hashString(s),
                .windows => {
                    var h = std.hash.Wyhash.init(0);
                    var it = unicode.Wtf8View.initUnchecked(s).iterator();
                    while (it.nextCodepoint()) |cp| {
                        const cp_upper = if (std.math.cast(u16, cp)) |wtf16|
                            std.os.windows.toUpperWtf16(wtf16)
                        else
                            cp;
                        h.update(&[_]u8{
                            @truncate(cp_upper >> 0),
                            @truncate(cp_upper >> 8),
                            @truncate(cp_upper >> 16),
                        });
                    }
                    return @truncate(h.final());
                },
            }
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return eqlKeys(a, b);
        }
    };
    fn eqlKeys(a: []const u8, b: []const u8) bool {
        return switch (native_os) {
            else => std.array_hash_map.eqlString(a, b),
            .windows => std.os.windows.eqlIgnoreCaseWtf8(a, b),
        };
    }

    pub fn validateKeyForPut(key: []const u8) bool {
        switch (native_os) {
            else => return key.len > 0 and mem.findAny(u8, key, &.{ 0, '=' }) == null,
            .windows => {
                if (!unicode.wtf8ValidateSlice(key)) return false;
                return key.len > 0 and key[0] != 0 and mem.findAnyPos(u8, key, 1, &.{ 0, '=' }) == null;
            },
        }
    }

    pub fn validateKeyForFetch(key: []const u8) bool {
        if (native_os == .windows and !unicode.wtf8ValidateSlice(key)) return false;
        return true;
    }

    /// Create a Map backed by a specific allocator.
    /// That allocator will be used for both backing allocations
    /// and string deduplication.
    pub fn init(allocator: Allocator) Map {
        return .{ .array_hash_map = .empty, .allocator = allocator };
    }

    /// Free the backing storage of the map, as well as all
    /// of the stored keys and values.
    pub fn deinit(self: *Map) void {
        const gpa = self.allocator;
        for (self.keys()) |key| gpa.free(key);
        for (self.values()) |value| gpa.free(value);
        self.array_hash_map.deinit(gpa);
        self.* = undefined;
    }

    pub fn keys(map: *const Map) [][]const u8 {
        return map.array_hash_map.keys();
    }

    pub fn values(map: *const Map) [][]const u8 {
        return map.array_hash_map.values();
    }

    pub fn putPosixBlock(map: *Map, view: PosixBlock.View) Allocator.Error!void {
        for (view.slice) |entry| {
            var entry_i: usize = 0;
            while (entry[entry_i] != 0 and entry[entry_i] != '=') : (entry_i += 1) {}
            const key = entry[0..entry_i];

            var end_i: usize = entry_i;
            while (entry[end_i] != 0) : (end_i += 1) {}
            const value = entry[entry_i + 1 .. end_i];

            try map.put(key, value);
        }
    }

    pub fn putWindowsBlock(map: *Map, view: WindowsBlock.View) Allocator.Error!void {
        var i: usize = 0;
        while (view.ptr[i] != 0) {
            const key_start = i;

            // There are some special environment variables that start with =,
            // so we need a special case to not treat = as a key/value separator
            // if it's the first character.
            // https://devblogs.microsoft.com/oldnewthing/20100506-00/?p=14133
            if (view.ptr[key_start] == '=') i += 1;

            while (view.ptr[i] != 0 and view.ptr[i] != '=') : (i += 1) {}
            const key_w = view.ptr[key_start..i];
            const key = try unicode.wtf16LeToWtf8Alloc(map.allocator, key_w);
            errdefer map.allocator.free(key);

            if (view.ptr[i] == '=') i += 1;

            const value_start = i;
            while (view.ptr[i] != 0) : (i += 1) {}
            const value_w = view.ptr[value_start..i];
            const value = try unicode.wtf16LeToWtf8Alloc(map.allocator, value_w);
            errdefer map.allocator.free(value);

            i += 1; // skip over null byte

            try map.putMove(key, value);
        }
    }

    /// Same as `put` but the key and value become owned by the Map rather
    /// than being copied.
    /// If `putMove` fails, the ownership of key and value does not transfer.
    ///
    /// Asserts that `key` is valid:
    /// - It cannot contain a NUL (`'\x00') byte.
    /// - It must have a length > 0.
    /// - It cannot contain `=`, except on Windows where only the first code point is allowed to be `=`.
    /// - On Windows, it must be valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn putMove(self: *Map, key: []u8, value: []u8) Allocator.Error!void {
        assert(validateKeyForPut(key));
        const gpa = self.allocator;
        const get_or_put = try self.array_hash_map.getOrPut(gpa, key);
        if (get_or_put.found_existing) {
            gpa.free(get_or_put.key_ptr.*);
            gpa.free(get_or_put.value_ptr.*);
            get_or_put.key_ptr.* = key;
        }
        get_or_put.value_ptr.* = value;
    }

    /// `key` and `value` are copied into the Map.
    ///
    /// Asserts that `key` is valid:
    /// - It cannot contain a NUL (`'\x00') byte.
    /// - It must have a length > 0.
    /// - It cannot contain `=`, except on Windows where only the first code point is allowed to be `=`.
    /// - On Windows, it must be valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn put(self: *Map, key: []const u8, value: []const u8) Allocator.Error!void {
        assert(validateKeyForPut(key));
        const gpa = self.allocator;
        const value_copy = try gpa.dupe(u8, value);
        errdefer gpa.free(value_copy);
        const get_or_put = try self.array_hash_map.getOrPut(gpa, key);
        errdefer {
            if (!get_or_put.found_existing) assert(self.array_hash_map.pop() != null);
        }
        if (get_or_put.found_existing) {
            gpa.free(get_or_put.value_ptr.*);
        } else {
            get_or_put.key_ptr.* = try gpa.dupe(u8, key);
        }
        get_or_put.value_ptr.* = value_copy;
    }

    /// Find the address of the value associated with a key.
    /// The returned pointer is invalidated if the map resizes.
    /// On Windows, asserts that `key` is valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn getPtr(self: Map, key: []const u8) ?*[]const u8 {
        assert(validateKeyForFetch(key));
        return self.array_hash_map.getPtr(key);
    }

    /// Return the map's copy of the value associated with
    /// a key.  The returned string is invalidated if this
    /// key is removed from the map.
    /// On Windows, asserts that `key` is valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn get(self: Map, key: []const u8) ?[]const u8 {
        assert(validateKeyForFetch(key));
        return self.array_hash_map.get(key);
    }

    /// On Windows, asserts that `key` is valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn contains(m: *const Map, key: []const u8) bool {
        assert(validateKeyForFetch(key));
        return m.array_hash_map.contains(key);
    }

    /// If there is an entry with a matching key, it is deleted from the hash
    /// map. The entry is removed from the underlying array by swapping it with
    /// the last element.
    ///
    /// Returns true if an entry was removed, false otherwise.
    ///
    /// This invalidates the value returned by get() for this key.
    /// On Windows, asserts that `key` is valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn swapRemove(self: *Map, key: []const u8) bool {
        assert(validateKeyForFetch(key));
        const kv = self.array_hash_map.fetchSwapRemove(key) orelse return false;
        const gpa = self.allocator;
        gpa.free(kv.key);
        gpa.free(kv.value);
        return true;
    }

    /// If there is an entry with a matching key, it is deleted from the map.
    /// The entry is removed from the underlying array by shifting all elements
    /// forward, thereby maintaining the current ordering.
    ///
    /// Returns true if an entry was removed, false otherwise.
    ///
    /// This invalidates the value returned by get() for this key.
    /// On Windows, asserts that `key` is valid [WTF-8](https://wtf-8.codeberg.page/).
    pub fn orderedRemove(self: *Map, key: []const u8) bool {
        assert(validateKeyForFetch(key));
        const kv = self.array_hash_map.fetchOrderedRemove(key) orelse return false;
        const gpa = self.allocator;
        gpa.free(kv.key);
        gpa.free(kv.value);
        return true;
    }

    /// Returns the number of KV pairs stored in the map.
    pub fn count(self: Map) Size {
        return self.array_hash_map.count();
    }

    /// Returns an iterator over entries in the map.
    pub fn iterator(self: *const Map) ArrayHashMap.Iterator {
        return self.array_hash_map.iterator();
    }

    /// Returns a full copy of `em` allocated with `gpa`, which is not necessarily
    /// the same allocator used to allocate `em`.
    pub fn clone(m: *const Map, gpa: Allocator) Allocator.Error!Map {
        // Since we need to dupe the keys and values, the only way for error handling to not be a
        // nightmare is to add keys to an empty map one-by-one. This could be avoided if this
        // abstraction were a bit less... OOP-esque.
        var new: Map = .init(gpa);
        errdefer new.deinit();
        try new.array_hash_map.ensureUnusedCapacity(gpa, m.array_hash_map.count());
        for (m.array_hash_map.keys(), m.array_hash_map.values()) |key, value| {
            try new.put(key, value);
        }
        return new;
    }

    /// Creates a null-delimited environment variable block in the format
    /// expected by POSIX, from a hash map plus options.
    pub fn createPosixBlock(
        map: *const Map,
        gpa: Allocator,
        options: CreatePosixBlockOptions,
    ) Allocator.Error!PosixBlock {
        const ZigProgressAction = enum { nothing, edit, delete, add };
        const zig_progress_action: ZigProgressAction = action: {
            const fd = options.zig_progress_fd orelse break :action .nothing;
            const exists = map.contains("ZIG_PROGRESS");
            if (fd >= 0) {
                break :action if (exists) .edit else .add;
            } else {
                if (exists) break :action .delete;
            }
            break :action .nothing;
        };

        const envp = try gpa.allocSentinel(?[*:0]u8, len: {
            var len: usize = map.count();
            switch (zig_progress_action) {
                .add => len += 1,
                .delete => len -= 1,
                .nothing, .edit => {},
            }
            break :len len;
        }, null);
        var envp_len: usize = 0;
        errdefer {
            envp[envp_len] = null;
            PosixBlock.deinit(.{ .slice = envp[0..envp_len :null] }, gpa);
        }

        if (zig_progress_action == .add) {
            envp[envp_len] = try std.fmt.allocPrintSentinel(gpa, "ZIG_PROGRESS={d}", .{options.zig_progress_fd.?}, 0);
            envp_len += 1;
        }

        for (map.keys(), map.values()) |key, value| {
            if (mem.eql(u8, key, "ZIG_PROGRESS")) switch (zig_progress_action) {
                .add => unreachable,
                .delete => continue,
                .edit => {
                    envp[envp_len] = try std.fmt.allocPrintSentinel(gpa, "{s}={d}", .{
                        key, options.zig_progress_fd.?,
                    }, 0);
                    envp_len += 1;
                    continue;
                },
                .nothing => {},
            };

            envp[envp_len] = try std.fmt.allocPrintSentinel(gpa, "{s}={s}", .{ key, value }, 0);
            envp_len += 1;
        }

        assert(envp_len == envp.len);
        return .{ .slice = envp };
    }

    /// Caller owns result.
    pub fn createWindowsBlock(
        map: *const Map,
        gpa: Allocator,
        options: CreateWindowsBlockOptions,
    ) error{ OutOfMemory, InvalidWtf8 }!WindowsBlock {
        // count bytes needed
        const max_chars_needed = max_chars_needed: {
            var max_chars_needed: usize = "\x00".len;
            if (options.zig_progress_handle) |handle| if (handle != std.os.windows.INVALID_HANDLE_VALUE) {
                max_chars_needed += std.fmt.count("ZIG_PROGRESS={d}\x00", .{@intFromPtr(handle)});
            };
            for (map.keys(), map.values()) |key, value| {
                if (options.zig_progress_handle != null and eqlKeys(key, "ZIG_PROGRESS")) continue;
                max_chars_needed += key.len + "=".len + value.len + "\x00".len;
            }
            break :max_chars_needed @max("\x00\x00".len, max_chars_needed);
        };
        const block = try gpa.alloc(u16, max_chars_needed);
        errdefer gpa.free(block);

        var i: usize = 0;
        if (options.zig_progress_handle) |handle| if (handle != std.os.windows.INVALID_HANDLE_VALUE) {
            @memcpy(
                block[i..][0.."ZIG_PROGRESS=".len],
                &[_]u16{ 'Z', 'I', 'G', '_', 'P', 'R', 'O', 'G', 'R', 'E', 'S', 'S', '=' },
            );
            i += "ZIG_PROGRESS=".len;
            var value_buf: [std.fmt.count("{d}", .{std.math.maxInt(usize)})]u8 = undefined;
            const value = std.fmt.bufPrint(&value_buf, "{d}", .{@intFromPtr(handle)}) catch unreachable;
            for (block[i..][0..value.len], value) |*r, v| r.* = v;
            i += value.len;
            block[i] = 0;
            i += 1;
        };
        for (map.keys(), map.values()) |key, value| {
            if (options.zig_progress_handle != null and eqlKeys(key, "ZIG_PROGRESS")) continue;
            i += try unicode.wtf8ToWtf16Le(block[i..], key);
            block[i] = '=';
            i += 1;
            i += try unicode.wtf8ToWtf16Le(block[i..], value);
            block[i] = 0;
            i += 1;
        }
        // An empty environment is a special case that requires a redundant
        // NUL terminator. CreateProcess will read the second code unit even
        // though theoretically the first should be enough to recognize that the
        // environment is empty (see https://nullprogram.com/blog/2023/08/23/)
        for (0..2) |_| {
            block[i] = 0;
            i += 1;
            if (i >= 2) break;
        } else unreachable;
        const reallocated = try gpa.realloc(block, i);
        return .{ .slice = reallocated[0 .. i - 1 :0] };
    }
};

pub const CreateMapError = error{
    OutOfMemory,
    /// WASI-only. `environ_sizes_get` or `environ_get` failed for an
    /// unanticipated, undocumented reason.
    Unexpected,
};

/// Allocates a `Map` and copies environment block into it.
pub fn createMap(env: Environ, allocator: Allocator) CreateMapError!Map {
    var map = Map.init(allocator);
    errdefer map.deinit();
    if (native_os == .windows) empty: {
        if (!env.block.use_global) break :empty;

        const peb = std.os.windows.peb();
        assert(std.os.windows.ntdll.RtlEnterCriticalSection(peb.FastPebLock) == .SUCCESS);
        defer assert(std.os.windows.ntdll.RtlLeaveCriticalSection(peb.FastPebLock) == .SUCCESS);
        try map.putWindowsBlock(.{ .ptr = peb.ProcessParameters.Environment });
    } else if (native_os == .wasi and !builtin.link_libc) empty: {
        if (!env.block.use_global) break :empty;

        var environ_count: usize = undefined;
        var environ_buf_size: usize = undefined;

        const environ_sizes_get_ret = std.os.wasi.environ_sizes_get(&environ_count, &environ_buf_size);
        if (environ_sizes_get_ret != .SUCCESS) {
            return posix.unexpectedErrno(environ_sizes_get_ret);
        }

        if (environ_count == 0) {
            return map;
        }

        const environ = try allocator.alloc([*:0]u8, environ_count);
        defer allocator.free(environ);
        const environ_buf = try allocator.alloc(u8, environ_buf_size);
        defer allocator.free(environ_buf);

        const environ_get_ret = std.os.wasi.environ_get(environ.ptr, environ_buf.ptr);
        if (environ_get_ret != .SUCCESS) {
            return posix.unexpectedErrno(environ_get_ret);
        }

        try map.putPosixBlock(.{ .slice = environ });
    } else try map.putPosixBlock(env.block.view());
    return map;
}

pub const ContainsError = error{
    OutOfMemory,
    /// On Windows, environment variable keys provided by the user must be
    /// valid [WTF-8](https://wtf-8.codeberg.page/). This error is unreachable
    /// if the key is statically known to be valid.
    InvalidWtf8,
    /// WASI-only. `environ_sizes_get` or `environ_get` failed for an
    /// unexpected reason.
    Unexpected,
};

/// On Windows, if `key` is not valid [WTF-8](https://wtf-8.codeberg.page/),
/// then `error.InvalidWtf8` is returned.
///
/// See also:
/// * `createMap`
/// * `containsConstant`
/// * `containsUnempty`
pub fn contains(environ: Environ, gpa: Allocator, key: []const u8) ContainsError!bool {
    if (native_os == .windows and !unicode.wtf8ValidateSlice(key)) return error.InvalidWtf8;
    var map = try createMap(environ, gpa);
    defer map.deinit();
    return map.contains(key);
}

/// On Windows, if `key` is not valid [WTF-8](https://wtf-8.codeberg.page/),
/// then `error.InvalidWtf8` is returned.
///
/// See also:
/// * `createMap`
/// * `containsUnemptyConstant`
/// * `contains`
pub fn containsUnempty(environ: Environ, gpa: Allocator, key: []const u8) ContainsError!bool {
    if (native_os == .windows and !unicode.wtf8ValidateSlice(key)) return error.InvalidWtf8;
    var map = try createMap(environ, gpa);
    defer map.deinit();
    const value = map.get(key) orelse return false;
    return value.len != 0;
}

/// This function is unavailable on WASI without libc due to the memory
/// allocation requirement.
///
/// On Windows, `key` must be valid [WTF-8](https://wtf-8.codeberg.page/),
///
/// See also:
/// * `contains`
/// * `containsUnemptyConstant`
/// * `createMap`
pub inline fn containsConstant(environ: Environ, comptime key: []const u8) bool {
    if (native_os == .windows) {
        const key_w = comptime unicode.wtf8ToWtf16LeStringLiteral(key);
        return getWindows(environ, key_w) != null;
    } else {
        return getPosix(environ, key) != null;
    }
}

/// This function is unavailable on WASI without libc due to the memory
/// allocation requirement.
///
/// On Windows, `key` must be valid [WTF-8](https://wtf-8.codeberg.page/),
///
/// See also:
/// * `containsUnempty`
/// * `containsConstant`
/// * `createMap`
pub inline fn containsUnemptyConstant(environ: Environ, comptime key: []const u8) bool {
    if (native_os == .windows) {
        const key_w = comptime unicode.wtf8ToWtf16LeStringLiteral(key);
        const value = getWindows(environ, key_w) orelse return false;
        return value.len != 0;
    } else {
        const value = getPosix(environ, key) orelse return false;
        return value.len != 0;
    }
}

/// This function is unavailable on WASI without libc due to the memory
/// allocation requirement.
///
/// See also:
/// * `getWindows`
/// * `createMap`
pub fn getPosix(environ: Environ, key: []const u8) ?[:0]const u8 {
    if (mem.findScalar(u8, key, '=') != null) return null;
    for (environ.block.view().slice) |entry| {
        var entry_i: usize = 0;
        while (entry[entry_i] != 0) : (entry_i += 1) {
            if (entry_i == key.len) break;
            if (entry[entry_i] != key[entry_i]) break;
        }
        if ((entry_i != key.len) or (entry[entry_i] != '=')) continue;

        return mem.sliceTo(entry + entry_i + 1, 0);
    }
    return null;
}

/// Windows-only. Get an environment variable with a null-terminated, WTF-16
/// encoded name.
///
/// This function performs a Unicode-aware case-insensitive lookup using
/// RtlEqualUnicodeString.
///
/// See also:
/// * `createMap`
/// * `containsConstant`
/// * `contains`
pub fn getWindows(environ: Environ, key: [*:0]const u16) ?[:0]const u16 {
    // '=' anywhere but the start makes this an invalid environment variable name.
    const key_slice = mem.sliceTo(key, 0);
    if (key_slice.len == 0 or mem.findScalar(u16, key_slice[1..], '=') != null) return null;

    if (!environ.block.use_global) return null;

    const peb = std.os.windows.peb();
    assert(std.os.windows.ntdll.RtlEnterCriticalSection(peb.FastPebLock) == .SUCCESS);
    defer assert(std.os.windows.ntdll.RtlLeaveCriticalSection(peb.FastPebLock) == .SUCCESS);
    const ptr = peb.ProcessParameters.Environment;

    var i: usize = 0;
    while (ptr[i] != 0) {
        const key_value = mem.sliceTo(ptr[i..], 0);

        // There are some special environment variables that start with =,
        // so we need a special case to not treat = as a key/value separator
        // if it's the first character.
        // https://devblogs.microsoft.com/oldnewthing/20100506-00/?p=14133
        const equal_index = mem.findScalarPos(u16, key_value, 1, '=') orelse {
            // This is enforced by CreateProcess.
            // If violated, CreateProcess will fail with INVALID_PARAMETER.
            unreachable; // must contain a =
        };

        const this_key = key_value[0..equal_index];
        if (std.os.windows.eqlIgnoreCaseWtf16(key_slice, this_key)) {
            return key_value[equal_index + 1 ..];
        }

        // skip past the NUL terminator
        i += key_value.len + 1;
    }
    return null;
}

pub const GetAllocError = error{
    OutOfMemory,
    EnvironmentVariableMissing,
    /// On Windows, environment variable keys provided by the user must be
    /// valid [WTF-8](https://wtf-8.codeberg.page/). This error is unreachable
    /// if the key is statically known to be valid.
    InvalidWtf8,
};

/// Caller owns returned memory.
///
/// On Windows:
/// * If `key` is not valid [WTF-8](https://wtf-8.codeberg.page/), then
///   `error.InvalidWtf8` is returned.
/// * The returned value is encoded as [WTF-8](https://wtf-8.codeberg.page/).
///
/// On other platforms, the value is an opaque sequence of bytes with no
/// particular encoding.
///
/// See also:
/// * `createMap`
pub fn getAlloc(environ: Environ, gpa: Allocator, key: []const u8) GetAllocError![]u8 {
    if (native_os == .windows and !unicode.wtf8ValidateSlice(key)) return error.InvalidWtf8;
    var map = createMap(environ, gpa) catch return error.OutOfMemory;
    defer map.deinit();
    const val = map.get(key) orelse return error.EnvironmentVariableMissing;
    return gpa.dupe(u8, val);
}

pub const CreatePosixBlockOptions = struct {
    /// `null` means to leave the `ZIG_PROGRESS` environment variable unmodified.
    /// If non-null, negative means to remove the environment variable, and >= 0
    /// means to provide it with the given integer.
    zig_progress_fd: ?i32 = null,
};

/// Creates a null-delimited environment variable block in the format expected
/// by POSIX, from a different one.
pub fn createPosixBlock(
    existing: Environ,
    gpa: Allocator,
    options: CreatePosixBlockOptions,
) Allocator.Error!PosixBlock {
    const contains_zig_progress = for (existing.block.view().slice) |entry| {
        if (mem.eql(u8, mem.sliceTo(entry, '='), "ZIG_PROGRESS")) break true;
    } else false;

    const ZigProgressAction = enum { nothing, edit, delete, add };
    const zig_progress_action: ZigProgressAction = action: {
        const fd = options.zig_progress_fd orelse break :action .nothing;
        if (fd >= 0) {
            break :action if (contains_zig_progress) .edit else .add;
        } else {
            if (contains_zig_progress) break :action .delete;
        }
        break :action .nothing;
    };

    const envp = try gpa.allocSentinel(?[*:0]u8, len: {
        var len: usize = existing.block.slice.len;
        switch (zig_progress_action) {
            .add => len += 1,
            .delete => len -= 1,
            .nothing, .edit => {},
        }
        break :len len;
    }, null);
    var envp_len: usize = 0;
    errdefer {
        envp[envp_len] = null;
        PosixBlock.deinit(.{ .slice = envp[0..envp_len :null] }, gpa);
    }
    if (zig_progress_action == .add) {
        envp[envp_len] = try std.fmt.allocPrintSentinel(gpa, "ZIG_PROGRESS={d}", .{options.zig_progress_fd.?}, 0);
        envp_len += 1;
    }

    var existing_index: usize = 0;
    while (existing.block.slice[existing_index]) |entry| : (existing_index += 1) {
        if (mem.eql(u8, mem.sliceTo(entry, '='), "ZIG_PROGRESS")) switch (zig_progress_action) {
            .add => unreachable,
            .delete => continue,
            .edit => {
                envp[envp_len] = try std.fmt.allocPrintSentinel(gpa, "ZIG_PROGRESS={d}", .{options.zig_progress_fd.?}, 0);
                envp_len += 1;
                continue;
            },
            .nothing => {},
        };
        envp[envp_len] = try gpa.dupeZ(u8, mem.span(entry));
        envp_len += 1;
    }

    assert(envp_len == envp.len);
    return .{ .slice = envp };
}

pub const CreateWindowsBlockOptions = struct {
    /// `null` means to leave the `ZIG_PROGRESS` environment variable unmodified.
    /// If non-null, `std.os.windows.INVALID_HANDLE_VALUE` means to remove the
    /// environment variable, otherwise provide it with the given handle as an integer.
    zig_progress_handle: ?std.os.windows.HANDLE = null,
};

/// Creates a null-delimited environment variable block in the format expected
/// by POSIX, from a different one.
pub fn createWindowsBlock(
    existing: Environ,
    gpa: Allocator,
    options: CreateWindowsBlockOptions,
) Allocator.Error!WindowsBlock {
    if (!existing.block.use_global) return .{
        .slice = try gpa.dupeSentinel(u16, WindowsBlock.empty.slice, 0),
    };
    const peb = std.os.windows.peb();
    assert(std.os.windows.ntdll.RtlEnterCriticalSection(peb.FastPebLock) == .SUCCESS);
    defer assert(std.os.windows.ntdll.RtlLeaveCriticalSection(peb.FastPebLock) == .SUCCESS);
    const existing_block = peb.ProcessParameters.Environment;
    var ranges: [2]struct { start: usize, end: usize } = undefined;
    var ranges_len: usize = 0;
    ranges[ranges_len].start = 0;
    const zig_progress_key = [_]u16{ 'Z', 'I', 'G', '_', 'P', 'R', 'O', 'G', 'R', 'E', 'S', 'S', '=' };
    const needed_len = needed_len: {
        var needed_len: usize = "\x00".len;
        if (options.zig_progress_handle) |handle| if (handle != std.os.windows.INVALID_HANDLE_VALUE) {
            needed_len += std.fmt.count("ZIG_PROGRESS={d}\x00", .{@intFromPtr(handle)});
        };
        var i: usize = 0;
        while (existing_block[i] != 0) {
            const start = i;
            const entry = mem.sliceTo(existing_block[start..], 0);
            i += entry.len + "\x00".len;
            if (options.zig_progress_handle != null and entry.len >= zig_progress_key.len and
                std.os.windows.eqlIgnoreCaseWtf16(entry[0..zig_progress_key.len], &zig_progress_key))
            {
                ranges[ranges_len].end = start;
                ranges_len += 1;
                ranges[ranges_len].start = i;
            } else needed_len += entry.len + "\x00".len;
        }
        ranges[ranges_len].end = i;
        ranges_len += 1;
        break :needed_len @max("\x00\x00".len, needed_len);
    };
    const block = try gpa.alloc(u16, needed_len);
    errdefer gpa.free(block);
    var i: usize = 0;
    if (options.zig_progress_handle) |handle| if (handle != std.os.windows.INVALID_HANDLE_VALUE) {
        @memcpy(block[i..][0..zig_progress_key.len], &zig_progress_key);
        i += zig_progress_key.len;
        var value_buf: [std.fmt.count("{d}", .{std.math.maxInt(usize)})]u8 = undefined;
        const value = std.fmt.bufPrint(&value_buf, "{d}", .{@intFromPtr(handle)}) catch unreachable;
        for (block[i..][0..value.len], value) |*r, v| r.* = v;
        i += value.len;
        block[i] = 0;
        i += 1;
    };
    for (ranges[0..ranges_len]) |range| {
        const range_len = range.end - range.start;
        @memcpy(block[i..][0..range_len], existing_block[range.start..range.end]);
        i += range_len;
    }
    // An empty environment is a special case that requires a redundant
    // NUL terminator. CreateProcess will read the second code unit even
    // though theoretically the first should be enough to recognize that the
    // environment is empty (see https://nullprogram.com/blog/2023/08/23/)
    for (0..2) |_| {
        block[i] = 0;
        i += 1;
        if (i >= 2) break;
    } else unreachable;
    assert(i == block.len);
    return .{ .slice = block[0 .. i - 1 :0] };
}

test "Map.createPosixBlock" {
    const gpa = testing.allocator;

    var envmap = Map.init(gpa);
    defer envmap.deinit();

    try envmap.put("HOME", "/home/ifreund");
    try envmap.put("WAYLAND_DISPLAY", "wayland-1");
    try envmap.put("DISPLAY", ":1");
    try envmap.put("DEBUGINFOD_URLS", " ");
    try envmap.put("XCURSOR_SIZE", "24");

    const block = try envmap.createPosixBlock(gpa, .{});
    defer block.deinit(gpa);

    try testing.expectEqual(@as(usize, 5), block.slice.len);

    for (&[_][]const u8{
        "HOME=/home/ifreund",
        "WAYLAND_DISPLAY=wayland-1",
        "DISPLAY=:1",
        "DEBUGINFOD_URLS= ",
        "XCURSOR_SIZE=24",
    }, block.slice) |expected, actual| try testing.expectEqualStrings(expected, mem.span(actual.?));
}

test Map {
    const gpa = testing.allocator;

    var env: Map = .init(gpa);
    defer env.deinit();

    try env.put("SOMETHING_NEW", "hello");
    try testing.expectEqualStrings("hello", env.get("SOMETHING_NEW").?);
    try testing.expectEqual(@as(Map.Size, 1), env.count());

    // overwrite
    try env.put("SOMETHING_NEW", "something");
    try testing.expectEqualStrings("something", env.get("SOMETHING_NEW").?);
    try testing.expectEqual(@as(Map.Size, 1), env.count());

    // a new longer name to test the Windows-specific conversion buffer
    try env.put("SOMETHING_NEW_AND_LONGER", "1");
    try testing.expectEqualStrings("1", env.get("SOMETHING_NEW_AND_LONGER").?);
    try testing.expectEqual(@as(Map.Size, 2), env.count());

    // case insensitivity on Windows only
    if (native_os == .windows) {
        try testing.expectEqualStrings("1", env.get("something_New_aNd_LONGER").?);
    } else {
        try testing.expect(null == env.get("something_New_aNd_LONGER"));
    }

    var it = env.iterator();
    var count: Map.Size = 0;
    while (it.next()) |entry| {
        const is_an_expected_name = mem.eql(u8, "SOMETHING_NEW", entry.key_ptr.*) or mem.eql(u8, "SOMETHING_NEW_AND_LONGER", entry.key_ptr.*);
        try testing.expect(is_an_expected_name);
        count += 1;
    }
    try testing.expectEqual(@as(Map.Size, 2), count);

    try testing.expect(env.swapRemove("SOMETHING_NEW"));
    try testing.expect(!env.swapRemove("SOMETHING_NEW"));
    try testing.expect(env.get("SOMETHING_NEW") == null);
    try testing.expect(!env.contains("SOMETHING_NEW"));

    try testing.expectEqual(@as(Map.Size, 1), env.count());

    if (native_os == .windows) {
        // test Unicode case-insensitivity on Windows
        try env.put("КИРиллИЦА", "something else");
        try testing.expectEqualStrings("something else", env.get("кириллица").?);

        // and WTF-8 that's not valid UTF-8
        const wtf8_with_surrogate_pair = try unicode.wtf16LeToWtf8Alloc(gpa, &[_]u16{
            mem.nativeToLittle(u16, 0xD83D), // unpaired high surrogate
        });
        defer gpa.free(wtf8_with_surrogate_pair);

        try env.put(wtf8_with_surrogate_pair, wtf8_with_surrogate_pair);
        try testing.expectEqualSlices(u8, wtf8_with_surrogate_pair, env.get(wtf8_with_surrogate_pair).?);
    }
}

test "convert from Environ to Map and back again" {
    if (native_os == .windows) return;
    if (native_os == .wasi and !builtin.link_libc) return;

    const gpa = testing.allocator;

    var map: Map = .init(gpa);
    defer map.deinit();
    try map.put("FOO", "BAR");
    try map.put("A", "");

    const environ: Environ = .{ .block = try map.createPosixBlock(gpa, .{}) };
    defer environ.block.deinit(gpa);

    try testing.expectEqual(true, environ.contains(gpa, "FOO"));
    try testing.expectEqual(false, environ.contains(gpa, "BAR"));
    try testing.expectEqual(true, environ.contains(gpa, "A"));
    try testing.expectEqual(true, environ.containsConstant("A"));
    try testing.expectEqual(false, environ.containsUnempty(gpa, "A"));
    try testing.expectEqual(false, environ.containsUnemptyConstant("A"));
    try testing.expectEqual(false, environ.contains(gpa, "B"));

    try testing.expectError(error.EnvironmentVariableMissing, environ.getAlloc(gpa, "BOGUS"));
    {
        const value = try environ.getAlloc(gpa, "FOO");
        defer gpa.free(value);
        try testing.expectEqualStrings("BAR", value);
    }

    var map2 = try environ.createMap(gpa);
    defer map2.deinit();

    try testing.expectEqualDeep(map.keys(), map2.keys());
    try testing.expectEqualDeep(map.values(), map2.values());
}

test "Map.putPosixBlock" {
    const gpa = testing.allocator;

    var map: Map = .init(gpa);
    defer map.deinit();

    try map.put("FOO", "BAR");
    try map.put("A", "");
    try map.put("ZIG_PROGRESS", "unchanged");

    const block = try map.createPosixBlock(gpa, .{});
    defer block.deinit(gpa);

    var map2: Map = .init(gpa);
    defer map2.deinit();
    try map2.putPosixBlock(block.view());

    try testing.expectEqualDeep(&[_][]const u8{ "FOO", "A", "ZIG_PROGRESS" }, map2.keys());
    try testing.expectEqualDeep(&[_][]const u8{ "BAR", "", "unchanged" }, map2.values());
}

test "Map.putWindowsBlock" {
    if (native_os != .windows) return;

    const gpa = testing.allocator;

    var map: Map = .init(gpa);
    defer map.deinit();

    try map.put("FOO", "BAR");
    try map.put("A", "");
    try map.put("=B", "");
    try map.put("ZIG_PROGRESS", "unchanged");

    const block = try map.createWindowsBlock(gpa, .{});
    defer block.deinit(gpa);

    var map2: Map = .init(gpa);
    defer map2.deinit();
    try map2.putWindowsBlock(block.view());

    try testing.expectEqualDeep(&[_][]const u8{ "FOO", "A", "=B", "ZIG_PROGRESS" }, map2.keys());
    try testing.expectEqualDeep(&[_][]const u8{ "BAR", "", "", "unchanged" }, map2.values());
}
