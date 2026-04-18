//! Both types and values are canonically represented by a single 32-bit integer
//! which is an index into an `InternPool` data structure.
//! This struct abstracts around this storage by providing methods only
//! applicable to types rather than values in general.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Value = @import("Value.zig");
const assert = std.debug.assert;
const Target = std.Target;
const Zcu = @import("Zcu.zig");
const log = std.log.scoped(.Type);
const target_util = @import("target.zig");
const InternPool = @import("InternPool.zig");
const Alignment = InternPool.Alignment;
const Zir = std.zig.Zir;
const Type = @This();

ip_index: InternPool.Index,

pub fn zigTypeTag(ty: Type, zcu: *const Zcu) std.builtin.TypeId {
    return zcu.intern_pool.zigTypeTag(ty.toIntern());
}

/// Every type is a member of exactly one "class" which determines:
/// * whether values of the type can exist at all
/// * whether values of the type can be runtime-knwon
/// * whether the type is considered comptime-only
/// * whether the type has runtime bits (nonzero ABI size)
pub const Class = enum(u3) {
    /// Values of this type cannot exist because the type semantically has no values. Attempting to
    /// create a value of this type (such as by coercing `undefined`) always emits a compile error.
    ///
    /// Not comptime-only. No runtime bits, i.e. ABI size is 0.
    ///
    /// Exhaustive list of no-possible-value ("NPV") types:
    /// * `noreturn`
    /// * `anyopaque`, and any `opaque` type
    /// * `[n]T` where `n` is non-zero and `T` is NPV
    /// * Any tuple where at least one non-`comptime` field has an NPV type
    /// * Any enum whose backing type is `noreturn`
    /// * Any struct where at least one non-`comptime` field has an NPV type
    /// * Any union where every field has an NPV type (including unions with no fields)
    ///   * If the union would typically have a runtime tag, even if that tag would have runtime
    ///     bits, the union type is still NPV; the runtime tag is effectively omitted.
    no_possible_value,

    /// Values of this type are always comptime-known because there is only one value inhabiting the
    /// type. This matches the colloquial understanding of a "zero-bit type".
    ///
    /// Not comptime-only (although always comptime-known). No runtime bits, i.e. ABI size is 0.
    ///
    /// Exhaustive list of one-possible-value ("OPV") types:
    /// * `void`
    /// * `u0`, `i0`
    /// * `[0]T` for any `T`
    /// * `[n]T` where `T` is OPV
    /// * `[n:s]T` where `T` is OPV
    /// * `@Vector(0, T)` for any `T`
    /// * `@Vector(n, T)` where `T` is OPV
    /// * Any tuple where every non-`comptime` field has an OPV type (including tuples with no fields)
    /// * Any enum whose backing type is OPV
    /// * Any struct where every non-`comptime` field has an OPV type (including structs with no fields)
    /// * Any union with no runtime tag where all fields have OPV
    /// * Any union where one field has an OPV type, and either:
    ///   * All other fields have NPV types (in this case, if there would be a runtime tag, it is omitted)
    ///   * All other fields have NPV or OPV types, and the union has no runtime tag
    one_possible_value,

    /// The type holds state (so it is neither NPV nor OPV), but contains no comptime-only state, so
    /// values may be runtime-known.
    ///
    /// Not comptime-only. Has runtime bits, i.e. ABI size is non-zero.
    ///
    /// Most types which are typically used in Zig inhabit this class. For instance, all pointer
    /// types, all integer types other than `u0` and `i0`, and most user-defined aggregates fall
    /// into this category.
    runtime,

    /// The type holds state (so it is neither NPV nor OPV). Some, but not all, of the contained
    /// state is comptime-only.
    ///
    /// Comptime-only. Has runtime bits, i.e. ABI size is non-zero.
    ///
    /// Partially-comptime types arise from aggregates (`struct`s, `union`s, or tuples) which have
    /// some fields with fully-comptime types (such as `comptime_int`) and some fields with runtime
    /// types (such as `u8`). Because the user may acquire pointers to these fields, pointers to the
    /// embedded runtime state must be valid, so backends are required to lower the runtime state
    /// within the type.
    ///
    /// Note that logically-runtime state which cannot be directly referenced by the user (such as
    /// the enum tag of a tagged union type, or the "populated" bit of an optional type) does not
    /// cause a type to be partially-comptime.
    partially_comptime,

    /// The type contains exclusively comptime-only state.
    ///
    /// Comptime-only. No runtime bits, i.e. ABI size is 0.
    ///
    /// Fully-comptime types arise from a handful of primitive fully-comptime types:
    /// * `type`
    /// * `comptime_int`
    /// * `comptime_float`
    /// * `@EnumLiteral()`
    /// * `@TypeOf(null)`
    /// * `@TypeOf(undefined)`
    ///
    /// Then, aggregates containing fully-comptime types may themselves be either fully-comptime or
    /// partially-comptime; see the doc comment on `.partially_comptime` for details.
    fully_comptime,
};

/// Returns the `Class` for the type `ty`. Asserts that the layout of `ty` is resolved.
pub fn classify(start_ty: Type, zcu: *const Zcu) Class {
    const ip = &zcu.intern_pool;

    // We avoid recursion in most cases to make us more optimizer-friendly because this can be a
    // very hot code path. The only case where recursion is necessary is tuples, so that case is
    // outlined into a separate function; see `classifyTuple`.

    var extra_states: enum { none, one, many } = .none;

    var cur_ty = start_ty;
    const base: Class = while (true) break switch (ip.indexToKey(cur_ty.toIntern())) {
        .simple_type => |t| switch (t) {
            .f16,
            .f32,
            .f64,
            .f80,
            .f128,
            .usize,
            .isize,
            .c_char,
            .c_short,
            .c_ushort,
            .c_int,
            .c_uint,
            .c_long,
            .c_ulong,
            .c_longlong,
            .c_ulonglong,
            .c_longdouble,
            .bool,
            .anyerror,
            .adhoc_inferred_error_set,
            => .runtime,

            .anyopaque => .no_possible_value,

            .type,
            .comptime_int,
            .comptime_float,
            .enum_literal,
            .null,
            .undefined,
            => .fully_comptime,

            .void => .one_possible_value,
            .noreturn => .no_possible_value,

            .generic_poison => unreachable,
        },

        .error_set_type,
        .inferred_error_set_type,
        .ptr_type,
        .anyframe_type,
        => .runtime,

        .func_type => .fully_comptime,

        .opaque_type => .no_possible_value,

        .error_union_type => |eu| {
            extra_states = .many;
            cur_ty = .fromInterned(eu.payload_type);
            continue;
        },

        .int_type => |int| switch (int.bits) {
            0 => .one_possible_value,
            else => .runtime,
        },
        .array_type => |arr| {
            if (arr.len == 0 and arr.sentinel == .none) break .one_possible_value;
            cur_ty = .fromInterned(arr.child);
            continue;
        },
        .vector_type => |vec| {
            if (vec.len == 0) break .one_possible_value;
            cur_ty = .fromInterned(vec.child);
            continue;
        },
        .opt_type => |child_ty_ip| {
            extra_states = switch (extra_states) {
                .none => .one,
                .one, .many => .many,
            };
            cur_ty = .fromInterned(child_ty_ip);
            continue;
        },
        .tuple_type => |tuple| {
            @branchHint(.unlikely);
            break classifyTuple(tuple.types.get(ip), tuple.values.get(ip), zcu);
        },
        .struct_type => {
            const struct_obj = ip.loadStructType(cur_ty.toIntern());
            switch (struct_obj.layout) {
                .auto, .@"extern" => {
                    zcu.assertUpToDate(.wrap(.{ .type_layout = cur_ty.toIntern() }));
                    break struct_obj.class;
                },
                .@"packed" => {
                    cur_ty = .fromInterned(struct_obj.packed_backing_int_type);
                    continue;
                },
            }
        },
        .union_type => {
            const union_obj = ip.loadUnionType(cur_ty.toIntern());
            switch (union_obj.layout) {
                .auto, .@"extern" => {
                    zcu.assertUpToDate(.wrap(.{ .type_layout = cur_ty.toIntern() }));
                    break union_obj.class;
                },
                .@"packed" => {
                    cur_ty = .fromInterned(union_obj.packed_backing_int_type);
                    continue;
                },
            }
        },
        .enum_type => {
            zcu.assertUpToDate(.wrap(.{ .type_layout = cur_ty.toIntern() }));
            cur_ty = .fromInterned(ip.loadEnumType(cur_ty.toIntern()).int_tag_type);
            continue;
        },

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    };

    return switch (base) {
        .runtime => .runtime, // extra states are irrelevant, we already have many!
        .partially_comptime => .partially_comptime, // likewise
        .fully_comptime => {
            // We do not need to change to `.partially_comptime` here because the extra states do
            // not necessarily require runtime bits. This is because Zig does not provide a way to
            // take the address of the "is null" bit of an optional or the error set "inside" of an
            // error union.
            return .fully_comptime;
        },

        .no_possible_value => switch (extra_states) {
            .none => .no_possible_value,
            .one => .one_possible_value,
            .many => .runtime,
        },

        .one_possible_value => switch (extra_states) {
            .none => .one_possible_value,
            .one, .many => .runtime,
        },
    };
}
/// This is a separate function to `classify` to avoid recursion in the main `classify` function,
/// which can encourage the optimizer to e.g. inline `classify` where it would be beneficial.
fn classifyTuple(types: []const InternPool.Index, values: []const InternPool.Index, zcu: *const Zcu) Class {
    var has_runtime_state = false;
    var has_comptime_state = false;
    for (types, values) |field_ty, field_comptime_val| {
        if (field_comptime_val != .none) continue;
        switch (Type.fromInterned(field_ty).classify(zcu)) {
            .no_possible_value => return .no_possible_value,
            .one_possible_value => {},
            .runtime => has_runtime_state = true,
            .fully_comptime => has_comptime_state = true,
            .partially_comptime => {
                has_runtime_state = true;
                has_comptime_state = true;
            },
        }
    }
    if (has_comptime_state) {
        return if (has_runtime_state) .partially_comptime else .fully_comptime;
    } else {
        return if (has_runtime_state) .runtime else .one_possible_value;
    }
}

/// Asserts the type is resolved.
pub fn isSelfComparable(ty: Type, zcu: *const Zcu, is_equality_cmp: bool) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        => true,

        .vector => ty.childType(zcu).isSelfComparable(zcu, is_equality_cmp),

        .bool,
        .type,
        .void,
        .error_set,
        .@"fn",
        .@"opaque",
        .@"anyframe",
        .@"enum",
        .enum_literal,
        => is_equality_cmp,

        .noreturn,
        .array,
        .undefined,
        .null,
        .error_union,
        .frame,
        => false,

        .@"struct", .@"union" => is_equality_cmp and ty.containerLayout(zcu) == .@"packed",
        .pointer => !ty.isSlice(zcu) and (is_equality_cmp or ty.isCPtr(zcu)),
        .optional => {
            if (!is_equality_cmp) return false;
            return ty.optionalChild(zcu).isSelfComparable(zcu, is_equality_cmp);
        },
    };
}

/// If it is a function pointer, returns the function type. Otherwise returns null.
pub fn castPtrToFn(ty: Type, zcu: *const Zcu) ?Type {
    if (ty.zigTypeTag(zcu) != .pointer) return null;
    const elem_ty = ty.childType(zcu);
    if (elem_ty.zigTypeTag(zcu) != .@"fn") return null;
    return elem_ty;
}

/// Asserts the type is a pointer.
pub fn ptrIsMutable(ty: Type, zcu: *const Zcu) bool {
    return !zcu.intern_pool.indexToKey(ty.toIntern()).ptr_type.flags.is_const;
}

pub const ArrayInfo = struct {
    elem_type: Type,
    sentinel: ?Value = null,
    len: u64,
};

pub fn arrayInfo(self: Type, zcu: *const Zcu) ArrayInfo {
    return .{
        .len = self.arrayLen(zcu),
        .sentinel = self.sentinel(zcu),
        .elem_type = self.childType(zcu),
    };
}

pub fn ptrInfo(ty: Type, zcu: *const Zcu) InternPool.Key.PtrType {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |p| p,
        .opt_type => |child| switch (zcu.intern_pool.indexToKey(child)) {
            .ptr_type => |p| p,
            else => unreachable,
        },
        else => unreachable,
    };
}

pub fn eql(a: Type, b: Type, zcu: *const Zcu) bool {
    _ = zcu; // TODO: remove this parameter
    // The InternPool data structure hashes based on Key to make interned objects
    // unique. An Index can be treated simply as u32 value for the
    // purpose of Type/Value hashing and equality.
    return a.toIntern() == b.toIntern();
}

pub const format = @compileError("do not format types directly; use either ty.fmtDebug() or ty.fmt()");

pub const Formatter = std.fmt.Alt(Format, Format.default);

pub fn fmt(ty: Type, pt: Zcu.PerThread) Formatter {
    return .{ .data = .{
        .ty = ty,
        .pt = pt,
    } };
}

const Format = struct {
    ty: Type,
    pt: Zcu.PerThread,

    fn default(f: Format, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return print(f.ty, writer, f.pt, null);
    }
};

pub fn fmtDebug(ty: Type) std.fmt.Alt(Type, dump) {
    return .{ .data = ty };
}

/// This is a debug function. In order to print types in a meaningful way
/// we also need access to the module.
pub fn dump(start_type: Type, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return writer.print("{any}", .{start_type.ip_index});
}

/// Prints a name suitable for `@typeName`.
/// TODO: take an `opt_sema` to pass to `fmtValue` when printing sentinels.
pub fn print(ty: Type, writer: *std.Io.Writer, pt: Zcu.PerThread, ctx: ?*Comparison) std.Io.Writer.Error!void {
    if (ctx) |c| {
        const should_dedupe = shouldDedupeType(ty, c, pt) catch |err| switch (err) {
            error.OutOfMemory => return error.WriteFailed,
        };
        switch (should_dedupe) {
            .dont_dedupe => {},
            .dedupe => |placeholder| return placeholder.format(writer),
        }
    }

    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .undef => return writer.writeAll("@as(type, undefined)"),
        .int_type => |int_type| {
            const sign_char: u8 = switch (int_type.signedness) {
                .signed => 'i',
                .unsigned => 'u',
            };
            return writer.print("{c}{d}", .{ sign_char, int_type.bits });
        },
        .ptr_type => {
            const info = ty.ptrInfo(zcu);

            if (info.sentinel != .none) switch (info.flags.size) {
                .one, .c => unreachable,
                .many => try writer.print("[*:{f}]", .{Value.fromInterned(info.sentinel).fmtValue(pt)}),
                .slice => try writer.print("[:{f}]", .{Value.fromInterned(info.sentinel).fmtValue(pt)}),
            } else switch (info.flags.size) {
                .one => try writer.writeAll("*"),
                .many => try writer.writeAll("[*]"),
                .c => try writer.writeAll("[*c]"),
                .slice => try writer.writeAll("[]"),
            }
            if (info.flags.is_allowzero and info.flags.size != .c) try writer.writeAll("allowzero ");
            if (info.flags.alignment != .none or
                info.packed_offset.host_size != 0 or
                info.flags.vector_index != .none)
            {
                const alignment = if (info.flags.alignment != .none)
                    info.flags.alignment
                else
                    Type.fromInterned(info.child).abiAlignment(pt.zcu);
                try writer.print("align({d}", .{alignment.toByteUnits() orelse 0});

                if (info.packed_offset.bit_offset != 0 or info.packed_offset.host_size != 0) {
                    try writer.print(":{d}:{d}", .{
                        info.packed_offset.bit_offset, info.packed_offset.host_size,
                    });
                }
                if (info.flags.vector_index != .none) {
                    try writer.print(":{d}", .{@intFromEnum(info.flags.vector_index)});
                }
                try writer.writeAll(") ");
            }
            if (info.flags.address_space != .generic) {
                try writer.print("addrspace(.{s}) ", .{@tagName(info.flags.address_space)});
            }
            if (info.flags.is_const) try writer.writeAll("const ");
            if (info.flags.is_volatile) try writer.writeAll("volatile ");

            try print(Type.fromInterned(info.child), writer, pt, ctx);
            return;
        },
        .array_type => |array_type| {
            if (array_type.sentinel == .none) {
                try writer.print("[{d}]", .{array_type.len});
                try print(Type.fromInterned(array_type.child), writer, pt, ctx);
            } else {
                try writer.print("[{d}:{f}]", .{
                    array_type.len,
                    Value.fromInterned(array_type.sentinel).fmtValue(pt),
                });
                try print(Type.fromInterned(array_type.child), writer, pt, ctx);
            }
            return;
        },
        .vector_type => |vector_type| {
            try writer.print("@Vector({d}, ", .{vector_type.len});
            try print(Type.fromInterned(vector_type.child), writer, pt, ctx);
            try writer.writeAll(")");
            return;
        },
        .opt_type => |child| {
            try writer.writeByte('?');
            return print(Type.fromInterned(child), writer, pt, ctx);
        },
        .error_union_type => |error_union_type| {
            try print(Type.fromInterned(error_union_type.error_set_type), writer, pt, ctx);
            try writer.writeByte('!');
            if (error_union_type.payload_type == .generic_poison_type) {
                try writer.writeAll("anytype");
            } else {
                try print(Type.fromInterned(error_union_type.payload_type), writer, pt, ctx);
            }
            return;
        },
        .inferred_error_set_type => |func_index| {
            const func_nav = ip.getNav(zcu.funcInfo(func_index).owner_nav);
            try writer.print("@typeInfo(@typeInfo(@TypeOf({f})).@\"fn\".return_type.?).error_union.error_set", .{
                func_nav.fqn.fmt(ip),
            });
        },
        .error_set_type => |error_set_type| {
            const NullTerminatedString = InternPool.NullTerminatedString;
            const sorted_names = zcu.gpa.dupe(NullTerminatedString, error_set_type.names.get(ip)) catch {
                zcu.comp.setAllocFailure();
                return writer.writeAll("error{...}");
            };
            defer zcu.gpa.free(sorted_names);

            std.mem.sortUnstable(NullTerminatedString, sorted_names, ip, struct {
                fn lessThan(ip_: *InternPool, lhs: NullTerminatedString, rhs: NullTerminatedString) bool {
                    const lhs_slice = lhs.toSlice(ip_);
                    const rhs_slice = rhs.toSlice(ip_);
                    return std.mem.lessThan(u8, lhs_slice, rhs_slice);
                }
            }.lessThan);

            try writer.writeAll("error{");
            for (sorted_names, 0..) |name, i| {
                if (i != 0) try writer.writeByte(',');
                try writer.print("{f}", .{name.fmt(ip)});
            }
            try writer.writeAll("}");
        },
        .simple_type => |s| switch (s) {
            .f16,
            .f32,
            .f64,
            .f80,
            .f128,
            .usize,
            .isize,
            .c_char,
            .c_short,
            .c_ushort,
            .c_int,
            .c_uint,
            .c_long,
            .c_ulong,
            .c_longlong,
            .c_ulonglong,
            .c_longdouble,
            .anyopaque,
            .bool,
            .void,
            .type,
            .anyerror,
            .comptime_int,
            .comptime_float,
            .noreturn,
            .adhoc_inferred_error_set,
            => return writer.writeAll(@tagName(s)),

            .null,
            .undefined,
            => try writer.print("@TypeOf({s})", .{@tagName(s)}),

            .enum_literal => try writer.writeAll("@EnumLiteral()"),

            .generic_poison => unreachable,
        },
        .struct_type => {
            const name = ip.loadStructType(ty.toIntern()).name;
            try writer.print("{f}", .{name.fmt(ip)});
        },
        .tuple_type => |tuple| {
            if (tuple.types.len == 0) {
                return writer.writeAll("@TypeOf(.{})");
            }
            try writer.writeAll("struct {");
            for (tuple.types.get(ip), tuple.values.get(ip), 0..) |field_ty, val, i| {
                try writer.writeAll(if (i == 0) " " else ", ");
                if (val != .none) try writer.writeAll("comptime ");
                try print(Type.fromInterned(field_ty), writer, pt, ctx);
                if (val != .none) try writer.print(" = {f}", .{Value.fromInterned(val).fmtValue(pt)});
            }
            try writer.writeAll(" }");
        },

        .union_type => {
            const name = ip.loadUnionType(ty.toIntern()).name;
            try writer.print("{f}", .{name.fmt(ip)});
        },
        .opaque_type => {
            const name = ip.loadOpaqueType(ty.toIntern()).name;
            try writer.print("{f}", .{name.fmt(ip)});
        },
        .enum_type => {
            const name = ip.loadEnumType(ty.toIntern()).name;
            try writer.print("{f}", .{name.fmt(ip)});
        },
        .func_type => |fn_info| {
            if (fn_info.is_noinline) {
                try writer.writeAll("noinline ");
            }
            try writer.writeAll("fn (");
            const param_types = fn_info.param_types.get(&zcu.intern_pool);
            for (param_types, 0..) |param_ty, i| {
                if (i != 0) try writer.writeAll(", ");
                if (std.math.cast(u5, i)) |index| {
                    if (fn_info.paramIsComptime(index)) {
                        try writer.writeAll("comptime ");
                    }
                    if (fn_info.paramIsNoalias(index)) {
                        try writer.writeAll("noalias ");
                    }
                }
                if (param_ty == .generic_poison_type) {
                    try writer.writeAll("anytype");
                } else {
                    try print(Type.fromInterned(param_ty), writer, pt, ctx);
                }
            }
            if (fn_info.is_var_args) {
                if (param_types.len != 0) {
                    try writer.writeAll(", ");
                }
                try writer.writeAll("...");
            }
            try writer.writeAll(") ");
            if (fn_info.cc != .auto) print_cc: {
                if (zcu.getTarget().cCallingConvention()) |ccc| {
                    if (fn_info.cc.eql(ccc)) {
                        try writer.writeAll("callconv(.c) ");
                        break :print_cc;
                    }
                }
                switch (fn_info.cc) {
                    .auto, .async, .naked, .@"inline" => try writer.print("callconv(.{f}) ", .{
                        std.zig.fmtId(@tagName(fn_info.cc)),
                    }),
                    else => try writer.print("callconv({any}) ", .{fn_info.cc}),
                }
            }
            if (fn_info.return_type == .generic_poison_type) {
                try writer.writeAll("anytype");
            } else {
                try print(Type.fromInterned(fn_info.return_type), writer, pt, ctx);
            }
        },
        .anyframe_type => |child| {
            if (child == .none) return writer.writeAll("anyframe");
            try writer.writeAll("anyframe->");
            return print(Type.fromInterned(child), writer, pt, ctx);
        },

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    }
}

pub fn fromInterned(i: InternPool.Index) Type {
    assert(i != .none);
    return .{ .ip_index = i };
}

pub fn toIntern(ty: Type) InternPool.Index {
    assert(ty.ip_index != .none);
    return ty.ip_index;
}

pub fn toValue(self: Type) Value {
    return .fromInterned(self.toIntern());
}

/// Returns `true` if and only if the type takes up space in memory at runtime. This is also exactly
/// whether or not the backend/linker needs to be sent values of this type to emit to the binary.
///
/// Types without runtime bits have an ABI size of 0; all other types have a non-zero ABI size. All
/// types, regardless of whether they have runtime bits, have a non-zero ABI alignment.
///
/// Comptime-only types may still have runtime bits. For instance, `struct { a: u32, b: type }` is a
/// comptime-only type, but it nonetheless has runtime bits and a runtime memory layout (where the
/// field `b: type` is omitted). This is because a user may take a pointer to the field `a`, which
/// must then be valid to use at runtime.
///
/// This function is a trivial wrapper around `classify`:
///
/// * Types with one possible value, such as `void`, or no possible value, such as `noreturn`, do
///   not have runtime bits and have an ABI size of 0 because they simply contain no state.
///
/// * Types which are fully comptime, such as `type` and `comptime_int`, do not have runtime bits
///   because they contain only comptime state. (This compiler implementation also currently makes
///   types like `struct { x: comptime_int }` fully comptime, but that could change in the future if
///   we start inserting hidden safety fields into them.)
///
/// * All other types contain some runtime state, so have runtime bits and a non-zero ABI size.
pub fn hasRuntimeBits(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.classify(zcu)) {
        .no_possible_value, .one_possible_value, .fully_comptime => false,
        .runtime, .partially_comptime => true,
    };
}

/// Returns `true` iff the memory layout of `ty` is defined by the Zig language specification.
///
/// Does not require `ty` to be resolved.
pub fn hasWellDefinedLayout(ty: Type, zcu: *const Zcu) bool {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .int_type,
        .vector_type,
        => true,

        .error_union_type,
        .error_set_type,
        .inferred_error_set_type,
        .tuple_type,
        .opaque_type,
        .anyframe_type,
        // These are function bodies, not function pointers.
        .func_type,
        => false,

        .array_type => |array_type| Type.fromInterned(array_type.child).hasWellDefinedLayout(zcu),
        .opt_type => ty.isPtrLikeOptional(zcu),
        .ptr_type => |ptr_type| ptr_type.flags.size != .slice,

        .simple_type => |t| switch (t) {
            .f16,
            .f32,
            .f64,
            .f80,
            .f128,
            .usize,
            .isize,
            .c_char,
            .c_short,
            .c_ushort,
            .c_int,
            .c_uint,
            .c_long,
            .c_ulong,
            .c_longlong,
            .c_ulonglong,
            .c_longdouble,
            .bool,
            .void,
            => true,

            .anyerror,
            .adhoc_inferred_error_set,
            .anyopaque,
            .type,
            .comptime_int,
            .comptime_float,
            .noreturn,
            .null,
            .undefined,
            .enum_literal,
            .generic_poison,
            => false,
        },
        .struct_type => switch (ip.loadStructType(ty.toIntern()).layout) {
            .auto => false,
            .@"extern", .@"packed" => true,
        },
        .union_type => switch (ip.loadUnionType(ty.toIntern()).layout) {
            .auto => false,
            .@"extern", .@"packed" => true,
        },
        .enum_type => switch (ip.loadEnumType(ty.toIntern()).int_tag_mode) {
            .explicit => true,
            .auto => false,
        },

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    };
}

/// Determines whether a function type has runtime bits, i.e. whether a
/// function with this type can exist at runtime.
/// Asserts that `ty` is a function type.
pub fn fnHasRuntimeBits(fn_ty: Type, zcu: *const Zcu) bool {
    assertHasLayout(fn_ty, zcu);
    const fn_info = zcu.typeToFunc(fn_ty).?;
    if (fn_info.comptime_bits != 0) return false;
    for (fn_info.param_types.get(&zcu.intern_pool)) |param_ty| {
        if (param_ty == .generic_poison_type) return false;
        switch (Type.fromInterned(param_ty).classify(zcu)) {
            .fully_comptime,
            .partially_comptime,
            .no_possible_value,
            => return false,

            .one_possible_value,
            .runtime,
            => {},
        }
    }
    const ret_ty: Type = .fromInterned(fn_info.return_type);
    if (ret_ty.toIntern() == .generic_poison_type) {
        return false;
    }
    if (ret_ty.zigTypeTag(zcu) == .error_union and
        ret_ty.errorUnionPayload(zcu).toIntern() == .generic_poison_type)
    {
        return false;
    }
    switch (ret_ty.classify(zcu)) {
        .fully_comptime,
        .partially_comptime,
        => return false,

        .no_possible_value,
        .one_possible_value,
        .runtime,
        => {},
    }
    if (fn_info.cc == .@"inline") return false;
    return true;
}

/// Like `hasRuntimeBits`, but also returns `true` for runtime functions.
pub fn isRuntimeFnOrHasRuntimeBits(ty: Type, zcu: *const Zcu) bool {
    switch (ty.zigTypeTag(zcu)) {
        .@"fn" => return ty.fnHasRuntimeBits(zcu),
        else => return ty.hasRuntimeBits(zcu),
    }
}

/// Returns whether `ty` is NPV, meaning it is "like `noreturn`" in a sense. See doc comments on
/// `Class` for more details.
///
/// Exactly equivalent to `ty.classify(zcu) == .no_possible_value`.
pub fn isNoReturn(ty: Type, zcu: *const Zcu) bool {
    return ty.classify(zcu) == .no_possible_value;
}

/// Never returns `none`. Asserts that all necessary type resolution is already done.
pub fn ptrAlignment(ptr_ty: Type, zcu: *Zcu) Alignment {
    const ip = &zcu.intern_pool;
    const ptr_key: InternPool.Key.PtrType = switch (ip.indexToKey(ptr_ty.toIntern())) {
        .ptr_type => |key| key,
        .opt_type => |child| ip.indexToKey(child).ptr_type,
        else => unreachable,
    };
    if (ptr_key.flags.alignment != .none) return ptr_key.flags.alignment;
    return Type.fromInterned(ptr_key.child).abiAlignment(zcu);
}

pub fn ptrAddressSpace(ty: Type, zcu: *const Zcu) std.builtin.AddressSpace {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.address_space,
        .opt_type => |child| zcu.intern_pool.indexToKey(child).ptr_type.flags.address_space,
        else => unreachable,
    };
}

/// Never returns `.none`. Asserts that the layout of `ty` is resolved.
///
/// Unlike ABI size, a type's ABI alignment is not affected by its `Class`. In other words, any
/// alignment is possible regardless of the result of `ty.classify(zcu)`.
pub fn abiAlignment(ty: Type, zcu: *const Zcu) Alignment {
    const ip = &zcu.intern_pool;
    const target = zcu.getTarget();
    assertHasLayout(ty, zcu);
    return switch (ip.indexToKey(ty.toIntern())) {
        .int_type => |int_type| {
            if (int_type.bits == 0) return .@"1";
            return .fromByteUnits(std.zig.target.intAlignment(target, int_type.bits));
        },
        .ptr_type, .anyframe_type => ptrAbiAlignment(target),
        .array_type => |array_type| Type.fromInterned(array_type.child).abiAlignment(zcu),
        .vector_type => |vector_type| {
            if (vector_type.len == 0) return .@"1";
            switch (zcu.comp.getZigBackend()) {
                else => {
                    const elem_bits: u32 = @intCast(Type.fromInterned(vector_type.child).bitSize(zcu));
                    if (elem_bits == 0) return .@"1";
                    const bytes = ((elem_bits * vector_type.len) + 7) / 8;
                    return .fromByteUnits(std.math.ceilPowerOfTwoAssert(u32, bytes));
                },
                .stage2_c => return Type.fromInterned(vector_type.child).abiAlignment(zcu),
                .stage2_x86_64 => {
                    if (vector_type.child == .bool_type) {
                        if (vector_type.len > 256 and target.cpu.has(.x86, .avx512f)) return .@"64";
                        if (vector_type.len > 128 and target.cpu.has(.x86, .avx)) return .@"32";
                        if (vector_type.len > 64) return .@"16";
                        const bytes = std.math.divCeil(u32, vector_type.len, 8) catch unreachable;
                        return .fromByteUnits(std.math.ceilPowerOfTwoAssert(u32, bytes));
                    }
                    const elem_bytes: u32 = @intCast(Type.fromInterned(vector_type.child).abiSize(zcu));
                    if (elem_bytes == 0) return .@"1";
                    const bytes = elem_bytes * vector_type.len;
                    if (bytes > 32 and target.cpu.has(.x86, .avx512f)) return .@"64";
                    if (bytes > 16 and target.cpu.has(.x86, .avx)) return .@"32";
                    return .@"16";
                },
            }
        },

        .opt_type => |child| Type.fromInterned(child).abiAlignment(zcu),
        .error_union_type => |eu| Alignment.maxStrict(
            Type.fromInterned(eu.payload_type).abiAlignment(zcu),
            errorAbiAlignment(zcu),
        ),

        .error_set_type, .inferred_error_set_type => errorAbiAlignment(zcu),

        .func_type => target_util.minFunctionAlignment(target),

        .simple_type => |t| switch (t) {
            .bool,
            .void,
            .noreturn,
            .anyopaque,
            .type,
            .comptime_int,
            .comptime_float,
            .null,
            .undefined,
            .enum_literal,
            => .@"1",

            .anyerror, .adhoc_inferred_error_set => errorAbiAlignment(zcu),
            .usize, .isize => .fromByteUnits(std.zig.target.intAlignment(target, target.ptrBitWidth())),

            .c_char => cTypeAlign(target, .char),
            .c_short => cTypeAlign(target, .short),
            .c_ushort => cTypeAlign(target, .ushort),
            .c_int => cTypeAlign(target, .int),
            .c_uint => cTypeAlign(target, .uint),
            .c_long => cTypeAlign(target, .long),
            .c_ulong => cTypeAlign(target, .ulong),
            .c_longlong => cTypeAlign(target, .longlong),
            .c_ulonglong => cTypeAlign(target, .ulonglong),
            .c_longdouble => cTypeAlign(target, .longdouble),

            .f16 => .@"2",
            .f32 => cTypeAlign(target, .float),
            .f64 => switch (target.cTypeBitSize(.double)) {
                64 => cTypeAlign(target, .double),
                else => .@"8",
            },
            .f80 => switch (target.cTypeBitSize(.longdouble)) {
                80 => cTypeAlign(target, .longdouble),
                else => Type.u80.abiAlignment(zcu),
            },
            .f128 => switch (target.cTypeBitSize(.longdouble)) {
                128 => cTypeAlign(target, .longdouble),
                else => .@"16",
            },

            .generic_poison => unreachable,
        },
        .tuple_type => |tuple| {
            var big_align: Alignment = .@"1";
            for (tuple.types.get(ip), tuple.values.get(ip)) |field_ty, val| {
                if (val != .none) continue; // comptime field
                const field_align = Type.fromInterned(field_ty).abiAlignment(zcu);
                big_align = big_align.maxStrict(field_align);
            }
            return big_align;
        },
        .struct_type => {
            const struct_obj = ip.loadStructType(ty.toIntern());
            switch (struct_obj.layout) {
                .@"packed" => return Type.fromInterned(struct_obj.packed_backing_int_type).abiAlignment(zcu),
                .auto, .@"extern" => {
                    assert(struct_obj.alignment != .none);
                    return struct_obj.alignment;
                },
            }
        },
        .union_type => {
            const union_obj = ip.loadUnionType(ty.toIntern());
            switch (union_obj.layout) {
                .@"packed" => return Type.fromInterned(union_obj.packed_backing_int_type).abiAlignment(zcu),
                .auto, .@"extern" => {
                    assert(union_obj.alignment != .none);
                    return union_obj.alignment;
                },
            }
        },
        .enum_type => Type.fromInterned(ip.loadEnumType(ty.toIntern()).int_tag_type).abiAlignment(zcu),
        .opaque_type => .@"1",

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    };
}

/// Asserts that `ty` is not an opaque type, and that the layout of `ty` is resolved.
///
/// If the type is NPV, OPV, or fully-comptime (see `Class`), the return value of this function is
/// guaranteed to be zero. Otherwise (if the type is runtime or partially-comptime) the return value
/// is guaranteed to be non-zero.
pub fn abiSize(ty: Type, zcu: *const Zcu) u64 {
    const ip = &zcu.intern_pool;
    const target = zcu.getTarget();
    assertHasLayout(ty, zcu);
    return switch (ip.indexToKey(ty.toIntern())) {
        .int_type => |int_type| std.zig.target.intByteSize(target, int_type.bits),
        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
            .slice => ptrAbiSize(target) * 2,
            .one, .many, .c => ptrAbiSize(target),
        },
        .anyframe_type => ptrAbiSize(target),
        .array_type => |arr| arr.lenIncludingSentinel() * Type.fromInterned(arr.child).abiSize(zcu),
        .vector_type => |vec| {
            const elem_ty: Type = .fromInterned(vec.child);
            const bytes = switch (zcu.comp.getZigBackend()) {
                else => std.math.divCeil(u64, vec.len * elem_ty.bitSize(zcu), 8) catch unreachable,
                .stage2_c => vec.len * elem_ty.abiSize(zcu),
                .stage2_x86_64 => switch (elem_ty.toIntern()) {
                    .bool_type => std.math.divCeil(u64, vec.len, 8) catch unreachable,
                    else => vec.len * elem_ty.abiSize(zcu),
                },
            };
            return ty.abiAlignment(zcu).forward(bytes);
        },
        .opt_type => |child_ty_ip| {
            const child_ty: Type = .fromInterned(child_ty_ip);
            if (child_ty.classify(zcu) == .no_possible_value) return 0;
            if (ty.optionalReprIsPayload(zcu)) return child_ty.abiSize(zcu);
            // Optional types are represented as a struct with the child type as the first
            // field and a boolean as the second. Since the child type's abi alignment is
            // guaranteed to be >= that of bool's (1 byte) the added size is exactly equal
            // to the child type's ABI alignment.
            return child_ty.abiSize(zcu) + child_ty.abiAlignment(zcu).toByteUnits().?;
        },
        .error_set_type, .inferred_error_set_type => errorAbiSize(zcu),
        .error_union_type => |error_union| {
            const payload_ty: Type = .fromInterned(error_union.payload_type);
            switch (payload_ty.classify(zcu)) {
                // Zig has no way to take the address of the error set "in" an error union (giving
                // implementations more freedom in terms of data layout), so if the payload type is
                // fully comptime, we don't need to dedicate runtime bits to the error set.
                .fully_comptime => return 0,
                else => {},
            }
            // The layout will either be (code, payload, padding) or (payload, code, padding)
            // depending on which has larger alignment. So the overall size is just the code
            // and payload sizes added and padded to the larger alignment.
            const big_align: Alignment = .maxStrict(errorAbiAlignment(zcu), payload_ty.abiAlignment(zcu));
            return big_align.forward(errorAbiSize(zcu) + payload_ty.abiSize(zcu));
        },
        .func_type => 0,
        .simple_type => |t| switch (t) {
            .void,
            .noreturn,
            .type,
            .comptime_int,
            .comptime_float,
            .null,
            .undefined,
            .enum_literal,
            => 0,

            .bool => 1,
            .anyerror, .adhoc_inferred_error_set => errorAbiSize(zcu),
            .usize, .isize => ptrAbiSize(target),

            .c_char => target.cTypeByteSize(.char),
            .c_short => target.cTypeByteSize(.short),
            .c_ushort => target.cTypeByteSize(.ushort),
            .c_int => target.cTypeByteSize(.int),
            .c_uint => target.cTypeByteSize(.uint),
            .c_long => target.cTypeByteSize(.long),
            .c_ulong => target.cTypeByteSize(.ulong),
            .c_longlong => target.cTypeByteSize(.longlong),
            .c_ulonglong => target.cTypeByteSize(.ulonglong),
            .c_longdouble => target.cTypeByteSize(.longdouble),

            .f16 => 2,
            .f32 => 4,
            .f64 => 8,
            .f80 => switch (target.cTypeBitSize(.longdouble)) {
                80 => target.cTypeByteSize(.longdouble),
                else => Type.u80.abiSize(zcu),
            },
            .f128 => 16,

            .anyopaque => unreachable,
            .generic_poison => unreachable,
        },
        .tuple_type => |tuple| switch (ty.classify(zcu)) {
            // `structFieldOffset` is bogus on NPV tuples, because there may be some fields with
            // non-zero size.
            .no_possible_value => 0,
            else => ty.structFieldOffset(tuple.types.len, zcu),
        },
        .struct_type => {
            const struct_obj = ip.loadStructType(ty.toIntern());
            switch (struct_obj.layout) {
                .@"packed" => return Type.fromInterned(struct_obj.packed_backing_int_type).abiSize(zcu),
                .auto, .@"extern" => return struct_obj.size,
            }
        },
        .union_type => {
            const union_obj = ip.loadUnionType(ty.toIntern());
            switch (union_obj.layout) {
                .@"packed" => return Type.fromInterned(union_obj.packed_backing_int_type).abiSize(zcu),
                .auto, .@"extern" => return union_obj.size,
            }
        },
        .enum_type => Type.fromInterned(ip.loadEnumType(ty.toIntern()).int_tag_type).abiSize(zcu),
        .opaque_type => unreachable,

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    };
}

pub fn ptrAbiAlignment(target: *const Target) Alignment {
    return .fromNonzeroByteUnits(@divExact(target.ptrBitWidth(), 8));
}
pub fn ptrAbiSize(target: *const Target) u64 {
    return @divExact(target.ptrBitWidth(), 8);
}
pub fn errorAbiAlignment(zcu: *const Zcu) Alignment {
    return .fromNonzeroByteUnits(std.zig.target.intAlignment(zcu.getTarget(), zcu.errorSetBits()));
}
pub fn errorAbiSize(zcu: *const Zcu) u64 {
    return std.zig.target.intByteSize(zcu.getTarget(), zcu.errorSetBits());
}

/// Asserts that `ty` is not an opaque or comptime-only type.
/// Once #19755 is implemented, this query will only work on types with a defined bit-level representation.
pub fn bitSize(ty: Type, zcu: *const Zcu) u64 {
    const target = zcu.getTarget();
    const ip = &zcu.intern_pool;
    assertHasLayout(ty, zcu);
    return switch (ip.indexToKey(ty.toIntern())) {
        .int_type => |int_type| int_type.bits,
        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
            .slice => target.ptrBitWidth() * 2,
            else => target.ptrBitWidth(),
        },
        .anyframe_type => target.ptrBitWidth(),
        .array_type => |array_type| {
            const elem_ty: Type = .fromInterned(array_type.child);
            const len = array_type.lenIncludingSentinel();
            return switch (zcu.comp.getZigBackend()) {
                .stage2_x86_64 => len * elem_ty.bitSize(zcu),
                // this case will be removed under #19755
                else => switch (len) {
                    0 => 0,
                    else => (len - 1) * 8 * elem_ty.abiSize(zcu) + elem_ty.bitSize(zcu),
                },
            };
        },
        .vector_type => |vec| vec.len * Type.fromInterned(vec.child).bitSize(zcu),
        .error_set_type, .inferred_error_set_type => zcu.errorSetBits(),
        .func_type => unreachable,

        .simple_type => |t| switch (t) {
            .void => 0,
            .bool => 1,
            .anyerror, .adhoc_inferred_error_set => zcu.errorSetBits(),
            .usize, .isize => target.ptrBitWidth(),

            .c_char => target.cTypeBitSize(.char),
            .c_short => target.cTypeBitSize(.short),
            .c_ushort => target.cTypeBitSize(.ushort),
            .c_int => target.cTypeBitSize(.int),
            .c_uint => target.cTypeBitSize(.uint),
            .c_long => target.cTypeBitSize(.long),
            .c_ulong => target.cTypeBitSize(.ulong),
            .c_longlong => target.cTypeBitSize(.longlong),
            .c_ulonglong => target.cTypeBitSize(.ulonglong),
            .c_longdouble => target.cTypeBitSize(.longdouble),

            .f16 => 16,
            .f32 => 32,
            .f64 => 64,
            .f80 => 80,
            .f128 => 128,

            .anyopaque => unreachable,
            .type => unreachable,
            .comptime_int => unreachable,
            .comptime_float => unreachable,
            .noreturn => unreachable,
            .null => unreachable,
            .undefined => unreachable,
            .enum_literal => unreachable,
            .generic_poison => unreachable,
        },

        .struct_type => {
            const struct_obj = ip.loadStructType(ty.toIntern());
            switch (struct_obj.layout) {
                .@"packed" => return Type.fromInterned(struct_obj.packed_backing_int_type).bitSize(zcu),
                .auto, .@"extern" => return struct_obj.size * 8, // will be `unreachable` under #19755
            }
        },
        .union_type => {
            const union_obj = ip.loadUnionType(ty.toIntern());
            switch (union_obj.layout) {
                .@"packed" => return Type.fromInterned(union_obj.packed_backing_int_type).bitSize(zcu),
                .auto, .@"extern" => return union_obj.size * 8, // will be `unreachable` under #19755
            }
        },
        .enum_type => Type.fromInterned(ip.loadEnumType(ty.toIntern()).int_tag_type).bitSize(zcu),

        // will be `unreachable` under #19755
        .opt_type,
        .error_union_type,
        .tuple_type,
        => ty.abiSize(zcu) * 8,

        .opaque_type => unreachable,

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    };
}

pub fn isSinglePointer(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_info| ptr_info.flags.size == .one,
        else => false,
    };
}

/// Asserts `ty` is a pointer.
pub fn ptrSize(ty: Type, zcu: *const Zcu) std.builtin.Type.Pointer.Size {
    return ty.ptrSizeOrNull(zcu).?;
}

/// Returns `null` if `ty` is not a pointer.
pub fn ptrSizeOrNull(ty: Type, zcu: *const Zcu) ?std.builtin.Type.Pointer.Size {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_info| ptr_info.flags.size,
        else => null,
    };
}

pub fn isSlice(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.size == .slice,
        else => false,
    };
}

pub fn isSliceAtRuntime(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.size == .slice,
        .opt_type => |child| switch (zcu.intern_pool.indexToKey(child)) {
            .ptr_type => |ptr_type| !ptr_type.flags.is_allowzero and ptr_type.flags.size == .slice,
            else => false,
        },
        else => false,
    };
}

pub fn slicePtrFieldType(ty: Type, zcu: *const Zcu) Type {
    return .fromInterned(zcu.intern_pool.slicePtrType(ty.toIntern()));
}

pub fn isConstPtr(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.is_const,
        else => false,
    };
}

pub fn isVolatilePtr(ty: Type, zcu: *const Zcu) bool {
    return isVolatilePtrIp(ty, &zcu.intern_pool);
}

pub fn isVolatilePtrIp(ty: Type, ip: *const InternPool) bool {
    return switch (ip.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.is_volatile,
        else => false,
    };
}

pub fn isAllowzeroPtr(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.is_allowzero,
        .opt_type => true,
        else => false,
    };
}

pub fn isCPtr(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.size == .c,
        else => false,
    };
}

pub fn isPtrAtRuntime(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
            .slice => false,
            .one, .many, .c => true,
        },
        .opt_type => |child| switch (zcu.intern_pool.indexToKey(child)) {
            .ptr_type => |p| switch (p.flags.size) {
                .slice, .c => false,
                .many, .one => !p.flags.is_allowzero,
            },
            else => false,
        },
        else => false,
    };
}

/// For pointer-like optionals, returns true, otherwise returns the allowzero property
/// of pointers.
pub fn ptrAllowsZero(ty: Type, zcu: *const Zcu) bool {
    return ty.isPtrLikeOptional(zcu) or ty.ptrInfo(zcu).flags.is_allowzero;
}

/// See also `isPtrLikeOptional`.
pub fn optionalReprIsPayload(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .opt_type => |child_type| child_type == .anyerror_type or switch (zcu.intern_pool.indexToKey(child_type)) {
            .ptr_type => |ptr_type| ptr_type.flags.size != .c and !ptr_type.flags.is_allowzero,
            .error_set_type, .inferred_error_set_type => true,
            else => false,
        },
        .ptr_type => |ptr_type| ptr_type.flags.size == .c,
        else => false,
    };
}

/// Returns true if the type is optional and would be lowered to a single pointer
/// address value, using 0 for null. Note that this returns true for C pointers.
pub fn isPtrLikeOptional(ty: Type, zcu: *const Zcu) bool {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .ptr_type => |ptr_type| ptr_type.flags.size == .c,
        .opt_type => |child| switch (zcu.intern_pool.indexToKey(child)) {
            .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
                .slice, .c => false,
                .many, .one => !ptr_type.flags.is_allowzero,
            },
            else => false,
        },
        else => false,
    };
}

/// For `*[N]T`,         returns `[N]T`.
/// For `*T`,            returns `T`.
/// For `[*]T`,          returns `T`.
/// For `@Vector(N, T)`, returns `T`.
/// For `[N]T`,          returns `T`.
/// For `?T`,            returns `T`.
pub fn childType(ty: Type, zcu: *const Zcu) Type {
    return childTypeIp(ty, &zcu.intern_pool);
}

pub fn childTypeIp(ty: Type, ip: *const InternPool) Type {
    return Type.fromInterned(ip.childType(ty.toIntern()));
}

/// Similar to `childType`, but for pointer-like (or slice-like) optionals, gets the child type
/// of the *pointer* type. Asserts that `ty` is either a pointer or a pointer-like optional.
///
/// Essentially, unwraps any one of the following into `T`:
/// ```
/// *T    ?*T    *allowzero T
/// [*]T  ?[*]T  [*]allowzero T
/// []T   ?[]T   []allowzero T
/// [*c]T
/// ```
/// This is primarily useful in Sema to implement operations which can act on optional pointers.
pub fn nullablePtrElem(ty: Type, zcu: *const Zcu) Type {
    switch (ty.zigTypeTag(zcu)) {
        .pointer => return ty.childType(zcu),
        .optional => {
            const ptr_ty = ty.childType(zcu);
            const ptr_info = zcu.intern_pool.indexToKey(ptr_ty.toIntern()).ptr_type;
            assert(ptr_info.flags.size != .c);
            assert(!ptr_info.flags.is_allowzero);
            return .fromInterned(ptr_info.child);
        },
        else => unreachable,
    }
}

/// Asserts that `ty` is an indexable type, and returns its element type. Tuples (and pointers to
/// tuples) are not supported because they do not have a single element type.
///
/// Returns `T` for each of the following types:
/// * `[n]T`
/// * `@Vector(n, T)`
/// * `*[n]T`
/// * `*@Vector(n, T)`
/// * `[]T`
/// * `[*]T`
/// * `[*c]T`
pub fn indexableElem(ty: Type, zcu: *const Zcu) Type {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        inline .array_type, .vector_type => |arr| .fromInterned(arr.child),
        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
            .many, .slice, .c => .fromInterned(ptr_type.child),
            .one => switch (ip.indexToKey(ptr_type.child)) {
                inline .array_type, .vector_type => |arr| .fromInterned(arr.child),
                else => unreachable,
            },
        },
        else => unreachable,
    };
}

/// For vectors, returns the element type. Otherwise returns self.
pub fn scalarType(ty: Type, zcu: *const Zcu) Type {
    return switch (ty.zigTypeTag(zcu)) {
        .vector => ty.childType(zcu),
        else => ty,
    };
}

/// Asserts that the type is an optional, or a C pointer.
/// For C pointers this returns the type unmodified.
pub fn optionalChild(ty: Type, zcu: *const Zcu) Type {
    switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .opt_type => |child| return .fromInterned(child),
        .ptr_type => |ptr_type| {
            assert(ptr_type.flags.size == .c);
            return ty;
        },
        else => unreachable,
    }
}

/// If `ty` is a tagged union, returns its tag type. Otherwise, returns `null`.
pub fn unionTagType(ty: Type, zcu: *const Zcu) ?Type {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .union_type => {},
        else => return null,
    }
    const union_obj = ip.loadUnionType(ty.toIntern());
    return switch (union_obj.tag_usage) {
        .tagged => .fromInterned(union_obj.enum_tag_type),
        .none, .safety => null,
    };
}

/// If the given union type contains a tag (including a safety tag) in its runtime layout, returns
/// its enum tag type. Otherwise, returns null. Asserts that `ty` is a union type.
///
/// In general, codegen logic should call this function instead of `unionTagType`.
pub fn unionTagTypeRuntime(ty: Type, zcu: *const Zcu) ?Type {
    assertHasLayout(ty, zcu);
    const union_type = zcu.intern_pool.loadUnionType(ty.toIntern());
    if (!union_type.has_runtime_tag) return null;
    return .fromInterned(union_type.enum_tag_type);
}

/// Asserts that `ty` is a union type, and returns its tag type, even if the tag will not be stored at runtime.
pub fn unionTagTypeHypothetical(ty: Type, zcu: *const Zcu) Type {
    assertHasLayout(ty, zcu);
    const union_obj = zcu.intern_pool.loadUnionType(ty.toIntern());
    return .fromInterned(union_obj.enum_tag_type);
}

pub fn unionFieldType(ty: Type, enum_tag: Value, zcu: *const Zcu) ?Type {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    const union_obj = zcu.typeToUnion(ty).?;
    const union_fields = union_obj.field_types.get(ip);
    const index = zcu.unionTagFieldIndex(union_obj, enum_tag) orelse return null;
    return Type.fromInterned(union_fields[index]);
}

pub fn unionFieldTypeByIndex(ty: Type, index: usize, zcu: *const Zcu) Type {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    const union_obj = zcu.typeToUnion(ty).?;
    return Type.fromInterned(union_obj.field_types.get(ip)[index]);
}

pub fn unionTagFieldIndex(ty: Type, enum_tag: Value, zcu: *const Zcu) ?u32 {
    assertHasLayout(ty, zcu);
    const union_obj = zcu.typeToUnion(ty).?;
    return zcu.unionTagFieldIndex(union_obj, enum_tag);
}

pub fn unionHasAllZeroBitFieldTypes(ty: Type, zcu: *const Zcu) bool {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    const union_obj = zcu.typeToUnion(ty).?;
    for (union_obj.field_types.get(ip)) |field_ty| {
        if (Type.fromInterned(field_ty).hasRuntimeBits(zcu)) return false;
    }
    return true;
}

/// Returns the type used for backing storage of this union during comptime operations.
/// Asserts the type is an extern union.
pub fn externUnionBackingType(ty: Type, pt: Zcu.PerThread) !Type {
    const zcu = pt.zcu;
    assertHasLayout(ty, zcu);
    const loaded_union = zcu.intern_pool.loadUnionType(ty.toIntern());
    switch (loaded_union.layout) {
        .@"extern" => return pt.arrayType(.{ .len = ty.abiSize(zcu), .child = .u8_type }),
        .@"packed" => unreachable,
        .auto => unreachable,
    }
}

/// Asserts that `ty` is a non-packed union type.
pub fn unionGetLayout(ty: Type, zcu: *const Zcu) Zcu.UnionLayout {
    assertHasLayout(ty, zcu);
    const union_obj = zcu.intern_pool.loadUnionType(ty.toIntern());
    return Type.getUnionLayout(union_obj, zcu);
}

pub fn containerLayout(ty: Type, zcu: *const Zcu) std.builtin.Type.ContainerLayout {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .tuple_type => .auto,
        .struct_type => ip.loadStructType(ty.toIntern()).layout,
        .union_type => ip.loadUnionType(ty.toIntern()).layout,
        else => unreachable,
    };
}

pub fn bitpackBackingInt(ty: Type, zcu: *const Zcu) Type {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => .fromInterned(ip.loadStructType(ty.toIntern()).packed_backing_int_type),
        .union_type => .fromInterned(ip.loadUnionType(ty.toIntern()).packed_backing_int_type),
        else => unreachable,
    };
}

/// Asserts that the type is an error union.
pub fn errorUnionPayload(ty: Type, zcu: *const Zcu) Type {
    return Type.fromInterned(zcu.intern_pool.indexToKey(ty.toIntern()).error_union_type.payload_type);
}

/// Asserts that the type is an error union.
pub fn errorUnionSet(ty: Type, zcu: *const Zcu) Type {
    return Type.fromInterned(zcu.intern_pool.errorUnionSet(ty.toIntern()));
}

/// Returns false for unresolved inferred error sets.
///
/// TODO: this function will behave incorrectly under incremental compilation, because in that case
/// it may see an outdated resolved error set. This function must be either deleted, or its contract
/// changed to require the caller to resolve the error set beforehand. If you must introduce new
/// call sites, please make sure the error set in question is definitely resolved first!
pub fn errorSetIsEmpty(ty: Type, zcu: *const Zcu) bool {
    const ip = &zcu.intern_pool;
    return switch (ty.toIntern()) {
        .anyerror_type, .adhoc_inferred_error_set_type => false,
        else => switch (ip.indexToKey(ty.toIntern())) {
            .error_set_type => |error_set_type| error_set_type.names.len == 0,
            .inferred_error_set_type => |i| switch (ip.funcIesResolvedUnordered(i)) {
                .none, .anyerror_type => false,
                else => |t| ip.indexToKey(t).error_set_type.names.len == 0,
            },
            else => unreachable,
        },
    };
}

/// Returns true if it is an error set that includes anyerror, false otherwise.
/// Note that the result may be a false negative if the type did not get error set
/// resolution prior to this call.
///
/// TODO: this function will behave incorrectly under incremental compilation, because in that case
/// it may see an outdated resolved error set. This function must be either deleted, or its contract
/// changed to require the caller to resolve the error set beforehand. If you must introduce new
/// call sites, please make sure the error set in question is definitely resolved first!
pub fn isAnyError(ty: Type, zcu: *const Zcu) bool {
    const ip = &zcu.intern_pool;
    return switch (ty.toIntern()) {
        .anyerror_type => true,
        .adhoc_inferred_error_set_type => false,
        else => switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
            .inferred_error_set_type => |i| ip.funcIesResolvedUnordered(i) == .anyerror_type,
            else => false,
        },
    };
}

pub fn isError(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .error_union, .error_set => true,
        else => false,
    };
}

/// Returns whether ty, which must be an error set, includes an error `name`.
/// Might return a false negative if `ty` is an inferred error set and not fully
/// resolved yet.
///
/// TODO: this function will behave incorrectly under incremental compilation, because in that case
/// it may see an outdated resolved error set. This function must be either deleted, or its contract
/// changed to require the caller to resolve the error set beforehand. If you must introduce new
/// call sites, please make sure the error set in question is definitely resolved first!
pub fn errorSetHasField(
    ty: Type,
    name: InternPool.NullTerminatedString,
    zcu: *const Zcu,
) bool {
    const ip = &zcu.intern_pool;
    return switch (ty.toIntern()) {
        .anyerror_type => true,
        else => switch (ip.indexToKey(ty.toIntern())) {
            .error_set_type => |error_set_type| error_set_type.nameIndex(ip, name) != null,
            .inferred_error_set_type => |i| switch (ip.funcIesResolvedUnordered(i)) {
                .anyerror_type => true,
                .none => false,
                else => |t| ip.indexToKey(t).error_set_type.nameIndex(ip, name) != null,
            },
            else => unreachable,
        },
    };
}

/// Asserts the type is an array or vector or struct.
pub fn arrayLen(ty: Type, zcu: *const Zcu) u64 {
    return ty.arrayLenIp(&zcu.intern_pool);
}

pub fn arrayLenIp(ty: Type, ip: *const InternPool) u64 {
    return ip.aggregateTypeLen(ty.toIntern());
}

pub fn arrayLenIncludingSentinel(ty: Type, zcu: *const Zcu) u64 {
    return zcu.intern_pool.aggregateTypeLenIncludingSentinel(ty.toIntern());
}

pub fn vectorLen(ty: Type, zcu: *const Zcu) u32 {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .vector_type => |vector_type| vector_type.len,
        .tuple_type => |tuple| @intCast(tuple.types.len),
        else => unreachable,
    };
}

/// Asserts the type is an array, pointer or vector.
pub fn sentinel(ty: Type, zcu: *const Zcu) ?Value {
    return switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .vector_type,
        .struct_type,
        .tuple_type,
        => null,

        .array_type => |t| if (t.sentinel != .none) Value.fromInterned(t.sentinel) else null,
        .ptr_type => |t| if (t.sentinel != .none) Value.fromInterned(t.sentinel) else null,

        else => unreachable,
    };
}

/// Returns true if and only if the type is a fixed-width integer.
pub fn isInt(self: Type, zcu: *const Zcu) bool {
    return self.toIntern() != .comptime_int_type and
        zcu.intern_pool.isIntegerType(self.toIntern());
}

/// Returns true if and only if the type is a fixed-width, signed integer.
pub fn isSignedInt(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.toIntern()) {
        .c_char_type => zcu.getTarget().cCharSignedness() == .signed,
        .isize_type, .c_short_type, .c_int_type, .c_long_type, .c_longlong_type => true,
        else => switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
            .int_type => |int_type| int_type.signedness == .signed,
            else => false,
        },
    };
}

/// Returns true if and only if the type is a fixed-width, unsigned integer.
pub fn isUnsignedInt(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.toIntern()) {
        .c_char_type => zcu.getTarget().cCharSignedness() == .unsigned,
        .usize_type, .c_ushort_type, .c_uint_type, .c_ulong_type, .c_ulonglong_type => true,
        else => switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
            .int_type => |int_type| int_type.signedness == .unsigned,
            else => false,
        },
    };
}

/// Returns true for integers, enums, error sets, and packed structs/unions.
/// If this function returns true, then intInfo() can be called on the type.
pub fn isAbiInt(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .int, .@"enum", .error_set => true,
        .@"struct", .@"union" => ty.containerLayout(zcu) == .@"packed",
        else => false,
    };
}

/// Asserts the type is an integer, enum, error set, or vector of one of them.
pub fn intInfo(starting_ty: Type, zcu: *const Zcu) InternPool.Key.IntType {
    const ip = &zcu.intern_pool;
    const target = zcu.getTarget();
    var ty = starting_ty;

    while (true) switch (ty.toIntern()) {
        .anyerror_type, .adhoc_inferred_error_set_type => {
            return .{ .signedness = .unsigned, .bits = zcu.errorSetBits() };
        },
        .usize_type => return .{ .signedness = .unsigned, .bits = target.ptrBitWidth() },
        .isize_type => return .{ .signedness = .signed, .bits = target.ptrBitWidth() },
        .c_char_type => return .{ .signedness = zcu.getTarget().cCharSignedness(), .bits = target.cTypeBitSize(.char) },
        .c_short_type => return .{ .signedness = .signed, .bits = target.cTypeBitSize(.short) },
        .c_ushort_type => return .{ .signedness = .unsigned, .bits = target.cTypeBitSize(.ushort) },
        .c_int_type => return .{ .signedness = .signed, .bits = target.cTypeBitSize(.int) },
        .c_uint_type => return .{ .signedness = .unsigned, .bits = target.cTypeBitSize(.uint) },
        .c_long_type => return .{ .signedness = .signed, .bits = target.cTypeBitSize(.long) },
        .c_ulong_type => return .{ .signedness = .unsigned, .bits = target.cTypeBitSize(.ulong) },
        .c_longlong_type => return .{ .signedness = .signed, .bits = target.cTypeBitSize(.longlong) },
        .c_ulonglong_type => return .{ .signedness = .unsigned, .bits = target.cTypeBitSize(.ulonglong) },
        else => switch (ip.indexToKey(ty.toIntern())) {
            .int_type => |int_type| return int_type,
            .struct_type => {
                const struct_obj = ip.loadStructType(ty.toIntern());
                assert(struct_obj.layout == .@"packed");
                ty = .fromInterned(struct_obj.packed_backing_int_type);
            },
            .union_type => {
                const union_obj = ip.loadUnionType(ty.toIntern());
                assert(union_obj.layout == .@"packed");
                ty = .fromInterned(union_obj.packed_backing_int_type);
            },
            .enum_type => ty = .fromInterned(ip.loadEnumType(ty.toIntern()).int_tag_type),
            .vector_type => |vector_type| ty = Type.fromInterned(vector_type.child),

            .error_set_type, .inferred_error_set_type => {
                return .{ .signedness = .unsigned, .bits = zcu.errorSetBits() };
            },

            .tuple_type => unreachable,

            .ptr_type => unreachable,
            .anyframe_type => unreachable,
            .array_type => unreachable,

            .opt_type => unreachable,
            .error_union_type => unreachable,
            .func_type => unreachable,
            .simple_type => unreachable, // handled via Index enum tag above

            .opaque_type => unreachable,

            // values, not types
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
            // memoization, not types
            .memoized_call,
            => unreachable,
        },
    };
}

/// Returns `false` for `comptime_float`.
pub fn isRuntimeFloat(ty: Type) bool {
    return switch (ty.toIntern()) {
        .f16_type,
        .f32_type,
        .f64_type,
        .f80_type,
        .f128_type,
        .c_longdouble_type,
        => true,

        else => false,
    };
}

/// Returns `true` for `comptime_float`.
pub fn isAnyFloat(ty: Type) bool {
    return switch (ty.toIntern()) {
        .f16_type,
        .f32_type,
        .f64_type,
        .f80_type,
        .f128_type,
        .c_longdouble_type,
        .comptime_float_type,
        => true,

        else => false,
    };
}

/// Asserts the type is a fixed-size float or comptime_float.
/// Returns 128 for comptime_float types.
pub fn floatBits(ty: Type, target: *const Target) u16 {
    return switch (ty.toIntern()) {
        .f16_type => 16,
        .f32_type => 32,
        .f64_type => 64,
        .f80_type => 80,
        .f128_type, .comptime_float_type => 128,
        .c_longdouble_type => target.cTypeBitSize(.longdouble),

        else => unreachable,
    };
}

/// Asserts the type is a fixed-size float or comptime_float.
pub fn floatSignificandBits(ty: Type, target: *const Target) u16 {
    return switch (ty.floatBits(target)) {
        16 => 11,
        32 => 24,
        64 => 53,
        80 => 64,
        128 => 113,
        else => unreachable,
    };
}

/// Asserts the type is a function or a function pointer.
pub fn fnReturnType(ty: Type, zcu: *const Zcu) Type {
    return Type.fromInterned(zcu.intern_pool.funcTypeReturnType(ty.toIntern()));
}

/// Asserts the type is a function.
pub fn fnCallingConvention(ty: Type, zcu: *const Zcu) std.builtin.CallingConvention {
    return zcu.intern_pool.indexToKey(ty.toIntern()).func_type.cc;
}

pub fn isValidParamType(self: Type, zcu: *const Zcu) bool {
    if (self.toIntern() == .generic_poison_type) return true;
    return switch (self.zigTypeTag(zcu)) {
        .@"opaque", .noreturn => false,
        else => true,
    };
}

pub fn isValidReturnType(self: Type, zcu: *const Zcu) bool {
    if (self.toIntern() == .generic_poison_type) return true;
    return switch (self.zigTypeTag(zcu)) {
        .@"opaque" => false,
        else => true,
    };
}

/// Asserts the type is a function.
pub fn fnIsVarArgs(ty: Type, zcu: *const Zcu) bool {
    return zcu.intern_pool.indexToKey(ty.toIntern()).func_type.is_var_args;
}

pub fn fnPtrMaskOrNull(ty: Type, zcu: *const Zcu) ?u64 {
    return switch (ty.zigTypeTag(zcu)) {
        .@"fn" => target_util.functionPointerMask(zcu.getTarget()),
        else => null,
    };
}

pub fn isNumeric(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.toIntern()) {
        .f16_type,
        .f32_type,
        .f64_type,
        .f80_type,
        .f128_type,
        .c_longdouble_type,
        .comptime_int_type,
        .comptime_float_type,
        .usize_type,
        .isize_type,
        .c_char_type,
        .c_short_type,
        .c_ushort_type,
        .c_int_type,
        .c_uint_type,
        .c_long_type,
        .c_ulong_type,
        .c_longlong_type,
        .c_ulonglong_type,
        => true,

        else => switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
            .int_type => true,
            else => false,
        },
    };
}

/// If the type's classification is `Class.one_possible_value` (see `classify`), returns the only
/// possible value for the type. Otherwise, returns `null`.
pub fn onePossibleValue(ty: Type, pt: Zcu.PerThread) !?Value {
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;
    assertHasLayout(ty, zcu);
    return switch (ip.indexToKey(ty.toIntern())) {
        .ptr_type,
        .error_union_type,
        .func_type,
        .anyframe_type,
        .error_set_type,
        .inferred_error_set_type,
        .opaque_type,
        => null,

        .simple_type => |t| switch (t) {
            .f16,
            .f32,
            .f64,
            .f80,
            .f128,
            .usize,
            .isize,
            .c_char,
            .c_short,
            .c_ushort,
            .c_int,
            .c_uint,
            .c_long,
            .c_ulong,
            .c_longlong,
            .c_ulonglong,
            .c_longdouble,
            .anyopaque,
            .bool,
            .type,
            .anyerror,
            .comptime_int,
            .comptime_float,
            .enum_literal,
            .adhoc_inferred_error_set,
            .null,
            .undefined,
            .noreturn,
            => null,

            .void => .void,

            .generic_poison => unreachable,
        },

        .int_type => |int_type| switch (int_type.bits) {
            0 => try pt.intValue(ty, 0),
            else => null,
        },

        inline .array_type, .vector_type => |seq_type, seq_tag| {
            const has_sentinel = seq_tag == .array_type and seq_type.sentinel != .none;
            if (seq_type.len + @intFromBool(has_sentinel) == 0) {
                return try pt.aggregateValue(ty, &.{});
            }
            if (try Type.fromInterned(seq_type.child).onePossibleValue(pt)) |opv| {
                return try pt.aggregateSplatValue(ty, opv);
            }
            return null;
        },
        .opt_type => |child| switch (Type.fromInterned(child).classify(zcu)) {
            .no_possible_value => try pt.nullValue(ty),
            else => null,
        },
        .tuple_type => |tuple| {
            // Check *whether* the OPV exists first, because constructing it is a little more expensive.
            if (ty.classify(zcu) != .one_possible_value) return null;
            const field_vals = try zcu.gpa.dupe(InternPool.Index, tuple.values.get(ip));
            defer zcu.gpa.free(field_vals);
            for (field_vals, tuple.types.get(ip)) |*field_val, field_ty_ip| {
                if (field_val.* != .none) continue; // comptime field value
                const field_ty: Type = .fromInterned(field_ty_ip);
                field_val.* = (try field_ty.onePossibleValue(pt)).?.toIntern();
            }
            return try pt.aggregateValue(ty, field_vals);
        },
        .struct_type => {
            const struct_obj = ip.loadStructType(ty.toIntern());
            switch (struct_obj.layout) {
                .auto, .@"extern" => {},
                .@"packed" => {
                    const backing_ty: Type = .fromInterned(struct_obj.packed_backing_int_type);
                    const backing_val = try backing_ty.onePossibleValue(pt) orelse return null;
                    return try pt.bitpackValue(ty, backing_val);
                },
            }
            // Type resolution already figured out whether there is an OPV, but if there is, it's
            // our job to compute it.
            if (struct_obj.class != .one_possible_value) return null;
            const field_vals = try gpa.alloc(InternPool.Index, struct_obj.field_types.len);
            defer gpa.free(field_vals);
            for (field_vals, 0..) |*field_val, i_usize| {
                const i: u32 = @intCast(i_usize);
                if (struct_obj.field_is_comptime_bits.get(ip, i)) {
                    field_val.* = struct_obj.field_defaults.get(ip)[i];
                    assert(field_val.* != .none);
                    continue;
                }
                const field_ty: Type = .fromInterned(struct_obj.field_types.get(ip)[i]);
                field_val.* = (try field_ty.onePossibleValue(pt)).?.toIntern();
            }
            return try pt.aggregateValue(ty, field_vals);
        },
        .union_type => {
            const union_obj = ip.loadUnionType(ty.toIntern());
            if (union_obj.layout == .@"packed") {
                const backing_ty: Type = .fromInterned(union_obj.packed_backing_int_type);
                const backing_val = try backing_ty.onePossibleValue(pt) orelse return null;
                return try pt.bitpackValue(ty, backing_val);
            }
            // Type resolution already figured out whether there is an OPV, but if there is, it's
            // our job to compute it.
            if (union_obj.class != .one_possible_value) return null;
            // The OPV comes from exactly one field whose type is OPV, while all others are NPV.
            for (union_obj.field_types.get(ip), 0..) |field_ty_ip, field_index| {
                const field_ty: Type = .fromInterned(field_ty_ip);
                switch (field_ty.classify(zcu)) {
                    .no_possible_value => continue,
                    .one_possible_value => {},
                    else => unreachable,
                }
                // This field is the one!
                const enum_tag_ty: Type = .fromInterned(union_obj.enum_tag_type);
                const tag_val = try pt.enumValueFieldIndex(enum_tag_ty, @intCast(field_index));
                const payload_val = (try field_ty.onePossibleValue(pt)).?;
                return try pt.unionValue(ty, tag_val, payload_val);
            } else unreachable;
        },
        .enum_type => if (try ty.intTagType(zcu).onePossibleValue(pt)) |int_tag_opv| {
            return .fromInterned(try pt.intern(.{ .enum_tag = .{
                .ty = ty.toIntern(),
                .int = int_tag_opv.toIntern(),
            } }));
        } else null,

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    };
}

/// Asserts that `ty` has its layout resolved. `generic_poison` will return `false`.
pub fn comptimeOnly(ty: Type, zcu: *const Zcu) bool {
    if (ty.toIntern() == .generic_poison_type) return false;
    if (ty.zigTypeTag(zcu) == .error_union and ty.errorUnionPayload(zcu).toIntern() == .generic_poison_type) return false;
    return switch (ty.classify(zcu)) {
        .no_possible_value, .one_possible_value, .runtime => false,
        .partially_comptime, .fully_comptime => true,
    };
}

pub fn isVector(ty: Type, zcu: *const Zcu) bool {
    return ty.zigTypeTag(zcu) == .vector;
}

/// Returns 0 if not a vector, otherwise returns @bitSizeOf(Element) * vector_len.
pub fn totalVectorBits(ty: Type, zcu: *Zcu) u64 {
    if (!ty.isVector(zcu)) return 0;
    const v = zcu.intern_pool.indexToKey(ty.toIntern()).vector_type;
    return v.len * Type.fromInterned(v.child).bitSize(zcu);
}

pub fn isArrayOrVector(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .array, .vector => true,
        else => false,
    };
}

pub fn isIndexable(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .array, .vector => true,
        .pointer => switch (ty.ptrSize(zcu)) {
            .slice, .many, .c => true,
            .one => switch (ty.childType(zcu).zigTypeTag(zcu)) {
                .array, .vector => true,
                .@"struct" => ty.childType(zcu).isTuple(zcu),
                else => false,
            },
        },
        .@"struct" => ty.isTuple(zcu),
        else => false,
    };
}

pub fn indexableHasLen(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .array, .vector => true,
        .pointer => switch (ty.ptrSize(zcu)) {
            .many, .c => false,
            .slice => true,
            .one => switch (ty.childType(zcu).zigTypeTag(zcu)) {
                .array, .vector => true,
                .@"struct" => ty.childType(zcu).isTuple(zcu),
                else => false,
            },
        },
        .@"struct" => ty.isTuple(zcu),
        else => false,
    };
}

/// Asserts that the type can have a namespace.
pub fn getNamespaceIndex(ty: Type, zcu: *Zcu) InternPool.NamespaceIndex {
    return ty.getNamespace(zcu).unwrap().?;
}

/// Returns null if the type has no namespace.
pub fn getNamespace(ty: Type, zcu: *Zcu) InternPool.OptionalNamespaceIndex {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .opaque_type => ip.loadOpaqueType(ty.toIntern()).namespace.toOptional(),
        .struct_type => ip.loadStructType(ty.toIntern()).namespace.toOptional(),
        .union_type => ip.loadUnionType(ty.toIntern()).namespace.toOptional(),
        .enum_type => ip.loadEnumType(ty.toIntern()).namespace.toOptional(),
        else => .none,
    };
}

// TODO: new dwarf structure will also need the enclosing code block for types created in imperative scopes
pub fn getParentNamespace(ty: Type, zcu: *Zcu) InternPool.OptionalNamespaceIndex {
    return zcu.namespacePtr(ty.getNamespace(zcu).unwrap() orelse return .none).parent;
}

// Works for vectors and vectors of integers.
pub fn minInt(ty: Type, pt: Zcu.PerThread, dest_ty: Type) !Value {
    const zcu = pt.zcu;
    const scalar = try minIntScalar(ty.scalarType(zcu), pt, dest_ty.scalarType(zcu));
    return if (ty.zigTypeTag(zcu) == .vector) pt.aggregateSplatValue(dest_ty, scalar) else scalar;
}

/// Asserts that the type is an integer.
pub fn minIntScalar(ty: Type, pt: Zcu.PerThread, dest_ty: Type) !Value {
    const zcu = pt.zcu;
    const info = ty.intInfo(zcu);
    if (info.signedness == .unsigned or info.bits == 0) return pt.intValue(dest_ty, 0);

    if (std.math.cast(u6, info.bits - 1)) |shift| {
        const n = @as(i64, std.math.minInt(i64)) >> (63 - shift);
        return pt.intValue(dest_ty, n);
    }

    var res = try std.math.big.int.Managed.init(zcu.gpa);
    defer res.deinit();

    try res.setTwosCompIntLimit(.min, info.signedness, info.bits);

    return pt.intValue_big(dest_ty, res.toConst());
}

// Works for vectors and vectors of integers.
/// The returned Value will have type dest_ty.
pub fn maxInt(ty: Type, pt: Zcu.PerThread, dest_ty: Type) !Value {
    const zcu = pt.zcu;
    const scalar = try maxIntScalar(ty.scalarType(zcu), pt, dest_ty.scalarType(zcu));
    return if (ty.zigTypeTag(zcu) == .vector) pt.aggregateSplatValue(dest_ty, scalar) else scalar;
}

/// The returned Value will have type dest_ty.
pub fn maxIntScalar(ty: Type, pt: Zcu.PerThread, dest_ty: Type) !Value {
    const info = ty.intInfo(pt.zcu);

    switch (info.bits) {
        0 => return pt.intValue(dest_ty, 0),
        1 => return switch (info.signedness) {
            .signed => try pt.intValue(dest_ty, 0),
            .unsigned => try pt.intValue(dest_ty, 1),
        },
        else => {},
    }

    if (std.math.cast(u6, info.bits - 1)) |shift| switch (info.signedness) {
        .signed => {
            const n = @as(i64, std.math.maxInt(i64)) >> (63 - shift);
            return pt.intValue(dest_ty, n);
        },
        .unsigned => {
            const n = @as(u64, std.math.maxInt(u64)) >> (63 - shift);
            return pt.intValue(dest_ty, n);
        },
    };

    var res = try std.math.big.int.Managed.init(pt.zcu.gpa);
    defer res.deinit();

    try res.setTwosCompIntLimit(.max, info.signedness, info.bits);

    return pt.intValue_big(dest_ty, res.toConst());
}

/// Asserts the type is an enum or a union.
pub fn intTagType(ty: Type, zcu: *const Zcu) Type {
    const ip = &zcu.intern_pool;
    const enum_ty: Type = switch (ip.indexToKey(ty.toIntern())) {
        .union_type => .fromInterned(ip.loadUnionType(ty.toIntern()).enum_tag_type),
        .enum_type => ty,
        else => unreachable,
    };
    return .fromInterned(ip.loadEnumType(enum_ty.toIntern()).int_tag_type);
}

pub fn isNonexhaustiveEnum(ty: Type, zcu: *const Zcu) bool {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .enum_type => ip.loadEnumType(ty.toIntern()).nonexhaustive,
        else => false,
    };
}

// Asserts that `ty` is an error set and not `anyerror`.
// Asserts that `ty` is resolved if it is an inferred error set.
pub fn errorSetNames(ty: Type, zcu: *const Zcu) InternPool.NullTerminatedString.Slice {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .error_set_type => |x| x.names,
        .inferred_error_set_type => |i| switch (ip.funcIesResolvedUnordered(i)) {
            .none => unreachable, // unresolved inferred error set
            .anyerror_type => unreachable,
            else => |t| ip.indexToKey(t).error_set_type.names,
        },
        else => unreachable,
    };
}

pub fn enumFields(ty: Type, zcu: *const Zcu) InternPool.NullTerminatedString.Slice {
    assertHasLayout(ty, zcu);
    return zcu.intern_pool.loadEnumType(ty.toIntern()).field_names;
}

pub fn enumFieldCount(ty: Type, zcu: *const Zcu) usize {
    assertHasLayout(ty, zcu);
    return zcu.intern_pool.loadEnumType(ty.toIntern()).field_names.len;
}

pub fn enumFieldName(ty: Type, field_index: usize, zcu: *const Zcu) InternPool.NullTerminatedString {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    return ip.loadEnumType(ty.toIntern()).field_names.get(ip)[field_index];
}

pub fn enumFieldIndex(ty: Type, field_name: InternPool.NullTerminatedString, zcu: *const Zcu) ?u32 {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    const enum_type = ip.loadEnumType(ty.toIntern());
    return enum_type.nameIndex(ip, field_name);
}

/// Asserts `ty` is an enum. `enum_tag` can either be the actual enum tag value
/// or an integer which represents the enum value. Returns the field index in
/// declaration order, or `null` if `enum_tag` does not match any field.
pub fn enumTagFieldIndex(ty: Type, enum_tag: Value, zcu: *const Zcu) ?u32 {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    const enum_type = ip.loadEnumType(ty.toIntern());
    const int_tag = switch (ip.indexToKey(enum_tag.toIntern())) {
        .int => enum_tag.toIntern(),
        .enum_tag => |info| info.int,
        else => unreachable,
    };
    assert(ip.typeOf(int_tag) == enum_type.int_tag_type);
    return enum_type.tagValueIndex(ip, int_tag);
}

/// Returns none in the case of a tuple which uses the integer index as the field name.
pub fn structFieldName(ty: Type, index: usize, zcu: *const Zcu) InternPool.OptionalNullTerminatedString {
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => {
            assertHasLayout(ty, zcu);
            return ip.loadStructType(ty.toIntern()).field_names.get(ip)[index].toOptional();
        },
        .tuple_type => return .none,
        else => unreachable,
    }
}

pub fn structFieldCount(ty: Type, zcu: *const Zcu) u32 {
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => {
            assertHasLayout(ty, zcu);
            return ip.loadStructType(ty.toIntern()).field_types.len;
        },
        .tuple_type => |tuple| return tuple.types.len,
        else => unreachable,
    }
}

/// Returns the field type. Supports tuples, structs, and unions.
pub fn fieldType(ty: Type, index: usize, zcu: *const Zcu) Type {
    const ip = &zcu.intern_pool;
    const types = switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => types: {
            assertHasLayout(ty, zcu);
            break :types ip.loadStructType(ty.toIntern()).field_types;
        },
        .union_type => types: {
            assertHasLayout(ty, zcu);
            break :types ip.loadUnionType(ty.toIntern()).field_types;
        },
        .tuple_type => |tuple| tuple.types,
        else => unreachable,
    };
    return .fromInterned(types.get(ip)[index]);
}

/// If an alignment was explicitly specified for the given field of the struct or union type `ty`,
/// returns that. Otherwise, returns `.none`. This function also supports tuples, for which it
/// always returns `.none`.
///
/// Asserts that the layout of `ty` is resolved, unless `ty` is a tuple.
pub fn explicitFieldAlignment(ty: Type, index: usize, zcu: *const Zcu) Alignment {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .tuple_type => .none,
        .struct_type => {
            assertHasLayout(ty, zcu);
            const struct_obj = ip.loadStructType(ty.toIntern());
            assert(struct_obj.layout != .@"packed");
            if (struct_obj.field_aligns.len == 0) return .none;
            return struct_obj.field_aligns.get(ip)[index];
        },
        .union_type => {
            assertHasLayout(ty, zcu);
            const union_obj = ip.loadUnionType(ty.toIntern());
            assert(union_obj.layout != .@"packed");
            if (union_obj.field_aligns.len == 0) return .none;
            return union_obj.field_aligns.get(ip)[index];
        },
        else => unreachable,
    };
}

/// Returns the alignment a struct field of type `field_ty` will be given if no alignment is
/// explicitly specified. However, in an `extern struct`, a higher alignment may be available due
/// to the struct's full layout (i.e. a field might coincidentally be more aligned).
///
/// Asserts that the layout of `field_ty` is resolved. Asserts that `layout` is not `.@"packed"`.
pub fn defaultStructFieldAlignment(
    field_ty: Type,
    layout: std.builtin.Type.ContainerLayout,
    zcu: *const Zcu,
) Alignment {
    const overalign_big_int = switch (layout) {
        .@"packed" => unreachable,
        .auto => zcu.getTarget().ofmt == .c,
        .@"extern" => true,
    };
    const abi_align = field_ty.abiAlignment(zcu);
    assert(abi_align != .none);
    if (overalign_big_int and field_ty.isAbiInt(zcu) and field_ty.intInfo(zcu).bits >= 128) {
        return abi_align.maxStrict(.@"16");
    }
    return abi_align;
}

pub fn structFieldDefaultValue(ty: Type, index: usize, zcu: *const Zcu) ?Value {
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => {
            const field_defaults = ip.loadStructType(ty.toIntern()).field_defaults.get(ip);
            if (field_defaults.len == 0) return null;
            if (field_defaults[index] == .none) return null;
            return .fromInterned(field_defaults[index]);
        },
        .tuple_type => |tuple| {
            const val = tuple.values.get(ip)[index];
            if (val == .none) return null;
            return .fromInterned(val);
        },
        else => unreachable,
    }
}

pub fn structFieldValueComptime(ty: Type, pt: Zcu.PerThread, index: usize) !?Value {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => {
            const struct_type = ip.loadStructType(ty.toIntern());
            if (struct_type.field_is_comptime_bits.get(ip, index)) {
                return .fromInterned(struct_type.field_defaults.get(ip)[index]);
            } else {
                return Type.fromInterned(struct_type.field_types.get(ip)[index]).onePossibleValue(pt);
            }
        },
        .tuple_type => |tuple| {
            const val = tuple.values.get(ip)[index];
            if (val == .none) {
                return Type.fromInterned(tuple.types.get(ip)[index]).onePossibleValue(pt);
            } else {
                return .fromInterned(val);
            }
        },
        else => unreachable,
    }
}

pub fn structFieldIsComptime(ty: Type, index: usize, zcu: *const Zcu) bool {
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => {
            assertHasLayout(ty, zcu);
            return ip.loadStructType(ty.toIntern()).field_is_comptime_bits.get(ip, index);
        },
        .tuple_type => |tuple| return tuple.values.get(ip)[index] != .none,
        else => unreachable,
    }
}

pub const FieldOffset = struct {
    field: usize,
    offset: u64,
};

/// Supports structs, tuples, and unions.
pub fn structFieldOffset(ty: Type, index: usize, zcu: *const Zcu) u64 {
    assertHasLayout(ty, zcu);
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => {
            const struct_type = ip.loadStructType(ty.toIntern());
            assert(struct_type.layout != .@"packed");
            return struct_type.field_offsets.get(ip)[index];
        },

        .tuple_type => |tuple| {
            var offset: u64 = 0;
            var big_align: Alignment = .none;

            for (tuple.types.get(ip), tuple.values.get(ip), 0..) |field_ty, field_val, i| {
                if (field_val != .none or !Type.fromInterned(field_ty).hasRuntimeBits(zcu)) {
                    // comptime field
                    if (i == index) return 0;
                    continue;
                }

                const field_align = Type.fromInterned(field_ty).abiAlignment(zcu);
                big_align = big_align.max(field_align);
                offset = field_align.forward(offset);
                if (i == index) return offset;
                offset += Type.fromInterned(field_ty).abiSize(zcu);
            }
            offset = big_align.max(.@"1").forward(offset);
            return offset;
        },

        .union_type => {
            const union_type = ip.loadUnionType(ty.toIntern());
            if (!union_type.has_runtime_tag) return 0;
            const layout = Type.getUnionLayout(union_type, zcu);
            if (layout.tag_align.compare(.gte, layout.payload_align)) {
                // {Tag, Payload}
                return layout.payload_align.forward(layout.tag_size);
            } else {
                // {Payload, Tag}
                return 0;
            }
        },

        else => unreachable,
    }
}

pub fn srcLocOrNull(ty: Type, zcu: *Zcu) ?Zcu.LazySrcLoc {
    const ip = &zcu.intern_pool;
    return .{
        .base_node_inst = switch (ip.indexToKey(ty.toIntern())) {
            .struct_type, .union_type, .opaque_type, .enum_type => |info| switch (info) {
                .declared => |d| d.zir_index,
                .reified => |r| r.zir_index,
                .generated_union_tag => |union_ty| ip.loadUnionType(union_ty).zir_index,
            },
            else => return null,
        },
        .offset = Zcu.LazySrcLoc.Offset.nodeOffset(.zero),
    };
}

pub fn srcLoc(ty: Type, zcu: *Zcu) Zcu.LazySrcLoc {
    return ty.srcLocOrNull(zcu).?;
}

pub fn isGenericPoison(ty: Type) bool {
    return ty.toIntern() == .generic_poison_type;
}

pub fn isTuple(ty: Type, zcu: *const Zcu) bool {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .tuple_type => true,
        else => false,
    };
}

/// Traverses optional child types and error union payloads until the type is neither of those.
/// For `E!?u32`, returns `u32`; for `*u8`, returns `*u8`.
pub fn optEuBaseType(ty: Type, zcu: *const Zcu) Type {
    var cur = ty;
    while (true) switch (cur.zigTypeTag(zcu)) {
        .optional => cur = cur.optionalChild(zcu),
        .error_union => cur = cur.errorUnionPayload(zcu),
        else => return cur,
    };
}

pub fn toUnsigned(ty: Type, pt: Zcu.PerThread) !Type {
    const zcu = pt.zcu;
    return switch (ty.toIntern()) {
        // zig fmt: off
        .usize_type,       .isize_type      => .usize,
        .c_ushort_type,    .c_short_type    => .c_ushort,
        .c_uint_type,      .c_int_type      => .c_uint,
        .c_ulong_type,     .c_long_type     => .c_ulong,
        .c_ulonglong_type, .c_longlong_type => .c_ulonglong,
        // zig fmt: on
        else => switch (ty.zigTypeTag(zcu)) {
            .int => pt.intType(.unsigned, ty.intInfo(zcu).bits),
            .vector => try pt.vectorType(.{
                .len = ty.vectorLen(zcu),
                .child = (try ty.childType(zcu).toUnsigned(pt)).toIntern(),
            }),
            else => unreachable,
        },
    };
}

pub fn typeDeclInst(ty: Type, zcu: *const Zcu) ?InternPool.TrackedInst.Index {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => ip.loadStructType(ty.toIntern()).zir_index,
        .union_type => ip.loadUnionType(ty.toIntern()).zir_index,
        .enum_type => ip.loadEnumType(ty.toIntern()).zir_index.unwrap(),
        .opaque_type => ip.loadOpaqueType(ty.toIntern()).zir_index,
        else => null,
    };
}

pub fn typeDeclInstAllowGeneratedTag(ty: Type, zcu: *const Zcu) ?InternPool.TrackedInst.Index {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => ip.loadStructType(ty.toIntern()).zir_index,
        .union_type => ip.loadUnionType(ty.toIntern()).zir_index,
        .enum_type => |e| switch (e) {
            .declared, .reified => ip.loadEnumType(ty.toIntern()).zir_index.unwrap().?,
            .generated_union_tag => |union_ty| ip.loadUnionType(union_ty).zir_index,
        },
        .opaque_type => ip.loadOpaqueType(ty.toIntern()).zir_index,
        else => null,
    };
}

pub fn typeDeclSrcLine(ty: Type, zcu: *Zcu) ?u32 {
    // Note that changes to ZIR instruction tracking only need to update this code
    // if a newly-tracked instruction can be a type's owner `zir_index`.
    comptime assert(Zir.inst_tracking_version == 0);

    const ip = &zcu.intern_pool;
    const tracked = switch (ip.indexToKey(ty.toIntern())) {
        .struct_type, .union_type, .opaque_type, .enum_type => |info| switch (info) {
            .declared => |d| d.zir_index,
            .reified => |r| r.zir_index,
            .generated_union_tag => |union_ty| ip.loadUnionType(union_ty).zir_index,
        },
        else => return null,
    };
    const info = tracked.resolveFull(&zcu.intern_pool) orelse return null;
    const file = zcu.fileByIndex(info.file);
    const zir = switch (file.getMode()) {
        .zig => file.zir.?,
        .zon => return 0,
    };
    const inst = zir.instructions.get(@intFromEnum(info.inst));
    return switch (inst.tag) {
        .struct_init, .struct_init_ref => zir.extraData(Zir.Inst.StructInit, inst.data.pl_node.payload_index).data.abs_line,
        .struct_init_anon => zir.extraData(Zir.Inst.StructInitAnon, inst.data.pl_node.payload_index).data.abs_line,
        .extended => switch (inst.data.extended.opcode) {
            .struct_decl => zir.getStructDecl(info.inst).src_line,
            .union_decl => zir.getUnionDecl(info.inst).src_line,
            .enum_decl => zir.getEnumDecl(info.inst).src_line,
            .opaque_decl => zir.getOpaqueDecl(info.inst).src_line,
            .reify_enum => zir.extraData(Zir.Inst.ReifyEnum, inst.data.extended.operand).data.src_line,
            .reify_struct => zir.extraData(Zir.Inst.ReifyStruct, inst.data.extended.operand).data.src_line,
            .reify_union => zir.extraData(Zir.Inst.ReifyUnion, inst.data.extended.operand).data.src_line,
            else => unreachable,
        },
        else => unreachable,
    };
}

/// Given a namespace type, returns its list of captured values.
pub fn getCaptures(ty: Type, zcu: *const Zcu) InternPool.CaptureValue.Slice {
    const ip = &zcu.intern_pool;
    return switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => ip.loadStructType(ty.toIntern()).captures,
        .union_type => ip.loadUnionType(ty.toIntern()).captures,
        .enum_type => ip.loadEnumType(ty.toIntern()).captures,
        .opaque_type => ip.loadOpaqueType(ty.toIntern()).captures,
        else => unreachable,
    };
}

pub fn arrayBase(ty: Type, zcu: *const Zcu) struct { Type, u64 } {
    var cur_ty: Type = ty;
    var cur_len: u64 = 1;
    while (cur_ty.zigTypeTag(zcu) == .array) {
        cur_len *= cur_ty.arrayLenIncludingSentinel(zcu);
        cur_ty = cur_ty.childType(zcu);
    }
    return .{ cur_ty, cur_len };
}

/// Asserts that `loaded_union.layout` is not `.@"packed"`.
pub fn getUnionLayout(loaded_union: InternPool.LoadedUnionType, zcu: *const Zcu) Zcu.UnionLayout {
    assert(loaded_union.layout != .@"packed");

    const ip = &zcu.intern_pool;
    var most_aligned_field: u32 = 0;
    var most_aligned_field_align: InternPool.Alignment = .@"1";
    var most_aligned_field_size: u64 = 0;
    var biggest_field: u32 = 0;
    var payload_size: u64 = 0;
    var payload_align: InternPool.Alignment = .@"1";
    for (loaded_union.field_types.get(ip), 0..) |field_ty_ip_index, field_index| {
        const field_ty: Type = .fromInterned(field_ty_ip_index);
        if (field_ty.isNoReturn(zcu)) continue;

        const field_align: InternPool.Alignment = a: {
            const explicit_aligns = loaded_union.field_aligns.get(ip);
            if (explicit_aligns.len > 0) {
                const a = explicit_aligns[field_index];
                if (a != .none) break :a a;
            }
            break :a field_ty.abiAlignment(zcu);
        };
        if (field_ty.hasRuntimeBits(zcu)) {
            const field_size = field_ty.abiSize(zcu);
            if (field_size > payload_size) {
                payload_size = field_size;
                biggest_field = @intCast(field_index);
            }
            if (field_size > 0 and field_align.compare(.gte, most_aligned_field_align)) {
                most_aligned_field = @intCast(field_index);
                most_aligned_field_align = field_align;
                most_aligned_field_size = field_size;
            }
        }
        payload_align = payload_align.max(field_align);
    }
    if (!loaded_union.has_runtime_tag or
        !Type.fromInterned(loaded_union.enum_tag_type).hasRuntimeBits(zcu))
    {
        return .{
            .abi_size = payload_align.forward(payload_size),
            .abi_align = payload_align,
            .most_aligned_field = most_aligned_field,
            .most_aligned_field_size = most_aligned_field_size,
            .biggest_field = biggest_field,
            .payload_size = payload_size,
            .payload_align = payload_align,
            .tag_align = .none,
            .tag_size = 0,
            .padding = 0,
        };
    }

    const tag_size = Type.fromInterned(loaded_union.enum_tag_type).abiSize(zcu);
    const tag_align = Type.fromInterned(loaded_union.enum_tag_type).abiAlignment(zcu).max(.@"1");
    return .{
        .abi_size = loaded_union.size,
        .abi_align = tag_align.max(payload_align),
        .most_aligned_field = most_aligned_field,
        .most_aligned_field_size = most_aligned_field_size,
        .biggest_field = biggest_field,
        .payload_size = payload_size,
        .payload_align = payload_align,
        .tag_align = tag_align,
        .tag_size = tag_size,
        .padding = loaded_union.padding,
    };
}

/// Asserts that `ptr_ty` is either a many-item pointer, a slice, a C pointer, or a single pointer
/// to array (in other words, a pointer which is indexed by pointer arithmetic), and returns the
/// type of the element pointer at the given index.
///
/// Asserts that the layout of the pointer element type is resolved.
///
/// If `index` is `null`, the index is an arbitrary runtime-known value.
pub fn elemPtrType(ptr_ty: Type, index: ?u64, pt: Zcu.PerThread) Allocator.Error!Type {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const ptr_info = ip.indexToKey(ptr_ty.toIntern()).ptr_type;
    const elem_ty: Type = switch (ptr_info.flags.size) {
        .slice, .many, .c => .fromInterned(ptr_info.child),
        .one => switch (ip.indexToKey(ptr_info.child)) {
            .array_type => |array_type| .fromInterned(array_type.child),
            else => unreachable,
        },
    };
    elem_ty.assertHasLayout(zcu);
    const elem_align: Alignment = switch (elem_ty.classify(zcu)) {
        .no_possible_value,
        .one_possible_value,
        => ptr_info.flags.alignment,

        .partially_comptime,
        .fully_comptime,
        => switch (ptr_info.flags.alignment) {
            .none => .none,
            else => |array_align| .minStrict(array_align, elem_ty.abiAlignment(zcu)),
        },

        .runtime => switch (ptr_info.flags.alignment) {
            .none => .none,
            else => |array_align| elem_align: {
                // If the index is runtime-known, use 1 as it gives the minimum possible alignment.
                const effective_index = index orelse 1;
                if (effective_index == 0) break :elem_align array_align;
                const byte_offset = effective_index * elem_ty.abiSize(zcu);
                break :elem_align .minStrict(array_align, .fromLog2Units(@ctz(byte_offset)));
            },
        },
    };
    return pt.ptrType(.{
        .child = elem_ty.toIntern(),
        .flags = .{
            .size = .one,
            .is_const = ptr_info.flags.is_const,
            .is_volatile = ptr_info.flags.is_volatile,
            .is_allowzero = ptr_info.flags.is_allowzero and (index == null or index == 0),
            .address_space = ptr_info.flags.address_space,
            .alignment = elem_align,
        },
    });
}

/// Asserts that `ptr_ty` is a pointer (single-item or C) to a struct, union, tuple, or slice, and
/// returns the type of a pointer to the field at `field_index`.
///
/// Asserts that the layout of the pointer child type is resolved.
///
/// For slices, `Value.slice_ptr_index` and `Value.slice_len_index` are used for the field index.
pub fn fieldPtrType(ptr_ty: Type, field_index: u32, pt: Zcu.PerThread) Allocator.Error!Type {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const ptr_info = ip.indexToKey(ptr_ty.toIntern()).ptr_type;
    assert(ptr_info.flags.size == .one or ptr_info.flags.size == .c);
    const aggregate_ty: Type = .fromInterned(ptr_info.child);
    aggregate_ty.assertHasLayout(zcu);
    // We only exit this `switch` for default-layout aggregates, where the field pointer alignment
    // is a simple minimum of the aggregate pointer alignment and the field alignment.
    // `field_align` is `.none` if there is no explicit alignment annotation.
    const field_ty: Type, const field_align: Alignment = switch (aggregate_ty.zigTypeTag(zcu)) {
        .@"struct" => switch (aggregate_ty.containerLayout(zcu)) {
            .auto => field: {
                if (aggregate_ty.isTuple(zcu)) {
                    break :field .{ aggregate_ty.fieldType(field_index, zcu), .none };
                }
                const struct_obj = ip.loadStructType(aggregate_ty.toIntern());
                break :field .{
                    .fromInterned(struct_obj.field_types.get(ip)[field_index]),
                    struct_obj.field_aligns.getOrNone(ip, field_index),
                };
            },
            .@"extern" => {
                // Field alignment is determined based on the actual field offset. For instance, in
                // `extern struct { x: u32, y: u16 }`, the `y` field is 4-byte aligned.
                const field_ty = aggregate_ty.fieldType(field_index, zcu);
                const field_offset = aggregate_ty.structFieldOffset(field_index, zcu);
                const parent_align = switch (ptr_info.flags.alignment) {
                    .none => aggregate_ty.abiAlignment(zcu),
                    else => |a| a,
                };
                const actual_field_align = switch (field_offset) {
                    0 => parent_align,
                    else => parent_align.minStrict(.fromLog2Units(@ctz(field_offset))),
                };
                const field_ptr_align: Alignment = a: {
                    if (ptr_info.flags.alignment == .none and
                        aggregate_ty.explicitFieldAlignment(field_index, zcu) == .none and
                        actual_field_align == field_ty.abiAlignment(zcu))
                    {
                        // There's no user-specified 'align' in sight, and the alignment from the
                        // field offset matches the field type's natural alignment, so just use a
                        // default-aligned pointer.
                        break :a .none;
                    }
                    break :a actual_field_align;
                };
                var field_ptr_info = ptr_info;
                field_ptr_info.child = field_ty.toIntern();
                field_ptr_info.flags.alignment = field_ptr_align;
                return pt.ptrType(field_ptr_info);
            },
            .@"packed" => {
                var field_ptr_info = ptr_info;
                if (field_ptr_info.flags.alignment == .none) {
                    field_ptr_info.flags.alignment = aggregate_ty.abiAlignment(zcu);
                }
                field_ptr_info.packed_offset = packed_offset: {
                    comptime assert(Type.packed_struct_layout_version == 2);
                    const bit_offset = zcu.structPackedFieldBitOffset(
                        ip.loadStructType(aggregate_ty.toIntern()),
                        field_index,
                    );
                    break :packed_offset if (ptr_info.packed_offset.host_size != 0) .{
                        .host_size = ptr_info.packed_offset.host_size,
                        .bit_offset = ptr_info.packed_offset.bit_offset + bit_offset,
                    } else .{
                        .host_size = switch (zcu.comp.getZigBackend()) {
                            else => @intCast((aggregate_ty.bitSize(zcu) + 7) / 8),
                            .stage2_x86_64, .stage2_c => @intCast(aggregate_ty.abiSize(zcu)),
                        },
                        .bit_offset = ptr_info.packed_offset.bit_offset + bit_offset,
                    };
                };
                field_ptr_info.child = aggregate_ty.fieldType(field_index, zcu).toIntern();
                return pt.ptrType(field_ptr_info);
            },
        },
        .@"union" => switch (aggregate_ty.containerLayout(zcu)) {
            .auto => field: {
                const union_obj = ip.loadUnionType(aggregate_ty.toIntern());
                break :field .{
                    .fromInterned(union_obj.field_types.get(ip)[field_index]),
                    union_obj.field_aligns.getOrNone(ip, field_index),
                };
            },
            .@"extern" => {
                // The alignment always matches that of the union pointer. If the union pointer is
                // default aligned (`.none`), we may need to explicitly align the result pointer.
                const field_ty = aggregate_ty.fieldType(field_index, zcu);
                var field_ptr_info = ptr_info;
                field_ptr_info.child = field_ty.toIntern();
                if (field_ptr_info.flags.alignment == .none and
                    Alignment.compareStrict(field_ty.abiAlignment(zcu), .neq, aggregate_ty.abiAlignment(zcu)))
                {
                    field_ptr_info.flags.alignment = aggregate_ty.abiAlignment(zcu);
                }
                return pt.ptrType(field_ptr_info);
            },
            .@"packed" => {
                const field_ty = aggregate_ty.fieldType(field_index, zcu);
                var field_ptr_info = ptr_info;
                if (field_ptr_info.flags.alignment == .none) {
                    const resolved_align = aggregate_ty.abiAlignment(zcu);
                    if (field_ty.abiAlignment(zcu) != resolved_align) {
                        field_ptr_info.flags.alignment = resolved_align;
                    }
                }
                field_ptr_info.child = aggregate_ty.fieldType(field_index, zcu).toIntern();
                return pt.ptrType(field_ptr_info);
            },
        },
        .pointer => field: {
            assert(aggregate_ty.isSlice(zcu));
            break :field switch (field_index) {
                Value.slice_ptr_index => .{ aggregate_ty.slicePtrFieldType(zcu), .none },
                Value.slice_len_index => .{ .usize, .none },
                else => unreachable,
            };
        },
        else => unreachable,
    };
    const field_ptr_align: Alignment = a: {
        if (aggregate_ty.zigTypeTag(zcu) == .@"struct" and aggregate_ty.structFieldIsComptime(field_index, zcu)) {
            // For `comptime` fields, just use exactly what was specified, or ABI alignment if nothing was specified.
            break :a field_align;
        }
        const actual_field_align = switch (field_align) {
            .none => switch (ip.indexToKey(aggregate_ty.toIntern())) {
                .tuple_type, .union_type => field_ty.abiAlignment(zcu),
                .struct_type => field_ty.defaultStructFieldAlignment(.auto, zcu),
                .ptr_type => Type.usize.abiAlignment(zcu),
                else => unreachable,
            },
            else => |a| a,
        };
        const actual_aggregate_align = switch (ptr_info.flags.alignment) {
            .none => aggregate_ty.abiAlignment(zcu),
            else => |a| a,
        };
        if (actual_aggregate_align.compareStrict(.lt, actual_field_align)) {
            // Underaligned aggregate; use that alignment.
            assert(ptr_info.flags.alignment != .none);
            break :a actual_aggregate_align;
        }
        if (field_align == .none and actual_field_align == field_ty.abiAlignment(zcu)) {
            // No explicit annotation on the field (nor an unusual default), and the aggregate
            // alignment is irrelevant to us, so return an un-annotated pointer.
            break :a .none;
        }
        break :a actual_field_align;
    };
    var field_ptr_info = ptr_info;
    field_ptr_info.flags.alignment = field_ptr_align;
    field_ptr_info.child = field_ty.toIntern();
    return pt.ptrType(field_ptr_info);
}

pub fn containerTypeName(ty: Type, ip: *const InternPool) InternPool.NullTerminatedString {
    return switch (ip.indexToKey(ty.toIntern())) {
        .struct_type => ip.loadStructType(ty.toIntern()).name,
        .union_type => ip.loadUnionType(ty.toIntern()).name,
        .enum_type => ip.loadEnumType(ty.toIntern()).name,
        .opaque_type => ip.loadOpaqueType(ty.toIntern()).name,
        else => unreachable,
    };
}

pub fn destructurable(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .array, .vector => true,
        .@"struct" => ty.isTuple(zcu),
        else => false,
    };
}

pub const UnpackableReason = union(enum) {
    comptime_only,
    pointer,
    enum_inferred_int_tag: Type,
    non_packed_struct: Type,
    non_packed_union: Type,
    slice,
    other,
};

/// Returns `null` iff `ty` is allowed in packed types.
pub fn unpackable(ty: Type, zcu: *const Zcu) ?UnpackableReason {
    return switch (ty.zigTypeTag(zcu)) {
        .void,
        .bool,
        .float,
        .int,
        => null,

        .type,
        .comptime_float,
        .comptime_int,
        .enum_literal,
        .undefined,
        .null,
        => .comptime_only,

        .noreturn,
        .@"opaque",
        .error_union,
        .error_set,
        .frame,
        .@"anyframe",
        .@"fn",
        .array,
        .vector,
        => .other,

        .optional => if (ty.isPtrLikeOptional(zcu))
            .pointer
        else
            .other,

        .pointer => switch (ty.ptrSize(zcu)) {
            .slice => .slice,
            .one, .many, .c => .pointer,
        },

        .@"enum" => switch (zcu.intern_pool.loadEnumType(ty.toIntern()).int_tag_mode) {
            .explicit => null,
            .auto => .{ .enum_inferred_int_tag = ty },
        },

        .@"struct" => switch (ty.containerLayout(zcu)) {
            .@"packed" => null,
            .auto, .@"extern" => .{ .non_packed_struct = ty },
        },
        .@"union" => switch (ty.containerLayout(zcu)) {
            .@"packed" => null,
            .auto, .@"extern" => .{ .non_packed_union = ty },
        },
    };
}

pub const ExternPosition = enum {
    ret_ty,
    param_ty,
    union_field,
    struct_field,
    element,
    other,
};

/// Returns true if `ty` is allowed in extern types.
/// Asserts that `ty` is fully resolved.
/// Keep in sync with `Sema.explainWhyTypeIsNotExtern`.
pub fn validateExtern(ty: Type, position: ExternPosition, zcu: *const Zcu) bool {
    ty.assertHasLayout(zcu);
    return switch (ty.zigTypeTag(zcu)) {
        .type,
        .comptime_float,
        .comptime_int,
        .enum_literal,
        .undefined,
        .null,
        .error_union,
        .error_set,
        .frame,
        => false,

        .void => switch (position) {
            .ret_ty,
            .union_field,
            .struct_field,
            .element,
            => true,
            .param_ty,
            .other,
            => false,
        },

        .noreturn => position == .ret_ty,

        .@"opaque",
        .bool,
        .float,
        .@"anyframe",
        => true,

        .pointer => {
            if (ty.isSlice(zcu)) return false;
            const child_ty = ty.childType(zcu);
            if (child_ty.zigTypeTag(zcu) == .@"fn") {
                return ty.isConstPtr(zcu) and validateExternCallconv(child_ty.fnCallingConvention(zcu));
            }
            return true;
        },
        .int => switch (ty.intInfo(zcu).bits) {
            0, 8, 16, 32, 64, 128 => true,
            else => false,
        },
        .@"fn" => {
            if (position != .other) return false;
            return validateExternCallconv(ty.fnCallingConvention(zcu));
        },
        .@"enum" => {
            const enum_obj = zcu.intern_pool.loadEnumType(ty.toIntern());
            return switch (enum_obj.int_tag_mode) {
                .auto => false,
                .explicit => Type.fromInterned(enum_obj.int_tag_type).validateExtern(position, zcu),
            };
        },
        .@"struct" => {
            if (ty.isTuple(zcu)) return false;
            const struct_obj = zcu.intern_pool.loadStructType(ty.toIntern());
            return switch (struct_obj.layout) {
                .auto => false,
                .@"extern" => true,
                .@"packed" => switch (struct_obj.packed_backing_mode) {
                    .auto => false,
                    .explicit => Type.fromInterned(struct_obj.packed_backing_int_type).validateExtern(position, zcu),
                },
            };
        },
        .@"union" => {
            const union_obj = zcu.intern_pool.loadUnionType(ty.toIntern());
            return switch (union_obj.layout) {
                .auto => false,
                .@"extern" => true,
                .@"packed" => switch (union_obj.packed_backing_mode) {
                    .auto => false,
                    .explicit => Type.fromInterned(union_obj.packed_backing_int_type).validateExtern(position, zcu),
                },
            };
        },
        .array => switch (position) {
            .ret_ty,
            .param_ty,
            => false,

            .union_field,
            .struct_field,
            .element,
            .other,
            => ty.childType(zcu).validateExtern(.element, zcu),
        },
        .vector => ty.childType(zcu).validateExtern(.element, zcu),
        .optional => ty.isPtrLikeOptional(zcu),
    };
}
fn validateExternCallconv(cc: std.builtin.CallingConvention) bool {
    return switch (cc) {
        // For now we want to authorize PTX kernel to use zig objects, even if we end up exposing the ABI.
        // The goal is to experiment with more integrated CPU/GPU code.
        .nvptx_kernel => true,
        else => !target_util.fnCallConvAllowsZigTypes(cc),
    };
}

/// Asserts that `ty` has resolved layout.
pub fn assertHasLayout(ty: Type, zcu: *const Zcu) void {
    if (!std.debug.runtime_safety) {
        // This early exit isn't necessary (`Zcu.assertUpToDate` checks `std.debug.runtime_safety`
        // itself), but LLVM has been observed to fail at optimizing away this safety check, which
        // has a major performance impact on ReleaseFast compiler builds.
        return;
    }
    switch (zcu.intern_pool.indexToKey(ty.toIntern())) {
        .int_type,
        .ptr_type,
        .anyframe_type,
        .simple_type,
        .opaque_type,
        .error_set_type,
        .inferred_error_set_type,
        => {},
        .func_type => |func_type| {
            for (func_type.param_types.get(&zcu.intern_pool)) |param_ty| {
                assertHasLayout(.fromInterned(param_ty), zcu);
            }
            assertHasLayout(.fromInterned(func_type.return_type), zcu);
        },
        .array_type => |arr| assertHasLayout(.fromInterned(arr.child), zcu),
        .vector_type => |vec| assertHasLayout(.fromInterned(vec.child), zcu),
        .opt_type => |child| assertHasLayout(.fromInterned(child), zcu),
        .error_union_type => |eu| assertHasLayout(.fromInterned(eu.payload_type), zcu),
        .tuple_type => |tuple| for (tuple.types.get(&zcu.intern_pool)) |field_ty| {
            assertHasLayout(.fromInterned(field_ty), zcu);
        },
        .struct_type => {
            assert(zcu.intern_pool.loadStructType(ty.toIntern()).want_layout);
            zcu.assertUpToDate(.wrap(.{ .type_layout = ty.toIntern() }));
        },
        .union_type => {
            assert(zcu.intern_pool.loadUnionType(ty.toIntern()).want_layout);
            zcu.assertUpToDate(.wrap(.{ .type_layout = ty.toIntern() }));
        },
        .enum_type => {
            assert(zcu.intern_pool.loadEnumType(ty.toIntern()).want_layout);
            zcu.assertUpToDate(.wrap(.{ .type_layout = ty.toIntern() }));
        },

        // values, not types
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
        .undef,
        // memoization, not types
        .memoized_call,
        => unreachable,
    }
}

/// Recursively walks the type and marks for each subtype how many times it has been seen
fn collectSubtypes(ty: Type, pt: Zcu.PerThread, visited: *std.AutoArrayHashMapUnmanaged(Type, u16)) error{OutOfMemory}!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    const gop = try visited.getOrPut(zcu.gpa, ty);
    if (gop.found_existing) {
        gop.value_ptr.* += 1;
    } else {
        gop.value_ptr.* = 1;
    }

    switch (ip.indexToKey(ty.toIntern())) {
        .ptr_type => try collectSubtypes(Type.fromInterned(ty.ptrInfo(zcu).child), pt, visited),
        .array_type => |array_type| try collectSubtypes(Type.fromInterned(array_type.child), pt, visited),
        .vector_type => |vector_type| try collectSubtypes(Type.fromInterned(vector_type.child), pt, visited),
        .opt_type => |child| try collectSubtypes(Type.fromInterned(child), pt, visited),
        .error_union_type => |error_union_type| {
            try collectSubtypes(Type.fromInterned(error_union_type.error_set_type), pt, visited);
            if (error_union_type.payload_type != .generic_poison_type) {
                try collectSubtypes(Type.fromInterned(error_union_type.payload_type), pt, visited);
            }
        },
        .tuple_type => |tuple| {
            for (tuple.types.get(ip)) |field_ty| {
                try collectSubtypes(Type.fromInterned(field_ty), pt, visited);
            }
        },
        .func_type => |fn_info| {
            const param_types = fn_info.param_types.get(&zcu.intern_pool);
            for (param_types) |param_ty| {
                if (param_ty != .generic_poison_type) {
                    try collectSubtypes(Type.fromInterned(param_ty), pt, visited);
                }
            }

            if (fn_info.return_type != .generic_poison_type) {
                try collectSubtypes(Type.fromInterned(fn_info.return_type), pt, visited);
            }
        },
        .anyframe_type => |child| try collectSubtypes(Type.fromInterned(child), pt, visited),

        // leaf types
        .undef,
        .inferred_error_set_type,
        .error_set_type,
        .struct_type,
        .union_type,
        .opaque_type,
        .enum_type,
        .simple_type,
        .int_type,
        => {},

        // values, not types
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
        // memoization, not types
        .memoized_call,
        => unreachable,
    }
}

fn shouldDedupeType(ty: Type, ctx: *Comparison, pt: Zcu.PerThread) error{OutOfMemory}!Comparison.DedupeEntry {
    if (ctx.type_occurrences.get(ty)) |occ| {
        if (ctx.type_dedupe_cache.get(ty)) |cached| {
            return cached;
        }

        var discarding: std.Io.Writer.Discarding = .init(&.{});

        print(ty, &discarding.writer, pt, null) catch
            unreachable; // we are writing into a discarding writer, it should never fail

        const type_len: i32 = @intCast(discarding.count);

        const placeholder_len: i32 = 1;
        const min_saved_bytes: i32 = 20;

        const saved_bytes = (type_len - placeholder_len) * (occ - 1);
        const max_placeholders = 7; // T to Z
        const should_dedupe = saved_bytes >= min_saved_bytes and ctx.placeholder_index < max_placeholders;

        const entry: Comparison.DedupeEntry = if (should_dedupe) b: {
            ctx.placeholder_index += 1;
            break :b .{ .dedupe = .{ .index = ctx.placeholder_index - 1 } };
        } else .dont_dedupe;

        try ctx.type_dedupe_cache.put(pt.zcu.gpa, ty, entry);

        return entry;
    } else {
        return .{ .dont_dedupe = {} };
    }
}

/// The comparison recursively walks all types given and notes how many times
/// each subtype occurs. It then while recursively printing decides for each
/// subtype whether to print the type inline or create a placeholder based on
/// the subtype length and number of occurences. Placeholders are then found by
/// iterating `type_dedupe_cache` which caches the inline/placeholder decisions.
pub const Comparison = struct {
    type_occurrences: std.AutoArrayHashMapUnmanaged(Type, u16),
    type_dedupe_cache: std.AutoArrayHashMapUnmanaged(Type, DedupeEntry),
    placeholder_index: u8,

    pub const Placeholder = struct {
        index: u8,

        pub fn format(p: Placeholder, writer: *std.Io.Writer) error{WriteFailed}!void {
            return writer.print("{c}", .{p.index + 'T'});
        }
    };

    pub const DedupeEntry = union(enum) {
        dont_dedupe: void,
        dedupe: Placeholder,
    };

    pub fn init(types: []const Type, pt: Zcu.PerThread) error{OutOfMemory}!Comparison {
        var cmp: Comparison = .{
            .type_occurrences = .empty,
            .type_dedupe_cache = .empty,
            .placeholder_index = 0,
        };

        errdefer cmp.deinit(pt);

        for (types) |ty| {
            try collectSubtypes(ty, pt, &cmp.type_occurrences);
        }

        return cmp;
    }

    pub fn deinit(cmp: *Comparison, pt: Zcu.PerThread) void {
        const gpa = pt.zcu.gpa;
        cmp.type_occurrences.deinit(gpa);
        cmp.type_dedupe_cache.deinit(gpa);
    }

    pub fn fmtType(ctx: *Comparison, ty: Type, pt: Zcu.PerThread) Comparison.Formatter {
        return .{ .ty = ty, .ctx = ctx, .pt = pt };
    }
    pub const Formatter = struct {
        ty: Type,
        ctx: *Comparison,
        pt: Zcu.PerThread,

        pub fn format(self: Comparison.Formatter, writer: anytype) error{WriteFailed}!void {
            print(self.ty, writer, self.pt, self.ctx) catch return error.WriteFailed;
        }
    };
};

pub const @"u0": Type = .{ .ip_index = .u0_type };
pub const @"u1": Type = .{ .ip_index = .u1_type };
pub const @"u8": Type = .{ .ip_index = .u8_type };
pub const @"u16": Type = .{ .ip_index = .u16_type };
pub const @"u29": Type = .{ .ip_index = .u29_type };
pub const @"u32": Type = .{ .ip_index = .u32_type };
pub const @"u64": Type = .{ .ip_index = .u64_type };
pub const @"u80": Type = .{ .ip_index = .u80_type };
pub const @"u128": Type = .{ .ip_index = .u128_type };
pub const @"u256": Type = .{ .ip_index = .u256_type };

pub const @"i8": Type = .{ .ip_index = .i8_type };
pub const @"i16": Type = .{ .ip_index = .i16_type };
pub const @"i32": Type = .{ .ip_index = .i32_type };
pub const @"i64": Type = .{ .ip_index = .i64_type };
pub const @"i128": Type = .{ .ip_index = .i128_type };

pub const @"f16": Type = .{ .ip_index = .f16_type };
pub const @"f32": Type = .{ .ip_index = .f32_type };
pub const @"f64": Type = .{ .ip_index = .f64_type };
pub const @"f80": Type = .{ .ip_index = .f80_type };
pub const @"f128": Type = .{ .ip_index = .f128_type };

pub const @"bool": Type = .{ .ip_index = .bool_type };
pub const @"usize": Type = .{ .ip_index = .usize_type };
pub const @"isize": Type = .{ .ip_index = .isize_type };
pub const @"comptime_int": Type = .{ .ip_index = .comptime_int_type };
pub const @"comptime_float": Type = .{ .ip_index = .comptime_float_type };
pub const @"void": Type = .{ .ip_index = .void_type };
pub const @"type": Type = .{ .ip_index = .type_type };
pub const @"anyerror": Type = .{ .ip_index = .anyerror_type };
pub const @"anyopaque": Type = .{ .ip_index = .anyopaque_type };
pub const @"anyframe": Type = .{ .ip_index = .anyframe_type };
pub const @"null": Type = .{ .ip_index = .null_type };
pub const @"undefined": Type = .{ .ip_index = .undefined_type };
pub const @"noreturn": Type = .{ .ip_index = .noreturn_type };
pub const enum_literal: Type = .{ .ip_index = .enum_literal_type };

pub const @"c_char": Type = .{ .ip_index = .c_char_type };
pub const @"c_short": Type = .{ .ip_index = .c_short_type };
pub const @"c_ushort": Type = .{ .ip_index = .c_ushort_type };
pub const @"c_int": Type = .{ .ip_index = .c_int_type };
pub const @"c_uint": Type = .{ .ip_index = .c_uint_type };
pub const @"c_long": Type = .{ .ip_index = .c_long_type };
pub const @"c_ulong": Type = .{ .ip_index = .c_ulong_type };
pub const @"c_longlong": Type = .{ .ip_index = .c_longlong_type };
pub const @"c_ulonglong": Type = .{ .ip_index = .c_ulonglong_type };
pub const @"c_longdouble": Type = .{ .ip_index = .c_longdouble_type };

pub const ptr_usize: Type = .{ .ip_index = .ptr_usize_type };
pub const ptr_const_comptime_int: Type = .{ .ip_index = .ptr_const_comptime_int_type };
pub const manyptr_u8: Type = .{ .ip_index = .manyptr_u8_type };
pub const manyptr_const_u8: Type = .{ .ip_index = .manyptr_const_u8_type };
pub const manyptr_const_u8_sentinel_0: Type = .{ .ip_index = .manyptr_const_u8_sentinel_0_type };
pub const slice_const_u8: Type = .{ .ip_index = .slice_const_u8_type };
pub const slice_const_u8_sentinel_0: Type = .{ .ip_index = .slice_const_u8_sentinel_0_type };
pub const slice_const_slice_const_u8: Type = .{ .ip_index = .slice_const_slice_const_u8_type };
pub const slice_const_type: Type = .{ .ip_index = .slice_const_type_type };
pub const optional_type: Type = .{ .ip_index = .optional_type_type };
pub const optional_noreturn: Type = .{ .ip_index = .optional_noreturn_type };

pub const vector_8_i8: Type = .{ .ip_index = .vector_8_i8_type };
pub const vector_16_i8: Type = .{ .ip_index = .vector_16_i8_type };
pub const vector_32_i8: Type = .{ .ip_index = .vector_32_i8_type };
pub const vector_64_i8: Type = .{ .ip_index = .vector_64_i8_type };
pub const vector_1_u8: Type = .{ .ip_index = .vector_1_u8_type };
pub const vector_2_u8: Type = .{ .ip_index = .vector_2_u8_type };
pub const vector_4_u8: Type = .{ .ip_index = .vector_4_u8_type };
pub const vector_8_u8: Type = .{ .ip_index = .vector_8_u8_type };
pub const vector_16_u8: Type = .{ .ip_index = .vector_16_u8_type };
pub const vector_32_u8: Type = .{ .ip_index = .vector_32_u8_type };
pub const vector_64_u8: Type = .{ .ip_index = .vector_64_u8_type };
pub const vector_2_i16: Type = .{ .ip_index = .vector_2_i16_type };
pub const vector_4_i16: Type = .{ .ip_index = .vector_4_i16_type };
pub const vector_8_i16: Type = .{ .ip_index = .vector_8_i16_type };
pub const vector_16_i16: Type = .{ .ip_index = .vector_16_i16_type };
pub const vector_32_i16: Type = .{ .ip_index = .vector_32_i16_type };
pub const vector_4_u16: Type = .{ .ip_index = .vector_4_u16_type };
pub const vector_8_u16: Type = .{ .ip_index = .vector_8_u16_type };
pub const vector_16_u16: Type = .{ .ip_index = .vector_16_u16_type };
pub const vector_32_u16: Type = .{ .ip_index = .vector_32_u16_type };
pub const vector_2_i32: Type = .{ .ip_index = .vector_2_i32_type };
pub const vector_4_i32: Type = .{ .ip_index = .vector_4_i32_type };
pub const vector_8_i32: Type = .{ .ip_index = .vector_8_i32_type };
pub const vector_16_i32: Type = .{ .ip_index = .vector_16_i32_type };
pub const vector_4_u32: Type = .{ .ip_index = .vector_4_u32_type };
pub const vector_8_u32: Type = .{ .ip_index = .vector_8_u32_type };
pub const vector_16_u32: Type = .{ .ip_index = .vector_16_u32_type };
pub const vector_2_i64: Type = .{ .ip_index = .vector_2_i64_type };
pub const vector_4_i64: Type = .{ .ip_index = .vector_4_i64_type };
pub const vector_8_i64: Type = .{ .ip_index = .vector_8_i64_type };
pub const vector_2_u64: Type = .{ .ip_index = .vector_2_u64_type };
pub const vector_4_u64: Type = .{ .ip_index = .vector_4_u64_type };
pub const vector_8_u64: Type = .{ .ip_index = .vector_8_u64_type };
pub const vector_1_u128: Type = .{ .ip_index = .vector_1_u128_type };
pub const vector_2_u128: Type = .{ .ip_index = .vector_2_u128_type };
pub const vector_1_u256: Type = .{ .ip_index = .vector_1_u256_type };
pub const vector_4_f16: Type = .{ .ip_index = .vector_4_f16_type };
pub const vector_8_f16: Type = .{ .ip_index = .vector_8_f16_type };
pub const vector_16_f16: Type = .{ .ip_index = .vector_16_f16_type };
pub const vector_32_f16: Type = .{ .ip_index = .vector_32_f16_type };
pub const vector_2_f32: Type = .{ .ip_index = .vector_2_f32_type };
pub const vector_4_f32: Type = .{ .ip_index = .vector_4_f32_type };
pub const vector_8_f32: Type = .{ .ip_index = .vector_8_f32_type };
pub const vector_16_f32: Type = .{ .ip_index = .vector_16_f32_type };
pub const vector_2_f64: Type = .{ .ip_index = .vector_2_f64_type };
pub const vector_4_f64: Type = .{ .ip_index = .vector_4_f64_type };
pub const vector_8_f64: Type = .{ .ip_index = .vector_8_f64_type };

pub const empty_tuple: Type = .{ .ip_index = .empty_tuple_type };

pub const generic_poison: Type = .{ .ip_index = .generic_poison_type };

pub fn smallestUnsignedBits(max: u64) u16 {
    return switch (max) {
        0 => 0,
        else => @as(u16, 1) + std.math.log2_int(u64, max),
    };
}

/// This is only used for comptime asserts. Bump this number when you make a change
/// to packed struct layout to find out all the places in the codebase you need to edit!
pub const packed_struct_layout_version = 2;

fn cTypeAlign(target: *const Target, c_type: Target.CType) Alignment {
    return Alignment.fromByteUnits(target.cTypeAlignment(c_type));
}
