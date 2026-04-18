const Dir = @This();
const root = @import("root");

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Io = std.Io;
const File = Io.File;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

handle: Handle,

pub const Handle = std.posix.fd_t;

pub const path = std.fs.path;

/// The maximum length of a file path that the operating system will accept.
///
/// Paths, including those returned from file system operations, may be longer
/// than this length, but such paths cannot be successfully passed back in
/// other file system operations. However, all path components returned by file
/// system operations are assumed to fit into a `u8` array of this length.
///
/// The byte count includes room for a null sentinel byte.
///
/// * On Windows, `[]u8` file paths are encoded as
///   [WTF-8](https://wtf-8.codeberg.page/).
/// * On WASI, `[]u8` file paths are encoded as valid UTF-8.
/// * On other platforms, `[]u8` file paths are opaque sequences of bytes with
///   no particular encoding.
pub const max_path_bytes = switch (native_os) {
    .linux, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .openbsd, .netbsd, .dragonfly, .haiku, .illumos, .plan9, .emscripten, .wasi, .serenity => std.posix.PATH_MAX,
    // Each WTF-16LE code unit may be expanded to 3 WTF-8 bytes.
    // If it would require 4 WTF-8 bytes, then there would be a surrogate
    // pair in the WTF-16LE, and we (over)account 3 bytes for it that way.
    // +1 for the null byte at the end, which can be encoded in 1 byte.
    .windows => std.os.windows.PATH_MAX_WIDE * 3 + 1,
    else => if (@hasDecl(root, "os") and @hasDecl(root.os, "PATH_MAX"))
        root.os.PATH_MAX
    else
        @compileError("PATH_MAX not implemented for " ++ @tagName(native_os)),
};

/// This represents the maximum size of a `[]u8` file name component that
/// the platform's common file systems support. File name components returned by file system
/// operations are likely to fit into a `u8` array of this length, but
/// (depending on the platform) this assumption may not hold for every configuration.
/// The byte count does not include a null sentinel byte.
/// On Windows, `[]u8` file name components are encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, file name components are encoded as valid UTF-8.
/// On other platforms, `[]u8` components are an opaque sequence of bytes with no particular encoding.
pub const max_name_bytes = switch (native_os) {
    .linux, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos, .serenity, .psp => std.posix.NAME_MAX,
    // Haiku's NAME_MAX includes the null terminator, so subtract one.
    .haiku => std.posix.NAME_MAX - 1,
    // Each WTF-16LE character may be expanded to 3 WTF-8 bytes.
    // If it would require 4 WTF-8 bytes, then there would be a surrogate
    // pair in the WTF-16LE, and we (over)account 3 bytes for it that way.
    .windows => std.os.windows.NAME_MAX * 3,
    // For WASI, the MAX_NAME will depend on the host OS, so it needs to be
    // as large as the largest max_name_bytes (Windows) in order to work on any host OS.
    // TODO determine if this is a reasonable approach
    .wasi => std.os.windows.NAME_MAX * 3,
    else => if (@hasDecl(root, "os") and @hasDecl(root.os, "NAME_MAX"))
        root.os.NAME_MAX
    else
        @compileError("NAME_MAX not implemented for " ++ @tagName(native_os)),
};

pub const Entry = struct {
    name: []const u8,
    kind: File.Kind,
    inode: File.INode,
};

/// Returns a handle to the current working directory.
///
/// It is not opened with iteration capability. Iterating over the result is
/// illegal behavior.
///
/// Closing the returned `Dir` is checked illegal behavior.
///
/// On POSIX targets, this function is comptime-callable.
///
/// This function is overridable via `std.Options.cwd`.
pub fn cwd() Dir {
    const cwdFn = std.Options.cwd orelse return switch (native_os) {
        .windows => .{ .handle = std.os.windows.peb().ProcessParameters.CurrentDirectory.Handle },
        .wasi => .{ .handle = 3 }, // Expect the first preopen to be current working directory.
        else => .{ .handle = std.posix.AT.FDCWD },
    };
    return cwdFn();
}

pub const Reader = struct {
    dir: Dir,
    state: State,
    /// Stores I/O implementation specific data.
    buffer: []align(@alignOf(usize)) u8,
    /// Index of next entry in `buffer`.
    index: usize,
    /// Fill position of `buffer`.
    end: usize,

    /// A length for `buffer` that allows all implementations to function.
    pub const min_buffer_len = switch (native_os) {
        .linux => std.mem.alignForward(usize, @sizeOf(std.os.linux.dirent64), 8) +
            std.mem.alignForward(usize, max_name_bytes, 8),
        .windows => len: {
            const max_info_len = @sizeOf(std.os.windows.FILE_BOTH_DIR_INFORMATION) + std.os.windows.NAME_MAX * 2;
            const info_align = @alignOf(std.os.windows.FILE_BOTH_DIR_INFORMATION);
            const reserved_len = std.mem.alignForward(usize, max_name_bytes, info_align) - max_info_len;
            break :len std.mem.alignForward(usize, reserved_len, info_align) + max_info_len;
        },
        .wasi => @sizeOf(std.os.wasi.dirent_t) +
            std.mem.alignForward(usize, max_name_bytes, @alignOf(std.os.wasi.dirent_t)),
        .openbsd => std.c.S.BLKSIZE,
        else => if (builtin.link_libc) @sizeOf(std.c.dirent) else std.mem.alignForward(usize, max_name_bytes, @alignOf(usize)),
    };

    pub const State = enum {
        /// Indicates the next call to `read` should rewind and start over the
        /// directory listing.
        reset,
        reading,
        finished,
    };

    pub const Error = error{
        AccessDenied,
        PermissionDenied,
        SystemResources,
    } || Io.UnexpectedError || Io.Cancelable;

    /// Asserts that `buffer` has length at least `min_buffer_len`.
    pub fn init(dir: Dir, buffer: []align(@alignOf(usize)) u8) Reader {
        assert(buffer.len >= min_buffer_len);
        return .{
            .dir = dir,
            .state = .reset,
            .index = 0,
            .end = 0,
            .buffer = buffer,
        };
    }

    /// All `Entry.name` are invalidated with the next call to `read` or
    /// `next`.
    pub fn read(r: *Reader, io: Io, buffer: []Entry) Error!usize {
        return io.vtable.dirRead(io.userdata, r, buffer);
    }

    /// `Entry.name` is invalidated with the next call to `read` or `next`.
    pub fn next(r: *Reader, io: Io) Error!?Entry {
        var buffer: [1]Entry = undefined;
        while (true) {
            const n = try read(r, io, &buffer);
            if (n == 1) return buffer[0];
            if (r.state == .finished) return null;
        }
    }

    pub fn reset(r: *Reader) void {
        r.state = .reset;
        r.index = 0;
        r.end = 0;
    }
};

/// This API is designed for convenience rather than performance:
/// * It chooses a buffer size rather than allowing the user to provide one.
/// * It is movable by only requesting one `Entry` at a time from the `Io`
///   implementation rather than doing batch operations.
///
/// Still, it will do a decent job of minimizing syscall overhead. For a
/// lower level abstraction, see `Reader`. For a higher level abstraction,
/// see `Walker`.
pub const Iterator = struct {
    reader: Reader,
    reader_buffer: [reader_buffer_len]u8 align(@alignOf(usize)),

    pub const reader_buffer_len = 2048;

    comptime {
        assert(reader_buffer_len >= Reader.min_buffer_len);
    }

    pub const Error = Reader.Error;

    pub fn init(dir: Dir, reader_state: Reader.State) Iterator {
        return .{
            .reader = .{
                .dir = dir,
                .state = reader_state,
                .index = 0,
                .end = 0,
                .buffer = undefined,
            },
            .reader_buffer = undefined,
        };
    }

    pub fn next(it: *Iterator, io: Io) Error!?Entry {
        it.reader.buffer = &it.reader_buffer;
        return it.reader.next(io);
    }
};

pub fn iterate(dir: Dir) Iterator {
    return .init(dir, .reset);
}

/// Like `iterate`, but will not reset the directory cursor before the first
/// iteration. This should only be used in cases where it is known that the
/// `Dir` has not had its cursor modified yet (e.g. it was just opened).
pub fn iterateAssumeFirstIteration(dir: Dir) Iterator {
    return .init(dir, .reading);
}

pub const SelectiveWalker = struct {
    stack: std.ArrayList(StackItem),
    name_buffer: std.ArrayList(u8),
    allocator: Allocator,

    pub const Error = Iterator.Error || Allocator.Error;

    const StackItem = struct {
        iter: Iterator,
        dirname_len: usize,
    };

    /// After each call to this function, and on deinit(), the memory returned
    /// from this function becomes invalid. A copy must be made in order to keep
    /// a reference to the path.
    pub fn next(self: *SelectiveWalker, io: Io) Error!?Walker.Entry {
        while (self.stack.items.len > 0) {
            const top = &self.stack.items[self.stack.items.len - 1];
            var dirname_len = top.dirname_len;
            if (top.iter.next(io) catch |err| {
                // If we get an error, then we want the user to be able to continue
                // walking if they want, which means that we need to pop the directory
                // that errored from the stack. Otherwise, all future `next` calls would
                // likely just fail with the same error.
                var item = self.stack.pop().?;
                if (self.stack.items.len != 0) {
                    item.iter.reader.dir.close(io);
                }
                return err;
            }) |entry| {
                self.name_buffer.shrinkRetainingCapacity(dirname_len);
                if (self.name_buffer.items.len != 0) {
                    try self.name_buffer.append(self.allocator, path.sep);
                    dirname_len += 1;
                }
                try self.name_buffer.ensureUnusedCapacity(self.allocator, entry.name.len + 1);
                self.name_buffer.appendSliceAssumeCapacity(entry.name);
                self.name_buffer.appendAssumeCapacity(0);
                const walker_entry: Walker.Entry = .{
                    .dir = top.iter.reader.dir,
                    .basename = self.name_buffer.items[dirname_len .. self.name_buffer.items.len - 1 :0],
                    .path = self.name_buffer.items[0 .. self.name_buffer.items.len - 1 :0],
                    .kind = entry.kind,
                };
                return walker_entry;
            } else {
                var item = self.stack.pop().?;
                if (self.stack.items.len != 0) {
                    item.iter.reader.dir.close(io);
                }
            }
        }
        return null;
    }

    /// Traverses into the directory, continuing walking one level down.
    pub fn enter(self: *SelectiveWalker, io: Io, entry: Walker.Entry) !void {
        if (entry.kind != .directory) {
            @branchHint(.cold);
            return;
        }

        var new_dir = entry.dir.openDir(io, entry.basename, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.NameTooLong => unreachable,
                else => |e| return e,
            }
        };
        errdefer new_dir.close(io);

        try self.stack.append(self.allocator, .{
            .iter = new_dir.iterateAssumeFirstIteration(),
            .dirname_len = self.name_buffer.items.len - 1,
        });
    }

    pub fn deinit(self: *SelectiveWalker) void {
        self.name_buffer.deinit(self.allocator);
        self.stack.deinit(self.allocator);
    }

    /// Leaves the current directory, continuing walking one level up.
    /// If the current entry is a directory entry, then the "current directory"
    /// will pertain to that entry if `enter` is called before `leave`.
    pub fn leave(self: *SelectiveWalker, io: Io) void {
        var item = self.stack.pop().?;
        if (self.stack.items.len != 0) {
            @branchHint(.likely);
            item.iter.reader.dir.close(io);
        }
    }
};

/// Recursively iterates over a directory, but requires the user to
/// opt-in to recursing into each directory entry.
///
/// `dir` must have been opened with `OpenOptions.iterate` set to `true`.
///
/// `Walker.deinit` releases allocated memory and directory handles.
///
/// The order of returned file system entries is undefined.
///
/// `dir` will not be closed after walking it.
///
/// See also `walk`.
pub fn walkSelectively(dir: Dir, allocator: Allocator) !SelectiveWalker {
    var stack: std.ArrayList(SelectiveWalker.StackItem) = .empty;

    try stack.append(allocator, .{
        .iter = dir.iterate(),
        .dirname_len = 0,
    });

    return .{
        .stack = stack,
        .name_buffer = .empty,
        .allocator = allocator,
    };
}

pub const Walker = struct {
    inner: SelectiveWalker,

    pub const Entry = struct {
        /// The containing directory. This can be used to operate directly on `basename`
        /// rather than `path`, avoiding `error.NameTooLong` for deeply nested paths.
        /// The directory remains open until `next` or `deinit` is called.
        dir: Dir,
        basename: [:0]const u8,
        path: [:0]const u8,
        kind: File.Kind,

        /// Returns the depth of the entry relative to the initial directory.
        /// Returns 1 for a direct child of the initial directory, 2 for an entry
        /// within a direct child of the initial directory, etc.
        pub fn depth(self: Walker.Entry) usize {
            return std.mem.countScalar(u8, self.path, path.sep) + 1;
        }
    };

    /// After each call to this function, and on deinit(), the memory returned
    /// from this function becomes invalid. A copy must be made in order to keep
    /// a reference to the path.
    pub fn next(self: *Walker, io: Io) !?Walker.Entry {
        const entry = try self.inner.next(io);
        if (entry != null and entry.?.kind == .directory) {
            try self.inner.enter(io, entry.?);
        }
        return entry;
    }

    pub fn deinit(self: *Walker) void {
        self.inner.deinit();
    }

    /// Leaves the current directory, continuing walking one level up.
    /// If the current entry is a directory entry, then the "current directory"
    /// is the directory pertaining to the current entry.
    pub fn leave(self: *Walker, io: Io) void {
        self.inner.leave(io);
    }
};

/// Recursively iterates over a directory.
///
/// `dir` must have been opened with `OpenOptions.iterate` set to `true`.
///
/// `Walker.deinit` releases allocated memory and directory handles.
///
/// The order of returned file system entries is undefined.
///
/// `dir` will not be closed after walking it.
///
/// See also:
/// * `walkSelectively`
pub fn walk(dir: Dir, allocator: Allocator) Allocator.Error!Walker {
    return .{ .inner = try walkSelectively(dir, allocator) };
}

pub const PathNameError = error{
    /// Returned when an insufficient buffer is provided that cannot fit the
    /// path name.
    NameTooLong,
    /// File system cannot encode the requested file name bytes.
    /// Could be due to invalid WTF-8 on Windows, invalid UTF-8 on WASI,
    /// invalid characters on Windows, etc. Filesystem and operating specific.
    BadPathName,
};

pub const AccessError = error{
    AccessDenied,
    PermissionDenied,
    FileNotFound,
    InputOutput,
    SystemResources,
    FileBusy,
    SymLinkLoop,
    ReadOnlyFileSystem,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

pub const AccessOptions = packed struct {
    follow_symlinks: bool = true,
    read: bool = false,
    write: bool = false,
    execute: bool = false,
};

/// Test accessing `sub_path`.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
///
/// Be careful of Time-Of-Check-Time-Of-Use race conditions when using this
/// function. For example, instead of testing if a file exists and then opening
/// it, just open it and handle the error for file not found.
pub fn access(dir: Dir, io: Io, sub_path: []const u8, options: AccessOptions) AccessError!void {
    return io.vtable.dirAccess(io.userdata, dir, sub_path, options);
}

pub fn accessAbsolute(io: Io, absolute_path: []const u8, options: AccessOptions) AccessError!void {
    assert(path.isAbsolute(absolute_path));
    return access(.cwd(), io, absolute_path, options);
}

pub const OpenError = error{
    FileNotFound,
    NotDir,
    AccessDenied,
    PermissionDenied,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NoDevice,
    SystemResources,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

pub const OpenOptions = struct {
    /// `true` means the opened directory can be used as the `Dir` parameter
    /// for functions which operate based on an open directory handle. When `false`,
    /// such operations are Illegal Behavior.
    access_sub_paths: bool = true,
    /// `true` means the opened directory can be scanned for the files and sub-directories
    /// of the result. It means the `iterate` function can be called.
    iterate: bool = false,
    /// `false` means it won't dereference the symlinks.
    follow_symlinks: bool = true,
};

/// Opens a directory at the given path. The directory is a system resource that remains
/// open until `close` is called on the result.
///
/// The directory cannot be iterated unless the `iterate` option is set to `true`.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn openDir(dir: Dir, io: Io, sub_path: []const u8, options: OpenOptions) OpenError!Dir {
    return io.vtable.dirOpenDir(io.userdata, dir, sub_path, options);
}

pub fn openDirAbsolute(io: Io, absolute_path: []const u8, options: OpenOptions) OpenError!Dir {
    assert(path.isAbsolute(absolute_path));
    return openDir(.cwd(), io, absolute_path, options);
}

pub fn close(dir: Dir, io: Io) void {
    return io.vtable.dirClose(io.userdata, (&dir)[0..1]);
}

pub fn closeMany(io: Io, dirs: []const Dir) void {
    return io.vtable.dirClose(io.userdata, dirs);
}

pub const OpenFileOptions = struct {
    mode: Mode = .read_only,
    /// Determines the behavior when opening a path that refers to a directory.
    ///
    /// If set to true, directories may be opened, but `error.IsDir` is still
    /// possible in certain scenarios, e.g. attempting to open a directory with
    /// write permissions.
    ///
    /// If set to false, `error.IsDir` will always be returned when opening a directory.
    ///
    /// When set to false:
    /// * On Windows, the behavior is implemented without any extra syscalls.
    /// * On other operating systems, the behavior is implemented with an additional
    ///   `fstat` syscall.
    allow_directory: bool = true,
    /// Indicates intent for only some operations to be performed on this
    /// opened file:
    /// * `close`
    /// * `stat`
    /// On Linux and FreeBSD, this corresponds to `std.posix.O.PATH`.
    path_only: bool = false,
    /// Open the file with an advisory lock to coordinate with other processes
    /// accessing it at the same time. An exclusive lock will prevent other
    /// processes from acquiring a lock. A shared lock will prevent other
    /// processes from acquiring a exclusive lock, but does not prevent
    /// other process from getting their own shared locks.
    ///
    /// The lock is advisory, except on Linux in very specific circumstances[1].
    /// This means that a process that does not respect the locking API can still get access
    /// to the file, despite the lock.
    ///
    /// On these operating systems, the lock is acquired atomically with
    /// opening the file:
    /// * Darwin
    /// * DragonFlyBSD
    /// * FreeBSD
    /// * Haiku
    /// * NetBSD
    /// * OpenBSD
    /// On these operating systems, the lock is acquired via a separate syscall
    /// after opening the file:
    /// * Linux
    /// * Windows
    ///
    /// [1]: https://www.kernel.org/doc/Documentation/filesystems/mandatory-locking.txt
    lock: File.Lock = .none,
    /// Sets whether or not to wait until the file is locked to return. If set to true,
    /// `error.WouldBlock` will be returned. Otherwise, the file will wait until the file
    /// is available to proceed.
    lock_nonblocking: bool = false,
    /// Set this to allow the opened file to automatically become the
    /// controlling TTY for the current process.
    allow_ctty: bool = false,
    follow_symlinks: bool = true,
    /// If supported by the operating system, attempted path resolution that
    /// would escape the directory instead returns `error.AccessDenied`. If
    /// unsupported, this option is ignored.
    resolve_beneath: bool = false,

    pub const Mode = enum { read_only, write_only, read_write };

    pub fn isRead(self: OpenFileOptions) bool {
        return self.mode != .write_only;
    }

    pub fn isWrite(self: OpenFileOptions) bool {
        return self.mode != .read_only;
    }
};

/// Opens a file for reading or writing, without attempting to create a new file.
///
/// To create a new file, see `createFile`.
///
/// Allocates a resource to be released with `File.close`.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn openFile(dir: Dir, io: Io, sub_path: []const u8, options: OpenFileOptions) File.OpenError!File {
    return io.vtable.dirOpenFile(io.userdata, dir, sub_path, options);
}

pub fn openFileAbsolute(io: Io, absolute_path: []const u8, options: OpenFileOptions) File.OpenError!File {
    assert(path.isAbsolute(absolute_path));
    return openFile(.cwd(), io, absolute_path, options);
}

pub const CreateFileOptions = struct {
    /// Whether the file will be created with read access.
    read: bool = false,
    /// If the file already exists, and is a regular file, and the access
    /// mode allows writing, it will be truncated to length 0.
    truncate: bool = true,
    /// Ensures that this open call creates the file, otherwise causes
    /// `error.PathAlreadyExists` to be returned.
    exclusive: bool = false,
    /// Open the file with an advisory lock to coordinate with other processes
    /// accessing it at the same time. An exclusive lock will prevent other
    /// processes from acquiring a lock. A shared lock will prevent other
    /// processes from acquiring a exclusive lock, but does not prevent
    /// other process from getting their own shared locks.
    ///
    /// The lock is advisory, except on Linux in very specific circumstances[1].
    /// This means that a process that does not respect the locking API can still get access
    /// to the file, despite the lock.
    ///
    /// On these operating systems, the lock is acquired atomically with
    /// opening the file:
    /// * Darwin
    /// * DragonFlyBSD
    /// * FreeBSD
    /// * Haiku
    /// * NetBSD
    /// * OpenBSD
    /// On these operating systems, the lock is acquired via a separate syscall
    /// after opening the file:
    /// * Linux
    /// * Windows
    ///
    /// [1]: https://www.kernel.org/doc/Documentation/filesystems/mandatory-locking.txt
    lock: File.Lock = .none,
    /// Sets whether or not to wait until the file is locked to return. If set to true,
    /// `error.WouldBlock` will be returned. Otherwise, the file will wait until the file
    /// is available to proceed.
    lock_nonblocking: bool = false,
    permissions: Permissions = .default_file,
    /// If supported by the operating system, attempted path resolution that
    /// would escape the directory instead returns `error.AccessDenied`. If
    /// unsupported, this option is ignored.
    resolve_beneath: bool = false,
};

/// Creates, opens, or overwrites a file with write access.
///
/// Allocates a resource to be dellocated with `File.close`.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn createFile(dir: Dir, io: Io, sub_path: []const u8, flags: CreateFileOptions) File.OpenError!File {
    return io.vtable.dirCreateFile(io.userdata, dir, sub_path, flags);
}

pub fn createFileAbsolute(io: Io, absolute_path: []const u8, flags: CreateFileOptions) File.OpenError!File {
    return createFile(.cwd(), io, absolute_path, flags);
}

pub const WriteFileOptions = struct {
    /// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
    /// On WASI, `sub_path` should be encoded as valid UTF-8.
    /// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
    sub_path: []const u8,
    data: []const u8,
    flags: CreateFileOptions = .{},
};

pub const WriteFileError = File.Writer.Error || File.OpenError;

/// Writes content to the file system, using the file creation flags provided.
pub fn writeFile(dir: Dir, io: Io, options: WriteFileOptions) WriteFileError!void {
    var file = try dir.createFile(io, options.sub_path, options.flags);
    defer file.close(io);
    try file.writeStreamingAll(io, options.data);
}

pub const PrevStatus = enum {
    stale,
    fresh,
};

pub const UpdateFileError = File.OpenError;

/// Check the file size, mtime, and permissions of `source_path` and `dest_path`. If
/// they are equal, does nothing. Otherwise, atomically copies `source_path` to
/// `dest_path`, creating the parent directory hierarchy as needed. The
/// destination file gains the mtime, atime, and permissions of the source file so
/// that the next call to `updateFile` will not need a copy.
///
/// Returns the previous status of the file before updating.
///
/// * On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// * On WASI, both paths should be encoded as valid UTF-8.
/// * On other platforms, both paths are an opaque sequence of bytes with no particular encoding.
pub fn updateFile(
    source_dir: Dir,
    io: Io,
    source_path: []const u8,
    dest_dir: Dir,
    /// If directories in this path do not exist, they are created.
    dest_path: []const u8,
    options: CopyFileOptions,
) !PrevStatus {
    var src_file = try source_dir.openFile(io, source_path, .{});
    defer src_file.close(io);

    const src_stat = try src_file.stat(io);
    const actual_permissions = options.permissions orelse src_stat.permissions;
    check_dest_stat: {
        const dest_stat = blk: {
            var dest_file = dest_dir.openFile(io, dest_path, .{}) catch |err| switch (err) {
                error.FileNotFound => break :check_dest_stat,
                else => |e| return e,
            };
            defer dest_file.close(io);

            break :blk try dest_file.stat(io);
        };

        if (src_stat.size == dest_stat.size and
            src_stat.mtime.nanoseconds == dest_stat.mtime.nanoseconds and
            actual_permissions == dest_stat.permissions)
        {
            return .fresh;
        }
    }

    var atomic_file = try dest_dir.createFileAtomic(io, dest_path, .{
        .permissions = actual_permissions,
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    var buffer: [1024]u8 = undefined; // Used only when direct fd-to-fd is not available.
    var file_writer = atomic_file.file.writer(io, &buffer);

    var src_reader: File.Reader = .initSize(src_file, io, &.{}, src_stat.size);
    const dest_writer = &file_writer.interface;

    _ = dest_writer.sendFileAll(&src_reader, .unlimited) catch |err| switch (err) {
        error.ReadFailed => return src_reader.err.?,
        error.WriteFailed => return file_writer.err.?,
    };
    try file_writer.flush();
    try file_writer.file.setTimestamps(io, .{
        .access_timestamp = .init(src_stat.atime),
        .modify_timestamp = .init(src_stat.mtime),
    });
    try atomic_file.replace(io);
    return .stale;
}

pub const ReadFileError = File.OpenError || File.Reader.Error;

/// Read all of file contents using a preallocated buffer.
///
/// The returned slice has the same pointer as `buffer`. If the length matches `buffer.len`
/// the situation is ambiguous. It could either mean that the entire file was read, and
/// it exactly fits the buffer, or it could mean the buffer was not big enough for the
/// entire file.
///
/// * On Windows, `file_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
/// * On WASI, `file_path` should be encoded as valid UTF-8.
/// * On other platforms, `file_path` is an opaque sequence of bytes with no particular encoding.
pub fn readFile(dir: Dir, io: Io, file_path: []const u8, buffer: []u8) ReadFileError![]u8 {
    var file = try dir.openFile(io, file_path, .{
        // We can take advantage of this on Windows since it doesn't involve any extra syscalls,
        // so we can get error.IsDir during open rather than during the read.
        .allow_directory = if (native_os == .windows) false else true,
    });
    defer file.close(io);

    var reader = file.reader(io, &.{});
    const n = reader.interface.readSliceShort(buffer) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
    };

    return buffer[0..n];
}

pub const CreateDirError = error{
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to create a new directory relative to it.
    AccessDenied,
    PermissionDenied,
    DiskQuota,
    PathAlreadyExists,
    SymLinkLoop,
    LinkQuotaExceeded,
    FileNotFound,
    SystemResources,
    NoSpaceLeft,
    NotDir,
    ReadOnlyFileSystem,
    NoDevice,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Creates a single directory with a relative or absolute path.
///
/// * On Windows, `sub_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
/// * On WASI, `sub_path` should be encoded as valid UTF-8.
/// * On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
///
/// Related:
/// * `createDirPath`
/// * `createDirAbsolute`
pub fn createDir(dir: Dir, io: Io, sub_path: []const u8, permissions: Permissions) CreateDirError!void {
    return io.vtable.dirCreateDir(io.userdata, dir, sub_path, permissions);
}

/// Create a new directory, based on an absolute path.
///
/// Asserts that the path is absolute. See `createDir` for a function that
/// operates on both absolute and relative paths.
///
/// On Windows, `absolute_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `absolute_path` should be encoded as valid UTF-8.
/// On other platforms, `absolute_path` is an opaque sequence of bytes with no particular encoding.
pub fn createDirAbsolute(io: Io, absolute_path: []const u8, permissions: Permissions) CreateDirError!void {
    assert(path.isAbsolute(absolute_path));
    return createDir(.cwd(), io, absolute_path, permissions);
}

test createDirAbsolute {}

pub const CreateDirPathError = CreateDirError || StatFileError;

/// Creates parent directories with default permissions as necessary to ensure
/// `sub_path` exists as a directory.
///
/// Returns success if the path already exists and is a directory.
///
/// This function may not be atomic. If it returns an error, the file system
/// may have been modified.
///
/// Fails on an empty path with `error.BadPathName` as that is not a path that
/// can be created.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
///
/// Paths containing `..` components are handled differently depending on the platform:
/// - On Windows, `..` are resolved before the path is passed to NtCreateFile, meaning
///   a `sub_path` like "first/../second" will resolve to "second" and only a
///   `./second` directory will be created.
/// - On other platforms, `..` are not resolved before the path is passed to `mkdirat`,
///   meaning a `sub_path` like "first/../second" will create both a `./first`
///   and a `./second` directory.
///
/// See also:
/// * `createDirPathStatus`
pub fn createDirPath(dir: Dir, io: Io, sub_path: []const u8) CreateDirPathError!void {
    _ = try io.vtable.dirCreateDirPath(io.userdata, dir, sub_path, .default_dir);
}

pub const CreatePathStatus = enum { existed, created };

/// Same as `createDirPath` except returns whether the path already existed or was
/// successfully created.
pub fn createDirPathStatus(dir: Dir, io: Io, sub_path: []const u8, permissions: Permissions) CreateDirPathError!CreatePathStatus {
    return io.vtable.dirCreateDirPath(io.userdata, dir, sub_path, permissions);
}

pub const CreateDirPathOpenError = CreateDirError || OpenError || StatFileError;

pub const CreateDirPathOpenOptions = struct {
    open_options: OpenOptions = .{},
    permissions: Permissions = .default_dir,
};

/// Performs the equivalent of `createDirPath` followed by `openDir`, atomically if possible.
///
/// When this operation is canceled, it may leave the file system in a
/// partially modified state.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn createDirPathOpen(dir: Dir, io: Io, sub_path: []const u8, options: CreateDirPathOpenOptions) CreateDirPathOpenError!Dir {
    return io.vtable.dirCreateDirPathOpen(io.userdata, dir, sub_path, options.permissions, options.open_options);
}

pub const Stat = File.Stat;
pub const StatError = File.StatError;

pub fn stat(dir: Dir, io: Io) StatError!Stat {
    return io.vtable.dirStat(io.userdata, dir);
}

pub const StatFileError = File.OpenError || File.StatError;

pub const StatFileOptions = struct {
    follow_symlinks: bool = true,
};

/// Returns metadata for a file inside the directory.
///
/// On Windows, this requires three syscalls. On other operating systems, it
/// only takes one.
///
/// Symlinks are followed.
///
/// `sub_path` may be absolute, in which case `self` is ignored.
///
/// * On Windows, `sub_path` should be encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
/// * On WASI, `sub_path` should be encoded as valid UTF-8.
/// * On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn statFile(dir: Dir, io: Io, sub_path: []const u8, options: StatFileOptions) StatFileError!Stat {
    return io.vtable.dirStatFile(io.userdata, dir, sub_path, options);
}

pub const RealPathError = File.RealPathError;

/// Obtains the canonicalized absolute path name of `sub_path` relative to this
/// `Dir`. If `sub_path` is absolute, ignores this `Dir` handle and obtains the
/// canonicalized absolute pathname of `sub_path` argument.
///
/// This function has limited platform support, and using it can lead to
/// unnecessary failures and race conditions. It is generally advisable to
/// avoid this function entirely.
pub fn realPath(dir: Dir, io: Io, out_buffer: []u8) RealPathError!usize {
    return io.vtable.dirRealPath(io.userdata, dir, out_buffer);
}

pub const RealPathFileError = RealPathError || PathNameError;

/// Obtains the canonicalized absolute path name of `sub_path` relative to this
/// `Dir`. If `sub_path` is absolute, ignores this `Dir` handle and obtains the
/// canonicalized absolute pathname of `sub_path` argument.
///
/// This function has limited platform support, and using it can lead to
/// unnecessary failures and race conditions. It is generally advisable to
/// avoid this function entirely.
///
/// See also:
/// * `realPathFileAlloc`.
/// * `realPathFileAbsolute`.
pub fn realPathFile(dir: Dir, io: Io, sub_path: []const u8, out_buffer: []u8) RealPathFileError!usize {
    return io.vtable.dirRealPathFile(io.userdata, dir, sub_path, out_buffer);
}

pub const RealPathFileAllocError = RealPathFileError || Allocator.Error;

/// Same as `realPathFile` except allocates result.
///
/// This function has limited platform support, and using it can lead to
/// unnecessary failures and race conditions. It is generally advisable to
/// avoid this function entirely.
///
/// See also:
/// * `realPathFile`.
/// * `realPathFileAbsolute`.
pub fn realPathFileAlloc(dir: Dir, io: Io, sub_path: []const u8, allocator: Allocator) RealPathFileAllocError![:0]u8 {
    var buffer: [max_path_bytes]u8 = undefined;
    const n = try realPathFile(dir, io, sub_path, &buffer);
    return allocator.dupeZ(u8, buffer[0..n]);
}

/// Same as `realPathFile` except `absolute_path` is asserted to be an absolute
/// path.
///
/// This function has limited platform support, and using it can lead to
/// unnecessary failures and race conditions. It is generally advisable to
/// avoid this function entirely.
///
/// See also:
/// * `realPathFile`.
/// * `realPathFileAlloc`.
pub fn realPathFileAbsolute(io: Io, absolute_path: []const u8, out_buffer: []u8) RealPathFileError!usize {
    assert(path.isAbsolute(absolute_path));
    return io.vtable.dirRealPathFile(io.userdata, .cwd(), absolute_path, out_buffer);
}

/// Same as `realPathFileAbsolute` except allocates result.
///
/// This function has limited platform support, and using it can lead to
/// unnecessary failures and race conditions. It is generally advisable to
/// avoid this function entirely.
///
/// See also:
/// * `realPathFileAbsolute`.
/// * `realPathFile`.
pub fn realPathFileAbsoluteAlloc(io: Io, absolute_path: []const u8, allocator: Allocator) RealPathFileAllocError![:0]u8 {
    var buffer: [max_path_bytes]u8 = undefined;
    const n = try realPathFileAbsolute(io, absolute_path, &buffer);
    return allocator.dupeZ(u8, buffer[0..n]);
}

pub const DeleteFileError = error{
    FileNotFound,
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to unlink a resource by path relative to it.
    AccessDenied,
    PermissionDenied,
    FileBusy,
    FileSystem,
    IsDir,
    SymLinkLoop,
    NotDir,
    SystemResources,
    ReadOnlyFileSystem,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Delete a file name and possibly the file it refers to, based on an open directory handle.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
///
/// Asserts that the path parameter has no null bytes.
pub fn deleteFile(dir: Dir, io: Io, sub_path: []const u8) DeleteFileError!void {
    return io.vtable.dirDeleteFile(io.userdata, dir, sub_path);
}

pub fn deleteFileAbsolute(io: Io, absolute_path: []const u8) DeleteFileError!void {
    assert(path.isAbsolute(absolute_path));
    return deleteFile(.cwd(), io, absolute_path);
}

test deleteFileAbsolute {}

pub const DeleteDirError = error{
    DirNotEmpty,
    FileNotFound,
    AccessDenied,
    PermissionDenied,
    FileBusy,
    FileSystem,
    SymLinkLoop,
    NotDir,
    SystemResources,
    ReadOnlyFileSystem,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Returns `error.DirNotEmpty` if the directory is not empty.
///
/// To delete a directory recursively, see `deleteTree`.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn deleteDir(dir: Dir, io: Io, sub_path: []const u8) DeleteDirError!void {
    return io.vtable.dirDeleteDir(io.userdata, dir, sub_path);
}

/// Same as `deleteDir` except the path is absolute.
///
/// On Windows, `dir_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `dir_path` should be encoded as valid UTF-8.
/// On other platforms, `dir_path` is an opaque sequence of bytes with no particular encoding.
pub fn deleteDirAbsolute(io: Io, absolute_path: []const u8) DeleteDirError!void {
    assert(path.isAbsolute(absolute_path));
    return deleteDir(.cwd(), io, absolute_path);
}

pub const RenameError = error{
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to rename a resource by path relative to it.
    AccessDenied,
    /// Attempted to replace a nonempty directory.
    DirNotEmpty,
    PermissionDenied,
    /// The file attempted to be moved or replaced is a running executable.
    FileBusy,
    DiskQuota,
    IsDir,
    SymLinkLoop,
    LinkQuotaExceeded,
    FileNotFound,
    NotDir,
    SystemResources,
    NoSpaceLeft,
    ReadOnlyFileSystem,
    CrossDevice,
    NoDevice,
    PipeBusy,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
    /// On Windows, antivirus software is enabled by default. It can be
    /// disabled, but Windows Update sometimes ignores the user's preference
    /// and re-enables it. When enabled, antivirus software on Windows
    /// intercepts file system operations and makes them significantly slower
    /// in addition to possibly failing with this error code.
    AntivirusInterference,
    HardwareFailure,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Change the name or location of a file or directory.
///
/// If `new_sub_path` already exists, it will be replaced.
///
/// Renaming a file over an existing directory or a directory over an existing
/// file will fail with `error.IsDir` or `error.NotDir`
///
/// * On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// * On WASI, both paths should be encoded as valid UTF-8.
/// * On other platforms, both paths are an opaque sequence of bytes with no particular encoding.
pub fn rename(
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    io: Io,
) RenameError!void {
    return io.vtable.dirRename(io.userdata, old_dir, old_sub_path, new_dir, new_sub_path);
}

pub fn renameAbsolute(old_path: []const u8, new_path: []const u8, io: Io) RenameError!void {
    assert(path.isAbsolute(old_path));
    assert(path.isAbsolute(new_path));
    const my_cwd = cwd();
    return io.vtable.dirRename(io.userdata, my_cwd, old_path, my_cwd, new_path);
}

pub const RenamePreserveError = error{
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to rename a resource by path relative to it.
    ///
    /// On Windows, this error may be returned instead of PathAlreadyExists when
    /// renaming a directory over an existing directory.
    AccessDenied,
    PathAlreadyExists,
    /// Operating system or file system does not support atomic nonreplacing
    /// rename.
    OperationUnsupported,
} || RenameError;

/// Change the name or location of a file or directory.
///
/// If `new_sub_path` already exists, `error.PathAlreadyExists` will be returned.
///
/// Renaming a file over an existing directory or a directory over an existing
/// file will fail with `error.IsDir` or `error.NotDir`
///
/// * On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// * On WASI, both paths should be encoded as valid UTF-8.
/// * On other platforms, both paths are an opaque sequence of bytes with no particular encoding.
pub fn renamePreserve(
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    io: Io,
) RenamePreserveError!void {
    return io.vtable.dirRenamePreserve(io.userdata, old_dir, old_sub_path, new_dir, new_sub_path);
}

pub const HardLinkOptions = File.HardLinkOptions;

pub const HardLinkError = File.HardLinkError;

pub fn hardLink(
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
    io: Io,
    options: HardLinkOptions,
) HardLinkError!void {
    return io.vtable.dirHardLink(io.userdata, old_dir, old_sub_path, new_dir, new_sub_path, options);
}

/// Use with `symLink`, `symLinkAtomic`, and `symLinkAbsolute` to
/// specify whether the symlink will point to a file or a directory. This value
/// is ignored on all hosts except Windows where creating symlinks to different
/// resource types, requires different flags. By default, `symLinkAbsolute` is
/// assumed to point to a file.
pub const SymLinkFlags = struct {
    is_directory: bool = false,
};

pub const SymLinkError = error{
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to create a new symbolic link relative to it.
    AccessDenied,
    PermissionDenied,
    DiskQuota,
    PathAlreadyExists,
    FileSystem,
    SymLinkLoop,
    FileNotFound,
    SystemResources,
    NoSpaceLeft,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
    ReadOnlyFileSystem,
    NotDir,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Creates a symbolic link named `sym_link_path` which contains the string `target_path`.
///
/// A symbolic link (also known as a soft link) may point to an existing file or to a nonexistent
/// one; the latter case is known as a dangling link.
///
/// If `sym_link_path` exists, it will not be overwritten.
///
/// On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, both paths should be encoded as valid UTF-8.
/// On other platforms, both paths are an opaque sequence of bytes with no particular encoding.
pub fn symLink(
    dir: Dir,
    io: Io,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: SymLinkFlags,
) SymLinkError!void {
    return io.vtable.dirSymLink(io.userdata, dir, target_path, sym_link_path, flags);
}

pub fn symLinkAbsolute(
    io: Io,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: SymLinkFlags,
) SymLinkError!void {
    assert(path.isAbsolute(target_path));
    assert(path.isAbsolute(sym_link_path));
    return symLink(.cwd(), io, target_path, sym_link_path, flags);
}

/// Same as `symLink`, except tries to create the symbolic link until it
/// succeeds or encounters an error other than `error.PathAlreadyExists`.
///
/// * On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// * On WASI, both paths should be encoded as valid UTF-8.
/// * On other platforms, both paths are an opaque sequence of bytes with no particular encoding.
pub fn symLinkAtomic(
    dir: Dir,
    io: Io,
    target_path: []const u8,
    sym_link_path: []const u8,
    flags: SymLinkFlags,
) !void {
    if (dir.symLink(io, target_path, sym_link_path, flags)) {
        return;
    } else |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    }

    const dirname = path.dirname(sym_link_path) orelse ".";

    const rand_len = @sizeOf(u64) * 2;
    const temp_path_len = dirname.len + 1 + rand_len;
    var temp_path_buf: [max_path_bytes]u8 = undefined;

    if (temp_path_len > temp_path_buf.len) return error.NameTooLong;
    @memcpy(temp_path_buf[0..dirname.len], dirname);
    temp_path_buf[dirname.len] = path.sep;

    const temp_path = temp_path_buf[0..temp_path_len];

    var random_integer: u64 = undefined;

    while (true) {
        io.random(@ptrCast(&random_integer));
        temp_path[dirname.len + 1 ..][0..rand_len].* = std.fmt.hex(random_integer);

        if (dir.symLink(io, target_path, temp_path, flags)) {
            return dir.rename(temp_path, dir, sym_link_path, io);
        } else |err| switch (err) {
            error.PathAlreadyExists => continue,
            else => |e| return e,
        }
    }
}

pub const ReadLinkError = error{
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to read value of a symbolic link relative to it.
    AccessDenied,
    PermissionDenied,
    FileSystem,
    SymLinkLoop,
    FileNotFound,
    SystemResources,
    NotLink,
    NotDir,
    /// Windows-only. This error may occur if the opened reparse point is
    /// of unsupported type.
    UnsupportedReparsePointType,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
    /// On Windows, antivirus software is enabled by default. It can be
    /// disabled, but Windows Update sometimes ignores the user's preference
    /// and re-enables it. When enabled, antivirus software on Windows
    /// intercepts file system operations and makes them significantly slower
    /// in addition to possibly failing with this error code.
    AntivirusInterference,
    /// File attempted to be opened is a running executable.
    FileBusy,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Obtain target of a symbolic link.
///
/// Returns how many bytes of `buffer` are populated.
///
/// Asserts that the path parameter has no null bytes.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn readLink(dir: Dir, io: Io, sub_path: []const u8, buffer: []u8) ReadLinkError!usize {
    return io.vtable.dirReadLink(io.userdata, dir, sub_path, buffer);
}

/// Same as `readLink`, except it asserts the path is absolute.
///
/// On Windows, `path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `path` should be encoded as valid UTF-8.
/// On other platforms, `path` is an opaque sequence of bytes with no particular encoding.
pub fn readLinkAbsolute(io: Io, absolute_path: []const u8, buffer: []u8) ReadLinkError!usize {
    assert(path.isAbsolute(absolute_path));
    return io.vtable.dirReadLink(io.userdata, .cwd(), absolute_path, buffer);
}

pub const ReadFileAllocError = File.OpenError || File.Reader.Error || Allocator.Error || error{
    /// File size reached or exceeded the provided limit.
    StreamTooLong,
};

/// Reads all the bytes from the named file. On success, caller owns returned
/// buffer.
///
/// If the file size is already known, a better alternative is to initialize a
/// `File.Reader`.
///
/// If the file size cannot be obtained, an error is returned. If
/// this is a realistic possibility, a better alternative is to initialize a
/// `File.Reader` which handles this seamlessly.
pub fn readFileAlloc(
    dir: Dir,
    io: Io,
    /// On Windows, should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
    /// On WASI, should be encoded as valid UTF-8.
    /// On other platforms, an opaque sequence of bytes with no particular encoding.
    sub_path: []const u8,
    /// Used to allocate the result.
    gpa: Allocator,
    /// If reached or exceeded, `error.StreamTooLong` is returned instead.
    limit: Io.Limit,
) ReadFileAllocError![]u8 {
    return readFileAllocOptions(dir, io, sub_path, gpa, limit, .of(u8), null);
}

/// Reads all the bytes from the named file. On success, caller owns returned
/// buffer.
///
/// If the file size is already known, a better alternative is to initialize a
/// `File.Reader`.
pub fn readFileAllocOptions(
    dir: Dir,
    io: Io,
    /// On Windows, should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
    /// On WASI, should be encoded as valid UTF-8.
    /// On other platforms, an opaque sequence of bytes with no particular encoding.
    sub_path: []const u8,
    /// Used to allocate the result.
    gpa: Allocator,
    /// If reached or exceeded, `error.StreamTooLong` is returned instead.
    limit: Io.Limit,
    comptime alignment: std.mem.Alignment,
    comptime sentinel: ?u8,
) ReadFileAllocError!(if (sentinel) |s| [:s]align(alignment.toByteUnits()) u8 else []align(alignment.toByteUnits()) u8) {
    var file = try dir.openFile(io, sub_path, .{
        // We can take advantage of this on Windows since it doesn't involve any extra syscalls,
        // so we can get error.IsDir during open rather than during the read.
        .allow_directory = if (native_os == .windows) false else true,
    });
    defer file.close(io);
    var file_reader = file.reader(io, &.{});
    return file_reader.interface.allocRemainingAlignedSentinel(gpa, limit, alignment, sentinel) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err.?,
        error.OutOfMemory, error.StreamTooLong => |e| return e,
    };
}

pub const DeleteTreeError = error{
    AccessDenied,
    PermissionDenied,
    FileTooBig,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NoDevice,
    SystemResources,
    ReadOnlyFileSystem,
    FileSystem,
    FileBusy,
    /// One of the path components was not a directory.
    /// This error is unreachable if `sub_path` does not contain a path separator.
    NotDir,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
} || PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Whether `sub_path` describes a symlink, file, or directory, this function
/// removes it. If it cannot be removed because it is a non-empty directory,
/// this function recursively removes its entries and then tries again.
///
/// This operation is not atomic on most file systems.
///
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn deleteTree(dir: Dir, io: Io, sub_path: []const u8) DeleteTreeError!void {
    var initial_iterable_dir = (try dir.deleteTreeOpenInitialSubpath(io, sub_path, .file)) orelse return;

    const StackItem = struct {
        name: []const u8,
        parent_dir: Dir,
        iter: Iterator,

        fn closeAll(inner_io: Io, items: []@This()) void {
            for (items) |*item| item.iter.reader.dir.close(inner_io);
        }
    };

    var stack_buffer: [16]StackItem = undefined;
    var stack = std.ArrayList(StackItem).initBuffer(&stack_buffer);
    defer StackItem.closeAll(io, stack.items);

    stack.appendAssumeCapacity(.{
        .name = sub_path,
        .parent_dir = dir,
        .iter = initial_iterable_dir.iterateAssumeFirstIteration(),
    });

    process_stack: while (stack.items.len != 0) {
        var top = &stack.items[stack.items.len - 1];
        while (try top.iter.next(io)) |entry| {
            var treat_as_dir = entry.kind == .directory;
            handle_entry: while (true) {
                if (treat_as_dir) {
                    if (stack.unusedCapacitySlice().len >= 1) {
                        var iterable_dir = top.iter.reader.dir.openDir(io, entry.name, .{
                            .follow_symlinks = false,
                            .iterate = true,
                        }) catch |err| switch (err) {
                            error.NotDir => {
                                treat_as_dir = false;
                                continue :handle_entry;
                            },
                            error.FileNotFound => {
                                // That's fine, we were trying to remove this directory anyway.
                                break :handle_entry;
                            },

                            error.AccessDenied,
                            error.PermissionDenied,
                            error.SymLinkLoop,
                            error.ProcessFdQuotaExceeded,
                            error.NameTooLong,
                            error.SystemFdQuotaExceeded,
                            error.NoDevice,
                            error.SystemResources,
                            error.Unexpected,
                            error.BadPathName,
                            error.NetworkNotFound,
                            error.Canceled,
                            => |e| return e,
                        };
                        stack.appendAssumeCapacity(.{
                            .name = entry.name,
                            .parent_dir = top.iter.reader.dir,
                            .iter = iterable_dir.iterateAssumeFirstIteration(),
                        });
                        continue :process_stack;
                    } else {
                        try top.iter.reader.dir.deleteTreeMinStackSizeWithKindHint(io, entry.name, entry.kind);
                        break :handle_entry;
                    }
                } else {
                    if (top.iter.reader.dir.deleteFile(io, entry.name)) {
                        break :handle_entry;
                    } else |err| switch (err) {
                        error.FileNotFound => break :handle_entry,

                        // Impossible because we do not pass any path separators.
                        error.NotDir => unreachable,

                        error.IsDir => {
                            treat_as_dir = true;
                            continue :handle_entry;
                        },

                        error.AccessDenied,
                        error.PermissionDenied,
                        error.SymLinkLoop,
                        error.NameTooLong,
                        error.SystemResources,
                        error.ReadOnlyFileSystem,
                        error.FileSystem,
                        error.FileBusy,
                        error.BadPathName,
                        error.NetworkNotFound,
                        error.Canceled,
                        error.Unexpected,
                        => |e| return e,
                    }
                }
            }
        }

        // On Windows, we can't delete until the dir's handle has been closed, so
        // close it before we try to delete.
        top.iter.reader.dir.close(io);

        // In order to avoid double-closing the directory when cleaning up
        // the stack in the case of an error, we save the relevant portions and
        // pop the value from the stack.
        const parent_dir = top.parent_dir;
        const name = top.name;
        stack.items.len -= 1;

        var need_to_retry: bool = false;
        parent_dir.deleteDir(io, name) catch |err| switch (err) {
            error.FileNotFound => {},
            error.DirNotEmpty => need_to_retry = true,
            else => |e| return e,
        };

        if (need_to_retry) {
            // Since we closed the handle that the previous iterator used, we
            // need to re-open the dir and re-create the iterator.
            var iterable_dir = iterable_dir: {
                var treat_as_dir = true;
                handle_entry: while (true) {
                    if (treat_as_dir) {
                        break :iterable_dir parent_dir.openDir(io, name, .{
                            .follow_symlinks = false,
                            .iterate = true,
                        }) catch |err| switch (err) {
                            error.NotDir => {
                                treat_as_dir = false;
                                continue :handle_entry;
                            },
                            error.FileNotFound => {
                                // That's fine, we were trying to remove this directory anyway.
                                continue :process_stack;
                            },

                            error.AccessDenied,
                            error.PermissionDenied,
                            error.SymLinkLoop,
                            error.ProcessFdQuotaExceeded,
                            error.NameTooLong,
                            error.SystemFdQuotaExceeded,
                            error.NoDevice,
                            error.SystemResources,
                            error.Unexpected,
                            error.BadPathName,
                            error.NetworkNotFound,
                            error.Canceled,
                            => |e| return e,
                        };
                    } else {
                        if (parent_dir.deleteFile(io, name)) {
                            continue :process_stack;
                        } else |err| switch (err) {
                            error.FileNotFound => continue :process_stack,

                            // Impossible because we do not pass any path separators.
                            error.NotDir => unreachable,

                            error.IsDir => {
                                treat_as_dir = true;
                                continue :handle_entry;
                            },

                            error.AccessDenied,
                            error.PermissionDenied,
                            error.SymLinkLoop,
                            error.NameTooLong,
                            error.SystemResources,
                            error.ReadOnlyFileSystem,
                            error.FileSystem,
                            error.FileBusy,
                            error.BadPathName,
                            error.NetworkNotFound,
                            error.Canceled,
                            error.Unexpected,
                            => |e| return e,
                        }
                    }
                }
            };
            // We know there is room on the stack since we are just re-adding
            // the StackItem that we previously popped.
            stack.appendAssumeCapacity(.{
                .name = name,
                .parent_dir = parent_dir,
                .iter = iterable_dir.iterateAssumeFirstIteration(),
            });
            continue :process_stack;
        }
    }
}

/// Like `deleteTree`, but only keeps one `Iterator` active at a time to minimize the function's stack size.
/// This is slower than `deleteTree` but uses less stack space.
/// On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, `sub_path` should be encoded as valid UTF-8.
/// On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn deleteTreeMinStackSize(dir: Dir, io: Io, sub_path: []const u8) DeleteTreeError!void {
    return dir.deleteTreeMinStackSizeWithKindHint(io, sub_path, .file);
}

fn deleteTreeMinStackSizeWithKindHint(parent: Dir, io: Io, sub_path: []const u8, kind_hint: File.Kind) DeleteTreeError!void {
    start_over: while (true) {
        var dir = (try parent.deleteTreeOpenInitialSubpath(io, sub_path, kind_hint)) orelse return;
        var cleanup_dir_parent: ?Dir = null;
        defer if (cleanup_dir_parent) |*d| d.close(io);

        var cleanup_dir = true;
        defer if (cleanup_dir) dir.close(io);

        // Valid use of max_path_bytes because dir_name_buf will only
        // ever store a single path component that was returned from the
        // filesystem.
        var dir_name_buf: [max_path_bytes]u8 = undefined;
        var dir_name: []const u8 = sub_path;

        // Here we must avoid recursion, in order to provide O(1) memory guarantee of this function.
        // Go through each entry and if it is not a directory, delete it. If it is a directory,
        // open it, and close the original directory. Repeat. Then start the entire operation over.

        scan_dir: while (true) {
            var dir_it = dir.iterateAssumeFirstIteration();
            dir_it: while (try dir_it.next(io)) |entry| {
                var treat_as_dir = entry.kind == .directory;
                handle_entry: while (true) {
                    if (treat_as_dir) {
                        const new_dir = dir.openDir(io, entry.name, .{
                            .follow_symlinks = false,
                            .iterate = true,
                        }) catch |err| switch (err) {
                            error.NotDir => {
                                treat_as_dir = false;
                                continue :handle_entry;
                            },
                            error.FileNotFound => {
                                // That's fine, we were trying to remove this directory anyway.
                                continue :dir_it;
                            },

                            error.AccessDenied,
                            error.PermissionDenied,
                            error.SymLinkLoop,
                            error.ProcessFdQuotaExceeded,
                            error.NameTooLong,
                            error.SystemFdQuotaExceeded,
                            error.NoDevice,
                            error.SystemResources,
                            error.Unexpected,
                            error.BadPathName,
                            error.NetworkNotFound,
                            error.Canceled,
                            => |e| return e,
                        };
                        if (cleanup_dir_parent) |*d| d.close(io);
                        cleanup_dir_parent = dir;
                        dir = new_dir;
                        const result = dir_name_buf[0..entry.name.len];
                        @memcpy(result, entry.name);
                        dir_name = result;
                        continue :scan_dir;
                    } else {
                        if (dir.deleteFile(io, entry.name)) {
                            continue :dir_it;
                        } else |err| switch (err) {
                            error.FileNotFound => continue :dir_it,

                            // Impossible because we do not pass any path separators.
                            error.NotDir => unreachable,

                            error.IsDir => {
                                treat_as_dir = true;
                                continue :handle_entry;
                            },

                            error.AccessDenied,
                            error.PermissionDenied,
                            error.SymLinkLoop,
                            error.NameTooLong,
                            error.SystemResources,
                            error.ReadOnlyFileSystem,
                            error.FileSystem,
                            error.FileBusy,
                            error.BadPathName,
                            error.NetworkNotFound,
                            error.Canceled,
                            error.Unexpected,
                            => |e| return e,
                        }
                    }
                }
            }
            // Reached the end of the directory entries, which means we successfully deleted all of them.
            // Now to remove the directory itself.
            dir.close(io);
            cleanup_dir = false;

            if (cleanup_dir_parent) |d| {
                d.deleteDir(io, dir_name) catch |err| switch (err) {
                    // These two things can happen due to file system race conditions.
                    error.FileNotFound, error.DirNotEmpty => continue :start_over,
                    else => |e| return e,
                };
                continue :start_over;
            } else {
                parent.deleteDir(io, sub_path) catch |err| switch (err) {
                    error.FileNotFound => return,
                    error.DirNotEmpty => continue :start_over,
                    else => |e| return e,
                };
                return;
            }
        }
    }
}

/// On successful delete, returns null.
fn deleteTreeOpenInitialSubpath(dir: Dir, io: Io, sub_path: []const u8, kind_hint: File.Kind) !?Dir {
    return iterable_dir: {
        // Treat as a file by default
        var treat_as_dir = kind_hint == .directory;

        handle_entry: while (true) {
            if (treat_as_dir) {
                break :iterable_dir dir.openDir(io, sub_path, .{
                    .follow_symlinks = false,
                    .iterate = true,
                }) catch |err| switch (err) {
                    error.NotDir => {
                        treat_as_dir = false;
                        continue :handle_entry;
                    },
                    error.FileNotFound => {
                        // That's fine, we were trying to remove this directory anyway.
                        return null;
                    },

                    error.AccessDenied,
                    error.PermissionDenied,
                    error.SymLinkLoop,
                    error.ProcessFdQuotaExceeded,
                    error.NameTooLong,
                    error.SystemFdQuotaExceeded,
                    error.NoDevice,
                    error.SystemResources,
                    error.Unexpected,
                    error.BadPathName,
                    error.NetworkNotFound,
                    error.Canceled,
                    => |e| return e,
                };
            } else {
                if (dir.deleteFile(io, sub_path)) {
                    return null;
                } else |err| switch (err) {
                    error.FileNotFound => return null,

                    error.IsDir => {
                        treat_as_dir = true;
                        continue :handle_entry;
                    },

                    error.AccessDenied,
                    error.PermissionDenied,
                    error.SymLinkLoop,
                    error.NameTooLong,
                    error.SystemResources,
                    error.ReadOnlyFileSystem,
                    error.NotDir,
                    error.FileSystem,
                    error.FileBusy,
                    error.BadPathName,
                    error.NetworkNotFound,
                    error.Canceled,
                    error.Unexpected,
                    => |e| return e,
                }
            }
        }
    };
}

pub const CopyFileOptions = struct {
    /// When this is `null` the permissions are copied from the source file.
    permissions: ?File.Permissions = null,
    make_path: bool = false,
    replace: bool = true,
};

pub const CopyFileError = File.OpenError || File.StatError ||
    CreateFileAtomicError || File.Atomic.ReplaceError || File.Atomic.LinkError ||
    File.Reader.Error || File.Writer.Error || error{InvalidFileName};

/// Atomically creates a new file at `dest_path` within `dest_dir` with the
/// same contents as `source_path` within `source_dir`.
///
/// Whether to overwrite the existing file is determined by `options`.
///
/// On Linux, until https://patchwork.kernel.org/patch/9636735/ is merged and
/// readily available, there is a possibility of power loss or application
/// termination leaving temporary files present in the same directory as
/// dest_path.
///
/// On Windows, both paths should be encoded as
/// [WTF-8](https://wtf-8.codeberg.page/). On WASI, both paths should be
/// encoded as valid UTF-8. On other platforms, both paths are an opaque
/// sequence of bytes with no particular encoding.
pub fn copyFile(
    source_dir: Dir,
    source_path: []const u8,
    dest_dir: Dir,
    dest_path: []const u8,
    io: Io,
    options: CopyFileOptions,
) CopyFileError!void {
    const file = try source_dir.openFile(io, source_path, .{});
    var file_reader: File.Reader = .init(file, io, &.{});
    defer file_reader.file.close(io);

    const permissions = options.permissions orelse blk: {
        const st = try file_reader.file.stat(io);
        file_reader.size = st.size;
        break :blk st.permissions;
    };

    var atomic_file = try dest_dir.createFileAtomic(io, dest_path, .{
        .permissions = permissions,
        .make_path = options.make_path,
        .replace = options.replace,
    });
    defer atomic_file.deinit(io);

    var buffer: [1024]u8 = undefined; // Used only when direct fd-to-fd is not available.
    var file_writer = atomic_file.file.writer(io, &buffer);

    _ = file_writer.interface.sendFileAll(&file_reader, .unlimited) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err.?,
        error.WriteFailed => return file_writer.err.?,
    };

    try file_writer.flush();

    switch (options.replace) {
        true => try atomic_file.replace(io),
        false => try atomic_file.link(io),
    }
}

/// Same as `copyFile`, except asserts that both `source_path` and `dest_path`
/// are absolute.
///
/// On Windows, both paths should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// On WASI, both paths should be encoded as valid UTF-8.
/// On other platforms, both paths are an opaque sequence of bytes with no particular encoding.
pub fn copyFileAbsolute(
    source_path: []const u8,
    dest_path: []const u8,
    io: Io,
    options: CopyFileOptions,
) !void {
    assert(path.isAbsolute(source_path));
    assert(path.isAbsolute(dest_path));
    const my_cwd = cwd();
    return copyFile(my_cwd, source_path, my_cwd, dest_path, io, options);
}

test copyFileAbsolute {}

pub const CreateFileAtomicOptions = struct {
    permissions: File.Permissions = .default_file,
    make_path: bool = false,
    /// Tells whether the unnamed file will be ultimately created with
    /// `File.Atomic.link` or `File.Atomic.replace`.
    ///
    /// If this value is incorrect it will cause an assertion failure in
    /// `File.Atomic.replace`.
    replace: bool = false,
};

pub const CreateFileAtomicError = error{
    NoDevice,
    /// On Windows, `\\server` or `\\server\share` was not found.
    NetworkNotFound,
    /// On Windows, antivirus software is enabled by default. It can be
    /// disabled, but Windows Update sometimes ignores the user's preference
    /// and re-enables it. When enabled, antivirus software on Windows
    /// intercepts file system operations and makes them significantly slower
    /// in addition to possibly failing with this error code.
    AntivirusInterference,
    /// In WASI, this error may occur when the file descriptor does
    /// not hold the required rights to open a new resource relative to it.
    AccessDenied,
    PermissionDenied,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    /// Either:
    /// * One of the path components does not exist.
    /// * Cwd was used, but cwd has been deleted.
    /// * The path associated with the open directory handle has been deleted.
    FileNotFound,
    /// Insufficient kernel memory was available.
    SystemResources,
    /// A new path cannot be created because the device has no room for the new file.
    NoSpaceLeft,
    /// A component used as a directory in the path was not, in fact, a directory.
    NotDir,
    WouldBlock,
    ReadOnlyFileSystem,
    /// The file attempted to be created is a running executable.
    FileBusy,
} || Io.Dir.PathNameError || Io.Cancelable || Io.UnexpectedError;

/// Create an unnamed ephemeral file that can eventually be atomically
/// materialized into `sub_path`.
///
/// The returned `File.Atomic` provides API to emulate the behavior in case it
/// is not directly supported by the underlying operating system.
///
/// * On Windows, `sub_path` should be encoded as [WTF-8](https://wtf-8.codeberg.page/).
/// * On WASI, `sub_path` should be encoded as valid UTF-8.
/// * On other platforms, `sub_path` is an opaque sequence of bytes with no particular encoding.
pub fn createFileAtomic(
    dir: Dir,
    io: Io,
    sub_path: []const u8,
    options: CreateFileAtomicOptions,
) CreateFileAtomicError!File.Atomic {
    return io.vtable.dirCreateFileAtomic(io.userdata, dir, sub_path, options);
}

pub const SetPermissionsError = File.SetPermissionsError;
pub const Permissions = File.Permissions;

/// Also known as "chmod".
///
/// The process must have the correct privileges in order to do this
/// successfully, or must have the effective user ID matching the owner
/// of the directory. Additionally, the directory must have been opened
/// with `OpenOptions.iterate` set to `true`.
pub fn setPermissions(dir: Dir, io: Io, new_permissions: File.Permissions) SetPermissionsError!void {
    return io.vtable.dirSetPermissions(io.userdata, dir, new_permissions);
}

pub const SetFilePermissionsError = PathNameError || SetPermissionsError || error{
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    /// `SetFilePermissionsOptions.follow_symlinks` was set to false, which is
    /// not allowed by the file system or operating system.
    OperationUnsupported,
};

pub const SetFilePermissionsOptions = struct {
    follow_symlinks: bool = true,
};

/// Also known as "fchmodat".
pub fn setFilePermissions(
    dir: Dir,
    io: Io,
    sub_path: []const u8,
    new_permissions: File.Permissions,
    options: SetFilePermissionsOptions,
) SetFilePermissionsError!void {
    return io.vtable.dirSetFilePermissions(io.userdata, dir, sub_path, new_permissions, options);
}

pub const SetOwnerError = File.SetOwnerError;

/// Also known as "chown".
///
/// The process must have the correct privileges in order to do this
/// successfully. The group may be changed by the owner of the directory to
/// any group of which the owner is a member. Additionally, the directory
/// must have been opened with `OpenOptions.iterate` set to `true`. If the
/// owner or group is specified as `null`, the ID is not changed.
pub fn setOwner(dir: Dir, io: Io, owner: ?File.Uid, group: ?File.Gid) SetOwnerError!void {
    return io.vtable.dirSetOwner(io.userdata, dir, owner, group);
}

pub const SetFileOwnerError = PathNameError || SetOwnerError;

pub const SetFileOwnerOptions = struct {
    follow_symlinks: bool = true,
};

/// Also known as "fchownat".
pub fn setFileOwner(
    dir: Dir,
    io: Io,
    sub_path: []const u8,
    owner: ?File.Uid,
    group: ?File.Gid,
    options: SetFileOwnerOptions,
) SetOwnerError!void {
    return io.vtable.dirSetFileOwner(io.userdata, dir, sub_path, owner, group, options);
}

pub const SetTimestampsError = File.SetTimestampsError || PathNameError;

pub const SetTimestampsOptions = struct {
    follow_symlinks: bool = true,
    access_timestamp: File.SetTimestamp = .unchanged,
    modify_timestamp: File.SetTimestamp = .unchanged,
};

/// The granularity that ultimately is stored depends on the combination of
/// operating system and file system. When a value as provided that exceeds
/// this range, the value is clamped to the maximum.
pub fn setTimestamps(
    dir: Dir,
    io: Io,
    sub_path: []const u8,
    options: SetTimestampsOptions,
) SetTimestampsError!void {
    return io.vtable.dirSetTimestamps(io.userdata, dir, sub_path, options);
}

pub const SetTimestampsNowOptions = struct {
    follow_symlinks: bool = true,
};

/// Sets the accessed and modification timestamps of the provided path to the
/// current wall clock time.
///
/// The granularity that ultimately is stored depends on the combination of
/// operating system and file system.
pub fn setTimestampsNow(
    dir: Dir,
    io: Io,
    sub_path: []const u8,
    options: SetTimestampsNowOptions,
) SetTimestampsError!void {
    return io.vtable.fileSetTimestamps(io.userdata, dir, sub_path, .{
        .follow_symlinks = options.follow_symlinks,
        .access_timestamp = .now,
        .modify_timestamp = .now,
    });
}
