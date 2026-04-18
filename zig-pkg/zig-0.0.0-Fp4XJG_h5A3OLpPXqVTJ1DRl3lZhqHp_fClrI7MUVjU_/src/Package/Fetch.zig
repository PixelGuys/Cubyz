//! Represents one independent job whose responsibility is to:
//!
//! 1. Check the local zig package directory to see if the hash already exists.
//!    If so, load, parse, and validate the build.zig.zon file therein, and
//!    goto step 9. Likewise if the location is a relative path, treat this
//!    the same as a cache hit. Otherwise, proceed.
//! 2. Check the global package cache for a compressed tarball matching the
//!    hash. If it is found, unpack the contents into a temporary directory inside
//!    project local zig cache. Rename this directory into the local zig package
//!    directory and goto step 9, skipping step 10.
//! 3. Fetch and unpack a URL into a temporary directory.
//! 4. Load, parse, and validate the build.zig.zon file therein. It is allowed
//!    for the file to be missing, in which case this fetched package is considered
//!    to be a "naked" package.
//! 5. Apply inclusion rules of the build.zig.zon to the temporary directory by
//!    deleting excluded files. If any files had errors for files that were
//!    ultimately excluded, those errors should be ignored, such as failure to
//!    create symlinks that weren't supposed to be included anyway.
//! 6. Compute the package hash based on the remaining files in the temporary
//!    directory.
//! 7. Rename the temporary directory into the local zig package directory. If
//!    the hash already exists, delete the temporary directory and leave the zig
//!    package directory untouched as it may be in use. This is done even if
//!    the hash is invalid, in case the package with the different hash is used
//!    in the future.
//! 8. Validate the computed hash against the expected hash. If invalid,
//!    this job is done.
//! 9. Spawn a new fetch job for each dependency in the manifest file. Use
//!    a mutex and a hash map so that redundant jobs do not get queued up.
//! 10.Compress the package directory and store it into the global package
//!    cache.
//!
//! All of this must be done with only referring to the state inside this struct
//! because this work will be done in a dedicated thread.
const Fetch = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std");
const Io = std.Io;
const fs = std.fs;
const log = std.log.scoped(.fetch);
const assert = std.debug.assert;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const git = @import("Fetch/git.zig");
const Package = @import("../Package.zig");
const Manifest = Package.Manifest;
const ErrorBundle = std.zig.ErrorBundle;

arena: std.heap.ArenaAllocator,
location: Location,
location_tok: std.zig.Ast.TokenIndex,
hash_tok: std.zig.Ast.OptionalTokenIndex,
name_tok: std.zig.Ast.TokenIndex,
lazy_status: LazyStatus,
parent_package_root: Cache.Path,
parent_manifest_ast: ?*const std.zig.Ast,
prog_node: std.Progress.Node,
job_queue: *JobQueue,
/// If true, don't add an error for a missing hash. This flag is not passed
/// down to recursive dependencies. It's intended to be used only be the CLI.
omit_missing_hash_error: bool,
/// If true, don't fail when a manifest file is missing the `paths` field,
/// which specifies inclusion rules. This is intended to be true for the first
/// fetch task and false for the recursive dependencies.
allow_missing_paths_field: bool,
/// If true and URL points to a Git repository, will use the latest commit.
use_latest_commit: bool,

// Above this are fields provided as inputs to `run`.
// Below this are fields populated by `run`.

/// Relative to the build root of the root package.
package_root: Cache.Path,
error_bundle: ErrorBundle.Wip,
manifest: Manifest,
manifest_ast: std.zig.Ast,
have_manifest: bool,
computed_hash: ComputedHash,
/// Fetch logic notices whether a package has a build.zig file and sets this flag.
has_build_zig: bool,
/// Indicates whether the task aborted due to an out-of-memory condition.
oom_flag: bool,
/// If `use_latest_commit` was true, this will be set to the commit that was used.
/// If the resource pointed to by the location is not a Git-repository, this
/// will be left unchanged.
latest_commit: ?git.Oid,

// This field is used by the CLI only, untouched by this file.

/// The module for this `Fetch` tasks's package, which exposes `build.zig` as
/// the root source file.
module: ?*Package.Module,

pub const LazyStatus = enum {
    /// Not lazy.
    eager,
    /// Lazy, found.
    available,
    /// Lazy, not found.
    unavailable,
};

/// Contains shared state among all `Fetch` tasks.
pub const JobQueue = struct {
    io: Io,
    mutex: Io.Mutex = .init,
    /// It's an array hash map so that it can be sorted before rendering the
    /// dependencies.zig source file.
    /// Protected by `mutex`.
    table: Table = .{},
    /// `table` may be missing some tasks such as ones that failed, so this
    /// field contains references to all of them.
    /// Protected by `mutex`.
    all_fetches: std.ArrayList(*Fetch) = .empty,
    prog_node: std.Progress.Node,

    http_client: *std.http.Client,
    /// This tracks `Fetch` tasks as well as recompression tasks.
    group: Io.Group = .init,
    global_cache: Cache.Directory,
    local_cache: Cache.Path,
    /// Path to "zig-pkg" inside the package in which the user ran `zig build`.
    root_pkg_path: Cache.Path,
    /// If true then, no fetching occurs, and:
    /// * The `global_cache` directory is assumed to be the direct parent
    ///   directory of on-disk packages rather than having the "p/" directory
    ///   prefix inside of it.
    /// * An error occurs if any non-lazy packages are not already present in
    ///   the package cache directory.
    /// * Missing hash field causes an error, and no fetching occurs so it does
    ///   not print the correct hash like usual.
    read_only: bool,
    recursive: bool,
    /// Dumps hash information to stdout which can be used to troubleshoot why
    /// two hashes of the same package do not match.
    /// If this is true, `recursive` must be false.
    debug_hash: bool,
    mode: Mode,
    /// Set of hashes that will be additionally fetched even if they are marked
    /// as lazy.
    unlazy_set: UnlazySet = .{},
    /// Identifies paths that override all packages in the tree with matching
    /// project ids.
    fork_set: ForkSet = .{},

    pub const Mode = enum {
        /// Non-lazy dependencies are always fetched.
        /// Lazy dependencies are fetched only when needed.
        needed,
        /// Both non-lazy and lazy dependencies are always fetched.
        all,
    };
    pub const Table = std.AutoArrayHashMapUnmanaged(Package.Hash, *Fetch);
    pub const UnlazySet = std.AutoArrayHashMapUnmanaged(Package.Hash, void);
    pub const ForkSet = std.ArrayHashMapUnmanaged(Fork, void, Fork.Context, false);

    pub const Fork = struct {
        path: Cache.Path,
        manifest_ast: std.zig.Ast,
        manifest: Package.Manifest,
        uses: usize,

        pub const Context = struct {
            pub fn hash(_: @This(), a: Fork) u32 {
                const project_id: Package.ProjectId = .init(a.manifest.name, a.manifest.id);
                return @truncate(project_id.hash());
            }

            pub fn eql(_: @This(), a: Fork, b: Fork, _: usize) bool {
                const a_project_id: Package.ProjectId = .init(a.manifest.name, a.manifest.id);
                const b_project_id: Package.ProjectId = .init(b.manifest.name, b.manifest.id);
                return a_project_id.eql(&b_project_id);
            }
        };

        pub const Adapter = struct {
            pub fn hash(_: @This(), a: Package.ProjectId) u32 {
                return @truncate(a.hash());
            }

            pub fn eql(_: @This(), a_project_id: Package.ProjectId, b: Fork, _: usize) bool {
                const b_project_id: Package.ProjectId = .init(b.manifest.name, b.manifest.id);
                return a_project_id.eql(&b_project_id);
            }
        };
    };

    pub fn deinit(jq: *JobQueue) void {
        const io = jq.io;
        jq.group.cancel(io);
        if (jq.all_fetches.items.len == 0) return;
        const gpa = jq.all_fetches.items[0].arena.child_allocator;
        jq.table.deinit(gpa);
        // These must be deinitialized in reverse order because subsequent
        // `Fetch` instances are allocated in prior ones' arenas.
        // Sorry, I know it's a bit weird, but it slightly simplifies the
        // critical section.
        while (jq.all_fetches.pop()) |f| f.deinit();
        jq.all_fetches.deinit(gpa);
        jq.* = undefined;
    }

    /// Dumps all subsequent error bundles into the first one.
    pub fn consolidateErrors(jq: *JobQueue) !void {
        const root = &jq.all_fetches.items[0].error_bundle;
        const gpa = root.gpa;
        for (jq.all_fetches.items[1..]) |fetch| {
            if (fetch.error_bundle.root_list.items.len > 0) {
                var bundle = try fetch.error_bundle.toOwnedBundle("");
                defer bundle.deinit(gpa);
                try root.addBundleAsRoots(bundle);
            }
        }
    }

    /// Creates the dependencies.zig source code for the build runner to obtain
    /// via `@import("@dependencies")`.
    pub fn createDependenciesSource(jq: *JobQueue, buf: *std.array_list.Managed(u8)) Allocator.Error!void {
        const keys = jq.table.keys();

        assert(keys.len != 0); // caller should have added the first one
        if (keys.len == 1) {
            // This is the first one. It must have no dependencies.
            return createEmptyDependenciesSource(buf);
        }

        try buf.appendSlice("pub const packages = struct {\n");

        // Ensure the generated .zig file is deterministic.
        jq.table.sortUnstable(@as(struct {
            keys: []const Package.Hash,
            pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
                return std.mem.lessThan(u8, &ctx.keys[a_index].bytes, &ctx.keys[b_index].bytes);
            }
        }, .{ .keys = keys }));

        for (keys, jq.table.values()) |*hash, fetch| {
            if (fetch == jq.all_fetches.items[0]) {
                // The first one is a dummy package for the current project.
                continue;
            }

            const hash_slice = hash.toSlice();

            try buf.print(
                \\    pub const {f} = struct {{
                \\
            , .{std.zig.fmtId(hash_slice)});

            lazy: {
                switch (fetch.lazy_status) {
                    .eager => break :lazy,
                    .available => {
                        try buf.appendSlice(
                            \\        pub const available = true;
                            \\
                        );
                        break :lazy;
                    },
                    .unavailable => {
                        try buf.appendSlice(
                            \\        pub const available = false;
                            \\    };
                            \\
                        );
                        continue;
                    },
                }
            }

            try buf.print(
                \\        pub const build_root = "{f}";
                \\
            , .{std.fmt.alt(fetch.package_root, .formatEscapeString)});

            if (fetch.has_build_zig) {
                try buf.print(
                    \\        pub const build_zig = @import("{f}");
                    \\
                , .{std.zig.fmtString(hash_slice)});
            }

            if (fetch.have_manifest) {
                const manifest = &fetch.manifest;
                try buf.appendSlice(
                    \\        pub const deps: []const struct { []const u8, []const u8 } = &.{
                    \\
                );
                for (manifest.dependencies.keys(), manifest.dependencies.values()) |name, dep| {
                    const h = depDigest(fetch.package_root, jq.global_cache, dep) orelse continue;
                    try buf.print(
                        "            .{{ \"{f}\", \"{f}\" }},\n",
                        .{ std.zig.fmtString(name), std.zig.fmtString(h.toSlice()) },
                    );
                }

                try buf.appendSlice(
                    \\        };
                    \\    };
                    \\
                );
            } else {
                try buf.appendSlice(
                    \\        pub const deps: []const struct { []const u8, []const u8 } = &.{};
                    \\    };
                    \\
                );
            }
        }

        try buf.appendSlice(
            \\};
            \\
            \\pub const root_deps: []const struct { []const u8, []const u8 } = &.{
            \\
        );

        const root_fetch = jq.all_fetches.items[0];
        assert(root_fetch.have_manifest);
        const root_manifest = &root_fetch.manifest;

        for (root_manifest.dependencies.keys(), root_manifest.dependencies.values()) |name, dep| {
            const h = depDigest(root_fetch.package_root, jq.global_cache, dep) orelse continue;
            try buf.print(
                "    .{{ \"{f}\", \"{f}\" }},\n",
                .{ std.zig.fmtString(name), std.zig.fmtString(h.toSlice()) },
            );
        }
        try buf.appendSlice("};\n");
    }

    pub fn createEmptyDependenciesSource(buf: *std.array_list.Managed(u8)) Allocator.Error!void {
        try buf.appendSlice(
            \\pub const packages = struct {};
            \\pub const root_deps: []const struct { []const u8, []const u8 } = &.{};
            \\
        );
    }

    fn recompress(jq: *JobQueue, package_hash: Package.Hash) Io.Cancelable!void {
        const pkg_hash_slice = package_hash.toSlice();

        const prog_node = jq.prog_node.startFmt(0, "recompress {s}", .{pkg_hash_slice});
        defer prog_node.end();

        var dest_sub_path_buf: ["p/".len + Package.Hash.max_len + ".tar.gz".len]u8 = undefined;
        const dest_path: Cache.Path = .{
            .root_dir = jq.global_cache,
            .sub_path = std.fmt.bufPrint(&dest_sub_path_buf, "p/{s}.tar.gz", .{pkg_hash_slice}) catch unreachable,
        };

        const gpa = jq.http_client.allocator;

        var arena_instance = std.heap.ArenaAllocator.init(gpa);
        defer arena_instance.deinit();
        const arena = arena_instance.allocator();

        recompressFallible(jq, arena, dest_path, pkg_hash_slice, prog_node) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.ReadFailed => comptime unreachable,
            error.WriteFailed => comptime unreachable,
            else => |e| log.warn("failed caching recompressed tarball to {f}: {t}", .{ dest_path, e }),
        };
    }

    fn recompressFallible(
        jq: *JobQueue,
        arena: Allocator,
        dest_path: Cache.Path,
        pkg_hash_slice: []const u8,
        prog_node: std.Progress.Node,
    ) !void {
        const gpa = jq.http_client.allocator;
        const io = jq.io;

        // We have to walk the file system up front in order to sort the file
        // list for determinism purposes. The hash of the recompressed file is
        // not critical because the true hash is based on the content alone.
        // However, if we want Zig users to be able to share cached package
        // data with each other via peer-to-peer protocols, we benefit greatly
        // from the data being identical on everyone's computers.
        var scanned_files: std.ArrayList(ScannedFile) = .empty;
        defer scanned_files.deinit(gpa);

        var pkg_dir = try jq.root_pkg_path.openDir(io, pkg_hash_slice, .{ .iterate = true });
        defer pkg_dir.close(io);

        {
            var walker = try pkg_dir.walk(gpa);
            defer walker.deinit();

            while (try walker.next(io)) |entry| {
                const symlink = switch (entry.kind) {
                    .directory => continue,
                    .file => false,
                    .sym_link => true,
                    else => return error.IllegalFileType,
                };
                const entry_path = try arena.dupe(u8, entry.path);
                // If necessary, normalize path separators to POSIX-style since the tar format requires that.
                if (comptime (std.fs.path.sep != std.fs.path.sep_posix)) {
                    std.mem.replaceScalar(u8, entry_path, std.fs.path.sep, std.fs.path.sep_posix);
                }
                try scanned_files.append(gpa, .{
                    .ptr = entry_path.ptr,
                    .len = @intCast(entry_path.len),
                    .symlink = symlink,
                });
            }

            std.mem.sortUnstable(ScannedFile, scanned_files.items, {}, stringCmp);
        }

        prog_node.setEstimatedTotalItems(scanned_files.items.len);

        var atomic_file = try dest_path.root_dir.handle.createFileAtomic(io, dest_path.sub_path, .{
            .make_path = true,
            .replace = true,
        });
        defer atomic_file.deinit(io);

        var file_write_buffer: [4096]u8 = undefined;
        var file_writer = atomic_file.file.writer(io, &file_write_buffer);

        var compress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
        var compress = std.compress.flate.Compress.init(&file_writer.interface, &compress_buffer, .gzip, .level_9) catch |err| switch (err) {
            error.WriteFailed => return file_writer.err.?,
        };

        var archiver: std.tar.Writer = .{ .underlying_writer = &compress.writer };
        archiver.prefix = pkg_hash_slice;

        var file_read_buffer: [4096]u8 = undefined;
        var link_buf: [fs.max_path_bytes]u8 = undefined;

        for (scanned_files.items) |scanned_file| {
            const entry_path = scanned_file.ptr[0..scanned_file.len];
            if (scanned_file.symlink) {
                const link_name = link_buf[0..try pkg_dir.readLink(io, entry_path, &link_buf)];
                archiver.writeLink(entry_path, link_name, .{}) catch |err| switch (err) {
                    error.WriteFailed => return file_writer.err.?,
                    else => |e| return e,
                };
            } else {
                var file = try pkg_dir.openFile(io, entry_path, .{});
                defer file.close(io);
                var file_reader: Io.File.Reader = .init(file, io, &file_read_buffer);
                archiver.writeFile(entry_path, &file_reader, 0) catch |err| switch (err) {
                    error.ReadFailed => return file_reader.err.?,
                    error.WriteFailed => return file_writer.err.?,
                    else => |e| return e,
                };
            }
            prog_node.completeOne();
        }

        // intentionally omitting the pointless trailer
        //try archiver.finish();
        compress.finish() catch |err| switch (err) {
            error.WriteFailed => return file_writer.err.?,
        };
        try file_writer.flush();
        try atomic_file.replace(io);
    }
};

const ScannedFile = struct {
    ptr: [*]const u8,
    len: u32,
    symlink: bool,
};

fn stringCmp(_: void, lhs: ScannedFile, rhs: ScannedFile) bool {
    return std.mem.lessThan(u8, lhs.ptr[0..lhs.len], rhs.ptr[0..rhs.len]);
}

pub const Location = union(enum) {
    remote: Remote,
    /// A directory found inside the parent package.
    relative_path: Cache.Path,
    /// Recursive Fetch tasks will never use this Location, but it may be
    /// passed in by the CLI. Indicates the file contents here should be copied
    /// into the global package cache. It may be a file relative to the cwd or
    /// absolute, in which case it should be treated exactly like a `file://`
    /// URL, or a directory, in which case it should be treated as an
    /// already-unpacked directory (but still needs to be copied into the
    /// global package cache and have inclusion rules applied).
    path_or_url: []const u8,

    pub const Remote = struct {
        url: []const u8,
        /// If this is null it means the user omitted the hash field from a dependency.
        /// It will be an error but the logic should still fetch and print the discovered hash.
        hash: ?Package.Hash,
    };
};

pub const RunError = error{
    OutOfMemory,
    Canceled,
    /// This error code is intended to be handled by inspecting the
    /// `error_bundle` field.
    FetchFailed,
};

pub fn run(f: *Fetch) RunError!void {
    const job_queue = f.job_queue;
    const io = job_queue.io;
    const eb = &f.error_bundle;
    const arena = f.arena.allocator();
    const gpa = f.arena.child_allocator;
    const local_cache_root = job_queue.local_cache;

    try eb.init(gpa);

    // Check the global zig package cache to see if the hash already exists. If
    // so, load, parse, and validate the build.zig.zon file therein, and skip
    // ahead to queuing up jobs for dependencies. Likewise if the location is a
    // relative path, treat this the same as a cache hit. Otherwise, proceed.

    const remote = switch (f.location) {
        .relative_path => |pkg_root| {
            if (fs.path.isAbsolute(pkg_root.sub_path)) return f.fail(
                f.location_tok,
                try eb.addString("expected path relative to build root; found absolute path"),
            );
            if (f.hash_tok.unwrap()) |hash_tok| return f.fail(
                hash_tok,
                try eb.addString("path-based dependencies are not hashed"),
            );
            // Packages fetched by URL may not use relative paths to escape outside the
            // fetched package directory from within the package cache.
            if (pkg_root.root_dir.eql(local_cache_root.root_dir)) {
                // `parent_package_root.sub_path` contains a path like this:
                // "p/$hash", or
                // "p/$hash/foo", with possibly more directories after "foo".
                // We want to fail unless the resolved relative path has a
                // prefix of "p/$hash/".
                const prefix_len: usize = if (job_queue.read_only) 0 else "p/".len;
                const parent_sub_path = f.parent_package_root.sub_path;
                const end = find_end: {
                    if (parent_sub_path.len > prefix_len) {
                        // Use `isSep` instead of `indexOfScalarPos` to account for
                        // Windows accepting both `\` and `/` as path separators.
                        for (parent_sub_path[prefix_len..], prefix_len..) |c, i| {
                            if (std.fs.path.isSep(c)) break :find_end i;
                        }
                    }
                    break :find_end parent_sub_path.len;
                };
                const expected_prefix = parent_sub_path[0..end];
                if (!std.mem.startsWith(u8, pkg_root.sub_path, expected_prefix)) {
                    return f.fail(
                        f.location_tok,
                        try eb.printString("dependency path outside project: '{f}'", .{pkg_root}),
                    );
                }
            }
            f.package_root = pkg_root;
            try loadManifest(f, pkg_root);
            if (!f.has_build_zig) try checkBuildFileExistence(f);
            if (!job_queue.recursive) return;
            return queueJobsForDeps(f);
        },
        .remote => |remote| remote,
        .path_or_url => |path_or_url| {
            if (Io.Dir.cwd().openDir(io, path_or_url, .{ .iterate = true })) |dir| {
                var resource: Resource = .{ .dir = dir };
                return f.runResource(path_or_url, &resource, null, false);
            } else |dir_err| {
                var server_header_buffer: [init_resource_buffer_size]u8 = undefined;

                const file_err = if (dir_err == error.NotDir) e: {
                    if (Io.Dir.cwd().openFile(io, path_or_url, .{})) |file| {
                        var resource: Resource = .{ .file = file.reader(io, &server_header_buffer) };
                        return f.runResource(path_or_url, &resource, null, false);
                    } else |err| break :e err;
                } else dir_err;

                const uri = std.Uri.parse(path_or_url) catch |uri_err| {
                    return f.fail(0, try eb.printString(
                        "'{s}' could not be recognized as a file path ({t}) or an URL ({t})",
                        .{ path_or_url, file_err, uri_err },
                    ));
                };
                var resource: Resource = undefined;
                try f.initResource(uri, &resource, &server_header_buffer);
                return f.runResource(try uri.path.toRawMaybeAlloc(arena), &resource, null, false);
            }
        },
    };

    var resource_buffer: [init_resource_buffer_size]u8 = undefined;

    if (remote.hash) |expected_hash| {
        const expected_project_id: Package.ProjectId = expected_hash.projectId();
        if (job_queue.fork_set.getKeyPtrAdapted(expected_project_id, @as(JobQueue.Fork.Adapter, .{}))) |fork| {
            log.debug("using fork {f} for {s}", .{ fork.path, fork.manifest.name });
            fork.uses += 1;
            f.package_root = fork.path;
            f.manifest_ast = fork.manifest_ast;
            f.manifest = fork.manifest;
            f.have_manifest = true;
            try checkBuildFileExistence(f);
            if (!job_queue.recursive) return;
            return queueJobsForDeps(f);
        }

        const package_root = try job_queue.root_pkg_path.join(arena, expected_hash.toSlice());
        if (package_root.root_dir.handle.access(io, package_root.sub_path, .{})) |_| {
            assert(f.lazy_status != .unavailable);
            f.package_root = package_root;
            try loadManifest(f, f.package_root);
            try checkBuildFileExistence(f);
            if (!job_queue.recursive) return;
            return queueJobsForDeps(f);
        } else |err| switch (err) {
            error.FileNotFound => {
                log.debug("FileNotFound: {f}", .{package_root});
                if (job_queue.read_only and f.lazy_status == .eager) return f.fail(
                    f.name_tok,
                    try eb.printString("package not found at '{f}'", .{package_root}),
                );
            },
            error.Canceled => |e| return e,
            else => |e| {
                try eb.addRootErrorMessage(.{
                    .msg = try eb.printString("unable to open package cache directory {f}: {t}", .{
                        package_root, e,
                    }),
                });
                return error.FetchFailed;
            },
        }

        // Check global cache before remote fetch.
        const cached_tarball_sub_path = try std.fmt.allocPrint(arena, "p/{s}.tar.gz", .{expected_hash.toSlice()});
        const cached_tarball_path: Cache.Path = .{
            .root_dir = job_queue.global_cache,
            .sub_path = cached_tarball_sub_path,
        };
        if (cached_tarball_path.root_dir.handle.openFile(io, cached_tarball_path.sub_path, .{})) |file| {
            log.debug("found global cached tarball {f}", .{cached_tarball_path});
            var resource: Resource = .{ .file = file.reader(io, &resource_buffer) };
            return f.runResource(cached_tarball_sub_path, &resource, remote.hash, true);
        } else |err| switch (err) {
            error.FileNotFound => log.debug("FileNotFound: {f}", .{cached_tarball_path}),
            error.Canceled => |e| return e,
            else => |e| {
                try eb.addRootErrorMessage(.{
                    .msg = try eb.printString("unable to open globally cached package {f}: {t}", .{
                        cached_tarball_path, e,
                    }),
                });
                return error.FetchFailed;
            },
        }

        switch (f.lazy_status) {
            .eager => {},
            .available => if (!job_queue.unlazy_set.contains(expected_hash)) {
                f.lazy_status = .unavailable;
                return;
            },
            .unavailable => unreachable,
        }
    } else if (job_queue.read_only) {
        try eb.addRootErrorMessage(.{
            .msg = try eb.addString("dependency is missing hash field"),
            .src_loc = try f.srcLoc(f.location_tok),
        });
        return error.FetchFailed;
    }

    // Fetch and unpack the remote into a temporary directory.
    const uri = std.Uri.parse(remote.url) catch |err| return f.fail(
        f.location_tok,
        try eb.printString("invalid URI: {t}", .{err}),
    );
    var resource: Resource = undefined;
    try f.initResource(uri, &resource, &resource_buffer);
    return f.runResource(try uri.path.toRawMaybeAlloc(arena), &resource, remote.hash, false);
}

pub fn deinit(f: *Fetch) void {
    f.error_bundle.deinit();
    f.arena.deinit();
}

/// Consumes `resource`, even if an error is returned.
fn runResource(
    f: *Fetch,
    uri_path: []const u8,
    resource: *Resource,
    remote_hash: ?Package.Hash,
    disable_recompress: bool,
) RunError!void {
    const job_queue = f.job_queue;
    assert(!job_queue.read_only);

    const io = job_queue.io;
    defer resource.deinit(io);

    const arena = f.arena.allocator();
    const eb = &f.error_bundle;
    const rand_int = r: {
        var x: u64 = undefined;
        io.random(@ptrCast(&x));
        break :r x;
    };
    const tmp_dir_sub_path = ".tmp-" ++ std.fmt.hex(rand_int);
    const tmp_directory_path = try job_queue.root_pkg_path.join(arena, tmp_dir_sub_path);

    const package_sub_path = blk: {
        var tmp_directory: Cache.Directory = .{
            .path = tmp_directory_path.sub_path,
            .handle = handle: {
                const dir = tmp_directory_path.root_dir.handle.createDirPathOpen(io, tmp_directory_path.sub_path, .{
                    .open_options = .{ .iterate = true },
                }) catch |err| {
                    try eb.addRootErrorMessage(.{
                        .msg = try eb.printString("unable to create temporary directory '{f}': {t}", .{
                            tmp_directory_path, err,
                        }),
                    });
                    return error.FetchFailed;
                };
                break :handle dir;
            },
        };
        defer tmp_directory.handle.close(io);

        // Fetch and unpack a resource into a temporary directory.
        var unpack_result = try unpackResource(f, resource, uri_path, tmp_directory);

        const pkg_path: Cache.Path = .{ .root_dir = tmp_directory, .sub_path = unpack_result.root_dir };

        // Load, parse, and validate the unpacked build.zig.zon file. It is allowed
        // for the file to be missing, in which case this fetched package is
        // considered to be a "naked" package.
        try loadManifest(f, pkg_path);

        const filter: Filter = .{
            .include_paths = if (f.have_manifest) f.manifest.paths else .{},
        };

        // Ignore errors that were excluded by manifest, such as failure to
        // create symlinks that weren't supposed to be included anyway.
        try unpack_result.validate(f, filter);

        // Apply the manifest's inclusion rules to the temporary directory by
        // deleting excluded files.
        // Empty directories have already been omitted by `unpackResource`.
        // Compute the package hash based on the remaining files in the temporary
        // directory.
        f.computed_hash = try computeHash(f, pkg_path, filter);

        if (unpack_result.root_dir.len > 0)
            break :blk try tmp_directory_path.join(arena, unpack_result.root_dir);

        break :blk tmp_directory_path;
    };

    const computed_package_hash = computedPackageHash(f);

    // Rename the temporary directory into the local zig package directory. If
    // the hash already exists, delete the temporary directory and leave the
    // zig package directory untouched as it may be in use. This is done even
    // if the hash is invalid, in case the package with the different hash is
    // used in the future.
    f.package_root = try job_queue.root_pkg_path.join(arena, computed_package_hash.toSlice());
    renameTmpIntoCache(io, package_sub_path, f.package_root) catch |err| {
        try eb.addRootErrorMessage(.{ .msg = try eb.printString(
            "unable to rename temporary directory {f} into package cache directory {f}: {t}",
            .{ package_sub_path, f.package_root, err },
        ) });
        return error.FetchFailed;
    };

    if (!disable_recompress) {
        // Spin off a task to recompress the tarball, with filtered files deleted, into
        // the global cache.
        job_queue.group.async(io, JobQueue.recompress, .{ job_queue, computed_package_hash });
    }

    // Remove temporary directory root if not already renamed to global cache.
    if (!package_sub_path.eql(tmp_directory_path)) {
        tmp_directory_path.root_dir.handle.deleteDir(io, tmp_directory_path.sub_path) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| log.warn("failed to delete temporary directory {f}: {t}", .{ tmp_directory_path, e }),
        };
    }

    // Validate the computed hash against the expected hash. If invalid, this
    // job is done.

    if (remote_hash) |declared_hash| {
        const hash_tok = f.hash_tok.unwrap().?;
        if (!computed_package_hash.eql(&declared_hash)) {
            return f.fail(hash_tok, try eb.printString(
                "hash mismatch: manifest declares {s} but the fetched package has {s}",
                .{ declared_hash.toSlice(), computed_package_hash.toSlice() },
            ));
        }
    } else if (!f.omit_missing_hash_error) {
        const notes_len = 1;
        try eb.addRootErrorMessage(.{
            .msg = try eb.addString("dependency is missing hash field"),
            .src_loc = try f.srcLoc(f.location_tok),
            .notes_len = notes_len,
        });
        const notes_start = try eb.reserveNotes(notes_len);
        eb.extra.items[notes_start] = @intFromEnum(try eb.addErrorMessage(.{
            .msg = try eb.printString("expected .hash = \"{s}\",", .{computed_package_hash.toSlice()}),
        }));
        return error.FetchFailed;
    }

    // Spawn a new fetch job for each dependency in the manifest file. Use
    // a mutex and a hash map so that redundant jobs do not get queued up.
    if (!job_queue.recursive) return;
    return queueJobsForDeps(f);
}

pub fn computedPackageHash(f: *const Fetch) Package.Hash {
    const saturated_size = std.math.cast(u32, f.computed_hash.total_size) orelse std.math.maxInt(u32);
    if (f.have_manifest) {
        const man = &f.manifest;
        var version_buffer: [32]u8 = undefined;
        const version: []const u8 = std.fmt.bufPrint(&version_buffer, "{f}", .{man.version}) catch &version_buffer;
        return .init(f.computed_hash.digest, man.name, version, man.id, saturated_size);
    }
    // In the future build.zig.zon fields will be added to allow overriding these values
    // for naked tarballs.
    return .init(f.computed_hash.digest, "N", "V", 0xffff, saturated_size);
}

/// `computeHash` gets a free check for the existence of `build.zig`, but when
/// not computing a hash, we need to do a syscall to check for it.
fn checkBuildFileExistence(f: *Fetch) RunError!void {
    const io = f.job_queue.io;
    const eb = &f.error_bundle;
    if (f.package_root.access(io, Package.build_zig_basename, .{})) |_| {
        f.has_build_zig = true;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |e| {
            try eb.addRootErrorMessage(.{
                .msg = try eb.printString("unable to access '{f}{s}': {t}", .{
                    f.package_root, Package.build_zig_basename, e,
                }),
            });
            return error.FetchFailed;
        },
    }
}

/// This function populates `f.manifest` or leaves it `null`.
fn loadManifest(f: *Fetch, pkg_root: Cache.Path) RunError!void {
    const io = f.job_queue.io;
    const eb = &f.error_bundle;
    const arena = f.arena.allocator();
    const manifest_path = try pkg_root.join(arena, Manifest.basename);

    Manifest.load(
        io,
        arena,
        manifest_path,
        &f.manifest_ast,
        eb,
        &f.manifest,
        f.allow_missing_paths_field,
    ) catch |err| switch (err) {
        error.FileNotFound => return,
        error.Canceled => |e| return e,
        error.ErrorsBundled => return error.FetchFailed,
        else => |e| {
            try eb.addRootErrorMessage(.{
                .msg = try eb.printString("unable to load package manifest '{f}': {t}", .{ manifest_path, e }),
            });
            return error.FetchFailed;
        },
    };
    f.have_manifest = true;
}

fn queueJobsForDeps(f: *Fetch) RunError!void {
    const io = f.job_queue.io;

    assert(f.job_queue.recursive);

    // If the package does not have a build.zig.zon file then there are no dependencies.
    if (!f.have_manifest) return;
    const manifest = &f.manifest;

    const new_fetches, const prog_names = nf: {
        const parent_arena = f.arena.allocator();
        const gpa = f.arena.child_allocator;
        const cache_root = f.job_queue.global_cache;
        const dep_names = manifest.dependencies.keys();
        const deps = manifest.dependencies.values();
        // Grab the new tasks into a temporary buffer so we can unlock that mutex
        // as fast as possible.
        // This overallocates any fetches that get skipped by the `continue` in the
        // loop below.
        const new_fetches = try parent_arena.alloc(Fetch, deps.len);
        const prog_names = try parent_arena.alloc([]const u8, deps.len);
        var new_fetch_index: usize = 0;

        try f.job_queue.mutex.lock(io);
        defer f.job_queue.mutex.unlock(io);

        try f.job_queue.all_fetches.ensureUnusedCapacity(gpa, new_fetches.len);
        try f.job_queue.table.ensureUnusedCapacity(gpa, @intCast(new_fetches.len));

        // There are four cases here:
        // * Correct hash is provided by manifest.
        //   - Hash map already has the entry, no need to add it again.
        // * Incorrect hash is provided by manifest.
        //   - Hash mismatch error emitted; `queueJobsForDeps` is not called.
        // * Hash is not provided by manifest.
        //   - Hash missing error emitted; `queueJobsForDeps` is not called.
        // * path-based location is used without a hash.
        //   - Hash is added to the table based on the path alone before
        //     calling run(); no need to add it again.
        //
        // If we add a dep as lazy and then later try to add the same dep as eager,
        // eagerness takes precedence and the existing entry is updated and re-scheduled
        // for fetching.

        for (dep_names, deps) |dep_name, dep| {
            var promoted_existing_to_eager = false;
            const new_fetch = &new_fetches[new_fetch_index];
            const location: Location = switch (dep.location) {
                .url => |url| .{
                    .remote = .{
                        .url = url,
                        .hash = h: {
                            const h = dep.hash orelse break :h null;
                            const pkg_hash: Package.Hash = .fromSlice(h);
                            if (h.len == 0) break :h pkg_hash;
                            const gop = f.job_queue.table.getOrPutAssumeCapacity(pkg_hash);
                            if (gop.found_existing) {
                                if (!dep.lazy and gop.value_ptr.*.lazy_status != .eager) {
                                    gop.value_ptr.*.lazy_status = .eager;
                                    promoted_existing_to_eager = true;
                                } else {
                                    continue;
                                }
                            }
                            gop.value_ptr.* = new_fetch;
                            break :h pkg_hash;
                        },
                    },
                },
                .path => |rel_path| l: {
                    // This might produce an invalid path, which is checked for
                    // at the beginning of run().
                    const new_root = try f.package_root.resolvePosix(parent_arena, rel_path);
                    const pkg_hash = relativePathDigest(new_root, cache_root);
                    const gop = f.job_queue.table.getOrPutAssumeCapacity(pkg_hash);
                    if (gop.found_existing) {
                        if (!dep.lazy and gop.value_ptr.*.lazy_status != .eager) {
                            gop.value_ptr.*.lazy_status = .eager;
                            promoted_existing_to_eager = true;
                        } else {
                            continue;
                        }
                    }
                    gop.value_ptr.* = new_fetch;
                    break :l .{ .relative_path = new_root };
                },
            };
            prog_names[new_fetch_index] = dep_name;
            new_fetch_index += 1;
            if (!promoted_existing_to_eager) {
                f.job_queue.all_fetches.appendAssumeCapacity(new_fetch);
            }
            new_fetch.* = .{
                .arena = std.heap.ArenaAllocator.init(gpa),
                .location = location,
                .location_tok = dep.location_tok,
                .hash_tok = dep.hash_tok,
                .name_tok = dep.name_tok,
                .lazy_status = switch (f.job_queue.mode) {
                    .needed => if (dep.lazy) .available else .eager,
                    .all => .eager,
                },
                .parent_package_root = f.package_root,
                .parent_manifest_ast = &f.manifest_ast,
                .prog_node = f.prog_node,
                .job_queue = f.job_queue,
                .omit_missing_hash_error = false,
                .allow_missing_paths_field = true,
                .use_latest_commit = false,

                .package_root = undefined,
                .error_bundle = undefined,
                .manifest = undefined,
                .manifest_ast = undefined,
                .have_manifest = false,
                .computed_hash = undefined,
                .has_build_zig = false,
                .oom_flag = false,
                .latest_commit = null,

                .module = null,
            };
        }

        f.prog_node.increaseEstimatedTotalItems(new_fetch_index);

        break :nf .{ new_fetches[0..new_fetch_index], prog_names[0..new_fetch_index] };
    };

    // Now it's time to dispatch tasks.
    for (new_fetches, prog_names) |*new_fetch, prog_name| {
        f.job_queue.group.async(io, workerRun, .{ new_fetch, prog_name });
    }
}

pub fn relativePathDigest(pkg_root: Cache.Path, cache_root: Cache.Directory) Package.Hash {
    return .initPath(pkg_root.sub_path, pkg_root.root_dir.eql(cache_root));
}

pub fn workerRun(f: *Fetch, prog_name: []const u8) Io.Cancelable!void {
    const prog_node = f.prog_node.start(prog_name, 0);
    defer prog_node.end();

    run(f) catch |err| switch (err) {
        error.OutOfMemory => f.oom_flag = true,
        error.Canceled => |e| return e,
        error.FetchFailed => {
            // Nothing to do because the errors are already reported in `error_bundle`,
            // and a reference is kept to the `Fetch` task inside `all_fetches`.
        },
    };
}

fn srcLoc(
    f: *Fetch,
    tok: std.zig.Ast.TokenIndex,
) Allocator.Error!ErrorBundle.SourceLocationIndex {
    const ast = f.parent_manifest_ast orelse return .none;
    const eb = &f.error_bundle;
    const start_loc = ast.tokenLocation(0, tok);
    const src_path = try eb.printString("{f}" ++ fs.path.sep_str ++ Manifest.basename, .{f.parent_package_root});
    const msg_off = 0;
    return eb.addSourceLocation(.{
        .src_path = src_path,
        .span_start = ast.tokenStart(tok),
        .span_end = @intCast(ast.tokenStart(tok) + ast.tokenSlice(tok).len),
        .span_main = ast.tokenStart(tok) + msg_off,
        .line = @intCast(start_loc.line),
        .column = @intCast(start_loc.column),
        .source_line = try eb.addString(ast.source[start_loc.line_start..start_loc.line_end]),
    });
}

fn fail(f: *Fetch, msg_tok: std.zig.Ast.TokenIndex, msg_str: u32) RunError {
    const eb = &f.error_bundle;
    try eb.addRootErrorMessage(.{
        .msg = msg_str,
        .src_loc = try f.srcLoc(msg_tok),
    });
    return error.FetchFailed;
}

const Resource = union(enum) {
    file: Io.File.Reader,
    http_request: HttpRequest,
    git: Git,
    dir: Io.Dir,

    const Git = struct {
        session: git.Session,
        fetch_stream: git.Session.FetchStream,
        want_oid: git.Oid,
    };

    const HttpRequest = struct {
        request: std.http.Client.Request,
        response: std.http.Client.Response,
        transfer_buffer: []u8,
        decompress: std.http.Decompress,
        decompress_buffer: []u8,
    };

    fn deinit(resource: *Resource, io: Io) void {
        switch (resource.*) {
            .file => |*file_reader| file_reader.file.close(io),
            .http_request => |*http_request| http_request.request.deinit(),
            .git => |*git_resource| {
                git_resource.fetch_stream.deinit();
            },
            .dir => |*dir| dir.close(io),
        }
        resource.* = undefined;
    }

    fn reader(resource: *Resource) *Io.Reader {
        return switch (resource.*) {
            .file => |*file_reader| return &file_reader.interface,
            .http_request => |*http_request| return http_request.response.readerDecompressing(
                http_request.transfer_buffer,
                &http_request.decompress,
                http_request.decompress_buffer,
            ),
            .git => |*g| return &g.fetch_stream.reader,
            .dir => unreachable,
        };
    }
};

const FileType = enum {
    tar,
    @"tar.gz",
    @"tar.xz",
    @"tar.zst",
    git_pack,
    zip,

    fn fromPath(file_path: []const u8) ?FileType {
        if (ascii.endsWithIgnoreCase(file_path, ".tar")) return .tar;
        if (ascii.endsWithIgnoreCase(file_path, ".tgz")) return .@"tar.gz";
        if (ascii.endsWithIgnoreCase(file_path, ".tar.gz")) return .@"tar.gz";
        if (ascii.endsWithIgnoreCase(file_path, ".txz")) return .@"tar.xz";
        if (ascii.endsWithIgnoreCase(file_path, ".tar.xz")) return .@"tar.xz";
        if (ascii.endsWithIgnoreCase(file_path, ".tzst")) return .@"tar.zst";
        if (ascii.endsWithIgnoreCase(file_path, ".tar.zst")) return .@"tar.zst";
        if (ascii.endsWithIgnoreCase(file_path, ".zip")) return .zip;
        if (ascii.endsWithIgnoreCase(file_path, ".jar")) return .zip;
        return null;
    }

    /// Parameter is a content-disposition header value.
    fn fromContentDisposition(cd_header: []const u8) ?FileType {
        const attach_end = ascii.indexOfIgnoreCase(cd_header, "attachment;") orelse
            return null;

        var value_start = ascii.indexOfIgnoreCasePos(cd_header, attach_end + 1, "filename") orelse
            return null;
        value_start += "filename".len;
        if (cd_header[value_start] == '*') {
            value_start += 1;
        }
        if (cd_header[value_start] != '=') return null;
        value_start += 1;

        var value_end = std.mem.indexOfPos(u8, cd_header, value_start, ";") orelse cd_header.len;
        if (cd_header[value_end - 1] == '\"') {
            value_end -= 1;
        }
        return fromPath(cd_header[value_start..value_end]);
    }

    test fromContentDisposition {
        try std.testing.expectEqual(@as(?FileType, .@"tar.gz"), fromContentDisposition("attaChment; FILENAME=\"stuff.tar.gz\"; size=42"));
        try std.testing.expectEqual(@as(?FileType, .@"tar.gz"), fromContentDisposition("attachment; filename*=\"stuff.tar.gz\""));
        try std.testing.expectEqual(@as(?FileType, .@"tar.xz"), fromContentDisposition("ATTACHMENT; filename=\"stuff.tar.xz\""));
        try std.testing.expectEqual(@as(?FileType, .@"tar.xz"), fromContentDisposition("attachment; FileName=\"stuff.tar.xz\""));
        try std.testing.expectEqual(@as(?FileType, .@"tar.gz"), fromContentDisposition("attachment; FileName*=UTF-8\'\'xyz%2Fstuff.tar.gz"));
        try std.testing.expectEqual(@as(?FileType, .tar), fromContentDisposition("attachment; FileName=\"stuff.tar\""));

        try std.testing.expect(fromContentDisposition("attachment FileName=\"stuff.tar.gz\"") == null);
        try std.testing.expect(fromContentDisposition("attachment; FileName\"stuff.gz\"") == null);
        try std.testing.expect(fromContentDisposition("attachment; size=42") == null);
        try std.testing.expect(fromContentDisposition("inline; size=42") == null);
        try std.testing.expect(fromContentDisposition("FileName=\"stuff.tar.gz\"; attachment;") == null);
        try std.testing.expect(fromContentDisposition("FileName=\"stuff.tar.gz\";") == null);
    }
};

const init_resource_buffer_size = git.Packet.max_data_length;

fn initResource(f: *Fetch, uri: std.Uri, resource: *Resource, reader_buffer: []u8) RunError!void {
    const io = f.job_queue.io;
    const arena = f.arena.allocator();
    const eb = &f.error_bundle;

    if (ascii.eqlIgnoreCase(uri.scheme, "file")) {
        const path = try uri.path.toRawMaybeAlloc(arena);
        const file = f.parent_package_root.openFile(io, path, .{}) catch |err| {
            return f.fail(f.location_tok, try eb.printString("unable to open '{f}{s}': {t}", .{
                f.parent_package_root, path, err,
            }));
        };
        resource.* = .{ .file = file.reader(io, reader_buffer) };
        return;
    }

    const http_client = f.job_queue.http_client;

    if (ascii.eqlIgnoreCase(uri.scheme, "http") or
        ascii.eqlIgnoreCase(uri.scheme, "https"))
    {
        resource.* = .{ .http_request = .{
            .request = http_client.request(.GET, uri, .{}) catch |err|
                return f.fail(f.location_tok, try eb.printString("unable to connect to server: {t}", .{err})),
            .response = undefined,
            .transfer_buffer = reader_buffer,
            .decompress_buffer = &.{},
            .decompress = undefined,
        } };
        const request = &resource.http_request.request;
        errdefer request.deinit();

        request.sendBodiless() catch |err|
            return f.fail(f.location_tok, try eb.printString("HTTP request failed: {t}", .{err}));

        var redirect_buffer: [8000]u8 = undefined;
        const response = &resource.http_request.response;
        response.* = request.receiveHead(&redirect_buffer) catch |err| switch (err) {
            error.ReadFailed => {
                return f.fail(f.location_tok, try eb.printString("HTTP response read failure: {t}", .{
                    request.connection.?.getReadError().?,
                }));
            },
            else => |e| return f.fail(f.location_tok, try eb.printString("invalid HTTP response: {t}", .{e})),
        };

        if (response.head.status != .ok) return f.fail(f.location_tok, try eb.printString(
            "bad HTTP response code: '{d} {s}'",
            .{ response.head.status, response.head.status.phrase() orelse "" },
        ));

        resource.http_request.decompress_buffer = try arena.alloc(u8, response.head.content_encoding.minBufferCapacity());
        return;
    }

    if (ascii.eqlIgnoreCase(uri.scheme, "git+http") or
        ascii.eqlIgnoreCase(uri.scheme, "git+https"))
    {
        var transport_uri = uri;
        transport_uri.scheme = uri.scheme["git+".len..];
        var session = git.Session.init(arena, http_client, transport_uri, reader_buffer) catch |err| {
            return f.fail(
                f.location_tok,
                try eb.printString("unable to discover remote git server capabilities: {t}", .{err}),
            );
        };

        const want_oid = want_oid: {
            const want_ref =
                if (uri.fragment) |fragment| try fragment.toRawMaybeAlloc(arena) else "HEAD";
            if (git.Oid.parseAny(want_ref)) |oid| break :want_oid oid else |_| {}

            const want_ref_head = try std.fmt.allocPrint(arena, "refs/heads/{s}", .{want_ref});
            const want_ref_tag = try std.fmt.allocPrint(arena, "refs/tags/{s}", .{want_ref});

            var ref_iterator: git.Session.RefIterator = undefined;
            session.listRefs(&ref_iterator, .{
                .ref_prefixes = &.{ want_ref, want_ref_head, want_ref_tag },
                .include_peeled = true,
                .buffer = reader_buffer,
            }) catch |err| return f.fail(f.location_tok, try eb.printString("unable to list refs: {t}", .{err}));
            defer ref_iterator.deinit();
            while (ref_iterator.next() catch |err| {
                return f.fail(f.location_tok, try eb.printString(
                    "unable to iterate refs: {s}",
                    .{@errorName(err)},
                ));
            }) |ref| {
                if (std.mem.eql(u8, ref.name, want_ref) or
                    std.mem.eql(u8, ref.name, want_ref_head) or
                    std.mem.eql(u8, ref.name, want_ref_tag))
                {
                    break :want_oid ref.peeled orelse ref.oid;
                }
            }
            return f.fail(f.location_tok, try eb.printString("ref not found: {s}", .{want_ref}));
        };
        if (f.use_latest_commit) {
            f.latest_commit = want_oid;
        } else if (uri.fragment == null) {
            const notes_len = 1;
            try eb.addRootErrorMessage(.{
                .msg = try eb.addString("url field is missing an explicit ref"),
                .src_loc = try f.srcLoc(f.location_tok),
                .notes_len = notes_len,
            });
            const notes_start = try eb.reserveNotes(notes_len);
            eb.extra.items[notes_start] = @intFromEnum(try eb.addErrorMessage(.{
                .msg = try eb.printString("try .url = \"{f}#{f}\",", .{
                    uri.fmt(.{ .scheme = true, .authority = true, .path = true }),
                    want_oid,
                }),
            }));
            return error.FetchFailed;
        }

        var want_oid_buf: [git.Oid.max_formatted_length]u8 = undefined;
        _ = std.fmt.bufPrint(&want_oid_buf, "{f}", .{want_oid}) catch unreachable;
        resource.* = .{ .git = .{
            .session = session,
            .fetch_stream = undefined,
            .want_oid = want_oid,
        } };
        const fetch_stream = &resource.git.fetch_stream;
        session.fetch(fetch_stream, &.{&want_oid_buf}, reader_buffer) catch |err| {
            return f.fail(f.location_tok, try eb.printString("unable to create fetch stream: {t}", .{err}));
        };
        errdefer fetch_stream.deinit(fetch_stream);

        return;
    }

    return f.fail(f.location_tok, try eb.printString("unsupported URL scheme: {s}", .{uri.scheme}));
}

fn unpackResource(
    f: *Fetch,
    resource: *Resource,
    uri_path: []const u8,
    tmp_directory: Cache.Directory,
) RunError!UnpackResult {
    const eb = &f.error_bundle;
    const file_type = switch (resource.*) {
        .file => FileType.fromPath(uri_path) orelse
            return f.fail(f.location_tok, try eb.printString("unknown file type: '{s}'", .{uri_path})),

        .http_request => |*http_request| ft: {
            const head = &http_request.response.head;

            // Content-Type takes first precedence.
            const content_type = head.content_type orelse
                return f.fail(f.location_tok, try eb.addString("missing 'Content-Type' header"));

            // Extract the MIME type, ignoring charset and boundary directives
            const mime_type_end = std.mem.indexOf(u8, content_type, ";") orelse content_type.len;
            const mime_type = content_type[0..mime_type_end];

            if (ascii.eqlIgnoreCase(mime_type, "application/x-tar"))
                break :ft .tar;

            if (ascii.eqlIgnoreCase(mime_type, "application/gzip") or
                ascii.eqlIgnoreCase(mime_type, "application/x-gzip") or
                ascii.eqlIgnoreCase(mime_type, "application/tar+gzip") or
                ascii.eqlIgnoreCase(mime_type, "application/x-tar-gz") or
                ascii.eqlIgnoreCase(mime_type, "application/x-gtar-compressed"))
            {
                break :ft .@"tar.gz";
            }

            if (ascii.eqlIgnoreCase(mime_type, "application/x-xz"))
                break :ft .@"tar.xz";

            if (ascii.eqlIgnoreCase(mime_type, "application/zstd"))
                break :ft .@"tar.zst";

            if (ascii.eqlIgnoreCase(mime_type, "application/zip") or
                ascii.eqlIgnoreCase(mime_type, "application/x-zip-compressed") or
                ascii.eqlIgnoreCase(mime_type, "application/java-archive"))
            {
                break :ft .zip;
            }

            if (!ascii.eqlIgnoreCase(mime_type, "application/octet-stream") and
                !ascii.eqlIgnoreCase(mime_type, "application/x-compressed"))
            {
                return f.fail(f.location_tok, try eb.printString(
                    "unrecognized 'Content-Type' header: '{s}'",
                    .{content_type},
                ));
            }

            // Next, the filename from 'content-disposition: attachment' takes precedence.
            if (head.content_disposition) |cd_header| {
                break :ft FileType.fromContentDisposition(cd_header) orelse {
                    return f.fail(f.location_tok, try eb.printString(
                        "unsupported Content-Disposition header value: '{s}' for Content-Type=application/octet-stream",
                        .{cd_header},
                    ));
                };
            }

            // Finally, the path from the URI is used.
            break :ft FileType.fromPath(uri_path) orelse {
                return f.fail(f.location_tok, try eb.printString("unknown file type: '{s}'", .{uri_path}));
            };
        },

        .git => .git_pack,

        .dir => |dir| {
            f.recursiveDirectoryCopy(dir, tmp_directory.handle) catch |err| {
                return f.fail(f.location_tok, try eb.printString("unable to copy directory '{s}': {t}", .{
                    uri_path, err,
                }));
            };
            return .{};
        },
    };

    switch (file_type) {
        .tar => {
            return unpackTarball(f, tmp_directory.handle, resource.reader());
        },
        .@"tar.gz" => {
            var flate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
            var decompress: std.compress.flate.Decompress = .init(resource.reader(), .gzip, &flate_buffer);
            return try unpackTarball(f, tmp_directory.handle, &decompress.reader);
        },
        .@"tar.xz" => {
            const gpa = f.arena.child_allocator;
            var decompress = std.compress.xz.Decompress.init(resource.reader(), gpa, &.{}) catch |err|
                return f.fail(f.location_tok, try eb.printString("unable to decompress tarball: {t}", .{err}));
            defer decompress.deinit();
            return try unpackTarball(f, tmp_directory.handle, &decompress.reader);
        },
        .@"tar.zst" => {
            const window_len = std.compress.zstd.default_window_len;
            const window_buffer = try f.arena.allocator().alloc(u8, window_len + std.compress.zstd.block_size_max);
            var decompress: std.compress.zstd.Decompress = .init(resource.reader(), window_buffer, .{
                .verify_checksum = false,
                .window_len = window_len,
            });
            return try unpackTarball(f, tmp_directory.handle, &decompress.reader);
        },
        .git_pack => return unpackGitPack(f, tmp_directory.handle, &resource.git) catch |err| switch (err) {
            error.FetchFailed => return error.FetchFailed,
            error.OutOfMemory => return error.OutOfMemory,
            else => |e| return f.fail(f.location_tok, try eb.printString("unable to unpack git files: {t}", .{e})),
        },
        .zip => return unzip(f, tmp_directory.handle, resource.reader()) catch |err| switch (err) {
            error.ReadFailed => return f.fail(f.location_tok, try eb.printString(
                "failed reading resource: {t}",
                .{err},
            )),
            else => |e| return e,
        },
    }
}

fn unpackTarball(f: *Fetch, out_dir: Io.Dir, reader: *Io.Reader) RunError!UnpackResult {
    const eb = &f.error_bundle;
    const arena = f.arena.allocator();
    const io = f.job_queue.io;

    var diagnostics: std.tar.Diagnostics = .{ .allocator = arena };

    std.tar.pipeToFileSystem(io, out_dir, reader, .{
        .diagnostics = &diagnostics,
        .strip_components = 0,
        .mode_mode = .ignore,
        .exclude_empty_directories = true,
    }) catch |err| return f.fail(
        f.location_tok,
        try eb.printString("unable to unpack tarball to temporary directory: {t}", .{err}),
    );

    var res: UnpackResult = .{ .root_dir = diagnostics.root_dir };
    if (diagnostics.errors.items.len > 0) {
        try res.allocErrors(arena, diagnostics.errors.items.len, "unable to unpack tarball");
        for (diagnostics.errors.items) |item| {
            switch (item) {
                .unable_to_create_file => |i| res.unableToCreateFile(stripRoot(i.file_name, res.root_dir), i.code),
                .unable_to_create_sym_link => |i| res.unableToCreateSymLink(stripRoot(i.file_name, res.root_dir), i.link_name, i.code),
                .unsupported_file_type => |i| res.unsupportedFileType(stripRoot(i.file_name, res.root_dir), @intFromEnum(i.file_type)),
                .components_outside_stripped_prefix => unreachable, // unreachable with strip_components = 0
            }
        }
    }
    return res;
}

fn unzip(
    f: *Fetch,
    out_dir: Io.Dir,
    reader: *Io.Reader,
) error{ ReadFailed, OutOfMemory, Canceled, FetchFailed }!UnpackResult {
    // We write the entire contents to a file first because zip files
    // must be processed back to front and they could be too large to
    // load into memory.

    const io = f.job_queue.io;
    const cache_root = f.job_queue.global_cache;
    const prefix = "tmp/";
    const suffix = ".zip";
    const eb = &f.error_bundle;
    const random_len = @sizeOf(u64) * 2;

    var zip_path: [prefix.len + random_len + suffix.len]u8 = undefined;
    zip_path[0..prefix.len].* = prefix.*;
    zip_path[prefix.len + random_len ..].* = suffix.*;

    var zip_file = while (true) {
        const random_integer = r: {
            var x: u64 = undefined;
            io.random(@ptrCast(&x));
            break :r x;
        };
        zip_path[prefix.len..][0..random_len].* = std.fmt.hex(random_integer);

        break cache_root.handle.createFile(io, &zip_path, .{
            .exclusive = true,
            .read = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            error.Canceled => return error.Canceled,
            else => |e| return f.fail(
                f.location_tok,
                try eb.printString("failed to create temporary zip file: {t}", .{e}),
            ),
        };
    };
    defer zip_file.close(io);
    var zip_file_buffer: [4096]u8 = undefined;
    var zip_file_reader = b: {
        var zip_file_writer = zip_file.writer(io, &zip_file_buffer);

        _ = reader.streamRemaining(&zip_file_writer.interface) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.WriteFailed => return f.fail(
                f.location_tok,
                try eb.printString("failed writing temporary zip file: {t}", .{err}),
            ),
        };
        zip_file_writer.interface.flush() catch |err| return f.fail(
            f.location_tok,
            try eb.printString("failed writing temporary zip file: {t}", .{err}),
        );
        break :b zip_file_writer.moveToReader();
    };

    var diagnostics: std.zip.Diagnostics = .{ .allocator = f.arena.allocator() };
    // no need to deinit since we are using an arena allocator

    zip_file_reader.seekTo(0) catch |err|
        return f.fail(f.location_tok, try eb.printString("failed to seek temporary zip file: {t}", .{err}));
    std.zip.extract(out_dir, &zip_file_reader, .{
        .allow_backslashes = true,
        .diagnostics = &diagnostics,
    }) catch |err| return f.fail(f.location_tok, try eb.printString("zip extract failed: {t}", .{err}));

    cache_root.handle.deleteFile(io, &zip_path) catch |err|
        return f.fail(f.location_tok, try eb.printString("delete temporary zip failed: {t}", .{err}));

    return .{ .root_dir = diagnostics.root_dir };
}

fn unpackGitPack(f: *Fetch, out_dir: Io.Dir, resource: *Resource.Git) anyerror!UnpackResult {
    const io = f.job_queue.io;
    const arena = f.arena.allocator();
    // TODO don't try to get a gpa from an arena. expose this dependency higher up
    // because the backing of arena could be page allocator
    const gpa = f.arena.child_allocator;
    const object_format: git.Oid.Format = resource.want_oid;

    var res: UnpackResult = .{};
    // The .git directory is used to store the packfile and associated index, but
    // we do not attempt to replicate the exact structure of a real .git
    // directory, since that isn't relevant for fetching a package.
    {
        var pack_dir = try out_dir.createDirPathOpen(io, ".git", .{});
        defer pack_dir.close(io);
        var pack_file = try pack_dir.createFile(io, "pkg.pack", .{ .read = true });
        defer pack_file.close(io);
        var pack_file_buffer: [4096]u8 = undefined;
        var pack_file_reader = b: {
            var pack_file_writer = pack_file.writer(io, &pack_file_buffer);
            const fetch_reader = &resource.fetch_stream.reader;
            _ = try fetch_reader.streamRemaining(&pack_file_writer.interface);
            try pack_file_writer.interface.flush();
            break :b pack_file_writer.moveToReader();
        };

        var index_file = try pack_dir.createFile(io, "pkg.idx", .{ .read = true });
        defer index_file.close(io);
        var index_file_buffer: [2000]u8 = undefined;
        var index_file_writer = index_file.writer(io, &index_file_buffer);
        {
            const index_prog_node = f.prog_node.start("Index pack", 0);
            defer index_prog_node.end();
            try git.indexPack(gpa, object_format, &pack_file_reader, &index_file_writer);
        }

        {
            var index_file_reader = index_file.reader(io, &index_file_buffer);
            const checkout_prog_node = f.prog_node.start("Checkout", 0);
            defer checkout_prog_node.end();
            var repository: git.Repository = undefined;
            try repository.init(gpa, object_format, &pack_file_reader, &index_file_reader);
            defer repository.deinit();
            var diagnostics: git.Diagnostics = .{ .allocator = arena };
            try repository.checkout(io, out_dir, resource.want_oid, &diagnostics);

            if (diagnostics.errors.items.len > 0) {
                try res.allocErrors(arena, diagnostics.errors.items.len, "unable to unpack packfile");
                for (diagnostics.errors.items) |item| {
                    switch (item) {
                        .unable_to_create_file => |i| res.unableToCreateFile(i.file_name, i.code),
                        .unable_to_create_sym_link => |i| res.unableToCreateSymLink(i.file_name, i.link_name, i.code),
                    }
                }
            }
        }
    }

    try out_dir.deleteTree(io, ".git");
    return res;
}

fn recursiveDirectoryCopy(f: *Fetch, dir: Io.Dir, tmp_dir: Io.Dir) anyerror!void {
    const gpa = f.arena.child_allocator;
    const io = f.job_queue.io;
    // Recursive directory copy.
    var it = try dir.walk(gpa);
    defer it.deinit();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {}, // omit empty directories
            .file => {
                dir.copyFile(entry.path, tmp_dir, entry.path, io, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        if (fs.path.dirname(entry.path)) |dirname| try tmp_dir.createDirPath(io, dirname);
                        try dir.copyFile(entry.path, tmp_dir, entry.path, io, .{});
                    },
                    else => |e| return e,
                };
            },
            .sym_link => {
                var buf: [fs.max_path_bytes]u8 = undefined;
                const link_name = buf[0..try dir.readLink(io, entry.path, &buf)];
                // TODO: if this would create a symlink to outside
                // the destination directory, fail with an error instead.
                tmp_dir.symLink(io, link_name, entry.path, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        if (fs.path.dirname(entry.path)) |dirname| try tmp_dir.createDirPath(io, dirname);
                        try tmp_dir.symLink(io, link_name, entry.path, .{});
                    },
                    else => |e| return e,
                };
            },
            else => return error.IllegalFileTypeInPackage,
        }
    }
}

pub fn renameTmpIntoCache(io: Io, tmp_path: Cache.Path, dest_path: Cache.Path) !void {
    var handled_missing_dir = false;
    while (true) {
        Io.Dir.rename(
            tmp_path.root_dir.handle,
            tmp_path.sub_path,
            dest_path.root_dir.handle,
            dest_path.sub_path,
            io,
        ) catch |err| switch (err) {
            error.FileNotFound => {
                if (handled_missing_dir) return err;
                const parent_sub_path = Io.Dir.path.dirname(dest_path.sub_path).?;
                dest_path.root_dir.handle.createDir(io, parent_sub_path, .default_dir) catch |er| switch (er) {
                    error.PathAlreadyExists => handled_missing_dir = true,
                    else => |e| return e,
                };
                continue;
            },
            error.DirNotEmpty, error.AccessDenied => {
                // Package has been already downloaded and may already be in use on the system.
                tmp_path.root_dir.handle.deleteTree(io, tmp_path.sub_path) catch |er| switch (er) {
                    error.Canceled => |e| return e,
                    // Garbage files leftover in zig-cache/tmp/ is, as they say
                    // on Star Trek, "operating within normal parameters".
                    else => |e| log.warn("failed to delete temporary directory {f}: {t}", .{ tmp_path, e }),
                };
            },
            else => |e| return e,
        };
        break;
    }
}

const ComputedHash = struct {
    digest: Package.Hash.Digest,
    total_size: u64,
};

/// Assumes that files not included in the package have already been filtered
/// prior to calling this function. This ensures that files not protected by
/// the hash are not present on the file system. Empty directories are *not
/// hashed* and must not be present on the file system when calling this
/// function.
fn computeHash(f: *Fetch, pkg_path: Cache.Path, filter: Filter) RunError!ComputedHash {
    const io = f.job_queue.io;
    // All the path name strings need to be in memory for sorting.
    const arena = f.arena.allocator();
    const gpa = f.arena.child_allocator;
    const eb = &f.error_bundle;
    const root_dir = pkg_path.root_dir.handle;

    // Collect all files, recursively, then sort.
    var all_files = std.array_list.Managed(*HashedFile).init(gpa);
    defer all_files.deinit();

    var deleted_files = std.array_list.Managed(*DeletedFile).init(gpa);
    defer deleted_files.deinit();

    // Track directories which had any files deleted from them so that empty directories
    // can be deleted.
    var sus_dirs: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer sus_dirs.deinit(gpa);

    var walker = try root_dir.walk(gpa);
    defer walker.deinit();

    // Total number of bytes of file contents included in the package.
    var total_size: u64 = 0;

    {
        // The final hash will be a hash of each file hashed independently. This
        // allows hashing in parallel.
        var group: Io.Group = .init;
        defer group.cancel(io);

        while (walker.next(io) catch |err| {
            try eb.addRootErrorMessage(.{ .msg = try eb.printString(
                "unable to walk temporary directory '{f}': {t}",
                .{ pkg_path, err },
            ) });
            return error.FetchFailed;
        }) |entry| {
            if (entry.kind == .directory) continue;

            const entry_pkg_path = stripRoot(entry.path, pkg_path.sub_path);
            if (!filter.includePath(entry_pkg_path)) {
                // Delete instead of including in hash calculation.
                const fs_path = try arena.dupe(u8, entry.path);

                // Also track the parent directory in case it becomes empty.
                if (fs.path.dirname(fs_path)) |parent|
                    try sus_dirs.put(gpa, parent, {});

                const deleted_file = try arena.create(DeletedFile);
                deleted_file.* = .{
                    .fs_path = fs_path,
                    .failure = undefined, // to be populated by the worker
                };
                group.async(io, workerDeleteFile, .{ io, root_dir, deleted_file });
                try deleted_files.append(deleted_file);
                continue;
            }

            const kind: HashedFile.Kind = switch (entry.kind) {
                .directory => unreachable,
                .file => .file,
                .sym_link => .link,
                else => return f.fail(f.location_tok, try eb.printString(
                    "package contains '{s}' which has illegal file type '{t}'",
                    .{ entry.path, entry.kind },
                )),
            };

            if (std.mem.eql(u8, entry_pkg_path, Package.build_zig_basename))
                f.has_build_zig = true;

            const fs_path = try arena.dupe(u8, entry.path);
            const hashed_file = try arena.create(HashedFile);
            hashed_file.* = .{
                .fs_path = fs_path,
                .normalized_path = try normalizePathAlloc(arena, entry_pkg_path),
                .kind = kind,
                .hash = undefined, // to be populated by the worker
                .failure = undefined, // to be populated by the worker
                .size = undefined, // to be populated by the worker
            };
            group.async(io, workerHashFile, .{ io, root_dir, hashed_file });
            try all_files.append(hashed_file);
        }

        try group.await(io);
    }

    {
        // Sort by length, descending, so that child directories get removed first.
        sus_dirs.sortUnstable(@as(struct {
            keys: []const []const u8,
            pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
                return ctx.keys[b_index].len < ctx.keys[a_index].len;
            }
        }, .{ .keys = sus_dirs.keys() }));

        // During this loop, more entries will be added, so we must loop by index.
        var i: usize = 0;
        while (i < sus_dirs.count()) : (i += 1) {
            const sus_dir = sus_dirs.keys()[i];
            root_dir.deleteDir(io, sus_dir) catch |err| switch (err) {
                error.DirNotEmpty => continue,
                error.FileNotFound => continue,
                else => |e| {
                    try eb.addRootErrorMessage(.{ .msg = try eb.printString(
                        "unable to delete empty directory '{s}': {s}",
                        .{ sus_dir, @errorName(e) },
                    ) });
                    return error.FetchFailed;
                },
            };
            if (fs.path.dirname(sus_dir)) |parent| {
                try sus_dirs.put(gpa, parent, {});
            }
        }
    }

    std.mem.sortUnstable(*HashedFile, all_files.items, {}, HashedFile.lessThan);

    var hasher = Package.Hash.Algo.init(.{});
    var any_failures = false;
    for (all_files.items) |hashed_file| {
        hashed_file.failure catch |err| {
            any_failures = true;
            try eb.addRootErrorMessage(.{
                .msg = try eb.printString("unable to hash '{s}': {s}", .{
                    hashed_file.fs_path, @errorName(err),
                }),
            });
        };
        hasher.update(&hashed_file.hash);
        total_size += hashed_file.size;
    }
    for (deleted_files.items) |deleted_file| {
        deleted_file.failure catch |err| {
            any_failures = true;
            try eb.addRootErrorMessage(.{
                .msg = try eb.printString("failed to delete excluded path '{s}' from package: {s}", .{
                    deleted_file.fs_path, @errorName(err),
                }),
            });
        };
    }

    if (any_failures) return error.FetchFailed;

    if (f.job_queue.debug_hash) {
        assert(!f.job_queue.recursive);
        // Print something to stdout that can be text diffed to figure out why
        // the package hash is different.
        dumpHashInfo(io, all_files.items) catch |err|
            std.process.fatal("unable to write to stdout: {t}", .{err});
    }

    return .{
        .digest = hasher.finalResult(),
        .total_size = total_size,
    };
}

fn dumpHashInfo(io: Io, all_files: []const *const HashedFile) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    dumpHashInfoWriter(&stdout_writer.interface, all_files) catch |err| switch (err) {
        error.WriteFailed => return stdout_writer.err.?,
    };
    try stdout_writer.flush();
}

fn dumpHashInfoWriter(w: *Io.Writer, all_files: []const *const HashedFile) Io.Writer.Error!void {
    for (all_files) |hashed_file| {
        try w.print("{t}: {x}: {s}\n", .{ hashed_file.kind, &hashed_file.hash, hashed_file.normalized_path });
    }
}

fn workerHashFile(io: Io, dir: Io.Dir, hashed_file: *HashedFile) void {
    hashed_file.failure = hashFileFallible(io, dir, hashed_file);
}

fn workerDeleteFile(io: Io, dir: Io.Dir, deleted_file: *DeletedFile) void {
    deleted_file.failure = deleteFileFallible(io, dir, deleted_file);
}

fn hashFileFallible(io: Io, dir: Io.Dir, hashed_file: *HashedFile) HashedFile.Error!void {
    var buf: [8000]u8 = undefined;
    var hasher = Package.Hash.Algo.init(.{});
    hasher.update(hashed_file.normalized_path);
    var file_size: u64 = 0;

    switch (hashed_file.kind) {
        .file => {
            var file = try dir.openFile(io, hashed_file.fs_path, .{});
            defer file.close(io);
            // Hard-coded false executable bit: https://github.com/ziglang/zig/issues/17463
            hasher.update(&.{ 0, 0 });
            var file_header: FileHeader = .{};
            while (true) {
                const bytes_read = try file.readPositional(io, &.{&buf}, file_size);
                if (bytes_read == 0) break;
                file_size += bytes_read;
                hasher.update(buf[0..bytes_read]);
                file_header.update(buf[0..bytes_read]);
            }
            if (file_header.isExecutable()) {
                try setExecutable(io, file);
            }
        },
        .link => {
            const link_name = buf[0..try dir.readLink(io, hashed_file.fs_path, &buf)];
            if (fs.path.sep != canonical_sep) {
                // Package hashes are intended to be consistent across
                // platforms which means we must normalize path separators
                // inside symlinks.
                normalizePath(link_name);
            }
            hasher.update(link_name);
        },
    }
    hasher.final(&hashed_file.hash);
    hashed_file.size = file_size;
}

fn deleteFileFallible(io: Io, dir: Io.Dir, deleted_file: *DeletedFile) DeletedFile.Error!void {
    try dir.deleteFile(io, deleted_file.fs_path);
}

fn setExecutable(io: Io, file: Io.File) !void {
    if (!Io.File.Permissions.has_executable_bit) return;
    try file.setPermissions(io, .executable_file);
}

const DeletedFile = struct {
    fs_path: []const u8,
    failure: Error!void,

    const Error =
        Io.Dir.DeleteFileError ||
        Io.Dir.DeleteDirError;
};

const HashedFile = struct {
    fs_path: []const u8,
    normalized_path: []const u8,
    hash: Package.Hash.Digest,
    failure: Error!void,
    kind: Kind,
    size: u64,

    const Error =
        Io.File.OpenError ||
        Io.File.ReadPositionalError ||
        Io.File.StatError ||
        Io.File.SetPermissionsError ||
        Io.Dir.ReadLinkError;

    const Kind = enum { file, link };

    fn lessThan(context: void, lhs: *const HashedFile, rhs: *const HashedFile) bool {
        _ = context;
        return std.mem.lessThan(u8, lhs.normalized_path, rhs.normalized_path);
    }
};

/// Strips root directory name from file system path.
fn stripRoot(fs_path: []const u8, root_dir: []const u8) []const u8 {
    if (root_dir.len == 0 or fs_path.len <= root_dir.len) return fs_path;

    if (std.mem.eql(u8, fs_path[0..root_dir.len], root_dir) and fs.path.isSep(fs_path[root_dir.len])) {
        return fs_path[root_dir.len + 1 ..];
    }

    return fs_path;
}

/// Make a file system path identical independently of operating system path inconsistencies.
/// This converts backslashes into forward slashes.
fn normalizePathAlloc(arena: Allocator, pkg_path: []const u8) ![]const u8 {
    const normalized = try arena.dupe(u8, pkg_path);
    if (fs.path.sep == canonical_sep) return normalized;
    normalizePath(normalized);
    return normalized;
}

const canonical_sep = fs.path.sep_posix;

fn normalizePath(bytes: []u8) void {
    assert(fs.path.sep != canonical_sep);
    std.mem.replaceScalar(u8, bytes, fs.path.sep, canonical_sep);
}

const Filter = struct {
    include_paths: std.StringArrayHashMapUnmanaged(void) = .empty,

    /// sub_path is relative to the package root.
    pub fn includePath(self: *const Filter, sub_path: []const u8) bool {
        if (self.include_paths.count() == 0) return true;
        if (self.include_paths.contains("")) return true;
        if (self.include_paths.contains(".")) return true;
        if (self.include_paths.contains(sub_path)) return true;

        // Check if any included paths are parent directories of sub_path.
        var dirname = sub_path;
        while (std.fs.path.dirname(dirname)) |next_dirname| {
            if (self.include_paths.contains(next_dirname)) return true;
            dirname = next_dirname;
        }

        return false;
    }

    test includePath {
        const gpa = std.testing.allocator;
        var filter: Filter = .{};
        defer filter.include_paths.deinit(gpa);

        try filter.include_paths.put(gpa, "src", {});
        try std.testing.expect(filter.includePath("src/core/unix/SDL_poll.c"));
        try std.testing.expect(!filter.includePath(".gitignore"));
    }
};

pub fn depDigest(pkg_root: Cache.Path, cache_root: Cache.Directory, dep: Manifest.Dependency) ?Package.Hash {
    if (dep.hash) |h| return .fromSlice(h);

    switch (dep.location) {
        .url => return null,
        .path => |rel_path| {
            var buf: [fs.max_path_bytes]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buf);
            const new_root = pkg_root.resolvePosix(fba.allocator(), rel_path) catch
                return null;
            return relativePathDigest(new_root, cache_root);
        },
    }
}

// Detects executable header: ELF or Macho-O magic header or shebang line.
const FileHeader = struct {
    header: [4]u8 = undefined,
    bytes_read: usize = 0,

    pub fn update(self: *FileHeader, buf: []const u8) void {
        if (self.bytes_read >= self.header.len) return;
        const n = @min(self.header.len - self.bytes_read, buf.len);
        @memcpy(self.header[self.bytes_read..][0..n], buf[0..n]);
        self.bytes_read += n;
    }

    fn isScript(self: *FileHeader) bool {
        const shebang = "#!";
        return std.mem.eql(u8, self.header[0..@min(self.bytes_read, shebang.len)], shebang);
    }

    fn isElf(self: *FileHeader) bool {
        const elf_magic = std.elf.MAGIC;
        return std.mem.eql(u8, self.header[0..@min(self.bytes_read, elf_magic.len)], elf_magic);
    }

    fn isMachO(self: *FileHeader) bool {
        if (self.bytes_read < 4) return false;
        const magic_number = std.mem.readInt(u32, &self.header, builtin.cpu.arch.endian());
        return magic_number == std.macho.MH_MAGIC or
            magic_number == std.macho.MH_MAGIC_64 or
            magic_number == std.macho.FAT_MAGIC or
            magic_number == std.macho.FAT_MAGIC_64 or
            magic_number == std.macho.MH_CIGAM or
            magic_number == std.macho.MH_CIGAM_64 or
            magic_number == std.macho.FAT_CIGAM or
            magic_number == std.macho.FAT_CIGAM_64;
    }

    pub fn isExecutable(self: *FileHeader) bool {
        return self.isScript() or self.isElf() or self.isMachO();
    }
};

test FileHeader {
    var h: FileHeader = .{};
    try std.testing.expect(!h.isExecutable());

    const elf_magic = std.elf.MAGIC;
    h.update(elf_magic[0..2]);
    try std.testing.expect(!h.isExecutable());
    h.update(elf_magic[2..4]);
    try std.testing.expect(h.isExecutable());

    h.update(elf_magic[2..4]);
    try std.testing.expect(h.isExecutable());

    const macho64_magic_bytes = [_]u8{ 0xCF, 0xFA, 0xED, 0xFE };
    h.bytes_read = 0;
    h.update(&macho64_magic_bytes);
    try std.testing.expect(h.isExecutable());

    const macho64_cigam_bytes = [_]u8{ 0xFE, 0xED, 0xFA, 0xCF };
    h.bytes_read = 0;
    h.update(&macho64_cigam_bytes);
    try std.testing.expect(h.isExecutable());
}

// Result of the `unpackResource` operation. Enables collecting errors from
// tar/git diagnostic, filtering that errors by manifest inclusion rules and
// emitting remaining errors to an `ErrorBundle`.
const UnpackResult = struct {
    errors: []Error = undefined,
    errors_count: usize = 0,
    root_error_message: []const u8 = "",

    // A non empty value means that the package contents are inside a
    // sub-directory indicated by the named path.
    root_dir: []const u8 = "",

    const Error = union(enum) {
        unable_to_create_sym_link: struct {
            code: anyerror,
            file_name: []const u8,
            link_name: []const u8,
        },
        unable_to_create_file: struct {
            code: anyerror,
            file_name: []const u8,
        },
        unsupported_file_type: struct {
            file_name: []const u8,
            file_type: u8,
        },

        fn excluded(self: Error, filter: Filter) bool {
            const file_name = switch (self) {
                .unable_to_create_file => |info| info.file_name,
                .unable_to_create_sym_link => |info| info.file_name,
                .unsupported_file_type => |info| info.file_name,
            };
            return !filter.includePath(file_name);
        }
    };

    fn allocErrors(self: *UnpackResult, arena: std.mem.Allocator, n: usize, root_error_message: []const u8) !void {
        self.root_error_message = try arena.dupe(u8, root_error_message);
        self.errors = try arena.alloc(UnpackResult.Error, n);
    }

    fn hasErrors(self: *UnpackResult) bool {
        return self.errors_count > 0;
    }

    fn unableToCreateFile(self: *UnpackResult, file_name: []const u8, err: anyerror) void {
        self.errors[self.errors_count] = .{ .unable_to_create_file = .{
            .code = err,
            .file_name = file_name,
        } };
        self.errors_count += 1;
    }

    fn unableToCreateSymLink(self: *UnpackResult, file_name: []const u8, link_name: []const u8, err: anyerror) void {
        self.errors[self.errors_count] = .{ .unable_to_create_sym_link = .{
            .code = err,
            .file_name = file_name,
            .link_name = link_name,
        } };
        self.errors_count += 1;
    }

    fn unsupportedFileType(self: *UnpackResult, file_name: []const u8, file_type: u8) void {
        self.errors[self.errors_count] = .{ .unsupported_file_type = .{
            .file_name = file_name,
            .file_type = file_type,
        } };
        self.errors_count += 1;
    }

    fn validate(self: *UnpackResult, f: *Fetch, filter: Filter) !void {
        if (self.errors_count == 0) return;

        var unfiltered_errors: u32 = 0;
        for (self.errors) |item| {
            if (item.excluded(filter)) continue;
            unfiltered_errors += 1;
        }
        if (unfiltered_errors == 0) return;

        // Emmit errors to an `ErrorBundle`.
        const eb = &f.error_bundle;
        try eb.addRootErrorMessage(.{
            .msg = try eb.addString(self.root_error_message),
            .src_loc = try f.srcLoc(f.location_tok),
            .notes_len = unfiltered_errors,
        });
        var note_i: u32 = try eb.reserveNotes(unfiltered_errors);
        for (self.errors) |item| {
            if (item.excluded(filter)) continue;
            switch (item) {
                .unable_to_create_sym_link => |info| {
                    eb.extra.items[note_i] = @intFromEnum(try eb.addErrorMessage(.{
                        .msg = try eb.printString("unable to create symlink from '{s}' to '{s}': {s}", .{
                            info.file_name, info.link_name, @errorName(info.code),
                        }),
                    }));
                },
                .unable_to_create_file => |info| {
                    eb.extra.items[note_i] = @intFromEnum(try eb.addErrorMessage(.{
                        .msg = try eb.printString("unable to create file '{s}': {s}", .{
                            info.file_name, @errorName(info.code),
                        }),
                    }));
                },
                .unsupported_file_type => |info| {
                    eb.extra.items[note_i] = @intFromEnum(try eb.addErrorMessage(.{
                        .msg = try eb.printString("file '{s}' has unsupported type '{c}'", .{
                            info.file_name, info.file_type,
                        }),
                    }));
                },
            }
            note_i += 1;
        }

        return error.FetchFailed;
    }

    test validate {
        const gpa = std.testing.allocator;
        var arena_instance = std.heap.ArenaAllocator.init(gpa);
        defer arena_instance.deinit();
        const arena = arena_instance.allocator();

        // fill UnpackResult with errors
        var res: UnpackResult = .{};
        try res.allocErrors(arena, 4, "unable to unpack");
        try std.testing.expectEqual(0, res.errors_count);
        res.unableToCreateFile("dir1/file1", error.File1);
        res.unableToCreateSymLink("dir2/file2", "filename", error.SymlinkError);
        res.unableToCreateFile("dir1/file3", error.File3);
        res.unsupportedFileType("dir2/file4", 'x');
        try std.testing.expectEqual(4, res.errors_count);

        // create filter, includes dir2, excludes dir1
        var filter: Filter = .{};
        try filter.include_paths.put(arena, "dir2", {});

        // init Fetch
        var fetch: Fetch = undefined;
        fetch.parent_manifest_ast = null;
        fetch.location_tok = 0;
        try fetch.error_bundle.init(gpa);
        defer fetch.error_bundle.deinit();

        // validate errors with filter
        try std.testing.expectError(error.FetchFailed, res.validate(&fetch, filter));

        // output errors to string
        var errors = try fetch.error_bundle.toOwnedBundle("");
        defer errors.deinit(gpa);
        var aw: Io.Writer.Allocating = .init(gpa);
        defer aw.deinit();
        try errors.renderToWriter(.{}, &aw.writer);
        try std.testing.expectEqualStrings(
            \\error: unable to unpack
            \\    note: unable to create symlink from 'dir2/file2' to 'filename': SymlinkError
            \\    note: file 'dir2/file4' has unsupported type 'x'
            \\
        , aw.written());
    }
};

test {
    _ = Filter;
    _ = FileType;
    _ = UnpackResult;
}
