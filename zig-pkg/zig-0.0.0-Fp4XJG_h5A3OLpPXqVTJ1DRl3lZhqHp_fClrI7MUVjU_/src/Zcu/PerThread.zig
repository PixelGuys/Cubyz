//! This type provides a wrapper around a `*Zcu` for uses which require a thread `Id`.
//! Any operation which mutates `InternPool` state lives here rather than on `Zcu`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Ast = std.zig.Ast;
const AstGen = std.zig.AstGen;
const BigIntConst = std.math.big.int.Const;
const BigIntMutable = std.math.big.int.Mutable;
const Cache = std.Build.Cache;
const log = std.log.scoped(.zcu);
const mem = std.mem;
const Zir = std.zig.Zir;
const Zoir = std.zig.Zoir;
const ZonGen = std.zig.ZonGen;
const Io = std.Io;

const Air = @import("../Air.zig");
const Builtin = @import("../Builtin.zig");
const build_options = @import("build_options");
const builtin = @import("builtin");
const dev = @import("../dev.zig");
const InternPool = @import("../InternPool.zig");
const AnalUnit = InternPool.AnalUnit;
const introspect = @import("../introspect.zig");
const Module = @import("../Package.zig").Module;
const Sema = @import("../Sema.zig");
const target_util = @import("../target.zig");
const tracy = @import("../tracy.zig");
const trace = tracy.trace;
const traceNamed = tracy.traceNamed;
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const Zcu = @import("../Zcu.zig");
const Compilation = @import("../Compilation.zig");
const codegen = @import("../codegen.zig");
const crash_report = @import("../crash_report.zig");

zcu: *Zcu,

/// Dense, per-thread unique index.
tid: Id,

pub const IdBacking = u7;
pub const Id = if (InternPool.single_threaded) enum {
    main,

    pub fn allocate(arena: Allocator, n: usize) Allocator.Error!void {
        _ = arena;
        _ = n;
    }
    pub fn acquire(io: std.Io) Id {
        _ = io;
        return .main;
    }
    pub fn release(tid: Id, io: std.Io) void {
        _ = io;
        _ = tid;
    }
} else enum(IdBacking) {
    main,
    _,

    var tid_mutex: std.Io.Mutex = .init;
    var tid_cond: std.Io.Condition = .init;
    /// This is a temporary workaround put in place to migrate from `std.Thread.Pool`
    /// to `std.Io.Threaded` for asynchronous/concurrent work. The eventual solution
    /// will likely involve significant changes to the `InternPool` implementation.
    var available_tids: std.ArrayList(Id) = .empty;
    threadlocal var recursive_depth: usize = 0;
    threadlocal var recursive_tid: Id = undefined;

    pub fn allocate(arena: Allocator, n: usize) Allocator.Error!void {
        assert(available_tids.items.len == 0);
        try available_tids.ensureTotalCapacityPrecise(arena, n - 1);
        for (1..n) |tid| available_tids.appendAssumeCapacity(@enumFromInt(tid));
        switch (build_options.io_mode) {
            .threaded => {
                // Called from the main thread, so mark ourselves as such.
                recursive_depth = 1;
                recursive_tid = .main;
            },
            .evented => {},
        }
    }
    pub fn acquire(io: std.Io) Id {
        switch (build_options.io_mode) {
            .threaded => {
                recursive_depth += 1;
                if (recursive_depth > 1) {
                    return recursive_tid;
                }
            },
            .evented => {},
        }
        tid_mutex.lockUncancelable(io);
        defer tid_mutex.unlock(io);
        while (true) {
            if (available_tids.pop()) |tid| {
                switch (build_options.io_mode) {
                    .threaded => recursive_tid = tid,
                    .evented => {},
                }
                return tid;
            }
            tid_cond.waitUncancelable(io, &tid_mutex);
        }
    }
    pub fn release(tid: Id, io: std.Io) void {
        switch (build_options.io_mode) {
            .threaded => {
                assert(recursive_tid == tid);
                recursive_depth -= 1;
                if (recursive_depth > 0) return;
            },
            .evented => {},
        }
        {
            tid_mutex.lockUncancelable(io);
            defer tid_mutex.unlock(io);
            available_tids.appendAssumeCapacity(tid);
        }
        tid_cond.signal(io);
    }
};

pub fn activate(zcu: *Zcu, tid: Id) Zcu.PerThread {
    zcu.intern_pool.activate();
    return .{ .zcu = zcu, .tid = tid };
}
pub fn deactivate(pt: Zcu.PerThread) void {
    pt.zcu.intern_pool.deactivate();
}

/// Called from `Compilation.performAllTheWork`. Performs one incremental update of the ZCU: detects
/// changes to files, runs AstGen, and then enters the main semantic analysis loop, where we build
/// up a graph of declarations, functions, etc, while also sending declarations and functions to
/// codegen as they are analyzed.
pub fn update(
    pt: Zcu.PerThread,
    main_progress_node: std.Progress.Node,
    decl_work_timer: *?Compilation.Timer,
) (Allocator.Error || Io.Cancelable)!void {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;

    {
        const tracy_trace = traceNamed(@src(), "astgen");
        defer tracy_trace.end();

        const zir_prog_node = main_progress_node.start("AST Lowering", 0);
        defer zir_prog_node.end();

        var timer = comp.startTimer();
        defer if (timer.finish(io)) |ns| {
            comp.mutex.lockUncancelable(io);
            defer comp.mutex.unlock(io);
            comp.time_report.?.stats.real_ns_files = ns;
        };

        var astgen_group: Io.Group = .init;
        defer astgen_group.cancel(io);

        // We cannot reference `zcu.import_table` after we spawn any `workerUpdateFile` jobs,
        // because on single-threaded targets the worker will be run eagerly, meaning the
        // `import_table` could be mutated, and not even holding `comp.mutex` will save us. So,
        // build up a list of the files to update *before* we spawn any jobs.
        var astgen_work_items: std.MultiArrayList(struct {
            file_index: Zcu.File.Index,
            file: *Zcu.File,
        }) = .empty;
        defer astgen_work_items.deinit(gpa);
        // Not every item in `import_table` will need updating, because some are builtin.zig
        // files. However, most will, so let's just reserve sufficient capacity upfront.
        try astgen_work_items.ensureTotalCapacity(gpa, zcu.import_table.count());
        for (zcu.import_table.keys()) |file_index| {
            const file = zcu.fileByIndex(file_index);
            if (file.is_builtin) {
                // This is a `builtin.zig`, so updating is redundant. However, we want to make
                // sure the file contents are still correct on disk, since it can improve the
                // debugging experience better. That job only needs `file`, so we can kick it
                // off right now.
                astgen_group.async(io, workerUpdateBuiltinFile, .{ comp, file });
                continue;
            }
            astgen_work_items.appendAssumeCapacity(.{
                .file_index = file_index,
                .file = file,
            });
        }

        // Now that we're not going to touch `zcu.import_table` again, we can spawn `workerUpdateFile` jobs.
        for (astgen_work_items.items(.file_index), astgen_work_items.items(.file)) |file_index, file| {
            astgen_group.async(io, workerUpdateFile, .{
                comp, file, file_index, zir_prog_node, &astgen_group,
            });
        }

        // On the other hand, it's fine to directly iterate `zcu.embed_table.keys()` here
        // because `workerUpdateEmbedFile` can't invalidate it. The different here is that one
        // `@embedFile` can't trigger analysis of a new `@embedFile`!
        for (0.., zcu.embed_table.keys()) |ef_index_usize, ef| {
            const ef_index: Zcu.EmbedFile.Index = @enumFromInt(ef_index_usize);
            astgen_group.async(io, workerUpdateEmbedFile, .{
                comp, ef_index, ef,
            });
        }

        try astgen_group.await(io);
    }

    // On an incremental update, a source file might become "dead", in that all imports of
    // the file were removed. This could even change what module the file belongs to! As such,
    // we do a traversal over the files, to figure out which ones are alive and the modules
    // they belong to.
    const any_fatal_files = try pt.computeAliveFiles();

    // If the cache mode is `whole`, add every alive source file to the manifest.
    switch (comp.cache_use) {
        .whole => |whole| if (whole.cache_manifest) |man| {
            for (zcu.alive_files.keys()) |file_index| {
                const file = zcu.fileByIndex(file_index);

                switch (file.status) {
                    .never_loaded => unreachable, // AstGen tried to load it
                    .retryable_failure => continue, // the file cannot be read; this is a guaranteed error
                    .astgen_failure, .success => {}, // the file was read successfully
                }

                const path = try file.path.toAbsolute(comp.dirs, gpa);
                defer gpa.free(path);

                const result = res: {
                    try whole.cache_manifest_mutex.lock(io);
                    defer whole.cache_manifest_mutex.unlock(io);
                    if (file.source) |source| {
                        break :res man.addFilePostContents(path, source, file.stat);
                    } else {
                        break :res man.addFilePost(path);
                    }
                };
                result catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    else => {
                        try pt.reportRetryableFileError(file_index, "unable to update cache: {s}", .{@errorName(err)});
                        continue;
                    },
                };
            }
        },
        .none, .incremental => {},
    }

    if (comp.time_report) |*tr| {
        tr.stats.n_reachable_files = @intCast(zcu.alive_files.count());
    }

    if (any_fatal_files or
        zcu.multi_module_err != null or
        zcu.failed_imports.items.len > 0 or
        comp.alloc_failure_occurred)
    {
        // We give up right now! No updating of ZIR refs, no nothing. The idea is that this prevents
        // us from invalidating lots of incremental dependencies due to files with e.g. parse errors.
        // However, this means our analysis data is invalid, so we want to omit all analysis errors.
        zcu.skip_analysis_this_update = true;
        return;
    }

    if (comp.config.incremental) {
        const update_zir_refs_node = main_progress_node.start("Update ZIR References", 0);
        defer update_zir_refs_node.end();
        try pt.updateZirRefs();
    }

    try zcu.flushRetryableFailures();

    if (!zcu.backendSupportsFeature(.separate_thread)) {
        // Close the ZCU task queue. Prelink may still be running, but the closed
        // queue will cause the linker task to exit once prelink finishes. The
        // closed queue also communicates to `enqueueZcu` that it should wait for
        // the linker task to finish and then run ZCU tasks serially.
        comp.link_queue.finishZcuQueue(comp);
    }

    zcu.sema_prog_node = main_progress_node.start("Semantic Analysis", 0);
    if (comp.bin_file != null) {
        zcu.codegen_prog_node = main_progress_node.start("Code Generation", 0);
    }
    // We increment `pending_codegen_jobs` so that it doesn't reach 0 until after analysis finishes.
    // That prevents the "Code Generation" node from constantly disappearing and reappearing when
    // we're probably going to analyze more functions at some point.
    assert(zcu.pending_codegen_jobs.swap(1, .monotonic) == 0); // don't let this become 0 until analysis finishes

    defer {
        zcu.sema_prog_node.end();
        zcu.sema_prog_node = .none;
        if (zcu.pending_codegen_jobs.fetchSub(1, .monotonic) == 1) {
            // Decremented to 0, so all done.
            zcu.codegen_prog_node.end();
            zcu.codegen_prog_node = .none;
        }
    }

    // Start the timer for the "decls" part of the pipeline (Sema, CodeGen, link).
    decl_work_timer.* = comp.startTimer();

    // To kick off semantic analysis, populate the root source file of any module we have marked
    // as an analysis root. Declarations in these files which want eager analysis---those being
    // `comptime` declarations, any declarations marked `export`, and `test` declarations in the
    // main module if this is a test compilation---become referenced, and so will be picked up
    // up by the main semantic analysis loop below.
    for (zcu.analysisRoots()) |analysis_root_mod| {
        const analysis_root_file = zcu.module_roots.get(analysis_root_mod).?.unwrap().?;
        try pt.ensureFilePopulated(analysis_root_file);
    }

    // This is the main semantic analysis loop, which is essentially the main loop of the whole
    // Zig compilation pipeline. It selects some `AnalUnit` which we know needs to be analyzed,
    // and analyzes it, which may in turn discover more `AnalUnit`s which we need to analyze.
    while (try zcu.findOutdatedToAnalyze()) |unit| {
        const tracy_trace = traceNamed(@src(), "analyze_outdated");
        defer tracy_trace.end();

        const maybe_err: Zcu.SemaError!void = switch (unit.unwrap()) {
            .@"comptime" => |cu| pt.ensureComptimeUnitUpToDate(cu),
            .nav_ty => |nav| pt.ensureNavTypeUpToDate(nav, null),
            .nav_val => |nav| pt.ensureNavValUpToDate(nav, null),
            .type_layout => |ty| pt.ensureTypeLayoutUpToDate(.fromInterned(ty), null),
            .struct_defaults => |ty| res: {
                // Unlike the other functions, this one requires that the type layout is resolved first.
                pt.ensureTypeLayoutUpToDate(.fromInterned(ty), null) catch |err| switch (err) {
                    error.OutOfMemory,
                    error.Canceled,
                    => |e| return e,

                    error.AnalysisFail => {}, // already reported
                };
                break :res pt.ensureStructDefaultsUpToDate(.fromInterned(ty), null);
            },
            .memoized_state => |stage| pt.ensureMemoizedStateUpToDate(stage, null),
            .func => |func| pt.ensureFuncBodyUpToDate(func, null),
        };
        maybe_err catch |err| switch (err) {
            error.OutOfMemory,
            error.Canceled,
            => |e| return e,

            error.AnalysisFail => {}, // already reported
        };
    }
}
fn workerUpdateBuiltinFile(comp: *Compilation, file: *Zcu.File) void {
    Builtin.updateFileOnDisk(file, comp) catch |err| comp.lockAndSetMiscFailure(
        .write_builtin_zig,
        "unable to write '{f}': {s}",
        .{ file.path.fmt(comp), @errorName(err) },
    );
}
fn workerUpdateFile(
    comp: *Compilation,
    file: *Zcu.File,
    file_index: Zcu.File.Index,
    prog_node: std.Progress.Node,
    group: *Io.Group,
) void {
    const io = comp.io;
    const tid: Zcu.PerThread.Id = .acquire(io);
    defer tid.release(io);

    const child_prog_node = prog_node.start(std.fs.path.basename(file.path.sub_path), 0);
    defer child_prog_node.end();

    const pt: Zcu.PerThread = .activate(comp.zcu.?, tid);
    defer pt.deactivate();
    pt.updateFile(file_index, file) catch |err| {
        pt.reportRetryableFileError(file_index, "unable to load '{s}': {s}", .{ std.fs.path.basename(file.path.sub_path), @errorName(err) }) catch |oom| switch (oom) {
            error.OutOfMemory => {
                comp.mutex.lockUncancelable(io);
                defer comp.mutex.unlock(io);
                comp.setAllocFailure();
            },
        };
        return;
    };

    switch (file.getMode()) {
        .zig => {}, // continue to logic below
        .zon => return, // ZON can't import anything so we're done
    }

    // Discover all imports in the file. Imports of modules we ignore for now since we don't
    // know which module we're in, but imports of file paths might need us to queue up other
    // AstGen jobs.
    const imports_index = file.zir.?.extra[@intFromEnum(Zir.ExtraIndex.imports)];
    if (imports_index != 0) {
        const extra = file.zir.?.extraData(Zir.Inst.Imports, imports_index);
        var import_i: u32 = 0;
        var extra_index = extra.end;

        while (import_i < extra.data.imports_len) : (import_i += 1) {
            const item = file.zir.?.extraData(Zir.Inst.Imports.Item, extra_index);
            extra_index = item.end;

            const import_path = file.zir.?.nullTerminatedString(item.data.name);

            if (pt.discoverImport(file.path, import_path)) |res| switch (res) {
                .module, .existing_file => {},
                .new_file => |new| {
                    group.async(io, workerUpdateFile, .{
                        comp, new.file, new.index, prog_node, group,
                    });
                },
            } else |err| switch (err) {
                error.OutOfMemory => {
                    comp.mutex.lockUncancelable(io);
                    defer comp.mutex.unlock(io);
                    comp.setAllocFailure();
                },
            }
        }
    }
}
fn workerUpdateEmbedFile(comp: *Compilation, ef_index: Zcu.EmbedFile.Index, ef: *Zcu.EmbedFile) void {
    const io = comp.io;
    const tid: Zcu.PerThread.Id = .acquire(io);
    defer tid.release(io);
    detectEmbedFileUpdate(comp, tid, ef_index, ef) catch |err| switch (err) {
        error.OutOfMemory => {
            comp.mutex.lockUncancelable(io);
            defer comp.mutex.unlock(io);
            comp.setAllocFailure();
        },
    };
}
fn detectEmbedFileUpdate(comp: *Compilation, tid: Zcu.PerThread.Id, ef_index: Zcu.EmbedFile.Index, ef: *Zcu.EmbedFile) !void {
    const io = comp.io;
    const zcu = comp.zcu.?;
    const pt: Zcu.PerThread = .activate(zcu, tid);
    defer pt.deactivate();

    const old_val = ef.val;
    const old_err = ef.err;

    try pt.updateEmbedFile(ef, null);

    if (ef.val != .none and ef.val == old_val) return; // success, value unchanged
    if (ef.val == .none and old_val == .none and ef.err == old_err) return; // failure, error unchanged

    comp.mutex.lockUncancelable(io);
    defer comp.mutex.unlock(io);

    try zcu.markDependeeOutdated(.not_marked_po, .{ .embed_file = ef_index });
}

fn deinitFile(pt: Zcu.PerThread, file_index: Zcu.File.Index) void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const file = zcu.fileByIndex(file_index);
    log.debug("deinit File {f}", .{file.path.fmt(zcu.comp)});
    file.path.deinit(gpa);
    file.unload(gpa);
    if (file.prev_zir) |prev_zir| {
        prev_zir.deinit(gpa);
        gpa.destroy(prev_zir);
    }
    file.* = undefined;
}

pub fn destroyFile(pt: Zcu.PerThread, file_index: Zcu.File.Index) void {
    const gpa = pt.zcu.gpa;
    const file = pt.zcu.fileByIndex(file_index);
    pt.deinitFile(file_index);
    gpa.destroy(file);
}

/// Ensures that `file` has up-to-date ZIR. If not, loads the ZIR cache or runs
/// AstGen as needed. Also updates `file.status`. Does not assume that `file.mod`
/// is populated. Does not return `error.AnalysisFail` on AstGen failures.
pub fn updateFile(
    pt: Zcu.PerThread,
    file_index: Zcu.File.Index,
    file: *Zcu.File,
) !void {
    dev.check(.ast_gen);

    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = zcu.gpa;
    const io = comp.io;

    // In any case we need to examine the stat of the file to determine the course of action.
    var source_file = f: {
        const dir, const sub_path = file.path.openInfo(comp.dirs);
        break :f try dir.openFile(io, sub_path, .{});
    };
    defer source_file.close(io);

    const stat = try source_file.stat(io);

    const want_local_cache = switch (file.path.root) {
        .none, .local_cache => true,
        .global_cache, .zig_lib => false,
    };

    const hex_digest: Cache.HexDigest = d: {
        var h: Cache.HashHelper = .{};
        // As well as the file path, we also include the compiler version in case of backwards-incompatible ZIR changes.
        file.path.addToHasher(&h.hasher);
        h.addBytes(build_options.version);
        h.add(builtin.zig_backend);
        break :d h.final();
    };

    const cache_directory = if (want_local_cache) zcu.local_zir_cache else zcu.global_zir_cache;
    const zir_dir = cache_directory.handle;

    // Determine whether we need to reload the file from disk and redo parsing and AstGen.
    var lock: Io.File.Lock = switch (file.status) {
        .never_loaded, .retryable_failure => lock: {
            // First, load the cached ZIR code, if any.
            log.debug("AstGen checking cache: {f} (local={}, digest={s})", .{
                file.path.fmt(comp), want_local_cache, &hex_digest,
            });

            break :lock .shared;
        },
        .astgen_failure, .success => lock: {
            const unchanged_metadata =
                stat.size == file.stat.size and
                stat.mtime.nanoseconds == file.stat.mtime.nanoseconds and
                stat.inode == file.stat.inode;

            if (unchanged_metadata) {
                log.debug("unmodified metadata of file: {f}", .{file.path.fmt(comp)});
                return;
            }

            log.debug("metadata changed: {f}", .{file.path.fmt(comp)});

            break :lock .exclusive;
        },
    };

    // The old compile error, if any, is no longer relevant.
    pt.lockAndClearFileCompileError(file_index, file);

    // If `zir` is not null, and `prev_zir` is null, then `TrackedInst`s are associated with `zir`.
    // We need to keep it around!
    // As an optimization, also check `loweringFailed`; if true, but `prev_zir == null`, then this
    // file has never passed AstGen, so we actually need not cache the old ZIR.
    if (file.zir != null and file.prev_zir == null and !file.zir.?.loweringFailed()) {
        assert(file.prev_zir == null);
        const prev_zir_ptr = try gpa.create(Zir);
        file.prev_zir = prev_zir_ptr;
        prev_zir_ptr.* = file.zir.?;
        file.zir = null;
    }

    // If ZOIR is changing, then we need to invalidate dependencies on it
    if (file.zoir != null) file.zoir_invalidated = true;

    // We're going to re-load everything, so unload source, AST, ZIR, ZOIR.
    file.unload(gpa);

    // We ask for a lock in order to coordinate with other zig processes.
    // If another process is already working on this file, we will get the cached
    // version. Likewise if we're working on AstGen and another process asks for
    // the cached file, they'll get it.
    const cache_file = while (true) {
        break zir_dir.createFile(io, &hex_digest, .{
            .read = true,
            .truncate = false,
            .lock = lock,
        }) catch |err| switch (err) {
            error.NotDir => unreachable, // no dir components
            error.BadPathName => unreachable, // it's a hex encoded name
            error.NameTooLong => unreachable, // it's a fixed size name
            error.PipeBusy => unreachable, // it's not a pipe
            error.NoDevice => unreachable, // it's not a pipe
            error.WouldBlock => unreachable, // not asking for non-blocking I/O
            error.FileNotFound => {
                // There are no dir components, so the only possibility should
                // be that the directory behind the handle has been deleted,
                // however we have observed on macOS two processes racing to do
                // openat() with O_CREAT manifest in ENOENT.
                //
                // As a workaround, we retry with exclusive=true which
                // disambiguates by returning EEXIST, indicating original
                // failure was a race, or ENOENT, indicating deletion of the
                // directory of our open handle.
                if (!builtin.os.tag.isDarwin()) {
                    std.process.fatal("cache directory '{f}' unexpectedly removed during compiler execution", .{
                        cache_directory,
                    });
                }
                break zir_dir.createFile(io, &hex_digest, .{
                    .read = true,
                    .truncate = false,
                    .lock = lock,
                    .exclusive = true,
                }) catch |excl_err| switch (excl_err) {
                    error.PathAlreadyExists => continue,
                    error.FileNotFound => {
                        std.process.fatal("cache directory '{f}' unexpectedly removed during compiler execution", .{
                            cache_directory,
                        });
                    },
                    else => |e| return e,
                };
            },

            else => |e| return e, // Retryable errors are handled at callsite.
        };
    };
    defer cache_file.close(io);

    // Under `--time-report`, ignore cache hits; do the work anyway for those juicy numbers.
    const ignore_hit = comp.time_report != null;

    const need_update = while (true) {
        const result = switch (file.getMode()) {
            inline else => |mode| try loadZirZoirCache(zcu, cache_file, stat, file, mode),
        };
        switch (result) {
            .success => if (!ignore_hit) {
                log.debug("AstGen cached success: {f}", .{file.path.fmt(comp)});
                break false;
            },
            .invalid => {},
            .truncated => log.warn("unexpected EOF reading cached ZIR for {f}", .{file.path.fmt(comp)}),
            .stale => log.debug("AstGen cache stale: {f}", .{file.path.fmt(comp)}),
        }

        // If we already have the exclusive lock then it is our job to update.
        if (builtin.os.tag == .wasi or lock == .exclusive) break true;
        // Otherwise, unlock to give someone a chance to get the exclusive lock
        // and then upgrade to an exclusive lock.
        cache_file.unlock(io);
        lock = .exclusive;
        try cache_file.lock(io, lock);
    };

    if (need_update) {
        var cache_file_writer: Io.File.Writer = .init(cache_file, io, &.{});

        if (stat.size > std.math.maxInt(u32))
            return error.FileTooBig;

        const source = try gpa.allocSentinel(u8, @intCast(stat.size), 0);
        defer if (file.source == null) gpa.free(source);
        var source_fr = source_file.reader(io, &.{});
        source_fr.size = stat.size;
        source_fr.interface.readSliceAll(source) catch |err| switch (err) {
            error.ReadFailed => return source_fr.err.?,
            error.EndOfStream => return error.UnexpectedEndOfFile,
        };

        file.source = source;

        var timer = comp.startTimer();
        // Any potential AST errors are converted to ZIR errors when we run AstGen/ZonGen.
        file.tree = try Ast.parse(gpa, source, file.getMode());
        if (timer.finish(io)) |ns_parse| {
            comp.mutex.lockUncancelable(io);
            defer comp.mutex.unlock(io);
            comp.time_report.?.stats.cpu_ns_parse += ns_parse;
        }

        timer = comp.startTimer();
        switch (file.getMode()) {
            .zig => {
                file.zir = try AstGen.generate(gpa, file.tree.?);
                Zcu.saveZirCache(gpa, &cache_file_writer, stat, file.zir.?) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    else => log.warn("unable to write cached ZIR code for {f} to {f}{s}: {t}", .{
                        file.path.fmt(comp), cache_directory, &hex_digest, err,
                    }),
                };
            },
            .zon => {
                file.zoir = try ZonGen.generate(gpa, file.tree.?, .{});
                Zcu.saveZoirCache(&cache_file_writer, stat, file.zoir.?) catch |err| {
                    log.warn("unable to write cached ZOIR code for {f} to {f}{s}: {t}", .{
                        file.path.fmt(comp), cache_directory, &hex_digest, err,
                    });
                };
            },
        }

        cache_file_writer.end() catch |err| switch (err) {
            error.WriteFailed => return cache_file_writer.err.?,
            else => |e| return e,
        };

        if (timer.finish(io)) |ns_astgen| {
            comp.mutex.lockUncancelable(io);
            defer comp.mutex.unlock(io);
            comp.time_report.?.stats.cpu_ns_astgen += ns_astgen;
        }

        log.debug("AstGen fresh success: {f}", .{file.path.fmt(comp)});
    }

    file.stat = .{
        .size = stat.size,
        .inode = stat.inode,
        .mtime = stat.mtime,
    };

    // Now, `zir` or `zoir` is definitely populated and up-to-date.
    // Mark file successes/failures as needed.

    switch (file.getMode()) {
        .zig => {
            if (file.zir.?.hasCompileErrors()) {
                comp.mutex.lockUncancelable(io);
                defer comp.mutex.unlock(io);
                try zcu.failed_files.putNoClobber(gpa, file_index, null);
            }
            if (file.zir.?.loweringFailed()) {
                file.status = .astgen_failure;
            } else {
                file.status = .success;
            }
        },
        .zon => {
            if (file.zoir.?.hasCompileErrors()) {
                file.status = .astgen_failure;
                comp.mutex.lockUncancelable(io);
                defer comp.mutex.unlock(io);
                try zcu.failed_files.putNoClobber(gpa, file_index, null);
            } else {
                file.status = .success;
            }
        },
    }

    switch (file.status) {
        .never_loaded => unreachable,
        .retryable_failure => unreachable,
        .astgen_failure, .success => {},
    }
}

fn loadZirZoirCache(
    zcu: *Zcu,
    cache_file: Io.File,
    stat: Io.File.Stat,
    file: *Zcu.File,
    comptime mode: Ast.Mode,
) !enum { success, invalid, truncated, stale } {
    assert(file.getMode() == mode);

    const gpa = zcu.gpa;
    const io = zcu.comp.io;

    const Header = switch (mode) {
        .zig => Zir.Header,
        .zon => Zoir.Header,
    };

    var buffer: [2000]u8 = undefined;
    var cache_fr = cache_file.reader(io, &buffer);
    cache_fr.size = stat.size;
    const cache_br = &cache_fr.interface;

    // First we read the header to determine the lengths of arrays.
    const header = (cache_br.takeStructPointer(Header) catch |err| switch (err) {
        error.ReadFailed => return cache_fr.err.?,
        // This can happen if Zig bails out of this function between creating
        // the cached file and writing it.
        error.EndOfStream => return .invalid,
        else => |e| return e,
    }).*;

    const unchanged_metadata =
        stat.size == header.stat_size and
        stat.mtime.nanoseconds == header.stat_mtime and
        stat.inode == header.stat_inode;

    if (!unchanged_metadata) {
        return .stale;
    }

    switch (mode) {
        .zig => file.zir = Zcu.loadZirCacheBody(gpa, header, cache_br) catch |err| switch (err) {
            error.ReadFailed => return cache_fr.err.?,
            error.EndOfStream => return .truncated,
            else => |e| return e,
        },
        .zon => file.zoir = Zcu.loadZoirCacheBody(gpa, header, cache_br) catch |err| switch (err) {
            error.ReadFailed => return cache_fr.err.?,
            error.EndOfStream => return .truncated,
            else => |e| return e,
        },
    }

    return .success;
}

const UpdatedFile = struct {
    file: *Zcu.File,
    inst_map: std.AutoHashMapUnmanaged(Zir.Inst.Index, Zir.Inst.Index),
};

fn cleanupUpdatedFiles(gpa: Allocator, updated_files: *std.AutoArrayHashMapUnmanaged(Zcu.File.Index, UpdatedFile)) void {
    for (updated_files.values()) |*elem| elem.inst_map.deinit(gpa);
    updated_files.deinit(gpa);
}

fn updateZirRefs(pt: Zcu.PerThread) (Io.Cancelable || Allocator.Error)!void {
    assert(pt.tid == .main);
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const ip = &zcu.intern_pool;
    const gpa = comp.gpa;
    const io = comp.io;

    // We need to visit every updated File for every TrackedInst in InternPool.
    // This only includes Zig files; ZON files are omitted.
    var updated_files: std.AutoArrayHashMapUnmanaged(Zcu.File.Index, UpdatedFile) = .empty;
    defer cleanupUpdatedFiles(gpa, &updated_files);

    for (zcu.import_table.keys()) |file_index| {
        if (!zcu.alive_files.contains(file_index)) continue;
        const file = zcu.fileByIndex(file_index);
        assert(file.status == .success);
        if (file.module_changed) {
            try updated_files.putNoClobber(gpa, file_index, .{
                .file = file,
                // We intentionally don't map any instructions here; that's the point, the whole file is outdated!
                .inst_map = .{},
            });
            continue;
        }
        switch (file.getMode()) {
            .zig => {}, // logic below
            .zon => {
                if (file.zoir_invalidated) {
                    try zcu.markDependeeOutdated(.not_marked_po, .{ .source_file = file_index });
                    file.zoir_invalidated = false;
                }
                continue;
            },
        }
        const old_zir = file.prev_zir orelse continue;
        const new_zir = file.zir.?;
        const gop = try updated_files.getOrPut(gpa, file_index);
        assert(!gop.found_existing);
        gop.value_ptr.* = .{
            .file = file,
            .inst_map = .{},
        };
        try Zcu.mapOldZirToNew(gpa, old_zir.*, new_zir, &gop.value_ptr.inst_map);
    }

    if (updated_files.count() == 0)
        return;

    for (ip.locals, 0..) |*local, tid| {
        const tracked_insts_list = local.getMutableTrackedInsts(gpa, io);
        for (tracked_insts_list.viewAllowEmpty().items(.@"0"), 0..) |*tracked_inst, tracked_inst_unwrapped_index| {
            const file_index = tracked_inst.file;
            const updated_file = updated_files.get(file_index) orelse continue;

            const file = updated_file.file;

            const old_inst = tracked_inst.inst.unwrap() orelse continue; // we can't continue tracking lost insts
            const tracked_inst_index = (InternPool.TrackedInst.Index.Unwrapped{
                .tid = @enumFromInt(tid),
                .index = @intCast(tracked_inst_unwrapped_index),
            }).wrap(ip);
            const new_inst = updated_file.inst_map.get(old_inst) orelse {
                // Tracking failed for this instruction due to changes in the ZIR.
                // Invalidate associated `src_hash` deps.
                log.debug("tracking failed for %{d}", .{old_inst});
                tracked_inst.inst = .lost;
                try zcu.markDependeeOutdated(.not_marked_po, .{ .src_hash = tracked_inst_index });
                continue;
            };
            tracked_inst.inst = InternPool.TrackedInst.MaybeLost.ZirIndex.wrap(new_inst);

            const old_zir = file.prev_zir.?.*;
            const new_zir = file.zir.?;
            const old_tag = old_zir.instructions.items(.tag)[@intFromEnum(old_inst)];
            const old_data = old_zir.instructions.items(.data)[@intFromEnum(old_inst)];

            switch (old_tag) {
                .declaration => {
                    const old_line = old_zir.getDeclaration(old_inst).src_line;
                    const new_line = new_zir.getDeclaration(new_inst).src_line;
                    if (old_line != new_line) {
                        try comp.link_queue.enqueueZcu(comp, pt.tid, .{ .debug_update_line_number = tracked_inst_index });
                    }
                },
                else => {},
            }

            if (old_zir.getAssociatedSrcHash(old_inst)) |old_hash| hash_changed: {
                if (new_zir.getAssociatedSrcHash(new_inst)) |new_hash| {
                    if (std.zig.srcHashEql(old_hash, new_hash)) {
                        break :hash_changed;
                    }
                    log.debug("hash for (%{d} -> %{d}) changed: {x} -> {x}", .{
                        old_inst, new_inst, &old_hash, &new_hash,
                    });
                }
                // The source hash associated with this instruction changed - invalidate relevant dependencies.
                try zcu.markDependeeOutdated(.not_marked_po, .{ .src_hash = tracked_inst_index });
            }

            // If this is a `struct_decl` etc, we must invalidate any outdated namespace dependencies.
            const has_namespace = switch (old_tag) {
                .extended => switch (old_data.extended.opcode) {
                    .struct_decl, .union_decl, .opaque_decl, .enum_decl => true,
                    else => false,
                },
                else => false,
            };
            if (!has_namespace) continue;

            // Value is whether the declaration is `pub`.
            var old_names: std.AutoArrayHashMapUnmanaged(InternPool.NullTerminatedString, bool) = .empty;
            defer old_names.deinit(zcu.gpa);
            for (old_zir.typeDecls(old_inst)) |decl_inst| {
                const old_decl = old_zir.getDeclaration(decl_inst);
                if (old_decl.name == .empty) continue;
                const name_ip = try zcu.intern_pool.getOrPutString(
                    zcu.gpa,
                    io,
                    pt.tid,
                    old_zir.nullTerminatedString(old_decl.name),
                    .no_embedded_nulls,
                );
                try old_names.put(zcu.gpa, name_ip, old_decl.is_pub);
            }
            var any_change = false;
            for (new_zir.typeDecls(new_inst)) |decl_inst| {
                const new_decl = new_zir.getDeclaration(decl_inst);
                if (new_decl.name == .empty) continue;
                const name_ip = try zcu.intern_pool.getOrPutString(
                    zcu.gpa,
                    io,
                    pt.tid,
                    new_zir.nullTerminatedString(new_decl.name),
                    .no_embedded_nulls,
                );
                if (old_names.fetchSwapRemove(name_ip)) |kv| {
                    if (kv.value == new_decl.is_pub) continue;
                }
                // Name added, or changed whether it's pub
                any_change = true;
                try zcu.markDependeeOutdated(.not_marked_po, .{ .namespace_name = .{
                    .namespace = tracked_inst_index,
                    .name = name_ip,
                } });
            }
            // The only elements remaining in `old_names` now are any names which were removed.
            for (old_names.keys()) |name_ip| {
                any_change = true;
                try zcu.markDependeeOutdated(.not_marked_po, .{ .namespace_name = .{
                    .namespace = tracked_inst_index,
                    .name = name_ip,
                } });
            }

            if (any_change) {
                try zcu.markDependeeOutdated(.not_marked_po, .{ .namespace = tracked_inst_index });
            }
        }
    }

    try ip.rehashTrackedInsts(gpa, io, pt.tid);

    for (updated_files.keys(), updated_files.values()) |file_index, updated_file| {
        const file = updated_file.file;

        if (file.prev_zir) |prev_zir| {
            prev_zir.deinit(gpa);
            gpa.destroy(prev_zir);
            file.prev_zir = null;
        }
        file.module_changed = false;

        // For every file which has changed, re-scan the namespace of the file's root struct type.
        // These types are special-cased because they don't have an enclosing declaration which will
        // be re-analyzed (causing the struct's namespace to be re-scanned). It's fine to do this
        // now because this work is fast (no actual Sema work is happening, we're just updating the
        // namespace contents). We must do this after updating ZIR refs above, since `scanNamespace`
        // calls will track some instructions.
        try pt.updateFileRootStructType(file_index);
    }
}

/// Ensures that `zcu.fileRootType` on this `file_index` is populated (not `.none`). This implies
/// that the file's namespace is scanned, discovering declarations.
///
/// Typical Zig compilations begin by claling this function on the root source file of the standard
/// library, `lib/std/std.zig`. The resulting namespace scan discovers a `comptime` declaration in
/// that file, which is queued for analysis, and everything goes from there.
pub fn ensureFilePopulated(pt: Zcu.PerThread, file_index: Zcu.File.Index) (Allocator.Error || Io.Cancelable)!void {
    dev.check(.sema);

    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    if (zcu.fileRootType(file_index) != .none) return; // already good

    if (zcu.comp.time_report) |*tr| tr.stats.n_imported_files += 1;

    const file = zcu.fileByIndex(file_index);
    assert(file.getMode() == .zig);
    const struct_decl = file.zir.?.getStructDecl(.main_struct_inst);
    const tracked_inst = try ip.trackZir(gpa, io, pt.tid, .{
        .file = file_index,
        .inst = .main_struct_inst,
    });
    const wip: InternPool.WipContainerType = switch (try ip.getDeclaredStructType(gpa, io, pt.tid, .{
        .zir_index = tracked_inst,
        .captures = &.{},
        .fields_len = @intCast(struct_decl.field_names.len),
        .layout = struct_decl.layout,
        .any_comptime_fields = struct_decl.field_comptime_bits != null,
        .any_field_defaults = struct_decl.field_default_body_lens != null,
        .any_field_aligns = struct_decl.field_align_body_lens != null,
        .packed_backing_mode = if (struct_decl.backing_int_type_body != null) .explicit else .auto,
    })) {
        .existing => unreachable, // it would have been set as `zcu.fileRootType` already
        .wip => |wip| wip,
    };
    errdefer wip.cancel(ip, pt.tid);

    wip.setName(ip, try file.internFullyQualifiedName(pt), .none);
    const new_namespace_index: InternPool.NamespaceIndex = try pt.createNamespace(.{
        .parent = .none,
        .owner_type = wip.index,
        .file_scope = file_index,
        .generation = zcu.generation,
    });
    errdefer pt.destroyNamespace(new_namespace_index);
    try pt.scanNamespace(new_namespace_index, struct_decl.decls);
    if (zcu.comp.debugIncremental()) try zcu.incremental_debug_state.newType(zcu, wip.index);
    zcu.setFileRootType(file_index, wip.finish(ip, new_namespace_index));
}

/// Ensures that all memoized state on `Zcu` is up-to-date, performing re-analysis if necessary.
/// Returns `error.AnalysisFail` if an analysis error is encountered; the caller is free to ignore
/// this, since the error is already registered, but it must not use the value of memoized fields.
pub fn ensureMemoizedStateUpToDate(
    pt: Zcu.PerThread,
    stage: InternPool.MemoizedStateStage,
    /// `null` is valid only for the "root" analysis, i.e. called from `Compilation.processOneJob`.
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    const unit: AnalUnit = .wrap(.{ .memoized_state = stage });

    log.debug("ensureMemoizedStateUpToDate", .{});

    assert(!zcu.analysis_in_progress.contains(unit));

    const was_outdated = zcu.clearOutdatedState(unit);
    const prev_failed = zcu.failed_analysis.contains(unit) or zcu.transitive_failed_analysis.contains(unit);

    if (was_outdated) {
        zcu.resetUnit(unit);
    } else {
        if (prev_failed) return error.AnalysisFail;
        // We use an arbitrary element to check if the state has been resolved yet.
        const to_check: Zcu.BuiltinDecl = switch (stage) {
            .main => .Type,
            .panic => .panic,
            .va_list => .VaList,
            .assembly => .assembly,
        };
        if (zcu.builtin_decl_values.get(to_check) != .none) return;
    }

    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const any_changed: bool, const new_failed: bool = if (pt.analyzeMemoizedState(stage, reason)) |any_changed|
        .{ any_changed or prev_failed, false }
    else |err| switch (err) {
        error.AnalysisFail => res: {
            if (!zcu.failed_analysis.contains(unit)) {
                // If this unit caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(unit)});
            }
            break :res .{ !prev_failed, true };
        },
        error.OutOfMemory => {
            // TODO: same as for `ensureComptimeUnitUpToDate` etc
            return error.OutOfMemory;
        },
        error.Canceled => |e| return e,
        error.ComptimeReturn => unreachable,
        error.ComptimeBreak => unreachable,
    };

    if (was_outdated) {
        const dependee: InternPool.Dependee = .{ .memoized_state = stage };
        if (any_changed) {
            try zcu.markDependeeOutdated(.marked_po, dependee);
        } else {
            try zcu.markPoDependeeUpToDate(dependee);
        }
    }

    if (new_failed) return error.AnalysisFail;
}

fn analyzeMemoizedState(
    pt: Zcu.PerThread,
    stage: InternPool.MemoizedStateStage,
    reason: ?*const Zcu.DependencyReason,
) Zcu.CompileError!bool {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;

    const unit: AnalUnit = .wrap(.{ .memoized_state = stage });

    try zcu.analysis_in_progress.putNoClobber(gpa, unit, reason);
    defer assert(zcu.analysis_in_progress.swapRemove(unit));

    var analysis_arena: std.heap.ArenaAllocator = .init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace: std.array_list.Managed(Zcu.LazySrcLoc) = .init(gpa);
    defer comptime_err_ret_trace.deinit();

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = .{ .instructions = .empty, .string_bytes = &.{}, .extra = &.{} },
        .owner = unit,
        .func_index = .none,
        .func_is_naked = false,
        .fn_ret_ty = .void,
        .fn_ret_ty_ies = null,
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    return sema.analyzeMemoizedState(stage);
}

/// Ensures that the state of the given `ComptimeUnit` is fully up-to-date, performing re-analysis
/// if necessary. Returns `error.AnalysisFail` if an analysis error is encountered; the caller is
/// free to ignore this, since the error is already registered.
pub fn ensureComptimeUnitUpToDate(pt: Zcu.PerThread, cu_id: InternPool.ComptimeUnit.Id) Zcu.SemaError!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    const anal_unit: AnalUnit = .wrap(.{ .@"comptime" = cu_id });

    log.debug("ensureComptimeUnitUpToDate {f}", .{zcu.fmtAnalUnit(anal_unit)});

    assert(!zcu.analysis_in_progress.contains(anal_unit));

    // Determine whether or not this `ComptimeUnit` is outdated. For this kind of `AnalUnit`, that's
    // the only indicator as to whether or not analysis is required; when a `ComptimeUnit` is first
    // created, it's marked as outdated.
    //
    // Note that if the unit is PO, we pessimistically assume that it *does* require re-analysis, to
    // ensure that the unit is definitely up-to-date when this function returns. This mechanism could
    // result in over-analysis if analysis occurs in a poor order; we do our best to avoid this by
    // carefully choosing which units to re-analyze. See `Zcu.findOutdatedToAnalyze`.

    const was_outdated = zcu.clearOutdatedState(anal_unit);

    if (was_outdated) {
        zcu.resetUnit(anal_unit);
    } else {
        // We can trust the current information about this unit.
        if (zcu.failed_analysis.contains(anal_unit)) return error.AnalysisFail;
        if (zcu.transitive_failed_analysis.contains(anal_unit)) return error.AnalysisFail;
        return;
    }

    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, anal_unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const unit_tracking = zcu.trackUnitSema(
        "comptime",
        zcu.intern_pool.getComptimeUnit(cu_id).zir_index,
    );
    defer unit_tracking.end(zcu);

    return pt.analyzeComptimeUnit(cu_id) catch |err| switch (err) {
        error.AnalysisFail => {
            if (!zcu.failed_analysis.contains(anal_unit)) {
                // If this unit caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, anal_unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(anal_unit)});
            }
            return error.AnalysisFail;
        },
        error.OutOfMemory => {
            // TODO: it's unclear how to gracefully handle this.
            // To report the error cleanly, we need to add a message to `failed_analysis` and a
            // corresponding entry to `retryable_failures`; but either of these things is quite
            // likely to OOM at this point.
            // If that happens, what do we do? Perhaps we could have a special field on `Zcu`
            // for reporting OOM errors without allocating.
            return error.OutOfMemory;
        },
        error.Canceled => |e| return e,
        error.ComptimeReturn => unreachable,
        error.ComptimeBreak => unreachable,
    };
}

/// Re-analyzes a `ComptimeUnit`. The unit has already been determined to be out-of-date, and old
/// side effects (exports/references/etc) have been dropped. If semantic analysis fails, this
/// function will return `error.AnalysisFail`, and it is the caller's reponsibility to add an entry
/// to `transitive_failed_analysis` if necessary.
fn analyzeComptimeUnit(pt: Zcu.PerThread, cu_id: InternPool.ComptimeUnit.Id) Zcu.CompileError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;

    const anal_unit: AnalUnit = .wrap(.{ .@"comptime" = cu_id });
    const comptime_unit = ip.getComptimeUnit(cu_id);

    log.debug("analyzeComptimeUnit {f}", .{zcu.fmtAnalUnit(anal_unit)});

    const inst_resolved = comptime_unit.zir_index.resolveFull(ip) orelse return error.AnalysisFail;
    const file = zcu.fileByIndex(inst_resolved.file);
    const zir = file.zir.?;

    try zcu.analysis_in_progress.putNoClobber(gpa, anal_unit, null);
    defer assert(zcu.analysis_in_progress.swapRemove(anal_unit));

    var analysis_arena: std.heap.ArenaAllocator = .init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace: std.array_list.Managed(Zcu.LazySrcLoc) = .init(gpa);
    defer comptime_err_ret_trace.deinit();

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = zir,
        .owner = anal_unit,
        .func_index = .none,
        .func_is_naked = false,
        .fn_ret_ty = .void,
        .fn_ret_ty_ies = null,
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    // The comptime unit declares on the source of the corresponding `comptime` declaration.
    try sema.declareDependency(.{ .src_hash = comptime_unit.zir_index });

    var block: Sema.Block = .{
        .parent = null,
        .sema = &sema,
        .namespace = comptime_unit.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = .{ .reason = .{
            .src = .{
                .base_node_inst = comptime_unit.zir_index,
                .offset = .{ .token_offset = .zero },
            },
            .r = .{ .simple = .comptime_keyword },
        } },
        .src_base_inst = comptime_unit.zir_index,
        .type_name_ctx = try ip.getOrPutStringFmt(gpa, io, pt.tid, "{f}.comptime", .{
            Type.fromInterned(zcu.namespacePtr(comptime_unit.namespace).owner_type).containerTypeName(ip).fmt(ip),
        }, .no_embedded_nulls),
    };
    defer block.instructions.deinit(gpa);

    const zir_decl = zir.getDeclaration(inst_resolved.inst);
    assert(zir_decl.kind == .@"comptime");
    assert(zir_decl.type_body == null);
    assert(zir_decl.align_body == null);
    assert(zir_decl.linksection_body == null);
    assert(zir_decl.addrspace_body == null);
    const value_body = zir_decl.value_body.?;

    const result_ref = try sema.resolveInlineBody(&block, value_body, inst_resolved.inst);
    assert(result_ref == .void_value); // AstGen should always uphold this

    // Nothing else to do -- for a comptime decl, all we care about are the side effects.
    // Just make sure to `flushExports`.
    try sema.flushExports();
}

/// Ensures that the layout of the given `struct`, `union`, or `enum` type is fully up-to-date,
/// performing re-analysis if necessary. Asserts that `ty` is a struct (not a tuple!), union, or
/// enum type. Returns `error.AnalysisFail` if an analysis error is encountered during type
/// resolution; the caller is free to ignore this, since the error is already registered.
pub fn ensureTypeLayoutUpToDate(
    pt: Zcu.PerThread,
    ty: Type,
    /// `null` is valid only for the "root" analysis, i.e. called from `Compilation.processOneJob`.
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const comp = zcu.comp;
    const gpa = comp.gpa;

    const anal_unit: AnalUnit = .wrap(.{ .type_layout = ty.toIntern() });

    log.debug("ensureTypeLayoutUpToDate {f}", .{zcu.fmtAnalUnit(anal_unit)});

    assert(!zcu.analysis_in_progress.contains(anal_unit));

    const was_outdated: bool = outdated: {
        if (zcu.clearOutdatedState(anal_unit)) break :outdated true;
        if (ip.setWantTypeLayout(comp.io, ty.toIntern())) {
            // We'll analyze the layout for the first time, but if this is a struct type then its
            // default field values also need to be analyzed.
            if (ip.indexToKey(ty.toIntern()) == .struct_type) {
                if (std.debug.runtime_safety) zcu.outdated_lock.lockUncancelable(zcu.comp.io);
                defer if (std.debug.runtime_safety) zcu.outdated_lock.unlock(zcu.comp.io);
                try zcu.outdated.ensureUnusedCapacity(gpa, 1);
                try zcu.outdated_ready.other.ensureUnusedCapacity(gpa, 1);
                zcu.outdated.putAssumeCapacityNoClobber(.wrap(.{ .struct_defaults = ty.toIntern() }), 0);
                zcu.outdated_ready.other.putAssumeCapacityNoClobber(.wrap(.{ .struct_defaults = ty.toIntern() }), {});
            }
            break :outdated true;
        }
        break :outdated false;
    };

    if (was_outdated) {
        zcu.resetUnit(anal_unit);
        // For types, we already know that we have to invalidate all dependees.
        // TODO: we actually *could* detect whether everything was the same. should we bother?
        try zcu.markDependeeOutdated(.marked_po, .{ .type_layout = ty.toIntern() });
    } else {
        // We can trust the current information about this unit.
        if (zcu.failed_analysis.contains(anal_unit)) return error.AnalysisFail;
        if (zcu.transitive_failed_analysis.contains(anal_unit)) return error.AnalysisFail;
        return;
    }

    if (comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, anal_unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const unit_tracking = zcu.trackUnitSema(ty.containerTypeName(ip).toSlice(ip), null);
    defer unit_tracking.end(zcu);

    try zcu.analysis_in_progress.put(gpa, anal_unit, reason);
    defer assert(zcu.analysis_in_progress.swapRemove(anal_unit));

    var analysis_arena: std.heap.ArenaAllocator = .init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace: std.array_list.Managed(Zcu.LazySrcLoc) = .init(gpa);
    defer comptime_err_ret_trace.deinit();

    const file = zcu.namespacePtr(ty.getNamespaceIndex(zcu)).fileScope(zcu);

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = file.zir.?,
        .owner = anal_unit,
        .func_index = .none,
        .func_is_naked = false,
        .fn_ret_ty = .void,
        .fn_ret_ty_ies = null,
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    const result = switch (ty.zigTypeTag(zcu)) {
        .@"enum" => Sema.type_resolution.resolveEnumLayout(&sema, ty),
        .@"struct" => Sema.type_resolution.resolveStructLayout(&sema, ty),
        .@"union" => Sema.type_resolution.resolveUnionLayout(&sema, ty),
        else => unreachable,
    };
    const new_failed: bool = if (result) failed: {
        break :failed false;
    } else |err| switch (err) {
        error.AnalysisFail => failed: {
            if (!zcu.failed_analysis.contains(anal_unit)) {
                // If this unit caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, anal_unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(anal_unit)});
            }
            break :failed true;
        },
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,
        error.ComptimeReturn => unreachable,
        error.ComptimeBreak => unreachable,
    };

    sema.flushExports() catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
    };

    // We don't need to `markDependeeOutdated`/`markPoDependeeUpToDate` here, because we already
    // marked the layout as outdated at the top of this function. However, we do need to tell the
    // debug info logic in the backend about this type.
    comp.link_prog_node.increaseEstimatedTotalItems(1);
    try comp.link_queue.enqueueZcu(comp, pt.tid, .{ .debug_update_container_type = .{
        .ty = ty.toIntern(),
        .success = !new_failed,
    } });

    if (new_failed) return error.AnalysisFail;
}

/// Ensures that the default field values of the given `struct` type are fully up-to-date,
/// performing re-analysis if necessary. Asserts that `ty` is a struct (not a tuple!) type. Unlike
/// the other "ensure X up to date" functions, this particular function also asserts that the
/// *layout* of `ty` is *already* up-to-date (though it is okay for that resolution to have failed).
/// Returns `error.AnalysisFail` if an analysis error is encountered while resolving the default
/// field values; the caller is free to ignore this, since the error is already registered.
pub fn ensureStructDefaultsUpToDate(
    pt: Zcu.PerThread,
    ty: Type,
    /// `null` is valid only for the "root" analysis, i.e. called from `Compilation.processOneJob`.
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const comp = zcu.comp;
    const gpa = comp.gpa;

    assert(ip.indexToKey(ty.toIntern()) == .struct_type);

    const anal_unit: AnalUnit = .wrap(.{ .struct_defaults = ty.toIntern() });

    log.debug("ensureStructDefaultsUpToDate {f}", .{zcu.fmtAnalUnit(anal_unit)});

    assert(!zcu.analysis_in_progress.contains(anal_unit));

    const was_outdated: bool = outdated: {
        if (zcu.clearOutdatedState(anal_unit)) break :outdated true;
        // The type layout should already be marked as "wanted" by this point, because a struct's
        // layout must always be analyzed before its default values are.
        assert(!ip.setWantTypeLayout(comp.io, ty.toIntern()));
        break :outdated false;
    };

    if (was_outdated) {
        zcu.resetUnit(anal_unit);
        // For types, we already know that we have to invalidate all dependees.
        // TODO: we actually *could* detect whether everything was the same. should we bother?
        try zcu.markDependeeOutdated(.marked_po, .{ .struct_defaults = ty.toIntern() });
    } else {
        // We can trust the current information about this unit.
        if (zcu.failed_analysis.contains(anal_unit)) return error.AnalysisFail;
        if (zcu.transitive_failed_analysis.contains(anal_unit)) return error.AnalysisFail;
        return;
    }

    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, anal_unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const unit_tracking = zcu.trackUnitSema(ty.containerTypeName(ip).toSlice(ip), null);
    defer unit_tracking.end(zcu);

    try zcu.analysis_in_progress.put(gpa, anal_unit, reason);
    defer assert(zcu.analysis_in_progress.swapRemove(anal_unit));

    var analysis_arena: std.heap.ArenaAllocator = .init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace: std.array_list.Managed(Zcu.LazySrcLoc) = .init(gpa);
    defer comptime_err_ret_trace.deinit();

    const file = zcu.namespacePtr(ty.getNamespaceIndex(zcu)).fileScope(zcu);

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = file.zir.?,
        .owner = anal_unit,
        .func_index = .none,
        .func_is_naked = false,
        .fn_ret_ty = .void,
        .fn_ret_ty_ies = null,
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    const new_failed: bool = if (Sema.type_resolution.resolveStructDefaults(&sema, ty)) failed: {
        break :failed false;
    } else |err| switch (err) {
        error.AnalysisFail => failed: {
            if (!zcu.failed_analysis.contains(anal_unit)) {
                // If this unit caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, anal_unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(anal_unit)});
            }
            break :failed true;
        },
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,
        error.ComptimeReturn => unreachable,
        error.ComptimeBreak => unreachable,
    };

    sema.flushExports() catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
    };

    // We don't need to `markDependeeOutdated`/`markPoDependeeUpToDate` here, because we already
    // marked the struct defaults as outdated at the top of this function.

    if (new_failed) return error.AnalysisFail;
}

/// Ensures that the resolved value of the given `Nav` is fully up-to-date, performing re-analysis
/// if necessary. Returns `error.AnalysisFail` if an analysis error is encountered; the caller is
/// free to ignore this, since the error is already registered.
pub fn ensureNavValUpToDate(
    pt: Zcu.PerThread,
    nav_id: InternPool.Nav.Index,
    /// `null` is valid only for the "root" analysis, i.e. called from `Compilation.processOneJob`.
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    const anal_unit: AnalUnit = .wrap(.{ .nav_val = nav_id });
    const nav = ip.getNav(nav_id);

    log.debug("ensureNavValUpToDate {f}", .{zcu.fmtAnalUnit(anal_unit)});

    assert(!zcu.analysis_in_progress.contains(anal_unit));

    try zcu.ensureNavValAnalysisQueued(nav_id);

    // Note that if the unit is PO, we pessimistically assume that it *does* require re-analysis, to
    // ensure that the unit is definitely up-to-date when this function returns. This mechanism could
    // result in over-analysis if analysis occurs in a poor order; we do our best to avoid this by
    // carefully choosing which units to re-analyze. See `Zcu.findOutdatedToAnalyze`.

    const was_outdated = zcu.clearOutdatedState(anal_unit);

    const prev_failed = zcu.failed_analysis.contains(anal_unit) or
        zcu.transitive_failed_analysis.contains(anal_unit);

    if (was_outdated) {
        zcu.resetUnit(anal_unit);
    } else {
        // We can trust the current information about this unit.
        if (prev_failed) return error.AnalysisFail;
        assert(nav.resolved.?.value != .none);
        return;
    }

    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, anal_unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const unit_tracking = zcu.trackUnitSema(nav.fqn.toSlice(ip), nav.srcInst(ip));
    defer unit_tracking.end(zcu);

    const invalidate_value: bool, const new_failed: bool = if (pt.analyzeNavVal(nav_id, reason)) |result| res: {
        break :res .{
            // If the unit has gone from failed to success, we still need to invalidate the dependencies.
            result.val_changed or prev_failed,
            false,
        };
    } else |err| switch (err) {
        error.AnalysisFail => res: {
            if (!zcu.failed_analysis.contains(anal_unit)) {
                // If this unit caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, anal_unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(anal_unit)});
            }
            break :res .{ !prev_failed, true };
        },
        error.OutOfMemory => {
            // TODO: it's unclear how to gracefully handle this.
            // To report the error cleanly, we need to add a message to `failed_analysis` and a
            // corresponding entry to `retryable_failures`; but either of these things is quite
            // likely to OOM at this point.
            // If that happens, what do we do? Perhaps we could have a special field on `Zcu`
            // for reporting OOM errors without allocating.
            return error.OutOfMemory;
        },
        error.Canceled => |e| return e,
        error.ComptimeReturn => unreachable,
        error.ComptimeBreak => unreachable,
    };

    if (was_outdated) {
        const dependee: InternPool.Dependee = .{ .nav_val = nav_id };
        if (invalidate_value) {
            // This dependency was marked as PO, meaning dependees were waiting
            // on its analysis result, and it has turned out to be outdated.
            // Update dependees accordingly.
            try zcu.markDependeeOutdated(.marked_po, dependee);
        } else {
            // This dependency was previously PO, but turned out to be up-to-date.
            // We do not need to queue successive analysis.
            try zcu.markPoDependeeUpToDate(dependee);
        }
    }

    if (new_failed) return error.AnalysisFail;
}

fn analyzeNavVal(
    pt: Zcu.PerThread,
    nav_id: InternPool.Nav.Index,
    reason: ?*const Zcu.DependencyReason,
) Zcu.CompileError!struct { val_changed: bool } {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;

    const anal_unit: AnalUnit = .wrap(.{ .nav_val = nav_id });
    const old_nav = ip.getNav(nav_id);

    log.debug("analyzeNavVal {f}", .{zcu.fmtAnalUnit(anal_unit)});

    const inst_resolved = old_nav.analysis.?.zir_index.resolveFull(ip) orelse return error.AnalysisFail;
    const file = zcu.fileByIndex(inst_resolved.file);
    const zir = file.zir.?;
    const zir_decl = zir.getDeclaration(inst_resolved.inst);

    try zcu.analysis_in_progress.putNoClobber(gpa, anal_unit, reason);
    defer assert(zcu.analysis_in_progress.swapRemove(anal_unit));

    var analysis_arena: std.heap.ArenaAllocator = .init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace: std.array_list.Managed(Zcu.LazySrcLoc) = .init(gpa);
    defer comptime_err_ret_trace.deinit();

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = zir,
        .owner = anal_unit,
        .func_index = .none,
        .func_is_naked = false,
        .fn_ret_ty = .void,
        .fn_ret_ty_ies = null,
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    // Every `Nav` declares a dependency on the source of the corresponding declaration.
    try sema.declareDependency(.{ .src_hash = old_nav.analysis.?.zir_index });

    // In theory, we would also add a reference to the corresponding `nav_val` unit here: there are
    // always references in both directions between a `nav_val` and `nav_ty`. However, to save memory,
    // these references are known implicitly. See logic in `Zcu.resolveReferences`.

    var block: Sema.Block = .{
        .parent = null,
        .sema = &sema,
        .namespace = old_nav.analysis.?.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = undefined, // set below
        .src_base_inst = old_nav.analysis.?.zir_index,
        .type_name_ctx = old_nav.fqn,
    };
    defer block.instructions.deinit(gpa);

    const ty_src = block.src(.{ .node_offset_var_decl_ty = .zero });
    const init_src = block.src(.{ .node_offset_var_decl_init = .zero });
    const align_src = block.src(.{ .node_offset_var_decl_align = .zero });
    const section_src = block.src(.{ .node_offset_var_decl_section = .zero });
    const addrspace_src = block.src(.{ .node_offset_var_decl_addrspace = .zero });

    block.comptime_reason = .{ .reason = .{
        .src = init_src,
        .r = .{ .simple = .container_var_init },
    } };

    const maybe_ty: ?Type = if (zir_decl.type_body != null) ty: {
        // Since we have a type body, the type is resolved separately!
        try sema.ensureNavResolved(&block, init_src, nav_id, .type);
        break :ty .fromInterned(ip.getNav(nav_id).resolved.?.type);
    } else null;

    const final_val: ?Value = if (zir_decl.value_body) |value_body| val: {
        if (maybe_ty) |ty| {
            // Put the resolved type into `inst_map` to be used as the result type of the init.
            try sema.inst_map.ensureSpaceForInstructions(gpa, &.{inst_resolved.inst});
            sema.inst_map.putAssumeCapacity(inst_resolved.inst, Air.internedToRef(ty.toIntern()));
            const uncoerced_result_ref = try sema.resolveInlineBody(&block, value_body, inst_resolved.inst);
            assert(sema.inst_map.remove(inst_resolved.inst));

            const result_ref = try sema.coerce(&block, ty, uncoerced_result_ref, init_src);
            break :val try sema.resolveFinalDeclValue(&block, init_src, result_ref);
        } else {
            // Just analyze the value; we have no type to offer.
            const result_ref = try sema.resolveInlineBody(&block, value_body, inst_resolved.inst);
            break :val try sema.resolveFinalDeclValue(&block, init_src, result_ref);
        }
    } else null;

    const nav_ty: Type = maybe_ty orelse final_val.?.typeOf(zcu);

    const is_const = is_const: switch (zir_decl.kind) {
        .@"comptime" => unreachable, // this is not a Nav
        .unnamed_test, .@"test", .decltest => {
            assert(nav_ty.zigTypeTag(zcu) == .@"fn");
            break :is_const true;
        },
        .@"const" => true,
        .@"var" => {
            try sema.validateVarType(
                &block,
                if (zir_decl.type_body != null) ty_src else init_src,
                nav_ty,
                zir_decl.linkage == .@"extern",
            );
            break :is_const false;
        },
    };

    // Now that we know the type, we can evaluate the alignment, linksection, and addrspace, to determine
    // the full pointer type of this declaration.

    const modifiers: Sema.NavPtrModifiers = if (zir_decl.type_body != null) m: {
        // `analyzeNavType` (from the `ensureNavTypeUpToDate` call above) has already populated this data into
        // the `Nav`. Load the new one, and pull the modifiers out.
        const r = ip.getNav(nav_id).resolved.?;
        break :m .{
            .@"align" = r.@"align",
            .@"linksection" = r.@"linksection",
            .@"addrspace" = r.@"addrspace",
        };
    } else m: {
        // `analyzeNavType` is essentially a stub which calls us. We are responsible for resolving this data.
        break :m try sema.resolveNavPtrModifiers(&block, zir_decl, inst_resolved.inst, nav_ty);
    };

    // Lastly, we must figure out the actual interned value to store to the `Nav`.
    // This isn't necessarily the same as `final_val`!

    const nav_val: Value = switch (zir_decl.linkage) {
        .normal, .@"export" => final_val.?,
        .@"extern" => val: {
            assert(final_val == null); // extern decls do not have a value body
            const lib_name: ?[]const u8 = if (zir_decl.lib_name != .empty) l: {
                break :l zir.nullTerminatedString(zir_decl.lib_name);
            } else null;
            if (lib_name) |l| {
                const lib_name_src = block.src(.{ .node_offset_lib_name = .zero });
                try sema.handleExternLibName(&block, lib_name_src, l);
            }
            break :val .fromInterned(try pt.getExtern(.{
                .name = old_nav.name,
                .ty = nav_ty.toIntern(),
                .lib_name = try ip.getOrPutStringOpt(gpa, io, pt.tid, lib_name, .no_embedded_nulls),
                .is_threadlocal = zir_decl.is_threadlocal,
                .linkage = .strong,
                .visibility = .default,
                .is_dll_import = false,
                .relocation = .any,
                .decoration = null,
                .is_const = is_const,
                .alignment = modifiers.@"align",
                .@"addrspace" = modifiers.@"addrspace",
                .zir_index = old_nav.analysis.?.zir_index, // `declaration` instruction
                .owner_nav = undefined, // ignored by `getExtern`
                .source = .syntax,
            }));
        },
    };

    switch (nav_val.toIntern()) {
        .unreachable_value => unreachable, // assertion failure
        else => {},
    }

    // This resolves the type of the resolved value, not that value itself. If `nav_val` is a struct type,
    // this resolves the type `type` (which needs no resolution), not the struct itself.
    try sema.ensureLayoutResolved(nav_ty, block.nodeOffset(.zero), if (zir_decl.kind == .@"var") .variable else .constant);

    const queue_linker_work, const is_owned_fn = switch (ip.indexToKey(nav_val.toIntern())) {
        .func => |f| .{ true, f.owner_nav == nav_id }, // note that this lets function aliases reach codegen
        .@"extern" => .{ false, nav_ty.zigTypeTag(zcu) == .@"fn" and zir_decl.linkage == .@"extern" },
        else => .{ true, false },
    };

    if (is_owned_fn) {
        // linksection etc are legal, except some targets do not support function alignment.
        if (zir_decl.align_body != null and !target_util.supportsFunctionAlignment(zcu.getTarget())) {
            return sema.fail(&block, align_src, "target does not support function alignment", .{});
        }
    } else if (nav_ty.comptimeOnly(zcu)) {
        // alignment, linksection, addrspace annotations are not allowed for comptime-only types.
        const cannot_align_reason: []const u8 = switch (ip.indexToKey(nav_val.toIntern())) {
            .func => "function alias", // slightly clearer message, since you *can* specify these on function *declarations*
            else => "comptime-only type",
        };
        if (zir_decl.align_body != null) {
            return sema.fail(&block, align_src, "cannot specify alignment of {s}", .{cannot_align_reason});
        }
        if (zir_decl.linksection_body != null) {
            return sema.fail(&block, section_src, "cannot specify linksection of {s}", .{cannot_align_reason});
        }
        if (zir_decl.addrspace_body != null) {
            return sema.fail(&block, addrspace_src, "cannot specify addrspace of {s}", .{cannot_align_reason});
        }
    }

    // We're about to resolve the value of the Nav. This causes the information about what the value
    // was last update to be lost; therefore, if the `nav_ty` is currently out of date, it would
    // incorrectly think it was unchanged when eventually analyzed. To avoid this, we need to detect
    // that case and invalidate the dependee right now.
    if (zcu.clearOutdatedState(.wrap(.{ .nav_ty = nav_id }))) {
        assert(zir_decl.type_body == null); // otherwise we already resolved it with `Sema.ensureNavResolved`
        zcu.resetUnit(.wrap(.{ .nav_ty = nav_id }));
        try pt.addDependency(.wrap(.{ .nav_ty = nav_id }), .{ .nav_val = nav_id }); // inferred type depends on the value (that's us!)
        if (comp.debugIncremental()) {
            const info = try zcu.incremental_debug_state.getUnitInfo(gpa, .wrap(.{ .nav_ty = nav_id }));
            info.last_update_gen = zcu.generation;
            info.deps.clearRetainingCapacity();
        }
        const type_changed: bool = if (old_nav.resolved) |r| r.type != nav_ty.toIntern() else true;
        if (type_changed) {
            try zcu.markDependeeOutdated(.marked_po, .{ .nav_ty = nav_id });
        } else {
            try zcu.markPoDependeeUpToDate(.{ .nav_ty = nav_id });
        }
    }
    ip.resolveNav(io, nav_id, .{
        .type = nav_ty.toIntern(),
        .@"align" = modifiers.@"align",
        .@"linksection" = modifiers.@"linksection",
        .@"addrspace" = modifiers.@"addrspace",
        .@"const" = is_const,
        .@"threadlocal" = zir_decl.is_threadlocal,
        .is_extern_decl = zir_decl.linkage == .@"extern",
        .value = nav_val.toIntern(),
    });

    if (zir_decl.linkage == .@"export") {
        const export_src = block.src(.{ .token_offset = @enumFromInt(@intFromBool(zir_decl.is_pub)) });
        const name_slice = zir.nullTerminatedString(zir_decl.name);
        const name_ip = try ip.getOrPutString(gpa, io, pt.tid, name_slice, .no_embedded_nulls);
        try sema.analyzeExportSelfNav(&block, export_src, name_ip);
    }

    try sema.flushExports();

    if (queue_linker_work) {
        comp.link_prog_node.increaseEstimatedTotalItems(1);
        try comp.link_queue.enqueueZcu(comp, pt.tid, .{ .link_nav = nav_id });
    }

    if (comp.config.is_test and zcu.test_functions.contains(nav_id)) {
        // We just analyzed a test function's "value" (essentially its signature); now we need to
        // implicitly reference the function *body*. `Zcu.resolveReferences` knows about this rule,
        // so we don't need to mark an explicit reference, but we do need to make sure that the test
        // body will actually get analyzed!
        try zcu.ensureFuncBodyAnalysisQueued(nav_val.toIntern());
    }

    return if (old_nav.resolved) |old_resolved| .{
        .val_changed = old_resolved.value != nav_val.toIntern(),
    } else .{
        .val_changed = true,
    };
}

pub fn ensureNavTypeUpToDate(
    pt: Zcu.PerThread,
    nav_id: InternPool.Nav.Index,
    /// `null` is valid only for the "root" analysis, i.e. called from `Compilation.processOneJob`.
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    const anal_unit: AnalUnit = .wrap(.{ .nav_ty = nav_id });
    const nav = ip.getNav(nav_id);

    log.debug("ensureNavTypeUpToDate {f}", .{zcu.fmtAnalUnit(anal_unit)});

    assert(!zcu.analysis_in_progress.contains(anal_unit));

    try zcu.ensureNavValAnalysisQueued(nav_id);

    // Note that if the unit is PO, we pessimistically assume that it *does* require re-analysis, to
    // ensure that the unit is definitely up-to-date when this function returns. This mechanism could
    // result in over-analysis if analysis occurs in a poor order; we do our best to avoid this by
    // carefully choosing which units to re-analyze. See `Zcu.findOutdatedToAnalyze`.

    const was_outdated = zcu.clearOutdatedState(anal_unit);

    const prev_failed = zcu.failed_analysis.contains(anal_unit) or
        zcu.transitive_failed_analysis.contains(anal_unit);

    if (was_outdated) {
        zcu.resetUnit(anal_unit);
    } else {
        // We can trust the current information about this unit.
        if (prev_failed) return error.AnalysisFail;
        assert(nav.resolved != null);
        return;
    }

    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, anal_unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const unit_tracking = zcu.trackUnitSema(nav.fqn.toSlice(ip), nav.srcInst(ip));
    defer unit_tracking.end(zcu);

    const invalidate_type: bool, const new_failed: bool = if (pt.analyzeNavType(nav_id, reason)) |result| res: {
        break :res .{
            // If the unit has gone from failed to success, we still need to invalidate the dependencies.
            result.type_changed or prev_failed,
            false,
        };
    } else |err| switch (err) {
        error.AnalysisFail => res: {
            if (!zcu.failed_analysis.contains(anal_unit)) {
                // If this unit caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, anal_unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(anal_unit)});
            }
            break :res .{ !prev_failed, true };
        },
        error.OutOfMemory => {
            // TODO: it's unclear how to gracefully handle this.
            // To report the error cleanly, we need to add a message to `failed_analysis` and a
            // corresponding entry to `retryable_failures`; but either of these things is quite
            // likely to OOM at this point.
            // If that happens, what do we do? Perhaps we could have a special field on `Zcu`
            // for reporting OOM errors without allocating.
            return error.OutOfMemory;
        },
        error.Canceled => |e| return e,
        error.ComptimeReturn => unreachable,
        error.ComptimeBreak => unreachable,
    };

    if (was_outdated) {
        const dependee: InternPool.Dependee = .{ .nav_ty = nav_id };
        if (invalidate_type) {
            // This dependency was marked as PO, meaning dependees were waiting
            // on its analysis result, and it has turned out to be outdated.
            // Update dependees accordingly.
            try zcu.markDependeeOutdated(.marked_po, dependee);
        } else {
            // This dependency was previously PO, but turned out to be up-to-date.
            // We do not need to queue successive analysis.
            try zcu.markPoDependeeUpToDate(dependee);
        }
    }

    if (new_failed) return error.AnalysisFail;
}

fn analyzeNavType(
    pt: Zcu.PerThread,
    nav_id: InternPool.Nav.Index,
    reason: ?*const Zcu.DependencyReason,
) Zcu.CompileError!struct { type_changed: bool } {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const ip = &zcu.intern_pool;

    const anal_unit: AnalUnit = .wrap(.{ .nav_ty = nav_id });
    const old_nav = ip.getNav(nav_id);

    log.debug("analyzeNavType {f}", .{zcu.fmtAnalUnit(anal_unit)});

    const inst_resolved = old_nav.analysis.?.zir_index.resolveFull(ip) orelse return error.AnalysisFail;
    const file = zcu.fileByIndex(inst_resolved.file);
    const zir = file.zir.?;

    try zcu.analysis_in_progress.putNoClobber(gpa, anal_unit, reason);
    defer assert(zcu.analysis_in_progress.swapRemove(anal_unit));

    const zir_decl = zir.getDeclaration(inst_resolved.inst);

    var analysis_arena: std.heap.ArenaAllocator = .init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace: std.array_list.Managed(Zcu.LazySrcLoc) = .init(gpa);
    defer comptime_err_ret_trace.deinit();

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = zir,
        .owner = anal_unit,
        .func_index = .none,
        .func_is_naked = false,
        .fn_ret_ty = .void,
        .fn_ret_ty_ies = null,
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    // Every `Nav` declares a dependency on the source of the corresponding declaration.
    try sema.declareDependency(.{ .src_hash = old_nav.analysis.?.zir_index });

    // In theory, we would also add a reference to the corresponding `nav_val` unit here: there are
    // always references in both directions between a `nav_val` and `nav_ty`. However, to save memory,
    // these references are known implicitly. See logic in `Zcu.resolveReferences`.

    var block: Sema.Block = .{
        .parent = null,
        .sema = &sema,
        .namespace = old_nav.analysis.?.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = undefined, // set below
        .src_base_inst = old_nav.analysis.?.zir_index,
        .type_name_ctx = old_nav.fqn,
    };
    defer block.instructions.deinit(gpa);

    const ty_src = block.src(.{ .node_offset_var_decl_ty = .zero });
    const init_src = block.src(.{ .node_offset_var_decl_init = .zero });

    const type_body = zir_decl.type_body orelse {
        // There is no type annotation, so we just need to use the declaration's value.
        // If the value had already been re-analyzed, it would have resolved the `nav_ty` unit as
        // either outdated or up-to-date. So we know that `old_nav` does contain information from
        // the previous update. As such, after this call, we will be able to determine whether the
        // type changed.
        try sema.ensureNavResolved(&block, init_src, nav_id, .fully);
        const new = ip.getNav(nav_id).resolved.?;
        return if (old_nav.resolved) |old| .{
            .type_changed = old.type != new.type or
                old.@"align" != new.@"align" or
                old.@"linksection" != new.@"linksection" or
                old.@"addrspace" != new.@"addrspace" or
                old.@"const" != new.@"const" or
                old.@"threadlocal" != new.@"threadlocal" or
                old.is_extern_decl != new.is_extern_decl,
        } else .{ .type_changed = true };
    };

    block.comptime_reason = .{ .reason = .{
        .src = ty_src,
        .r = .{ .simple = .type },
    } };

    const resolved_ty: Type = ty: {
        const uncoerced_type_ref = try sema.resolveInlineBody(&block, type_body, inst_resolved.inst);
        const type_ref = try sema.coerce(&block, .type, uncoerced_type_ref, ty_src);
        break :ty .fromInterned(type_ref.toInterned().?);
    };

    try sema.ensureLayoutResolved(resolved_ty, block.nodeOffset(.zero), if (zir_decl.kind == .@"var") .variable else .constant);

    // In the case where the type is specified, this function is also responsible for resolving
    // the pointer modifiers, i.e. alignment, linksection, addrspace.
    const modifiers = try sema.resolveNavPtrModifiers(&block, zir_decl, inst_resolved.inst, resolved_ty);

    const is_const = switch (zir_decl.kind) {
        .@"comptime" => unreachable,
        .unnamed_test, .@"test", .decltest, .@"const" => true,
        .@"var" => false,
    };

    const is_extern_decl = zir_decl.linkage == .@"extern";

    // Now for the question of the day: are the type and modifiers the same as before? If they are,
    // then we should actually avoid calling `ip.resolveNav`. This is because `analyzeNavVal` will
    // later wanmt to look at the resolved *value* to figure out whether *that* has changed: if we
    // threw that data away now, it would have to assume the value *had* changed even if it actually
    // hadn't, which could spin off a bunch of unnecessary re-analysis! OTOH, if the type *has*
    // changed, then we obviously know that the value will also have changed, so resetting the value
    // to `.none` is fine in that case.
    const changed: bool = if (old_nav.resolved) |old| changed: {
        break :changed old.type != resolved_ty.toIntern() or
            old.@"align" != modifiers.@"align" or
            old.@"linksection" != modifiers.@"linksection" or
            old.@"addrspace" != modifiers.@"addrspace" or
            old.@"const" != is_const or
            old.@"threadlocal" != zir_decl.is_threadlocal or
            old.is_extern_decl != is_extern_decl;
    } else true;

    if (!changed) return .{ .type_changed = false };

    ip.resolveNav(io, nav_id, .{
        .type = resolved_ty.toIntern(),
        .@"align" = modifiers.@"align",
        .@"linksection" = modifiers.@"linksection",
        .@"addrspace" = modifiers.@"addrspace",
        .@"const" = is_const,
        .@"threadlocal" = zir_decl.is_threadlocal,
        .is_extern_decl = is_extern_decl,
        .value = .none,
    });

    return .{ .type_changed = true };
}

/// If `func_index` is not a runtime function (e.g. it has a comptime-only parameter type) then it
/// is still valid to call this function and use its `func_body` unit in general---analysis of the
/// runtime function body will simply fail.
pub fn ensureFuncBodyUpToDate(
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    /// `null` is valid only for the "root" analysis, i.e. called from `Compilation.processOneJob`.
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!void {
    dev.check(.sema);

    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    const anal_unit: AnalUnit = .wrap(.{ .func = func_index });

    log.debug("ensureFuncBodyUpToDate {f}", .{zcu.fmtAnalUnit(anal_unit)});

    assert(!zcu.analysis_in_progress.contains(anal_unit));

    const func = zcu.funcInfo(func_index);

    assert(func.ty == func.uncoerced_ty); // analyze the body of the original function, not a coerced one

    const was_outdated = zcu.clearOutdatedState(anal_unit) or
        ip.setWantRuntimeFnAnalysis(zcu.comp.io, func_index);

    const prev_failed = zcu.failed_analysis.contains(anal_unit) or zcu.transitive_failed_analysis.contains(anal_unit);

    if (was_outdated) {
        zcu.resetUnit(anal_unit);
    } else {
        // We can trust the current information about this function.
        if (prev_failed) return error.AnalysisFail;
        return;
    }

    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, anal_unit);
        info.last_update_gen = zcu.generation;
        info.deps.clearRetainingCapacity();
    }

    const owner_nav = ip.getNav(func.owner_nav);
    const unit_tracking = zcu.trackUnitSema(
        owner_nav.fqn.toSlice(ip),
        owner_nav.srcInst(ip),
    );
    defer unit_tracking.end(zcu);

    const ies_outdated, const new_failed = if (pt.analyzeFuncBody(func_index, reason)) |result|
        .{ prev_failed or result.ies_outdated, false }
    else |err| switch (err) {
        error.AnalysisFail => res: {
            if (!zcu.failed_analysis.contains(anal_unit)) {
                // If this function caused the error, it would have an entry in `failed_analysis`.
                // Since it does not, this must be a transitive failure.
                try zcu.transitive_failed_analysis.put(gpa, anal_unit, {});
                log.debug("mark transitive analysis failure for {f}", .{zcu.fmtAnalUnit(anal_unit)});
            }
            // We consider the IES to be outdated if the function previously succeeded analysis; in this case,
            // we need to re-analyze dependants to ensure they hit a transitive error here, rather than reporting
            // a different error later (which may now be invalid).
            break :res .{ !prev_failed, true };
        },
        error.OutOfMemory => {
            // TODO: it's unclear how to gracefully handle this.
            // To report the error cleanly, we need to add a message to `failed_analysis` and a
            // corresponding entry to `retryable_failures`; but either of these things is quite
            // likely to OOM at this point.
            // If that happens, what do we do? Perhaps we could have a special field on `Zcu`
            // for reporting OOM errors without allocating.
            return error.OutOfMemory;
        },
        error.Canceled => |e| return e,
    };

    if (was_outdated) {
        if (ies_outdated) {
            try zcu.markDependeeOutdated(.marked_po, .{ .func_ies = func_index });
        } else {
            try zcu.markPoDependeeUpToDate(.{ .func_ies = func_index });
        }
    }

    if (new_failed) return error.AnalysisFail;
}

fn analyzeFuncBody(
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!struct { ies_outdated: bool } {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    const func = zcu.funcInfo(func_index);
    const anal_unit = AnalUnit.wrap(.{ .func = func_index });

    // We'll want to remember what the IES used to be before the update for
    // dependency invalidation purposes.
    const old_resolved_ies = if (func.analysisUnordered(ip).inferred_error_set)
        func.resolvedErrorSetUnordered(ip)
    else
        .none;

    log.debug("analyze and generate fn body {f}", .{zcu.fmtAnalUnit(anal_unit)});

    var air = try pt.analyzeFuncBodyInner(func_index, reason);
    var air_owned = true;
    defer if (air_owned) air.deinit(gpa);

    const ies_outdated = !func.analysisUnordered(ip).inferred_error_set or
        func.resolvedErrorSetUnordered(ip) != old_resolved_ies;

    const comp = zcu.comp;

    const dump_air = build_options.enable_debug_extensions and comp.verbose_air;
    const dump_llvm_ir = build_options.enable_debug_extensions and (comp.verbose_llvm_ir != null or comp.verbose_llvm_bc != null);

    if (comp.bin_file != null or zcu.llvm_object != null or dump_air or dump_llvm_ir) {
        zcu.codegen_prog_node.increaseEstimatedTotalItems(1);
        comp.link_prog_node.increaseEstimatedTotalItems(1);

        // Some linkers need to refer to the AIR. In that case, the linker is not running
        // concurrently, so we'll just keep ownership of the AIR for ourselves instead of
        // letting the codegen job destroy it.
        const disown_air = zcu.backendSupportsFeature(.separate_thread);

        // Begin the codegen task. If the codegen/link queue is backed up, this might
        // block until the linker is able to process some tasks.
        const codegen_task = try zcu.codegen_task_pool.start(zcu, func_index, &air, disown_air);
        if (disown_air) air_owned = false;

        try comp.link_queue.enqueueZcu(comp, pt.tid, .{ .link_func = codegen_task });
    }

    return .{ .ies_outdated = ies_outdated };
}

/// The given file has been modified on this incremental update, so if it has a populated root
/// struct type, either re-scan its namespace, or clear it and invalidate dependencies if the
/// type is no longer valid. See comments in body for more details.
///
/// Called by `updateZirRefs` for all updated Zig source files before the main update loop.
///
/// Asserts that the file has successfully populated ZIR.
fn updateFileRootStructType(pt: Zcu.PerThread, file_index: Zcu.File.Index) Allocator.Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    const file = zcu.fileByIndex(file_index);
    const file_root_type = zcu.fileRootType(file_index);
    if (file_root_type == .none) {
        // We haven't analyzed any `@import` of this file so far, so there's nothing to update. If
        // an `@import` gets analyzed, then `ensureFilePopulated` will create the root struct type
        // and scan the namespace.
        return;
    }

    const loaded_struct = ip.loadStructType(file_root_type);

    log.debug("updateFileRootStructType mod={s} sub_file_path={s}", .{
        file.mod.?.fully_qualified_name,
        file.sub_file_path,
    });

    if (loaded_struct.zir_index.resolve(ip) == null) {
        // The file's root struct decl has been lost, so a new struct type must be interned at a new
        // `InternPool.Index`. Clear the file's root type so that `ensureFilePopulated` will do that
        // work, and invalidate dependencies on this file to force re-analysis of `@import` sites.
        zcu.setFileRootType(file_index, .none);
        try zcu.markDependeeOutdated(.not_marked_po, .{ .source_file = file_index });
    } else {
        // The existing struct type is valid, but the namespace contents might have changed. For
        // most struct types, that would cause the surrounding declaration to be invalidated which
        // causes `Sema.zirStructType` (or whatever) to call `ensureNamespaceUpToDate`. However,
        // there is no "surrounding declaration" for the root struct type of a Zig source file, so
        // update this namespace now.
        const decls = file.zir.?.getStructDecl(.main_struct_inst).decls;
        try pt.scanNamespace(loaded_struct.namespace, decls);
        zcu.namespacePtr(loaded_struct.namespace).generation = zcu.generation;
    }
}

/// Called by AstGen worker threads when an import is seen. If `new_file` is returned, the caller is
/// then responsible for queueing a new AstGen job for the new file.
/// Assumes that `comp.mutex` is NOT locked. It will be locked by this function where necessary.
pub fn discoverImport(
    pt: Zcu.PerThread,
    importer_path: Compilation.Path,
    import_string: []const u8,
) Allocator.Error!union(enum) {
    module,
    existing_file: Zcu.File.Index,
    new_file: struct {
        index: Zcu.File.Index,
        file: *Zcu.File,
    },
} {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;

    if (!mem.endsWith(u8, import_string, ".zig") and !mem.endsWith(u8, import_string, ".zon")) {
        return .module;
    }

    const new_path = try importer_path.upJoin(gpa, zcu.comp.dirs, import_string);
    errdefer new_path.deinit(gpa);

    // We're about to do a GOP on `import_table`, so we need the mutex.
    comp.mutex.lockUncancelable(io);
    defer comp.mutex.unlock(io);

    const gop = try zcu.import_table.getOrPutAdapted(gpa, new_path, Zcu.ImportTableAdapter{ .zcu = zcu });
    errdefer _ = zcu.import_table.pop();
    if (gop.found_existing) {
        new_path.deinit(gpa); // we didn't need it for `File.path`
        return .{ .existing_file = gop.key_ptr.* };
    }

    zcu.import_table.lockPointers();
    defer zcu.import_table.unlockPointers();

    const new_file = try gpa.create(Zcu.File);
    errdefer gpa.destroy(new_file);

    const new_file_index = try zcu.intern_pool.createFile(gpa, io, pt.tid, .{
        .bin_digest = new_path.digest(),
        .file = new_file,
        .root_type = .none,
    });
    errdefer comptime unreachable; // because we don't remove the file from the internpool

    gop.key_ptr.* = new_file_index;
    new_file.* = .{
        .status = .never_loaded,
        .path = new_path,
        .stat = undefined,
        .is_builtin = false,
        .source = null,
        .tree = null,
        .zir = null,
        .zoir = null,
        .mod = null,
        .sub_file_path = undefined,
        .module_changed = false,
        .prev_zir = null,
        .zoir_invalidated = false,
    };

    return .{ .new_file = .{
        .index = new_file_index,
        .file = new_file,
    } };
}

pub fn doImport(
    pt: Zcu.PerThread,
    /// This file must have its `mod` populated.
    importer: *Zcu.File,
    import_string: []const u8,
) error{
    OutOfMemory,
    ModuleNotFound,
    IllegalZigImport,
}!struct {
    file: Zcu.File.Index,
    module_root: ?*Module,
} {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const imported_mod: ?*Module = m: {
        if (mem.eql(u8, import_string, "std")) break :m zcu.std_mod;
        if (mem.eql(u8, import_string, "root")) break :m zcu.root_mod;
        if (mem.eql(u8, import_string, "builtin")) {
            const opts = importer.mod.?.getBuiltinOptions(zcu.comp.config);
            break :m zcu.builtin_modules.get(opts.hash()).?;
        }
        break :m importer.mod.?.deps.get(import_string);
    };
    if (imported_mod) |mod| {
        if (zcu.module_roots.get(mod).?.unwrap()) |file_index| {
            return .{
                .file = file_index,
                .module_root = mod,
            };
        }
    }
    if (!std.mem.endsWith(u8, import_string, ".zig") and
        !std.mem.endsWith(u8, import_string, ".zon"))
    {
        return error.ModuleNotFound;
    }
    const path = try importer.path.upJoin(gpa, zcu.comp.dirs, import_string);
    defer path.deinit(gpa);
    if (try path.isIllegalZigImport(gpa, zcu.comp.dirs)) {
        return error.IllegalZigImport;
    }
    return .{
        .file = zcu.import_table.getKeyAdapted(path, Zcu.ImportTableAdapter{ .zcu = zcu }).?,
        .module_root = null,
    };
}
/// This is called once during `Compilation.create` and never again. "builtin" modules don't yet
/// exist, so are not added to `module_roots` here. They must be added when they are created.
pub fn populateModuleRootTable(pt: Zcu.PerThread) error{
    OutOfMemory,
    /// One of the specified modules had its root source file at an illegal path.
    IllegalZigImport,
}!void {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;

    // We'll initially add [mod, undefined] pairs, and when we reach the pair while
    // iterating, rewrite the undefined value.
    const roots = &zcu.module_roots;
    roots.clearRetainingCapacity();

    // Start with:
    // * `std_mod`, which is the main root of analysis
    // * `root_mod`, which is `@import("root")`
    // * `main_mod`, which is a special analysis root in tests (and otherwise equal to `root_mod`)
    // All other modules will be found by traversing their dependency tables.
    try roots.ensureTotalCapacity(gpa, 3);
    roots.putAssumeCapacity(zcu.std_mod, undefined);
    roots.putAssumeCapacity(zcu.root_mod, undefined);
    roots.putAssumeCapacity(zcu.main_mod, undefined);
    var i: usize = 0;
    while (i < roots.count()) {
        const mod = roots.keys()[i];
        try roots.ensureUnusedCapacity(gpa, mod.deps.count());
        for (mod.deps.values()) |dep| {
            const gop = roots.getOrPutAssumeCapacity(dep);
            _ = gop; // we want to leave the value undefined if it was added
        }

        const root_file_out = &roots.values()[i];
        roots.lockPointers();
        defer roots.unlockPointers();

        i += 1;

        if (Zcu.File.modeFromPath(mod.root_src_path) == null) {
            root_file_out.* = .none;
            continue;
        }

        const path = try mod.root.join(gpa, zcu.comp.dirs, mod.root_src_path);
        errdefer path.deinit(gpa);

        if (try path.isIllegalZigImport(gpa, zcu.comp.dirs)) {
            return error.IllegalZigImport;
        }

        const gop = try zcu.import_table.getOrPutAdapted(gpa, path, Zcu.ImportTableAdapter{ .zcu = zcu });
        errdefer _ = zcu.import_table.pop();

        if (gop.found_existing) {
            path.deinit(gpa);
            root_file_out.* = gop.key_ptr.*.toOptional();
            continue;
        }

        zcu.import_table.lockPointers();
        defer zcu.import_table.unlockPointers();

        const new_file = try gpa.create(Zcu.File);
        errdefer gpa.destroy(new_file);

        const new_file_index = try zcu.intern_pool.createFile(gpa, io, pt.tid, .{
            .bin_digest = path.digest(),
            .file = new_file,
            .root_type = .none,
        });
        errdefer comptime unreachable; // because we don't remove the file from the internpool

        gop.key_ptr.* = new_file_index;
        root_file_out.* = new_file_index.toOptional();
        new_file.* = .{
            .status = .never_loaded,
            .path = path,
            .stat = undefined,
            .is_builtin = false,
            .source = null,
            .tree = null,
            .zir = null,
            .zoir = null,
            .mod = null,
            .sub_file_path = undefined,
            .module_changed = false,
            .prev_zir = null,
            .zoir_invalidated = false,
        };
    }
}

/// Clears and re-populates `pt.zcu.alive_files`, and determines the module identity of every alive
/// file. If a file's module changes, its `module_changed` flag is set for `updateZirRefs` to see.
/// Also clears and re-populates `failed_imports` and `multi_module_err` based on the set of alive
/// files.
///
/// Live files are also added as file system inputs if necessary.
///
/// Returns whether there is any live file which is failed. Howewver, this function does *not*
/// modify `pt.zcu.skip_analysis_this_update`.
///
/// If an error is returned, `pt.zcu.alive_files` might contain undefined values.
fn computeAliveFiles(pt: Zcu.PerThread) Allocator.Error!bool {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = zcu.gpa;

    var any_fatal_files = false;
    zcu.multi_module_err = null;
    zcu.failed_imports.clearRetainingCapacity();
    zcu.alive_files.clearRetainingCapacity();

    // This function will iterate the keys of `alive_files`, adding new entries as it discovers
    // imports. Once a file is in `alive_files`, it has its `mod` field up-to-date. If conflicting
    // imports are discovered for a file, we will set `multi_module_err`. Crucially, this traversal
    // is single-threaded, and depends only on the order of the imports map from AstGen, which makes
    // its behavior (in terms of which multi module errors are discovered) entirely consistent in a
    // multi-threaded environment (where things like file indices could differ between compiler runs).

    // The roots of our file liveness analysis will be the analysis roots.
    const analysis_roots = zcu.analysisRoots();
    try zcu.alive_files.ensureTotalCapacity(gpa, analysis_roots.len);
    for (analysis_roots) |mod| {
        const file_index = zcu.module_roots.get(mod).?.unwrap() orelse continue;
        const file = zcu.fileByIndex(file_index);

        file.mod = mod;
        file.sub_file_path = mod.root_src_path;

        zcu.alive_files.putAssumeCapacityNoClobber(file_index, .{ .analysis_root = mod });
    }

    var live_check_idx: usize = 0;
    while (live_check_idx < zcu.alive_files.count()) {
        const file_idx = zcu.alive_files.keys()[live_check_idx];
        const file = zcu.fileByIndex(file_idx);
        live_check_idx += 1;

        switch (file.status) {
            .never_loaded => unreachable, // everything reachable is loaded by the AstGen workers
            .retryable_failure, .astgen_failure => any_fatal_files = true,
            .success => {},
        }

        try comp.appendFileSystemInput(file.path);

        switch (file.getMode()) {
            .zig => {}, // continue to logic below
            .zon => continue, // ZON can't import anything
        }

        if (file.status != .success) continue; // ZIR not valid if there was a file failure

        const zir = file.zir.?;
        const imports_index = zir.extra[@intFromEnum(Zir.ExtraIndex.imports)];
        if (imports_index == 0) continue; // this Zig file has no imports
        const extra = zir.extraData(Zir.Inst.Imports, imports_index);
        var extra_index = extra.end;
        try zcu.alive_files.ensureUnusedCapacity(gpa, extra.data.imports_len);
        for (0..extra.data.imports_len) |_| {
            const item = zir.extraData(Zir.Inst.Imports.Item, extra_index);
            extra_index = item.end;
            const import_path = zir.nullTerminatedString(item.data.name);

            if (std.mem.eql(u8, import_path, "builtin")) {
                // We've not necessarily generated builtin modules yet, so `doImport` could fail. Instead,
                // create the module here. Then, since we know that `builtin.zig` doesn't have an error and
                // has no imports other than 'std', we can just continue onto the next import.
                try pt.updateBuiltinModule(file.mod.?.getBuiltinOptions(comp.config));
                continue;
            }

            const res = pt.doImport(file, import_path) catch |err| switch (err) {
                error.OutOfMemory => |e| return e,
                error.ModuleNotFound => {
                    // It'd be nice if this were a file-level error, but allowing this turns out to
                    // be quite important in practice, e.g. for optional dependencies whose import
                    // is behind a comptime condition. So, the error here happens in `Sema` instead.
                    continue;
                },
                error.IllegalZigImport => {
                    try zcu.failed_imports.append(gpa, .{
                        .file_index = file_idx,
                        .import_string = item.data.name,
                        .import_token = item.data.token,
                        .kind = .illegal_zig_import,
                    });
                    continue;
                },
            };

            // If the import was not of a module, we propagate our own module.
            const imported_mod = res.module_root orelse file.mod.?;
            const imported_file = zcu.fileByIndex(res.file);

            const imported_ref: Zcu.File.Reference = .{ .import = .{
                .importer = file_idx,
                .tok = item.data.token,
                .module = res.module_root,
            } };

            const gop = zcu.alive_files.getOrPutAssumeCapacity(res.file);
            if (gop.found_existing) {
                // This means `imported_file.mod` is already populated. If it doesn't match
                // `imported_mod`, then this file exists in multiple modules.
                if (imported_file.mod.? != imported_mod) {
                    // We only report the first multi-module error we see. Thanks to this traversal
                    // being deterministic, this doesn't raise consistency issues. Moreover, it's a
                    // useful behavior; we know that this error can be reached *without* realising
                    // that any other files are multi-module, so it's probably approximately where
                    // the problem "begins". Any compilation with a multi-module file is likely to
                    // have a huge number of them by transitive imports, so just reporting this one
                    // hopefully keeps the error focused.
                    zcu.multi_module_err = .{
                        .file = file_idx,
                        .modules = .{ imported_file.mod.?, imported_mod },
                        .refs = .{ gop.value_ptr.*, imported_ref },
                    };
                    // If we discover a multi-module error, it's the only error which matters, and we
                    // can't discern any useful information about the file's own imports; so just do
                    // an early exit now we've populated `zcu.multi_module_err`.
                    return any_fatal_files;
                }
                continue;
            }
            // We're the first thing we've found referencing `res.file`.
            gop.value_ptr.* = imported_ref;
            if (imported_file.mod) |m| {
                if (m == imported_mod) {
                    // Great, the module and sub path are already populated correctly.
                    continue;
                }
            }
            // We need to set the file's module, meaning we also need to compute its sub path.
            // This string is externally managed and has a lifetime at least equal to the
            // lifetime of `imported_file`. `null` means the file is outside its module root.
            switch (imported_file.path.isNested(imported_mod.root)) {
                .yes => |sub_path| {
                    if (imported_file.mod != null) {
                        // There was a module from a previous update; instruct `updateZirRefs` to
                        // invalidate everything.
                        imported_file.module_changed = true;
                    }
                    imported_file.mod = imported_mod;
                    imported_file.sub_file_path = sub_path;
                },
                .different_roots, .no => {
                    try zcu.failed_imports.append(gpa, .{
                        .file_index = file_idx,
                        .import_string = item.data.name,
                        .import_token = item.data.token,
                        .kind = .file_outside_module_root,
                    });
                    _ = zcu.alive_files.pop(); // we failed to populate `mod`/`sub_file_path`
                },
            }
        }
    }

    return any_fatal_files;
}

/// Ensures that the `@import("builtin")` module corresponding to `opts` is available in
/// `builtin_modules`, and that its file is populated. Also ensures the file on disk is
/// up-to-date, setting a misc failure if updating it fails.
/// Asserts that the imported `builtin.zig` has no ZIR errors, and that it has only one
/// import, which is 'std'.
pub fn updateBuiltinModule(pt: Zcu.PerThread, opts: Builtin) Allocator.Error!void {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;

    const gop = try zcu.builtin_modules.getOrPut(gpa, opts.hash());
    if (gop.found_existing) return; // the `File` is up-to-date
    errdefer _ = zcu.builtin_modules.pop();

    const mod: *Module = try .createBuiltin(comp.arena, opts, comp.dirs);
    assert(std.mem.eql(u8, &mod.getBuiltinOptions(comp.config).hash(), gop.key_ptr)); // builtin is its own builtin

    const path = try mod.root.join(gpa, comp.dirs, "builtin.zig");
    errdefer path.deinit(gpa);

    const file_gop = try zcu.import_table.getOrPutAdapted(gpa, path, Zcu.ImportTableAdapter{ .zcu = zcu });
    // `Compilation.Path.isIllegalZigImport` checks guard file creation, so
    // there isn't an `import_table` entry for this path yet.
    assert(!file_gop.found_existing);
    errdefer _ = zcu.import_table.pop();

    try zcu.module_roots.ensureUnusedCapacity(gpa, 1);

    const file = try gpa.create(Zcu.File);
    errdefer gpa.destroy(file);

    file.* = .{
        .status = .never_loaded,
        .stat = undefined,
        .path = path,
        .is_builtin = true,
        .source = null,
        .tree = null,
        .zir = null,
        .zoir = null,
        .mod = mod,
        .sub_file_path = "builtin.zig",
        .module_changed = false,
        .prev_zir = null,
        .zoir_invalidated = false,
    };

    const file_index = try zcu.intern_pool.createFile(gpa, io, pt.tid, .{
        .bin_digest = path.digest(),
        .file = file,
        .root_type = .none,
    });

    gop.value_ptr.* = mod;
    file_gop.key_ptr.* = file_index;
    zcu.module_roots.putAssumeCapacityNoClobber(mod, file_index.toOptional());
    try opts.populateFile(gpa, file);

    assert(file.status == .success);
    assert(!file.zir.?.hasCompileErrors());
    {
        // Check that it has only one import, which is 'std'.
        const imports_idx = file.zir.?.extra[@intFromEnum(Zir.ExtraIndex.imports)];
        assert(imports_idx != 0); // there is an import
        const extra = file.zir.?.extraData(Zir.Inst.Imports, imports_idx);
        assert(extra.data.imports_len == 1); // there is exactly one import
        const item = file.zir.?.extraData(Zir.Inst.Imports.Item, extra.end);
        const import_path = file.zir.?.nullTerminatedString(item.data.name);
        assert(mem.eql(u8, import_path, "std")); // the single import is of 'std'
    }

    Builtin.updateFileOnDisk(file, comp) catch |err| comp.setMiscFailure(
        .write_builtin_zig,
        "unable to write '{f}': {s}",
        .{ file.path.fmt(comp), @errorName(err) },
    );
}

pub fn embedFile(
    pt: Zcu.PerThread,
    cur_file: *Zcu.File,
    import_string: []const u8,
) error{
    OutOfMemory,
    Canceled,
    ImportOutsideModulePath,
}!Zcu.EmbedFile.Index {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    const opt_mod: ?*Module = m: {
        if (mem.eql(u8, import_string, "std")) break :m zcu.std_mod;
        if (mem.eql(u8, import_string, "root")) break :m zcu.root_mod;
        if (mem.eql(u8, import_string, "builtin")) {
            const opts = cur_file.mod.?.getBuiltinOptions(zcu.comp.config);
            break :m zcu.builtin_modules.get(opts.hash()).?;
        }
        break :m cur_file.mod.?.deps.get(import_string);
    };
    if (opt_mod) |mod| {
        const path = try mod.root.join(gpa, zcu.comp.dirs, mod.root_src_path);
        errdefer path.deinit(gpa);

        const gop = try zcu.embed_table.getOrPutAdapted(gpa, path, Zcu.EmbedTableAdapter{});
        if (gop.found_existing) {
            path.deinit(gpa); // we're not using this key
            return @enumFromInt(gop.index);
        }
        errdefer _ = zcu.embed_table.pop();
        gop.key_ptr.* = try pt.newEmbedFile(path);
        return @enumFromInt(gop.index);
    }

    const embed_file: *Zcu.EmbedFile, const embed_file_idx: Zcu.EmbedFile.Index = ef: {
        const path = try cur_file.path.upJoin(gpa, zcu.comp.dirs, import_string);
        errdefer path.deinit(gpa);
        const gop = try zcu.embed_table.getOrPutAdapted(gpa, path, Zcu.EmbedTableAdapter{});
        if (gop.found_existing) {
            path.deinit(gpa); // we're not using this key
            break :ef .{ gop.key_ptr.*, @enumFromInt(gop.index) };
        } else {
            errdefer _ = zcu.embed_table.pop();
            gop.key_ptr.* = try pt.newEmbedFile(path);
            break :ef .{ gop.key_ptr.*, @enumFromInt(gop.index) };
        }
    };

    switch (embed_file.path.isNested(cur_file.mod.?.root)) {
        .yes => {},
        .different_roots, .no => return error.ImportOutsideModulePath,
    }

    return embed_file_idx;
}

pub fn updateEmbedFile(
    pt: Zcu.PerThread,
    ef: *Zcu.EmbedFile,
    /// If not `null`, the interned file data is stored here, if it was loaded.
    /// `newEmbedFile` uses this to add the file to the `whole` cache manifest.
    ip_str_out: ?*?InternPool.String,
) Allocator.Error!void {
    pt.updateEmbedFileInner(ef, ip_str_out) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |e| {
            ef.val = .none;
            ef.err = e;
            ef.stat = undefined;
        },
    };
}

fn updateEmbedFileInner(
    pt: Zcu.PerThread,
    ef: *Zcu.EmbedFile,
    ip_str_out: ?*?InternPool.String,
) !void {
    const tid = pt.tid;
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const io = zcu.comp.io;
    const ip = &zcu.intern_pool;

    var file = f: {
        const dir, const sub_path = ef.path.openInfo(zcu.comp.dirs);
        break :f try dir.openFile(io, sub_path, .{});
    };
    defer file.close(io);

    const stat: Cache.File.Stat = .fromFs(try file.stat(io));

    if (ef.val != .none) {
        const old_stat = ef.stat;
        const unchanged_metadata =
            stat.size == old_stat.size and
            stat.mtime.nanoseconds == old_stat.mtime.nanoseconds and
            stat.inode == old_stat.inode;
        if (unchanged_metadata) return;
    }

    const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;
    const size_plus_one = std.math.add(usize, size, 1) catch return error.FileTooBig;

    // The loaded bytes of the file, including a sentinel 0 byte.
    const ip_str: InternPool.String = str: {
        const string_bytes = ip.getLocal(tid).getMutableStringBytes(gpa, io);
        const old_len = string_bytes.mutate.len;
        errdefer string_bytes.shrinkRetainingCapacity(old_len);
        const bytes = (try string_bytes.addManyAsSlice(size_plus_one))[0];
        var fr = file.reader(io, &.{});
        fr.size = stat.size;
        fr.interface.readSliceAll(bytes[0..size]) catch |err| switch (err) {
            error.ReadFailed => return fr.err.?,
            error.EndOfStream => return error.UnexpectedEof,
        };
        bytes[size] = 0;
        break :str try ip.getOrPutTrailingString(gpa, io, tid, @intCast(bytes.len), .maybe_embedded_nulls);
    };
    if (ip_str_out) |p| p.* = ip_str;

    const array_ty = try pt.arrayType(.{
        .len = size,
        .sentinel = .zero_u8,
        .child = .u8_type,
    });
    const ptr_ty = try pt.singleConstPtrType(array_ty);

    const array_val = try pt.intern(.{ .aggregate = .{
        .ty = array_ty.toIntern(),
        .storage = .{ .bytes = ip_str },
    } });
    const ptr_val = try pt.intern(.{ .ptr = .{
        .ty = ptr_ty.toIntern(),
        .base_addr = .{ .uav = .{
            .val = array_val,
            .orig_ty = ptr_ty.toIntern(),
        } },
        .byte_offset = 0,
    } });

    ef.val = ptr_val;
    ef.err = null;
    ef.stat = stat;
}

/// Assumes that `path` is allocated into `gpa`. Takes ownership of `path` on success.
fn newEmbedFile(
    pt: Zcu.PerThread,
    path: Compilation.Path,
) !*Zcu.EmbedFile {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    const new_file = try gpa.create(Zcu.EmbedFile);
    errdefer gpa.destroy(new_file);

    new_file.* = .{
        .path = path,
        .val = .none,
        .err = null,
        .stat = undefined,
    };

    var opt_ip_str: ?InternPool.String = null;
    try pt.updateEmbedFile(new_file, &opt_ip_str);

    try comp.appendFileSystemInput(path);

    // Add the file contents to the `whole` cache manifest if necessary.
    cache: {
        const whole = switch (zcu.comp.cache_use) {
            .whole => |whole| whole,
            .incremental, .none => break :cache,
        };
        const man = whole.cache_manifest orelse break :cache;
        const ip_str = opt_ip_str orelse break :cache; // this will be a compile error

        const array_len = Value.fromInterned(new_file.val).typeOf(zcu).childType(zcu).arrayLen(zcu);
        const contents = ip_str.toSlice(array_len, ip);

        const path_str = try path.toAbsolute(comp.dirs, gpa);
        defer gpa.free(path_str);

        try whole.cache_manifest_mutex.lock(io);
        defer whole.cache_manifest_mutex.unlock(io);

        try man.addFilePostContents(path_str, contents, new_file.stat);
    }

    return new_file;
}

pub fn scanNamespace(
    pt: Zcu.PerThread,
    namespace_index: Zcu.Namespace.Index,
    decls: []const Zir.Inst.Index,
) Allocator.Error!void {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.gpa;
    const namespace = zcu.namespacePtr(namespace_index);

    const tracked_unit = zcu.trackUnitSema(
        Type.fromInterned(namespace.owner_type).containerTypeName(ip).toSlice(ip),
        null,
    );
    defer tracked_unit.end(zcu);

    // For incremental updates, `scanDecl` wants to look up existing decls by their ZIR index rather
    // than their name. We'll build an efficient mapping now, then discard the current `decls`.
    // We map to the `AnalUnit`, since not every declaration has a `Nav`.
    var existing_by_inst: std.AutoHashMapUnmanaged(InternPool.TrackedInst.Index, InternPool.AnalUnit) = .empty;
    defer existing_by_inst.deinit(gpa);

    try existing_by_inst.ensureTotalCapacity(gpa, @intCast(
        namespace.pub_decls.count() + namespace.priv_decls.count() +
            namespace.comptime_decls.items.len +
            namespace.test_decls.items.len,
    ));

    for (namespace.pub_decls.keys()) |nav| {
        const zir_index = ip.getNav(nav).analysis.?.zir_index;
        existing_by_inst.putAssumeCapacityNoClobber(zir_index, .wrap(.{ .nav_val = nav }));
    }
    for (namespace.priv_decls.keys()) |nav| {
        const zir_index = ip.getNav(nav).analysis.?.zir_index;
        existing_by_inst.putAssumeCapacityNoClobber(zir_index, .wrap(.{ .nav_val = nav }));
    }
    for (namespace.comptime_decls.items) |cu| {
        const zir_index = ip.getComptimeUnit(cu).zir_index;
        existing_by_inst.putAssumeCapacityNoClobber(zir_index, .wrap(.{ .@"comptime" = cu }));
    }
    for (namespace.test_decls.items) |nav| {
        const zir_index = ip.getNav(nav).analysis.?.zir_index;
        existing_by_inst.putAssumeCapacityNoClobber(zir_index, .wrap(.{ .nav_val = nav }));
        // This test will be re-added to `test_functions` later on if it's still alive. Remove it for now.
        _ = zcu.test_functions.swapRemove(nav);
    }

    var seen_decls: std.AutoHashMapUnmanaged(InternPool.NullTerminatedString, void) = .empty;
    defer seen_decls.deinit(gpa);

    namespace.pub_decls.clearRetainingCapacity();
    namespace.priv_decls.clearRetainingCapacity();
    namespace.comptime_decls.clearRetainingCapacity();
    namespace.test_decls.clearRetainingCapacity();

    var scan_decl_iter: ScanDeclIter = .{
        .pt = pt,
        .namespace_index = namespace_index,
        .seen_decls = &seen_decls,
        .existing_by_inst = &existing_by_inst,
        .pass = .named,
    };
    for (decls) |decl_inst| {
        try scan_decl_iter.scanDecl(decl_inst);
    }
    scan_decl_iter.pass = .unnamed;
    for (decls) |decl_inst| {
        try scan_decl_iter.scanDecl(decl_inst);
    }
}

const ScanDeclIter = struct {
    pt: Zcu.PerThread,
    namespace_index: Zcu.Namespace.Index,
    seen_decls: *std.AutoHashMapUnmanaged(InternPool.NullTerminatedString, void),
    existing_by_inst: *const std.AutoHashMapUnmanaged(InternPool.TrackedInst.Index, InternPool.AnalUnit),
    /// Decl scanning is run in two passes, so that we can detect when a generated
    /// name would clash with an explicit name and use a different one.
    pass: enum { named, unnamed },
    unnamed_test_index: usize = 0,

    fn avoidNameConflict(iter: *ScanDeclIter, comptime fmt: []const u8, args: anytype) !InternPool.NullTerminatedString {
        const pt = iter.pt;
        const ip = &pt.zcu.intern_pool;
        const comp = pt.zcu.comp;
        const gpa = comp.gpa;
        const io = comp.io;
        var name = try ip.getOrPutStringFmt(gpa, io, pt.tid, fmt, args, .no_embedded_nulls);
        var gop = try iter.seen_decls.getOrPut(gpa, name);
        var next_suffix: u32 = 0;
        while (gop.found_existing) {
            name = try ip.getOrPutStringFmt(gpa, io, pt.tid, "{f}_{d}", .{ name.fmt(ip), next_suffix }, .no_embedded_nulls);
            gop = try iter.seen_decls.getOrPut(gpa, name);
            next_suffix += 1;
        }
        return name;
    }

    fn scanDecl(iter: *ScanDeclIter, decl_inst: Zir.Inst.Index) Allocator.Error!void {
        const tracy_trace = trace(@src());
        defer tracy_trace.end();

        const pt = iter.pt;
        const zcu = pt.zcu;
        const comp = zcu.comp;
        const namespace_index = iter.namespace_index;
        const namespace = zcu.namespacePtr(namespace_index);
        const gpa = comp.gpa;
        const io = comp.io;
        const file = namespace.fileScope(zcu);
        const zir = file.zir.?;
        const ip = &zcu.intern_pool;

        const decl = zir.getDeclaration(decl_inst);

        const maybe_name: InternPool.OptionalNullTerminatedString = switch (decl.kind) {
            .@"comptime" => name: {
                if (iter.pass != .unnamed) return;
                break :name .none;
            },
            .unnamed_test => name: {
                if (iter.pass != .unnamed) return;
                const i = iter.unnamed_test_index;
                iter.unnamed_test_index += 1;
                break :name (try iter.avoidNameConflict("test_{d}", .{i})).toOptional();
            },
            .@"test", .decltest => |kind| name: {
                // We consider these to be unnamed since the decl name can be adjusted to avoid conflicts if necessary.
                if (iter.pass != .unnamed) return;
                const prefix = @tagName(kind);
                break :name (try iter.avoidNameConflict("{s}.{s}", .{ prefix, zir.nullTerminatedString(decl.name) })).toOptional();
            },
            .@"const", .@"var" => name: {
                if (iter.pass != .named) return;
                const name = try ip.getOrPutString(
                    gpa,
                    io,
                    pt.tid,
                    zir.nullTerminatedString(decl.name),
                    .no_embedded_nulls,
                );
                try iter.seen_decls.putNoClobber(gpa, name, {});
                break :name name.toOptional();
            },
        };

        const tracked_inst = try ip.trackZir(gpa, io, pt.tid, .{
            .file = namespace.file_scope,
            .inst = decl_inst,
        });

        const existing_unit = iter.existing_by_inst.get(tracked_inst);

        const name = maybe_name.unwrap() orelse {
            // Only `comptime` declarations are unnamed.
            assert(decl.kind == .@"comptime");
            if (existing_unit) |unit| {
                try namespace.comptime_decls.append(gpa, unit.unwrap().@"comptime");
            } else {
                const cu = try ip.createComptimeUnit(gpa, io, pt.tid, tracked_inst, namespace_index);
                try zcu.queueComptimeUnitAnalysis(cu);
                try namespace.comptime_decls.append(gpa, cu);
            }
            return;
        };

        const fqn = try namespace.internFullyQualifiedName(ip, gpa, io, pt.tid, name);

        const nav = if (existing_unit) |unit| nav: {
            const nav = unit.unwrap().nav_val;
            assert(ip.getNav(nav).name == name);
            assert(ip.getNav(nav).fqn == fqn);
            break :nav nav;
        } else nav: {
            const nav = try ip.createDeclNav(gpa, io, pt.tid, name, fqn, tracked_inst, namespace_index);
            if (zcu.comp.debugIncremental()) try zcu.incremental_debug_state.newNav(zcu, nav);
            break :nav nav;
        };

        const want_analysis: bool = switch (decl.kind) {
            .@"comptime" => unreachable,
            .unnamed_test, .@"test", .decltest => a: {
                const is_named = decl.kind != .unnamed_test;
                try namespace.test_decls.append(gpa, nav);
                // TODO: incremental compilation!
                // * remove from `test_functions` if no longer matching filter
                // * add to `test_functions` if newly passing filter
                // This logic is unaware of incremental: we'll end up with duplicates.
                // Perhaps we should add all test indiscriminately and filter at the end of the update.
                if (!comp.config.is_test) break :a false;
                if (file.mod != zcu.main_mod) break :a false;
                if (is_named and comp.test_filters.len > 0) {
                    const fqn_slice = fqn.toSlice(ip);
                    for (comp.test_filters) |test_filter| {
                        if (std.mem.indexOf(u8, fqn_slice, test_filter) != null) break;
                    } else break :a false;
                }
                try zcu.test_functions.put(gpa, nav, {});
                break :a true;
            },
            .@"const", .@"var" => a: {
                if (decl.is_pub) {
                    try namespace.pub_decls.putContext(gpa, nav, {}, .{ .zcu = zcu });
                } else {
                    try namespace.priv_decls.putContext(gpa, nav, {}, .{ .zcu = zcu });
                }
                break :a false;
            },
        };

        if (want_analysis or decl.linkage == .@"export") {
            try zcu.ensureNavValAnalysisQueued(nav);
        }
    }
};

fn analyzeFuncBodyInner(
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    reason: ?*const Zcu.DependencyReason,
) Zcu.SemaError!Air {
    const tracy_trace = trace(@src());
    defer tracy_trace.end();

    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const ip = &zcu.intern_pool;

    const anal_unit = AnalUnit.wrap(.{ .func = func_index });
    const func = zcu.funcInfo(func_index);

    // This is the `Nav` corresponding to the `declaration` instruction which the function or its generic owner originates from.
    const decl_analysis = if (func.generic_owner == .none)
        ip.getNav(func.owner_nav).analysis.?
    else
        ip.getNav(zcu.funcInfo(func.generic_owner).owner_nav).analysis.?;

    const file = zcu.fileByIndex(decl_analysis.zir_index.resolveFile(ip));
    const zir = file.zir.?;

    try zcu.analysis_in_progress.putNoClobber(gpa, anal_unit, reason);
    defer assert(zcu.analysis_in_progress.swapRemove(anal_unit));

    if (zcu.comp.time_report) |*tr| {
        if (func.generic_owner != .none) {
            tr.stats.n_generic_instances += 1;
        }
    }

    const func_nav = ip.getNav(func.owner_nav);

    var analysis_arena = std.heap.ArenaAllocator.init(gpa);
    defer analysis_arena.deinit();

    var comptime_err_ret_trace = std.array_list.Managed(Zcu.LazySrcLoc).init(gpa);
    defer comptime_err_ret_trace.deinit();

    // In the case of a generic function instance, this is the type of the
    // instance, which has comptime parameters elided. In other words, it is
    // the runtime-known parameters only, not to be confused with the
    // generic_owner function type, which potentially has more parameters,
    // including comptime parameters.
    const fn_ty = Type.fromInterned(func.ty);
    const fn_ty_info = zcu.typeToFunc(fn_ty).?;

    var sema: Sema = .{
        .pt = pt,
        .gpa = gpa,
        .arena = analysis_arena.allocator(),
        .code = zir,
        .owner = anal_unit,
        .func_index = func_index,
        .func_is_naked = fn_ty_info.cc == .naked,
        .fn_ret_ty = Type.fromInterned(fn_ty_info.return_type),
        .fn_ret_ty_ies = null,
        .branch_quota = @max(func.branchQuotaUnordered(ip), Sema.default_branch_quota),
        .comptime_err_ret_trace = &comptime_err_ret_trace,
    };
    defer sema.deinit();

    // Every runtime function has a dependency on the source of the Decl it originates from.
    // It also depends on the value of its owner Decl.
    try sema.declareDependency(.{ .src_hash = decl_analysis.zir_index });
    try sema.declareDependency(.{ .nav_val = func.owner_nav });

    // Make sure that the declaration `Nav` still refers to this function (or its generic owner).
    // This will not be the case if the incremental update has changed a function type or turned a
    // `fn` decl into some other declaration. In that case, we must not run analysis: this function
    // will not be referenced this update, and trying to generate it could be problematic since we
    // assume the owner NAV actually, um, owns us.
    //
    // If we *are* still owned by the right NAV, this analysis updates `zir_body_inst` if necessary.

    if (func.generic_owner == .none) {
        try pt.ensureNavValUpToDate(func.owner_nav, reason);
        if (ip.getNav(func.owner_nav).resolved.?.value != func_index) {
            return error.AnalysisFail;
        }
    } else {
        const go_nav = zcu.funcInfo(func.generic_owner).owner_nav;
        try pt.ensureNavValUpToDate(go_nav, reason);
        if (ip.getNav(go_nav).resolved.?.value != func.generic_owner) {
            return error.AnalysisFail;
        }
    }

    if (func.analysisUnordered(ip).inferred_error_set) {
        const ies = try analysis_arena.allocator().create(Sema.InferredErrorSet);
        ies.* = .{ .func = func_index };
        sema.fn_ret_ty_ies = ies;
    }

    // reset in case calls to errorable functions are removed.
    ip.funcSetHasErrorTrace(io, func_index, fn_ty_info.cc == .auto);

    // First few indexes of extra are reserved and set at the end.
    const reserved_count = @typeInfo(Air.ExtraIndex).@"enum".fields.len;
    try sema.air_extra.ensureTotalCapacity(gpa, reserved_count);
    sema.air_extra.items.len += reserved_count;

    var inner_block: Sema.Block = .{
        .parent = null,
        .sema = &sema,
        .namespace = decl_analysis.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = null,
        .src_base_inst = decl_analysis.zir_index,
        .type_name_ctx = func_nav.fqn,
    };
    defer inner_block.instructions.deinit(gpa);

    const fn_info = sema.code.getFnInfo(func.zirBodyInstUnordered(ip).resolve(ip) orelse return error.AnalysisFail);

    // Here we are performing "runtime semantic analysis" for a function body, which means
    // we must map the parameter ZIR instructions to `arg` AIR instructions.
    // AIR requires the `arg` parameters to be the first N instructions.
    // This could be a generic function instantiation, however, in which case we need to
    // map the comptime parameters to constant values and only emit arg AIR instructions
    // for the runtime ones.
    const runtime_params_len = fn_ty_info.param_types.len;
    try inner_block.instructions.ensureTotalCapacityPrecise(gpa, runtime_params_len);
    try sema.air_instructions.ensureUnusedCapacity(gpa, fn_info.total_params_len);
    try sema.inst_map.ensureSpaceForInstructions(gpa, fn_info.param_body);

    // In the case of a generic function instance, pre-populate all the comptime args.
    if (func.comptime_args.len != 0) {
        for (
            fn_info.param_body[0..func.comptime_args.len],
            func.comptime_args.get(ip),
        ) |inst, comptime_arg| {
            if (comptime_arg == .none) continue;
            sema.inst_map.putAssumeCapacityNoClobber(inst, Air.internedToRef(comptime_arg));
        }
    }

    const src_params_len = if (func.comptime_args.len != 0)
        func.comptime_args.len
    else
        runtime_params_len;

    var runtime_param_index: usize = 0;
    for (fn_info.param_body[0..src_params_len], 0..) |inst, zir_param_index| {
        const gop = sema.inst_map.getOrPutAssumeCapacity(inst);
        if (gop.found_existing) continue; // provided above by comptime arg

        const param_ty: Type = .fromInterned(fn_ty_info.param_types.get(ip)[runtime_param_index]);
        runtime_param_index += 1;

        if (param_ty.isGenericPoison()) {
            // We're guaranteed to get a compile error on the `fnHasRuntimeBits` check after this
            // loop (the generic poison means this is a generic function). But `continue` here to
            // avoid an illegal call to `onePossibleValue` below.
            continue;
        }

        const param_ty_src = inner_block.src(.{ .func_decl_param_ty = @intCast(zir_param_index) });

        try sema.ensureLayoutResolved(param_ty, param_ty_src, .parameter);
        if (try param_ty.onePossibleValue(pt)) |opv| {
            gop.value_ptr.* = .fromValue(opv);
            continue;
        }
        const arg_index: Air.Inst.Index = @enumFromInt(sema.air_instructions.len);
        gop.value_ptr.* = arg_index.toRef();
        inner_block.instructions.appendAssumeCapacity(arg_index);
        sema.air_instructions.appendAssumeCapacity(.{
            .tag = .arg,
            .data = .{ .arg = .{
                .ty = .fromIntern(param_ty.toIntern()),
                .zir_param_index = @intCast(zir_param_index),
            } },
        });
    }

    try sema.ensureLayoutResolved(sema.fn_ret_ty, inner_block.src(.{ .node_offset_fn_type_ret_ty = .zero }), .return_type);

    // The function type is now resolved, so we're ready to check whether it even makes sense to ask
    // for it to be analyzed at runtime.
    if (!fn_ty.fnHasRuntimeBits(zcu)) {
        const description: []const u8 = switch (fn_ty_info.cc) {
            .@"inline" => "inline",
            else => "generic",
        };
        // This error makes sense because the only reason this analysis would ever be requested is
        // for IES resolution.
        return sema.fail(
            &inner_block,
            inner_block.nodeOffset(.zero),
            "cannot resolve inferred error set of {s} function type '{f}'",
            .{ description, fn_ty.fmt(pt) },
        );
    }

    const last_arg_index = inner_block.instructions.items.len;

    // Save the error trace as our first action in the function.
    // If this is unnecessary after all, Liveness will clean it up for us.
    const error_return_trace_index = try sema.analyzeSaveErrRetIndex(&inner_block);
    sema.error_return_trace_index_on_fn_entry = error_return_trace_index;
    inner_block.error_return_trace_index = error_return_trace_index;

    sema.analyzeFnBody(&inner_block, fn_info.body) catch |err| switch (err) {
        error.ComptimeReturn => unreachable,
        else => |e| return e,
    };

    for (sema.unresolved_inferred_allocs.keys()) |ptr_inst| {
        // The lack of a resolve_inferred_alloc means that this instruction
        // is unused so it just has to be a no-op.
        sema.air_instructions.set(@intFromEnum(ptr_inst), .{
            .tag = .alloc,
            .data = .{ .ty = .ptr_const_comptime_int },
        });
    }

    func.setBranchHint(ip, io, sema.branch_hint orelse .none);

    if (zcu.comp.config.any_error_tracing and func.analysisUnordered(ip).has_error_trace and fn_ty_info.cc != .auto) {
        // We're using an error trace, but didn't start out with one from the caller.
        // We'll have to create it at the start of the function.
        sema.setupErrorReturnTrace(&inner_block, last_arg_index) catch |err| switch (err) {
            error.ComptimeReturn => unreachable,
            error.ComptimeBreak => unreachable,
            else => |e| return e,
        };
    }

    // Copy the block into place and mark that as the main block.
    try sema.air_extra.ensureUnusedCapacity(gpa, @typeInfo(Air.Block).@"struct".fields.len +
        inner_block.instructions.items.len);
    const main_block_index = sema.addExtraAssumeCapacity(Air.Block{
        .body_len = @intCast(inner_block.instructions.items.len),
    });
    sema.air_extra.appendSliceAssumeCapacity(@ptrCast(inner_block.instructions.items));
    sema.air_extra.items[@intFromEnum(Air.ExtraIndex.main_block)] = main_block_index;

    // Resolving inferred error sets is done *before* setting the function
    // state to success, so that "unable to resolve inferred error set" errors
    // can be emitted here.
    if (sema.fn_ret_ty_ies) |ies| {
        sema.resolveInferredErrorSetPtr(&inner_block, .{
            .base_node_inst = inner_block.src_base_inst,
            .offset = Zcu.LazySrcLoc.Offset.nodeOffset(.zero),
        }, ies) catch |err| switch (err) {
            error.ComptimeReturn => unreachable,
            error.ComptimeBreak => unreachable,
            else => |e| return e,
        };
        assert(ies.resolved != .none);
        func.setResolvedErrorSet(ip, io, ies.resolved);
    }

    try sema.flushExports();

    defer {
        sema.air_instructions = .empty;
        sema.air_extra = .empty;
    }
    return .{
        .instructions = sema.air_instructions.slice(),
        .extra = sema.air_extra,
    };
}

pub fn createNamespace(pt: Zcu.PerThread, initialization: Zcu.Namespace) !Zcu.Namespace.Index {
    const comp = pt.zcu.comp;
    return pt.zcu.intern_pool.createNamespace(comp.gpa, comp.io, pt.tid, initialization);
}

pub fn destroyNamespace(pt: Zcu.PerThread, namespace_index: Zcu.Namespace.Index) void {
    return pt.zcu.intern_pool.destroyNamespace(pt.tid, namespace_index);
}

pub fn getErrorValue(
    pt: Zcu.PerThread,
    name: InternPool.NullTerminatedString,
) Allocator.Error!Zcu.ErrorInt {
    const comp = pt.zcu.comp;
    return pt.zcu.intern_pool.getErrorValue(comp.gpa, comp.io, pt.tid, name);
}

pub fn getErrorValueFromSlice(pt: Zcu.PerThread, name: []const u8) Allocator.Error!Zcu.ErrorInt {
    const comp = pt.zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    return pt.getErrorValue(try pt.zcu.intern_pool.getOrPutString(gpa, io, name));
}

/// Removes any entry from `Zcu.failed_files` associated with `file`. Acquires `Compilation.mutex` as needed.
/// `file.zir` must be unchanged from the last update, as it is used to determine if there is such an entry.
fn lockAndClearFileCompileError(pt: Zcu.PerThread, file_index: Zcu.File.Index, file: *Zcu.File) void {
    const maybe_has_error = switch (file.status) {
        .never_loaded => false,
        .retryable_failure => true,
        .astgen_failure => true,
        .success => switch (file.getMode()) {
            .zig => has_error: {
                const zir = file.zir orelse break :has_error false;
                break :has_error zir.hasCompileErrors();
            },
            .zon => has_error: {
                const zoir = file.zoir orelse break :has_error false;
                break :has_error zoir.hasCompileErrors();
            },
        },
    };

    // If runtime safety is on, let's quickly lock the mutex and check anyway.
    if (!maybe_has_error and !std.debug.runtime_safety) {
        return;
    }

    const comp = pt.zcu.comp;
    const io = comp.io;
    comp.mutex.lockUncancelable(io);
    defer comp.mutex.unlock(io);
    if (pt.zcu.failed_files.fetchSwapRemove(file_index)) |kv| {
        assert(maybe_has_error); // the runtime safety case above
        if (kv.value) |msg| pt.zcu.gpa.free(msg); // delete previous error message
    }
}

/// Called from `Compilation.update`, after everything is done, just before
/// reporting compile errors. In this function we emit exported symbol collision
/// errors and communicate exported symbols to the linker backend.
pub fn processExports(pt: Zcu.PerThread) !void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    if (zcu.single_exports.count() == 0 and zcu.multi_exports.count() == 0) {
        // We can avoid a call to `resolveReferences` in this case.
        return;
    }

    // First, construct a mapping of every exported value and Nav to the indices of all its different exports.
    var nav_exports: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, std.ArrayList(Zcu.Export.Index)) = .empty;
    var uav_exports: std.AutoArrayHashMapUnmanaged(InternPool.Index, std.ArrayList(Zcu.Export.Index)) = .empty;
    defer {
        for (nav_exports.values()) |*exports| {
            exports.deinit(gpa);
        }
        nav_exports.deinit(gpa);
        for (uav_exports.values()) |*exports| {
            exports.deinit(gpa);
        }
        uav_exports.deinit(gpa);
    }

    // We note as a heuristic:
    // * It is rare to export a value.
    // * It is rare for one Nav to be exported multiple times.
    // So, this ensureTotalCapacity serves as a reasonable (albeit very approximate) optimization.
    try nav_exports.ensureTotalCapacity(gpa, zcu.single_exports.count() + zcu.multi_exports.count());

    const unit_references = try zcu.resolveReferences();

    for (zcu.single_exports.keys(), zcu.single_exports.values()) |exporter, export_idx| {
        const exp = export_idx.ptr(zcu);
        if (!unit_references.contains(exporter)) {
            // This export might already have been sent to the linker on a previous update, in which case we need to delete it.
            // The linker export API should be modified to eliminate this call. #23616
            if (zcu.comp.bin_file) |lf| {
                if (zcu.llvm_object == null) {
                    lf.deleteExport(exp.exported, exp.opts.name);
                }
            }
            continue;
        }
        const value_ptr, const found_existing = switch (exp.exported) {
            .nav => |nav| gop: {
                const gop = try nav_exports.getOrPut(gpa, nav);
                break :gop .{ gop.value_ptr, gop.found_existing };
            },
            .uav => |uav| gop: {
                const gop = try uav_exports.getOrPut(gpa, uav);
                break :gop .{ gop.value_ptr, gop.found_existing };
            },
        };
        if (!found_existing) value_ptr.* = .empty;
        try value_ptr.append(gpa, export_idx);
    }

    for (zcu.multi_exports.keys(), zcu.multi_exports.values()) |exporter, info| {
        const exports = zcu.all_exports.items[info.index..][0..info.len];
        if (!unit_references.contains(exporter)) {
            // This export might already have been sent to the linker on a previous update, in which case we need to delete it.
            // The linker export API should be modified to eliminate this loop. #23616
            if (zcu.comp.bin_file) |lf| {
                if (zcu.llvm_object == null) {
                    for (exports) |exp| {
                        lf.deleteExport(exp.exported, exp.opts.name);
                    }
                }
            }
            continue;
        }
        for (exports, info.index..) |exp, export_idx| {
            const value_ptr, const found_existing = switch (exp.exported) {
                .nav => |nav| gop: {
                    const gop = try nav_exports.getOrPut(gpa, nav);
                    break :gop .{ gop.value_ptr, gop.found_existing };
                },
                .uav => |uav| gop: {
                    const gop = try uav_exports.getOrPut(gpa, uav);
                    break :gop .{ gop.value_ptr, gop.found_existing };
                },
            };
            if (!found_existing) value_ptr.* = .empty;
            try value_ptr.append(gpa, @enumFromInt(export_idx));
        }
    }

    // If there are compile errors, we won't call `updateExports`. Not only would it be redundant
    // work, but the linker may not have seen an exported `Nav` due to a compile error, so linker
    // implementations would have to handle that case. This early return avoids that.
    const skip_linker_work = zcu.comp.anyErrors();

    // Map symbol names to `Export` for name collision detection.
    var symbol_exports: SymbolExports = .{};
    defer symbol_exports.deinit(gpa);

    for (nav_exports.keys(), nav_exports.values()) |exported_nav, exports_list| {
        const exported: Zcu.Exported = .{ .nav = exported_nav };
        try pt.processExportsInner(&symbol_exports, exported, exports_list.items, skip_linker_work);
    }

    for (uav_exports.keys(), uav_exports.values()) |exported_uav, exports_list| {
        const exported: Zcu.Exported = .{ .uav = exported_uav };
        try pt.processExportsInner(&symbol_exports, exported, exports_list.items, skip_linker_work);
    }
}

const SymbolExports = std.AutoArrayHashMapUnmanaged(InternPool.NullTerminatedString, Zcu.Export.Index);

fn processExportsInner(
    pt: Zcu.PerThread,
    symbol_exports: *SymbolExports,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
    skip_linker_work: bool,
) error{OutOfMemory}!void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    for (export_indices) |export_idx| {
        const new_export = export_idx.ptr(zcu);
        const gop = try symbol_exports.getOrPut(gpa, new_export.opts.name);
        if (gop.found_existing) {
            new_export.status = .failed_retryable;
            try zcu.failed_exports.ensureUnusedCapacity(gpa, 1);
            const msg = try Zcu.ErrorMsg.create(gpa, new_export.src, "exported symbol collision: {f}", .{
                new_export.opts.name.fmt(ip),
            });
            errdefer msg.destroy(gpa);
            const other_export = gop.value_ptr.ptr(zcu);
            try zcu.errNote(other_export.src, msg, "other symbol here", .{});
            zcu.failed_exports.putAssumeCapacityNoClobber(export_idx, msg);
            new_export.status = .failed;
        } else {
            gop.value_ptr.* = export_idx;
        }
    }

    switch (exported) {
        .nav => |nav_index| if (failed: {
            const nav = ip.getNav(nav_index);
            if (zcu.failed_codegen.contains(nav_index)) break :failed true;
            if (nav.analysis != null) {
                const unit: AnalUnit = .wrap(.{ .nav_val = nav_index });
                if (zcu.failed_analysis.contains(unit)) break :failed true;
                if (zcu.transitive_failed_analysis.contains(unit)) break :failed true;
            }
            const val: Value = switch ((nav.resolved orelse break :failed true).value) {
                .none => break :failed true,
                else => |val| .fromInterned(val),
            };
            // If the value is a function, we also need to check if that function succeeded analysis.
            if (val.typeOf(zcu).zigTypeTag(zcu) == .@"fn") {
                const func_unit = AnalUnit.wrap(.{ .func = val.toIntern() });
                if (zcu.failed_analysis.contains(func_unit)) break :failed true;
                if (zcu.transitive_failed_analysis.contains(func_unit)) break :failed true;
            }
            break :failed false;
        }) {
            // This `Nav` is failed, so was never sent to codegen. There should be a compile error.
            assert(skip_linker_work);
        },
        .uav => {},
    }

    if (skip_linker_work) return;

    if (zcu.llvm_object) |llvm_object| {
        try zcu.handleUpdateExports(export_indices, llvm_object.updateExports(exported, export_indices));
    } else if (zcu.comp.bin_file) |lf| {
        try zcu.handleUpdateExports(export_indices, lf.updateExports(pt, exported, export_indices));
    }
}

pub fn populateTestFunctions(pt: Zcu.PerThread) Allocator.Error!void {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const ip = &zcu.intern_pool;

    // Our job is to correctly set the value of the `test_functions` declaration if it has been
    // analyzed and sent to codegen, It usually will have been, because the test runner will
    // reference it, and `std.builtin` shouldn't have type errors. However, if it hasn't been
    // analyzed, we will just terminate early, since clearly the test runner hasn't referenced
    // `test_functions` so there's no point populating it. More to the the point, we potentially
    // *can't* populate it without doing some type resolution, and... let's try to leave Sema in
    // the past here.

    const builtin_mod = zcu.builtin_modules.get(zcu.root_mod.getBuiltinOptions(zcu.comp.config).hash()).?;
    const builtin_file_index = zcu.module_roots.get(builtin_mod).?.unwrap().?;
    const builtin_root_type = zcu.fileRootType(builtin_file_index);
    if (builtin_root_type == .none) return; // `@import("builtin")` never analyzed
    const builtin_namespace = Type.fromInterned(builtin_root_type).getNamespace(zcu).unwrap().?;
    // We know that the namespace has a `test_functions`...
    const test_fns_nav_index = zcu.namespacePtr(builtin_namespace).pub_decls.getKeyAdapted(
        try ip.getOrPutString(gpa, io, pt.tid, "test_functions", .no_embedded_nulls),
        Zcu.Namespace.NameAdapter{ .zcu = zcu },
    ).?;
    const test_fns_nav = ip.getNav(test_fns_nav_index);
    // ...but it might not be populated, so let's check that!
    if (zcu.failed_analysis.contains(.wrap(.{ .nav_val = test_fns_nav_index })) or
        zcu.transitive_failed_analysis.contains(.wrap(.{ .nav_val = test_fns_nav_index })) or
        test_fns_nav.resolved == null or
        test_fns_nav.resolved.?.value == .none)
    {
        // The value of `builtin.test_functions` was either never referenced, or failed analysis.
        // Either way, we don't need to do anything.
        return;
    }

    // Okay, `builtin.test_functions` is (potentially) referenced and valid. Our job now is to swap
    // its placeholder `&.{}` value for the actual list of all test functions.

    const test_fn_ty = Type.fromInterned(test_fns_nav.resolved.?.type).slicePtrFieldType(zcu).childType(zcu);

    const array_anon_decl: InternPool.Key.Ptr.BaseAddr.Uav = array: {
        // Add zcu.test_functions to an array decl then make the test_functions
        // decl reference it as a slice.
        const test_fn_vals = try gpa.alloc(InternPool.Index, zcu.test_functions.count());
        defer gpa.free(test_fn_vals);

        for (test_fn_vals, zcu.test_functions.keys()) |*test_fn_val, test_nav_index| {
            const test_nav = ip.getNav(test_nav_index);

            {
                // The test declaration might have failed; if that's the case, just return, as we'll
                // be emitting a compile error anyway.
                const anal_unit: AnalUnit = .wrap(.{ .nav_val = test_nav_index });
                if (zcu.failed_analysis.contains(anal_unit) or
                    zcu.transitive_failed_analysis.contains(anal_unit))
                {
                    return;
                }
            }

            const test_nav_name = test_nav.fqn;
            const test_nav_name_len = test_nav_name.length(ip);
            const test_name_anon_decl: InternPool.Key.Ptr.BaseAddr.Uav = n: {
                const test_name_ty = try pt.arrayType(.{
                    .len = test_nav_name_len,
                    .child = .u8_type,
                });
                const test_name_val = try pt.intern(.{ .aggregate = .{
                    .ty = test_name_ty.toIntern(),
                    .storage = .{ .bytes = test_nav_name.toString() },
                } });
                break :n .{
                    .orig_ty = (try pt.singleConstPtrType(test_name_ty)).toIntern(),
                    .val = test_name_val,
                };
            };

            const test_fn_fields = .{
                // name
                try pt.intern(.{ .slice = .{
                    .ty = .slice_const_u8_type,
                    .ptr = try pt.intern(.{ .ptr = .{
                        .ty = .manyptr_const_u8_type,
                        .base_addr = .{ .uav = test_name_anon_decl },
                        .byte_offset = 0,
                    } }),
                    .len = try pt.intern(.{ .int = .{
                        .ty = .usize_type,
                        .storage = .{ .u64 = test_nav_name_len },
                    } }),
                } }),
                // func
                try pt.intern(.{ .ptr = .{
                    .ty = (try pt.navPtrType(test_nav_index)).toIntern(),
                    .base_addr = .{ .nav = test_nav_index },
                    .byte_offset = 0,
                } }),
            };
            test_fn_val.* = (try pt.aggregateValue(test_fn_ty, &test_fn_fields)).toIntern();
        }

        const array_ty = try pt.arrayType(.{
            .len = test_fn_vals.len,
            .child = test_fn_ty.toIntern(),
            .sentinel = .none,
        });
        break :array .{
            .orig_ty = (try pt.singleConstPtrType(array_ty)).toIntern(),
            .val = (try pt.aggregateValue(array_ty, test_fn_vals)).toIntern(),
        };
    };

    {
        const new_ty = try pt.ptrType(.{
            .child = test_fn_ty.toIntern(),
            .flags = .{
                .is_const = true,
                .size = .slice,
            },
        });
        const new_init = try pt.intern(.{ .slice = .{
            .ty = new_ty.toIntern(),
            .ptr = try pt.intern(.{ .ptr = .{
                .ty = new_ty.slicePtrFieldType(zcu).toIntern(),
                .base_addr = .{ .uav = array_anon_decl },
                .byte_offset = 0,
            } }),
            .len = (try pt.intValue(Type.usize, zcu.test_functions.count())).toIntern(),
        } });
        var new_resolved_test_fns = test_fns_nav.resolved.?;
        new_resolved_test_fns.value = new_init;
        ip.resolveNav(io, test_fns_nav_index, new_resolved_test_fns);
    }
    // The linker thread is not running, so we actually need to dispatch this task directly.
    @import("../link.zig").linkTestFunctionsNav(pt, test_fns_nav_index);
}

/// Stores an error in `pt.zcu.failed_files` for this file, and sets the file
/// status to `retryable_failure`.
pub fn reportRetryableFileError(
    pt: Zcu.PerThread,
    file_index: Zcu.File.Index,
    comptime format: []const u8,
    args: anytype,
) error{OutOfMemory}!void {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;

    const file = zcu.fileByIndex(file_index);

    file.status = .retryable_failure;

    const msg = try std.fmt.allocPrint(gpa, format, args);
    errdefer gpa.free(msg);

    const old_msg: ?[]u8 = old_msg: {
        comp.mutex.lockUncancelable(io);
        defer comp.mutex.unlock(io);

        const gop = try zcu.failed_files.getOrPut(gpa, file_index);
        const old: ?[]u8 = if (gop.found_existing) old: {
            break :old gop.value_ptr.*;
        } else null;
        gop.value_ptr.* = msg;

        break :old_msg old;
    };
    if (old_msg) |m| gpa.free(m);
}

/// Shortcut for calling `intern_pool.get`.
pub fn intern(pt: Zcu.PerThread, key: InternPool.Key) Allocator.Error!InternPool.Index {
    const comp = pt.zcu.comp;
    return pt.zcu.intern_pool.get(comp.gpa, comp.io, pt.tid, key);
}

/// Essentially a shortcut for calling `intern_pool.getCoerced`.
/// However, this function also allows coercing `extern`s. The `InternPool` function can't do
/// this because it requires potentially queueing a link task.
pub fn getCoerced(pt: Zcu.PerThread, val: Value, new_ty: Type) Allocator.Error!Value {
    const ip = &pt.zcu.intern_pool;
    const comp = pt.zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    switch (ip.indexToKey(val.toIntern())) {
        .@"extern" => |@"extern"| {
            // TODO: it's awkward to make this function cancelable. The problem is really that
            // `getCoerced` is a bad API: it should be replaced with smaller, more specialized
            // functions, so that this cancel point is only possible in the rare case that you
            // may actually need to coerce an extern!
            const old_prot = io.swapCancelProtection(.blocked);
            defer _ = io.swapCancelProtection(old_prot);
            const coerced = pt.getExtern(.{
                .name = @"extern".name,
                .ty = new_ty.toIntern(),
                .lib_name = @"extern".lib_name,
                .is_const = @"extern".is_const,
                .is_threadlocal = @"extern".is_threadlocal,
                .linkage = @"extern".linkage,
                .visibility = @"extern".visibility,
                .is_dll_import = @"extern".is_dll_import,
                .relocation = @"extern".relocation,
                .decoration = @"extern".decoration,
                .alignment = @"extern".alignment,
                .@"addrspace" = @"extern".@"addrspace",
                .zir_index = @"extern".zir_index,
                .owner_nav = undefined, // ignored by `getExtern`.
                .source = @"extern".source,
            }) catch |err| switch (err) {
                error.Canceled => unreachable, // blocked above
                error.OutOfMemory => |e| return e,
            };
            return .fromInterned(coerced);
        },
        else => {},
    }
    return .fromInterned(try ip.getCoerced(gpa, io, pt.tid, val.toIntern(), new_ty.toIntern()));
}

pub fn intType(pt: Zcu.PerThread, signedness: std.builtin.Signedness, bits: u16) Allocator.Error!Type {
    return Type.fromInterned(try pt.intern(.{ .int_type = .{
        .signedness = signedness,
        .bits = bits,
    } }));
}

pub fn errorIntType(pt: Zcu.PerThread) std.mem.Allocator.Error!Type {
    return pt.intType(.unsigned, pt.zcu.errorSetBits());
}

pub fn arrayType(pt: Zcu.PerThread, info: InternPool.Key.ArrayType) Allocator.Error!Type {
    return Type.fromInterned(try pt.intern(.{ .array_type = info }));
}

pub fn vectorType(pt: Zcu.PerThread, info: InternPool.Key.VectorType) Allocator.Error!Type {
    return Type.fromInterned(try pt.intern(.{ .vector_type = info }));
}

pub fn optionalType(pt: Zcu.PerThread, child_type: InternPool.Index) Allocator.Error!Type {
    return Type.fromInterned(try pt.intern(.{ .opt_type = child_type }));
}

pub fn ptrType(pt: Zcu.PerThread, info: InternPool.Key.PtrType) Allocator.Error!Type {
    var canon_info = info;

    if (info.flags.size == .c) canon_info.flags.is_allowzero = true;

    switch (info.flags.vector_index) {
        // Canonicalize host_size. If it matches the bit size of the pointee type,
        // we change it to 0 here. If this causes an assertion trip, the pointee type
        // needs to be resolved before calling this ptr() function.
        .none => if (info.packed_offset.host_size != 0) {
            const elem_bit_size = Type.fromInterned(info.child).bitSize(pt.zcu);
            assert(info.packed_offset.bit_offset + elem_bit_size <= info.packed_offset.host_size * 8);
            if (info.packed_offset.host_size * 8 == elem_bit_size) {
                canon_info.packed_offset.host_size = 0;
            }
        },
        _ => assert(@intFromEnum(info.flags.vector_index) < info.packed_offset.host_size),
    }

    return Type.fromInterned(try pt.intern(.{ .ptr_type = canon_info }));
}

pub fn singleMutPtrType(pt: Zcu.PerThread, child_type: Type) Allocator.Error!Type {
    return pt.ptrType(.{ .child = child_type.toIntern() });
}

pub fn singleConstPtrType(pt: Zcu.PerThread, child_type: Type) Allocator.Error!Type {
    return pt.ptrType(.{
        .child = child_type.toIntern(),
        .flags = .{
            .is_const = true,
        },
    });
}

pub fn manyConstPtrType(pt: Zcu.PerThread, child_type: Type) Allocator.Error!Type {
    return pt.ptrType(.{
        .child = child_type.toIntern(),
        .flags = .{
            .size = .many,
            .is_const = true,
        },
    });
}

pub fn adjustPtrTypeChild(pt: Zcu.PerThread, ptr_ty: Type, new_child: Type) Allocator.Error!Type {
    var info = ptr_ty.ptrInfo(pt.zcu);
    info.child = new_child.toIntern();
    return pt.ptrType(info);
}

pub fn funcType(pt: Zcu.PerThread, key: InternPool.GetFuncTypeKey) Allocator.Error!Type {
    const comp = pt.zcu.comp;
    return .fromInterned(try pt.zcu.intern_pool.getFuncType(comp.gpa, comp.io, pt.tid, key));
}

/// Use this for `anyframe->T` only.
/// For `anyframe`, use the `InternPool.Index.anyframe` tag directly.
pub fn anyframeType(pt: Zcu.PerThread, payload_ty: Type) Allocator.Error!Type {
    return Type.fromInterned(try pt.intern(.{ .anyframe_type = payload_ty.toIntern() }));
}

pub fn errorUnionType(pt: Zcu.PerThread, error_set_ty: Type, payload_ty: Type) Allocator.Error!Type {
    return Type.fromInterned(try pt.intern(.{ .error_union_type = .{
        .error_set_type = error_set_ty.toIntern(),
        .payload_type = payload_ty.toIntern(),
    } }));
}

pub fn singleErrorSetType(pt: Zcu.PerThread, name: InternPool.NullTerminatedString) Allocator.Error!Type {
    const names: *const [1]InternPool.NullTerminatedString = &name;
    const comp = pt.zcu.comp;
    return Type.fromInterned(try pt.zcu.intern_pool.getErrorSetType(comp.gpa, comp.io, pt.tid, names));
}

/// Sorts `names` in place.
pub fn errorSetFromUnsortedNames(
    pt: Zcu.PerThread,
    names: []InternPool.NullTerminatedString,
) Allocator.Error!Type {
    std.mem.sort(
        InternPool.NullTerminatedString,
        names,
        {},
        InternPool.NullTerminatedString.indexLessThan,
    );
    const comp = pt.zcu.comp;
    const new_ty = try pt.zcu.intern_pool.getErrorSetType(comp.gpa, comp.io, pt.tid, names);
    return Type.fromInterned(new_ty);
}

/// Supports only pointers, not pointer-like optionals.
pub fn ptrIntValue(pt: Zcu.PerThread, ty: Type, x: u64) Allocator.Error!Value {
    const zcu = pt.zcu;
    assert(ty.zigTypeTag(zcu) == .pointer and !ty.isSlice(zcu));
    assert(x != 0 or ty.isAllowzeroPtr(zcu));
    return Value.fromInterned(try pt.intern(.{ .ptr = .{
        .ty = ty.toIntern(),
        .base_addr = .int,
        .byte_offset = x,
    } }));
}

/// Creates an enum tag value based on the integer tag value.
pub fn enumValue(pt: Zcu.PerThread, ty: Type, tag_int: InternPool.Index) Allocator.Error!Value {
    if (std.debug.runtime_safety) {
        const tag = ty.zigTypeTag(pt.zcu);
        assert(tag == .@"enum");
    }
    return Value.fromInterned(try pt.intern(.{ .enum_tag = .{
        .ty = ty.toIntern(),
        .int = tag_int,
    } }));
}

/// Creates an enum tag value based on the field index according to source code
/// declaration order.
pub fn enumValueFieldIndex(pt: Zcu.PerThread, ty: Type, field_index: u32) Allocator.Error!Value {
    const ip = &pt.zcu.intern_pool;
    const enum_type = ip.loadEnumType(ty.toIntern());

    assert(field_index < enum_type.field_names.len);

    if (enum_type.field_values.len == 0) {
        // Auto-numbered fields.
        return Value.fromInterned(try pt.intern(.{ .enum_tag = .{
            .ty = ty.toIntern(),
            .int = try pt.intern(.{ .int = .{
                .ty = enum_type.int_tag_type,
                .storage = .{ .u64 = field_index },
            } }),
        } }));
    }

    return .fromInterned(try pt.intern(.{ .enum_tag = .{
        .ty = ty.toIntern(),
        .int = enum_type.field_values.get(ip)[field_index],
    } }));
}

pub fn undefValue(pt: Zcu.PerThread, ty: Type) Allocator.Error!Value {
    if (std.debug.runtime_safety) {
        // TODO: values of type `struct { comptime x: u8 = undefined }` are currently represented as
        // undef. This is wrong: they should really be represented as empty aggregates instead,
        // because `comptime` fields shouldn't factor into that decision! This is implemented
        // through logic in `aggregateValue` and requires this weird workaround in what ought to be
        // a straightforward assertion:
        //assert(ty.classify(pt.zcu) != .one_possible_value);
        if (ty.classify(pt.zcu) == .one_possible_value) {
            const ip = &pt.zcu.intern_pool;
            switch (ip.indexToKey(ty.toIntern())) {
                else => unreachable, // assertion failure
                .struct_type => {
                    const comptime_bits = ip.loadStructType(ty.toIntern()).field_is_comptime_bits.getAll(ip);
                    for (comptime_bits) |bag| {
                        if (@popCount(bag) > 0) break;
                    } else unreachable; // assertion failure
                },
                .tuple_type => |tuple| for (tuple.values.get(ip)) |val| {
                    if (val != .none) break;
                } else unreachable, // assertion failure
            }
        }
    }
    return .fromInterned(try pt.intern(.{ .undef = ty.toIntern() }));
}

pub fn undefRef(pt: Zcu.PerThread, ty: Type) Allocator.Error!Air.Inst.Ref {
    return .fromValue(try pt.undefValue(ty));
}

pub fn intValue(pt: Zcu.PerThread, ty: Type, x: anytype) Allocator.Error!Value {
    if (std.math.cast(u64, x)) |casted| return pt.intValue_u64(ty, casted);
    if (std.math.cast(i64, x)) |casted| return pt.intValue_i64(ty, casted);
    var limbs_buffer: [4]usize = undefined;
    var big_int = BigIntMutable.init(&limbs_buffer, x);
    return pt.intValue_big(ty, big_int.toConst());
}

pub fn intRef(pt: Zcu.PerThread, ty: Type, x: anytype) Allocator.Error!Air.Inst.Ref {
    return Air.internedToRef((try pt.intValue(ty, x)).toIntern());
}

pub fn intValue_big(pt: Zcu.PerThread, ty: Type, x: BigIntConst) Allocator.Error!Value {
    if (ty.toIntern() != .comptime_int_type) {
        const int_info = ty.intInfo(pt.zcu);
        assert(x.fitsInTwosComp(int_info.signedness, int_info.bits));
    }
    return .fromInterned(try pt.intern(.{ .int = .{
        .ty = ty.toIntern(),
        .storage = .{ .big_int = x },
    } }));
}

pub fn intValue_u64(pt: Zcu.PerThread, ty: Type, x: u64) Allocator.Error!Value {
    if (ty.toIntern() != .comptime_int_type and x != 0) {
        const int_info = ty.intInfo(pt.zcu);
        const unsigned_bits = int_info.bits - @intFromBool(int_info.signedness == .signed);
        assert(unsigned_bits >= std.math.log2(x) + 1);
    }
    return .fromInterned(try pt.intern(.{ .int = .{
        .ty = ty.toIntern(),
        .storage = .{ .u64 = x },
    } }));
}

pub fn intValue_i64(pt: Zcu.PerThread, ty: Type, x: i64) Allocator.Error!Value {
    if (ty.toIntern() != .comptime_int_type and x != 0) {
        const int_info = ty.intInfo(pt.zcu);
        const unsigned_bits = int_info.bits - @intFromBool(int_info.signedness == .signed);
        if (x > 0) {
            assert(unsigned_bits >= std.math.log2(x) + 1);
        } else {
            assert(int_info.signedness == .signed);
            assert(unsigned_bits >= std.math.log2_int_ceil(u64, @abs(x)));
        }
    }
    return .fromInterned(try pt.intern(.{ .int = .{
        .ty = ty.toIntern(),
        .storage = .{ .i64 = x },
    } }));
}

/// Shortcut for calling `intern_pool.getUnion`.
/// TODO: remove either this or `unionValue`.
pub fn internUnion(pt: Zcu.PerThread, un: InternPool.Key.Union) Allocator.Error!InternPool.Index {
    const comp = pt.zcu.comp;
    return pt.zcu.intern_pool.getUnion(comp.gpa, comp.io, pt.tid, un);
}

/// TODO: remove either this or `internUnion`.
pub fn unionValue(pt: Zcu.PerThread, union_ty: Type, tag: Value, val: Value) Allocator.Error!Value {
    const comp = pt.zcu.comp;
    return Value.fromInterned(try pt.zcu.intern_pool.getUnion(comp.gpa, comp.io, pt.tid, .{
        .ty = union_ty.toIntern(),
        .tag = tag.toIntern(),
        .val = val.toIntern(),
    }));
}

pub fn aggregateValue(pt: Zcu.PerThread, ty: Type, elems: []const InternPool.Index) Allocator.Error!Value {
    for (elems) |elem| {
        if (!Value.fromInterned(elem).isUndef(pt.zcu)) break;
    } else if (elems.len > 0) {
        return pt.undefValue(ty);
    }
    return .fromInterned(try pt.intern(.{ .aggregate = .{
        .ty = ty.toIntern(),
        .storage = .{ .elems = elems },
    } }));
}

/// Asserts that `ty` is either an array or a vector.
pub fn aggregateSplatValue(pt: Zcu.PerThread, ty: Type, repeated_elem: Value) Allocator.Error!Value {
    switch (ty.zigTypeTag(pt.zcu)) {
        .array, .vector => {},
        else => unreachable,
    }
    if (repeated_elem.isUndef(pt.zcu)) return pt.undefValue(ty);
    return .fromInterned(try pt.intern(.{ .aggregate = .{
        .ty = ty.toIntern(),
        .storage = .{ .repeated_elem = repeated_elem.toIntern() },
    } }));
}

/// This function casts the float representation down to the representation of the type, potentially
/// losing data if the representation wasn't correct.
pub fn floatValue(pt: Zcu.PerThread, ty: Type, x: anytype) Allocator.Error!Value {
    const storage: InternPool.Key.Float.Storage = switch (ty.floatBits(pt.zcu.getTarget())) {
        16 => .{ .f16 = @as(f16, @floatCast(x)) },
        32 => .{ .f32 = @as(f32, @floatCast(x)) },
        64 => .{ .f64 = @as(f64, @floatCast(x)) },
        80 => .{ .f80 = @as(f80, @floatCast(x)) },
        128 => .{ .f128 = @as(f128, @floatCast(x)) },
        else => unreachable,
    };
    return Value.fromInterned(try pt.intern(.{ .float = .{
        .ty = ty.toIntern(),
        .storage = storage,
    } }));
}

/// Create a value whose type is a `packed struct` or `packed union`, from the backing integer value.
pub fn bitpackValue(pt: Zcu.PerThread, ty: Type, backing_int_val: Value) Allocator.Error!Value {
    assert(backing_int_val.typeOf(pt.zcu).toIntern() == ty.bitpackBackingInt(pt.zcu).toIntern());
    return .fromInterned(try pt.intern(.{ .bitpack = .{
        .ty = ty.toIntern(),
        .backing_int_val = backing_int_val.toIntern(),
    } }));
}

pub fn nullValue(pt: Zcu.PerThread, opt_ty: Type) Allocator.Error!Value {
    assert(pt.zcu.intern_pool.isOptionalType(opt_ty.toIntern()));
    return Value.fromInterned(try pt.intern(.{ .opt = .{
        .ty = opt_ty.toIntern(),
        .val = .none,
    } }));
}

/// `ty` is an integer or a vector of integers.
pub fn overflowArithmeticTupleType(pt: Zcu.PerThread, ty: Type) !Type {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const ov_ty: Type = if (ty.zigTypeTag(zcu) == .vector) try pt.vectorType(.{
        .len = ty.vectorLen(zcu),
        .child = .u1_type,
    }) else .u1;
    const tuple_ty = try zcu.intern_pool.getTupleType(comp.gpa, comp.io, pt.tid, .{
        .types = &.{ ty.toIntern(), ov_ty.toIntern() },
        .values = &.{ .none, .none },
    });
    return .fromInterned(tuple_ty);
}

pub fn smallestUnsignedInt(pt: Zcu.PerThread, max: u64) Allocator.Error!Type {
    return pt.intType(.unsigned, Type.smallestUnsignedBits(max));
}

/// Returns the smallest possible integer type containing both `min` and
/// `max`. Asserts that neither value is undef.
/// TODO: if #3806 is implemented, this becomes trivial
pub fn intFittingRange(pt: Zcu.PerThread, min: Value, max: Value) !Type {
    const zcu = pt.zcu;
    assert(!min.isUndef(zcu));
    assert(!max.isUndef(zcu));

    if (std.debug.runtime_safety) {
        assert(Value.order(min, max, zcu).compare(.lte));
    }

    const sign = min.compareHetero(.lt, .zero_comptime_int, zcu);

    const min_val_bits = pt.intBitsForValue(min, sign);
    const max_val_bits = pt.intBitsForValue(max, sign);

    return pt.intType(
        if (sign) .signed else .unsigned,
        @max(min_val_bits, max_val_bits),
    );
}

/// Given a value representing an integer, returns the number of bits necessary to represent
/// this value in an integer. If `sign` is true, returns the number of bits necessary in a
/// twos-complement integer; otherwise in an unsigned integer.
/// Asserts that `val` is not undef. If `val` is negative, asserts that `sign` is true.
pub fn intBitsForValue(pt: Zcu.PerThread, val: Value, sign: bool) u16 {
    const zcu = pt.zcu;
    assert(!val.isUndef(zcu));

    const key = zcu.intern_pool.indexToKey(val.toIntern());
    switch (key.int.storage) {
        .i64 => |x| {
            if (std.math.cast(u64, x)) |casted| return Type.smallestUnsignedBits(casted) + @intFromBool(sign);
            assert(sign);
            // Protect against overflow in the following negation.
            if (x == std.math.minInt(i64)) return 64;
            return Type.smallestUnsignedBits(@as(u64, @intCast(-(x + 1)))) + 1;
        },
        .u64 => |x| {
            return Type.smallestUnsignedBits(x) + @intFromBool(sign);
        },
        .big_int => |big| {
            if (big.positive) return @as(u16, @intCast(big.bitCountAbs() + @intFromBool(sign)));

            // Zero is still a possibility, in which case unsigned is fine
            if (big.eqlZero()) return 0;

            return @as(u16, @intCast(big.bitCountTwosComp()));
        },
    }
}

pub fn navPtrType(pt: Zcu.PerThread, nav_id: InternPool.Nav.Index) Allocator.Error!Type {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const resolved_nav = ip.getNav(nav_id).resolved.?;
    return pt.ptrType(.{
        .child = resolved_nav.type,
        .flags = .{
            .alignment = resolved_nav.@"align",
            .address_space = resolved_nav.@"addrspace",
            .is_const = resolved_nav.@"const",
        },
    });
}

/// Intern an `.@"extern"`, creating a corresponding owner `Nav` if necessary.
/// If necessary, the new `Nav` is queued for codegen.
/// `key.owner_nav` is ignored and may be `undefined`.
pub fn getExtern(pt: Zcu.PerThread, key: InternPool.Key.Extern) (Io.Cancelable || Allocator.Error)!InternPool.Index {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    Type.fromInterned(key.ty).assertHasLayout(zcu);
    const result = try zcu.intern_pool.getExtern(comp.gpa, comp.io, pt.tid, key);
    if (result.new_nav.unwrap()) |nav| {
        if (comp.debugIncremental()) try zcu.incremental_debug_state.newNav(zcu, nav);
        comp.link_prog_node.increaseEstimatedTotalItems(1);
        try comp.link_queue.enqueueZcu(comp, pt.tid, .{ .link_nav = nav });
    }
    return result.index;
}

/// Given a namespace, re-scan its declarations from the type definition if they have not
/// yet been re-scanned on this update.
/// If the type declaration instruction has been lost, returns `error.AnalysisFail`.
/// This will effectively short-circuit the caller, which will be semantic analysis of a
/// guaranteed-unreferenced `AnalUnit`, to trigger a transitive analysis error.
pub fn ensureNamespaceUpToDate(pt: Zcu.PerThread, namespace_index: Zcu.Namespace.Index) Zcu.SemaError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const namespace = zcu.namespacePtr(namespace_index);

    if (namespace.generation == zcu.generation) return;

    const Container = enum { @"struct", @"union", @"enum", @"opaque" };
    const container: Container, const full_key = switch (ip.indexToKey(namespace.owner_type)) {
        .struct_type => |k| .{ .@"struct", k },
        .union_type => |k| .{ .@"union", k },
        .enum_type => |k| .{ .@"enum", k },
        .opaque_type => |k| .{ .@"opaque", k },
        else => unreachable, // namespaces are owned by a container type
    };

    const key = switch (full_key) {
        .reified, .generated_union_tag => {
            // Namespace always empty, so up-to-date.
            namespace.generation = zcu.generation;
            return;
        },
        .declared => |d| d,
    };

    // Namespace outdated -- re-scan the type if necessary.

    const inst_info = key.zir_index.resolveFull(ip) orelse return error.AnalysisFail;
    const file = zcu.fileByIndex(inst_info.file);
    const zir = &file.zir.?;

    const decls = switch (container) {
        .@"struct" => zir.getStructDecl(inst_info.inst).decls,
        .@"union" => zir.getUnionDecl(inst_info.inst).decls,
        .@"enum" => zir.getEnumDecl(inst_info.inst).decls,
        .@"opaque" => zir.getOpaqueDecl(inst_info.inst).decls,
    };

    try pt.scanNamespace(namespace_index, decls);
    namespace.generation = zcu.generation;
}

pub fn uavValue(pt: Zcu.PerThread, val: Value) Zcu.SemaError!Value {
    const zcu = pt.zcu;
    const ptr_ty = try pt.ptrType(.{
        .child = val.typeOf(zcu).toIntern(),
        .flags = .{
            .alignment = .none,
            .is_const = true,
            .address_space = .generic,
        },
    });
    return .fromInterned(try pt.intern(.{ .ptr = .{
        .ty = ptr_ty.toIntern(),
        .base_addr = .{ .uav = .{
            .val = val.toIntern(),
            .orig_ty = ptr_ty.toIntern(),
        } },
        .byte_offset = 0,
    } }));
}

pub fn addDependency(pt: Zcu.PerThread, unit: AnalUnit, dependee: InternPool.Dependee) Allocator.Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.comp.gpa;
    try zcu.intern_pool.addDependency(gpa, unit, dependee);
    if (zcu.comp.debugIncremental()) {
        const info = try zcu.incremental_debug_state.getUnitInfo(gpa, unit);
        try info.deps.append(gpa, dependee);
    }
}

pub const RunCodegenError = Io.Cancelable || error{AlreadyReported};

/// Performs code generation, which comes after `Sema` but before `link` in the pipeline. This part
/// of the pipeline is self-contained and can usually be run concurrently with other components.
///
/// This function is called asynchronously by `Zcu.CodegenTaskPool.start` and awaited by the linker.
/// However, if the codegen backend does not support `Zcu.Feature.separate_thread`, then
/// `Compilation.processOneJob` will immediately await the result of the linker task, meaning the
/// pipeline becomes effectively single-threaded.
pub fn runCodegen(pt: Zcu.PerThread, func_index: InternPool.Index, air: *Air) RunCodegenError!codegen.AnyMir {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;

    crash_report.CodegenFunc.start(zcu, func_index);
    defer crash_report.CodegenFunc.stop(func_index);

    var timer = comp.startTimer();

    const codegen_result = runCodegenInner(pt, func_index, air);

    if (timer.finish(io)) |ns_codegen| report_time: {
        const ip = &zcu.intern_pool;
        const nav = ip.indexToKey(func_index).func.owner_nav;
        const zir_decl = ip.getNav(nav).srcInst(ip);
        comp.mutex.lockUncancelable(io);
        defer comp.mutex.unlock(io);
        const tr = &zcu.comp.time_report.?;
        tr.stats.cpu_ns_codegen += ns_codegen;
        const gop = tr.decl_codegen_ns.getOrPut(comp.gpa, zir_decl) catch |err| switch (err) {
            error.OutOfMemory => {
                comp.setAllocFailure();
                break :report_time;
            },
        };
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += ns_codegen;
    }

    if (zcu.pending_codegen_jobs.rmw(.Sub, 1, .monotonic) == 1) {
        // Decremented to 0, so all done.
        zcu.codegen_prog_node.end();
        zcu.codegen_prog_node = .none;
    }

    return codegen_result catch |err| {
        switch (err) {
            error.OutOfMemory => comp.setAllocFailure(),
            error.CodegenFail => zcu.assertCodegenFailed(zcu.funcInfo(func_index).owner_nav),
            error.NoLinkFile => assert(comp.bin_file == null),
            error.BackendDoesNotProduceMir => switch (target_util.zigBackend(
                &zcu.root_mod.resolved_target.result,
                comp.config.use_llvm,
            )) {
                else => unreachable, // assertion failure
                .stage2_spirv,
                .stage2_llvm,
                => {},
            },
            error.Canceled => |e| return e,
        }
        return error.AlreadyReported;
    };
}
fn runCodegenInner(pt: Zcu.PerThread, func_index: InternPool.Index, air: *Air) error{
    OutOfMemory,
    Canceled,
    CodegenFail,
    NoLinkFile,
    BackendDoesNotProduceMir,
}!codegen.AnyMir {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const comp = zcu.comp;

    const nav = zcu.funcInfo(func_index).owner_nav;
    const fqn = ip.getNav(nav).fqn;

    const codegen_prog_node = zcu.codegen_prog_node.start(fqn.toSlice(ip), 0);
    defer codegen_prog_node.end();

    if (codegen.legalizeFeatures(pt, nav)) |features| {
        try air.legalize(pt, features);
    }

    var liveness: ?Air.Liveness = if (codegen.wantsLiveness(pt, nav))
        try .analyze(zcu, air.*, ip)
    else
        null;
    defer if (liveness) |*l| l.deinit(gpa);

    if (build_options.enable_debug_extensions and comp.verbose_air) p: {
        const io = comp.io;
        const stderr = try io.lockStderr(&.{}, null);
        defer io.unlockStderr();
        printVerboseAir(pt, liveness, fqn, air, &stderr.file_writer.interface) catch |err| switch (err) {
            error.WriteFailed => switch (stderr.file_writer.err.?) {
                error.Canceled => |e| return e,
                else => break :p,
            },
        };
    }

    if (std.debug.runtime_safety) verify_liveness: {
        var verify: Air.Liveness.Verify = .{
            .gpa = gpa,
            .zcu = zcu,
            .air = air.*,
            .liveness = liveness orelse break :verify_liveness,
            .intern_pool = ip,
        };
        defer verify.deinit();

        verify.verify() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return zcu.codegenFail(nav, "invalid liveness: {t}", .{err}),
        };
    }

    // The LLVM backend is special, because we only need to do codegen. There is no equivalent to the
    // "emit" step because LLVM does not support incremental linking. Our linker (LLD or self-hosted)
    // will just see the ZCU object file which LLVM ultimately emits.
    if (zcu.llvm_object) |llvm_object| {
        assert(zcu.pending_codegen_jobs.load(.monotonic) == 2); // only one codegen at a time (but the value is 2 because 1 is the base)
        try llvm_object.updateFunc(pt, func_index, air, &liveness);
        return error.BackendDoesNotProduceMir;
    }

    const lf = comp.bin_file orelse return error.NoLinkFile;

    // Just like LLVM, the SPIR-V backend can't multi-threaded due to SPIR-V design limitations.
    if (lf.cast(.spirv)) |spirv_file| {
        assert(zcu.pending_codegen_jobs.load(.monotonic) == 2); // only one codegen at a time (but the value is 2 because 1 is the base)
        spirv_file.updateFunc(pt, func_index, air, &liveness) catch |err| {
            switch (err) {
                error.OutOfMemory => comp.link_diags.setAllocFailure(),
            }
            return error.CodegenFail;
        };
        return error.BackendDoesNotProduceMir;
    }

    return codegen.generateFunction(lf, pt, zcu.navSrcLoc(nav), func_index, air, &liveness) catch |err| switch (err) {
        error.OutOfMemory,
        error.CodegenFail,
        => |e| return e,
        error.Overflow,
        error.RelocationNotByteAligned,
        => return zcu.codegenFail(nav, "unable to codegen: {s}", .{@errorName(err)}),
    };
}

fn printVerboseAir(
    pt: Zcu.PerThread,
    liveness: ?Air.Liveness,
    fqn: InternPool.NullTerminatedString,
    air: *const Air,
    w: *Io.Writer,
) Io.Writer.Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    try w.print("# Begin Function AIR: {f}:\n", .{fqn.fmt(ip)});
    try air.write(w, pt, liveness);
    try w.print("# End Function AIR: {f}\n\n", .{fqn.fmt(ip)});
}
