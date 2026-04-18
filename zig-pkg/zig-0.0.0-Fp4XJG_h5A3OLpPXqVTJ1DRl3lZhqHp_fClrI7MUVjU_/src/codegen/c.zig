const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;
const log = std.log.scoped(.c);
const Allocator = mem.Allocator;
const Writer = std.Io.Writer;

const dev = @import("../dev.zig");
const link = @import("../link.zig");
const Zcu = @import("../Zcu.zig");
const Module = @import("../Package/Module.zig");
const Compilation = @import("../Compilation.zig");
const Value = @import("../Value.zig");
const Type = @import("../Type.zig");
const C = link.File.C;
const Decl = Zcu.Decl;
const trace = @import("../tracy.zig").trace;
const Air = @import("../Air.zig");
const InternPool = @import("../InternPool.zig");
const Alignment = InternPool.Alignment;

const BigIntLimb = std.math.big.Limb;
const BigInt = std.math.big.int;

pub fn legalizeFeatures(_: *const std.Target) ?*const Air.Legalize.Features {
    return comptime switch (dev.env.supports(.legalize)) {
        inline false, true => |supports_legalize| &.init(.{
            // we don't currently ask zig1 to use safe optimization modes
            .expand_intcast_safe = supports_legalize,
            .expand_int_from_float_safe = supports_legalize,
            .expand_int_from_float_optimized_safe = supports_legalize,
            .expand_add_safe = supports_legalize,
            .expand_sub_safe = supports_legalize,
            .expand_mul_safe = supports_legalize,

            .expand_packed_load = true,
            .expand_packed_store = true,
            .expand_packed_struct_field_val = true,
            .expand_packed_aggregate_init = true,
        }),
    };
}

/// For most backends, MIR is basically a sequence of machine code instructions, perhaps with some
/// "pseudo instructions" thrown in. For the C backend, it is instead the generated C code for a
/// single function. We also need to track some information to get merged into the global `link.C`
/// state, including:
/// * The UAVs used, so declarations can be emitted in `flush`
/// * The types used, so declarations can be emitted in `flush`
/// * The lazy functions used, so definitions can be emitted in `flush`
pub const Mir = struct {
    // These remaining fields are essentially just an owned version of `link.C.AvBlock`.
    fwd_decl: []u8,
    code_header: []u8,
    code: []u8,
    /// This map contains all the UAVs we saw generating this function.
    /// `link.C` will merge them into its `uavs`/`aligned_uavs` fields.
    /// Key is the value of the UAV; value is the UAV's alignment, or
    /// `.none` for natural alignment. The specified alignment is never
    /// less than the natural alignment.
    need_uavs: std.AutoArrayHashMapUnmanaged(InternPool.Index, Alignment),
    ctype_deps: CType.Dependencies,
    /// Key is an enum type for which we need a generated `@tagName` function.
    need_tag_name_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
    /// Key is a function Nav for which we need a generated `zig_never_tail` wrapper.
    need_never_tail_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void),
    /// Key is a function Nav for which we need a generated `zig_never_inline` wrapper.
    need_never_inline_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void),

    pub fn deinit(mir: *Mir, gpa: Allocator) void {
        gpa.free(mir.fwd_decl);
        gpa.free(mir.code_header);
        gpa.free(mir.code);
        mir.need_uavs.deinit(gpa);
        mir.ctype_deps.deinit(gpa);
        mir.need_tag_name_funcs.deinit(gpa);
        mir.need_never_tail_funcs.deinit(gpa);
        mir.need_never_inline_funcs.deinit(gpa);
    }
};

pub const Error = Writer.Error || Allocator.Error || error{AnalysisFail};

pub const CType = @import("c/type.zig").CType;

pub const CValue = union(enum) {
    none: void,
    new_local: LocalIndex,
    local: LocalIndex,
    /// Address of a local.
    local_ref: LocalIndex,
    /// A constant instruction, to be rendered inline.
    constant: Value,
    /// Index into the parameters
    arg: usize,
    /// Index into a tuple's fields
    field: usize,
    /// By-value
    nav: InternPool.Nav.Index,
    nav_ref: InternPool.Nav.Index,
    /// An undefined value (cannot be dereferenced)
    undef: Type,
    /// Rendered as an identifier (using fmtIdent)
    identifier: []const u8,
    /// Rendered as "payload." followed by as identifier (using fmtIdent)
    payload_identifier: []const u8,

    fn eql(lhs: CValue, rhs: CValue) bool {
        return switch (lhs) {
            .none => rhs == .none,
            .new_local, .local => |lhs_local| switch (rhs) {
                .new_local, .local => |rhs_local| lhs_local == rhs_local,
                else => false,
            },
            .local_ref => |lhs_local| switch (rhs) {
                .local_ref => |rhs_local| lhs_local == rhs_local,
                else => false,
            },
            .constant => |lhs_val| switch (rhs) {
                .constant => |rhs_val| lhs_val.toIntern() == rhs_val.toIntern(),
                else => false,
            },
            .arg => |lhs_arg_index| switch (rhs) {
                .arg => |rhs_arg_index| lhs_arg_index == rhs_arg_index,
                else => false,
            },
            .field => |lhs_field_index| switch (rhs) {
                .field => |rhs_field_index| lhs_field_index == rhs_field_index,
                else => false,
            },
            .nav => |lhs_nav| switch (rhs) {
                .nav => |rhs_nav| lhs_nav == rhs_nav,
                else => false,
            },
            .nav_ref => |lhs_nav| switch (rhs) {
                .nav_ref => |rhs_nav| lhs_nav == rhs_nav,
                else => false,
            },
            .undef => |lhs_ty| switch (rhs) {
                .undef => |rhs_ty| lhs_ty.toIntern() == rhs_ty.toIntern(),
                else => false,
            },
            .identifier => |lhs_id| switch (rhs) {
                .identifier => |rhs_id| std.mem.eql(u8, lhs_id, rhs_id),
                else => false,
            },
            .payload_identifier => |lhs_id| switch (rhs) {
                .payload_identifier => |rhs_id| std.mem.eql(u8, lhs_id, rhs_id),
                else => false,
            },
        };
    }
};

const BlockData = struct {
    block_id: u32,
    result: CValue,
};

const LocalType = struct {
    type: Type,
    alignment: Alignment,
};

const LocalIndex = u16;
const LocalsList = std.AutoArrayHashMapUnmanaged(LocalIndex, void);
const LocalsMap = std.AutoArrayHashMapUnmanaged(LocalType, LocalsList);

const ValueRenderLocation = enum {
    initializer,
    static_initializer,
    other,

    fn isInitializer(loc: ValueRenderLocation) bool {
        return switch (loc) {
            .initializer, .static_initializer => true,
            .other => false,
        };
    }
};

const BuiltinInfo = enum { none, bits };

const reserved_idents = std.StaticStringMap(void).initComptime(.{
    // C language
    .{ "alignas", {
        @setEvalBranchQuota(4000);
    } },
    .{ "alignof", {} },
    .{ "asm", {} },
    .{ "atomic_bool", {} },
    .{ "atomic_char", {} },
    .{ "atomic_char16_t", {} },
    .{ "atomic_char32_t", {} },
    .{ "atomic_int", {} },
    .{ "atomic_int_fast16_t", {} },
    .{ "atomic_int_fast32_t", {} },
    .{ "atomic_int_fast64_t", {} },
    .{ "atomic_int_fast8_t", {} },
    .{ "atomic_int_least16_t", {} },
    .{ "atomic_int_least32_t", {} },
    .{ "atomic_int_least64_t", {} },
    .{ "atomic_int_least8_t", {} },
    .{ "atomic_intmax_t", {} },
    .{ "atomic_intptr_t", {} },
    .{ "atomic_llong", {} },
    .{ "atomic_long", {} },
    .{ "atomic_ptrdiff_t", {} },
    .{ "atomic_schar", {} },
    .{ "atomic_short", {} },
    .{ "atomic_size_t", {} },
    .{ "atomic_uchar", {} },
    .{ "atomic_uint", {} },
    .{ "atomic_uint_fast16_t", {} },
    .{ "atomic_uint_fast32_t", {} },
    .{ "atomic_uint_fast64_t", {} },
    .{ "atomic_uint_fast8_t", {} },
    .{ "atomic_uint_least16_t", {} },
    .{ "atomic_uint_least32_t", {} },
    .{ "atomic_uint_least64_t", {} },
    .{ "atomic_uint_least8_t", {} },
    .{ "atomic_uintmax_t", {} },
    .{ "atomic_uintptr_t", {} },
    .{ "atomic_ullong", {} },
    .{ "atomic_ulong", {} },
    .{ "atomic_ushort", {} },
    .{ "atomic_wchar_t", {} },
    .{ "auto", {} },
    .{ "break", {} },
    .{ "case", {} },
    .{ "char", {} },
    .{ "complex", {} },
    .{ "const", {} },
    .{ "continue", {} },
    .{ "default", {} },
    .{ "do", {} },
    .{ "double", {} },
    .{ "else", {} },
    .{ "enum", {} },
    .{ "extern", {} },
    .{ "float", {} },
    .{ "for", {} },
    .{ "fortran", {} },
    .{ "goto", {} },
    .{ "if", {} },
    .{ "imaginary", {} },
    .{ "inline", {} },
    .{ "int", {} },
    .{ "int16_t", {} },
    .{ "int32_t", {} },
    .{ "int64_t", {} },
    .{ "int8_t", {} },
    .{ "intptr_t", {} },
    .{ "long", {} },
    .{ "noreturn", {} },
    .{ "register", {} },
    .{ "restrict", {} },
    .{ "return", {} },
    .{ "short", {} },
    .{ "signed", {} },
    .{ "size_t", {} },
    .{ "sizeof", {} },
    .{ "ssize_t", {} },
    .{ "static", {} },
    .{ "static_assert", {} },
    .{ "struct", {} },
    .{ "switch", {} },
    .{ "thread_local", {} },
    .{ "typedef", {} },
    .{ "typeof", {} },
    .{ "uint16_t", {} },
    .{ "uint32_t", {} },
    .{ "uint64_t", {} },
    .{ "uint8_t", {} },
    .{ "uintptr_t", {} },
    .{ "union", {} },
    .{ "unsigned", {} },
    .{ "void", {} },
    .{ "volatile", {} },
    .{ "while", {} },

    // stdarg.h
    .{ "va_start", {} },
    .{ "va_arg", {} },
    .{ "va_end", {} },
    .{ "va_copy", {} },

    // stdbool.h
    .{ "bool", {} },
    .{ "false", {} },
    .{ "true", {} },

    // stddef.h
    .{ "offsetof", {} },

    // windows.h
    .{ "max", {} },
    .{ "min", {} },
});

fn isReservedIdent(ident: []const u8) bool {
    // C language
    if (ident.len >= 2 and ident[0] == '_') {
        switch (ident[1]) {
            'A'...'Z', '_' => return true,
            else => {},
        }
    }

    // windows.h
    if (mem.startsWith(u8, ident, "DUMMYSTRUCTNAME") or
        mem.startsWith(u8, ident, "DUMMYUNIONNAME"))
    {
        return true;
    }

    // CType
    if (mem.startsWith(u8, ident, "enum__") or
        mem.startsWith(u8, ident, "bitpack__") or
        mem.startsWith(u8, ident, "aligned__") or
        mem.startsWith(u8, ident, "fn__"))
    {
        return true;
    }

    return reserved_idents.has(ident);
}

fn formatIdentSolo(ident: []const u8, w: *Writer) Writer.Error!void {
    return formatIdentOptions(ident, w, true);
}

fn formatIdentUnsolo(ident: []const u8, w: *Writer) Writer.Error!void {
    return formatIdentOptions(ident, w, false);
}

fn formatIdentOptions(ident: []const u8, w: *Writer, solo: bool) Writer.Error!void {
    if (solo and isReservedIdent(ident)) {
        try w.writeAll("zig_e_");
    }
    for (ident, 0..) |c, i| {
        switch (c) {
            'a'...'z', 'A'...'Z', '_' => try w.writeByte(c),
            '.', ' ' => try w.writeByte('_'),
            '0'...'9' => if (i == 0) {
                try w.print("_{x:2}", .{c});
            } else {
                try w.writeByte(c);
            },
            else => try w.print("_{x:2}", .{c}),
        }
    }
}

pub fn fmtIdentSolo(ident: []const u8) std.fmt.Alt([]const u8, formatIdentSolo) {
    return .{ .data = ident };
}

pub fn fmtIdentUnsolo(ident: []const u8) std.fmt.Alt([]const u8, formatIdentUnsolo) {
    return .{ .data = ident };
}

// Returns true if `formatIdent` would make any edits to ident.
// This must be kept in sync with `formatIdent`.
pub fn isMangledIdent(ident: []const u8, solo: bool) bool {
    if (solo and isReservedIdent(ident)) return true;
    for (ident, 0..) |c, i| {
        switch (c) {
            'a'...'z', 'A'...'Z', '_' => {},
            '0'...'9' => if (i == 0) return true,
            else => return true,
        }
    }
    return false;
}

/// This data is available when rendering C source code for an interned function.
pub const Function = struct {
    air: Air,
    liveness: Air.Liveness,
    value_map: std.AutoHashMap(Air.Inst.Ref, CValue),
    blocks: std.AutoHashMapUnmanaged(Air.Inst.Index, BlockData) = .empty,
    next_arg_index: u32 = 0,
    next_block_index: u32 = 0,
    dg: DeclGen,
    code: Writer.Allocating,
    indent_counter: usize,
    /// Key is an enum type for which we need a generated `@tagName` function.
    need_tag_name_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
    /// Key is a function Nav for which we need a generated `zig_never_tail` wrapper.
    need_never_tail_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void),
    /// Key is a function Nav for which we need a generated `zig_never_inline` wrapper.
    need_never_inline_funcs: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, void),
    func_index: InternPool.Index,
    /// All the locals, to be emitted at the top of the function.
    locals: std.ArrayList(LocalType) = .empty,
    /// Which locals are available for reuse, based on Type.
    free_locals_map: LocalsMap = .{},
    /// Locals which will not be freed by Liveness. This is used after a
    /// Function body is lowered in order to make `free_locals_map` have
    /// 100% of the locals within so that it can be used to render the block
    /// of variable declarations at the top of a function, sorted descending
    /// by type alignment.
    /// The value is whether the alloc needs to be emitted in the header.
    allocs: std.AutoArrayHashMapUnmanaged(LocalIndex, bool) = .empty,
    /// Maps from `loop_switch_br` instructions to the allocated local used
    /// for the switch cond. Dispatches should set this local to the new cond.
    loop_switch_conds: std.AutoHashMapUnmanaged(Air.Inst.Index, LocalIndex) = .empty,

    const indent_width = 1;
    const indent_char = ' ';

    fn newline(f: *Function) !void {
        const w = &f.code.writer;
        try w.writeByte('\n');
        try w.splatByteAll(indent_char, f.indent_counter);
    }
    fn indent(f: *Function) void {
        f.indent_counter += indent_width;
    }
    fn outdent(f: *Function) !void {
        f.indent_counter -= indent_width;
        const written = f.code.written();
        switch (written[written.len - 1]) {
            indent_char => f.code.shrinkRetainingCapacity(written.len - indent_width),
            '\n' => try f.code.writer.splatByteAll(indent_char, f.indent_counter),
            else => {
                std.debug.print("\"{f}\"\n", .{std.zig.fmtString(written[written.len -| 100..])});
                unreachable;
            },
        }
    }

    fn resolveInst(f: *Function, ref: Air.Inst.Ref) !CValue {
        const gop = try f.value_map.getOrPut(ref);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .constant = .fromInterned(ref.toInterned().?) };
        }
        return gop.value_ptr.*;
    }

    fn wantSafety(f: *Function) bool {
        return switch (f.dg.pt.zcu.optimizeMode()) {
            .Debug, .ReleaseSafe => true,
            .ReleaseFast, .ReleaseSmall => false,
        };
    }

    /// Skips the reuse logic. This function should be used for any persistent allocation, i.e.
    /// those which go into `allocs`. This function does not add the resulting local into `allocs`;
    /// that responsibility lies with the caller.
    fn allocLocalValue(f: *Function, local_type: LocalType) !CValue {
        try f.locals.ensureUnusedCapacity(f.dg.gpa, 1);
        const index = f.locals.items.len;
        f.locals.appendAssumeCapacity(local_type);
        return .{ .new_local = @intCast(index) };
    }

    fn allocLocal(f: *Function, inst: ?Air.Inst.Index, ty: Type) !CValue {
        return f.allocAlignedLocal(inst, .{
            .type = ty,
            .alignment = .none,
        });
    }

    /// Only allocates the local; does not print anything. Will attempt to re-use locals, so should
    /// not be used for persistent locals (i.e. those in `allocs`).
    fn allocAlignedLocal(f: *Function, inst: ?Air.Inst.Index, local_type: LocalType) !CValue {
        const result: CValue = result: {
            if (f.free_locals_map.getPtr(local_type)) |locals_list| {
                if (locals_list.pop()) |local_entry| {
                    break :result .{ .new_local = local_entry.key };
                }
            }
            break :result try f.allocLocalValue(local_type);
        };
        if (inst) |i| {
            log.debug("%{d}: allocating t{d}", .{ i, result.new_local });
        } else {
            log.debug("allocating t{d}", .{result.new_local});
        }
        return result;
    }

    fn writeCValue(f: *Function, w: *Writer, c_value: CValue, location: ValueRenderLocation) !void {
        switch (c_value) {
            .none => unreachable,
            .new_local, .local => |i| try w.print("t{d}", .{i}),
            .local_ref => |i| try w.print("&t{d}", .{i}),
            .constant => |val| try f.dg.renderValue(w, val, location),
            .arg => |i| try w.print("a{d}", .{i}),
            .undef => |ty| try f.dg.renderUndefValue(w, ty, location),
            else => try f.dg.writeCValue(w, c_value),
        }
    }

    fn writeCValueDeref(f: *Function, w: *Writer, c_value: CValue) !void {
        switch (c_value) {
            .none => unreachable,
            .new_local, .local, .constant => {
                try w.writeAll("(*");
                try f.writeCValue(w, c_value, .other);
                try w.writeByte(')');
            },
            .local_ref => |i| try w.print("t{d}", .{i}),
            .arg => |i| try w.print("(*a{d})", .{i}),
            else => try f.dg.writeCValueDeref(w, c_value),
        }
    }

    fn writeCValueMember(
        f: *Function,
        w: *Writer,
        c_value: CValue,
        member: CValue,
    ) Error!void {
        switch (c_value) {
            .new_local, .local, .local_ref, .constant, .arg => {
                try f.writeCValue(w, c_value, .other);
                try w.writeByte('.');
                try f.writeCValue(w, member, .other);
            },
            else => return f.dg.writeCValueMember(w, c_value, member),
        }
    }

    fn writeCValueDerefMember(f: *Function, w: *Writer, c_value: CValue, member: CValue) !void {
        switch (c_value) {
            .new_local, .local, .arg => {
                try f.writeCValue(w, c_value, .other);
                try w.writeAll("->");
            },
            .constant => {
                try w.writeByte('(');
                try f.writeCValue(w, c_value, .other);
                try w.writeAll(")->");
            },
            .local_ref => {
                try f.writeCValueDeref(w, c_value);
                try w.writeByte('.');
            },
            else => return f.dg.writeCValueDerefMember(w, c_value, member),
        }
        try f.writeCValue(w, member, .other);
    }

    fn fail(f: *Function, comptime format: []const u8, args: anytype) Error {
        return f.dg.fail(format, args);
    }

    fn renderType(f: *Function, w: *Writer, ty: Type) !void {
        return f.dg.renderType(w, ty);
    }

    fn renderIntCast(f: *Function, w: *Writer, dest_ty: Type, src: CValue, v: Vectorize, src_ty: Type, location: ValueRenderLocation) !void {
        return f.dg.renderIntCast(w, dest_ty, .{ .c_value = .{ .f = f, .value = src, .v = v } }, src_ty, location);
    }

    fn fmtIntLiteralDec(f: *Function, val: Value) !std.fmt.Alt(FormatIntLiteralContext, formatIntLiteral) {
        return f.dg.fmtIntLiteralDec(val, .other);
    }

    fn fmtIntLiteralHex(f: *Function, val: Value) !std.fmt.Alt(FormatIntLiteralContext, formatIntLiteral) {
        return f.dg.fmtIntLiteralHex(val, .other);
    }

    pub fn deinit(f: *Function) void {
        const gpa = f.dg.gpa;
        f.allocs.deinit(gpa);
        f.locals.deinit(gpa);
        deinitFreeLocalsMap(gpa, &f.free_locals_map);
        f.blocks.deinit(gpa);
        f.value_map.deinit();
        f.need_tag_name_funcs.deinit(gpa);
        f.need_never_tail_funcs.deinit(gpa);
        f.need_never_inline_funcs.deinit(gpa);
        f.loop_switch_conds.deinit(gpa);
    }

    fn typeOf(f: *Function, inst: Air.Inst.Ref) Type {
        return f.air.typeOf(inst, &f.dg.pt.zcu.intern_pool);
    }

    fn typeOfIndex(f: *Function, inst: Air.Inst.Index) Type {
        return f.air.typeOfIndex(inst, &f.dg.pt.zcu.intern_pool);
    }

    fn copyCValue(f: *Function, dst: CValue, src: CValue) !void {
        switch (dst) {
            .new_local, .local => |dst_local_index| switch (src) {
                .new_local, .local => |src_local_index| if (dst_local_index == src_local_index) return,
                else => {},
            },
            else => {},
        }
        const w = &f.code.writer;
        try f.writeCValue(w, dst, .other);
        try w.writeAll(" = ");
        try f.writeCValue(w, src, .other);
        try w.writeByte(';');
        try f.newline();
    }

    fn moveCValue(f: *Function, inst: Air.Inst.Index, ty: Type, src: CValue) !CValue {
        switch (src) {
            // Move the freshly allocated local to be owned by this instruction,
            // by returning it here instead of freeing it.
            .new_local => return src,
            else => {
                try freeCValue(f, inst, src);
                const dst = try f.allocLocal(inst, ty);
                try f.copyCValue(dst, src);
                return dst;
            },
        }
    }

    fn freeCValue(f: *Function, inst: ?Air.Inst.Index, val: CValue) !void {
        switch (val) {
            .new_local => |local_index| try freeLocal(f, inst, local_index, null),
            else => {},
        }
    }
};

/// This data is available when rendering *any* C source code (function or otherwise).
pub const DeclGen = struct {
    gpa: Allocator,
    arena: Allocator,
    pt: Zcu.PerThread,
    mod: *Module,
    owner_nav: InternPool.Nav.Index.Optional,
    is_naked_fn: bool,
    expected_block: ?u32,
    error_msg: ?*Zcu.ErrorMsg,
    ctype_deps: CType.Dependencies,
    /// This map contains all the UAVs we saw generating this function.
    /// `link.C` will merge them into its `uavs`/`aligned_uavs` fields.
    /// Key is the value of the UAV; value is the UAV's alignment, or
    /// `.none` for natural alignment. The specified alignment is never
    /// less than the natural alignment.
    uavs: std.AutoArrayHashMapUnmanaged(InternPool.Index, Alignment),

    fn fail(dg: *DeclGen, comptime format: []const u8, args: anytype) Error {
        @branchHint(.cold);
        const zcu = dg.pt.zcu;
        const src_loc = zcu.navSrcLoc(dg.owner_nav.unwrap().?);
        dg.error_msg = try Zcu.ErrorMsg.create(dg.gpa, src_loc, format, args);
        return error.AnalysisFail;
    }

    fn renderUav(
        dg: *DeclGen,
        w: *Writer,
        uav: InternPool.Key.Ptr.BaseAddr.Uav,
        location: ValueRenderLocation,
    ) Error!void {
        const pt = dg.pt;
        const zcu = pt.zcu;
        const ip = &zcu.intern_pool;
        const uav_val = Value.fromInterned(uav.val);
        const uav_ty = uav_val.typeOf(zcu);

        // Render an undefined pointer if we have a pointer to a zero-bit or comptime type.
        const ptr_ty: Type = .fromInterned(uav.orig_ty);
        if (ptr_ty.isPtrAtRuntime(zcu) and !uav_ty.isRuntimeFnOrHasRuntimeBits(zcu)) {
            return dg.renderUndefValue(w, ptr_ty, location);
        }

        switch (ip.indexToKey(uav.val)) {
            .func => unreachable,
            .@"extern" => unreachable,
            else => {},
        }

        // We shouldn't cast C function pointers as this is UB (when you call
        // them).  The analysis until now should ensure that the C function
        // pointers are compatible.  If they are not, then there is a bug
        // somewhere and we should let the C compiler tell us about it.
        const elem_ty = ptr_ty.childType(zcu);
        const need_cast = elem_ty.toIntern() != uav_ty.toIntern() and
            elem_ty.zigTypeTag(zcu) != .@"fn" or uav_ty.zigTypeTag(zcu) != .@"fn";
        if (need_cast) {
            try w.writeAll("((");
            try dg.renderType(w, ptr_ty);
            try w.writeByte(')');
        }
        try w.writeByte('&');
        try renderUavName(w, uav_val);
        if (need_cast) try w.writeByte(')');

        // Indicate that the anon decl should be rendered to the output so that
        // our reference above is not undefined.
        const ptr_type = ip.indexToKey(uav.orig_ty).ptr_type;
        const gop = try dg.uavs.getOrPut(dg.gpa, uav.val);
        if (!gop.found_existing) gop.value_ptr.* = .none;
        // If there is an explicit alignment, greater than the current one, use it.
        // Note that we intentionally start at `.none`, so `gop.value_ptr.*` is never
        // underaligned, so we don't need to worry about the `.none` case here.
        if (ptr_type.flags.alignment != .none) {
            // Resolve the current alignment so we can choose the bigger one.
            const cur_alignment: Alignment = if (gop.value_ptr.* == .none) abi: {
                break :abi Type.fromInterned(ptr_type.child).abiAlignment(zcu);
            } else gop.value_ptr.*;
            gop.value_ptr.* = cur_alignment.maxStrict(ptr_type.flags.alignment);
        }
    }

    fn renderNav(
        dg: *DeclGen,
        w: *Writer,
        nav_index: InternPool.Nav.Index,
        location: ValueRenderLocation,
    ) Error!void {
        const pt = dg.pt;
        const zcu = pt.zcu;
        const ip = &zcu.intern_pool;

        // Chase function values in order to be able to reference the original function.
        const owner_nav = switch (ip.getNav(nav_index).resolved.?.value) {
            .none => nav_index, // this can't be an extern or a function
            else => |value| switch (ip.indexToKey(value)) {
                .func => |f| f.owner_nav,
                .@"extern" => |e| e.owner_nav,
                else => nav_index,
            },
        };

        // Render an undefined pointer if we have a pointer to a zero-bit or comptime type.
        const nav_ty: Type = .fromInterned(ip.getNav(owner_nav).resolved.?.type);
        const ptr_ty = try pt.navPtrType(owner_nav);
        if (!nav_ty.isRuntimeFnOrHasRuntimeBits(zcu)) {
            return dg.renderUndefValue(w, ptr_ty, location);
        }

        // We shouldn't cast C function pointers as this is UB (when you call
        // them).  The analysis until now should ensure that the C function
        // pointers are compatible.  If they are not, then there is a bug
        // somewhere and we should let the C compiler tell us about it.
        const elem_ty = ptr_ty.childType(zcu);
        const need_cast = elem_ty.toIntern() != nav_ty.toIntern() and
            elem_ty.zigTypeTag(zcu) != .@"fn" or nav_ty.zigTypeTag(zcu) != .@"fn";
        if (need_cast) {
            try w.writeAll("((");
            try dg.renderType(w, ptr_ty);
            try w.writeByte(')');
        }
        try w.writeByte('&');
        try renderNavName(w, owner_nav, ip);
        if (need_cast) try w.writeByte(')');
    }

    fn renderPointer(
        dg: *DeclGen,
        w: *Writer,
        derivation: Value.PointerDeriveStep,
        location: ValueRenderLocation,
    ) Error!void {
        const pt = dg.pt;
        const zcu = pt.zcu;
        switch (derivation) {
            .comptime_alloc_ptr, .comptime_field_ptr => unreachable,
            .int => |int| {
                const addr_val = try pt.intValue(.usize, int.addr);
                try w.writeByte('(');
                try dg.renderType(w, int.ptr_ty);
                try w.print("){f}", .{try dg.fmtIntLiteralHex(addr_val, .other)});
            },

            .nav_ptr => |nav| try dg.renderNav(w, nav, location),
            .uav_ptr => |uav| try dg.renderUav(w, uav, location),

            inline .eu_payload_ptr, .opt_payload_ptr => |info| {
                try w.writeAll("&(");
                try dg.renderPointer(w, info.parent.*, location);
                try w.writeAll(")->payload");
            },

            .field_ptr => |field| {
                const parent_ptr_ty = try field.parent.ptrType(pt);

                switch (fieldLocation(parent_ptr_ty, field.result_ptr_ty, field.field_idx, zcu)) {
                    .begin => {
                        try w.writeByte('(');
                        try dg.renderType(w, field.result_ptr_ty);
                        try w.writeByte(')');
                        try dg.renderPointer(w, field.parent.*, location);
                    },
                    .field => |name| {
                        try w.writeAll("&(");
                        try dg.renderPointer(w, field.parent.*, location);
                        try w.writeAll(")->");
                        try dg.writeCValue(w, name);
                    },
                    .byte_offset => |byte_offset| {
                        try w.writeByte('(');
                        try dg.renderType(w, field.result_ptr_ty);
                        try w.writeByte(')');
                        const offset_val = try pt.intValue(.usize, byte_offset);
                        try w.writeAll("((char *)");
                        try dg.renderPointer(w, field.parent.*, location);
                        try w.print(" + {f})", .{try dg.fmtIntLiteralDec(offset_val, .other)});
                    },
                }
            },

            .elem_ptr => |elem| if (!(try elem.parent.ptrType(pt)).childType(zcu).hasRuntimeBits(zcu)) {
                // Element type is zero-bit, so lowers to `void`. The index is irrelevant; just cast the pointer.
                try w.writeByte('(');
                try dg.renderType(w, elem.result_ptr_ty);
                try w.writeByte(')');
                try dg.renderPointer(w, elem.parent.*, location);
            } else {
                const index_val = try pt.intValue(.usize, elem.elem_idx);
                try w.writeByte('(');
                // We want to do pointer arithmetic on a pointer to the element type, but the parent
                // might be a pointer-to-array, in which case we must cast it.
                if (elem.result_ptr_ty.toIntern() != (try elem.parent.ptrType(pt)).toIntern()) {
                    try w.writeByte('(');
                    try dg.renderType(w, elem.result_ptr_ty);
                    try w.writeByte(')');
                }
                try dg.renderPointer(w, elem.parent.*, location);
                try w.print(" + {f})", .{try dg.fmtIntLiteralDec(index_val, .other)});
            },

            .offset_and_cast => |oac| {
                try w.writeByte('(');
                try dg.renderType(w, oac.new_ptr_ty);
                try w.writeByte(')');
                if (oac.byte_offset == 0) {
                    try dg.renderPointer(w, oac.parent.*, location);
                } else {
                    const offset_val = try pt.intValue(.usize, oac.byte_offset);
                    try w.writeAll("((char *)");
                    try dg.renderPointer(w, oac.parent.*, location);
                    try w.print(" + {f})", .{try dg.fmtIntLiteralDec(offset_val, .other)});
                }
            },
        }
    }

    fn renderValueAsLvalue(
        dg: *DeclGen,
        w: *Writer,
        val: Value,
    ) Error!void {
        const zcu = dg.pt.zcu;

        // If the type of `val` lowers to a C struct or union type, then `renderValue` will render
        // it as a compound literal, and compound literals are already lvalues.
        const ty = val.typeOf(zcu);
        const is_aggregate: bool = switch (ty.zigTypeTag(zcu)) {
            .@"struct", .@"union" => switch (ty.containerLayout(zcu)) {
                .auto, .@"extern" => true,
                .@"packed" => false,
            },
            .array,
            .vector,
            .error_union,
            .optional,
            => true,
            else => false,
        };
        if (is_aggregate) return renderValue(dg, w, val, .other);

        // Otherwise, use a UAV.
        const gop = try dg.uavs.getOrPut(dg.gpa, val.toIntern());
        if (!gop.found_existing) gop.value_ptr.* = .none;
        try renderUavName(w, val);
    }

    fn renderValue(
        dg: *DeclGen,
        w: *Writer,
        val: Value,
        location: ValueRenderLocation,
    ) Error!void {
        const pt = dg.pt;
        const zcu = pt.zcu;
        const ip = &zcu.intern_pool;
        const target = &dg.mod.resolved_target.result;

        const initializer_type: ValueRenderLocation = switch (location) {
            .static_initializer => .static_initializer,
            else => .initializer,
        };

        const ty = val.typeOf(zcu);
        switch (ip.indexToKey(val.toIntern())) {
            // types, not values
            .int_type,
            .ptr_type,
            .array_type,
            .vector_type,
            .opt_type,
            .anyframe_type,
            .error_union_type,
            .simple_type,
            .struct_type,
            .tuple_type,
            .union_type,
            .opaque_type,
            .enum_type,
            .func_type,
            .error_set_type,
            .inferred_error_set_type,
            // memoization, not values
            .memoized_call,
            => unreachable,

            .undef => try dg.renderUndefValue(w, ty, location),
            .simple_value => |simple_value| switch (simple_value) {
                // non-runtime values
                .void => unreachable,
                .null => unreachable,
                .@"unreachable" => unreachable,

                .false => try w.writeAll("false"),
                .true => try w.writeAll("true"),
            },
            .@"extern",
            .func,
            .enum_literal,
            => unreachable, // non-runtime values
            .int => try w.print("{f}", .{try dg.fmtIntLiteralDec(val, location)}),
            .err => |err| try renderErrorName(w, err.name.toSlice(ip)),
            .error_union => |error_union| {
                if (!location.isInitializer()) {
                    try w.writeByte('(');
                    try dg.renderType(w, ty);
                    try w.writeByte(')');
                }
                try w.writeAll("{ .error = ");
                switch (error_union.val) {
                    .err_name => |err_name| try renderErrorName(w, err_name.toSlice(ip)),
                    .payload => try w.writeByte('0'),
                }
                if (ty.errorUnionPayload(zcu).hasRuntimeBits(zcu)) {
                    try w.writeAll(", .payload = ");
                    switch (error_union.val) {
                        .err_name => try dg.renderUndefValue(w, ty.errorUnionPayload(zcu), initializer_type),
                        .payload => |payload| try dg.renderValue(w, .fromInterned(payload), initializer_type),
                    }
                }
                try w.writeAll(" }");
            },
            .enum_tag => |enum_tag| try dg.renderValue(w, .fromInterned(enum_tag.int), location),
            .float => {
                const bits = ty.floatBits(target);
                const f128_val = val.toFloat(f128, zcu);

                // All unsigned ints matching float types are pre-allocated.
                const repr_ty = pt.intType(.unsigned, bits) catch unreachable;

                assert(bits <= 128);
                var repr_val_limbs: [BigInt.calcTwosCompLimbCount(128)]BigIntLimb = undefined;
                var repr_val_big = BigInt.Mutable{
                    .limbs = &repr_val_limbs,
                    .len = undefined,
                    .positive = undefined,
                };

                switch (bits) {
                    16 => repr_val_big.set(@as(u16, @bitCast(val.toFloat(f16, zcu)))),
                    32 => repr_val_big.set(@as(u32, @bitCast(val.toFloat(f32, zcu)))),
                    64 => repr_val_big.set(@as(u64, @bitCast(val.toFloat(f64, zcu)))),
                    80 => repr_val_big.set(@as(u80, @bitCast(val.toFloat(f80, zcu)))),
                    128 => repr_val_big.set(@as(u128, @bitCast(f128_val))),
                    else => unreachable,
                }

                var empty = true;
                if (std.math.isFinite(f128_val)) {
                    try w.writeAll("zig_make_");
                    try dg.renderTypeForBuiltinFnName(w, ty);
                    try w.writeByte('(');
                    switch (bits) {
                        16 => try w.print("{x}", .{val.toFloat(f16, zcu)}),
                        32 => try w.print("{x}", .{val.toFloat(f32, zcu)}),
                        64 => try w.print("{x}", .{val.toFloat(f64, zcu)}),
                        80 => try w.print("{x}", .{val.toFloat(f80, zcu)}),
                        128 => try w.print("{x}", .{f128_val}),
                        else => unreachable,
                    }
                    try w.writeAll(", ");
                    empty = false;
                } else {
                    // isSignalNan is equivalent to isNan currently, and MSVC doesn't have nans, so prefer nan
                    const operation = if (std.math.isNan(f128_val))
                        "nan"
                    else if (std.math.isSignalNan(f128_val))
                        "nans"
                    else if (std.math.isInf(f128_val))
                        "inf"
                    else
                        unreachable;

                    if (location == .static_initializer) {
                        if (!std.math.isNan(f128_val) and std.math.isSignalNan(f128_val))
                            return dg.fail("TODO: C backend: implement nans rendering in static initializers", .{});

                        // MSVC doesn't have a way to define a custom or signaling NaN value in a constant expression

                        // TODO: Re-enable this check, otherwise we're writing qnan bit patterns on msvc incorrectly
                        // if (std.math.isNan(f128_val) and f128_val != std.math.nan(f128))
                        //     return dg.fail("Only quiet nans are supported in global variable initializers", .{});
                    }

                    if (location == .static_initializer) {
                        try w.writeAll("zig_init_special_");
                    } else {
                        try w.writeAll("zig_make_special_");
                    }
                    try dg.renderTypeForBuiltinFnName(w, ty);
                    try w.writeByte('(');
                    if (std.math.signbit(f128_val)) try w.writeByte('-');
                    try w.writeAll(", ");
                    try w.writeAll(operation);
                    try w.writeAll(", ");
                    if (std.math.isNan(f128_val)) switch (bits) {
                        // We only actually need to pass the significand, but it will get
                        // properly masked anyway, so just pass the whole value.
                        16 => try w.print("\"0x{x}\"", .{@as(u16, @bitCast(val.toFloat(f16, zcu)))}),
                        32 => try w.print("\"0x{x}\"", .{@as(u32, @bitCast(val.toFloat(f32, zcu)))}),
                        64 => try w.print("\"0x{x}\"", .{@as(u64, @bitCast(val.toFloat(f64, zcu)))}),
                        80 => try w.print("\"0x{x}\"", .{@as(u80, @bitCast(val.toFloat(f80, zcu)))}),
                        128 => try w.print("\"0x{x}\"", .{@as(u128, @bitCast(f128_val))}),
                        else => unreachable,
                    };
                    try w.writeAll(", ");
                    empty = false;
                }
                try w.print("{f}", .{try dg.fmtIntLiteralHex(
                    try pt.intValue_big(repr_ty, repr_val_big.toConst()),
                    location,
                )});
                if (!empty) try w.writeByte(')');
            },
            .slice => |slice| {
                if (!location.isInitializer()) {
                    try w.writeByte('(');
                    try dg.renderType(w, ty);
                    try w.writeByte(')');
                }
                try w.writeByte('{');
                try dg.renderValue(w, .fromInterned(slice.ptr), initializer_type);
                try w.writeByte(',');
                try dg.renderValue(w, .fromInterned(slice.len), initializer_type);
                try w.writeByte('}');
            },
            .ptr => {
                const derivation = try val.pointerDerivation(dg.arena, pt, null);
                try w.writeByte('(');
                try dg.renderPointer(w, derivation, location);
                try w.writeByte(')');
            },
            .opt => |opt| switch (CType.classifyOptional(ty, zcu)) {
                .npv_payload => unreachable, // opv optional
                .opv_payload => {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }
                    try w.writeAll(switch (opt.val) {
                        .none => "{.is_null = true}",
                        else => "{.is_null = false}",
                    });
                },
                .error_set => switch (opt.val) {
                    .none => try w.writeByte('0'),
                    else => |payload_val| try dg.renderValue(w, .fromInterned(payload_val), location),
                },
                .ptr_like => switch (opt.val) {
                    .none => try w.writeAll("NULL"),
                    else => |payload_val| try dg.renderValue(w, .fromInterned(payload_val), location),
                },
                .slice_like => switch (opt.val) {
                    .none => {
                        if (!location.isInitializer()) {
                            try w.writeByte('(');
                            try dg.renderType(w, ty);
                            try w.writeByte(')');
                        }
                        try w.writeAll("{NULL,");
                        try dg.renderUndefValue(w, .usize, initializer_type);
                        try w.writeByte('}');
                    },
                    else => |payload_val| try dg.renderValue(w, .fromInterned(payload_val), location),
                },
                .@"struct" => {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }
                    switch (opt.val) {
                        .none => {
                            try w.writeAll("{ .is_null = true, .payload = ");
                            try dg.renderUndefValue(w, ty.optionalChild(zcu), initializer_type);
                            try w.writeAll(" }");
                        },
                        else => |payload_val| {
                            try w.writeAll("{ .is_null = false, .payload = ");
                            try dg.renderValue(w, .fromInterned(payload_val), initializer_type);
                            try w.writeAll(" }");
                        },
                    }
                },
            },
            .aggregate => switch (ip.indexToKey(ty.toIntern())) {
                .array_type, .vector_type => {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }
                    try w.writeByte('{');
                    const ai = ty.arrayInfo(zcu);
                    if (ai.elem_type.eql(.u8, zcu)) {
                        var literal: StringLiteral = .init(w, @intCast(ty.arrayLenIncludingSentinel(zcu)));
                        try literal.start();
                        var index: usize = 0;
                        while (index < ai.len) : (index += 1) {
                            const elem_val = try val.elemValue(pt, index);
                            const elem_val_u8: u8 = if (elem_val.isUndef(zcu))
                                undefPattern(u8)
                            else
                                @intCast(elem_val.toUnsignedInt(zcu));
                            try literal.writeChar(elem_val_u8);
                        }
                        if (ai.sentinel) |s| {
                            const s_u8: u8 = @intCast(s.toUnsignedInt(zcu));
                            if (s_u8 != 0) try literal.writeChar(s_u8);
                        }
                        try literal.end();
                    } else {
                        try w.writeByte('{');
                        var index: usize = 0;
                        while (index < ai.len) : (index += 1) {
                            if (index > 0) try w.writeByte(',');
                            const elem_val = try val.elemValue(pt, index);
                            try dg.renderValue(w, elem_val, initializer_type);
                        }
                        if (ai.sentinel) |s| {
                            if (index > 0) try w.writeByte(',');
                            try dg.renderValue(w, s, initializer_type);
                        }
                        try w.writeByte('}');
                    }
                    try w.writeByte('}');
                },
                .tuple_type => |tuple| {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }

                    try w.writeByte('{');
                    var empty = true;
                    for (0..tuple.types.len) |field_index| {
                        const comptime_val = tuple.values.get(ip)[field_index];
                        if (comptime_val != .none) continue;
                        const field_ty: Type = .fromInterned(tuple.types.get(ip)[field_index]);
                        if (!field_ty.hasRuntimeBits(zcu)) continue;

                        if (!empty) try w.writeByte(',');

                        const field_val = Value.fromInterned(
                            switch (ip.indexToKey(val.toIntern()).aggregate.storage) {
                                .bytes => |bytes| try pt.intern(.{ .int = .{
                                    .ty = field_ty.toIntern(),
                                    .storage = .{ .u64 = bytes.at(field_index, ip) },
                                } }),
                                .elems => |elems| elems[field_index],
                                .repeated_elem => |elem| elem,
                            },
                        );
                        try dg.renderValue(w, field_val, initializer_type);

                        empty = false;
                    }
                    try w.writeByte('}');
                },
                .struct_type => {
                    const loaded_struct = ip.loadStructType(ty.toIntern());
                    assert(loaded_struct.layout != .@"packed");

                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }

                    try w.writeByte('{');
                    var field_it = loaded_struct.iterateRuntimeOrder(ip);
                    var need_comma = false;
                    while (field_it.next()) |field_index| {
                        const field_ty: Type = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                        if (!field_ty.hasRuntimeBits(zcu)) continue;

                        if (need_comma) try w.writeByte(',');
                        need_comma = true;
                        const field_val = switch (ip.indexToKey(val.toIntern()).aggregate.storage) {
                            .bytes => |bytes| try pt.intern(.{ .int = .{
                                .ty = field_ty.toIntern(),
                                .storage = .{ .u64 = bytes.at(field_index, ip) },
                            } }),
                            .elems => |elems| elems[field_index],
                            .repeated_elem => |elem| elem,
                        };
                        try dg.renderValue(w, Value.fromInterned(field_val), initializer_type);
                    }
                    try w.writeByte('}');
                },
                else => unreachable,
            },
            .bitpack => |bitpack| return dg.renderValue(w, .fromInterned(bitpack.backing_int_val), location),
            .un => |un| {
                const loaded_union = ip.loadUnionType(ty.toIntern());
                if (un.tag == .none) {
                    assert(loaded_union.layout == .@"extern");
                    if (location == .static_initializer) {
                        return dg.fail("TODO: C backend: implement extern union backing type rendering in static initializers", .{});
                    }

                    const ptr_ty = try pt.singleConstPtrType(ty);
                    try w.writeAll("*(");
                    try dg.renderType(w, ptr_ty);
                    try w.writeAll(")&");
                    // We need an lvalue for '&'.
                    try dg.renderValueAsLvalue(w, .fromInterned(un.val));
                } else {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }
                    if (ty.unionHasAllZeroBitFieldTypes(zcu)) {
                        assert(loaded_union.has_runtime_tag); // otherwise it does not have runtime bits
                        try w.writeAll("{ .tag = ");
                        try dg.renderValue(w, .fromInterned(un.tag), initializer_type);
                        try w.writeAll(" }");
                        return;
                    }

                    if (loaded_union.layout == .auto) try w.writeByte('{');

                    if (loaded_union.has_runtime_tag) {
                        try w.writeAll(" .tag = ");
                        try dg.renderValue(w, .fromInterned(un.tag), initializer_type);
                        try w.writeAll(", .payload = ");
                    }

                    const enum_tag_ty: Type = .fromInterned(loaded_union.enum_tag_type);
                    const active_field_index = enum_tag_ty.enumTagFieldIndex(.fromInterned(un.tag), zcu).?;
                    const active_field_ty: Type = .fromInterned(loaded_union.field_types.get(ip)[active_field_index]);
                    if (active_field_ty.hasRuntimeBits(zcu)) {
                        const active_field_name = enum_tag_ty.enumFieldName(active_field_index, zcu);
                        try w.print("{{ .{f} = ", .{fmtIdentSolo(active_field_name.toSlice(ip))});
                        try dg.renderValue(w, .fromInterned(un.val), initializer_type);
                        try w.writeAll(" }");
                    } else {
                        const first_field_ty: Type = for (loaded_union.field_types.get(ip)) |field_ty_ip| {
                            const field_ty: Type = .fromInterned(field_ty_ip);
                            if (!field_ty.hasRuntimeBits(pt.zcu)) continue;
                            break field_ty;
                        } else unreachable;
                        try w.writeByte('{');
                        try dg.renderUndefValue(w, first_field_ty, initializer_type);
                        try w.writeByte('}');
                    }

                    if (loaded_union.has_runtime_tag) try w.writeByte(' ');
                    if (loaded_union.layout == .auto) try w.writeByte('}');
                }
            },
        }
    }

    fn renderUndefValue(
        dg: *DeclGen,
        w: *Writer,
        ty: Type,
        location: ValueRenderLocation,
    ) Error!void {
        const pt = dg.pt;
        const zcu = pt.zcu;
        const ip = &zcu.intern_pool;
        const target = &dg.mod.resolved_target.result;

        const initializer_type: ValueRenderLocation = switch (location) {
            .static_initializer => .static_initializer,
            else => .initializer,
        };

        const safety_on = switch (zcu.optimizeMode()) {
            .Debug, .ReleaseSafe => true,
            .ReleaseFast, .ReleaseSmall => false,
        };

        switch (ty.toIntern()) {
            .c_longdouble_type,
            .f16_type,
            .f32_type,
            .f64_type,
            .f80_type,
            .f128_type,
            => {
                const bits = ty.floatBits(target);
                // All unsigned ints matching float types are pre-allocated.
                const repr_ty = dg.pt.intType(.unsigned, bits) catch unreachable;

                try w.writeAll("zig_make_");
                try dg.renderTypeForBuiltinFnName(w, ty);
                try w.writeByte('(');
                switch (bits) {
                    16 => try w.print("{x}", .{@as(f16, @bitCast(undefPattern(i16)))}),
                    32 => try w.print("{x}", .{@as(f32, @bitCast(undefPattern(i32)))}),
                    64 => try w.print("{x}", .{@as(f64, @bitCast(undefPattern(i64)))}),
                    80 => try w.print("{x}", .{@as(f80, @bitCast(undefPattern(i80)))}),
                    128 => try w.print("{x}", .{@as(f128, @bitCast(undefPattern(i128)))}),
                    else => unreachable,
                }
                try w.writeAll(", ");
                try dg.renderUndefValue(w, repr_ty, .other);
                return w.writeByte(')');
            },
            .bool_type => try w.writeAll(if (safety_on) "0xaa" else "false"),
            else => switch (ip.indexToKey(ty.toIntern())) {
                .simple_type, // anyerror, c_char (etc), usize, isize
                .int_type,
                .enum_type,
                .error_set_type,
                .inferred_error_set_type,
                => switch (CType.classifyInt(ty, zcu)) {
                    .void => unreachable, // opv
                    .small => |s| {
                        const int = ty.intInfo(zcu);
                        var buf: [std.math.big.int.calcTwosCompLimbCount(128)]std.math.big.Limb = undefined;
                        var bigint: std.math.big.int.Mutable = .init(&buf, undefPattern(u128));
                        bigint.truncate(bigint.toConst(), int.signedness, int.bits);
                        const fmt_undef: FormatInt128 = .{
                            .target = zcu.getTarget(),
                            .int_cty = s,
                            .val = bigint.toConst(),
                            .is_global = location == .static_initializer,
                            .base = 16,
                            .case = .lower,
                        };
                        try w.print("{f}", .{fmt_undef});
                    },
                    .big => |big| {
                        var buf: [std.math.big.int.calcTwosCompLimbCount(128)]std.math.big.Limb = undefined;
                        var limb_bigint: std.math.big.int.Mutable = .init(&buf, undefPattern(u128));
                        limb_bigint.truncate(limb_bigint.toConst(), .unsigned, big.limb_size.bits());
                        const fmt_undef_limb: FormatInt128 = .{
                            .target = zcu.getTarget(),
                            .int_cty = big.limb_size.unsigned(),
                            .val = limb_bigint.toConst(),
                            .is_global = location == .static_initializer,
                            .base = 16,
                            .case = .lower,
                        };

                        if (!location.isInitializer()) {
                            try w.writeByte('(');
                            try dg.renderType(w, ty);
                            try w.writeByte(')');
                        }
                        try w.writeAll("{{");
                        try w.print("{f}", .{fmt_undef_limb});
                        for (1..big.limbs_len) |_| {
                            try w.print(",{f}", .{fmt_undef_limb});
                        }
                        try w.writeAll("}}");
                    },
                },
                .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
                    .one, .many, .c => {
                        try w.writeAll("((");
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                        try dg.renderUndefValue(w, .usize, location);
                        try w.writeByte(')');
                    },
                    .slice => {
                        if (!location.isInitializer()) {
                            try w.writeByte('(');
                            try dg.renderType(w, ty);
                            try w.writeByte(')');
                        }

                        try w.writeByte('{');
                        try dg.renderUndefValue(w, ty.slicePtrFieldType(zcu), initializer_type);
                        try w.writeByte(',');
                        try dg.renderUndefValue(w, .usize, initializer_type);
                        try w.writeByte('}');
                    },
                },
                .opt_type => |child_type| switch (CType.classifyOptional(ty, zcu)) {
                    .npv_payload => unreachable, // opv optional

                    .error_set,
                    .ptr_like,
                    .slice_like,
                    => try dg.renderUndefValue(w, .fromInterned(child_type), location),

                    .opv_payload => {
                        if (!location.isInitializer()) {
                            try w.writeByte('(');
                            try dg.renderType(w, ty);
                            try w.writeByte(')');
                        }
                        try w.writeAll(if (safety_on) "{.is_null=0xaa}" else "{.is_null=false}");
                    },

                    .@"struct" => {
                        if (!location.isInitializer()) {
                            try w.writeByte('(');
                            try dg.renderType(w, ty);
                            try w.writeByte(')');
                        }
                        try w.writeAll("{ .is_null = ");
                        try dg.renderUndefValue(w, .bool, initializer_type);
                        try w.writeAll(", .payload = ");
                        try dg.renderUndefValue(w, .fromInterned(child_type), initializer_type);
                        try w.writeAll(" }");
                    },
                },
                .struct_type => {
                    const loaded_struct = ip.loadStructType(ty.toIntern());
                    switch (loaded_struct.layout) {
                        .auto, .@"extern" => {
                            if (!location.isInitializer()) {
                                try w.writeByte('(');
                                try dg.renderType(w, ty);
                                try w.writeByte(')');
                            }
                            try w.writeByte('{');
                            var field_it = loaded_struct.iterateRuntimeOrder(ip);
                            var need_comma = false;
                            while (field_it.next()) |field_index| {
                                const field_ty: Type = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                                if (!field_ty.hasRuntimeBits(zcu)) continue;

                                if (need_comma) try w.writeByte(',');
                                need_comma = true;
                                try dg.renderUndefValue(w, field_ty, initializer_type);
                            }
                            return w.writeByte('}');
                        },
                        .@"packed" => return dg.renderUndefValue(w, ty.bitpackBackingInt(zcu), location),
                    }
                },
                .tuple_type => |tuple_info| {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }

                    try w.writeByte('{');
                    var need_comma = false;
                    for (0..tuple_info.types.len) |field_index| {
                        if (tuple_info.values.get(ip)[field_index] != .none) continue;
                        const field_ty: Type = .fromInterned(tuple_info.types.get(ip)[field_index]);
                        if (!field_ty.hasRuntimeBits(zcu)) continue;

                        if (need_comma) try w.writeByte(',');
                        need_comma = true;
                        try dg.renderUndefValue(w, field_ty, initializer_type);
                    }
                    return w.writeByte('}');
                },
                .union_type => {
                    const loaded_union = ip.loadUnionType(ty.toIntern());
                    switch (loaded_union.layout) {
                        .auto, .@"extern" => {
                            if (!location.isInitializer()) {
                                try w.writeByte('(');
                                try dg.renderType(w, ty);
                                try w.writeByte(')');
                            }

                            const first_field_ty: Type = for (loaded_union.field_types.get(ip)) |field_ty_ip| {
                                const field_ty: Type = .fromInterned(field_ty_ip);
                                if (!field_ty.hasRuntimeBits(pt.zcu)) continue;
                                break field_ty;
                            } else {
                                assert(loaded_union.has_runtime_tag); // otherwise it does not have runtime bits
                                try w.writeAll("{ .tag = ");
                                try dg.renderUndefValue(w, .fromInterned(loaded_union.enum_tag_type), initializer_type);
                                try w.writeAll(" }");
                                return;
                            };

                            if (loaded_union.layout == .auto) try w.writeByte('{');

                            if (loaded_union.has_runtime_tag) {
                                try w.writeAll(" .tag = ");
                                try dg.renderUndefValue(w, .fromInterned(loaded_union.enum_tag_type), initializer_type);
                                try w.writeAll(", .payload = ");
                            }

                            try w.writeByte('{');
                            try dg.renderUndefValue(w, first_field_ty, initializer_type);
                            try w.writeByte('}');

                            if (loaded_union.has_runtime_tag) try w.writeByte(' ');
                            if (loaded_union.layout == .auto) try w.writeByte('}');
                        },
                        .@"packed" => return dg.renderUndefValue(w, ty.bitpackBackingInt(zcu), location),
                    }
                },
                .error_union_type => |error_union| {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }
                    try w.writeAll("{ .error = ");
                    try dg.renderUndefValue(w, .fromInterned(error_union.error_set_type), initializer_type);
                    if (Type.fromInterned(error_union.payload_type).hasRuntimeBits(zcu)) {
                        try w.writeAll(", .payload = ");
                        try dg.renderUndefValue(w, .fromInterned(error_union.payload_type), initializer_type);
                    }
                    try w.writeAll(" }");
                },
                .array_type, .vector_type => {
                    if (!location.isInitializer()) {
                        try w.writeByte('(');
                        try dg.renderType(w, ty);
                        try w.writeByte(')');
                    }
                    try w.writeByte('{');
                    const ai = ty.arrayInfo(zcu);
                    if (ai.elem_type.eql(.u8, zcu)) {
                        var literal: StringLiteral = .init(w, @intCast(ty.arrayLenIncludingSentinel(zcu)));
                        try literal.start();
                        var index: u64 = 0;
                        while (index < ai.len) : (index += 1) try literal.writeChar(0xaa);
                        if (ai.sentinel) |s| {
                            const s_u8: u8 = @intCast(s.toUnsignedInt(zcu));
                            if (s_u8 != 0) try literal.writeChar(s_u8);
                        }
                        try literal.end();
                    } else {
                        try w.writeByte('{');
                        var index: u64 = 0;
                        while (index < ai.len) : (index += 1) {
                            if (index > 0) try w.writeAll(", ");
                            try dg.renderUndefValue(w, ty.childType(zcu), initializer_type);
                        }
                        if (ai.sentinel) |s| {
                            if (index > 0) try w.writeAll(", ");
                            try dg.renderValue(w, s, location);
                        }
                        try w.writeByte('}');
                    }
                    try w.writeByte('}');
                },
                .anyframe_type,
                .opaque_type,
                .func_type,
                => unreachable,

                .undef,
                .simple_value,
                .@"extern",
                .func,
                .int,
                .err,
                .error_union,
                .enum_literal,
                .enum_tag,
                .float,
                .ptr,
                .slice,
                .opt,
                .aggregate,
                .un,
                .bitpack,
                .memoized_call,
                => unreachable, // values, not types
            },
        }
    }

    fn renderFunctionSignature(
        dg: *DeclGen,
        w: *Writer,
        fn_val: Value,
        fn_align: InternPool.Alignment,
        kind: enum { forward_decl, definition },
        name: union(enum) {
            nav: InternPool.Nav.Index,
            nav_never_tail: InternPool.Nav.Index,
            nav_never_inline: InternPool.Nav.Index,
            @"export": struct {
                main_name: InternPool.NullTerminatedString,
                extern_name: InternPool.NullTerminatedString,
            },
        },
    ) !void {
        const zcu = dg.pt.zcu;
        const ip = &zcu.intern_pool;

        const fn_ty = fn_val.typeOf(zcu);

        const fn_info = zcu.typeToFunc(fn_ty).?;
        if (fn_info.cc == .naked) {
            switch (kind) {
                .forward_decl => try w.writeAll("zig_naked_decl "),
                .definition => try w.writeAll("zig_naked "),
            }
        }

        if (fn_val.getFunction(zcu)) |func| {
            const func_analysis = func.analysisUnordered(ip);

            if (func_analysis.branch_hint == .cold)
                try w.writeAll("zig_cold ");

            if (kind == .definition and func_analysis.disable_intrinsics or dg.mod.no_builtin)
                try w.writeAll("zig_no_builtin ");
        }

        if (fn_info.return_type == .noreturn_type) try w.writeAll("zig_noreturn ");

        // While incomplete types are usually an acceptable substitute for "void", this is not true
        // in function return types, where "void" is the only incomplete type permitted.
        const actual_return_type: Type = .fromInterned(fn_info.return_type);
        const effective_return_type: Type = switch (actual_return_type.classify(zcu)) {
            .no_possible_value => .noreturn,
            .one_possible_value, .fully_comptime => .void, // no runtime bits
            .partially_comptime, .runtime => actual_return_type, // yes runtime bits
        };

        const ret_cty: CType = try .lower(effective_return_type, &dg.ctype_deps, dg.arena, zcu);
        try w.print("{f}", .{ret_cty.fmtDeclaratorPrefix(zcu)});
        if (toCallingConvention(fn_info.cc, zcu)) |call_conv| {
            try w.print("zig_callconv({s}) ", .{call_conv});
        }
        switch (name) {
            .nav => |nav| try renderNavName(w, nav, ip),
            .nav_never_tail => |nav| try w.print("zig_never_tail_{f}__{d}", .{
                fmtIdentUnsolo(ip.getNav(nav).name.toSlice(ip)), @intFromEnum(nav),
            }),
            .nav_never_inline => |nav| try w.print("zig_never_inline_{f}__{d}", .{
                fmtIdentUnsolo(ip.getNav(nav).name.toSlice(ip)), @intFromEnum(nav),
            }),
            .@"export" => |@"export"| try w.print("{f}", .{fmtIdentSolo(@"export".extern_name.toSlice(ip))}),
        }
        {
            try w.writeByte('(');
            var c_param_index: u32 = 0;
            for (fn_info.param_types.get(ip)) |param_ty_ip| {
                const param_ty: Type = .fromInterned(param_ty_ip);
                if (!param_ty.hasRuntimeBits(zcu)) continue;
                if (c_param_index != 0) try w.writeAll(", ");
                try dg.renderTypeAndName(w, param_ty, .{ .arg = c_param_index }, .{
                    .@"const" = kind == .definition,
                }, .none);
                c_param_index += 1;
            }
            if (fn_info.is_var_args) {
                if (c_param_index != 0) try w.writeAll(", ");
                try w.writeAll("...");
            } else if (c_param_index == 0) {
                try w.writeAll("void");
            }
            try w.writeByte(')');
        }
        try w.print("{f}", .{ret_cty.fmtDeclaratorSuffixIgnoreNonstring(zcu)});

        switch (kind) {
            .forward_decl => {
                if (fn_align.toByteUnits()) |a| try w.print(" zig_align_fn({})", .{a});
                switch (name) {
                    .nav, .nav_never_tail, .nav_never_inline => {},
                    .@"export" => |@"export"| {
                        const extern_name = @"export".extern_name.toSlice(ip);
                        const is_mangled = isMangledIdent(extern_name, true);
                        const is_export = @"export".extern_name != @"export".main_name;
                        if (is_mangled and is_export) {
                            try w.print(" zig_mangled_export({f}, {f}, {f})", .{
                                fmtIdentSolo(extern_name),
                                fmtStringLiteral(extern_name, null),
                                fmtStringLiteral(@"export".main_name.toSlice(ip), null),
                            });
                        } else if (is_mangled) {
                            try w.print(" zig_mangled({f}, {f})", .{
                                fmtIdentSolo(extern_name), fmtStringLiteral(extern_name, null),
                            });
                        } else if (is_export) {
                            try w.print(" zig_export({f}, {f})", .{
                                fmtStringLiteral(@"export".main_name.toSlice(ip), null),
                                fmtStringLiteral(extern_name, null),
                            });
                        }
                    },
                }
            },
            .definition => {},
        }
    }

    /// Renders the C lowering of the given Zig type to `w`. This renders the type name---to render
    /// a declarator with this type, see instead `renderTypeAndName`.
    fn renderType(dg: *DeclGen, w: *Writer, ty: Type) (Writer.Error || Allocator.Error)!void {
        const zcu = dg.pt.zcu;
        const cty: CType = try .lower(ty, &dg.ctype_deps, dg.arena, zcu);
        try w.print("{f}", .{cty.fmtTypeName(zcu)});
    }

    const IntCastContext = union(enum) {
        c_value: struct {
            f: *Function,
            value: CValue,
            v: Vectorize,
        },
        value: struct {
            value: Value,
        },

        pub fn writeValue(self: *const IntCastContext, dg: *DeclGen, w: *Writer, location: ValueRenderLocation) !void {
            switch (self.*) {
                .c_value => |v| {
                    try v.f.writeCValue(w, v.value, location);
                    try v.v.elem(v.f, w);
                },
                .value => |v| try dg.renderValue(w, v.value, location),
            }
        }
    };
    fn intCastIsNoop(dg: *DeclGen, dest_ty: Type, src_ty: Type) bool {
        const pt = dg.pt;
        const zcu = pt.zcu;
        const dest_bits = dest_ty.bitSize(zcu);
        const dest_int_info = dest_ty.intInfo(pt.zcu);

        const src_is_ptr = src_ty.isPtrAtRuntime(pt.zcu);
        const src_eff_ty: Type = if (src_is_ptr) switch (dest_int_info.signedness) {
            .unsigned => .usize,
            .signed => .isize,
        } else src_ty;

        const src_bits = src_eff_ty.bitSize(zcu);
        const src_int_info = if (src_eff_ty.isAbiInt(pt.zcu)) src_eff_ty.intInfo(pt.zcu) else null;
        if (dest_bits <= 64 and src_bits <= 64) {
            const needs_cast = src_int_info == null or
                (toCIntBits(dest_int_info.bits) != toCIntBits(src_int_info.?.bits) or
                    dest_int_info.signedness != src_int_info.?.signedness);
            return !needs_cast and !src_is_ptr;
        } else return false;
    }
    /// Renders a cast to an int type, from either an int or a pointer.
    ///
    /// Some platforms don't have 128 bit integers, so we need to use
    /// the zig_make_ and zig_lo_ macros in those cases.
    ///
    ///   | Dest type bits   | Src type         | Result
    ///   |------------------|------------------|---------------------------|
    ///   | < 64 bit integer | pointer          | (zig_<dest_ty>)(zig_<u|i>size)src
    ///   | < 64 bit integer | < 64 bit integer | (zig_<dest_ty>)src
    ///   | < 64 bit integer | > 64 bit integer | zig_lo(src)
    ///   | > 64 bit integer | pointer          | zig_make_<dest_ty>(0, (zig_<u|i>size)src)
    ///   | > 64 bit integer | < 64 bit integer | zig_make_<dest_ty>(0, src)
    ///   | > 64 bit integer | > 64 bit integer | zig_make_<dest_ty>(zig_hi_<src_ty>(src), zig_lo_<src_ty>(src))
    fn renderIntCast(
        dg: *DeclGen,
        w: *Writer,
        dest_ty: Type,
        context: IntCastContext,
        src_ty: Type,
        location: ValueRenderLocation,
    ) !void {
        const pt = dg.pt;
        const zcu = pt.zcu;
        const dest_bits = dest_ty.bitSize(zcu);
        const dest_int_info = dest_ty.intInfo(zcu);

        const src_is_ptr = src_ty.isPtrAtRuntime(zcu);
        const src_eff_ty: Type = if (src_is_ptr) switch (dest_int_info.signedness) {
            .unsigned => .usize,
            .signed => .isize,
        } else src_ty;

        const src_bits = src_eff_ty.bitSize(zcu);
        const src_int_info = if (src_eff_ty.isAbiInt(zcu)) src_eff_ty.intInfo(zcu) else null;
        if (dest_bits <= 64 and src_bits <= 64) {
            const needs_cast = src_int_info == null or
                (toCIntBits(dest_int_info.bits) != toCIntBits(src_int_info.?.bits) or
                    dest_int_info.signedness != src_int_info.?.signedness);

            if (needs_cast) {
                try w.writeByte('(');
                try dg.renderType(w, dest_ty);
                try w.writeByte(')');
            }
            if (src_is_ptr) {
                try w.writeByte('(');
                try dg.renderType(w, src_eff_ty);
                try w.writeByte(')');
            }
            try context.writeValue(dg, w, location);
        } else if (dest_bits <= 64 and src_bits > 64) {
            assert(!src_is_ptr);
            if (dest_bits < 64) {
                try w.writeByte('(');
                try dg.renderType(w, dest_ty);
                try w.writeByte(')');
            }
            try w.writeAll("zig_lo_");
            try dg.renderTypeForBuiltinFnName(w, src_eff_ty);
            try w.writeByte('(');
            try context.writeValue(dg, w, .other);
            try w.writeByte(')');
        } else if (dest_bits > 64 and src_bits <= 64) {
            try w.writeAll("zig_make_");
            try dg.renderTypeForBuiltinFnName(w, dest_ty);
            try w.writeAll("(0, ");
            if (src_is_ptr) {
                try w.writeByte('(');
                try dg.renderType(w, src_eff_ty);
                try w.writeByte(')');
            }
            try context.writeValue(dg, w, .other);
            try w.writeByte(')');
        } else {
            assert(!src_is_ptr);
            try w.writeAll("zig_make_");
            try dg.renderTypeForBuiltinFnName(w, dest_ty);
            try w.writeAll("(zig_hi_");
            try dg.renderTypeForBuiltinFnName(w, src_eff_ty);
            try w.writeByte('(');
            try context.writeValue(dg, w, .other);
            try w.writeAll("), zig_lo_");
            try dg.renderTypeForBuiltinFnName(w, src_eff_ty);
            try w.writeByte('(');
            try context.writeValue(dg, w, .other);
            try w.writeAll("))");
        }
    }

    /// Renders to `w` a C declarator whose type is the C lowering of the given Zig type.
    fn renderTypeAndName(
        dg: *DeclGen,
        w: *Writer,
        ty: Type,
        name: CValue,
        qualifiers: CQualifiers,
        alignment: Alignment,
    ) !void {
        const zcu = dg.pt.zcu;
        const ip = &zcu.intern_pool;
        const cty: CType = try .lower(ty, &dg.ctype_deps, dg.arena, zcu);
        try w.print("{f}", .{cty.fmtDeclaratorPrefix(zcu)});
        if (alignment != .none) switch (alignment.order(ty.abiAlignment(zcu))) {
            .lt => try w.print("zig_under_align({d}) ", .{alignment.toByteUnits().?}),
            .eq => {},
            .gt => try w.print("zig_align({d}) ", .{alignment.toByteUnits().?}),
        };
        if (qualifiers.@"const") try w.writeAll("const ");
        if (qualifiers.@"volatile") try w.writeAll("volatile ");
        if (qualifiers.restrict) try w.writeAll("restrict ");
        switch (name) {
            .new_local, .local => |i| try w.print("t{d}", .{i}),
            .arg => |i| try w.print("a{d}", .{i}),
            .constant => |uav| try renderUavName(w, uav),
            .nav => |nav| try renderNavName(w, nav, ip),
            .identifier => |ident| try w.print("{f}", .{fmtIdentSolo(ident)}),
            else => unreachable,
        }
        try w.print("{f}", .{cty.fmtDeclaratorSuffix(zcu)});
    }

    fn writeCValue(dg: *DeclGen, w: *Writer, c_value: CValue) Error!void {
        switch (c_value) {
            .none, .new_local, .local, .local_ref => unreachable,
            .constant => |uav| try renderUavName(w, uav),
            .arg => unreachable,
            .field => |i| try w.print("f{d}", .{i}),
            .nav => |nav| try renderNavName(w, nav, &dg.pt.zcu.intern_pool),
            .nav_ref => |nav| {
                try w.writeByte('&');
                try renderNavName(w, nav, &dg.pt.zcu.intern_pool);
            },
            .undef => |ty| try dg.renderUndefValue(w, ty, .other),
            .identifier => |ident| try w.print("{f}", .{fmtIdentSolo(ident)}),
            .payload_identifier => |ident| try w.print("{f}.{f}", .{
                fmtIdentSolo("payload"),
                fmtIdentSolo(ident),
            }),
        }
    }

    fn writeCValueDeref(dg: *DeclGen, w: *Writer, c_value: CValue) !void {
        switch (c_value) {
            .none,
            .new_local,
            .local,
            .local_ref,
            .constant,
            .arg,
            => unreachable,
            .field => |i| try w.print("f{d}", .{i}),
            .nav => |nav| {
                try w.writeAll("(*");
                try renderNavName(w, nav, &dg.pt.zcu.intern_pool);
                try w.writeByte(')');
            },
            .nav_ref => |nav| try renderNavName(w, nav, &dg.pt.zcu.intern_pool),
            .undef => unreachable,
            .identifier => |ident| try w.print("(*{f})", .{fmtIdentSolo(ident)}),
            .payload_identifier => |ident| try w.print("(*{f}.{f})", .{
                fmtIdentSolo("payload"),
                fmtIdentSolo(ident),
            }),
        }
    }

    fn writeCValueMember(
        dg: *DeclGen,
        w: *Writer,
        c_value: CValue,
        member: CValue,
    ) Error!void {
        try dg.writeCValue(w, c_value);
        try w.writeByte('.');
        try dg.writeCValue(w, member);
    }

    fn writeCValueDerefMember(
        dg: *DeclGen,
        w: *Writer,
        c_value: CValue,
        member: CValue,
    ) !void {
        switch (c_value) {
            .none,
            .new_local,
            .local,
            .local_ref,
            .constant,
            .field,
            .undef,
            .arg,
            => unreachable,
            .nav, .identifier, .payload_identifier => {
                try dg.writeCValue(w, c_value);
                try w.writeAll("->");
            },
            .nav_ref => {
                try dg.writeCValueDeref(w, c_value);
                try w.writeByte('.');
            },
        }
        try dg.writeCValue(w, member);
    }

    fn renderTypeForBuiltinFnName(dg: *DeclGen, w: *Writer, ty: Type) !void {
        const zcu = dg.pt.zcu;
        switch (ty.zigTypeTag(zcu)) {
            .bool => return w.writeAll("u8"),
            .float => return w.print("f{d}", .{ty.floatBits(zcu.getTarget())}),
            else => {},
        }
        if (ty.isPtrAtRuntime(zcu)) {
            return w.print("p{d}", .{zcu.getTarget().ptrBitWidth()});
        }
        switch (CType.classifyInt(ty, zcu)) {
            .void => unreachable, // opv
            .small => try w.print("{c}{d}", .{
                signAbbrev(ty.intInfo(zcu).signedness),
                ty.abiSize(zcu) * 8,
            }),
            .big => try w.writeAll("big"),
        }
    }

    fn renderBuiltinInfo(dg: *DeclGen, w: *Writer, ty: Type, info: BuiltinInfo) !void {
        const pt = dg.pt;
        const zcu = pt.zcu;

        const is_big = lowersToBigInt(ty, zcu);
        switch (info) {
            .none => if (!is_big) return,
            .bits => {},
        }

        const int_info: std.builtin.Type.Int = if (ty.isAbiInt(zcu)) ty.intInfo(zcu) else .{
            .signedness = .unsigned,
            .bits = @intCast(ty.bitSize(zcu)),
        };

        if (is_big) try w.print(", {}", .{int_info.signedness == .signed});
        try w.print(", {f}", .{try dg.fmtIntLiteralDec(
            try pt.intValue(if (is_big) .u16 else .u8, int_info.bits),
            .other,
        )});
    }

    fn fmtIntLiteral(
        dg: *DeclGen,
        val: Value,
        loc: ValueRenderLocation,
        base: u8,
        case: std.fmt.Case,
    ) !std.fmt.Alt(FormatIntLiteralContext, formatIntLiteral) {
        // If there's a bigint type involved, mark a dependency on it.
        const cty: CType = try .lower(val.typeOf(dg.pt.zcu), &dg.ctype_deps, dg.arena, dg.pt.zcu);
        return .{ .data = .{
            .dg = dg,
            .loc = loc,
            .val = val,
            .cty = cty,
            .base = base,
            .case = case,
        } };
    }

    fn fmtIntLiteralDec(
        dg: *DeclGen,
        val: Value,
        loc: ValueRenderLocation,
    ) !std.fmt.Alt(FormatIntLiteralContext, formatIntLiteral) {
        return fmtIntLiteral(dg, val, loc, 10, .lower);
    }

    fn fmtIntLiteralHex(
        dg: *DeclGen,
        val: Value,
        loc: ValueRenderLocation,
    ) !std.fmt.Alt(FormatIntLiteralContext, formatIntLiteral) {
        return fmtIntLiteral(dg, val, loc, 16, .lower);
    }
};

const CQualifiers = packed struct {
    @"const": bool = false,
    @"volatile": bool = false,
    restrict: bool = false,
};

pub fn genGlobalAsm(zcu: *Zcu, w: *Writer) !void {
    for (zcu.global_assembly.values()) |asm_source| {
        try w.print("__asm({f});\n", .{fmtStringLiteral(asm_source, null)});
    }
}

pub fn genErrDecls(
    zcu: *const Zcu,
    w: *Writer,
    slice_const_u8_sentinel_0_type_name: []const u8,
) Writer.Error!void {
    const ip = &zcu.intern_pool;

    const names = ip.global_error_set.getNamesFromMainThread();
    // Don't generate an invalid empty enum if the global error set is empty!
    if (names.len > 0) {
        try w.writeAll("enum {\n");
        for (names, 1..) |name_nts, value| {
            try w.writeByte(' ');
            try renderErrorName(w, name_nts.toSlice(ip));
            try w.print(" = {d}u,\n", .{value});
        }
        try w.writeAll("};\n");
    }

    for (names) |name_nts| {
        const name = name_nts.toSlice(ip);
        try w.print(
            "static uint8_t const zig_errorName_{f}[] = {f};\n",
            .{ fmtIdentUnsolo(name), fmtStringLiteral(name, 0) },
        );
    }

    try w.print(
        "static {s} const zig_errorName[{d}] = {{",
        .{ slice_const_u8_sentinel_0_type_name, names.len },
    );
    if (names.len > 0) try w.writeByte('\n');
    for (names) |name_nts| {
        const name = name_nts.toSlice(ip);
        try w.print(
            " {{zig_errorName_{f},{d}}},\n",
            .{ fmtIdentUnsolo(name), name.len },
        );
    }
    try w.writeAll("};\n");
}

pub fn genTagNameFn(
    zcu: *const Zcu,
    w: *Writer,
    slice_const_u8_sentinel_0_type_name: []const u8,
    enum_ty: Type,
    enum_type_name: []const u8,
) Writer.Error!void {
    const ip = &zcu.intern_pool;
    const loaded_enum = ip.loadEnumType(enum_ty.toIntern());
    assert(loaded_enum.field_names.len > 0);
    if (Type.fromInterned(loaded_enum.int_tag_type).bitSize(zcu) > 64) {
        @panic("TODO CBE: tagName for enum over 64 bits");
    }

    try w.print("static {s} zig_tagName_{f}__{d}({s} tag) {{\n", .{
        slice_const_u8_sentinel_0_type_name,
        fmtIdentUnsolo(loaded_enum.name.toSlice(ip)),
        @intFromEnum(enum_ty.toIntern()),
        enum_type_name,
    });
    for (loaded_enum.field_names.get(ip), 0..) |field_name, field_index| {
        try w.print(" static uint8_t const name{d}[] = {f};\n", .{
            field_index, fmtStringLiteral(field_name.toSlice(ip), 0),
        });
    }

    try w.writeAll(" switch (tag) {\n");
    const field_values = loaded_enum.field_values.get(ip);
    for (loaded_enum.field_names.get(ip), 0..) |field_name, field_index| {
        const field_int: i65 = int: {
            if (field_values.len == 0) break :int field_index;
            const field_val: Value = .fromInterned(field_values[field_index]);
            break :int field_val.getUnsignedInt(zcu) orelse field_val.toSignedInt(zcu);
        };
        try w.print("  case {d}: return ({s}){{name{d},{d}}};\n", .{
            field_int,
            slice_const_u8_sentinel_0_type_name,
            field_index,
            field_name.toSlice(ip).len,
        });
    }
    try w.writeAll(
        \\ }
        \\ zig_unreachable();
        \\}
        \\
    );
}

pub fn genLazyCallModifierFn(
    dg: *DeclGen,
    fn_nav: InternPool.Nav.Index,
    kind: enum { never_tail, never_inline },
    w: *Writer,
) Error!void {
    const zcu = dg.pt.zcu;
    const ip = &zcu.intern_pool;

    const fn_val = zcu.navValue(fn_nav);

    try w.print("static zig_{t} ", .{kind});
    try dg.renderFunctionSignature(w, fn_val, .none, .definition, switch (kind) {
        .never_tail => .{ .nav_never_tail = fn_nav },
        .never_inline => .{ .nav_never_inline = fn_nav },
    });
    try w.writeAll(" {\n return ");
    try renderNavName(w, fn_nav, ip);
    try w.writeByte('(');
    {
        const func_type = ip.indexToKey(fn_val.typeOf(zcu).toIntern()).func_type;
        var c_param_index: u32 = 0;
        for (func_type.param_types.get(ip)) |param_ty_ip| {
            const param_ty: Type = .fromInterned(param_ty_ip);
            if (!param_ty.hasRuntimeBits(zcu)) continue;
            if (c_param_index != 0) try w.writeAll(", ");
            try w.print("a{d}", .{c_param_index});
            c_param_index += 1;
        }
    }
    try w.writeAll(");\n}\n");
}

pub fn generate(
    lf: *link.File,
    pt: Zcu.PerThread,
    src_loc: Zcu.LazySrcLoc,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) @import("../codegen.zig").CodeGenError!Mir {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    _ = src_loc;
    assert(lf.tag == .c);

    const func = zcu.funcInfo(func_index);

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var function: Function = .{
        .value_map = .init(gpa),
        .air = air.*,
        .liveness = liveness.*.?,
        .func_index = func_index,
        .dg = .{
            .gpa = gpa,
            .arena = arena.allocator(),
            .pt = pt,
            .mod = zcu.navFileScope(func.owner_nav).mod.?,
            .error_msg = null,
            .owner_nav = func.owner_nav.toOptional(),
            .is_naked_fn = Type.fromInterned(func.ty).fnCallingConvention(zcu) == .naked,
            .expected_block = null,
            .ctype_deps = .empty,
            .uavs = .empty,
        },
        .code = .init(gpa),
        .indent_counter = 0,
        .need_tag_name_funcs = .empty,
        .need_never_tail_funcs = .empty,
        .need_never_inline_funcs = .empty,
    };
    defer {
        function.code.deinit();
        function.dg.ctype_deps.deinit(gpa);
        function.dg.uavs.deinit(gpa);
        function.deinit();
    }

    var fwd_decl: Writer.Allocating = .init(gpa);
    defer fwd_decl.deinit();

    var code_header: Writer.Allocating = .init(gpa);
    defer code_header.deinit();

    genFunc(&function, &fwd_decl.writer, &code_header.writer) catch |err| switch (err) {
        error.AnalysisFail => return zcu.codegenFailMsg(func.owner_nav, function.dg.error_msg.?),
        error.WriteFailed => return error.OutOfMemory,
        error.OutOfMemory => |e| return e,
    };

    var mir: Mir = .{
        .fwd_decl = &.{},
        .code_header = &.{},
        .code = &.{},
        .ctype_deps = function.dg.ctype_deps.move(),
        .need_uavs = function.dg.uavs.move(),
        .need_tag_name_funcs = function.need_tag_name_funcs.move(),
        .need_never_tail_funcs = function.need_never_tail_funcs.move(),
        .need_never_inline_funcs = function.need_never_inline_funcs.move(),
    };
    errdefer mir.deinit(gpa);
    mir.fwd_decl = try fwd_decl.toOwnedSlice();
    mir.code_header = try code_header.toOwnedSlice();
    mir.code = try function.code.toOwnedSlice();
    return mir;
}

pub fn genFunc(f: *Function, fwd_decl_writer: *Writer, header_writer: *Writer) Error!void {
    const tracy = trace(@src());
    defer tracy.end();

    const zcu = f.dg.pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = f.dg.gpa;
    const nav_index = f.dg.owner_nav.unwrap().?;
    const nav_val = zcu.navValue(nav_index);
    const nav = ip.getNav(nav_index);

    try fwd_decl_writer.writeAll("static ");
    try f.dg.renderFunctionSignature(
        fwd_decl_writer,
        nav_val,
        nav.resolved.?.@"align",
        .forward_decl,
        .{ .nav = nav_index },
    );
    try fwd_decl_writer.writeAll(";\n");

    if (nav.resolved.?.@"linksection".toSlice(ip)) |s|
        try header_writer.print("zig_linksection_fn({f}) ", .{fmtStringLiteral(s, null)});
    try f.dg.renderFunctionSignature(
        header_writer,
        nav_val,
        .none,
        .definition,
        .{ .nav = nav_index },
    );
    try header_writer.writeAll(" {\n ");

    f.free_locals_map.clearRetainingCapacity();

    const main_body = f.air.getMainBody();
    f.indent();
    try genBodyResolveState(f, undefined, &.{}, main_body, true);
    try f.outdent();
    try f.code.writer.writeByte('}');
    try f.newline();
    if (f.dg.expected_block) |_|
        return f.fail("runtime code not allowed in naked function", .{});

    // Take advantage of the free_locals map to bucket locals per type. All
    // locals corresponding to AIR instructions should be in there due to
    // Liveness analysis, however, locals from alloc instructions will be
    // missing. These are added now to complete the map. Then we can sort by
    // alignment, descending.
    const free_locals = &f.free_locals_map;
    assert(f.value_map.count() == 0); // there must not be any unfreed locals
    for (f.allocs.keys(), f.allocs.values()) |local_index, should_emit| {
        if (!should_emit) continue;
        const local = f.locals.items[local_index];
        log.debug("inserting local {d} into free_locals", .{local_index});
        const gop = try free_locals.getOrPut(gpa, local);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        try gop.value_ptr.putNoClobber(gpa, local_index, {});
    }

    const SortContext = struct {
        zcu: *const Zcu,
        keys: []const LocalType,

        pub fn lessThan(ctx: @This(), lhs_index: usize, rhs_index: usize) bool {
            const lhs = ctx.keys[lhs_index];
            const rhs = ctx.keys[rhs_index];
            const lhs_align = switch (lhs.alignment) {
                .none => lhs.type.abiAlignment(ctx.zcu),
                else => |a| a,
            };
            const rhs_align = switch (rhs.alignment) {
                .none => rhs.type.abiAlignment(ctx.zcu),
                else => |a| a,
            };
            return Alignment.compareStrict(lhs_align, .gt, rhs_align);
        }
    };
    free_locals.sort(SortContext{
        .zcu = zcu,
        .keys = free_locals.keys(),
    });

    for (free_locals.values()) |list| {
        for (list.keys()) |local_index| {
            const local = f.locals.items[local_index];
            try f.dg.renderTypeAndName(header_writer, local.type, .{ .local = local_index }, .{}, local.alignment);
            try header_writer.writeAll(";\n ");
        }
    }
}

pub fn genDecl(dg: *DeclGen, w: *Writer) Error!void {
    const tracy = trace(@src());
    defer tracy.end();

    const pt = dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(dg.owner_nav.unwrap().?);
    const nav_ty: Type = .fromInterned(nav.resolved.?.type);

    if (ip.indexToKey(nav.resolved.?.value) == .@"extern") return;

    const init_val: Value = .fromInterned(nav.resolved.?.value);

    if (nav.resolved.?.@"linksection".toSlice(ip)) |s| {
        try w.print("zig_linksection({f}) ", .{fmtStringLiteral(s, null)});
    }

    // We don't bother underaligning---it's unnecessary and hurts compatibility.
    const a = nav.resolved.?.@"align";
    if (a != .none and a.compareStrict(.gt, nav_ty.abiAlignment(zcu))) {
        try w.print("zig_align({d}) ", .{a.toByteUnits().?});
    }

    try genDeclValue(dg, w, .{
        .name = .{ .nav = dg.owner_nav.unwrap().? },
        .@"const" = nav.resolved.?.@"const",
        .@"threadlocal" = nav.resolved.?.@"threadlocal",
        .init_val = init_val,
    });
}
pub fn genDeclFwd(dg: *DeclGen, w: *Writer) Error!void {
    const tracy = trace(@src());
    defer tracy.end();

    const pt = dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(dg.owner_nav.unwrap().?);
    const nav_ty: Type = .fromInterned(nav.resolved.?.type);

    const init_val: Value = switch (ip.indexToKey(nav.resolved.?.value)) {
        else => .fromInterned(nav.resolved.?.value),

        .@"extern" => |@"extern"| switch (nav_ty.zigTypeTag(zcu)) {
            .@"fn" => {
                try w.writeAll("zig_extern ");
                try dg.renderFunctionSignature(
                    w,
                    .fromInterned(nav.resolved.?.value),
                    nav.resolved.?.@"align",
                    .forward_decl,
                    .{ .@"export" = .{
                        .main_name = nav.name,
                        .extern_name = nav.name,
                    } },
                );
                try w.writeAll(";\n");
                return;
            },
            else => {
                switch (@"extern".linkage) {
                    .internal => try w.writeAll("static "),
                    .strong => try w.print("zig_extern zig_visibility({t}) ", .{@"extern".visibility}),
                    .weak => try w.print("zig_extern zig_weak_linkage zig_visibility({t}) ", .{@"extern".visibility}),
                    .link_once => return dg.fail("TODO: CBE: implement linkonce linkage?", .{}),
                }
                if (nav.resolved.?.@"threadlocal" and !dg.mod.single_threaded) {
                    try w.writeAll("zig_threadlocal ");
                }
                try dg.renderTypeAndName(
                    w,
                    .fromInterned(nav.resolved.?.type),
                    .{ .nav = dg.owner_nav.unwrap().? },
                    .{ .@"const" = nav.resolved.?.@"const" },
                    nav.resolved.?.@"align",
                );
                try w.writeAll(";\n");
                return;
            },
        },
    };

    // We don't bother underaligning---it's unnecessary and hurts compatibility.
    const a = nav.resolved.?.@"align";
    if (a != .none and a.compareStrict(.gt, nav_ty.abiAlignment(zcu))) {
        try w.print("zig_align({d}) ", .{a.toByteUnits().?});
    }

    try genDeclValueFwd(dg, w, .{
        .name = .{ .nav = dg.owner_nav.unwrap().? },
        .@"const" = nav.resolved.?.@"const",
        .@"threadlocal" = nav.resolved.?.@"threadlocal",
        .init_val = init_val,
    });
}
pub fn genDeclValue(dg: *DeclGen, w: *Writer, options: struct {
    name: CValue,
    @"const": bool,
    @"threadlocal": bool,
    init_val: Value,
}) Error!void {
    const zcu = dg.pt.zcu;
    const ty = options.init_val.typeOf(zcu);
    if (options.@"threadlocal" and !dg.mod.single_threaded) {
        try w.writeAll("zig_threadlocal ");
    }
    try dg.renderTypeAndName(w, ty, options.name, .{ .@"const" = options.@"const" }, .none);
    try w.writeAll(" = ");
    try dg.renderValue(w, options.init_val, .static_initializer);
    try w.writeAll(";\n");
}
pub fn genDeclValueFwd(dg: *DeclGen, w: *Writer, options: struct {
    name: CValue,
    @"const": bool,
    @"threadlocal": bool,
    init_val: Value,
}) Error!void {
    const zcu = dg.pt.zcu;
    const ty = options.init_val.typeOf(zcu);
    try w.writeAll("static ");
    if (options.@"threadlocal" and !dg.mod.single_threaded) {
        try w.writeAll("zig_threadlocal ");
    }
    try dg.renderTypeAndName(w, ty, options.name, .{ .@"const" = options.@"const" }, .none);
    try w.writeAll(";\n");
}

pub fn genExports(dg: *DeclGen, w: *Writer, exported: Zcu.Exported, export_indices: []const Zcu.Export.Index) !void {
    const zcu = dg.pt.zcu;
    const ip = &zcu.intern_pool;

    const main_name = export_indices[0].ptr(zcu).opts.name;
    try w.writeAll("#define ");
    switch (exported) {
        .nav => |nav| try renderNavName(w, nav, ip),
        .uav => |uav| try renderUavName(w, Value.fromInterned(uav)),
    }
    try w.writeByte(' ');
    try w.print("{f}", .{fmtIdentSolo(main_name.toSlice(ip))});
    try w.writeByte('\n');

    const exported_val = exported.getValue(zcu);
    if (ip.isFunctionType(exported_val.typeOf(zcu).toIntern())) return for (export_indices) |export_index| {
        const @"export" = export_index.ptr(zcu);
        try w.writeAll("zig_extern ");
        if (@"export".opts.linkage == .weak) try w.writeAll("zig_weak_linkage_fn ");
        try dg.renderFunctionSignature(
            w,
            exported.getValue(zcu),
            exported.getAlign(zcu),
            .forward_decl,
            .{ .@"export" = .{
                .main_name = main_name,
                .extern_name = @"export".opts.name,
            } },
        );
        try w.writeAll(";\n");
    };
    const is_const = switch (exported) {
        .nav => |nav| ip.getNav(nav).resolved.?.@"const",
        .uav => true,
    };
    for (export_indices) |export_index| {
        const @"export" = export_index.ptr(zcu);
        try w.writeAll("zig_extern ");
        if (@"export".opts.linkage == .weak) try w.writeAll("zig_weak_linkage ");
        if (@"export".opts.section.toSlice(ip)) |s| try w.print("zig_linksection({f}) ", .{
            fmtStringLiteral(s, null),
        });
        const extern_name = @"export".opts.name.toSlice(ip);
        const is_mangled = isMangledIdent(extern_name, true);
        const is_export = @"export".opts.name != main_name;
        try dg.renderTypeAndName(
            w,
            exported.getValue(zcu).typeOf(zcu),
            .{ .identifier = extern_name },
            .{ .@"const" = is_const },
            exported.getAlign(zcu),
        );
        if (is_mangled and is_export) {
            try w.print(" zig_mangled_export({f}, {f}, {f})", .{
                fmtIdentSolo(extern_name),
                fmtStringLiteral(extern_name, null),
                fmtStringLiteral(main_name.toSlice(ip), null),
            });
        } else if (is_mangled) {
            try w.print(" zig_mangled({f}, {f})", .{
                fmtIdentSolo(extern_name), fmtStringLiteral(extern_name, null),
            });
        } else if (is_export) {
            try w.print(" zig_export({f}, {f})", .{
                fmtStringLiteral(main_name.toSlice(ip), null),
                fmtStringLiteral(extern_name, null),
            });
        }
        try w.writeAll(";\n");
    }
}

/// Generate code for an entire body which ends with a `noreturn` instruction. The states of
/// `value_map` and `free_locals_map` are undefined after the generation, and new locals may not
/// have been added to `free_locals_map`. For a version of this function that restores this state,
/// see `genBodyResolveState`.
fn genBody(f: *Function, body: []const Air.Inst.Index) Error!void {
    const w = &f.code.writer;
    if (body.len == 0) {
        try w.writeAll("{}");
    } else {
        try w.writeByte('{');
        f.indent();
        try f.newline();
        try genBodyInner(f, body);
        try f.outdent();
        try w.writeByte('}');
    }
}

/// Generate code for an entire body which ends with a `noreturn` instruction. The states of
/// `value_map` and `free_locals_map` are restored to their original values, and any non-allocated
/// locals introduced within the body are correctly added to `free_locals_map`. Operands in
/// `leading_deaths` have their deaths processed before the body is generated.
/// A scope is introduced (using braces) only if `inner` is `false`.
/// If `leading_deaths` is empty, `inst` may be `undefined`.
fn genBodyResolveState(f: *Function, inst: Air.Inst.Index, leading_deaths: []const Air.Inst.Index, body: []const Air.Inst.Index, inner: bool) Error!void {
    if (body.len == 0) {
        // Don't go to the expense of cloning everything!
        if (!inner) try f.code.writer.writeAll("{}");
        return;
    }

    // TODO: we can probably avoid the copies in some other common cases too.

    const gpa = f.dg.gpa;

    // Save the original value_map and free_locals_map so that we can restore them after the body.
    var old_value_map = try f.value_map.clone();
    defer old_value_map.deinit();
    var old_free_locals = try cloneFreeLocalsMap(gpa, &f.free_locals_map);
    defer deinitFreeLocalsMap(gpa, &old_free_locals);

    // Remember how many locals there were before entering the body so that we can free any that
    // were newly introduced. Any new locals must necessarily be logically free after the then
    // branch is complete.
    const pre_locals_len: LocalIndex = @intCast(f.locals.items.len);

    for (leading_deaths) |death| {
        try die(f, inst, death.toRef());
    }

    if (inner) {
        try genBodyInner(f, body);
    } else {
        try genBody(f, body);
    }

    f.value_map.deinit();
    f.value_map = old_value_map.move();
    deinitFreeLocalsMap(gpa, &f.free_locals_map);
    f.free_locals_map = old_free_locals.move();

    // Now, use the lengths we stored earlier to detect any locals the body generated, and free
    // them, unless they were used to store allocs.

    for (pre_locals_len..f.locals.items.len) |local_i| {
        const local_index: LocalIndex = @intCast(local_i);
        if (f.allocs.contains(local_index)) {
            continue;
        }
        try freeLocal(f, inst, local_index, null);
    }
}

fn genBodyInner(f: *Function, body: []const Air.Inst.Index) Error!void {
    const zcu = f.dg.pt.zcu;
    const ip = &zcu.intern_pool;
    const air_tags = f.air.instructions.items(.tag);
    const air_datas = f.air.instructions.items(.data);

    for (body) |inst| {
        if (f.dg.expected_block) |_|
            return f.fail("runtime code not allowed in naked function", .{});
        if (f.liveness.isUnused(inst) and !f.air.mustLower(inst, ip))
            continue;

        const result_value = switch (air_tags[@intFromEnum(inst)]) {
            // zig fmt: off
            .inferred_alloc, .inferred_alloc_comptime => unreachable,

            // No "scalarize" legalizations are enabled, so these instructions never appear.
            .legalize_vec_elem_val   => unreachable,
            .legalize_vec_store_elem => unreachable,
            // No soft float legalizations are enabled.
            .legalize_compiler_rt_call => unreachable,

            .arg      => try airArg(f, inst),

            .breakpoint => try airBreakpoint(f),
            .ret_addr   => try airRetAddr(f, inst),
            .frame_addr => try airFrameAddress(f, inst),

            .ptr_add => try airPtrAddSub(f, inst, '+'),
            .ptr_sub => try airPtrAddSub(f, inst, '-'),

            // TODO use a different strategy for add, sub, mul, div
            // that communicates to the optimizer that wrapping is UB.
            .add => try airBinOp(f, inst, "+", "add", .none),
            .sub => try airBinOp(f, inst, "-", "sub", .none),
            .mul => try airBinOp(f, inst, "*", "mul", .none),

            .neg => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "neg", .none),
            .div_float => try airBinBuiltinCall(f, inst, "div", .none),

            .div_trunc, .div_exact => try airBinOp(f, inst, "/", "div_trunc", .none),
            .rem => blk: {
                const bin_op = air_datas[@intFromEnum(inst)].bin_op;
                const lhs_scalar_ty = f.typeOf(bin_op.lhs).scalarType(zcu);
                // For binary operations @TypeOf(lhs)==@TypeOf(rhs),
                // so we only check one.
                break :blk if (lhs_scalar_ty.isInt(zcu))
                    try airBinOp(f, inst, "%", "rem", .none)
                else
                    try airBinBuiltinCall(f, inst, "fmod", .none);
            },
            .div_floor => try airBinBuiltinCall(f, inst, "div_floor", .none),
            .mod       => try airBinBuiltinCall(f, inst, "mod", .none),
            .abs       => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].ty_op.operand, "abs", .none),

            .add_wrap => try airBinBuiltinCall(f, inst, "addw", .bits),
            .sub_wrap => try airBinBuiltinCall(f, inst, "subw", .bits),
            .mul_wrap => try airBinBuiltinCall(f, inst, "mulw", .bits),

            .add_sat => try airBinBuiltinCall(f, inst, "adds", .bits),
            .sub_sat => try airBinBuiltinCall(f, inst, "subs", .bits),
            .mul_sat => try airBinBuiltinCall(f, inst, "muls", .bits),
            .shl_sat => try airBinBuiltinCall(f, inst, "shls", .bits),

            .sqrt        => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "sqrt", .none),
            .sin         => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "sin", .none),
            .cos         => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "cos", .none),
            .tan         => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "tan", .none),
            .exp         => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "exp", .none),
            .exp2        => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "exp2", .none),
            .log         => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "log", .none),
            .log2        => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "log2", .none),
            .log10       => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "log10", .none),
            .floor       => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "floor", .none),
            .ceil        => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "ceil", .none),
            .round       => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "round", .none),
            .trunc_float => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].un_op, "trunc", .none),

            .mul_add => try airMulAdd(f, inst),

            .add_with_overflow => try airOverflow(f, inst, "add", .bits),
            .sub_with_overflow => try airOverflow(f, inst, "sub", .bits),
            .mul_with_overflow => try airOverflow(f, inst, "mul", .bits),
            .shl_with_overflow => try airOverflow(f, inst, "shl", .bits),

            .min => try airMinMax(f, inst, '<', "min"),
            .max => try airMinMax(f, inst, '>', "max"),

            .slice => try airSlice(f, inst),

            .cmp_gt  => try airCmpOp(f, inst, air_datas[@intFromEnum(inst)].bin_op, .gt),
            .cmp_gte => try airCmpOp(f, inst, air_datas[@intFromEnum(inst)].bin_op, .gte),
            .cmp_lt  => try airCmpOp(f, inst, air_datas[@intFromEnum(inst)].bin_op, .lt),
            .cmp_lte => try airCmpOp(f, inst, air_datas[@intFromEnum(inst)].bin_op, .lte),

            .cmp_eq  => try airEquality(f, inst, .eq),
            .cmp_neq => try airEquality(f, inst, .neq),

            .cmp_vector => blk: {
                const ty_pl = air_datas[@intFromEnum(inst)].ty_pl;
                const extra = f.air.extraData(Air.VectorCmp, ty_pl.payload).data;
                break :blk try airCmpOp(f, inst, extra, extra.compareOperator());
            },
            .cmp_lte_errors_len => try airCmpLteErrorsLen(f, inst),

            // bool_and and bool_or are non-short-circuit operations
            .bool_and, .bit_and => try airBinOp(f, inst, "&",  "and", .none),
            .bool_or,  .bit_or  => try airBinOp(f, inst, "|",  "or",  .none),
            .xor                => try airBinOp(f, inst, "^",  "xor", .none),
            .shr, .shr_exact    => try airBinBuiltinCall(f, inst, "shr", .none),
            .shl,               => try airBinBuiltinCall(f, inst, "shlw", .bits),
            .shl_exact          => try airBinOp(f, inst, "<<", "shl", .none),
            .not                => try airNot  (f, inst),

            .optional_payload         => try airOptionalPayload(f, inst, false),
            .optional_payload_ptr     => try airOptionalPayload(f, inst, true),
            .optional_payload_ptr_set => try airOptionalPayloadPtrSet(f, inst),
            .wrap_optional            => try airWrapOptional(f, inst),

            .is_err          => try airIsErr(f, inst, false, "!="),
            .is_non_err      => try airIsErr(f, inst, false, "=="),
            .is_err_ptr      => try airIsErr(f, inst, true, "!="),
            .is_non_err_ptr  => try airIsErr(f, inst, true, "=="),

            .is_null         => try airIsNull(f, inst, .eq, false),
            .is_non_null     => try airIsNull(f, inst, .neq, false),
            .is_null_ptr     => try airIsNull(f, inst, .eq, true),
            .is_non_null_ptr => try airIsNull(f, inst, .neq, true),

            .alloc            => try airAlloc(f, inst),
            .ret_ptr          => try airRetPtr(f, inst),
            .assembly         => try airAsm(f, inst),
            .bitcast          => try airBitcast(f, inst),
            .intcast          => try airIntCast(f, inst),
            .trunc            => try airTrunc(f, inst),
            .load             => try airLoad(f, inst),
            .store            => try airStore(f, inst, false),
            .store_safe       => try airStore(f, inst, true),
            .struct_field_ptr => try airStructFieldPtr(f, inst),
            .array_to_slice   => try airArrayToSlice(f, inst),
            .cmpxchg_weak     => try airCmpxchg(f, inst, "weak"),
            .cmpxchg_strong   => try airCmpxchg(f, inst, "strong"),
            .atomic_rmw       => try airAtomicRmw(f, inst),
            .atomic_load      => try airAtomicLoad(f, inst),
            .memset           => try airMemset(f, inst, false),
            .memset_safe      => try airMemset(f, inst, true),
            .memcpy           => try airMemcpy(f, inst, "memcpy("),
            .memmove          => try airMemcpy(f, inst, "memmove("),
            .set_union_tag    => try airSetUnionTag(f, inst),
            .get_union_tag    => try airGetUnionTag(f, inst),
            .clz              => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].ty_op.operand, "clz", .bits),
            .ctz              => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].ty_op.operand, "ctz", .bits),
            .popcount         => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].ty_op.operand, "popcount", .bits),
            .byte_swap        => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].ty_op.operand, "byte_swap", .bits),
            .bit_reverse      => try airUnBuiltinCall(f, inst, air_datas[@intFromEnum(inst)].ty_op.operand, "bit_reverse", .bits),
            .tag_name         => try airTagName(f, inst),
            .error_name       => try airErrorName(f, inst),
            .splat            => try airSplat(f, inst),
            .select           => try airSelect(f, inst),
            .shuffle_one      => try airShuffleOne(f, inst),
            .shuffle_two      => try airShuffleTwo(f, inst),
            .reduce           => try airReduce(f, inst),
            .aggregate_init   => try airAggregateInit(f, inst),
            .union_init       => try airUnionInit(f, inst),
            .prefetch         => try airPrefetch(f, inst),
            .addrspace_cast   => return f.fail("TODO: C backend: implement addrspace_cast", .{}),

            .@"try"       => try airTry(f, inst),
            .try_cold     => try airTry(f, inst),
            .try_ptr      => try airTryPtr(f, inst),
            .try_ptr_cold => try airTryPtr(f, inst),

            .dbg_stmt => try airDbgStmt(f, inst),
            .dbg_empty_stmt => try airDbgEmptyStmt(f, inst),
            .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline => try airDbgVar(f, inst),

            .float_from_int,
            .int_from_float,
            .fptrunc,
            .fpext,
            => try airFloatCast(f, inst),

            .atomic_store_unordered => try airAtomicStore(f, inst, toMemoryOrder(.unordered)),
            .atomic_store_monotonic => try airAtomicStore(f, inst, toMemoryOrder(.monotonic)),
            .atomic_store_release   => try airAtomicStore(f, inst, toMemoryOrder(.release)),
            .atomic_store_seq_cst   => try airAtomicStore(f, inst, toMemoryOrder(.seq_cst)),

            .struct_field_ptr_index_0 => try airStructFieldPtrIndex(f, inst, 0),
            .struct_field_ptr_index_1 => try airStructFieldPtrIndex(f, inst, 1),
            .struct_field_ptr_index_2 => try airStructFieldPtrIndex(f, inst, 2),
            .struct_field_ptr_index_3 => try airStructFieldPtrIndex(f, inst, 3),

            .field_parent_ptr => try airFieldParentPtr(f, inst),

            .struct_field_val => try airStructFieldVal(f, inst),
            .slice_ptr        => try airSliceField(f, inst, false, "ptr"),
            .slice_len        => try airSliceField(f, inst, false, "len"),

            .ptr_slice_ptr_ptr => try airSliceField(f, inst, true, "ptr"),
            .ptr_slice_len_ptr => try airSliceField(f, inst, true, "len"),

            .ptr_elem_val       => try airPtrElemVal(f, inst),
            .ptr_elem_ptr       => try airPtrElemPtr(f, inst),
            .slice_elem_val     => try airSliceElemVal(f, inst),
            .slice_elem_ptr     => try airSliceElemPtr(f, inst),
            .array_elem_val     => try airArrayElemVal(f, inst),

            .unwrap_errunion_payload     => try airUnwrapErrUnionPay(f, inst, false),
            .unwrap_errunion_payload_ptr => try airUnwrapErrUnionPay(f, inst, true),
            .unwrap_errunion_err         => try airUnwrapErrUnionErr(f, inst),
            .unwrap_errunion_err_ptr     => try airUnwrapErrUnionErr(f, inst),
            .wrap_errunion_payload       => try airWrapErrUnionPay(f, inst),
            .wrap_errunion_err           => try airWrapErrUnionErr(f, inst),
            .errunion_payload_ptr_set    => try airErrUnionPayloadPtrSet(f, inst),
            .err_return_trace            => try airErrReturnTrace(f, inst),
            .set_err_return_trace        => try airSetErrReturnTrace(f, inst),
            .save_err_return_trace_index => try airSaveErrReturnTraceIndex(f, inst),

            .wasm_memory_size => try airWasmMemorySize(f, inst),
            .wasm_memory_grow => try airWasmMemoryGrow(f, inst),

            .add_optimized,
            .sub_optimized,
            .mul_optimized,
            .div_float_optimized,
            .div_trunc_optimized,
            .div_floor_optimized,
            .div_exact_optimized,
            .rem_optimized,
            .mod_optimized,
            .neg_optimized,
            .cmp_lt_optimized,
            .cmp_lte_optimized,
            .cmp_eq_optimized,
            .cmp_gte_optimized,
            .cmp_gt_optimized,
            .cmp_neq_optimized,
            .cmp_vector_optimized,
            .reduce_optimized,
            .int_from_float_optimized,
            => return f.fail("TODO implement optimized float mode", .{}),

            .add_safe,
            .sub_safe,
            .mul_safe,
            .intcast_safe,
            .int_from_float_safe,
            .int_from_float_optimized_safe,
            => return f.fail("TODO implement safety_checked_instructions", .{}),

            .is_named_enum_value => return f.fail("TODO: C backend: implement is_named_enum_value", .{}),
            .error_set_has_value => return f.fail("TODO: C backend: implement error_set_has_value", .{}),

            .runtime_nav_ptr => try airRuntimeNavPtr(f, inst),

            .c_va_start => try airCVaStart(f, inst),
            .c_va_arg => try airCVaArg(f, inst),
            .c_va_end => try airCVaEnd(f, inst),
            .c_va_copy => try airCVaCopy(f, inst),

            .work_item_id,
            .work_group_size,
            .work_group_id,
            => unreachable,

            // Instructions that are known to always be `noreturn` based on their tag.
            .br              => return airBr(f, inst),
            .repeat          => return airRepeat(f, inst),
            .switch_dispatch => return airSwitchDispatch(f, inst),
            .cond_br         => return airCondBr(f, inst),
            .switch_br       => return airSwitchBr(f, inst, false),
            .loop_switch_br  => return airSwitchBr(f, inst, true),
            .loop            => return airLoop(f, inst),
            .ret             => return airRet(f, inst, false),
            .ret_safe        => return airRet(f, inst, false), // TODO
            .ret_load        => return airRet(f, inst, true),
            .trap            => return airTrap(f),
            .unreach         => return airUnreach(f),

            // Instructions which may be `noreturn`.
            .block => res: {
                const res = try airBlock(f, inst);
                if (f.typeOfIndex(inst).isNoReturn(zcu)) return;
                break :res res;
            },
            .dbg_inline_block => res: {
                const res = try airDbgInlineBlock(f, inst);
                if (f.typeOfIndex(inst).isNoReturn(zcu)) return;
                break :res res;
            },
            // TODO: calls should be in this category! The AIR we emit for them is a bit weird.
            // The instruction has type `noreturn`, but there are instructions (and maybe a safety
            // check) following nonetheless. The `unreachable` or safety check should be emitted by
            // backends instead.
            .call              => try airCall(f, inst, .auto),
            .call_always_tail  => .none,
            .call_never_tail   => try airCall(f, inst, .never_tail),
            .call_never_inline => try airCall(f, inst, .never_inline),

            // zig fmt: on
        };
        if (result_value == .new_local) {
            log.debug("map %{d} to t{d}", .{ inst, result_value.new_local });
        }
        try f.value_map.putNoClobber(inst.toRef(), switch (result_value) {
            .none => continue,
            .new_local => |local_index| .{ .local = local_index },
            else => result_value,
        });
    }
    unreachable;
}

fn airSliceField(f: *Function, inst: Air.Inst.Index, is_ptr: bool, field_name: []const u8) !CValue {
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    if (is_ptr) {
        try w.writeByte('&');
        try f.writeCValueDerefMember(w, operand, .{ .identifier = field_name });
    } else try f.writeCValueMember(w, operand, .{ .identifier = field_name });
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airPtrElemVal(f: *Function, inst: Air.Inst.Index) !CValue {
    const zcu = f.dg.pt.zcu;
    const inst_ty = f.typeOfIndex(inst);
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    assert(inst_ty.hasRuntimeBits(zcu));

    const ptr = try f.resolveInst(bin_op.lhs);
    const index = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    switch (f.typeOf(bin_op.lhs).ptrSize(zcu)) {
        .one => try f.writeCValueDerefMember(w, ptr, .{ .identifier = "array" }),
        .many, .c => try f.writeCValue(w, ptr, .other),
        .slice => unreachable,
    }
    try w.writeByte('[');
    try f.writeCValue(w, index, .other);
    try w.writeAll("];");
    try f.newline();
    return local;
}

fn airPtrElemPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = f.air.extraData(Air.Bin, ty_pl.payload).data;

    const inst_ty = f.typeOfIndex(inst);
    const ptr_ty = f.typeOf(bin_op.lhs);
    assert(ptr_ty.indexableElem(zcu).hasRuntimeBits(zcu));

    const ptr = try f.resolveInst(bin_op.lhs);
    const index = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try w.writeByte('&');
    if (ptr_ty.ptrSize(zcu) == .one) {
        // `*[n]T` was turned into a pointer to `struct { T array[n]; }`
        try f.writeCValueDerefMember(w, ptr, .{ .identifier = "array" });
    } else {
        try f.writeCValue(w, ptr, .other);
    }
    try w.writeByte('[');
    try f.writeCValue(w, index, .other);
    try w.writeAll("];");
    try f.newline();
    return local;
}

fn airSliceElemVal(f: *Function, inst: Air.Inst.Index) !CValue {
    const zcu = f.dg.pt.zcu;
    const inst_ty = f.typeOfIndex(inst);
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    assert(inst_ty.hasRuntimeBits(zcu));

    const slice = try f.resolveInst(bin_op.lhs);
    const index = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try f.writeCValueMember(w, slice, .{ .identifier = "ptr" });
    try w.writeByte('[');
    try f.writeCValue(w, index, .other);
    try w.writeAll("];");
    try f.newline();
    return local;
}

fn airSliceElemPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = f.air.extraData(Air.Bin, ty_pl.payload).data;

    const inst_ty = f.typeOfIndex(inst);
    const slice_ty = f.typeOf(bin_op.lhs);
    const elem_ty = slice_ty.childType(zcu);
    assert(elem_ty.hasRuntimeBits(zcu));

    const slice = try f.resolveInst(bin_op.lhs);
    const index = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try w.writeByte('&');
    try f.writeCValueMember(w, slice, .{ .identifier = "ptr" });
    try w.writeByte('[');
    try f.writeCValue(w, index, .other);
    try w.writeAll("];");
    try f.newline();
    return local;
}

fn airArrayElemVal(f: *Function, inst: Air.Inst.Index) !CValue {
    const zcu = f.dg.pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const inst_ty = f.typeOfIndex(inst);
    assert(inst_ty.hasRuntimeBits(zcu));

    const array = try f.resolveInst(bin_op.lhs);
    const index = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try f.writeCValueMember(w, array, .{ .identifier = "array" });
    try w.writeByte('[');
    try f.writeCValue(w, index, .other);
    try w.writeAll("];");
    try f.newline();
    return local;
}

fn airAlloc(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const inst_ty = f.typeOfIndex(inst);
    const elem_ty = inst_ty.childType(zcu);
    if (!elem_ty.hasRuntimeBits(zcu)) return .{ .undef = inst_ty };

    const local = try f.allocLocalValue(.{
        .type = elem_ty,
        .alignment = inst_ty.ptrInfo(zcu).flags.alignment,
    });
    log.debug("%{d}: allocated unfreeable t{d}", .{ inst, local.new_local });
    try f.allocs.put(zcu.gpa, local.new_local, true);

    switch (elem_ty.zigTypeTag(zcu)) {
        .@"struct", .@"union" => switch (elem_ty.containerLayout(zcu)) {
            .@"packed" => {
                // For packed aggregates, we zero-initialize to try and work around a design flaw
                // related to how `packed`, `undefined`, and RLS interact. See comment in `airStore`
                // for details.
                const w = &f.code.writer;
                try w.print("memset(&t{d}, 0x00, sizeof(", .{local.new_local});
                try f.renderType(w, elem_ty);
                try w.writeAll("));");
                try f.newline();
            },
            .auto, .@"extern" => {},
        },
        else => {},
    }

    return .{ .local_ref = local.new_local };
}

fn airRetPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const inst_ty = f.typeOfIndex(inst);
    const elem_ty = inst_ty.childType(zcu);
    if (!elem_ty.hasRuntimeBits(zcu)) return .{ .undef = inst_ty };

    const local = try f.allocLocalValue(.{
        .type = elem_ty,
        .alignment = inst_ty.ptrInfo(zcu).flags.alignment,
    });
    log.debug("%{d}: allocated unfreeable t{d}", .{ inst, local.new_local });
    try f.allocs.put(zcu.gpa, local.new_local, true);

    switch (elem_ty.zigTypeTag(zcu)) {
        .@"struct", .@"union" => switch (elem_ty.containerLayout(zcu)) {
            .@"packed" => {
                // For packed aggregates, we zero-initialize to try and work around a design flaw
                // related to how `packed`, `undefined`, and RLS interact. See comment in `airStore`
                // for details.
                const w = &f.code.writer;
                try w.print("memset(&t{d}, 0x00, sizeof(", .{local.new_local});
                try f.renderType(w, elem_ty);
                try w.writeAll("));");
                try f.newline();
            },
            .auto, .@"extern" => {},
        },
        else => {},
    }

    return .{ .local_ref = local.new_local };
}

fn airArg(f: *Function, inst: Air.Inst.Index) !CValue {
    const i = f.next_arg_index;
    f.next_arg_index += 1;
    const result: CValue = .{ .arg = i };

    if (f.liveness.isUnused(inst)) {
        const w = &f.code.writer;
        try w.writeByte('(');
        try f.renderType(w, .void);
        try w.writeByte(')');
        try f.writeCValue(w, result, .other);
        try w.writeByte(';');
        try f.newline();
        return .none;
    }

    return result;
}

fn airLoad(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const ptr_ty = f.typeOf(ty_op.operand);
    const ptr_scalar_ty = ptr_ty.scalarType(zcu);
    const ptr_info = ptr_scalar_ty.ptrInfo(zcu);
    const src_ty: Type = .fromInterned(ptr_info.child);

    // `Air.Legalize.Feature.expand_packed_load` should ensure that the only
    // bit-pointers we see here are vector element pointers.
    assert(ptr_info.packed_offset.host_size == 0 or ptr_info.flags.vector_index != .none);

    assert(src_ty.hasRuntimeBits(zcu));

    const operand = try f.resolveInst(ty_op.operand);

    try reap(f, inst, &.{ty_op.operand});

    const is_aligned = if (ptr_info.flags.alignment != .none)
        ptr_info.flags.alignment.order(src_ty.abiAlignment(zcu)).compare(.gte)
    else
        true;

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, src_ty);
    const v = try Vectorize.start(f, inst, w, ptr_ty);

    if (!is_aligned) {
        try w.writeAll("memcpy(&");
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(", (const char *)");
        try f.writeCValue(w, operand, .other);
        try v.elem(f, w);
        try w.writeAll(", sizeof(");
        try f.renderType(w, src_ty);
        try w.writeAll("))");
    } else {
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(" = ");
        try f.writeCValueDeref(w, operand);
        try v.elem(f, w);
    }
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airRet(f: *Function, inst: Air.Inst.Index, is_ptr: bool) !void {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const w = &f.code.writer;
    const op_inst = un_op.toIndex();
    const op_ty = f.typeOf(un_op);
    const ret_ty = if (is_ptr) op_ty.childType(zcu) else op_ty;

    if (op_inst != null and f.air.instructions.items(.tag)[@intFromEnum(op_inst.?)] == .call_always_tail) {
        try reap(f, inst, &.{un_op});
        _ = try airCall(f, op_inst.?, .always_tail);
    } else if (ret_ty.hasRuntimeBits(zcu)) {
        const operand = try f.resolveInst(un_op);
        try reap(f, inst, &.{un_op});

        try w.writeAll("return ");
        if (is_ptr) {
            try f.writeCValueDeref(w, operand);
        } else switch (operand) {
            // Instead of 'return &local', emit 'return undefined'.
            .local_ref => try f.dg.renderUndefValue(w, ret_ty, .other),
            else => try f.writeCValue(w, operand, .other),
        }
        try w.writeAll(";\n");
    } else {
        try reap(f, inst, &.{un_op});
        // Not even allowed to return void in a naked function.
        if (!f.dg.is_naked_fn) try w.writeAll("return;\n");
    }
}

fn airIntCast(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const operand_ty = f.typeOf(ty_op.operand);
    const scalar_ty = operand_ty.scalarType(zcu);

    // `intCastIsNoop` doesn't apply to vectors because every vector lowers to a different C struct.
    if (inst_ty.zigTypeTag(zcu) != .vector and f.dg.intCastIsNoop(inst_scalar_ty, scalar_ty)) {
        return f.moveCValue(inst, inst_ty, operand);
    }

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    try f.renderIntCast(w, inst_scalar_ty, operand, v, scalar_ty, .other);
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);
    return local;
}

fn airTrunc(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const dest_int_info = inst_scalar_ty.intInfo(zcu);
    const dest_bits = dest_int_info.bits;
    const dest_c_bits = toCIntBits(dest_bits) orelse
        return f.fail("TODO: C backend: implement integer types larger than 128 bits", .{});
    const operand_ty = f.typeOf(ty_op.operand);
    const scalar_ty = operand_ty.scalarType(zcu);
    const scalar_int_info = scalar_ty.intInfo(zcu);

    const need_cast = dest_c_bits < 64;
    const need_lo = scalar_int_info.bits > 64 and dest_bits <= 64;
    const need_mask = dest_bits < 8 or !std.math.isPowerOfTwo(dest_bits);
    if (!need_cast and !need_lo and !need_mask) return f.moveCValue(inst, inst_ty, operand);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    if (need_cast) {
        try w.writeByte('(');
        try f.renderType(w, inst_scalar_ty);
        try w.writeByte(')');
    }
    if (need_lo) {
        try w.writeAll("zig_lo_");
        try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
        try w.writeByte('(');
    }
    if (!need_mask) {
        try f.writeCValue(w, operand, .other);
        try v.elem(f, w);
    } else switch (dest_int_info.signedness) {
        .unsigned => {
            try w.writeAll("zig_and_");
            try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
            try w.writeByte('(');
            try f.writeCValue(w, operand, .other);
            try v.elem(f, w);
            try w.print(", {f})", .{
                try f.fmtIntLiteralHex(try inst_scalar_ty.maxIntScalar(pt, scalar_ty)),
            });
        },
        .signed => {
            const c_bits = toCIntBits(scalar_int_info.bits) orelse
                return f.fail("TODO: C backend: implement integer types larger than 128 bits", .{});
            const shift_val = try pt.intValue(.u8, c_bits - dest_bits);

            try w.writeAll("zig_shr_");
            try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
            if (c_bits == 128) {
                try w.print("(zig_bitCast_i{d}(", .{c_bits});
            } else {
                try w.print("((int{d}_t)", .{c_bits});
            }
            try w.print("zig_shl_u{d}(", .{c_bits});
            if (c_bits == 128) {
                try w.print("zig_bitCast_u{d}(", .{c_bits});
            } else {
                try w.print("(uint{d}_t)", .{c_bits});
            }
            try f.writeCValue(w, operand, .other);
            try v.elem(f, w);
            if (c_bits == 128) try w.writeByte(')');
            try w.print(", {f})", .{try f.fmtIntLiteralDec(shift_val)});
            if (c_bits == 128) try w.writeByte(')');
            try w.print(", {f})", .{try f.fmtIntLiteralDec(shift_val)});
        },
    }
    if (need_lo) try w.writeByte(')');
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);
    return local;
}

fn airStore(f: *Function, inst: Air.Inst.Index, safety: bool) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    // *a = b;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const ptr_ty = f.typeOf(bin_op.lhs);
    const ptr_scalar_ty = ptr_ty.scalarType(zcu);
    const ptr_info = ptr_scalar_ty.ptrInfo(zcu);

    // `Air.Legalize.Feature.expand_packed_store` should ensure that the only
    // bit-pointers we see here are vector element pointers.
    assert(ptr_info.packed_offset.host_size == 0 or ptr_info.flags.vector_index != .none);

    const ptr_val = try f.resolveInst(bin_op.lhs);
    const src_ty = f.typeOf(bin_op.rhs);

    const val_is_undef = if (bin_op.rhs.toInterned()) |ip_index| Value.fromInterned(ip_index).isUndef(zcu) else false;

    const w = &f.code.writer;
    if (val_is_undef) {
        try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
        if (safety and ptr_info.packed_offset.host_size == 0) {
            // If the thing we're initializing is a packed struct/union, we set to 0 instead of
            // 0xAA. This is a hack to work around a problem with partially-undefined packed
            // aggregates. If we used 0xAA here, then a later initialization through RLS would
            // not zero the high padding bits (for a packed type which is not 8/16/32/64/etc bits),
            // so we would get a miscompilation. Using 0x00 here avoids this bug in some cases. It
            // is *not* a correct fix; for instance it misses any case where packed structs are
            // nested in other aggregates. A proper fix for this will involve changing the language,
            // such as to remove RLS. This just prevents miscompilations in *some* common cases.
            const byte_str: []const u8 = switch (src_ty.zigTypeTag(zcu)) {
                else => "0xaa",
                .@"struct", .@"union" => switch (src_ty.containerLayout(zcu)) {
                    .auto, .@"extern" => "0xaa",
                    .@"packed" => "0x00",
                },
            };
            try w.writeAll("memset(");
            try f.writeCValue(w, ptr_val, .other);
            try w.print(", {s}, sizeof(", .{byte_str});
            try f.renderType(w, .fromInterned(ptr_info.child));
            try w.writeAll("));");
            try f.newline();
        }
        return .none;
    }

    const is_aligned = if (ptr_info.flags.alignment != .none)
        ptr_info.flags.alignment.order(src_ty.abiAlignment(zcu)).compare(.gte)
    else
        true;

    const src_val = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    if (!is_aligned) {
        // For this memcpy to safely work we need the rhs to have the same
        // underlying type as the lhs (i.e. they must both be arrays of the same underlying type).
        assert(src_ty.eql(.fromInterned(ptr_info.child), zcu));

        const v = try Vectorize.start(f, inst, w, ptr_ty);
        try w.writeAll("memcpy((char *)");
        try f.writeCValue(w, ptr_val, .other);
        try v.elem(f, w);
        try w.writeAll(", &");
        switch (src_val) {
            .constant => |val| try f.dg.renderValueAsLvalue(w, val),
            else => try f.writeCValue(w, src_val, .other),
        }
        try v.elem(f, w);
        try w.writeAll(", sizeof(");
        try f.renderType(w, src_ty);
        try w.writeAll("));");
        try f.newline();
        try v.end(f, inst, w);
    } else {
        switch (ptr_val) {
            .local_ref => |ptr_local_index| switch (src_val) {
                .new_local, .local => |src_local_index| if (ptr_local_index == src_local_index)
                    return .none,
                else => {},
            },
            else => {},
        }
        const v = try Vectorize.start(f, inst, w, ptr_ty);
        try f.writeCValueDeref(w, ptr_val);
        try v.elem(f, w);
        try w.writeAll(" = ");
        try f.writeCValue(w, src_val, .other);
        try v.elem(f, w);
        try w.writeByte(';');
        try f.newline();
        try v.end(f, inst, w);
    }
    return .none;
}

fn airOverflow(f: *Function, inst: Air.Inst.Index, operation: []const u8, info: BuiltinInfo) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = f.air.extraData(Air.Bin, ty_pl.payload).data;

    const lhs = try f.resolveInst(bin_op.lhs);
    const rhs = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const inst_ty = f.typeOfIndex(inst);
    const operand_ty = f.typeOf(bin_op.lhs);
    const scalar_ty = operand_ty.scalarType(zcu);

    const ref_arg = lowersToBigInt(scalar_ty, zcu);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValueMember(w, local, .{ .field = 1 });
    try v.elem(f, w);
    try w.writeAll(" = zig_");
    try w.writeAll(operation);
    try w.writeAll("o_");
    try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
    try w.writeAll("(&");
    try f.writeCValueMember(w, local, .{ .field = 0 });
    try v.elem(f, w);
    try w.writeAll(", ");
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeAll(", ");
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, rhs, .other);
    if (f.typeOf(bin_op.rhs).isVector(zcu)) try v.elem(f, w);
    try f.dg.renderBuiltinInfo(w, scalar_ty, info);
    try w.writeAll(");");
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airNot(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_ty = f.typeOf(ty_op.operand);
    const scalar_ty = operand_ty.scalarType(zcu);
    if (scalar_ty.toIntern() != .bool_type) return try airUnBuiltinCall(f, inst, ty_op.operand, "not", .bits);

    const op = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const inst_ty = f.typeOfIndex(inst);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    try w.writeByte('!');
    try f.writeCValue(w, op, .other);
    try v.elem(f, w);
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airBinOp(
    f: *Function,
    inst: Air.Inst.Index,
    operator: []const u8,
    operation: []const u8,
    info: BuiltinInfo,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const operand_ty = f.typeOf(bin_op.lhs);
    const scalar_ty = operand_ty.scalarType(zcu);
    if ((scalar_ty.isInt(zcu) and scalar_ty.bitSize(zcu) > 64) or scalar_ty.isRuntimeFloat())
        return try airBinBuiltinCall(f, inst, operation, info);

    const lhs = try f.resolveInst(bin_op.lhs);
    const rhs = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const inst_ty = f.typeOfIndex(inst);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeByte(' ');
    try w.writeAll(operator);
    try w.writeByte(' ');
    try f.writeCValue(w, rhs, .other);
    try v.elem(f, w);
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airCmpOp(
    f: *Function,
    inst: Air.Inst.Index,
    data: anytype,
    operator: std.math.CompareOperator,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const lhs_ty = f.typeOf(data.lhs);
    const scalar_ty = lhs_ty.scalarType(zcu);

    const scalar_bits = scalar_ty.bitSize(zcu);
    if (scalar_ty.isInt(zcu) and scalar_bits > 64)
        return airCmpBuiltinCall(
            f,
            inst,
            data,
            operator,
            .cmp,
            if (scalar_bits > 128) .bits else .none,
        );
    if (scalar_ty.isRuntimeFloat())
        return airCmpBuiltinCall(f, inst, data, operator, .operator, .none);

    const inst_ty = f.typeOfIndex(inst);
    const lhs = try f.resolveInst(data.lhs);
    const rhs = try f.resolveInst(data.rhs);
    try reap(f, inst, &.{ data.lhs, data.rhs });

    const rhs_ty = f.typeOf(data.rhs);
    const need_cast = lhs_ty.isSinglePointer(zcu) or rhs_ty.isSinglePointer(zcu);
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, lhs_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    if (lhs != .undef and lhs.eql(rhs)) try w.writeAll(switch (operator) {
        .lt, .neq, .gt => "false",
        .lte, .eq, .gte => "true",
    }) else {
        if (need_cast) try w.writeAll("(void*)");
        try f.writeCValue(w, lhs, .other);
        try v.elem(f, w);
        try w.writeAll(compareOperatorC(operator));
        if (need_cast) try w.writeAll("(void*)");
        try f.writeCValue(w, rhs, .other);
        try v.elem(f, w);
    }
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airEquality(
    f: *Function,
    inst: Air.Inst.Index,
    operator: std.math.CompareOperator,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const operand_ty = f.typeOf(bin_op.lhs);
    const operand_bits = operand_ty.bitSize(zcu);
    if (operand_ty.isAbiInt(zcu) and operand_bits > 64)
        return airCmpBuiltinCall(
            f,
            inst,
            bin_op,
            operator,
            .cmp,
            if (operand_bits > 128) .bits else .none,
        );
    if (operand_ty.isRuntimeFloat())
        return airCmpBuiltinCall(f, inst, bin_op, operator, .operator, .none);

    const lhs = try f.resolveInst(bin_op.lhs);
    const rhs = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    if (lhs.eql(rhs)) {
        // Avoid emitting a tautological comparison.
        return .{ .constant = .makeBool(switch (operator) {
            .eq, .lte, .gte => true,
            .neq, .lt, .gt => false,
        }) };
    }

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, .bool);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");

    switch (operand_ty.zigTypeTag(zcu)) {
        .optional => switch (CType.classifyOptional(operand_ty, zcu)) {
            .npv_payload => unreachable, // opv optional

            .error_set, .ptr_like => {},

            .slice_like => unreachable, // equality is not defined on slices

            .opv_payload => {
                try f.writeCValueMember(w, lhs, .{ .identifier = "is_null" });
                try w.writeAll(compareOperatorC(operator));
                try f.writeCValueMember(w, rhs, .{ .identifier = "is_null" });
                try w.writeByte(';');
                try f.newline();
                return local;
            },

            .@"struct" => {
                // `lhs.is_null || rhs.is_null ? lhs.is_null == rhs.is_null : lhs.payload == rhs.payload`
                try f.writeCValueMember(w, lhs, .{ .identifier = "is_null" });
                try w.writeAll(" || ");
                try f.writeCValueMember(w, rhs, .{ .identifier = "is_null" });
                try w.writeAll(" ? ");
                try f.writeCValueMember(w, lhs, .{ .identifier = "is_null" });
                try w.writeAll(compareOperatorC(operator));
                try f.writeCValueMember(w, rhs, .{ .identifier = "is_null" });
                try w.writeAll(" : ");
                try f.writeCValueMember(w, lhs, .{ .identifier = "payload" });
                try w.writeAll(compareOperatorC(operator));
                try f.writeCValueMember(w, rhs, .{ .identifier = "payload" });
                try w.writeByte(';');
                try f.newline();
                return local;
            },
        },
        .bool, .int, .pointer, .@"enum", .error_set => {},
        .@"struct", .@"union" => assert(operand_ty.containerLayout(zcu) == .@"packed"),
        else => unreachable,
    }

    try f.writeCValue(w, lhs, .other);
    try w.writeAll(compareOperatorC(operator));
    try f.writeCValue(w, rhs, .other);
    try w.writeByte(';');
    try f.newline();

    return local;
}

fn airCmpLteErrorsLen(f: *Function, inst: Air.Inst.Index) !CValue {
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;

    const operand = try f.resolveInst(un_op);
    try reap(f, inst, &.{un_op});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, .bool);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try f.writeCValue(w, operand, .other);
    try w.print(" < sizeof({f}) / sizeof(*{0f});", .{fmtIdentSolo("zig_errorName")});
    try f.newline();
    return local;
}

fn airPtrAddSub(f: *Function, inst: Air.Inst.Index, operator: u8) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = f.air.extraData(Air.Bin, ty_pl.payload).data;

    const lhs = try f.resolveInst(bin_op.lhs);
    const rhs = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const elem_ty = inst_scalar_ty.indexableElem(zcu);
    assert(elem_ty.hasRuntimeBits(zcu));

    const local = try f.allocLocal(inst, inst_ty);
    const w = &f.code.writer;
    const v = try Vectorize.start(f, inst, w, inst_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    // We must convert to and from integer types to prevent UB if the operation
    // results in a NULL pointer, or if LHS is NULL. The operation is only UB
    // if the result is NULL and then dereferenced.
    try w.writeByte('(');
    try f.renderType(w, inst_scalar_ty);
    try w.writeAll(")(((uintptr_t)");
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.print(") {c} (", .{operator});
    try f.writeCValue(w, rhs, .other);
    try v.elem(f, w);
    try w.writeAll("*sizeof(");
    try f.renderType(w, elem_ty);
    try w.writeAll(")));");
    try f.newline();
    try v.end(f, inst, w);
    return local;
}

fn airMinMax(f: *Function, inst: Air.Inst.Index, operator: u8, operation: []const u8) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);

    if ((inst_scalar_ty.isInt(zcu) and inst_scalar_ty.bitSize(zcu) > 64) or inst_scalar_ty.isRuntimeFloat())
        return try airBinBuiltinCall(f, inst, operation, .none);

    const lhs = try f.resolveInst(bin_op.lhs);
    const rhs = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, inst_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    // (lhs <> rhs) ? lhs : rhs
    try w.writeAll(" = (");
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeByte(' ');
    try w.writeByte(operator);
    try w.writeByte(' ');
    try f.writeCValue(w, rhs, .other);
    try v.elem(f, w);
    try w.writeAll(") ? ");
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeAll(" : ");
    try f.writeCValue(w, rhs, .other);
    try v.elem(f, w);
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airSlice(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = f.air.extraData(Air.Bin, ty_pl.payload).data;

    const ptr = try f.resolveInst(bin_op.lhs);
    const len = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const inst_ty = f.typeOfIndex(inst);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);

    try f.writeCValueMember(w, local, .{ .identifier = "ptr" });
    try w.writeAll(" = ");
    try f.writeCValue(w, ptr, .other);
    try w.writeByte(';');
    try f.newline();

    try f.writeCValueMember(w, local, .{ .identifier = "len" });
    try w.writeAll(" = ");
    try f.writeCValue(w, len, .other);
    try w.writeByte(';');
    try f.newline();

    return local;
}

fn airCall(
    f: *Function,
    inst: Air.Inst.Index,
    modifier: std.builtin.CallModifier,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    // Not even allowed to call panic in a naked function.
    if (f.dg.is_naked_fn) return .none;

    const gpa = f.dg.gpa;
    const w = &f.code.writer;

    const call = f.air.unwrapCall(inst);
    const args = call.args;

    const resolved_args = try gpa.alloc(CValue, args.len);
    defer gpa.free(resolved_args);
    for (resolved_args, args) |*resolved_arg, arg| {
        const arg_ty = f.typeOf(arg);
        if (!arg_ty.hasRuntimeBits(zcu)) {
            resolved_arg.* = .none;
            continue;
        }
        resolved_arg.* = try f.resolveInst(arg);
    }

    const callee = try f.resolveInst(call.callee);

    {
        var bt = iterateBigTomb(f, inst);
        try bt.feed(call.callee);
        for (args) |arg| try bt.feed(arg);
    }

    const callee_ty = f.typeOf(call.callee);
    const callee_is_ptr = switch (callee_ty.zigTypeTag(zcu)) {
        .@"fn" => false,
        .pointer => true,
        else => unreachable,
    };
    const fn_info = zcu.typeToFunc(if (callee_is_ptr) callee_ty.childType(zcu) else callee_ty).?;
    const ret_ty: Type = .fromInterned(fn_info.return_type);

    const result_local = result: {
        if (modifier == .always_tail) {
            try w.writeAll("zig_always_tail return ");
            break :result .none;
        } else if (!ret_ty.hasRuntimeBits(zcu)) {
            break :result .none;
        } else if (f.liveness.isUnused(inst)) {
            try w.writeAll("(void)");
            break :result .none;
        } else {
            const local = try f.allocAlignedLocal(inst, .{
                .type = ret_ty,
                .alignment = .none,
            });
            try f.writeCValue(w, local, .other);
            try w.writeAll(" = ");
            break :result local;
        }
    };

    callee: {
        known: {
            const callee_ip_index = call.callee.toInterned() orelse break :known;
            const fn_nav, const need_cast = switch (ip.indexToKey(callee_ip_index)) {
                .@"extern" => |@"extern"| .{ @"extern".owner_nav, false },
                .func => |func| .{ func.owner_nav, Type.fromInterned(func.ty).fnCallingConvention(zcu) != .naked and
                    Type.fromInterned(func.uncoerced_ty).fnCallingConvention(zcu) == .naked },
                .ptr => |ptr| if (ptr.byte_offset == 0) switch (ptr.base_addr) {
                    .nav => |nav| .{ nav, Type.fromInterned(ptr.ty).childType(zcu).fnCallingConvention(zcu) != .naked and
                        zcu.navValue(nav).typeOf(zcu).fnCallingConvention(zcu) == .naked },
                    else => break :known,
                } else break :known,
                else => break :known,
            };
            if (need_cast) {
                try w.writeAll("((");
                try f.renderType(w, if (callee_is_ptr) callee_ty else try pt.singleConstPtrType(callee_ty));
                try w.writeByte(')');
                if (!callee_is_ptr) try w.writeByte('&');
            }
            switch (modifier) {
                .auto, .always_tail => try renderNavName(w, fn_nav, ip),
                .never_tail => {
                    try f.need_never_tail_funcs.put(gpa, fn_nav, {});
                    try w.print("zig_never_tail_{f}__{d}", .{
                        fmtIdentUnsolo(ip.getNav(fn_nav).name.toSlice(ip)), @intFromEnum(fn_nav),
                    });
                },
                .never_inline => {
                    try f.need_never_inline_funcs.put(gpa, fn_nav, {});
                    try w.print("zig_never_inline_{f}__{d}", .{
                        fmtIdentUnsolo(ip.getNav(fn_nav).name.toSlice(ip)), @intFromEnum(fn_nav),
                    });
                },
                else => unreachable,
            }
            if (need_cast) try w.writeByte(')');
            break :callee;
        }
        switch (modifier) {
            .auto, .always_tail => {},
            .never_tail => return f.fail("CBE: runtime callee with never_tail attribute unsupported", .{}),
            .never_inline => return f.fail("CBE: runtime callee with never_inline attribute unsupported", .{}),
            else => unreachable,
        }
        // Fall back to function pointer call.
        try f.writeCValue(w, callee, .other);
    }

    try w.writeByte('(');
    var need_comma = false;
    for (resolved_args) |resolved_arg| {
        if (resolved_arg == .none) continue;
        if (need_comma) try w.writeAll(", ");
        need_comma = true;
        try f.writeCValue(w, resolved_arg, .other);
    }
    try w.writeAll(");");
    switch (modifier) {
        .always_tail => try w.writeByte('\n'),
        else => try f.newline(),
    }

    return result_local;
}

fn airDbgStmt(f: *Function, inst: Air.Inst.Index) !CValue {
    const dbg_stmt = f.air.instructions.items(.data)[@intFromEnum(inst)].dbg_stmt;
    const w = &f.code.writer;
    // TODO re-evaluate whether to emit these or not. If we naively emit
    // these directives, the output file will report bogus line numbers because
    // every newline after the #line directive adds one to the line.
    // We also don't print the filename yet, so the output is strictly unhelpful.
    // If we wanted to go this route, we would need to go all the way and not output
    // newlines until the next dbg_stmt occurs.
    // Perhaps an additional compilation option is in order?
    //try w.print("#line {d}", .{dbg_stmt.line + 1});
    //try f.newline();
    try w.print("/* file:{d}:{d} */", .{ dbg_stmt.line + 1, dbg_stmt.column + 1 });
    try f.newline();
    return .none;
}

fn airDbgEmptyStmt(f: *Function, _: Air.Inst.Index) !CValue {
    try f.code.writer.writeAll("(void)0;");
    try f.newline();
    return .none;
}

fn airDbgInlineBlock(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const block = f.air.unwrapDbgBlock(inst);
    const owner_nav = ip.getNav(zcu.funcInfo(block.func).owner_nav);
    const w = &f.code.writer;
    try w.print("/* inline:{f} */", .{owner_nav.fqn.fmt(&zcu.intern_pool)});
    try f.newline();
    return lowerBlock(f, inst, block.body);
}

fn airDbgVar(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const tag = f.air.instructions.items(.tag)[@intFromEnum(inst)];
    const pl_op = f.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const name: Air.NullTerminatedString = @enumFromInt(pl_op.payload);
    const operand_is_undef = if (pl_op.operand.toInterned()) |ip_index| Value.fromInterned(ip_index).isUndef(zcu) else false;
    if (!operand_is_undef) _ = try f.resolveInst(pl_op.operand);

    try reap(f, inst, &.{pl_op.operand});
    const w = &f.code.writer;
    try w.print("/* {s}:{s} */", .{ @tagName(tag), name.toSlice(f.air) });
    try f.newline();
    return .none;
}

fn airBlock(f: *Function, inst: Air.Inst.Index) !CValue {
    const block = f.air.unwrapBlock(inst);
    return lowerBlock(f, inst, block.body);
}

fn lowerBlock(f: *Function, inst: Air.Inst.Index, body: []const Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const liveness_block = f.liveness.getBlock(inst);

    const block_id = f.next_block_index;
    f.next_block_index += 1;
    const w = &f.code.writer;

    const inst_ty = f.typeOfIndex(inst);
    const result = if (inst_ty.hasRuntimeBits(zcu) and !f.liveness.isUnused(inst))
        try f.allocLocal(inst, inst_ty)
    else
        .none;

    try f.blocks.putNoClobber(f.dg.gpa, inst, .{
        .block_id = block_id,
        .result = result,
    });

    try genBodyResolveState(f, inst, &.{}, body, true);

    assert(f.blocks.remove(inst));

    // The body might result in some values we had beforehand being killed
    for (liveness_block.deaths) |death| {
        try die(f, inst, death.toRef());
    }

    // noreturn blocks have no `br` instructions reaching them, so we don't want a label
    if (f.dg.is_naked_fn) {
        if (f.dg.expected_block) |expected_block| {
            if (block_id != expected_block)
                return f.fail("runtime code not allowed in naked function", .{});
            f.dg.expected_block = null;
        }
    } else if (!f.typeOfIndex(inst).isNoReturn(zcu)) {
        // label must be followed by an expression, include an empty one.
        try w.print("\nzig_block_{d}:;", .{block_id});
        try f.newline();
    }

    return result;
}

fn airTry(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const unwrapped_try = f.air.unwrapTry(inst);
    const body = unwrapped_try.else_body;
    const err_union_ty = f.air.typeOf(unwrapped_try.error_union, &pt.zcu.intern_pool);
    return lowerTry(f, inst, unwrapped_try.error_union, body, err_union_ty, false);
}

fn airTryPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const unwrapped_try = f.air.unwrapTryPtr(inst);
    const body = unwrapped_try.else_body;
    const err_union_ty = f.air.typeOf(unwrapped_try.error_union_ptr, &pt.zcu.intern_pool).childType(pt.zcu);
    return lowerTry(f, inst, unwrapped_try.error_union_ptr, body, err_union_ty, true);
}

fn lowerTry(
    f: *Function,
    inst: Air.Inst.Index,
    operand: Air.Inst.Ref,
    body: []const Air.Inst.Index,
    err_union_ty: Type,
    is_ptr: bool,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const err_union = try f.resolveInst(operand);
    const inst_ty = f.typeOfIndex(inst);
    const liveness_condbr = f.liveness.getCondBr(inst);
    const w = &f.code.writer;
    const payload_ty = err_union_ty.errorUnionPayload(zcu);

    try w.writeAll("if (");

    // Reap the operand so that it can be reused inside genBody.
    // Remember we must avoid calling reap() twice for the same operand
    // in this function.
    try reap(f, inst, &.{operand});
    if (is_ptr)
        try f.writeCValueDerefMember(w, err_union, .{ .identifier = "error" })
    else
        try f.writeCValueMember(w, err_union, .{ .identifier = "error" });

    try w.writeAll(") ");

    try genBodyResolveState(f, inst, liveness_condbr.else_deaths, body, false);
    try f.newline();
    if (f.dg.expected_block) |_|
        return f.fail("runtime code not allowed in naked function", .{});

    // Now we have the "then branch" (in terms of the liveness data); process any deaths.
    for (liveness_condbr.then_deaths) |death| {
        try die(f, inst, death.toRef());
    }

    if (!payload_ty.hasRuntimeBits(zcu)) {
        if (!is_ptr) {
            return .none;
        } else {
            return err_union;
        }
    }

    try reap(f, inst, &.{operand});

    if (f.liveness.isUnused(inst)) return .none;

    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    if (is_ptr) {
        try w.writeByte('&');
        try f.writeCValueDerefMember(w, err_union, .{ .identifier = "payload" });
    } else try f.writeCValueMember(w, err_union, .{ .identifier = "payload" });
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airBr(f: *Function, inst: Air.Inst.Index) !void {
    const branch = f.air.instructions.items(.data)[@intFromEnum(inst)].br;
    const block = f.blocks.get(branch.block_inst).?;
    const result = block.result;
    const w = &f.code.writer;

    if (f.dg.is_naked_fn) {
        if (result != .none) return f.fail("runtime code not allowed in naked function", .{});
        f.dg.expected_block = block.block_id;
        return;
    }

    // If result is .none then the value of the block is unused.
    if (result != .none) {
        const operand = try f.resolveInst(branch.operand);
        try reap(f, inst, &.{branch.operand});

        try f.writeCValue(w, result, .other);
        try w.writeAll(" = ");
        try f.writeCValue(w, operand, .other);
        try w.writeByte(';');
        try f.newline();
    }

    try w.print("goto zig_block_{d};\n", .{block.block_id});
}

fn airRepeat(f: *Function, inst: Air.Inst.Index) !void {
    const repeat = f.air.instructions.items(.data)[@intFromEnum(inst)].repeat;
    try f.code.writer.print("goto zig_loop_{d};\n", .{@intFromEnum(repeat.loop_inst)});
}

fn airSwitchDispatch(f: *Function, inst: Air.Inst.Index) !void {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const br = f.air.instructions.items(.data)[@intFromEnum(inst)].br;
    const w = &f.code.writer;

    if (br.operand.toInterned()) |cond_ip_index| {
        const cond_val: Value = .fromInterned(cond_ip_index);
        // Comptime-known dispatch. Iterate the cases to find the correct
        // one, and branch directly to the corresponding case.
        const switch_br = f.air.unwrapSwitch(br.block_inst);
        var it = switch_br.iterateCases();
        const target_case_idx: u32 = target: while (it.next()) |case| {
            for (case.items) |item| {
                const val = Value.fromInterned(item.toInterned().?);
                if (cond_val.compareHetero(.eq, val, zcu)) break :target case.idx;
            }
            for (case.ranges) |range| {
                const low = Value.fromInterned(range[0].toInterned().?);
                const high = Value.fromInterned(range[1].toInterned().?);
                if (cond_val.compareHetero(.gte, low, zcu) and
                    cond_val.compareHetero(.lte, high, zcu))
                {
                    break :target case.idx;
                }
            }
        } else switch_br.cases_len;
        try w.print("goto zig_switch_{d}_dispatch_{d};\n", .{ @intFromEnum(br.block_inst), target_case_idx });
        return;
    }

    // Runtime-known dispatch. Set the switch condition, and branch back.
    const cond = try f.resolveInst(br.operand);
    const cond_local = f.loop_switch_conds.get(br.block_inst).?;
    try f.writeCValue(w, .{ .local = cond_local }, .other);
    try w.writeAll(" = ");
    try f.writeCValue(w, cond, .other);
    try w.writeByte(';');
    try f.newline();
    try w.print("goto zig_switch_{d}_loop;\n", .{@intFromEnum(br.block_inst)});
}

fn airBitcast(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const inst_ty = f.typeOfIndex(inst);

    const operand = try f.resolveInst(ty_op.operand);
    const operand_ty = f.typeOf(ty_op.operand);

    const bitcasted = try bitcast(f, inst_ty, operand, operand_ty);
    try reap(f, inst, &.{ty_op.operand});
    return f.moveCValue(inst, inst_ty, bitcasted);
}

fn bitcast(f: *Function, dest_ty: Type, operand: CValue, operand_ty: Type) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const target = &f.dg.mod.resolved_target.result;
    const w = &f.code.writer;

    if (operand_ty.isAbiInt(zcu) and dest_ty.isAbiInt(zcu)) {
        const src_info = dest_ty.intInfo(zcu);
        const dest_info = operand_ty.intInfo(zcu);
        if (src_info.signedness == dest_info.signedness and
            src_info.bits == dest_info.bits) return operand;
    }

    if (dest_ty.isPtrAtRuntime(zcu) or operand_ty.isPtrAtRuntime(zcu)) {
        const local = try f.allocLocal(null, dest_ty);
        try f.writeCValue(w, local, .other);
        try w.writeAll(" = (");
        try f.renderType(w, dest_ty);
        try w.writeByte(')');
        try f.writeCValue(w, operand, .other);
        try w.writeByte(';');
        try f.newline();
        return local;
    }

    const local = try f.allocLocal(null, dest_ty);
    // On big-endian targets, copying ABI integers with padding bits is awkward, because the padding bits are at the low bytes of the value.
    // We need to offset the source or destination pointer appropriately and copy the right number of bytes.
    if (target.cpu.arch.endian() == .big and dest_ty.isAbiInt(zcu) and !operand_ty.isAbiInt(zcu)) {
        // e.g. [10]u8 -> u80. We need to offset the destination so that we copy to the least significant bits of the integer.
        const offset = dest_ty.abiSize(zcu) - operand_ty.abiSize(zcu);
        try w.writeAll("memcpy((char *)&");
        try f.writeCValue(w, local, .other);
        try w.print(" + {d}, &", .{offset});
        switch (operand) {
            .constant => |val| try f.dg.renderValueAsLvalue(w, val),
            else => try f.writeCValue(w, operand, .other),
        }
        try w.print(", {d});", .{operand_ty.abiSize(zcu)});
    } else if (target.cpu.arch.endian() == .big and operand_ty.isAbiInt(zcu) and !dest_ty.isAbiInt(zcu)) {
        // e.g. u80 -> [10]u8. We need to offset the source so that we copy from the least significant bits of the integer.
        const offset = operand_ty.abiSize(zcu) - dest_ty.abiSize(zcu);
        try w.writeAll("memcpy(&");
        try f.writeCValue(w, local, .other);
        try w.writeAll(", (const char *)&");
        switch (operand) {
            .constant => |val| try f.dg.renderValueAsLvalue(w, val),
            else => try f.writeCValue(w, operand, .other),
        }
        try w.print(" + {d}, {d});", .{ offset, dest_ty.abiSize(zcu) });
    } else {
        try w.writeAll("memcpy(&");
        try f.writeCValue(w, local, .other);
        try w.writeAll(", &");
        switch (operand) {
            .constant => |val| try f.dg.renderValueAsLvalue(w, val),
            else => try f.writeCValue(w, operand, .other),
        }
        try w.print(", {d});", .{@min(dest_ty.abiSize(zcu), operand_ty.abiSize(zcu))});
    }

    try f.newline();

    // Ensure padding bits have the expected value.
    if (dest_ty.isAbiInt(zcu)) {
        switch (CType.classifyInt(dest_ty, zcu)) {
            .void => unreachable, // opv
            .small => {
                try f.writeCValue(w, local, .other);
                try w.writeAll(" = zig_wrap_");
                try f.dg.renderTypeForBuiltinFnName(w, dest_ty);
                try w.writeByte('(');
                try f.writeCValue(w, local, .other);
                try f.dg.renderBuiltinInfo(w, dest_ty, .bits);
                try w.writeAll(");");
                try f.newline();
            },
            .big => |big| {
                const dest_info = dest_ty.intInfo(zcu);
                const padding_index: u16 = switch (target.cpu.arch.endian()) {
                    .little => big.limbs_len - 1,
                    .big => 0,
                };
                const wrap_bits = ((dest_info.bits - 1) % big.limb_size.bits()) + 1;
                if (big.limb_size != .@"128" or dest_info.signedness == .unsigned) {
                    try f.writeCValueMember(w, local, .{ .identifier = "limbs" });
                    try w.print("[{d}] = zig_wrap_{c}{d}(", .{
                        padding_index,
                        signAbbrev(dest_info.signedness),
                        big.limb_size.bits(),
                    });
                    try f.writeCValueMember(w, local, .{ .identifier = "limbs" });
                    try w.print("[{d}], {d});", .{ padding_index, wrap_bits });
                } else {
                    try f.writeCValueMember(w, local, .{ .identifier = "limbs" });
                    try w.print("[{d}] = zig_bitCast_u128(zig_wrap_i128(zig_bitCast_i128(", .{
                        padding_index,
                    });
                    try f.writeCValueMember(w, local, .{ .identifier = "limbs" });
                    try w.print("[{d}]), {d}));", .{ padding_index, wrap_bits });
                    try f.newline();
                }
            },
        }
    }

    return local;
}

fn airTrap(f: *Function) !void {
    // Not even allowed to call trap in a naked function.
    if (f.dg.is_naked_fn) return;
    try f.code.writer.writeAll("zig_trap();\n");
}

fn airBreakpoint(f: *Function) !CValue {
    const w = &f.code.writer;
    try w.writeAll("zig_breakpoint();");
    try f.newline();
    return .none;
}

fn airRetAddr(f: *Function, inst: Air.Inst.Index) !CValue {
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, .usize);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = (");
    try f.renderType(w, .usize);
    try w.writeAll(")zig_return_address();");
    try f.newline();
    return local;
}

fn airFrameAddress(f: *Function, inst: Air.Inst.Index) !CValue {
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, .usize);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = (");
    try f.renderType(w, .usize);
    try w.writeAll(")zig_frame_address();");
    try f.newline();
    return local;
}

fn airUnreach(f: *Function) !void {
    // Not even allowed to call unreachable in a naked function.
    if (f.dg.is_naked_fn) return;
    try f.code.writer.writeAll("zig_unreachable();\n");
}

fn airLoop(f: *Function, inst: Air.Inst.Index) !void {
    const block = f.air.unwrapBlock(inst);
    const w = &f.code.writer;

    // `repeat` instructions matching this loop will branch to
    // this label. Since we need a label for arbitrary `repeat`
    // anyway, there's actually no need to use a "real" looping
    // construct at all!
    try w.print("zig_loop_{d}:", .{@intFromEnum(inst)});
    try f.newline();
    try genBodyInner(f, block.body); // no need to restore state, we're noreturn
}

fn airCondBr(f: *Function, inst: Air.Inst.Index) !void {
    const cond_br = f.air.unwrapCondBr(inst);
    const cond = try f.resolveInst(cond_br.condition);
    try reap(f, inst, &.{cond_br.condition});
    const then_body = cond_br.then_body;
    const else_body = cond_br.else_body;
    const liveness_condbr = f.liveness.getCondBr(inst);
    const w = &f.code.writer;

    try w.writeAll("if (");
    try f.writeCValue(w, cond, .other);
    try w.writeAll(") ");

    try genBodyResolveState(f, inst, liveness_condbr.then_deaths, then_body, false);
    try f.newline();
    if (else_body.len > 0) if (f.dg.expected_block) |_|
        return f.fail("runtime code not allowed in naked function", .{});

    // We don't need to use `genBodyResolveState` for the else block, because this instruction is
    // noreturn so must terminate a body, therefore we don't need to leave `value_map` or
    // `free_locals_map` well defined (our parent is responsible for doing that).

    for (liveness_condbr.else_deaths) |death| {
        try die(f, inst, death.toRef());
    }

    // We never actually need an else block, because our branches are noreturn so must (for
    // instance) `br` to a block (label).

    try genBodyInner(f, else_body);
}

fn airSwitchBr(f: *Function, inst: Air.Inst.Index, is_dispatch_loop: bool) !void {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const gpa = f.dg.gpa;
    const switch_br = f.air.unwrapSwitch(inst);
    const init_condition = try f.resolveInst(switch_br.operand);
    try reap(f, inst, &.{switch_br.operand});
    const cond_ty = f.typeOf(switch_br.operand);
    const w = &f.code.writer;

    // For dispatches, we will create a local alloc to contain the condition value.
    // This may not result in optimal codegen for switch loops, but it minimizes the
    // amount of C code we generate, which is probably more desirable here (and is simpler).
    const cond_val = if (is_dispatch_loop) cond: {
        const new_local = try f.allocLocal(inst, cond_ty);
        try f.copyCValue(new_local, init_condition);
        try w.print("zig_switch_{d}_loop:", .{@intFromEnum(inst)});
        try f.newline();
        try f.loop_switch_conds.put(gpa, inst, new_local.new_local);
        break :cond new_local;
    } else init_condition;

    defer if (is_dispatch_loop) {
        assert(f.loop_switch_conds.remove(inst));
    };

    const liveness = try f.liveness.getSwitchBr(gpa, inst, switch_br.cases_len + 1);
    defer gpa.free(liveness.deaths);

    const lowered_cond_ty: Type = switch (cond_ty.zigTypeTag(zcu)) {
        .@"enum", .error_set, .int, .@"struct", .@"union" => cond_ty,
        .bool => .u1,
        .pointer => .usize,
        .void => unreachable, // OPV type, always lowered to block/loop
        .comptime_int, .enum_literal, .@"fn", .type => unreachable, // comptime-only
        else => unreachable, // not supported by switch statement
    };
    const cond_cint = switch (CType.classifyInt(lowered_cond_ty, zcu)) {
        .void => unreachable, // OPV type, always lowered to block/loop
        .small => |small| small,
        .big => {
            return lowerSwitchToConditions(f, inst, cond_val, lowered_cond_ty, switch_br, liveness, is_dispatch_loop, false);
        },
    };

    switch (cond_cint) {
        .zig_u128, .zig_i128 => try w.writeAll("zig_switch_int128("),
        else => try w.writeAll("switch ("),
    }
    if (cond_ty.toIntern() != lowered_cond_ty.toIntern()) {
        try w.writeByte('(');
        try f.renderType(w, lowered_cond_ty);
        try w.writeByte(')');
    }
    try f.writeCValue(w, cond_val, .other);
    try w.writeAll(") {");
    f.indent();

    var any_range_cases = false;
    var it = switch_br.iterateCases();
    while (it.next()) |case| {
        if (case.ranges.len > 0) {
            any_range_cases = true;
            continue;
        }

        switch (cond_cint) {
            .zig_u128, .zig_i128 => {
                try f.newline();
                try w.writeAll("zig_switch_prong_begin_int128()");
            },
            else => {},
        }

        for (case.items) |item| {
            try f.newline();
            case: {
                switch (cond_cint) {
                    .zig_u128 => try w.writeAll(" zig_switch_case_int128(u128, "),
                    .zig_i128 => try w.writeAll(" zig_switch_case_int128(i128, "),
                    else => {
                        try w.writeAll("case ");
                        break :case;
                    },
                }
                if (cond_ty.toIntern() != lowered_cond_ty.toIntern()) {
                    try w.writeByte('(');
                    try f.renderType(w, lowered_cond_ty);
                    try w.writeByte(')');
                }
                try f.writeCValue(w, cond_val, .other);
                try w.writeAll(", ");
            }
            const item_value: Value = .fromInterned(item.toInterned().?);
            // If `item_value` is a pointer with a known integer address, print the address
            // with no cast to avoid a warning.
            write_val: {
                if (cond_ty.zigTypeTag(zcu) == .pointer) {
                    if (item_value.getUnsignedInt(zcu)) |item_int| {
                        try w.print("{f}", .{try f.fmtIntLiteralDec(try pt.intValue(lowered_cond_ty, item_int))});
                        break :write_val;
                    }
                    try w.writeByte('(');
                    try f.renderType(w, .usize);
                    try w.writeByte(')');
                }
                try f.dg.renderValue(w, .fromInterned(item.toInterned().?), .other);
            }
            switch (cond_cint) {
                .zig_u128, .zig_i128 => try w.writeByte(')'),
                else => try w.writeByte(':'),
            }
        }

        switch (cond_cint) {
            .zig_u128, .zig_i128 => {
                try f.newline();
                try w.writeAll("zig_switch_prong_end_int128()");
            },
            else => {},
        }

        try w.writeAll(" {");
        f.indent();
        try f.newline();
        if (is_dispatch_loop) {
            try w.print("zig_switch_{d}_dispatch_{d}:;", .{ @intFromEnum(inst), case.idx });
            try f.newline();
        }
        try genBodyResolveState(f, inst, liveness.deaths[case.idx], case.body, true);
        try f.outdent();
        try w.writeByte('}');
        if (f.dg.expected_block) |_|
            return f.fail("runtime code not allowed in naked function", .{});

        // The case body must be noreturn so we don't need to insert a break.
    }

    try f.newline();

    switch (cond_cint) {
        .zig_u128, .zig_i128 => try w.writeAll("zig_switch_default_int128() "),
        else => try w.writeAll("default: "),
    }
    if (any_range_cases) {
        // We will iterate the cases again to handle those with ranges, and generate
        // code using conditions rather than switch cases for such cases.
        try lowerSwitchToConditions(f, inst, cond_val, lowered_cond_ty, switch_br, liveness, is_dispatch_loop, true);
    }
    if (is_dispatch_loop) {
        try w.print("zig_switch_{d}_dispatch_{d}: ", .{ @intFromEnum(inst), switch_br.cases_len });
    }
    const else_body = it.elseBody();
    if (else_body.len > 0) {
        // Note that this must be the last case, so we do not need to use `genBodyResolveState`
        // since the parent block will do it (because the case body is noreturn).
        for (liveness.deaths[liveness.deaths.len - 1]) |death| {
            try die(f, inst, death.toRef());
        }
        try genBody(f, else_body);
        if (f.dg.expected_block) |_|
            return f.fail("runtime code not allowed in naked function", .{});
    } else try airUnreach(f);
    try f.newline();
    try f.outdent();
    try w.writeAll("}\n");
}
fn lowerSwitchToConditions(
    f: *Function,
    inst: Air.Inst.Index,
    cond_val: CValue,
    cond_ty: Type,
    switch_br: Air.UnwrappedSwitch,
    liveness: Air.Liveness.SwitchBrTable,
    is_dispatch_loop: bool,
    only_ranges: bool,
) !void {
    const w = &f.code.writer;

    var it = switch_br.iterateCases();
    while (it.next()) |case| {
        if (case.ranges.len == 0 and only_ranges) continue;

        try w.writeAll("if (");
        for (case.items, 0..) |item, item_i| {
            if (item_i != 0) {
                try f.newline();
                try w.writeAll(" || ");
            }
            try lowerSwitchCmp(f, cond_val, .eq, item, cond_ty);
        }
        for (case.ranges, 0..) |range, range_i| {
            if (case.items.len != 0 or range_i != 0) {
                try f.newline();
                try w.writeAll(" || ");
            }
            // "(x >= lower && x <= upper)"
            try w.writeByte('(');
            try lowerSwitchCmp(f, cond_val, .gte, range[0], cond_ty);
            try w.writeAll(" && ");
            try lowerSwitchCmp(f, cond_val, .lte, range[1], cond_ty);
            try w.writeByte(')');
        }
        try w.writeAll(") {");
        f.indent();
        try f.newline();
        if (is_dispatch_loop) {
            try w.print("zig_switch_{d}_dispatch_{d}: ", .{ @intFromEnum(inst), case.idx });
        }
        try genBodyResolveState(f, inst, liveness.deaths[case.idx], case.body, true);
        try f.outdent();
        try w.writeByte('}');
        try f.newline();
        if (f.dg.expected_block) |_|
            return f.fail("runtime code not allowed in naked function", .{});
    }

    if (!only_ranges) {
        if (is_dispatch_loop) {
            try w.print("zig_switch_{d}_dispatch_{d}: ", .{ @intFromEnum(inst), switch_br.cases_len });
        }
        const else_body = it.elseBody();
        if (else_body.len > 0) {
            // Note that this must be the last case, so we do not need to use `genBodyResolveState`
            // since the parent block will do it (because the case body is noreturn).
            for (liveness.deaths[liveness.deaths.len - 1]) |death| {
                try die(f, inst, death.toRef());
            }
            try genBody(f, else_body);
            if (f.dg.expected_block) |_|
                return f.fail("runtime code not allowed in naked function", .{});
        } else try airUnreach(f);
        try f.newline();
    }
}
fn lowerSwitchCmp(
    f: *Function,
    cond_val: CValue,
    operator: std.math.CompareOperator,
    case_inst: Air.Inst.Ref,
    ty: Type,
) !void {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const w = &f.code.writer;

    const class = CType.classifyInt(ty, zcu);
    const use_builtin = switch (class) {
        .void => unreachable, // assertion failure
        .small => |small| switch (small) {
            .zig_u128, .zig_i128 => true,
            else => false,
        },
        .big => true,
    };
    if (use_builtin) {
        try w.writeAll("zig_cmp_");
        try f.dg.renderTypeForBuiltinFnName(w, ty);
        try w.writeByte('(');
    }
    if (class == .big) try w.writeByte('&');
    try f.writeCValue(w, cond_val, .other);
    try w.writeAll(if (use_builtin) ", " else compareOperatorC(operator));
    if (class == .big) try w.writeByte('&');
    try f.dg.renderValue(w, .fromInterned(case_inst.toInterned().?), .other);
    if (use_builtin) {
        try f.dg.renderBuiltinInfo(w, ty, if (class == .big) .bits else .none);
        try w.writeByte(')');
        try w.writeAll(compareOperatorC(operator));
        try w.writeByte('0');
    }
}

fn asmInputNeedsLocal(f: *Function, constraint: []const u8, value: CValue) bool {
    const dg = f.dg;
    const target = &dg.mod.resolved_target.result;
    return switch (constraint[0]) {
        '{' => true,
        'i', 'r' => false,
        'I' => !target.cpu.arch.isArm(),
        else => switch (value) {
            .constant => |val| switch (dg.pt.zcu.intern_pool.indexToKey(val.toIntern())) {
                .ptr => |ptr| if (ptr.byte_offset == 0) switch (ptr.base_addr) {
                    .nav => false,
                    else => true,
                } else true,
                else => true,
            },
            else => false,
        },
    };
}

fn airAsm(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const unwrapped_asm = f.air.unwrapAsm(inst);
    const is_volatile = unwrapped_asm.is_volatile;
    const gpa = f.dg.gpa;
    const outputs = unwrapped_asm.outputs;
    const inputs = unwrapped_asm.inputs;

    const result = result: {
        const w = &f.code.writer;
        const inst_ty = f.typeOfIndex(inst);
        const inst_local = if (inst_ty.hasRuntimeBits(zcu)) local: {
            const inst_local = try f.allocLocalValue(.{
                .type = inst_ty,
                .alignment = .none,
            });
            if (f.wantSafety()) {
                try f.writeCValue(w, inst_local, .other);
                try w.writeAll(" = ");
                try f.writeCValue(w, .{ .undef = inst_ty }, .other);
                try w.writeByte(';');
                try f.newline();
            }
            break :local inst_local;
        } else .none;

        const locals_begin: LocalIndex = @intCast(f.locals.items.len);
        var it = unwrapped_asm.iterateOutputs();
        while (it.next()) |output| {
            const constraint = output.constraint;

            if (constraint.len < 2 or constraint[0] != '=' or
                (constraint[1] == '{' and constraint[constraint.len - 1] != '}'))
            {
                return f.fail("CBE: constraint not supported: '{s}'", .{constraint});
            }

            const is_reg = constraint[1] == '{';
            if (is_reg) {
                const output_ty = if (output.operand == .none) inst_ty else f.typeOf(output.operand).childType(zcu);
                try w.writeAll("register ");
                const output_local = try f.allocLocalValue(.{
                    .type = output_ty,
                    .alignment = .none,
                });
                try f.allocs.put(gpa, output_local.new_local, false);
                try f.dg.renderTypeAndName(w, output_ty, output_local, .{}, .none);
                try w.writeAll(" __asm(\"");
                try w.writeAll(constraint["={".len .. constraint.len - "}".len]);
                try w.writeAll("\")");
                if (f.wantSafety()) {
                    try w.writeAll(" = ");
                    try f.writeCValue(w, .{ .undef = output_ty }, .other);
                }
                try w.writeByte(';');
                try f.newline();
            }
        }

        it = unwrapped_asm.iterateInputs();
        while (it.next()) |input| {
            const constraint = input.constraint;

            if (constraint.len < 1 or mem.indexOfScalar(u8, "=+&%", constraint[0]) != null or
                (constraint[0] == '{' and constraint[constraint.len - 1] != '}'))
            {
                return f.fail("CBE: constraint not supported: '{s}'", .{constraint});
            }

            const is_reg = constraint[0] == '{';
            const input_val = try f.resolveInst(input.operand);
            if (asmInputNeedsLocal(f, constraint, input_val)) {
                const input_ty = f.typeOf(input.operand);
                if (is_reg) try w.writeAll("register ");
                const input_local = try f.allocLocalValue(.{
                    .type = input_ty,
                    .alignment = .none,
                });
                try f.allocs.put(gpa, input_local.new_local, false);
                // Do not render the declaration as `const` qualified if we're generating an
                // explicit `register` local, as GCC will ignore the constraint completely.
                try f.dg.renderTypeAndName(w, input_ty, input_local, .{ .@"const" = is_reg }, .none);
                if (is_reg) {
                    try w.writeAll(" __asm(\"");
                    try w.writeAll(constraint["{".len .. constraint.len - "}".len]);
                    try w.writeAll("\")");
                }
                try w.writeAll(" = ");
                try f.writeCValue(w, input_val, .other);
                try w.writeByte(';');
                try f.newline();
            }
        }

        {
            const asm_source = unwrapped_asm.source;

            var stack = std.heap.stackFallback(256, f.dg.gpa);
            const allocator = stack.get();
            const fixed_asm_source = try allocator.alloc(u8, asm_source.len);
            defer allocator.free(fixed_asm_source);

            var src_i: usize = 0;
            var dst_i: usize = 0;
            while (true) {
                const literal = mem.sliceTo(asm_source[src_i..], '%');
                src_i += literal.len;

                @memcpy(fixed_asm_source[dst_i..][0..literal.len], literal);
                dst_i += literal.len;

                if (src_i >= asm_source.len) break;

                src_i += 1;
                if (src_i >= asm_source.len)
                    return f.fail("CBE: invalid inline asm string '{s}'", .{asm_source});

                fixed_asm_source[dst_i] = '%';
                dst_i += 1;

                if (asm_source[src_i] != '[') {
                    // This also handles %%
                    fixed_asm_source[dst_i] = asm_source[src_i];
                    src_i += 1;
                    dst_i += 1;
                    continue;
                }

                const desc = mem.sliceTo(asm_source[src_i..], ']');
                if (mem.indexOfScalar(u8, desc, ':')) |colon| {
                    const name = desc[0..colon];
                    const modifier = desc[colon + 1 ..];

                    @memcpy(fixed_asm_source[dst_i..][0..modifier.len], modifier);
                    dst_i += modifier.len;
                    @memcpy(fixed_asm_source[dst_i..][0..name.len], name);
                    dst_i += name.len;

                    src_i += desc.len;
                    if (src_i >= asm_source.len)
                        return f.fail("CBE: invalid inline asm string '{s}'", .{asm_source});
                }
            }

            try w.writeAll("__asm");
            if (is_volatile) try w.writeAll(" volatile");
            try w.print("({f}", .{fmtStringLiteral(fixed_asm_source[0..dst_i], null)});
        }

        var locals_index = locals_begin;
        try w.writeByte(':');

        it = unwrapped_asm.iterateOutputs();
        while (it.next()) |output| {
            const constraint = output.constraint;
            const name = output.name;

            if (output.index > 0) try w.writeByte(',');
            try w.writeByte(' ');
            if (!mem.eql(u8, name, "_")) try w.print("[{s}]", .{name});
            const is_reg = constraint[1] == '{';
            try w.print("{f}(", .{fmtStringLiteral(if (is_reg) "=r" else constraint, null)});
            if (is_reg) {
                try f.writeCValue(w, .{ .local = locals_index }, .other);
                locals_index += 1;
            } else if (output.operand == .none) {
                try f.writeCValue(w, inst_local, .other);
            } else {
                try f.writeCValueDeref(w, try f.resolveInst(output.operand));
            }
            try w.writeByte(')');
        }
        try w.writeByte(':');

        it = unwrapped_asm.iterateInputs();
        while (it.next()) |input| {
            const constraint = input.constraint;
            const name = input.name;

            if (input.index > 0) try w.writeByte(',');
            try w.writeByte(' ');
            if (!mem.eql(u8, name, "_")) try w.print("[{s}]", .{name});

            const is_reg = constraint[0] == '{';
            const input_val = try f.resolveInst(input.operand);
            try w.print("{f}(", .{fmtStringLiteral(if (is_reg) "r" else constraint, null)});
            try f.writeCValue(w, if (asmInputNeedsLocal(f, constraint, input_val)) local: {
                const input_local_idx = locals_index;
                locals_index += 1;
                break :local .{ .local = input_local_idx };
            } else input_val, .other);
            try w.writeByte(')');
        }
        try w.writeByte(':');
        const ip = &zcu.intern_pool;
        const clobbers_val: Value = .fromInterned(unwrapped_asm.clobbers);
        const clobbers_ty = clobbers_val.typeOf(zcu);
        var clobbers_bigint_buf: Value.BigIntSpace = undefined;
        const clobbers_bigint = clobbers_val.toBigInt(&clobbers_bigint_buf, zcu);
        for (0..clobbers_ty.structFieldCount(zcu)) |field_index| {
            assert(clobbers_ty.fieldType(field_index, zcu).toIntern() == .bool_type);
            const limb_bits = @bitSizeOf(std.math.big.Limb);
            if (field_index / limb_bits >= clobbers_bigint.limbs.len) continue; // field is false
            switch (@as(u1, @truncate(clobbers_bigint.limbs[field_index / limb_bits] >> @intCast(field_index % limb_bits)))) {
                0 => continue, // field is false
                1 => {}, // field is true
            }
            const field_name = clobbers_ty.structFieldName(field_index, zcu).toSlice(ip).?;
            assert(field_name.len != 0);

            const target = &f.dg.mod.resolved_target.result;
            var c_name_buf: [16]u8 = undefined;
            const name =
                if ((target.cpu.arch.isMIPS() or target.cpu.arch == .alpha) and field_name[0] == 'r') name: {
                    // Convert "rN" to "$N"
                    const c_name = (&c_name_buf)[0..field_name.len];
                    @memcpy(c_name, field_name);
                    c_name_buf[0] = '$';
                    break :name c_name;
                } else if ((target.cpu.arch.isMIPS() and (mem.startsWith(u8, field_name, "fcc") or field_name[0] == 'w')) or
                ((target.cpu.arch.isMIPS() or target.cpu.arch == .alpha) and field_name[0] == 'f') or
                (target.cpu.arch == .kvx and !mem.eql(u8, field_name, "memory"))) name: {
                    // "$" prefix for these registers
                    c_name_buf[0] = '$';
                    @memcpy((&c_name_buf)[1..][0..field_name.len], field_name);
                    break :name (&c_name_buf)[0 .. 1 + field_name.len];
                } else if (target.cpu.arch.isSPARC() and
                (mem.eql(u8, field_name, "ccr") or mem.eql(u8, field_name, "icc") or mem.eql(u8, field_name, "xcc"))) name: {
                    // C compilers just use `icc` to encompass all of these.
                    break :name "icc";
                } else field_name;

            try w.print(" {f}", .{fmtStringLiteral(name, null)});
            (try w.writableArray(1))[0] = ',';
        }
        w.undo(1); // erase the last comma
        try w.writeAll(");");
        try f.newline();

        locals_index = locals_begin;
        it = unwrapped_asm.iterateOutputs();
        while (it.next()) |output| {
            const constraint = output.constraint;

            const is_reg = constraint[1] == '{';
            if (is_reg) {
                try f.writeCValueDeref(w, if (output.operand == .none)
                    .{ .local_ref = inst_local.new_local }
                else
                    try f.resolveInst(output.operand));
                try w.writeAll(" = ");
                try f.writeCValue(w, .{ .local = locals_index }, .other);
                locals_index += 1;
                try w.writeByte(';');
                try f.newline();
            }
        }

        break :result if (f.liveness.isUnused(inst)) .none else inst_local;
    };

    var bt = iterateBigTomb(f, inst);
    for (outputs) |output| {
        if (output == .none) continue;
        try bt.feed(output);
    }
    for (inputs) |input| {
        try bt.feed(input);
    }

    return result;
}

fn airIsNull(
    f: *Function,
    inst: Air.Inst.Index,
    operator: enum { eq, neq },
    is_ptr: bool,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;

    const w = &f.code.writer;
    const operand = try f.resolveInst(un_op);
    try reap(f, inst, &.{un_op});

    const local = try f.allocLocal(inst, .bool);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");

    const operand_ty = f.typeOf(un_op);
    const optional_ty = if (is_ptr) operand_ty.childType(zcu) else operand_ty;

    const pre: []const u8, const maybe_field: ?[]const u8, const post: []const u8 = switch (operator) {
        // zig fmt: off
        .eq => switch (CType.classifyOptional(optional_ty, zcu)) {
            .npv_payload => unreachable, // opv optional
            .error_set   => .{ "", null,      " == 0" },
            .ptr_like    => .{ "", null,      " == NULL" },
            .slice_like  => .{ "", "ptr",     " == NULL" },
            .opv_payload => .{ "", "is_null", "" },
            .@"struct"   => .{ "", "is_null", "" },
        },
        .neq => switch (CType.classifyOptional(optional_ty, zcu)) {
            .npv_payload => unreachable, // opv optional
            .error_set   => .{ "",  null,      " != 0" },
            .ptr_like    => .{ "",  null,      " != NULL" },
            .slice_like  => .{ "",  "ptr",     " != NULL" },
            .opv_payload => .{ "!", "is_null", "" },
            .@"struct"   => .{ "!", "is_null", "" },
        },
        // zig fmt: on
    };

    try w.writeAll(pre);
    if (maybe_field) |field| {
        if (is_ptr) {
            try f.writeCValueDerefMember(w, operand, .{ .identifier = field });
        } else {
            try f.writeCValueMember(w, operand, .{ .identifier = field });
        }
    } else {
        if (is_ptr) {
            try f.writeCValueDeref(w, operand);
        } else {
            try f.writeCValue(w, operand, .other);
        }
    }
    try w.writeAll(post);

    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airOptionalPayload(f: *Function, inst: Air.Inst.Index, is_ptr: bool) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const operand_ty = f.typeOf(ty_op.operand);
    const opt_ty = if (is_ptr) operand_ty.childType(zcu) else operand_ty;

    const operand = try f.resolveInst(ty_op.operand);

    switch (CType.classifyOptional(opt_ty, zcu)) {
        .npv_payload => unreachable, // opv optional

        .opv_payload => return if (is_ptr) .{ .undef = inst_ty } else .none,

        .error_set,
        .ptr_like,
        .slice_like,
        => return f.moveCValue(inst, inst_ty, operand),

        .@"struct" => {
            const w = &f.code.writer;
            const local = try f.allocLocal(inst, inst_ty);
            try f.writeCValue(w, local, .other);
            try w.writeAll(" = ");
            if (is_ptr) {
                try w.writeByte('&');
                try f.writeCValueDerefMember(w, operand, .{ .identifier = "payload" });
            } else try f.writeCValueMember(w, operand, .{ .identifier = "payload" });
            try w.writeByte(';');
            try f.newline();
            return local;
        },
    }
}

fn airOptionalPayloadPtrSet(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const w = &f.code.writer;
    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});
    const operand_ty = f.typeOf(ty_op.operand);
    const opt_ty = operand_ty.childType(zcu);

    const inst_ty = f.typeOfIndex(inst);

    switch (CType.classifyOptional(opt_ty, zcu)) {
        .npv_payload => unreachable, // opv optional

        .opv_payload => {
            try f.writeCValueDerefMember(w, operand, .{ .identifier = "is_null" });
            try w.writeAll(" = ");
            try f.dg.renderValue(w, .false, .other);
            try w.writeByte(';');
            try f.newline();
            return .{ .undef = inst_ty };
        },

        .error_set,
        .ptr_like,
        .slice_like,
        => return f.moveCValue(inst, inst_ty, operand),

        .@"struct" => {
            try f.writeCValueDerefMember(w, operand, .{ .identifier = "is_null" });
            try w.writeAll(" = ");
            try f.dg.renderValue(w, .false, .other);
            try w.writeByte(';');
            try f.newline();
            if (f.liveness.isUnused(inst)) return .none;
            const local = try f.allocLocal(inst, inst_ty);
            try f.writeCValue(w, local, .other);
            try w.writeAll(" = &");
            try f.writeCValueDerefMember(w, operand, .{ .identifier = "payload" });
            try w.writeByte(';');
            try f.newline();
            return local;
        },
    }
}

fn fieldLocation(
    container_ptr_ty: Type,
    field_ptr_ty: Type,
    field_index: u32,
    zcu: *Zcu,
) union(enum) {
    begin: void,
    field: CValue,
    byte_offset: u64,
} {
    const ip = &zcu.intern_pool;
    const container_ty: Type = .fromInterned(ip.indexToKey(container_ptr_ty.toIntern()).ptr_type.child);
    switch (ip.indexToKey(container_ty.toIntern())) {
        .struct_type => {
            const loaded_struct = ip.loadStructType(container_ty.toIntern());
            return switch (loaded_struct.layout) {
                .auto, .@"extern" => if (!container_ty.hasRuntimeBits(zcu))
                    .begin
                else if (!field_ptr_ty.childType(zcu).hasRuntimeBits(zcu))
                    .{ .byte_offset = loaded_struct.field_offsets.get(ip)[field_index] }
                else
                    .{ .field = .{ .identifier = loaded_struct.field_names.get(ip)[field_index].toSlice(ip) } },
                .@"packed" => if (field_ptr_ty.ptrInfo(zcu).packed_offset.host_size == 0)
                    .{ .byte_offset = @divExact(zcu.structPackedFieldBitOffset(loaded_struct, field_index) +
                        container_ptr_ty.ptrInfo(zcu).packed_offset.bit_offset, 8) }
                else
                    .begin,
            };
        },
        .tuple_type => return if (!container_ty.hasRuntimeBits(zcu))
            .begin
        else if (!field_ptr_ty.childType(zcu).hasRuntimeBits(zcu))
            .{ .byte_offset = container_ty.structFieldOffset(field_index, zcu) }
        else
            .{ .field = .{ .field = field_index } },
        .union_type => {
            const loaded_union = ip.loadUnionType(container_ty.toIntern());
            switch (loaded_union.layout) {
                .auto => {
                    const field_ty: Type = .fromInterned(loaded_union.field_types.get(ip)[field_index]);
                    if (!field_ty.hasRuntimeBits(zcu)) {
                        if (container_ty.unionHasAllZeroBitFieldTypes(zcu)) return .begin;
                        return .{ .field = .{ .identifier = "payload" } };
                    }
                    const field_name = ip.loadEnumType(loaded_union.enum_tag_type).field_names.get(ip)[field_index];
                    return .{ .field = .{ .payload_identifier = field_name.toSlice(ip) } };
                },
                .@"extern" => {
                    const field_ty: Type = .fromInterned(loaded_union.field_types.get(ip)[field_index]);
                    if (!field_ty.hasRuntimeBits(zcu)) return .begin;
                    const field_name = ip.loadEnumType(loaded_union.enum_tag_type).field_names.get(ip)[field_index];
                    return .{ .field = .{ .identifier = field_name.toSlice(ip) } };
                },
                .@"packed" => return .begin,
            }
        },
        .ptr_type => |ptr_info| switch (ptr_info.flags.size) {
            .one, .many, .c => unreachable,
            .slice => switch (field_index) {
                0 => return .{ .field = .{ .identifier = "ptr" } },
                1 => return .{ .field = .{ .identifier = "len" } },
                else => unreachable,
            },
        },
        else => unreachable,
    }
}

fn airStructFieldPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = f.air.extraData(Air.StructField, ty_pl.payload).data;

    const container_ptr_val = try f.resolveInst(extra.struct_operand);
    try reap(f, inst, &.{extra.struct_operand});
    const container_ptr_ty = f.typeOf(extra.struct_operand);
    return fieldPtr(f, inst, container_ptr_ty, container_ptr_val, extra.field_index);
}

fn airStructFieldPtrIndex(f: *Function, inst: Air.Inst.Index, index: u8) !CValue {
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const container_ptr_val = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});
    const container_ptr_ty = f.typeOf(ty_op.operand);
    return fieldPtr(f, inst, container_ptr_ty, container_ptr_val, index);
}

fn airFieldParentPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = f.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;

    const container_ptr_ty = f.typeOfIndex(inst);
    const container_ty = container_ptr_ty.childType(zcu);

    const field_ptr_ty = f.typeOf(extra.field_ptr);
    const field_ptr_val = try f.resolveInst(extra.field_ptr);
    try reap(f, inst, &.{extra.field_ptr});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, container_ptr_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = (");
    try f.renderType(w, container_ptr_ty);
    try w.writeByte(')');

    switch (fieldLocation(container_ptr_ty, field_ptr_ty, extra.field_index, zcu)) {
        .begin => try f.writeCValue(w, field_ptr_val, .other),
        .field => |field| {
            const u8_ptr_ty = try pt.adjustPtrTypeChild(field_ptr_ty, .u8);

            try w.writeAll("((");
            try f.renderType(w, u8_ptr_ty);
            try w.writeByte(')');
            try f.writeCValue(w, field_ptr_val, .other);
            try w.writeAll(" - offsetof(");
            try f.renderType(w, container_ty);
            try w.writeAll(", ");
            try f.writeCValue(w, field, .other);
            try w.writeAll("))");
        },
        .byte_offset => |byte_offset| {
            const u8_ptr_ty = try pt.adjustPtrTypeChild(field_ptr_ty, .u8);

            try w.writeAll("((");
            try f.renderType(w, u8_ptr_ty);
            try w.writeByte(')');
            try f.writeCValue(w, field_ptr_val, .other);
            try w.print(" - {f})", .{
                try f.fmtIntLiteralDec(try pt.intValue(.usize, byte_offset)),
            });
        },
    }

    try w.writeByte(';');
    try f.newline();
    return local;
}

fn fieldPtr(
    f: *Function,
    inst: Air.Inst.Index,
    container_ptr_ty: Type,
    container_ptr_val: CValue,
    field_index: u32,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const field_ptr_ty = f.typeOfIndex(inst);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, field_ptr_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = (");
    try f.renderType(w, field_ptr_ty);
    try w.writeByte(')');

    switch (fieldLocation(container_ptr_ty, field_ptr_ty, field_index, zcu)) {
        .begin => try f.writeCValue(w, container_ptr_val, .other),
        .field => |field| {
            try w.writeByte('&');
            try f.writeCValueDerefMember(w, container_ptr_val, field);
        },
        .byte_offset => |byte_offset| {
            const u8_ptr_ty = try pt.adjustPtrTypeChild(field_ptr_ty, .u8);

            try w.writeAll("((");
            try f.renderType(w, u8_ptr_ty);
            try w.writeByte(')');
            try f.writeCValue(w, container_ptr_val, .other);
            try w.print(" + {f})", .{
                try f.fmtIntLiteralDec(try pt.intValue(.usize, byte_offset)),
            });
        },
    }

    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airStructFieldVal(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = f.air.extraData(Air.StructField, ty_pl.payload).data;

    const inst_ty = f.typeOfIndex(inst);
    assert(inst_ty.hasRuntimeBits(zcu));

    const struct_byval = try f.resolveInst(extra.struct_operand);
    try reap(f, inst, &.{extra.struct_operand});
    const struct_ty = f.typeOf(extra.struct_operand);
    const w = &f.code.writer;

    assert(struct_ty.containerLayout(zcu) != .@"packed"); // `Air.Legalize.Feature.expand_packed_struct_field_val` handles this case
    const field_name: CValue = switch (ip.indexToKey(struct_ty.toIntern())) {
        .struct_type => .{ .identifier = struct_ty.structFieldName(extra.field_index, zcu).unwrap().?.toSlice(ip) },
        .union_type => name: {
            const union_type = ip.loadUnionType(struct_ty.toIntern());
            const enum_tag_ty: Type = .fromInterned(union_type.enum_tag_type);
            const field_name_str = enum_tag_ty.enumFieldName(extra.field_index, zcu).toSlice(ip);
            break :name .{ .payload_identifier = field_name_str };
        },
        .tuple_type => .{ .field = extra.field_index },
        else => unreachable,
    };

    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try f.writeCValueMember(w, struct_byval, field_name);
    try w.writeByte(';');
    try f.newline();
    return local;
}

/// *(E!T) -> E
/// Note that the result is never a pointer.
fn airUnwrapErrUnionErr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(ty_op.operand);
    const operand_ty = f.typeOf(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const operand_is_ptr = operand_ty.zigTypeTag(zcu) == .pointer;
    const local = try f.allocLocal(inst, inst_ty);

    const w = &f.code.writer;
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");

    if (operand_is_ptr)
        try f.writeCValueDerefMember(w, operand, .{ .identifier = "error" })
    else
        try f.writeCValueMember(w, operand, .{ .identifier = "error" });
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airUnwrapErrUnionPay(f: *Function, inst: Air.Inst.Index, is_ptr: bool) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});
    const operand_ty = f.typeOf(ty_op.operand);
    const error_union_ty = if (is_ptr) operand_ty.childType(zcu) else operand_ty;

    const w = &f.code.writer;
    if (!error_union_ty.errorUnionPayload(zcu).hasRuntimeBits(zcu)) {
        assert(is_ptr); // opv bug in sema
        const local = try f.allocLocal(inst, inst_ty);
        try f.writeCValue(w, local, .other);
        try w.writeAll(" = (");
        try f.renderType(w, inst_ty);
        try w.writeByte(')');
        try f.writeCValue(w, operand, .other);
        try w.writeByte(';');
        try f.newline();
        return local;
    }

    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    if (is_ptr) {
        try w.writeByte('&');
        try f.writeCValueDerefMember(w, operand, .{ .identifier = "payload" });
    } else try f.writeCValueMember(w, operand, .{ .identifier = "payload" });
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airWrapOptional(f: *Function, inst: Air.Inst.Index) !CValue {
    const zcu = f.dg.pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);

    const operand = try f.resolveInst(ty_op.operand);

    switch (CType.classifyOptional(inst_ty, zcu)) {
        .npv_payload => unreachable, // opv optional

        .opv_payload => unreachable, // opv bug in Sema

        .error_set,
        .ptr_like,
        .slice_like,
        => return f.moveCValue(inst, inst_ty, operand),

        .@"struct" => {
            const w = &f.code.writer;
            const local = try f.allocLocal(inst, inst_ty);

            try f.writeCValueMember(w, local, .{ .identifier = "is_null" });
            try w.writeAll(" = false;");
            try f.newline();

            try f.writeCValueMember(w, local, .{ .identifier = "payload" });
            try w.writeAll(" = ");
            try f.writeCValue(w, operand, .other);
            try w.writeByte(';');
            try f.newline();

            return local;
        },
    }
}

fn airWrapErrUnionErr(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const payload_ty = inst_ty.errorUnionPayload(zcu);
    const err = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);

    if (payload_ty.hasRuntimeBits(zcu)) {
        try f.writeCValueMember(w, local, .{ .identifier = "payload" });
        try w.writeAll(" = ");
        try f.dg.renderUndefValue(w, payload_ty, .other);
        try w.writeByte(';');
        try f.newline();
    }

    try f.writeCValueMember(w, local, .{ .identifier = "error" });
    try w.writeAll(" = ");
    try f.writeCValue(w, err, .other);
    try w.writeByte(';');
    try f.newline();

    return local;
}

fn airErrUnionPayloadPtrSet(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const w = &f.code.writer;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const inst_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(ty_op.operand);

    const err_int_ty = try pt.errorIntType();
    const no_err = try pt.intValue(err_int_ty, 0);
    try reap(f, inst, &.{ty_op.operand});

    // First, set the non-error value.
    try f.writeCValueDerefMember(w, operand, .{ .identifier = "error" });
    try w.print(" = {f};", .{try f.fmtIntLiteralDec(no_err)});
    try f.newline();

    // Then return the payload pointer (only if it is used)
    if (f.liveness.isUnused(inst)) return .none;

    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = &");
    try f.writeCValueDerefMember(w, operand, .{ .identifier = "payload" });
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airErrReturnTrace(f: *Function, inst: Air.Inst.Index) !CValue {
    _ = inst;
    return f.fail("TODO: C backend: implement airErrReturnTrace", .{});
}

fn airSetErrReturnTrace(f: *Function, inst: Air.Inst.Index) !CValue {
    _ = inst;
    return f.fail("TODO: C backend: implement airSetErrReturnTrace", .{});
}

fn airSaveErrReturnTraceIndex(f: *Function, inst: Air.Inst.Index) !CValue {
    _ = inst;
    return f.fail("TODO: C backend: implement airSaveErrReturnTraceIndex", .{});
}

fn airWrapErrUnionPay(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const payload_ty = inst_ty.errorUnionPayload(zcu);
    const payload = try f.resolveInst(ty_op.operand);
    assert(payload_ty.hasRuntimeBits(zcu));
    try reap(f, inst, &.{ty_op.operand});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);

    try f.writeCValueMember(w, local, .{ .identifier = "payload" });
    try w.writeAll(" = ");
    try f.writeCValue(w, payload, .other);
    try w.writeByte(';');
    try f.newline();

    try f.writeCValueMember(w, local, .{ .identifier = "error" });
    try w.writeAll(" = ");
    try f.dg.renderValue(w, try pt.intValue(try pt.errorIntType(), 0), .other);
    try w.writeByte(';');
    try f.newline();

    return local;
}

fn airIsErr(f: *Function, inst: Air.Inst.Index, is_ptr: bool, operator: []const u8) !CValue {
    const pt = f.dg.pt;
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;

    const w = &f.code.writer;
    const operand = try f.resolveInst(un_op);
    try reap(f, inst, &.{un_op});
    const local = try f.allocLocal(inst, .bool);

    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    const err_int_ty = try pt.errorIntType();
    if (is_ptr)
        try f.writeCValueDerefMember(w, operand, .{ .identifier = "error" })
    else
        try f.writeCValueMember(w, operand, .{ .identifier = "error" });
    try w.print(" {s} ", .{operator});
    try f.dg.renderValue(w, try pt.intValue(err_int_ty, 0), .other);
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airArrayToSlice(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});
    const inst_ty = f.typeOfIndex(inst);
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const operand_ty = f.typeOf(ty_op.operand);
    const array_ty = operand_ty.childType(zcu);

    // We have a `*[n]T`, which was turned into to a pointer to `struct { T array[n]; }`.
    // Ideally we would want to use 'operand->array' to convert to a `T *` (we get a `T []`
    // which decays to a pointer), but if the element type is zero-bit or the array length is
    // zero, there will not be an `array` member (the array type lowers to `void`). We cannot
    // check the type layout here because it may not be resolved, so in this instance, we must
    // use a pointer cast.
    try f.writeCValueMember(w, local, .{ .identifier = "ptr" });
    try w.writeAll(" = (");
    try f.dg.renderType(w, inst_ty.slicePtrFieldType(zcu));
    try w.writeByte(')');
    try f.writeCValue(w, operand, .other);
    try w.writeByte(';');
    try f.newline();

    try f.writeCValueMember(w, local, .{ .identifier = "len" });
    try w.print(" = {f}", .{
        try f.fmtIntLiteralDec(try pt.intValue(.usize, array_ty.arrayLen(zcu))),
    });
    try w.writeByte(';');
    try f.newline();

    return local;
}

fn airFloatCast(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});
    const operand_ty = f.typeOf(ty_op.operand);
    const scalar_ty = operand_ty.scalarType(zcu);
    const target = &f.dg.mod.resolved_target.result;
    const operation = if (inst_scalar_ty.isRuntimeFloat() and scalar_ty.isRuntimeFloat())
        if (inst_scalar_ty.floatBits(target) < scalar_ty.floatBits(target)) "trunc" else "extend"
    else if (inst_scalar_ty.isInt(zcu) and scalar_ty.isRuntimeFloat())
        if (inst_scalar_ty.isSignedInt(zcu)) "fix" else "fixuns"
    else if (inst_scalar_ty.isRuntimeFloat() and scalar_ty.isInt(zcu))
        if (scalar_ty.isSignedInt(zcu)) "float" else "floatun"
    else
        unreachable;

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    if (inst_scalar_ty.isInt(zcu) and scalar_ty.isRuntimeFloat()) {
        try w.writeAll("zig_wrap_");
        try f.dg.renderTypeForBuiltinFnName(w, inst_scalar_ty);
        try w.writeByte('(');
    }
    try w.writeAll("zig_");
    try w.writeAll(operation);
    try w.writeAll(compilerRtAbbrev(scalar_ty, zcu, target));
    try w.writeAll(compilerRtAbbrev(inst_scalar_ty, zcu, target));
    try w.writeByte('(');
    try f.writeCValue(w, operand, .other);
    try v.elem(f, w);
    try w.writeByte(')');
    if (inst_scalar_ty.isInt(zcu) and scalar_ty.isRuntimeFloat()) {
        try f.dg.renderBuiltinInfo(w, inst_scalar_ty, .bits);
        try w.writeByte(')');
    }
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airUnBuiltinCall(
    f: *Function,
    inst: Air.Inst.Index,
    operand_ref: Air.Inst.Ref,
    operation: []const u8,
    info: BuiltinInfo,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;

    const operand = try f.resolveInst(operand_ref);
    try reap(f, inst, &.{operand_ref});
    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const operand_ty = f.typeOf(operand_ref);
    const scalar_ty = operand_ty.scalarType(zcu);

    const ref_ret = lowersToBigInt(inst_scalar_ty, zcu);
    const ref_arg = lowersToBigInt(scalar_ty, zcu);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    if (!ref_ret) {
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(" = ");
    }
    try w.print("zig_{s}_", .{operation});
    try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
    try w.writeByte('(');
    if (ref_ret) {
        try w.writeByte('&');
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(", ");
    }
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, operand, .other);
    try v.elem(f, w);
    try f.dg.renderBuiltinInfo(w, scalar_ty, info);
    try w.writeAll(");");
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airBinBuiltinCall(
    f: *Function,
    inst: Air.Inst.Index,
    operation: []const u8,
    info: BuiltinInfo,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const operand_ty = f.typeOf(bin_op.lhs);
    const is_big = lowersToBigInt(operand_ty, zcu);

    const lhs = try f.resolveInst(bin_op.lhs);
    const rhs = try f.resolveInst(bin_op.rhs);
    if (!is_big) try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const scalar_ty = operand_ty.scalarType(zcu);

    const ref_ret = lowersToBigInt(inst_scalar_ty, zcu);
    const ref_arg = lowersToBigInt(scalar_ty, zcu);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    if (is_big) try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
    const v = try Vectorize.start(f, inst, w, operand_ty);
    if (!ref_ret) {
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(" = ");
    }
    try w.print("zig_{s}_", .{operation});
    try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
    try w.writeByte('(');
    if (ref_ret) {
        try w.writeByte('&');
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(", ");
    }
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeAll(", ");
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, rhs, .other);
    if (f.typeOf(bin_op.rhs).isVector(zcu)) try v.elem(f, w);
    try f.dg.renderBuiltinInfo(w, scalar_ty, info);
    try w.writeAll(");\n");
    try v.end(f, inst, w);

    return local;
}

fn airCmpBuiltinCall(
    f: *Function,
    inst: Air.Inst.Index,
    data: anytype,
    operator: std.math.CompareOperator,
    operation: enum { cmp, operator },
    info: BuiltinInfo,
) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const lhs = try f.resolveInst(data.lhs);
    const rhs = try f.resolveInst(data.rhs);
    try reap(f, inst, &.{ data.lhs, data.rhs });

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    const operand_ty = f.typeOf(data.lhs);
    const scalar_ty = operand_ty.scalarType(zcu);

    const ref_ret = lowersToBigInt(inst_scalar_ty, zcu);
    const ref_arg = lowersToBigInt(scalar_ty, zcu);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, operand_ty);
    if (!ref_ret) {
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(" = ");
    }
    try w.print("zig_{s}_", .{switch (operation) {
        else => @tagName(operation),
        .operator => compareOperatorAbbrev(operator),
    }});
    try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
    try w.writeByte('(');
    if (ref_ret) {
        try w.writeByte('&');
        try f.writeCValue(w, local, .other);
        try v.elem(f, w);
        try w.writeAll(", ");
    }
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeAll(", ");
    if (ref_arg) try w.writeByte('&');
    try f.writeCValue(w, rhs, .other);
    try v.elem(f, w);
    try f.dg.renderBuiltinInfo(w, scalar_ty, info);
    try w.writeByte(')');
    if (!ref_ret) try w.print("{s}{f}", .{
        compareOperatorC(operator),
        try f.fmtIntLiteralDec(try pt.intValue(.i32, 0)),
    });
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airCmpxchg(f: *Function, inst: Air.Inst.Index, flavor: [*:0]const u8) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = f.air.extraData(Air.Cmpxchg, ty_pl.payload).data;
    const inst_ty = f.typeOfIndex(inst);
    const ptr = try f.resolveInst(extra.ptr);
    const expected_value = try f.resolveInst(extra.expected_value);
    const new_value = try f.resolveInst(extra.new_value);
    const ptr_ty = f.typeOf(extra.ptr);
    const ty = ptr_ty.childType(zcu);

    const w = &f.code.writer;
    const new_value_mat = try Materialize.start(f, inst, ty, new_value);
    try reap(f, inst, &.{ extra.ptr, extra.expected_value, extra.new_value });

    const repr_ty = if (ty.isRuntimeFloat())
        pt.intType(.unsigned, @as(u16, @intCast(ty.abiSize(zcu) * 8))) catch unreachable
    else
        ty;

    const local = try f.allocLocal(inst, inst_ty);
    if (inst_ty.isPtrLikeOptional(zcu)) {
        try f.writeCValue(w, local, .other);
        try w.writeAll(" = ");
        try f.writeCValue(w, expected_value, .other);
        try w.writeByte(';');
        try f.newline();

        try w.writeAll("if (");
        try w.print("zig_cmpxchg_{s}((zig_atomic(", .{flavor});
        try f.renderType(w, ty);
        try w.writeByte(')');
        if (ptr_ty.isVolatilePtr(zcu)) try w.writeAll(" volatile");
        try w.writeAll(" *)");
        try f.writeCValue(w, ptr, .other);
        try w.writeAll(", ");
        try f.writeCValue(w, local, .other);
        try w.writeAll(", ");
        try new_value_mat.mat(f, w);
        try w.writeAll(", ");
        try writeMemoryOrder(w, extra.successOrder());
        try w.writeAll(", ");
        try writeMemoryOrder(w, extra.failureOrder());
        try w.writeAll(", ");
        try f.dg.renderTypeForBuiltinFnName(w, ty);
        try w.writeAll(", ");
        try f.renderType(w, repr_ty);
        try w.writeByte(')');
        try w.writeAll(") {");
        f.indent();
        try f.newline();

        try f.writeCValue(w, local, .other);
        try w.writeAll(" = NULL;");
        try f.newline();

        try f.outdent();
        try w.writeByte('}');
        try f.newline();
    } else {
        try f.writeCValueMember(w, local, .{ .identifier = "payload" });
        try w.writeAll(" = ");
        try f.writeCValue(w, expected_value, .other);
        try w.writeByte(';');
        try f.newline();

        try f.writeCValueMember(w, local, .{ .identifier = "is_null" });
        try w.print(" = zig_cmpxchg_{s}((zig_atomic(", .{flavor});
        try f.renderType(w, ty);
        try w.writeByte(')');
        if (ptr_ty.isVolatilePtr(zcu)) try w.writeAll(" volatile");
        try w.writeAll(" *)");
        try f.writeCValue(w, ptr, .other);
        try w.writeAll(", ");
        try f.writeCValueMember(w, local, .{ .identifier = "payload" });
        try w.writeAll(", ");
        try new_value_mat.mat(f, w);
        try w.writeAll(", ");
        try writeMemoryOrder(w, extra.successOrder());
        try w.writeAll(", ");
        try writeMemoryOrder(w, extra.failureOrder());
        try w.writeAll(", ");
        try f.dg.renderTypeForBuiltinFnName(w, ty);
        try w.writeAll(", ");
        try f.renderType(w, repr_ty);
        try w.writeAll(");");
        try f.newline();
    }
    try new_value_mat.end(f, inst);

    if (f.liveness.isUnused(inst)) {
        try freeLocal(f, inst, local.new_local, null);
        return .none;
    }

    return local;
}

fn airAtomicRmw(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const pl_op = f.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = f.air.extraData(Air.AtomicRmw, pl_op.payload).data;
    const inst_ty = f.typeOfIndex(inst);
    const ptr_ty = f.typeOf(pl_op.operand);
    const ty = ptr_ty.childType(zcu);
    const ptr = try f.resolveInst(pl_op.operand);
    const operand = try f.resolveInst(extra.operand);

    const w = &f.code.writer;
    const operand_mat = try Materialize.start(f, inst, ty, operand);
    try reap(f, inst, &.{ pl_op.operand, extra.operand });

    const repr_bits: u16 = @intCast(ty.abiSize(zcu) * 8);
    const is_float = ty.isRuntimeFloat();
    const is_128 = repr_bits == 128;
    const repr_ty = if (is_float) pt.intType(.unsigned, repr_bits) catch unreachable else ty;

    const local = try f.allocLocal(inst, inst_ty);
    try w.print("zig_atomicrmw_{s}", .{toAtomicRmwSuffix(extra.op())});
    if (is_float) try w.writeAll("_float") else if (is_128) try w.writeAll("_int128");
    try w.writeByte('(');
    try f.writeCValue(w, local, .other);
    try w.writeAll(", (");
    const use_atomic = switch (extra.op()) {
        else => true,
        // These are missing from stdatomic.h, so no atomic types unless a fallback is used.
        .Nand, .Min, .Max => is_float or is_128,
    };
    if (use_atomic) try w.writeAll("zig_atomic(");
    try f.renderType(w, ty);
    if (use_atomic) try w.writeByte(')');
    if (ptr_ty.isVolatilePtr(zcu)) try w.writeAll(" volatile");
    try w.writeAll(" *)");
    try f.writeCValue(w, ptr, .other);
    try w.writeAll(", ");
    try operand_mat.mat(f, w);
    try w.writeAll(", ");
    try writeMemoryOrder(w, extra.ordering());
    try w.writeAll(", ");
    try f.dg.renderTypeForBuiltinFnName(w, ty);
    try w.writeAll(", ");
    try f.renderType(w, repr_ty);
    try w.writeAll(");");
    try f.newline();
    try operand_mat.end(f, inst);

    if (f.liveness.isUnused(inst)) {
        try freeLocal(f, inst, local.new_local, null);
        return .none;
    }

    return local;
}

fn airAtomicLoad(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const atomic_load = f.air.instructions.items(.data)[@intFromEnum(inst)].atomic_load;
    const ptr = try f.resolveInst(atomic_load.ptr);
    try reap(f, inst, &.{atomic_load.ptr});
    const ptr_ty = f.typeOf(atomic_load.ptr);
    const ty = ptr_ty.childType(zcu);

    const repr_ty = if (ty.isRuntimeFloat())
        pt.intType(.unsigned, @as(u16, @intCast(ty.abiSize(zcu) * 8))) catch unreachable
    else
        ty;

    const inst_ty = f.typeOfIndex(inst);
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);

    try w.writeAll("zig_atomic_load(");
    try f.writeCValue(w, local, .other);
    try w.writeAll(", (zig_atomic(");
    try f.renderType(w, ty);
    try w.writeByte(')');
    if (ptr_ty.isVolatilePtr(zcu)) try w.writeAll(" volatile");
    try w.writeAll(" *)");
    try f.writeCValue(w, ptr, .other);
    try w.writeAll(", ");
    try writeMemoryOrder(w, atomic_load.order);
    try w.writeAll(", ");
    try f.dg.renderTypeForBuiltinFnName(w, ty);
    try w.writeAll(", ");
    try f.renderType(w, repr_ty);
    try w.writeAll(");");
    try f.newline();

    return local;
}

fn airAtomicStore(f: *Function, inst: Air.Inst.Index, order: [*:0]const u8) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const ptr_ty = f.typeOf(bin_op.lhs);
    const ty = ptr_ty.childType(zcu);
    const ptr = try f.resolveInst(bin_op.lhs);
    const element = try f.resolveInst(bin_op.rhs);

    const w = &f.code.writer;
    const element_mat = try Materialize.start(f, inst, ty, element);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const repr_ty = if (ty.isRuntimeFloat())
        pt.intType(.unsigned, @as(u16, @intCast(ty.abiSize(zcu) * 8))) catch unreachable
    else
        ty;

    try w.writeAll("zig_atomic_store((zig_atomic(");
    try f.renderType(w, ty);
    try w.writeByte(')');
    if (ptr_ty.isVolatilePtr(zcu)) try w.writeAll(" volatile");
    try w.writeAll(" *)");
    try f.writeCValue(w, ptr, .other);
    try w.writeAll(", ");
    try element_mat.mat(f, w);
    try w.print(", {s}, ", .{order});
    try f.dg.renderTypeForBuiltinFnName(w, ty);
    try w.writeAll(", ");
    try f.renderType(w, repr_ty);
    try w.writeAll(");");
    try f.newline();
    try element_mat.end(f, inst);

    return .none;
}

fn airMemset(f: *Function, inst: Air.Inst.Index, safety: bool) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_ty = f.typeOf(bin_op.lhs);
    const dest_slice = try f.resolveInst(bin_op.lhs);
    const value = try f.resolveInst(bin_op.rhs);
    const elem_ty = f.typeOf(bin_op.rhs);
    const elem_abi_size = elem_ty.abiSize(zcu);
    const val_is_undef = if (bin_op.rhs.toInterned()) |ip_index| Value.fromInterned(ip_index).isUndef(zcu) else false;
    const w = &f.code.writer;

    if (val_is_undef) {
        if (!safety) {
            try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
            return .none;
        }

        try w.writeAll("memset(");
        switch (dest_ty.ptrSize(zcu)) {
            .slice => {
                try f.writeCValueMember(w, dest_slice, .{ .identifier = "ptr" });
                try w.writeAll(", 0xaa, ");
                try f.writeCValueMember(w, dest_slice, .{ .identifier = "len" });
            },
            .one => {
                try f.writeCValue(w, dest_slice, .other);
                try w.print(", 0xaa, {d}", .{dest_ty.childType(zcu).arrayLen(zcu)});
            },
            .many, .c => unreachable,
        }
        if (elem_abi_size > 0) try w.print(" * {d}", .{elem_abi_size});
        try w.writeAll(");");
        try f.newline();
        try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
        return .none;
    }

    if (elem_abi_size == 1 and !dest_ty.isVolatilePtr(zcu)) {
        const bitcasted = try bitcast(f, .u8, value, elem_ty);
        try w.writeAll("memset(");
        switch (dest_ty.ptrSize(zcu)) {
            .slice => {
                try f.writeCValueMember(w, dest_slice, .{ .identifier = "ptr" });
                try w.writeAll(", ");
                try f.writeCValue(w, bitcasted, .other);
                try w.writeAll(", ");
                try f.writeCValueMember(w, dest_slice, .{ .identifier = "len" });
            },
            .one => {
                try f.writeCValue(w, dest_slice, .other);
                try w.writeAll(", ");
                try f.writeCValue(w, bitcasted, .other);
                try w.print(", {d}", .{dest_ty.childType(zcu).arrayLen(zcu)});
            },
            .many, .c => unreachable,
        }
        try w.writeAll(");");
        try f.newline();
        try f.freeCValue(inst, bitcasted);
        try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
        return .none;
    }

    // Fallback path: use a `for` loop.

    const index = try f.allocLocal(inst, .usize);

    try w.writeAll("for (");
    try f.writeCValue(w, index, .other);
    try w.writeAll(" = ");
    try f.dg.renderValue(w, .zero_usize, .other);
    try w.writeAll("; ");
    try f.writeCValue(w, index, .other);
    try w.writeAll(" != ");
    switch (dest_ty.ptrSize(zcu)) {
        .slice => try f.writeCValueMember(w, dest_slice, .{ .identifier = "len" }),
        .one => try w.print("{d}", .{dest_ty.childType(zcu).arrayLen(zcu)}),
        .many, .c => unreachable,
    }
    try w.writeAll("; ++");
    try f.writeCValue(w, index, .other);
    try w.writeAll(") ");

    switch (dest_ty.ptrSize(zcu)) {
        .slice => try f.writeCValueMember(w, dest_slice, .{ .identifier = "ptr" }),
        .one => try f.writeCValueDerefMember(w, dest_slice, .{ .identifier = "array" }),
        .many, .c => unreachable,
    }
    try w.writeByte('[');
    try f.writeCValue(w, index, .other);
    try w.writeAll("] = ");
    try f.writeCValue(w, value, .other);
    try w.writeByte(';');
    try f.newline();

    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
    try freeLocal(f, inst, index.new_local, null);

    return .none;
}

fn airMemcpy(f: *Function, inst: Air.Inst.Index, function_paren: []const u8) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_ptr = try f.resolveInst(bin_op.lhs);
    const src_ptr = try f.resolveInst(bin_op.rhs);
    const dest_ty = f.typeOf(bin_op.lhs);
    const src_ty = f.typeOf(bin_op.rhs);
    const w = &f.code.writer;

    if (dest_ty.ptrSize(zcu) != .one) {
        try w.writeAll("if (");
        try f.writeCValueMember(w, dest_ptr, .{ .identifier = "len" });
        try w.writeAll(" != 0) ");
    }
    try w.writeAll(function_paren);
    switch (dest_ty.ptrSize(zcu)) {
        .slice => try f.writeCValueMember(w, dest_ptr, .{ .identifier = "ptr" }),
        .one => try f.writeCValueDerefMember(w, dest_ptr, .{ .identifier = "array" }),
        .many, .c => unreachable,
    }
    try w.writeAll(", ");
    switch (src_ty.ptrSize(zcu)) {
        .slice => try f.writeCValueMember(w, src_ptr, .{ .identifier = "ptr" }),
        .one => try f.writeCValueDerefMember(w, src_ptr, .{ .identifier = "array" }),
        .many, .c => try f.writeCValue(w, src_ptr, .other),
    }
    try w.writeAll(", ");
    switch (dest_ty.ptrSize(zcu)) {
        .slice => try f.writeCValueMember(w, dest_ptr, .{ .identifier = "len" }),
        .one => try w.print("{d}", .{dest_ty.childType(zcu).arrayLen(zcu)}),
        .many, .c => unreachable,
    }
    try w.writeAll(" * sizeof(");
    try f.renderType(w, dest_ty.indexableElem(zcu));
    try w.writeAll("));");
    try f.newline();

    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });
    return .none;
}

fn airSetUnionTag(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const bin_op = f.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const union_ptr = try f.resolveInst(bin_op.lhs);
    const new_tag = try f.resolveInst(bin_op.rhs);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs });

    const union_ty = f.typeOf(bin_op.lhs).childType(zcu);
    const layout = union_ty.unionGetLayout(zcu);
    if (layout.tag_size == 0) return .none;

    const w = &f.code.writer;
    try f.writeCValueDerefMember(w, union_ptr, .{ .identifier = "tag" });
    try w.writeAll(" = ");
    try f.writeCValue(w, new_tag, .other);
    try w.writeByte(';');
    try f.newline();
    return .none;
}

fn airGetUnionTag(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const union_ty = f.typeOf(ty_op.operand);
    const layout = union_ty.unionGetLayout(zcu);
    if (layout.tag_size == 0) return .none;

    const inst_ty = f.typeOfIndex(inst);
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try f.writeCValueMember(w, operand, .{ .identifier = "tag" });
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airTagName(f: *Function, inst: Air.Inst.Index) !CValue {
    const zcu = f.dg.pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.comp.gpa;
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;

    const inst_ty = f.typeOfIndex(inst);
    const enum_ty = f.typeOf(un_op);
    const operand = try f.resolveInst(un_op);
    try reap(f, inst, &.{un_op});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try f.need_tag_name_funcs.put(gpa, enum_ty.toIntern(), {});
    try w.print(" = zig_tagName_{f}__{d}(", .{
        fmtIdentUnsolo(enum_ty.containerTypeName(ip).toSlice(ip)),
        @intFromEnum(enum_ty.toIntern()),
    });
    try f.writeCValue(w, operand, .other);
    try w.writeAll(");");
    try f.newline();

    return local;
}

fn airErrorName(f: *Function, inst: Air.Inst.Index) !CValue {
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;

    const w = &f.code.writer;
    const inst_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(un_op);
    try reap(f, inst, &.{un_op});
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);

    try w.writeAll(" = zig_errorName[");
    try f.writeCValue(w, operand, .other);
    try w.writeAll(" - 1];");
    try f.newline();
    return local;
}

fn airSplat(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const inst_ty = f.typeOfIndex(inst);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, inst_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    try f.writeCValue(w, operand, .other);
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airSelect(f: *Function, inst: Air.Inst.Index) !CValue {
    const pl_op = f.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = f.air.extraData(Air.Bin, pl_op.payload).data;

    const pred = try f.resolveInst(pl_op.operand);
    const lhs = try f.resolveInst(extra.lhs);
    const rhs = try f.resolveInst(extra.rhs);
    try reap(f, inst, &.{ pl_op.operand, extra.lhs, extra.rhs });

    const inst_ty = f.typeOfIndex(inst);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, inst_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = ");
    try f.writeCValue(w, pred, .other);
    try v.elem(f, w);
    try w.writeAll(" ? ");
    try f.writeCValue(w, lhs, .other);
    try v.elem(f, w);
    try w.writeAll(" : ");
    try f.writeCValue(w, rhs, .other);
    try v.elem(f, w);
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airShuffleOne(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;

    const unwrapped = f.air.unwrapShuffleOne(zcu, inst);
    const mask = unwrapped.mask;
    const operand = try f.resolveInst(unwrapped.operand);
    const inst_ty = unwrapped.result_ty;

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try reap(f, inst, &.{unwrapped.operand}); // local cannot alias operand
    for (mask, 0..) |mask_elem, out_idx| {
        try f.writeCValueMember(w, local, .{ .identifier = "array" });
        try w.writeByte('[');
        try f.dg.renderValue(w, try pt.intValue(.usize, out_idx), .other);
        try w.writeAll("] = ");
        switch (mask_elem.unwrap()) {
            .elem => |src_idx| {
                try f.writeCValueMember(w, operand, .{ .identifier = "array" });
                try w.writeByte('[');
                try f.dg.renderValue(w, try pt.intValue(.usize, src_idx), .other);
                try w.writeByte(']');
            },
            .value => |val| try f.dg.renderValue(w, .fromInterned(val), .other),
        }
        try w.writeAll(";\n");
    }

    return local;
}

fn airShuffleTwo(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;

    const unwrapped = f.air.unwrapShuffleTwo(zcu, inst);
    const mask = unwrapped.mask;
    const operand_a = try f.resolveInst(unwrapped.operand_a);
    const operand_b = try f.resolveInst(unwrapped.operand_b);
    const inst_ty = unwrapped.result_ty;
    const elem_ty = inst_ty.childType(zcu);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try reap(f, inst, &.{ unwrapped.operand_a, unwrapped.operand_b }); // local cannot alias operands
    for (mask, 0..) |mask_elem, out_idx| {
        try f.writeCValueMember(w, local, .{ .identifier = "array" });
        try w.writeByte('[');
        try f.dg.renderValue(w, try pt.intValue(.usize, out_idx), .other);
        try w.writeAll("] = ");
        switch (mask_elem.unwrap()) {
            .a_elem => |src_idx| {
                try f.writeCValueMember(w, operand_a, .{ .identifier = "array" });
                try w.writeByte('[');
                try f.dg.renderValue(w, try pt.intValue(.usize, src_idx), .other);
                try w.writeByte(']');
            },
            .b_elem => |src_idx| {
                try f.writeCValueMember(w, operand_b, .{ .identifier = "array" });
                try w.writeByte('[');
                try f.dg.renderValue(w, try pt.intValue(.usize, src_idx), .other);
                try w.writeByte(']');
            },
            .undef => try f.dg.renderUndefValue(w, elem_ty, .other),
        }
        try w.writeByte(';');
        try f.newline();
    }

    return local;
}

fn airReduce(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const reduce = f.air.instructions.items(.data)[@intFromEnum(inst)].reduce;

    const scalar_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(reduce.operand);
    try reap(f, inst, &.{reduce.operand});
    const operand_ty = f.typeOf(reduce.operand);
    const w = &f.code.writer;

    const use_operator = scalar_ty.bitSize(zcu) <= 64;
    const op: union(enum) {
        const Func = struct { operation: []const u8, info: BuiltinInfo = .none };
        builtin: Func,
        infix: []const u8,
        ternary: []const u8,
    } = switch (reduce.operation) {
        .And => if (use_operator) .{ .infix = " &= " } else .{ .builtin = .{ .operation = "and" } },
        .Or => if (use_operator) .{ .infix = " |= " } else .{ .builtin = .{ .operation = "or" } },
        .Xor => if (use_operator) .{ .infix = " ^= " } else .{ .builtin = .{ .operation = "xor" } },
        .Min => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => if (use_operator) .{ .ternary = " < " } else .{ .builtin = .{ .operation = "min" } },
            .float => .{ .builtin = .{ .operation = "min" } },
            else => unreachable,
        },
        .Max => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => if (use_operator) .{ .ternary = " > " } else .{ .builtin = .{ .operation = "max" } },
            .float => .{ .builtin = .{ .operation = "max" } },
            else => unreachable,
        },
        .Add => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => if (use_operator) .{ .infix = " += " } else .{ .builtin = .{ .operation = "addw", .info = .bits } },
            .float => .{ .builtin = .{ .operation = "add" } },
            else => unreachable,
        },
        .Mul => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => if (use_operator) .{ .infix = " *= " } else .{ .builtin = .{ .operation = "mulw", .info = .bits } },
            .float => .{ .builtin = .{ .operation = "mul" } },
            else => unreachable,
        },
    };

    // Reduce a vector by repeatedly applying a function to produce an
    // accumulated result.
    //
    // Equivalent to:
    //   reduce: {
    //     var accum: T = init;
    //     for (vec) |elem| {
    //       accum = func(accum, elem);
    //     }
    //     break :reduce accum;
    //   }

    const accum = try f.allocLocal(inst, scalar_ty);
    try f.writeCValue(w, accum, .other);
    try w.writeAll(" = ");

    try f.dg.renderValue(w, switch (reduce.operation) {
        .Or, .Xor => switch (scalar_ty.zigTypeTag(zcu)) {
            .bool => Value.false,
            .int => try pt.intValue(scalar_ty, 0),
            else => unreachable,
        },
        .And => switch (scalar_ty.zigTypeTag(zcu)) {
            .bool => Value.true,
            .int => switch (scalar_ty.intInfo(zcu).signedness) {
                .unsigned => try scalar_ty.maxIntScalar(pt, scalar_ty),
                .signed => try pt.intValue(scalar_ty, -1),
            },
            else => unreachable,
        },
        .Add => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => try pt.intValue(scalar_ty, 0),
            .float => try pt.floatValue(scalar_ty, 0.0),
            else => unreachable,
        },
        .Mul => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => try pt.intValue(scalar_ty, 1),
            .float => try pt.floatValue(scalar_ty, 1.0),
            else => unreachable,
        },
        .Min => switch (scalar_ty.zigTypeTag(zcu)) {
            .bool => Value.true,
            .int => try scalar_ty.maxIntScalar(pt, scalar_ty),
            .float => try pt.floatValue(scalar_ty, std.math.nan(f128)),
            else => unreachable,
        },
        .Max => switch (scalar_ty.zigTypeTag(zcu)) {
            .bool => Value.false,
            .int => try scalar_ty.minIntScalar(pt, scalar_ty),
            .float => try pt.floatValue(scalar_ty, std.math.nan(f128)),
            else => unreachable,
        },
    }, .other);
    try w.writeByte(';');
    try f.newline();

    const v = try Vectorize.start(f, inst, w, operand_ty);
    try f.writeCValue(w, accum, .other);
    switch (op) {
        .builtin => |func| {
            try w.print(" = zig_{s}_", .{func.operation});
            try f.dg.renderTypeForBuiltinFnName(w, scalar_ty);
            try w.writeByte('(');
            try f.writeCValue(w, accum, .other);
            try w.writeAll(", ");
            try f.writeCValue(w, operand, .other);
            try v.elem(f, w);
            try f.dg.renderBuiltinInfo(w, scalar_ty, func.info);
            try w.writeByte(')');
        },
        .infix => |ass| {
            try w.writeAll(ass);
            try f.writeCValue(w, operand, .other);
            try v.elem(f, w);
        },
        .ternary => |cmp| {
            try w.writeAll(" = ");
            try f.writeCValue(w, accum, .other);
            try w.writeAll(cmp);
            try f.writeCValue(w, operand, .other);
            try v.elem(f, w);
            try w.writeAll(" ? ");
            try f.writeCValue(w, accum, .other);
            try w.writeAll(" : ");
            try f.writeCValue(w, operand, .other);
            try v.elem(f, w);
        },
    }
    try w.writeByte(';');
    try f.newline();
    try v.end(f, inst, w);

    return accum;
}

fn airAggregateInit(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const inst_ty = f.typeOfIndex(inst);
    const len: usize = @intCast(inst_ty.arrayLen(zcu));
    const elements: []const Air.Inst.Ref = @ptrCast(f.air.extra.items[ty_pl.payload..][0..len]);
    const gpa = f.dg.gpa;
    const resolved_elements = try gpa.alloc(CValue, elements.len);
    defer gpa.free(resolved_elements);
    for (resolved_elements, elements) |*resolved_element, element| {
        resolved_element.* = try f.resolveInst(element);
    }
    {
        var bt = iterateBigTomb(f, inst);
        for (elements) |element| {
            try bt.feed(element);
        }
    }

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    switch (ip.indexToKey(inst_ty.toIntern())) {
        inline .array_type, .vector_type => |info, tag| {
            for (resolved_elements, 0..) |element, i| {
                try f.writeCValueMember(w, local, .{ .identifier = "array" });
                try w.print("[{d}] = ", .{i});
                try f.writeCValue(w, element, .other);
                try w.writeByte(';');
                try f.newline();
            }
            if (tag == .array_type and info.sentinel != .none) {
                try f.writeCValueMember(w, local, .{ .identifier = "array" });
                try w.print("[{d}] = ", .{info.len});
                try f.dg.renderValue(w, Value.fromInterned(info.sentinel), .other);
                try w.writeByte(';');
                try f.newline();
            }
        },
        .struct_type => {
            const loaded_struct = ip.loadStructType(inst_ty.toIntern());
            switch (loaded_struct.layout) {
                .auto, .@"extern" => {
                    var field_it = loaded_struct.iterateRuntimeOrder(ip);
                    while (field_it.next()) |field_index| {
                        const field_ty: Type = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                        if (!field_ty.hasRuntimeBits(zcu)) continue;

                        try f.writeCValueMember(w, local, .{ .identifier = loaded_struct.field_names.get(ip)[field_index].toSlice(ip) });
                        try w.writeAll(" = ");
                        try f.writeCValue(w, resolved_elements[field_index], .other);
                        try w.writeByte(';');
                        try f.newline();
                    }
                },
                .@"packed" => unreachable, // `Air.Legalize.Feature.expand_packed_struct_init` handles this case
            }
        },
        .tuple_type => |tuple_info| for (0..tuple_info.types.len) |field_index| {
            if (tuple_info.values.get(ip)[field_index] != .none) continue;
            const field_ty: Type = .fromInterned(tuple_info.types.get(ip)[field_index]);
            if (!field_ty.hasRuntimeBits(zcu)) continue;

            try f.writeCValueMember(w, local, .{ .field = field_index });
            try w.writeAll(" = ");
            try f.writeCValue(w, resolved_elements[field_index], .other);
            try w.writeByte(';');
            try f.newline();
        },
        else => unreachable,
    }

    return local;
}

fn airUnionInit(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const ty_pl = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = f.air.extraData(Air.UnionInit, ty_pl.payload).data;
    const field_index = extra.field_index;

    const union_ty = f.typeOfIndex(inst);
    const loaded_union = ip.loadUnionType(union_ty.toIntern());
    const loaded_enum = ip.loadEnumType(loaded_union.enum_tag_type);

    const payload = try f.resolveInst(extra.init);
    try reap(f, inst, &.{extra.init});

    const w = &f.code.writer;
    if (loaded_union.layout == .@"packed") return f.moveCValue(inst, union_ty, payload);

    const local = try f.allocLocal(inst, union_ty);

    if (loaded_union.has_runtime_tag) {
        try f.writeCValueMember(w, local, .{ .identifier = "tag" });
        if (loaded_enum.field_values.len == 0) {
            // auto-numbered
            try w.print(" = {d};", .{field_index});
        } else {
            const tag_int_val: Value = .fromInterned(loaded_enum.field_values.get(ip)[field_index]);
            try w.print(" = {f};", .{try f.fmtIntLiteralDec(tag_int_val)});
        }
        try f.newline();
    }

    const field_name_slice = loaded_enum.field_names.get(ip)[field_index].toSlice(ip);
    switch (loaded_union.layout) {
        .auto => try f.writeCValueMember(w, local, .{ .payload_identifier = field_name_slice }),
        .@"extern" => try f.writeCValueMember(w, local, .{ .identifier = field_name_slice }),
        .@"packed" => unreachable,
    }
    try w.writeAll(" = ");
    try f.writeCValue(w, payload, .other);
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airPrefetch(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const prefetch = f.air.instructions.items(.data)[@intFromEnum(inst)].prefetch;

    const ptr_ty = f.typeOf(prefetch.ptr);
    const ptr = try f.resolveInst(prefetch.ptr);
    try reap(f, inst, &.{prefetch.ptr});

    const w = &f.code.writer;
    switch (prefetch.cache) {
        .data => {
            try w.writeAll("zig_prefetch(");
            if (ptr_ty.isSlice(zcu))
                try f.writeCValueMember(w, ptr, .{ .identifier = "ptr" })
            else
                try f.writeCValue(w, ptr, .other);
            try w.print(", {d}, {d});", .{ @intFromEnum(prefetch.rw), prefetch.locality });
            try f.newline();
        },
        // The available prefetch intrinsics do not accept a cache argument; only
        // address, rw, and locality.
        .instruction => {},
    }

    return .none;
}

fn airWasmMemorySize(f: *Function, inst: Air.Inst.Index) !CValue {
    const pl_op = f.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;

    const w = &f.code.writer;
    const inst_ty = f.typeOfIndex(inst);
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);

    try w.writeAll(" = ");
    try w.print("zig_wasm_memory_size({d});", .{pl_op.payload});
    try f.newline();

    return local;
}

fn airWasmMemoryGrow(f: *Function, inst: Air.Inst.Index) !CValue {
    const pl_op = f.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;

    const w = &f.code.writer;
    const inst_ty = f.typeOfIndex(inst);
    const operand = try f.resolveInst(pl_op.operand);
    try reap(f, inst, &.{pl_op.operand});
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);

    try w.writeAll(" = ");
    try w.print("zig_wasm_memory_grow({d}, ", .{pl_op.payload});
    try f.writeCValue(w, operand, .other);
    try w.writeAll(");");
    try f.newline();
    return local;
}

fn airMulAdd(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const pl_op = f.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const bin_op = f.air.extraData(Air.Bin, pl_op.payload).data;

    const mulend1 = try f.resolveInst(bin_op.lhs);
    const mulend2 = try f.resolveInst(bin_op.rhs);
    const addend = try f.resolveInst(pl_op.operand);
    try reap(f, inst, &.{ bin_op.lhs, bin_op.rhs, pl_op.operand });

    const inst_ty = f.typeOfIndex(inst);
    const inst_scalar_ty = inst_ty.scalarType(zcu);

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    const v = try Vectorize.start(f, inst, w, inst_ty);
    try f.writeCValue(w, local, .other);
    try v.elem(f, w);
    try w.writeAll(" = zig_fma_");
    try f.dg.renderTypeForBuiltinFnName(w, inst_scalar_ty);
    try w.writeByte('(');
    try f.writeCValue(w, mulend1, .other);
    try v.elem(f, w);
    try w.writeAll(", ");
    try f.writeCValue(w, mulend2, .other);
    try v.elem(f, w);
    try w.writeAll(", ");
    try f.writeCValue(w, addend, .other);
    try v.elem(f, w);
    try w.writeAll(");");
    try f.newline();
    try v.end(f, inst, w);

    return local;
}

fn airRuntimeNavPtr(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_nav = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_nav;
    const w = &f.code.writer;
    const local = try f.allocLocal(inst, .fromInterned(ty_nav.ty));
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = ");
    try f.dg.renderNav(w, ty_nav.nav, .other);
    try w.writeByte(';');
    try f.newline();
    return local;
}

fn airCVaStart(f: *Function, inst: Air.Inst.Index) !CValue {
    const pt = f.dg.pt;
    const zcu = pt.zcu;
    const inst_ty = f.typeOfIndex(inst);

    assert(Value.fromInterned(f.func_index).typeOf(zcu).fnIsVarArgs(zcu));

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try w.writeAll("va_start(*(va_list *)&");
    try f.writeCValue(w, local, .other);
    if (f.next_arg_index > 0) {
        try w.writeAll(", ");
        try f.writeCValue(w, .{ .arg = f.next_arg_index - 1 }, .other);
    }
    try w.writeAll(");");
    try f.newline();
    return local;
}

fn airCVaArg(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const va_list = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try f.writeCValue(w, local, .other);
    try w.writeAll(" = va_arg(*(va_list *)");
    try f.writeCValue(w, va_list, .other);
    try w.writeAll(", ");
    try f.renderType(w, ty_op.ty.toType());
    try w.writeAll(");");
    try f.newline();
    return local;
}

fn airCVaEnd(f: *Function, inst: Air.Inst.Index) !CValue {
    const un_op = f.air.instructions.items(.data)[@intFromEnum(inst)].un_op;

    const va_list = try f.resolveInst(un_op);
    try reap(f, inst, &.{un_op});

    const w = &f.code.writer;
    try w.writeAll("va_end(*(va_list *)");
    try f.writeCValue(w, va_list, .other);
    try w.writeAll(");");
    try f.newline();
    return .none;
}

fn airCVaCopy(f: *Function, inst: Air.Inst.Index) !CValue {
    const ty_op = f.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const inst_ty = f.typeOfIndex(inst);
    const va_list = try f.resolveInst(ty_op.operand);
    try reap(f, inst, &.{ty_op.operand});

    const w = &f.code.writer;
    const local = try f.allocLocal(inst, inst_ty);
    try w.writeAll("va_copy(*(va_list *)&");
    try f.writeCValue(w, local, .other);
    try w.writeAll(", *(va_list *)");
    try f.writeCValue(w, va_list, .other);
    try w.writeAll(");");
    try f.newline();
    return local;
}

fn toMemoryOrder(order: std.builtin.AtomicOrder) [:0]const u8 {
    return switch (order) {
        // Note: unordered is actually even less atomic than relaxed
        .unordered, .monotonic => "zig_memory_order_relaxed",
        .acquire => "zig_memory_order_acquire",
        .release => "zig_memory_order_release",
        .acq_rel => "zig_memory_order_acq_rel",
        .seq_cst => "zig_memory_order_seq_cst",
    };
}

fn writeMemoryOrder(w: *Writer, order: std.builtin.AtomicOrder) !void {
    return w.writeAll(toMemoryOrder(order));
}

fn toCallingConvention(cc: std.builtin.CallingConvention, zcu: *Zcu) ?[]const u8 {
    if (zcu.getTarget().cCallingConvention()) |ccc| {
        if (cc.eql(ccc)) {
            return null;
        }
    }
    return switch (cc) {
        .auto, .naked => null,

        .x86_16_cdecl => "cdecl",
        .x86_16_regparmcall => "regparmcall",
        .x86_64_sysv, .x86_sysv => "sysv_abi",
        .x86_64_win, .x86_win => "ms_abi",
        .x86_16_stdcall, .x86_stdcall => "stdcall",
        .x86_fastcall => "fastcall",
        .x86_thiscall => "thiscall",

        .x86_vectorcall,
        .x86_64_vectorcall,
        => "vectorcall",

        .x86_64_regcall_v3_sysv,
        .x86_64_regcall_v4_win,
        .x86_regcall_v3,
        .x86_regcall_v4_win,
        => "regcall",

        .aarch64_vfabi => "aarch64_vector_pcs",
        .aarch64_vfabi_sve => "aarch64_sve_pcs",

        .arm_aapcs => "pcs(\"aapcs\")",
        .arm_aapcs_vfp => "pcs(\"aapcs-vfp\")",

        .arc_interrupt => |opts| switch (opts.type) {
            inline else => |t| "interrupt(\"" ++ @tagName(t) ++ "\")",
        },

        .arm_interrupt => |opts| switch (opts.type) {
            .generic => "interrupt",
            .irq => "interrupt(\"IRQ\")",
            .fiq => "interrupt(\"FIQ\")",
            .swi => "interrupt(\"SWI\")",
            .abort => "interrupt(\"ABORT\")",
            .undef => "interrupt(\"UNDEF\")",
        },

        .avr_signal => "signal",

        .microblaze_interrupt => |opts| switch (opts.type) {
            .user => "save_volatiles",
            .regular => "interrupt_handler",
            .fast => "fast_interrupt",
            .breakpoint => "break_handler",
        },

        .mips_interrupt,
        .mips64_interrupt,
        => |opts| switch (opts.mode) {
            inline else => |m| "interrupt(\"" ++ @tagName(m) ++ "\")",
        },

        .riscv64_lp64_v, .riscv32_ilp32_v => "riscv_vector_cc",

        .riscv32_interrupt,
        .riscv64_interrupt,
        => |opts| switch (opts.mode) {
            inline else => |m| "interrupt(\"" ++ @tagName(m) ++ "\")",
        },

        .sh_renesas => "renesas",
        .sh_interrupt => |opts| switch (opts.save) {
            .fpscr => "trapa_handler", // Implies `interrupt_handler`.
            .high => "interrupt_handler, nosave_low_regs",
            .full => "interrupt_handler",
            .bank => "interrupt_handler, resbank",
        },

        .m68k_rtd => "m68k_rtd",

        .avr_interrupt,
        .csky_interrupt,
        .m68k_interrupt,
        .msp430_interrupt,
        .x86_16_interrupt,
        .x86_interrupt,
        .x86_64_interrupt,
        => "interrupt",

        else => unreachable, // `Zcu.callconvSupported`
    };
}

fn toAtomicRmwSuffix(order: std.builtin.AtomicRmwOp) []const u8 {
    return switch (order) {
        .Xchg => "xchg",
        .Add => "add",
        .Sub => "sub",
        .And => "and",
        .Nand => "nand",
        .Or => "or",
        .Xor => "xor",
        .Max => "max",
        .Min => "min",
    };
}

fn toCIntBits(zig_bits: u32) ?u32 {
    for (&[_]u8{ 8, 16, 32, 64, 128 }) |c_bits| {
        if (zig_bits <= c_bits) {
            return c_bits;
        }
    }
    return null;
}

fn signAbbrev(signedness: std.builtin.Signedness) u8 {
    return switch (signedness) {
        .signed => 'i',
        .unsigned => 'u',
    };
}

fn compilerRtAbbrev(ty: Type, zcu: *Zcu, target: *const std.Target) []const u8 {
    return if (ty.isInt(zcu)) switch (ty.intInfo(zcu).bits) {
        1...32 => "si",
        33...64 => "di",
        65...128 => "ti",
        else => unreachable,
    } else if (ty.isRuntimeFloat()) switch (ty.floatBits(target)) {
        16 => "hf",
        32 => "sf",
        64 => "df",
        80 => "xf",
        128 => "tf",
        else => unreachable,
    } else unreachable;
}

fn compareOperatorAbbrev(operator: std.math.CompareOperator) []const u8 {
    return switch (operator) {
        .lt => "lt",
        .lte => "le",
        .eq => "eq",
        .gte => "ge",
        .gt => "gt",
        .neq => "ne",
    };
}

fn compareOperatorC(operator: std.math.CompareOperator) []const u8 {
    return switch (operator) {
        .lt => " < ",
        .lte => " <= ",
        .eq => " == ",
        .gte => " >= ",
        .gt => " > ",
        .neq => " != ",
    };
}

const StringLiteral = struct {
    len: usize,
    cur_len: usize,
    w: *Writer,
    first: bool,

    // MSVC throws C2078 if an array of size 65536 or greater is initialized with a string literal,
    // regardless of the length of the string literal initializing it. Array initializer syntax is
    // used instead.
    // C99 only requires 4095.
    const max_string_initializer_len = @min(65535, 4095);

    // MSVC has a length limit of 16380 per string literal (before concatenation)
    // C99 only requires 4095.
    const max_char_len = 4;
    const max_literal_len = @min(16380 - max_char_len, 4095);

    fn init(w: *Writer, len: usize) StringLiteral {
        return .{
            .cur_len = 0,
            .len = len,
            .w = w,
            .first = true,
        };
    }

    pub fn start(sl: *StringLiteral) Writer.Error!void {
        if (sl.len <= max_string_initializer_len) {
            try sl.w.writeByte('\"');
        } else {
            try sl.w.writeByte('{');
        }
    }

    pub fn end(sl: *StringLiteral) Writer.Error!void {
        if (sl.len <= max_string_initializer_len) {
            try sl.w.writeByte('\"');
        } else {
            try sl.w.writeByte('}');
        }
    }

    fn writeStringLiteralChar(sl: *StringLiteral, c: u8) Writer.Error!usize {
        const w = sl.w;
        switch (c) {
            7 => {
                try w.writeAll("\\a");
                return 2;
            },
            8 => {
                try w.writeAll("\\b");
                return 2;
            },
            '\t' => {
                try w.writeAll("\\t");
                return 2;
            },
            '\n' => {
                try w.writeAll("\\n");
                return 2;
            },
            11 => {
                try w.writeAll("\\v");
                return 2;
            },
            12 => {
                try w.writeAll("\\f");
                return 2;
            },
            '\r' => {
                try w.writeAll("\\r");
                return 2;
            },
            '"', '\'', '?', '\\' => {
                try w.print("\\{c}", .{c});
                return 2;
            },
            ' '...'!', '#'...'&', '('...'>', '@'...'[', ']'...'~' => {
                try w.writeByte(c);
                return 1;
            },
            else => {
                var buf: [4]u8 = undefined;
                const printed = std.fmt.bufPrint(&buf, "\\{o:0>3}", .{c}) catch unreachable;
                try w.writeAll(printed);
                return printed.len;
            },
        }
    }

    pub fn writeChar(sl: *StringLiteral, c: u8) Writer.Error!void {
        if (sl.len <= max_string_initializer_len) {
            if (sl.cur_len == 0 and !sl.first) try sl.w.writeAll("\"\"");

            const char_len = try sl.writeStringLiteralChar(c);
            assert(char_len <= max_char_len);
            sl.cur_len += char_len;

            if (sl.cur_len >= max_literal_len) {
                sl.cur_len = 0;
                sl.first = false;
            }
        } else {
            if (!sl.first) try sl.w.writeByte(',');
            var buf: [6]u8 = undefined;
            const printed = std.fmt.bufPrint(&buf, "'\\x{x}'", .{c}) catch unreachable;
            try sl.w.writeAll(printed);
            sl.cur_len += printed.len;
            sl.first = false;
        }
    }
};

const FormatStringContext = struct {
    str: []const u8,
    sentinel: ?u8,
};

fn formatStringLiteral(data: FormatStringContext, w: *Writer) Writer.Error!void {
    var literal: StringLiteral = .init(w, data.str.len + @intFromBool(data.sentinel != null));
    try literal.start();
    for (data.str) |c| try literal.writeChar(c);
    if (data.sentinel) |sentinel| if (sentinel != 0) try literal.writeChar(sentinel);
    try literal.end();
}

fn fmtStringLiteral(str: []const u8, sentinel: ?u8) std.fmt.Alt(FormatStringContext, formatStringLiteral) {
    return .{ .data = .{ .str = str, .sentinel = sentinel } };
}

fn undefPattern(comptime IntType: type) IntType {
    const int_info = @typeInfo(IntType).int;
    const UnsignedType = std.meta.Int(.unsigned, int_info.bits);
    return @bitCast(@as(UnsignedType, (1 << (int_info.bits | 1)) / 3));
}

const FormatIntLiteralContext = struct {
    dg: *DeclGen,
    loc: ValueRenderLocation,
    val: Value,
    cty: CType,
    base: u8,
    case: std.fmt.Case,
};
fn formatIntLiteral(data: FormatIntLiteralContext, w: *Writer) Writer.Error!void {
    const dg = data.dg;
    const zcu = dg.pt.zcu;
    const target = &dg.mod.resolved_target.result;

    const val = data.val;
    const ty = val.typeOf(zcu);

    assert(!val.isUndef(zcu));

    var space: Value.BigIntSpace = undefined;
    const val_bigint = val.toBigInt(&space, zcu);

    switch (CType.classifyInt(ty, zcu)) {
        .void => unreachable, // opv
        .small => |int_cty| return FormatInt128.format(.{
            .target = zcu.getTarget(),
            .int_cty = int_cty,
            .val = val_bigint,
            .is_global = data.loc == .static_initializer,
            .base = data.base,
            .case = data.case,
        }, w),
        .big => |big| {
            if (!data.loc.isInitializer()) {
                // Use `CType.fmtTypeName` directly to avoid the possibility of `error.OutOfMemory`.
                try w.print("({f})", .{data.cty.fmtTypeName(zcu)});
            }

            try w.writeAll("{{");

            var limb_buf: [std.math.big.int.calcTwosCompLimbCount(65535)]std.math.big.Limb = undefined;
            for (0..big.limbs_len) |limb_index| {
                if (limb_index != 0) try w.writeAll(", ");
                const limb_bit_offset: u16 = switch (target.cpu.arch.endian()) {
                    .little => @intCast(limb_index * big.limb_size.bits()),
                    .big => @intCast((big.limbs_len - limb_index - 1) * big.limb_size.bits()),
                };
                var limb_bigint: std.math.big.int.Mutable = .{
                    .limbs = &limb_buf,
                    .len = undefined,
                    .positive = undefined,
                };
                limb_bigint.shiftRight(val_bigint, limb_bit_offset);
                limb_bigint.truncate(limb_bigint.toConst(), .unsigned, big.limb_size.bits());
                try FormatInt128.format(.{
                    .target = zcu.getTarget(),
                    .int_cty = big.limb_size.unsigned(),
                    .val = limb_bigint.toConst(),
                    .is_global = data.loc == .static_initializer,
                    .base = data.base,
                    .case = data.case,
                }, w);
            }

            try w.writeAll("}}");
        },
    }
}
const FormatInt128 = struct {
    target: *const std.Target,
    int_cty: CType.Int,
    val: std.math.big.int.Const,
    is_global: bool,
    base: u8,
    case: std.fmt.Case,
    pub fn format(data: FormatInt128, w: *Writer) Writer.Error!void {
        const target = data.target;

        const val = data.val;
        const is_global = data.is_global;
        const base = data.base;
        const case = data.case;

        switch (data.int_cty) {
            .uint8_t,
            .uint16_t,
            .uint32_t,
            .uint64_t,
            .@"unsigned short",
            .@"unsigned int",
            .@"unsigned long",
            .@"unsigned long long",
            .uintptr_t,
            => |t| try w.print("{f}", .{
                fmtUnsignedIntLiteralSmall(target, t, val.toInt(u64) catch unreachable, is_global, base, case),
            }),

            .int8_t,
            .int16_t,
            .int32_t,
            .int64_t,
            .char,
            .@"signed short",
            .@"signed int",
            .@"signed long",
            .@"signed long long",
            .intptr_t,
            => |t| try w.print("{f}", .{
                fmtSignedIntLiteralSmall(target, t, val.toInt(i64) catch unreachable, is_global, base, case),
            }),

            .zig_u128 => {
                const raw = val.toInt(u128) catch unreachable;
                const lo: u64 = @truncate(raw);
                const hi: u64 = @intCast(raw >> 64);
                const macro_name: []const u8 = if (is_global) "zig_init_u128" else "zig_make_u128";
                try w.print("{s}({f}, {f})", .{
                    macro_name,
                    fmtUnsignedIntLiteralSmall(target, .uint64_t, hi, is_global, base, case),
                    fmtUnsignedIntLiteralSmall(target, .uint64_t, lo, is_global, base, case),
                });
            },

            .zig_i128 => {
                const raw = val.toInt(i128) catch unreachable;
                const lo: u64 = @truncate(@as(u128, @bitCast(raw)));
                const hi: i64 = @intCast(raw >> 64);
                const macro_name: []const u8 = if (is_global) "zig_init_i128" else "zig_make_i128";
                try w.print("{s}({f}, {f})", .{
                    macro_name,
                    fmtSignedIntLiteralSmall(target, .int64_t, hi, is_global, base, case),
                    fmtUnsignedIntLiteralSmall(target, .uint64_t, lo, is_global, base, case),
                });
            },
        }
    }
};
fn fmtUnsignedIntLiteralSmall(
    target: *const std.Target,
    int_cty: CType.Int,
    val: u64,
    is_global: bool,
    base: u8,
    case: std.fmt.Case,
) FormatUnsignedIntLiteralSmall {
    return .{
        .target = target,
        .int_cty = int_cty,
        .val = val,
        .is_global = is_global,
        .base = base,
        .case = case,
    };
}
fn fmtSignedIntLiteralSmall(
    target: *const std.Target,
    int_cty: CType.Int,
    val: i64,
    is_global: bool,
    base: u8,
    case: std.fmt.Case,
) FormatSignedIntLiteralSmall {
    return .{
        .target = target,
        .int_cty = int_cty,
        .val = val,
        .is_global = is_global,
        .base = base,
        .case = case,
    };
}

const FormatSignedIntLiteralSmall = struct {
    target: *const std.Target,
    int_cty: CType.Int,
    val: i64,
    is_global: bool,
    base: u8,
    case: std.fmt.Case,
    pub fn format(data: FormatSignedIntLiteralSmall, w: *Writer) Writer.Error!void {
        const bits = data.int_cty.bits(data.target);
        const max_int: i64 = @bitCast((@as(u64, 1) << @intCast(bits - 1)) - 1);
        const min_int: i64 = @bitCast(@as(u64, 1) << @intCast(bits - 1));
        if (data.val == max_int) {
            return w.print("{s}_MAX", .{minMaxMacroPrefix(data.int_cty)});
        } else if (data.val == min_int) {
            return w.print("{s}_MIN", .{minMaxMacroPrefix(data.int_cty)});
        }
        if (data.val < 0) try w.writeByte('-');
        try w.writeAll(intLiteralPrefix(data.int_cty, data.is_global));
        switch (data.base) {
            2 => try w.writeAll("0b"),
            8 => try w.writeByte('0'),
            10 => {},
            16 => try w.writeAll("0x"),
            else => unreachable,
        }
        // This `@abs` is safe thanks to the `min_int` case above.
        try w.printInt(@abs(data.val), data.base, data.case, .{});
        try w.writeAll(intLiteralSuffix(data.int_cty));
    }
};
const FormatUnsignedIntLiteralSmall = struct {
    target: *const std.Target,
    int_cty: CType.Int,
    val: u64,
    is_global: bool,
    base: u8,
    case: std.fmt.Case,
    pub fn format(data: FormatUnsignedIntLiteralSmall, w: *Writer) Writer.Error!void {
        const bits = data.int_cty.bits(data.target);
        const max_int: u64 = @as(u64, std.math.maxInt(u64)) >> @intCast(64 - bits);
        if (data.val == max_int) {
            return w.print("{s}_MAX", .{minMaxMacroPrefix(data.int_cty)});
        }
        try w.writeAll(intLiteralPrefix(data.int_cty, data.is_global));
        switch (data.base) {
            2 => try w.writeAll("0b"),
            8 => try w.writeByte('0'),
            10 => {},
            16 => try w.writeAll("0x"),
            else => unreachable,
        }
        try w.printInt(data.val, data.base, data.case, .{});
        try w.writeAll(intLiteralSuffix(data.int_cty));
    }
};
fn minMaxMacroPrefix(int_cty: CType.Int) []const u8 {
    return switch (int_cty) {
        // zig fmt: off
        .char => "CHAR",

        .@"unsigned short"     => "USHRT",
        .@"unsigned int"       => "UINT",
        .@"unsigned long"      => "ULONG",
        .@"unsigned long long" => "ULLONG",

        .@"signed short"     => "SHRT",
        .@"signed int"       => "INT",
        .@"signed long"      => "LONG",
        .@"signed long long" => "LLONG",

        .uint8_t  => "UINT8",
        .uint16_t => "UINT16",
        .uint32_t => "UINT32",
        .uint64_t => "UINT64",
        .zig_u128 => unreachable,

        .int8_t   => "INT8",
        .int16_t  => "INT16",
        .int32_t  => "INT32",
        .int64_t  => "INT64",
        .zig_i128 => unreachable,

        .uintptr_t => "UINTPTR",
        .intptr_t  => "INTPTR",
        // zig fmt: on
    };
}
fn intLiteralPrefix(cty: CType.Int, is_global: bool) []const u8 {
    return switch (cty) {
        // zig fmt: off
        .char              => if (is_global) "" else "(char)",

        .@"unsigned short"     => if (is_global) "" else "(unsigned short)",
        .@"unsigned int"       => "",
        .@"unsigned long"      => "",
        .@"unsigned long long" => "",

        .@"signed short"     => if (is_global) "" else "(signed short)",
        .@"signed int"       => "",
        .@"signed long"      => "",
        .@"signed long long" => "",

        .uint8_t  =>  "UINT8_C(",
        .uint16_t => "UINT16_C(",
        .uint32_t => "UINT32_C(",
        .uint64_t => "UINT64_C(",
        .zig_u128 => unreachable,

        .int8_t   =>  "INT8_C(",
        .int16_t  => "INT16_C(",
        .int32_t  => "INT32_C(",
        .int64_t  => "INT64_C(",
        .zig_i128 => unreachable,

        .uintptr_t => if (is_global) "" else "(uintptr_t)",
        .intptr_t  => if (is_global) "" else "(intptr_t)",
        // zig fmt: on
    };
}
fn intLiteralSuffix(cty: CType.Int) []const u8 {
    return switch (cty) {
        // zig fmt: off
        .char      => "",

        .@"unsigned short"     => "u",
        .@"unsigned int"       => "u",
        .@"unsigned long"      => "ul",
        .@"unsigned long long" => "ull",

        .@"signed short"     => "",
        .@"signed int"       => "",
        .@"signed long"      => "l",
        .@"signed long long" => "ll",

        .uint8_t  => ")",
        .uint16_t => ")",
        .uint32_t => ")",
        .uint64_t => ")",
        .zig_u128 => unreachable,

        .int8_t   => ")",
        .int16_t  => ")",
        .int32_t  => ")",
        .int64_t  => ")",
        .zig_i128 => unreachable,

        .uintptr_t => "ul",
        .intptr_t  => "",
        // zig fmt: on
    };
}

const Materialize = struct {
    local: CValue,

    pub fn start(f: *Function, inst: Air.Inst.Index, ty: Type, value: CValue) !Materialize {
        return .{ .local = switch (value) {
            .local_ref, .constant, .nav_ref, .undef => try f.moveCValue(inst, ty, value),
            .new_local => |local| .{ .local = local },
            else => value,
        } };
    }

    pub fn mat(self: Materialize, f: *Function, w: *Writer) !void {
        try f.writeCValue(w, self.local, .other);
    }

    pub fn end(self: Materialize, f: *Function, inst: Air.Inst.Index) !void {
        try f.freeCValue(inst, self.local);
    }
};

const Vectorize = struct {
    index: CValue = .none,

    pub fn start(f: *Function, inst: Air.Inst.Index, w: *Writer, ty: Type) !Vectorize {
        const pt = f.dg.pt;
        const zcu = pt.zcu;
        switch (ty.zigTypeTag(zcu)) {
            else => return .{ .index = .none },
            .vector => {
                const local = try f.allocLocal(inst, .usize);
                try w.writeAll("for (");
                try f.writeCValue(w, local, .other);
                try w.print(" = {f}; ", .{try f.fmtIntLiteralDec(.zero_usize)});
                try f.writeCValue(w, local, .other);
                try w.print(" < {f}; ", .{try f.fmtIntLiteralDec(try pt.intValue(.usize, ty.vectorLen(zcu)))});
                try f.writeCValue(w, local, .other);
                try w.print(" += {f}) {{", .{try f.fmtIntLiteralDec(.one_usize)});
                f.indent();
                try f.newline();
                return .{ .index = local };
            },
        }
    }

    pub fn elem(self: Vectorize, f: *Function, w: *Writer) !void {
        if (self.index != .none) {
            try w.writeAll(".array[");
            try f.writeCValue(w, self.index, .other);
            try w.writeByte(']');
        }
    }

    pub fn end(self: Vectorize, f: *Function, inst: Air.Inst.Index, w: *Writer) !void {
        if (self.index != .none) {
            try f.outdent();
            try w.writeByte('}');
            try f.newline();
            try freeLocal(f, inst, self.index.new_local, null);
        }
    }
};

fn lowersToBigInt(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .int, .@"enum", .@"struct", .@"union" => CType.classifyInt(ty, zcu) == .big,
        else => false,
    };
}

fn reap(f: *Function, inst: Air.Inst.Index, operands: []const Air.Inst.Ref) !void {
    assert(operands.len <= Air.Liveness.bpi - 1);
    var tomb_bits = f.liveness.getTombBits(inst);
    for (operands) |operand| {
        const dies = @as(u1, @truncate(tomb_bits)) != 0;
        tomb_bits >>= 1;
        if (!dies) continue;
        try die(f, inst, operand);
    }
}

fn die(f: *Function, inst: Air.Inst.Index, ref: Air.Inst.Ref) !void {
    const ref_inst = ref.toIndex() orelse return;
    const c_value = (f.value_map.fetchRemove(ref) orelse return).value;
    const local_index = switch (c_value) {
        .new_local, .local => |l| l,
        else => return,
    };
    try freeLocal(f, inst, local_index, ref_inst);
}

fn freeLocal(f: *Function, inst: ?Air.Inst.Index, local_index: LocalIndex, ref_inst: ?Air.Inst.Index) !void {
    const gpa = f.dg.gpa;
    const local = f.locals.items[local_index];
    if (inst) |i| {
        if (ref_inst) |operand| {
            log.debug("%{d}: freeing t{d} (operand %{d})", .{ @intFromEnum(i), local_index, operand });
        } else {
            log.debug("%{d}: freeing t{d}", .{ @intFromEnum(i), local_index });
        }
    } else {
        if (ref_inst) |operand| {
            log.debug("freeing t{d} (operand %{d})", .{ local_index, operand });
        } else {
            log.debug("freeing t{d}", .{local_index});
        }
    }
    const gop = try f.free_locals_map.getOrPut(gpa, local);
    if (!gop.found_existing) gop.value_ptr.* = .{};
    if (std.debug.runtime_safety) {
        // If this trips, an unfreeable allocation was attempted to be freed.
        assert(!f.allocs.contains(local_index));
    }
    // If this trips, it means a local is being inserted into the
    // free_locals map while it already exists in the map, which is not
    // allowed.
    try gop.value_ptr.putNoClobber(gpa, local_index, {});
}

const BigTomb = struct {
    f: *Function,
    inst: Air.Inst.Index,
    lbt: Air.Liveness.BigTomb,

    fn feed(bt: *BigTomb, op_ref: Air.Inst.Ref) !void {
        const dies = bt.lbt.feed();
        if (!dies) return;
        try die(bt.f, bt.inst, op_ref);
    }
};

fn iterateBigTomb(f: *Function, inst: Air.Inst.Index) BigTomb {
    return .{
        .f = f,
        .inst = inst,
        .lbt = f.liveness.iterateBigTomb(inst),
    };
}

/// A naive clone of this map would create copies of the ArrayList which is
/// stored in the values. This function additionally clones the values.
fn cloneFreeLocalsMap(gpa: Allocator, map: *LocalsMap) !LocalsMap {
    var cloned = try map.clone(gpa);
    const values = cloned.values();
    var i: usize = 0;
    errdefer {
        cloned.deinit(gpa);
        while (i > 0) {
            i -= 1;
            values[i].deinit(gpa);
        }
    }
    while (i < values.len) : (i += 1) {
        values[i] = try values[i].clone(gpa);
    }
    return cloned;
}

fn deinitFreeLocalsMap(gpa: Allocator, map: *LocalsMap) void {
    for (map.values()) |*value| {
        value.deinit(gpa);
    }
    map.deinit(gpa);
}

fn renderErrorName(w: *Writer, err_name: []const u8) Writer.Error!void {
    try w.print("zig_error_{f}", .{fmtIdentUnsolo(err_name)});
}

fn renderNavName(w: *Writer, nav_index: InternPool.Nav.Index, ip: *const InternPool) !void {
    const nav = ip.getNav(nav_index);
    if (nav.getExtern(ip)) |@"extern"| {
        try w.print("{f}", .{
            fmtIdentSolo(ip.getNav(@"extern".owner_nav).name.toSlice(ip)),
        });
    } else {
        // MSVC has a limit of 4095 character token length limit, and fmtIdent can (worst case),
        // expand to 3x the length of its input, but let's cut it off at a much shorter limit.
        const fqn_slice = ip.getNav(nav_index).fqn.toSlice(ip);
        try w.print("{f}__{d}", .{
            fmtIdentUnsolo(fqn_slice[0..@min(fqn_slice.len, 100)]),
            @intFromEnum(nav_index),
        });
    }
}

fn renderUavName(w: *Writer, uav: Value) !void {
    try w.print("__anon_{d}", .{@intFromEnum(uav.toIntern())});
}
