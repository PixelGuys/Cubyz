//! WriteFile is used to create a directory in an appropriate location inside
//! the local cache which has a set of files that have either been generated
//! during the build, or are copied from the source package.
const WriteFile = @This();

const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const Step = std.Build.Step;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

step: Step,

/// The elements here are pointers because we need stable pointers for the GeneratedFile field.
files: std.ArrayList(File),
directories: std.ArrayList(Directory),
generated_directory: std.Build.GeneratedFile,
mode: Mode = .whole_cached,

pub const base_id: Step.Id = .write_file;

pub const Mode = union(enum) {
    /// Default mode. Integrates with the cache system. The directory should be
    /// read-only during the make phase. Any different inputs result in
    /// different "o" subdirectory.
    whole_cached,
    /// In this mode, the directory will be placed inside "tmp" rather than
    /// "o", and caching will be skipped. During the `make` phase, the step
    /// will always do all the file system operations, and on successful build
    /// completion, the dir will be deleted along with all other tmp
    /// directories. The directory is therefore eligible to be used for
    /// mutations by other steps.
    tmp,
    /// The operations will not be performed against a freshly created
    /// directory, but instead act against a temporary directory.
    mutate: std.Build.LazyPath,
};

pub const File = struct {
    sub_path: []const u8,
    contents: Contents,
};

pub const Directory = struct {
    source: std.Build.LazyPath,
    sub_path: []const u8,
    options: Options,

    pub const Options = struct {
        /// File paths that end in any of these suffixes will be excluded from copying.
        exclude_extensions: []const []const u8 = &.{},
        /// Only file paths that end in any of these suffixes will be included in copying.
        /// `null` means that all suffixes will be included.
        /// `exclude_extensions` takes precedence over `include_extensions`.
        include_extensions: ?[]const []const u8 = null,

        pub fn dupe(opts: Options, b: *std.Build) Options {
            return .{
                .exclude_extensions = b.dupeStrings(opts.exclude_extensions),
                .include_extensions = if (opts.include_extensions) |incs| b.dupeStrings(incs) else null,
            };
        }

        pub fn pathIncluded(opts: Options, path: []const u8) bool {
            for (opts.exclude_extensions) |ext| {
                if (std.mem.endsWith(u8, path, ext))
                    return false;
            }
            if (opts.include_extensions) |incs| {
                for (incs) |inc| {
                    if (std.mem.endsWith(u8, path, inc))
                        return true;
                } else {
                    return false;
                }
            }
            return true;
        }
    };
};

pub const Contents = union(enum) {
    bytes: []const u8,
    copy: std.Build.LazyPath,
};

pub fn create(owner: *std.Build) *WriteFile {
    const write_file = owner.allocator.create(WriteFile) catch @panic("OOM");
    write_file.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = "WriteFile",
            .owner = owner,
            .makeFn = make,
        }),
        .files = .empty,
        .directories = .empty,
        .generated_directory = .{ .step = &write_file.step },
    };
    return write_file;
}

pub fn add(write_file: *WriteFile, sub_path: []const u8, bytes: []const u8) std.Build.LazyPath {
    const b = write_file.step.owner;
    const gpa = b.allocator;
    const file = File{
        .sub_path = b.dupePath(sub_path),
        .contents = .{ .bytes = b.dupe(bytes) },
    };
    write_file.files.append(gpa, file) catch @panic("OOM");
    write_file.maybeUpdateName();
    return .{
        .generated = .{
            .file = &write_file.generated_directory,
            .sub_path = file.sub_path,
        },
    };
}

/// Place the file into the generated directory within the local cache,
/// along with all the rest of the files added to this step. The parameter
/// here is the destination path relative to the local cache directory
/// associated with this WriteFile. It may be a basename, or it may
/// include sub-directories, in which case this step will ensure the
/// required sub-path exists.
/// This is the option expected to be used most commonly with `addCopyFile`.
pub fn addCopyFile(write_file: *WriteFile, source: std.Build.LazyPath, sub_path: []const u8) std.Build.LazyPath {
    const b = write_file.step.owner;
    const gpa = b.allocator;
    const file = File{
        .sub_path = b.dupePath(sub_path),
        .contents = .{ .copy = source },
    };
    write_file.files.append(gpa, file) catch @panic("OOM");

    write_file.maybeUpdateName();
    source.addStepDependencies(&write_file.step);
    return .{
        .generated = .{
            .file = &write_file.generated_directory,
            .sub_path = file.sub_path,
        },
    };
}

/// Copy files matching the specified exclude/include patterns to the specified subdirectory
/// relative to this step's generated directory.
/// The returned value is a lazy path to the generated subdirectory.
pub fn addCopyDirectory(
    write_file: *WriteFile,
    source: std.Build.LazyPath,
    sub_path: []const u8,
    options: Directory.Options,
) std.Build.LazyPath {
    const b = write_file.step.owner;
    const gpa = b.allocator;
    const dir = Directory{
        .source = source.dupe(b),
        .sub_path = b.dupePath(sub_path),
        .options = options.dupe(b),
    };
    write_file.directories.append(gpa, dir) catch @panic("OOM");

    write_file.maybeUpdateName();
    source.addStepDependencies(&write_file.step);
    return .{
        .generated = .{
            .file = &write_file.generated_directory,
            .sub_path = dir.sub_path,
        },
    };
}

/// Returns a `LazyPath` representing the base directory that contains all the
/// files from this `WriteFile`.
pub fn getDirectory(write_file: *WriteFile) std.Build.LazyPath {
    return .{ .generated = .{ .file = &write_file.generated_directory } };
}

fn maybeUpdateName(write_file: *WriteFile) void {
    if (write_file.files.items.len == 1 and write_file.directories.items.len == 0) {
        // First time adding a file; update name.
        if (std.mem.eql(u8, write_file.step.name, "WriteFile")) {
            write_file.step.name = write_file.step.owner.fmt("WriteFile {s}", .{write_file.files.items[0].sub_path});
        }
    } else if (write_file.directories.items.len == 1 and write_file.files.items.len == 0) {
        // First time adding a directory; update name.
        if (std.mem.eql(u8, write_file.step.name, "WriteFile")) {
            write_file.step.name = write_file.step.owner.fmt("WriteFile {s}", .{write_file.directories.items[0].sub_path});
        }
    }
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    _ = options;
    const b = step.owner;
    const graph = b.graph;
    const io = graph.io;
    const arena = b.allocator;
    const gpa = graph.cache.gpa;
    const write_file: *WriteFile = @fieldParentPtr("step", step);

    const open_dir_cache = try arena.alloc(Io.Dir, write_file.directories.items.len);
    var open_dirs_count: usize = 0;
    defer Io.Dir.closeMany(io, open_dir_cache[0..open_dirs_count]);

    switch (write_file.mode) {
        .whole_cached => {
            step.clearWatchInputs();

            // The cache is used here not really as a way to speed things up - because writing
            // the data to a file would probably be very fast - but as a way to find a canonical
            // location to put build artifacts.

            // If, for example, a hard-coded path was used as the location to put WriteFile
            // files, then two WriteFiles executing in parallel might clobber each other.

            var man = b.graph.cache.obtain();
            defer man.deinit();

            for (write_file.files.items) |file| {
                man.hash.addBytes(file.sub_path);

                switch (file.contents) {
                    .bytes => |bytes| {
                        man.hash.addBytes(bytes);
                    },
                    .copy => |lazy_path| {
                        const path = lazy_path.getPath3(b, step);
                        _ = try man.addFilePath(path, null);
                        try step.addWatchInput(lazy_path);
                    },
                }
            }

            for (write_file.directories.items, open_dir_cache) |dir, *open_dir_cache_elem| {
                man.hash.addBytes(dir.sub_path);
                for (dir.options.exclude_extensions) |ext| man.hash.addBytes(ext);
                if (dir.options.include_extensions) |incs| for (incs) |inc| man.hash.addBytes(inc);

                const need_derived_inputs = try step.addDirectoryWatchInput(dir.source);
                const src_dir_path = dir.source.getPath3(b, step);

                var src_dir = src_dir_path.root_dir.handle.openDir(io, src_dir_path.subPathOrDot(), .{ .iterate = true }) catch |err| {
                    return step.fail("unable to open source directory '{f}': {s}", .{
                        src_dir_path, @errorName(err),
                    });
                };
                open_dir_cache_elem.* = src_dir;
                open_dirs_count += 1;

                var it = try src_dir.walk(gpa);
                defer it.deinit();
                while (try it.next(io)) |entry| {
                    if (!dir.options.pathIncluded(entry.path)) continue;

                    switch (entry.kind) {
                        .directory => {
                            if (need_derived_inputs) {
                                const entry_path = try src_dir_path.join(arena, entry.path);
                                try step.addDirectoryWatchInputFromPath(entry_path);
                            }
                        },
                        .file => {
                            const entry_path = try src_dir_path.join(arena, entry.path);
                            _ = try man.addFilePath(entry_path, null);
                        },
                        else => continue,
                    }
                }
            }

            if (try step.cacheHit(&man)) {
                const digest = man.final();
                write_file.generated_directory.path = try b.cache_root.join(arena, &.{ "o", &digest });
                assert(step.result_cached);
                return;
            }

            const digest = man.final();
            const cache_path = "o" ++ Dir.path.sep_str ++ digest;

            write_file.generated_directory.path = try b.cache_root.join(arena, &.{cache_path});

            try operate(write_file, open_dir_cache, .{
                .root_dir = b.cache_root,
                .sub_path = cache_path,
            });

            try step.writeManifest(&man);
        },
        .tmp => {
            step.result_cached = false;

            var rand_int: u64 = undefined;
            io.random(@ptrCast(&rand_int));
            const tmp_dir_sub_path = "tmp" ++ Dir.path.sep_str ++ std.fmt.hex(rand_int);

            write_file.generated_directory.path = try b.cache_root.join(arena, &.{tmp_dir_sub_path});

            try operate(write_file, open_dir_cache, .{
                .root_dir = b.cache_root,
                .sub_path = tmp_dir_sub_path,
            });
        },
        .mutate => |lp| {
            step.result_cached = false;
            const root_path = try lp.getPath4(b, step);
            write_file.generated_directory.path = try root_path.toString(arena);
            try operate(write_file, open_dir_cache, root_path);
        },
    }
}

fn operate(write_file: *WriteFile, open_dir_cache: []const Io.Dir, root_path: std.Build.Cache.Path) !void {
    const step = &write_file.step;
    const b = step.owner;
    const io = b.graph.io;
    const gpa = b.graph.cache.gpa;
    const arena = b.allocator;

    var cache_dir = root_path.root_dir.handle.createDirPathOpen(io, root_path.sub_path, .{}) catch |err|
        return step.fail("unable to make path {f}: {t}", .{ root_path, err });
    defer cache_dir.close(io);

    for (write_file.files.items) |file| {
        if (Dir.path.dirname(file.sub_path)) |dirname| {
            cache_dir.createDirPath(io, dirname) catch |err| {
                return step.fail("unable to make path '{f}{c}{s}': {t}", .{
                    root_path, Dir.path.sep, dirname, err,
                });
            };
        }
        switch (file.contents) {
            .bytes => |bytes| {
                cache_dir.writeFile(io, .{ .sub_path = file.sub_path, .data = bytes }) catch |err| {
                    return step.fail("unable to write file '{f}{c}{s}': {t}", .{
                        root_path, Dir.path.sep, file.sub_path, err,
                    });
                };
            },
            .copy => |file_source| {
                const source_path = file_source.getPath2(b, step);
                const prev_status = Io.Dir.updateFile(.cwd(), io, source_path, cache_dir, file.sub_path, .{}) catch |err| {
                    return step.fail("unable to update file from '{s}' to '{f}{c}{s}': {t}", .{
                        source_path, root_path, Dir.path.sep, file.sub_path, err,
                    });
                };
                // At this point we already will mark the step as a cache miss.
                // But this is kind of a partial cache hit since individual
                // file copies may be avoided. Oh well, this information is
                // discarded.
                _ = prev_status;
            },
        }
    }

    for (write_file.directories.items, open_dir_cache) |dir, already_open_dir| {
        const src_dir_path = dir.source.getPath3(b, step);
        const dest_dirname = dir.sub_path;

        if (dest_dirname.len != 0) {
            cache_dir.createDirPath(io, dest_dirname) catch |err| {
                return step.fail("unable to make path '{f}{c}{s}': {t}", .{
                    root_path, Dir.path.sep, dest_dirname, err,
                });
            };
        }

        var it = try already_open_dir.walk(gpa);
        defer it.deinit();
        while (try it.next(io)) |entry| {
            if (!dir.options.pathIncluded(entry.path)) continue;

            const src_entry_path = try src_dir_path.join(arena, entry.path);
            const dest_path = b.pathJoin(&.{ dest_dirname, entry.path });
            switch (entry.kind) {
                .directory => try cache_dir.createDirPath(io, dest_path),
                .file => {
                    const prev_status = Io.Dir.updateFile(
                        src_entry_path.root_dir.handle,
                        io,
                        src_entry_path.sub_path,
                        cache_dir,
                        dest_path,
                        .{},
                    ) catch |err| {
                        return step.fail("unable to update file from '{f}' to '{f}{c}{s}': {t}", .{
                            src_entry_path, root_path, Dir.path.sep, dest_path, err,
                        });
                    };
                    _ = prev_status;
                },
                else => continue,
            }
        }
    }
}
