/// Unlike other linker implementations, `link.C` does not attempt to incrementally link its output,
/// because C has many language rules which make that impractical. Instead, we individually generate
/// each declaration (NAV), and the output is stitched together (alongside types and UAVs) in an
/// appropriate order in `flush`.
const C = @This();

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const fs = std.fs;
const Path = std.Build.Cache.Path;

const build_options = @import("build_options");
const Zcu = @import("../Zcu.zig");
const Module = @import("../Package/Module.zig");
const InternPool = @import("../InternPool.zig");
const Alignment = InternPool.Alignment;
const Compilation = @import("../Compilation.zig");
const codegen = @import("../codegen/c.zig");
const link = @import("../link.zig");
const trace = @import("../tracy.zig").trace;
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const AnyMir = @import("../codegen.zig").AnyMir;

base: link.File,

/// All the string bytes of rendered C code, all squished into one array. `String` is used to refer
/// to specific slices of this array, used for the rendered C code of an individual UAV/NAV/type.
///
/// During code generation for functions, a separate buffer is used, and the contents of that buffer
/// are copied into `string_bytes` when the function is emitted by `updateFunc`.
string_bytes: std.ArrayList(u8),

/// Like with `string_bytes`, we concatenate all type dependencies into one array, and slice into it
/// for specific groups of dependencies. These values are indices into `type_pool`, and thus also
/// into `types`. We store these instead of `InternPool.Index` because it lets us avoid some hash
/// map lookups in `flush`.
type_dependencies: std.ArrayList(link.ConstPool.Index),
/// For storing dependencies on "aligned" versions of types, we must associate each type with a
/// bitmask of required alignments. As with `type_dependencies`, we concatenate all such masks into
/// one array.
align_dependency_masks: std.ArrayList(u64),

/// All NAVs, regardless of whether they are functions or simple constants, are put in this map.
navs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, RenderedDecl),
/// All UAVs which may be referenced are in this map. The UAV alignment is not included in the
/// rendered C code stored here, because we don't know the alignment a UAV needs until `flush`.
uavs: std.AutoArrayHashMapUnmanaged(InternPool.Index, RenderedDecl),
/// Contains all types which are needed by some other rendered code. Does not contain any constants
/// other than types.
type_pool: link.ConstPool,
/// Indices are `link.ConstPool.Index` from `type_pool`. Contains rendered C code for every type
/// which may be referenced. Logic in `flush` will perform the appropriate topological sort to emit
/// these type definitions in an order which C allows.
types: std.ArrayList(RenderedType),

/// The set of big int types required by *any* generated code so far. These are always safe to emit,
/// so they do not participate in the dependency graph traversal in `flush`. Therefore, redundant
/// big-int types may be emitted under incremental compilation.
bigint_types: std.AutoArrayHashMapUnmanaged(codegen.CType.BigInt, void),

exported_navs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, String),
exported_uavs: std.AutoArrayHashMapUnmanaged(InternPool.Index, String),

/// A reference into `string_bytes`.
const String = extern struct {
    start: u32,
    len: u32,

    const empty: String = .{
        .start = 0,
        .len = 0,
    };

    fn get(s: String, c: *C) []const u8 {
        return c.string_bytes.items[s.start..][0..s.len];
    }
};

const CTypeDependencies = struct {
    len: u32,
    errunion_len: u32,
    fwd_len: u32,
    errunion_fwd_len: u32,
    aligned_fwd_len: u32,

    /// Index into `C.type_dependencies`. Starting at this index are:
    /// * `len` dependencies on complete types
    /// * `errunion_len` dependencies on complete error union types
    /// * `fwd_len` dependencies on forward-declared types
    /// * `errunion_fwd_len` dependencies on forward-declared error union types
    /// * `aligned_fwd_len` dependencies on aligned types
    type_start: u32,
    /// Index into `C.align_dependency_masks`. Starting at this index are `aligned_type_fwd_len`
    /// items containing the bitmasks for each aligned type (in `C.type_dependencies`).
    align_mask_start: u32,

    const Resolved = struct {
        type: []const link.ConstPool.Index,
        errunion_type: []const link.ConstPool.Index,
        type_fwd: []const link.ConstPool.Index,
        errunion_type_fwd: []const link.ConstPool.Index,
        aligned_type_fwd: []const link.ConstPool.Index,
        aligned_type_masks: []const u64,
    };

    fn get(td: *const CTypeDependencies, c: *const C) Resolved {
        const types_overlong = c.type_dependencies.items[td.type_start..];
        return .{
            .type = types_overlong[0..td.len],
            .errunion_type = types_overlong[td.len..][0..td.errunion_len],
            .type_fwd = types_overlong[td.len + td.errunion_len ..][0..td.fwd_len],
            .errunion_type_fwd = types_overlong[td.len + td.errunion_len + td.fwd_len ..][0..td.errunion_fwd_len],
            .aligned_type_fwd = types_overlong[td.len + td.errunion_len + td.fwd_len + td.errunion_fwd_len ..][0..td.aligned_fwd_len],
            .aligned_type_masks = c.align_dependency_masks.items[td.align_mask_start..][0..td.aligned_fwd_len],
        };
    }

    const empty: CTypeDependencies = .{
        .len = 0,
        .errunion_len = 0,
        .fwd_len = 0,
        .errunion_fwd_len = 0,
        .aligned_fwd_len = 0,
        .type_start = 0,
        .align_mask_start = 0,
    };
};

const RenderedDecl = struct {
    fwd_decl: String,
    code: String,
    ctype_deps: CTypeDependencies,
    need_uavs: std.AutoArrayHashMapUnmanaged(InternPool.Index, Alignment),
    need_tag_name_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
    need_never_tail_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void),
    need_never_inline_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void),

    const init: RenderedDecl = .{
        .fwd_decl = .empty,
        .code = .empty,
        .ctype_deps = .empty,
        .need_uavs = .empty,
        .need_tag_name_funcs = .empty,
        .need_never_tail_funcs = .empty,
        .need_never_inline_funcs = .empty,
    };

    fn deinit(rd: *RenderedDecl, gpa: Allocator) void {
        rd.need_uavs.deinit(gpa);
        rd.need_tag_name_funcs.deinit(gpa);
        rd.need_never_tail_funcs.deinit(gpa);
        rd.need_never_inline_funcs.deinit(gpa);
        rd.* = undefined;
    }

    /// We are about to re-render this declaration, but we want to reuse the existing buffers, so
    /// call `clearRetainCapacity` on the containers. Sets `fwd_decl` and `code` to `undefined`,
    /// because we shouldn't be using the old values any longer.
    fn clearRetainingCapacity(rd: *RenderedDecl) void {
        rd.fwd_decl = undefined;
        rd.code = undefined;
        rd.need_uavs.clearRetainingCapacity();
        rd.need_tag_name_funcs.clearRetainingCapacity();
        rd.need_never_tail_funcs.clearRetainingCapacity();
        rd.need_never_inline_funcs.clearRetainingCapacity();
    }
};

const RenderedType = struct {
    /// If this type lowers to an aggregate, this is a forward declaration of its struct/union tag.
    /// Otherwise, this is `.empty`.
    ///
    /// Populated immediately and never changes.
    fwd_decl: String,

    /// A forward declaration of an error union type with this type as its *payload*.
    ///
    /// Populated immediately and never changes.
    errunion_fwd_decl: String,

    /// If this type lowers to an aggregate, this is the struct/union definition.
    /// If this type lowers to a typedef, this is that typedef.
    /// Otherwise, this is `.empty`.
    definition: String,
    /// The `struct` definition for an error union type with this type as its *payload*.
    ///
    /// This string is empty iff the payload type does not have a resolved layout. If the layout is
    /// resolved, the error union struct is defined, even if the payload type lacks runtime bits.
    errunion_definition: String,

    /// Dependencies which must be satisfied before emitting the name of this type. As such, they
    /// must be satisfied before emitting `errunion_definition` or any aligned typedef.
    ///
    /// Populated immediately and never changes.
    deps: CTypeDependencies,

    /// Dependencies which must be satisfied before emitting `definition`.
    definition_deps: CTypeDependencies,
};

/// Only called by `link.ConstPool` due to `c.type_pool`, so `val` is always a type.
pub fn addConst(
    c: *C,
    pt: Zcu.PerThread,
    pool_index: link.ConstPool.Index,
    val: InternPool.Index,
) Allocator.Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.comp.gpa;
    assert(zcu.intern_pool.typeOf(val) == .type_type);
    assert(@intFromEnum(pool_index) == c.types.items.len);

    const ty: Type = .fromInterned(val);

    const fwd_decl: String = fwd_decl: {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.CType.render_defs.fwdDecl(ty, &aw.writer, zcu) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        break :fwd_decl .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    };

    const errunion_fwd_decl: String = errunion_fwd_decl: {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.CType.render_defs.errunionFwdDecl(ty, &aw.writer, zcu) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        break :errunion_fwd_decl .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    };

    try c.types.append(gpa, .{
        .fwd_decl = fwd_decl,
        .errunion_fwd_decl = errunion_fwd_decl,
        // This field will be populated just below.
        .deps = undefined,
        // The remaining fields will be populated later by either `updateConstIncomplete` or
        // `updateConstComplete` (it is guaranteed that at least one will be called).
        .definition = undefined,
        .errunion_definition = undefined,
        .definition_deps = undefined,
    });

    {
        // Find the dependencies required to just render the type `ty`.
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        var deps: codegen.CType.Dependencies = .empty;
        defer deps.deinit(gpa);
        _ = try codegen.CType.lower(ty, &deps, arena.allocator(), zcu);
        // This call may add more items to `c.types`.
        const type_deps = try c.addCTypeDependencies(pt, &deps);
        c.types.items[@intFromEnum(pool_index)].deps = type_deps;
    }
}

/// Only called by `link.ConstPool` due to `c.type_pool`, so `val` is always a type.
pub fn updateConstIncomplete(
    c: *C,
    pt: Zcu.PerThread,
    index: link.ConstPool.Index,
    val: InternPool.Index,
) Allocator.Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.comp.gpa;

    assert(zcu.intern_pool.typeOf(val) == .type_type);
    const ty: Type = .fromInterned(val);

    const rendered: *RenderedType = &c.types.items[@intFromEnum(index)];

    rendered.errunion_definition = .empty;
    rendered.definition_deps = .empty;
    rendered.definition = definition: {
        if (rendered.fwd_decl.len != 0) {
            // This is a struct or union type. We will never complete it, but we must forward
            // declare it to ensure that its first usage does not appear in a different scope.
            break :definition rendered.fwd_decl;
        }
        // Otherwise, we might need to `typedef` to `void`.
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.CType.render_defs.defineIncomplete(ty, &aw.writer, pt) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        break :definition .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    };
}
/// Only called by `link.ConstPool` due to `c.type_pool`, so `val` is always a type.
pub fn updateConst(
    c: *C,
    pt: Zcu.PerThread,
    index: link.ConstPool.Index,
    val: InternPool.Index,
) Allocator.Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.comp.gpa;

    assert(zcu.intern_pool.typeOf(val) == .type_type);
    const ty: Type = .fromInterned(val);

    const rendered: *RenderedType = &c.types.items[@intFromEnum(index)];

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var deps: codegen.CType.Dependencies = .empty;
    defer deps.deinit(gpa);

    {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.CType.render_defs.errunionDefineComplete(
            ty,
            &deps,
            arena.allocator(),
            &aw.writer,
            pt,
        ) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.OutOfMemory => |e| return e,
        };
        rendered.errunion_definition = .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    }

    deps.clearRetainingCapacity();

    {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.CType.render_defs.defineComplete(
            ty,
            &deps,
            arena.allocator(),
            &aw.writer,
            pt,
        ) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.OutOfMemory => |e| return e,
        };
        // Remove dependency on a forward declaration of ourselves; we're defining this type so that
        // forward declaration obviously exists!
        _ = deps.type_fwd.swapRemove(ty.toIntern());
        rendered.definition = .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    }

    {
        // This call invalidates `rendered`.
        const definition_deps = try c.addCTypeDependencies(pt, &deps);
        c.types.items[@intFromEnum(index)].definition_deps = definition_deps;
    }
}

fn addString(c: *C, vec: []const []const u8) Allocator.Error!String {
    const gpa = c.base.comp.gpa;

    var len: u32 = 0;
    for (vec) |s| len += @intCast(s.len);
    try c.string_bytes.ensureUnusedCapacity(gpa, len);

    const start: u32 = @intCast(c.string_bytes.items.len);
    for (vec) |s| c.string_bytes.appendSliceAssumeCapacity(s);
    assert(c.string_bytes.items.len == start + len);

    return .{ .start = start, .len = len };
}

pub fn open(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*C {
    return createEmpty(arena, comp, emit, options);
}

pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*C {
    const io = comp.io;
    const target = &comp.root_mod.resolved_target.result;
    assert(target.ofmt == .c);
    const optimize_mode = comp.root_mod.optimize_mode;
    const use_lld = build_options.have_llvm and comp.config.use_lld;
    const use_llvm = comp.config.use_llvm;
    const output_mode = comp.config.output_mode;

    // These are caught by `Compilation.Config.resolve`.
    assert(!use_lld);
    assert(!use_llvm);

    const file = try emit.root_dir.handle.createFile(io, emit.sub_path, .{
        // Truncation is done on `flush`.
        .truncate = false,
    });
    errdefer file.close(io);

    const c_file = try arena.create(C);

    c_file.* = .{
        .base = .{
            .tag = .c,
            .comp = comp,
            .emit = emit,
            .gc_sections = options.gc_sections orelse (optimize_mode != .Debug and output_mode != .Obj),
            .print_gc_sections = options.print_gc_sections,
            .stack_size = options.stack_size orelse 16777216,
            .allow_shlib_undefined = options.allow_shlib_undefined orelse false,
            .file = file,
            .build_id = options.build_id,
        },
        .string_bytes = .empty,
        .type_dependencies = .empty,
        .align_dependency_masks = .empty,
        .navs = .empty,
        .uavs = .empty,
        .type_pool = .empty,
        .types = .empty,
        .bigint_types = .empty,
        .exported_navs = .empty,
        .exported_uavs = .empty,
    };

    return c_file;
}

pub fn deinit(c: *C) void {
    const gpa = c.base.comp.gpa;

    for (c.navs.values()) |*r| r.deinit(gpa);
    for (c.uavs.values()) |*r| r.deinit(gpa);

    c.string_bytes.deinit(gpa);
    c.type_dependencies.deinit(gpa);
    c.align_dependency_masks.deinit(gpa);
    c.navs.deinit(gpa);
    c.uavs.deinit(gpa);
    c.type_pool.deinit(gpa);
    c.types.deinit(gpa);
    c.bigint_types.deinit(gpa);
    c.exported_navs.deinit(gpa);
    c.exported_uavs.deinit(gpa);
}

pub fn updateContainerType(
    c: *C,
    pt: Zcu.PerThread,
    ty: InternPool.Index,
    success: bool,
) link.File.UpdateContainerTypeError!void {
    try c.type_pool.updateContainerType(pt, .{ .c = c }, ty, success);
}

pub fn updateFunc(
    c: *C,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *AnyMir,
) Allocator.Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const nav = zcu.funcInfo(func_index).owner_nav;

    const rendered_decl: *RenderedDecl = rd: {
        const gop = try c.navs.getOrPut(gpa, nav);
        if (gop.found_existing) gop.value_ptr.deinit(gpa);
        break :rd gop.value_ptr;
    };
    c.navs.lockPointers();
    defer c.navs.unlockPointers();

    rendered_decl.* = .{
        .fwd_decl = try c.addString(&.{mir.c.fwd_decl}),
        .code = try c.addString(&.{ mir.c.code_header, mir.c.code }),
        .ctype_deps = try c.addCTypeDependencies(pt, &mir.c.ctype_deps),
        .need_uavs = mir.c.need_uavs.move(),
        .need_tag_name_funcs = mir.c.need_tag_name_funcs.move(),
        .need_never_tail_funcs = mir.c.need_never_tail_funcs.move(),
        .need_never_inline_funcs = mir.c.need_never_inline_funcs.move(),
    };

    const old_uavs_len = c.uavs.count();
    try c.uavs.ensureUnusedCapacity(gpa, rendered_decl.need_uavs.count());
    for (rendered_decl.need_uavs.keys()) |val| {
        const gop = c.uavs.getOrPutAssumeCapacity(val);
        if (gop.found_existing) {
            assert(gop.index < old_uavs_len);
        } else {
            assert(gop.index >= old_uavs_len);
        }
    }
    try c.updateNewUavs(pt, old_uavs_len);

    try c.type_pool.flushPending(pt, .{ .c = c });
}

pub fn updateNav(
    c: *C,
    pt: Zcu.PerThread,
    nav_index: InternPool.Nav.Index,
) Allocator.Error!void {
    const tracy = trace(@src());
    defer tracy.end();

    const gpa = c.base.comp.gpa;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    const nav = ip.getNav(nav_index);
    switch (ip.indexToKey(nav.resolved.?.value)) {
        .func => return,
        .@"extern" => {},
        else => {
            const nav_ty: Type = .fromInterned(nav.resolved.?.type);
            if (!nav_ty.hasRuntimeBits(zcu)) {
                if (c.navs.fetchSwapRemove(nav_index)) |kv| {
                    var old_rendered = kv.value;
                    old_rendered.deinit(gpa);
                }
                return;
            }
        },
    }

    const rendered_decl: *RenderedDecl = rd: {
        const gop = try c.navs.getOrPut(gpa, nav_index);
        if (gop.found_existing) {
            gop.value_ptr.clearRetainingCapacity();
        } else {
            gop.value_ptr.* = .init;
        }
        break :rd gop.value_ptr;
    };
    c.navs.lockPointers();
    defer c.navs.unlockPointers();

    {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();

        var dg: codegen.DeclGen = .{
            .gpa = gpa,
            .arena = arena.allocator(),
            .pt = pt,
            .mod = zcu.navFileScope(nav_index).mod.?,
            .error_msg = null,
            .owner_nav = nav_index.toOptional(),
            .is_naked_fn = false,
            .expected_block = null,
            .ctype_deps = .empty,
            .uavs = rendered_decl.need_uavs.move(),
        };

        defer {
            rendered_decl.need_uavs = dg.uavs.move();
            dg.ctype_deps.deinit(gpa);
        }

        rendered_decl.fwd_decl = fwd_decl: {
            var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
            defer c.string_bytes = aw.toArrayList();
            const start = aw.written().len;
            codegen.genDeclFwd(&dg, &aw.writer) catch |err| switch (err) {
                error.AnalysisFail => switch (zcu.codegenFailMsg(nav_index, dg.error_msg.?)) {
                    error.CodegenFail => return,
                    error.OutOfMemory => |e| return e,
                },
                error.WriteFailed, error.OutOfMemory => return error.OutOfMemory,
            };
            break :fwd_decl .{
                .start = @intCast(start),
                .len = @intCast(aw.written().len - start),
            };
        };

        rendered_decl.code = code: {
            var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
            defer c.string_bytes = aw.toArrayList();
            const start = aw.written().len;
            codegen.genDecl(&dg, &aw.writer) catch |err| switch (err) {
                error.AnalysisFail => switch (zcu.codegenFailMsg(nav_index, dg.error_msg.?)) {
                    error.CodegenFail => return,
                    error.OutOfMemory => |e| return e,
                },
                error.WriteFailed, error.OutOfMemory => return error.OutOfMemory,
            };
            break :code .{
                .start = @intCast(start),
                .len = @intCast(aw.written().len - start),
            };
        };

        rendered_decl.ctype_deps = try c.addCTypeDependencies(pt, &dg.ctype_deps);
    }

    const old_uavs_len = c.uavs.count();
    try c.uavs.ensureUnusedCapacity(gpa, rendered_decl.need_uavs.count());
    for (rendered_decl.need_uavs.keys()) |val| {
        const gop = c.uavs.getOrPutAssumeCapacity(val);
        if (gop.found_existing) {
            assert(gop.index < old_uavs_len);
        } else {
            assert(gop.index >= old_uavs_len);
        }
    }
    try c.updateNewUavs(pt, old_uavs_len);

    try c.type_pool.flushPending(pt, .{ .c = c });
}

/// Unlike `updateNav` and `updateFunc`, this does *not* add newly-discovered UAVs to `c.uavs`. The
/// caller is instead responsible for doing that (by iterating `rendered_decl.need_uavs`). However,
/// this function *does* still add newly-discovered *types* to `c.type_pool`.
///
/// This function does not accept an alignment for the UAV, because the alignment needed on a UAV is
/// not known until `flush` (since we need to have seen all uses of the UAV first). Instead, `flush`
/// will prefix the UAV definition with an appropriate alignment annotation if necessary.
fn updateUav(
    c: *C,
    pt: Zcu.PerThread,
    val: Value,
    rendered_decl: *RenderedDecl,
) Allocator.Error!void {
    const tracy = trace(@src());
    defer tracy.end();

    const gpa = c.base.comp.gpa;

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var dg: codegen.DeclGen = .{
        .gpa = gpa,
        .arena = arena.allocator(),
        .pt = pt,
        .mod = pt.zcu.root_mod,
        .error_msg = null,
        .owner_nav = .none,
        .is_naked_fn = false,
        .expected_block = null,
        .ctype_deps = .empty,
        .uavs = .empty,
    };
    defer {
        rendered_decl.need_uavs = dg.uavs.move();
        dg.ctype_deps.deinit(gpa);
    }

    rendered_decl.fwd_decl = fwd_decl: {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.genDeclValueFwd(&dg, &aw.writer, .{
            .name = .{ .constant = val },
            .@"const" = true,
            .@"threadlocal" = false,
            .init_val = val,
        }) catch |err| switch (err) {
            error.AnalysisFail => {
                @panic("TODO: CBE error.AnalysisFail on uav");
            },
            error.WriteFailed, error.OutOfMemory => return error.OutOfMemory,
        };
        break :fwd_decl .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    };

    rendered_decl.code = code: {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.genDeclValue(&dg, &aw.writer, .{
            .name = .{ .constant = val },
            .@"const" = true,
            .@"threadlocal" = false,
            .init_val = val,
        }) catch |err| switch (err) {
            error.AnalysisFail => {
                @panic("TODO: CBE error.AnalysisFail on uav");
            },
            error.WriteFailed, error.OutOfMemory => return error.OutOfMemory,
        };
        break :code .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    };

    rendered_decl.ctype_deps = try c.addCTypeDependencies(pt, &dg.ctype_deps);
}

pub fn updateLineNumber(c: *C, pt: Zcu.PerThread, ti_id: InternPool.TrackedInst.Index) error{}!void {
    // The C backend does not currently emit "#line" directives. Even if it did, it would not be
    // capable of updating those line numbers without re-generating the entire declaration.
    _ = c;
    _ = pt;
    _ = ti_id;
}

pub fn flush(c: *C, arena: Allocator, tid: Zcu.PerThread.Id, prog_node: std.Progress.Node) link.File.FlushError!void {
    const tracy = trace(@src());
    defer tracy.end();

    const sub_prog_node = prog_node.start("Flush Module", 0);
    defer sub_prog_node.end();

    const comp = c.base.comp;
    const diags = &comp.link_diags;
    const gpa = comp.gpa;
    const io = comp.io;
    const zcu = c.base.comp.zcu.?;
    const ip = &zcu.intern_pool;
    const target = zcu.getTarget();
    const pt: Zcu.PerThread = .activate(zcu, tid);
    defer pt.deactivate();

    // If it's somehow not made it into the pool, we need to generate the type `[:0]const u8` for
    // error names.
    const slice_const_u8_sentinel_0_pool_index = try c.type_pool.get(
        pt,
        .{ .c = c },
        .slice_const_u8_sentinel_0_type,
    );
    try c.type_pool.flushPending(pt, .{ .c = c });

    // Find the set of referenced NAVs; these are the ones we'll emit. It is important in this
    // backend that we only emit referenced NAVs, because other ones may contain code from past
    // incremental updates which is invalid C (due to e.g. types changing). Machine code backends
    // don't have this problem because there are, of course, no type checking performed when you
    // *execute* a binary!
    var need_navs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void) = .empty;
    defer need_navs.deinit(gpa);
    {
        const unit_references = try zcu.resolveReferences();
        for (c.navs.keys()) |nav| {
            const nav_val = ip.getNav(nav).resolved.?.value;
            const check_unit: ?InternPool.AnalUnit = switch (ip.indexToKey(nav_val)) {
                else => .wrap(.{ .nav_val = nav }),
                .func => .wrap(.{ .func = nav_val }),
                // TODO: this is a hack to deal with the fact that there's currently no good way to
                // know which `extern`s are alive. This can and will break in certain patterns of
                // incremental update. We kind of need to think a bit more about how the frontend
                // actually represents `extern`, it's a bit awkward right now.
                .@"extern" => null,
            };
            if (check_unit) |u| {
                if (!unit_references.contains(u)) continue;
            }
            try need_navs.putNoClobber(gpa, nav, {});
        }
    }

    // Using our knowledge of which NAVs are referenced, we now need to discover the set of UAVs and
    // C types which are referenced (and hence must be emitted). As above, this is necessary to make
    // sure we only emit valid C code.
    //
    // At the same time, we will discover the set of lazy functions which are referenced.

    var need_uavs: std.AutoArrayHashMapUnmanaged(InternPool.Index, Alignment) = .empty;
    defer need_uavs.deinit(gpa);

    var need_types: std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, void) = .empty;
    defer need_types.deinit(gpa);
    var need_errunion_types: std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, void) = .empty;
    defer need_errunion_types.deinit(gpa);
    var need_aligned_types: std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, u64) = .empty;
    defer need_aligned_types.deinit(gpa);

    var need_tag_name_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Index, void) = .empty;
    defer need_tag_name_funcs.deinit(gpa);

    var need_never_tail_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void) = .empty;
    defer need_never_tail_funcs.deinit(gpa);

    var need_never_inline_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void) = .empty;
    defer need_never_inline_funcs.deinit(gpa);

    // As mentioned above, we need this type for error names.
    try need_types.put(gpa, slice_const_u8_sentinel_0_pool_index, {});

    // Every exported NAV should have been discovered via `zcu.resolveReferences`...
    for (c.exported_navs.keys()) |nav| assert(need_navs.contains(nav));
    // ...but we *do* need to add exported UAVs to the set.
    try need_uavs.ensureUnusedCapacity(gpa, c.exported_uavs.count());
    for (c.exported_uavs.keys()) |uav| {
        const gop = need_uavs.getOrPutAssumeCapacity(uav);
        if (!gop.found_existing) gop.value_ptr.* = .none;
    }

    // For every referenced NAV, some UAVs, C types, and lazy functions may be referenced.
    for (need_navs.keys()) |nav| {
        const rendered = c.navs.getPtr(nav).?;
        try mergeNeededCTypes(
            c,
            &need_types,
            &need_errunion_types,
            &need_aligned_types,
            &rendered.ctype_deps,
        );
        try mergeNeededUavs(zcu, &need_uavs, &rendered.need_uavs);

        try need_tag_name_funcs.ensureUnusedCapacity(gpa, rendered.need_tag_name_funcs.count());
        for (rendered.need_tag_name_funcs.keys()) |enum_type| {
            need_tag_name_funcs.putAssumeCapacity(enum_type, {});
        }

        try need_never_tail_funcs.ensureUnusedCapacity(gpa, rendered.need_never_tail_funcs.count());
        for (rendered.need_never_tail_funcs.keys()) |fn_nav| {
            need_never_tail_funcs.putAssumeCapacity(fn_nav, {});
        }

        try need_never_inline_funcs.ensureUnusedCapacity(gpa, rendered.need_never_inline_funcs.count());
        for (rendered.need_never_inline_funcs.keys()) |fn_nav| {
            need_never_inline_funcs.putAssumeCapacity(fn_nav, {});
        }
    }

    // UAVs may reference other UAVs or C types.
    {
        var index: usize = 0;
        while (need_uavs.count() > index) : (index += 1) {
            const val = need_uavs.keys()[index];
            const rendered = c.uavs.getPtr(val).?;
            try mergeNeededCTypes(
                c,
                &need_types,
                &need_errunion_types,
                &need_aligned_types,
                &rendered.ctype_deps,
            );
            try mergeNeededUavs(zcu, &need_uavs, &rendered.need_uavs);
        }
    }

    // Finally, C types may reference other C types.
    {
        var index: usize = 0;
        var errunion_index: usize = 0;
        var aligned_index: usize = 0;
        while (true) {
            if (index < need_types.count()) {
                const pool_index = need_types.keys()[index];
                const rendered = &c.types.items[@intFromEnum(pool_index)];
                try mergeNeededCTypes(
                    c,
                    &need_types,
                    &need_errunion_types,
                    &need_aligned_types,
                    &rendered.definition_deps, // we're tasked with emitting the *definition* of this type
                );
                index += 1;
                continue;
            }

            if (errunion_index < need_errunion_types.count()) {
                const payload_pool_index = need_errunion_types.keys()[errunion_index];
                const rendered = &c.types.items[@intFromEnum(payload_pool_index)];
                try mergeNeededCTypes(
                    c,
                    &need_types,
                    &need_errunion_types,
                    &need_aligned_types,
                    &rendered.deps, // the error union type requires emitting this type's *name*
                );
                errunion_index += 1;
                continue;
            }

            if (aligned_index < need_aligned_types.count()) {
                const pool_index = need_aligned_types.keys()[aligned_index];
                const rendered = &c.types.items[@intFromEnum(pool_index)];
                try mergeNeededCTypes(
                    c,
                    &need_types,
                    &need_errunion_types,
                    &need_aligned_types,
                    &rendered.deps, // an aligned typedef requires emitting this type's *name*
                );
                aligned_index += 1;
                continue;
            }

            break;
        }
    }

    // Now that we know which types are required, generate aligned typedefs. One buffer per aligned
    // type, with *all* aligned typedefs for that type.
    const aligned_type_strings = try arena.alloc([]const u8, need_aligned_types.count());
    {
        var aw: std.Io.Writer.Allocating = .init(gpa);
        defer aw.deinit();
        var unused_deps: codegen.CType.Dependencies = .empty;
        defer unused_deps.deinit(gpa);
        for (
            need_aligned_types.keys(),
            need_aligned_types.values(),
            aligned_type_strings,
        ) |pool_index, align_mask, *str_out| {
            const ty: Type = .fromInterned(pool_index.val(&c.type_pool));
            const has_layout = c.types.items[@intFromEnum(pool_index)].errunion_definition.len > 0;
            for (0..@bitSizeOf(@TypeOf(align_mask))) |bit_index| {
                switch (@as(u1, @truncate(align_mask >> @intCast(bit_index)))) {
                    0 => continue,
                    1 => {},
                }
                codegen.CType.render_defs.defineAligned(
                    ty,
                    .fromLog2Units(@intCast(bit_index)),
                    has_layout,
                    &unused_deps,
                    arena,
                    &aw.writer,
                    pt,
                ) catch |err| switch (err) {
                    error.WriteFailed => return error.OutOfMemory,
                    error.OutOfMemory => |e| return e,
                };
            }
            str_out.* = try arena.dupe(u8, aw.written());
            aw.clearRetainingCapacity();
        }
    }

    // We have discovered the full set of NAVs, UAVs, and types we need to emit, and will now begin
    // to build the output buffer. Our strategy is to emit the C source in this order:
    //
    // * ABI defines and `#include "zig.h"`
    // * Big-int type definitions
    // * Other CType definitions (traversing the dependency graph to sort topologically)
    // * Global assembly
    // * UAV exports
    // * NAV exports
    // * UAV forward declarations
    // * NAV forward declarations
    // * Lazy declarations (error names; @tagName functions; never_tail/never_inline wrappers)
    // * UAV definitions
    // * NAV definitions
    //
    // Most of these sections are order-independent within themselves, with the exception of the
    // type definitions, which must be ordered to avoid a struct/union from embedding a type which
    // is currently incomplete.
    //
    // When emitting UAV forward declarations, if the UAV requires alignment, we must prefix it with
    // an alignment annotation. We couldn't emit the alignment into the UAV's `RenderedDecl` because
    // we couldn't have known the required alignment until now!

    var f: Flush = .{ .all_buffers = .empty, .file_size = 0 };
    defer f.deinit(gpa);

    // We know exactly what we'll be emitting, so can reserve capacity for all of our buffers!

    try f.all_buffers.ensureUnusedCapacity(gpa, 3 + // ABI defines and `#include "zig.h"`
        1 + // Big-int type definitions
        need_types.count() + // `RenderedType.fwd_decl` (worst-case)
        need_types.count() + // `RenderedType.definition`
        need_errunion_types.count() + // `RenderedType.errunion_fwd_decl` (worst-case)
        need_errunion_types.count() + // `RenderedType.errunion_definition`
        need_aligned_types.count() + // `aligned_type_strings`
        1 + // Global assembly
        c.exported_uavs.count() + // UAV export block
        c.exported_navs.count() + // NAV export block
        need_uavs.count() + // UAV forward declarations
        need_navs.count() + // NAV forward declarations
        1 + // Lazy declarations
        need_uavs.count() * 3 + // UAV definitions ("static ", "zig_align(4)", "<definition body>")
        need_navs.count() * 2); // NAV definitions ("static ", "<definition body>")

    // ABI defines and `#include "zig.h"`
    switch (target.abi) {
        .msvc, .itanium => f.appendBufAssumeCapacity("#define ZIG_TARGET_ABI_MSVC\n"),
        else => {},
    }
    f.appendBufAssumeCapacity(try std.fmt.allocPrint(
        arena,
        "#define ZIG_TARGET_MAX_INT_ALIGNMENT {d}\n",
        .{target.cMaxIntAlignment()},
    ));
    f.appendBufAssumeCapacity(
        \\#include "zig.h"
        \\
    );

    // Big-int type definitions
    var bigint_aw: std.Io.Writer.Allocating = .init(gpa);
    defer bigint_aw.deinit();
    for (c.bigint_types.keys()) |bigint| {
        codegen.CType.render_defs.defineBigInt(bigint, &bigint_aw.writer, zcu) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
    }
    f.appendBufAssumeCapacity(bigint_aw.written());

    // CType definitions
    {
        var ft: FlushTypes = .{
            .c = c,
            .f = &f,
            .aligned_types = &need_aligned_types,
            .aligned_type_strings = aligned_type_strings,
            .status = .empty,
            .errunion_status = .empty,
            .aligned_status = .empty,
        };
        defer {
            ft.status.deinit(gpa);
            ft.errunion_status.deinit(gpa);
            ft.aligned_status.deinit(gpa);
        }
        try ft.status.ensureUnusedCapacity(gpa, need_types.count());
        try ft.errunion_status.ensureUnusedCapacity(gpa, need_errunion_types.count());
        try ft.aligned_status.ensureUnusedCapacity(gpa, need_aligned_types.count());

        for (need_types.keys()) |pool_index| {
            ft.doType(pool_index);
        }
        for (need_errunion_types.keys()) |pool_index| {
            ft.doErrunionType(pool_index);
        }
        for (need_aligned_types.keys()) |pool_index| {
            ft.doAlignedTypeFwd(pool_index);
        }
    }

    // Global assembly
    var asm_aw: std.Io.Writer.Allocating = .init(gpa);
    defer asm_aw.deinit();
    codegen.genGlobalAsm(zcu, &asm_aw.writer) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
    };
    f.appendBufAssumeCapacity(asm_aw.written());

    var export_names: std.AutoHashMapUnmanaged(InternPool.NullTerminatedString, void) = .empty;
    defer export_names.deinit(gpa);
    try export_names.ensureTotalCapacity(gpa, @intCast(zcu.single_exports.count()));
    for (zcu.single_exports.values()) |export_index| {
        export_names.putAssumeCapacity(export_index.ptr(zcu).opts.name, {});
    }
    for (zcu.multi_exports.values()) |info| {
        try export_names.ensureUnusedCapacity(gpa, info.len);
        for (zcu.all_exports.items[info.index..][0..info.len]) |@"export"| {
            export_names.putAssumeCapacity(@"export".opts.name, {});
        }
    }

    // UAV export block
    for (c.exported_uavs.values()) |code| {
        f.appendBufAssumeCapacity(code.get(c));
    }

    // NAV export block
    for (c.exported_navs.values()) |code| {
        f.appendBufAssumeCapacity(code.get(c));
    }

    // UAV forward declarations
    for (need_uavs.keys()) |val| {
        if (c.exported_uavs.contains(val)) continue; // the export was the declaration
        const fwd_decl = c.uavs.getPtr(val).?.fwd_decl;
        f.appendBufAssumeCapacity(fwd_decl.get(c));
    }

    // NAV forward declarations
    for (need_navs.keys()) |nav| {
        if (c.exported_navs.contains(nav)) continue; // the export was the declaration
        switch (ip.indexToKey(ip.getNav(nav).resolved.?.value)) {
            .@"extern" => |e| if (export_names.contains(e.name)) continue,
            else => {},
        }
        const fwd_decl = c.navs.getPtr(nav).?.fwd_decl;
        f.appendBufAssumeCapacity(fwd_decl.get(c));
    }

    // Lazy declarations
    var lazy_decls_aw: std.Io.Writer.Allocating = .init(gpa);
    defer lazy_decls_aw.deinit();
    {
        var lazy_dg: codegen.DeclGen = .{
            .gpa = gpa,
            .arena = arena,
            .pt = pt,
            .mod = pt.zcu.root_mod,
            .owner_nav = .none,
            .is_naked_fn = false,
            .expected_block = null,
            .error_msg = null,
            .ctype_deps = .empty,
            .uavs = .empty,
        };
        defer {
            assert(lazy_dg.uavs.count() == 0);
            lazy_dg.ctype_deps.deinit(gpa);
        }
        const slice_const_u8_sentinel_0_cty: codegen.CType = try .lower(
            .slice_const_u8_sentinel_0,
            &lazy_dg.ctype_deps,
            arena,
            zcu,
        );
        const slice_const_u8_sentinel_0_name = try std.fmt.allocPrint(
            arena,
            "{f}",
            .{slice_const_u8_sentinel_0_cty.fmtTypeName(zcu)},
        );
        codegen.genErrDecls(zcu, &lazy_decls_aw.writer, slice_const_u8_sentinel_0_name) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        for (need_tag_name_funcs.keys()) |enum_ty_ip| {
            const enum_ty: Type = .fromInterned(enum_ty_ip);
            const enum_cty: codegen.CType = try .lower(
                enum_ty,
                &lazy_dg.ctype_deps,
                arena,
                zcu,
            );
            codegen.genTagNameFn(
                zcu,
                &lazy_decls_aw.writer,
                slice_const_u8_sentinel_0_name,
                enum_ty,
                try std.fmt.allocPrint(arena, "{f}", .{enum_cty.fmtTypeName(zcu)}),
            ) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
            };
        }
        for (need_never_tail_funcs.keys()) |fn_nav| {
            codegen.genLazyCallModifierFn(&lazy_dg, fn_nav, .never_tail, &lazy_decls_aw.writer) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                error.OutOfMemory => |e| return e,
                error.AnalysisFail => unreachable,
            };
        }
        for (need_never_inline_funcs.keys()) |fn_nav| {
            codegen.genLazyCallModifierFn(&lazy_dg, fn_nav, .never_inline, &lazy_decls_aw.writer) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                error.OutOfMemory => |e| return e,
                error.AnalysisFail => unreachable,
            };
        }
    }
    f.appendBufAssumeCapacity(lazy_decls_aw.written());

    // UAV definitions
    for (need_uavs.keys(), need_uavs.values()) |val, overalign| {
        const code = c.uavs.getPtr(val).?.code;
        if (code.len == 0) continue;
        if (!c.exported_uavs.contains(val)) {
            f.appendBufAssumeCapacity("static ");
        }
        if (overalign != .none) {
            // As long as `Alignment` isn't too big, it's reasonable to just generate all possible
            // alignment annotations statically into a LUT, which avoids allocating strings on this
            // path.
            comptime assert(@bitSizeOf(Alignment) < 8);
            const table_len = (1 << @bitSizeOf(Alignment)) - 1;
            const table: [table_len][]const u8 = comptime table: {
                @setEvalBranchQuota(16_000);
                var table: [table_len][]const u8 = undefined;
                for (&table, 0..) |*str, log2_align| {
                    const byte_align = Alignment.fromLog2Units(log2_align).toByteUnits().?;
                    str.* = std.fmt.comptimePrint("zig_align({d}) ", .{byte_align});
                }
                break :table table;
            };
            f.appendBufAssumeCapacity(table[overalign.toLog2Units()]);
        }
        f.appendBufAssumeCapacity(code.get(c));
    }

    // NAV definitions
    for (need_navs.keys()) |nav| {
        const code = c.navs.getPtr(nav).?.code;
        if (code.len == 0) continue;
        if (!c.exported_navs.contains(nav)) {
            const is_extern = ip.indexToKey(ip.getNav(nav).resolved.?.value) == .@"extern";
            f.appendBufAssumeCapacity(if (is_extern) "zig_extern " else "static ");
        }
        f.appendBufAssumeCapacity(code.get(c));
    }

    // We've collected all of our buffers; it's now time to actually write the file!
    const file = c.base.file.?;
    file.setLength(io, f.file_size) catch |err| return diags.fail("failed to allocate file: {t}", .{err});
    var fw = file.writer(io, &.{});
    var w = &fw.interface;
    w.writeVecAll(f.all_buffers.items) catch |err| switch (err) {
        error.WriteFailed => return diags.fail("failed to write to '{f}': {s}", .{
            std.fmt.alt(c.base.emit, .formatEscapeChar), @errorName(fw.err.?),
        }),
    };
}

const Flush = struct {
    /// We collect a list of buffers to write, and write them all at once with pwritev 😎
    all_buffers: std.ArrayList([]const u8),
    /// Keeps track of the total bytes of `all_buffers`.
    file_size: u64,

    fn appendBufAssumeCapacity(f: *Flush, buf: []const u8) void {
        if (buf.len == 0) return;
        f.all_buffers.appendAssumeCapacity(buf);
        f.file_size += buf.len;
    }

    fn deinit(f: *Flush, gpa: Allocator) void {
        f.all_buffers.deinit(gpa);
    }
};

pub fn updateExports(
    c: *C,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) Allocator.Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var dg: codegen.DeclGen = .{
        .gpa = gpa,
        .arena = arena.allocator(),
        .pt = pt,
        .mod = zcu.root_mod,
        .owner_nav = .none,
        .is_naked_fn = false,
        .expected_block = null,
        .error_msg = null,
        .ctype_deps = .empty,
        .uavs = .empty,
    };
    defer {
        assert(dg.uavs.count() == 0);
        dg.ctype_deps.deinit(gpa);
    }

    const code: String = code: {
        var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, &c.string_bytes);
        defer c.string_bytes = aw.toArrayList();
        const start = aw.written().len;
        codegen.genExports(&dg, &aw.writer, exported, export_indices) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.OutOfMemory => |e| return e,
        };
        break :code .{
            .start = @intCast(start),
            .len = @intCast(aw.written().len - start),
        };
    };
    switch (exported) {
        .nav => |nav| try c.exported_navs.put(gpa, nav, code),
        .uav => |uav| try c.exported_uavs.put(gpa, uav, code),
    }
}

pub fn deleteExport(
    self: *C,
    exported: Zcu.Exported,
    _: InternPool.NullTerminatedString,
) void {
    switch (exported) {
        .nav => |nav| _ = self.exported_navs.swapRemove(nav),
        .uav => |uav| _ = self.exported_uavs.swapRemove(uav),
    }
}

fn mergeNeededCTypes(
    c: *C,
    need_types: *std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, void),
    need_errunion_types: *std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, void),
    need_aligned_types: *std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, u64),
    deps: *const CTypeDependencies,
) Allocator.Error!void {
    const gpa = c.base.comp.gpa;

    const resolved = deps.get(c);

    try need_types.ensureUnusedCapacity(gpa, resolved.type.len + resolved.type_fwd.len);
    try need_errunion_types.ensureUnusedCapacity(gpa, resolved.errunion_type.len + resolved.errunion_type_fwd.len);
    try need_aligned_types.ensureUnusedCapacity(gpa, resolved.aligned_type_fwd.len);

    for (resolved.type) |index| need_types.putAssumeCapacity(index, {});
    for (resolved.type_fwd) |index| need_types.putAssumeCapacity(index, {});

    for (resolved.errunion_type) |index| need_errunion_types.putAssumeCapacity(index, {});
    for (resolved.errunion_type_fwd) |index| need_errunion_types.putAssumeCapacity(index, {});

    for (resolved.aligned_type_fwd, resolved.aligned_type_masks) |ty_index, align_mask| {
        const gop = need_aligned_types.getOrPutAssumeCapacity(ty_index);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* |= align_mask;
    }
}

fn mergeNeededUavs(
    zcu: *const Zcu,
    global: *std.AutoArrayHashMapUnmanaged(InternPool.Index, Alignment),
    new: *const std.AutoArrayHashMapUnmanaged(InternPool.Index, Alignment),
) Allocator.Error!void {
    const gpa = zcu.comp.gpa;

    try global.ensureUnusedCapacity(gpa, new.count());
    for (new.keys(), new.values()) |uav_val, need_align| {
        const gop = global.getOrPutAssumeCapacity(uav_val);
        if (!gop.found_existing) gop.value_ptr.* = .none;

        if (need_align != .none) {
            const cur_align = switch (gop.value_ptr.*) {
                .none => Value.fromInterned(uav_val).typeOf(zcu).abiAlignment(zcu),
                else => |a| a,
            };
            if (need_align.compareStrict(.gt, cur_align)) {
                gop.value_ptr.* = need_align;
            }
        }
    }
}

fn addCTypeDependencies(
    c: *C,
    pt: Zcu.PerThread,
    deps: *const codegen.CType.Dependencies,
) Allocator.Error!CTypeDependencies {
    const gpa = pt.zcu.comp.gpa;

    try c.bigint_types.ensureUnusedCapacity(gpa, deps.bigint.count());
    for (deps.bigint.keys()) |bigint| c.bigint_types.putAssumeCapacity(bigint, {});

    const type_start = c.type_dependencies.items.len;
    const errunion_type_start = type_start + deps.type.count();
    const type_fwd_start = errunion_type_start + deps.errunion_type.count();
    const errunion_type_fwd_start = type_fwd_start + deps.type_fwd.count();
    const aligned_type_fwd_start = errunion_type_fwd_start + deps.errunion_type_fwd.count();
    try c.type_dependencies.appendNTimes(gpa, undefined, deps.type.count() +
        deps.errunion_type.count() +
        deps.type_fwd.count() +
        deps.errunion_type_fwd.count() +
        deps.aligned_type_fwd.count());

    const align_mask_start = c.align_dependency_masks.items.len;
    try c.align_dependency_masks.appendSlice(gpa, deps.aligned_type_fwd.values());

    for (deps.type.keys(), type_start..) |ty, i| {
        const pool_index = try c.type_pool.get(pt, .{ .c = c }, ty);
        c.type_dependencies.items[i] = pool_index;
    }

    for (deps.errunion_type.keys(), errunion_type_start..) |ty, i| {
        const pool_index = try c.type_pool.get(pt, .{ .c = c }, ty);
        c.type_dependencies.items[i] = pool_index;
    }

    for (deps.type_fwd.keys(), type_fwd_start..) |ty, i| {
        const pool_index = try c.type_pool.get(pt, .{ .c = c }, ty);
        c.type_dependencies.items[i] = pool_index;
    }

    for (deps.errunion_type_fwd.keys(), errunion_type_fwd_start..) |ty, i| {
        const pool_index = try c.type_pool.get(pt, .{ .c = c }, ty);
        c.type_dependencies.items[i] = pool_index;
    }

    for (deps.aligned_type_fwd.keys(), aligned_type_fwd_start..) |ty, i| {
        const pool_index = try c.type_pool.get(pt, .{ .c = c }, ty);
        c.type_dependencies.items[i] = pool_index;
    }

    return .{
        .len = @intCast(deps.type.count()),
        .errunion_len = @intCast(deps.errunion_type.count()),
        .fwd_len = @intCast(deps.type_fwd.count()),
        .errunion_fwd_len = @intCast(deps.errunion_type_fwd.count()),
        .aligned_fwd_len = @intCast(deps.aligned_type_fwd.count()),
        .type_start = @intCast(type_start),
        .align_mask_start = @intCast(align_mask_start),
    };
}

fn updateNewUavs(c: *C, pt: Zcu.PerThread, old_uavs_len: usize) Allocator.Error!void {
    const gpa = pt.zcu.comp.gpa;
    var index = old_uavs_len;
    while (index < c.uavs.count()) : (index += 1) {
        // `new_uavs` is UAVs discovered while lowering *this* UAV.
        const new_uavs: []const InternPool.Index = new: {
            c.uavs.lockPointers();
            defer c.uavs.unlockPointers();
            const val: Value = .fromInterned(c.uavs.keys()[index]);
            const rendered_decl = &c.uavs.values()[index];
            rendered_decl.* = .init;
            try c.updateUav(pt, val, rendered_decl);
            break :new rendered_decl.need_uavs.keys();
        };
        try c.uavs.ensureUnusedCapacity(gpa, new_uavs.len);
        for (new_uavs) |val| {
            const gop = c.uavs.getOrPutAssumeCapacity(val);
            if (!gop.found_existing) {
                assert(gop.index > index);
            }
        }
    }
}

const FlushTypes = struct {
    c: *C,
    f: *Flush,

    aligned_types: *const std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, u64),
    aligned_type_strings: []const []const u8,

    status: std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, bool),
    errunion_status: std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, bool),
    aligned_status: std.AutoArrayHashMapUnmanaged(link.ConstPool.Index, void),

    fn processDeps(ft: *FlushTypes, deps: *const CTypeDependencies) void {
        const resolved = deps.get(ft.c);
        for (resolved.type) |pool_index| ft.doType(pool_index);
        for (resolved.type_fwd) |pool_index| ft.doTypeFwd(pool_index);
        for (resolved.errunion_type) |pool_index| ft.doErrunionType(pool_index);
        for (resolved.errunion_type_fwd) |pool_index| ft.doErrunionTypeFwd(pool_index);
        for (resolved.aligned_type_fwd) |pool_index| ft.doAlignedTypeFwd(pool_index);
    }
    fn processDepsAsFwd(ft: *FlushTypes, deps: *const CTypeDependencies) void {
        const resolved = deps.get(ft.c);
        for (resolved.type) |pool_index| ft.doTypeFwd(pool_index);
        for (resolved.type_fwd) |pool_index| ft.doTypeFwd(pool_index);
        for (resolved.errunion_type) |pool_index| ft.doErrunionTypeFwd(pool_index);
        for (resolved.errunion_type_fwd) |pool_index| ft.doErrunionTypeFwd(pool_index);
        for (resolved.aligned_type_fwd) |pool_index| ft.doAlignedTypeFwd(pool_index);
    }

    fn doAlignedTypeFwd(ft: *FlushTypes, pool_index: link.ConstPool.Index) void {
        const c = ft.c;
        if (ft.aligned_status.contains(pool_index)) return;
        if (ft.aligned_types.getIndex(pool_index)) |i| {
            const rendered = &c.types.items[@intFromEnum(pool_index)];
            ft.processDepsAsFwd(&rendered.deps);
            ft.f.appendBufAssumeCapacity(ft.aligned_type_strings[i]);
        }
        ft.aligned_status.putAssumeCapacity(pool_index, {});
    }
    fn doTypeFwd(ft: *FlushTypes, pool_index: link.ConstPool.Index) void {
        const c = ft.c;
        if (ft.status.contains(pool_index)) return;
        const rendered = &c.types.items[@intFromEnum(pool_index)];
        if (rendered.fwd_decl.len > 0) {
            ft.f.appendBufAssumeCapacity(rendered.fwd_decl.get(c));
            ft.status.putAssumeCapacityNoClobber(pool_index, false);
        } else {
            ft.processDepsAsFwd(&rendered.definition_deps);
            const gop = ft.status.getOrPutAssumeCapacity(pool_index);
            if (!gop.found_existing) {
                gop.value_ptr.* = false;
                ft.f.appendBufAssumeCapacity(rendered.definition.get(c));
            }
        }
    }
    fn doType(ft: *FlushTypes, pool_index: link.ConstPool.Index) void {
        const c = ft.c;
        if (ft.status.get(pool_index)) |completed| {
            if (completed) return;
        }
        const rendered = &c.types.items[@intFromEnum(pool_index)];
        ft.processDeps(&rendered.definition_deps);
        if (rendered.fwd_decl.len == 0 and ft.status.contains(pool_index)) {
            // `doTypeFwd` already rendered the defintion, we just had to complete the type by
            // fully resolving its dependencies.
        } else if (rendered.definition.len > 0) {
            ft.f.appendBufAssumeCapacity(rendered.definition.get(c));
        } else if (!ft.status.contains(pool_index)) {
            // The type will never be completed, but it must be forward declared to avoid it being
            // declared in the wrong scope.
            ft.f.appendBufAssumeCapacity(rendered.fwd_decl.get(c));
        }
        ft.status.putAssumeCapacity(pool_index, true);
    }
    fn doErrunionTypeFwd(ft: *FlushTypes, pool_index: link.ConstPool.Index) void {
        const c = ft.c;
        const gop = ft.errunion_status.getOrPutAssumeCapacity(pool_index);
        if (gop.found_existing) return;
        const rendered = &c.types.items[@intFromEnum(pool_index)];
        ft.f.appendBufAssumeCapacity(rendered.errunion_fwd_decl.get(c));
        gop.value_ptr.* = false;
    }
    fn doErrunionType(ft: *FlushTypes, pool_index: link.ConstPool.Index) void {
        const c = ft.c;
        if (ft.errunion_status.get(pool_index)) |completed| {
            if (completed) return;
        }
        const rendered = &c.types.items[@intFromEnum(pool_index)];
        ft.processDeps(&rendered.deps);
        if (rendered.errunion_definition.len > 0) {
            ft.f.appendBufAssumeCapacity(rendered.errunion_definition.get(c));
        } else {
            // The error union type will never be completed, but forward declare it to avoid the
            // type being first declared in a different scope.
            ft.f.appendBufAssumeCapacity(rendered.errunion_fwd_decl.get(c));
        }
        ft.errunion_status.putAssumeCapacity(pool_index, true);
    }
};
