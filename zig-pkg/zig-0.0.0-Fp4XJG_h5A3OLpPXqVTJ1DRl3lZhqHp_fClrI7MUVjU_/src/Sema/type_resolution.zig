const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

const Sema = @import("../Sema.zig");
const Block = Sema.Block;
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const Zcu = @import("../Zcu.zig");
const CompileError = Zcu.CompileError;
const SemaError = Zcu.SemaError;
const LazySrcLoc = Zcu.LazySrcLoc;
const InternPool = @import("../InternPool.zig");
const Alignment = InternPool.Alignment;
const arith = @import("arith.zig");

pub const LayoutResolveReason = enum {
    variable,
    constant,
    parameter,
    return_type,
    field,
    backing_enum,
    init,
    coerce,
    ptr_access,
    ptr_offset,
    field_used,
    field_queried,
    size_of,
    align_of,
    type_info,
    align_check,
    bit_ptr_child,
    @"export",
    @"extern",
    asm_out_type,
    builtin_type,

    /// Written after string: "while resolving type 'T' "
    /// e.g. "while resolving type 'MyStruct' for variable declared here"
    pub fn msg(r: LayoutResolveReason) []const u8 {
        return switch (r) {
            // zig fmt: off
            .variable      => "for variable declared here",
            .constant      => "for constant declared here",
            .parameter     => "for function parameter declared here",
            .return_type   => "for function return type declared here",
            .field         => "for field declared here",
            .backing_enum  => "for backing enum type declared here",
            .init          => "for initialization performed here",
            .coerce        => "for coercion performed here",
            .ptr_access    => "for pointer access here",
            .ptr_offset    => "for pointer offset here",
            .field_used    => "for field usage here",
            .field_queried => "for field query here",
            .size_of       => "for size query here",
            .align_of      => "for alignment query here",
            .type_info     => "for type information query here",
            .align_check   => "for alignment check here",
            .bit_ptr_child => "for bit size check here",
            .@"export"     => "for export here",
            .@"extern"     => "for extern declaration here",
            .asm_out_type  => "for inline assembly output type declared here",
            .builtin_type  => "from 'std.builtin'",
            // zig fmt: on
        };
    }
};

/// Ensures that `ty` has known layout, including alignment, size, and (where relevant) field offsets.
/// `ty` may be any type; its layout is resolved *recursively* if necessary.
/// Adds incremental dependencies tracking any required type resolution.
pub fn ensureLayoutResolved(sema: *Sema, ty: Type, src: LazySrcLoc, reason: LayoutResolveReason) SemaError!void {
    return ensureLayoutResolvedInner(sema, ty, ty, &.{
        .src = src,
        .type_layout_reason = reason,
    });
}
fn ensureLayoutResolvedInner(sema: *Sema, ty: Type, orig_ty: Type, reason: *const Zcu.DependencyReason) SemaError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(ty.toIntern())) {
        .int_type,
        .ptr_type,
        .anyframe_type,
        .simple_type,
        .opaque_type,
        .error_set_type,
        .inferred_error_set_type,
        => {},

        .func_type => |func_type| {
            for (func_type.param_types.get(ip)) |param_ty| {
                try ensureLayoutResolvedInner(sema, .fromInterned(param_ty), orig_ty, reason);
            }
            try ensureLayoutResolvedInner(sema, .fromInterned(func_type.return_type), orig_ty, reason);
        },

        .array_type => |arr| return ensureLayoutResolvedInner(sema, .fromInterned(arr.child), orig_ty, reason),
        .vector_type => |vec| return ensureLayoutResolvedInner(sema, .fromInterned(vec.child), orig_ty, reason),
        .opt_type => |child| return ensureLayoutResolvedInner(sema, .fromInterned(child), orig_ty, reason),
        .error_union_type => |eu| return ensureLayoutResolvedInner(sema, .fromInterned(eu.payload_type), orig_ty, reason),
        .tuple_type => |tuple| for (tuple.types.get(ip)) |field_ty| {
            try ensureLayoutResolvedInner(sema, .fromInterned(field_ty), orig_ty, reason);
        },
        .struct_type, .union_type, .enum_type => {
            try sema.declareDependency(.{ .type_layout = ty.toIntern() });
            try sema.addReferenceEntry(null, reason.src, .wrap(.{ .type_layout = ty.toIntern() }));
            if (zcu.analysis_in_progress.contains(.wrap(.{ .type_layout = ty.toIntern() }))) {
                return sema.failWithDependencyLoop(.wrap(.{ .type_layout = ty.toIntern() }), reason);
            }
            try pt.ensureTypeLayoutUpToDate(ty, reason);
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
    }
}

/// Asserts that `ty` is a non-tuple `struct` type, and ensures that its fields' default values
/// are resolved. Adds incremental dependencies tracking the required type resolution.
///
/// It is not necessary to call this function to query the values of comptime fields: those values
/// are available from type *layout* resolution, see `ensureLayoutResolved`.
///
/// Asserts that the *layout* of `ty` has already been resolved---see `ensureLayoutResolved`.
pub fn ensureStructDefaultsResolved(sema: *Sema, ty: Type, src: LazySrcLoc) SemaError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    assert(ip.indexToKey(ty.toIntern()) == .struct_type);
    ty.assertHasLayout(zcu);

    try sema.declareDependency(.{ .struct_defaults = ty.toIntern() });
    try sema.addReferenceEntry(null, src, .wrap(.{ .struct_defaults = ty.toIntern() }));

    const reason: Zcu.DependencyReason = .{ .src = src, .type_layout_reason = undefined };

    if (zcu.analysis_in_progress.contains(.wrap(.{ .struct_defaults = ty.toIntern() }))) {
        return sema.failWithDependencyLoop(.wrap(.{ .struct_defaults = ty.toIntern() }), &reason);
    }

    try pt.ensureStructDefaultsUpToDate(ty, &reason);
}

/// Asserts that `struct_ty` is a non-packed non-tuple struct, and that `sema.owner` is that type.
/// This function *does* register the `src_hash` dependency on the struct.
pub fn resolveStructLayout(sema: *Sema, struct_ty: Type) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    assert(sema.owner.unwrap().type_layout == struct_ty.toIntern());

    const struct_obj = ip.loadStructType(struct_ty.toIntern());
    assert(struct_obj.want_layout);
    const zir_index = struct_obj.zir_index.resolve(ip) orelse return error.AnalysisFail;

    var block: Block = .{
        .parent = null,
        .sema = sema,
        .namespace = struct_obj.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = undefined, // always set before using `block`
        .src_base_inst = struct_obj.zir_index,
        .type_name_ctx = struct_obj.name,
    };
    defer block.instructions.deinit(gpa);

    // There may be old field names in here from a previous update.
    struct_obj.field_name_map.get(ip).clearRetainingCapacity();

    if (struct_obj.is_reified) {
        // The field names are populated, but we haven't checked for duplicates (nor populated the map) yet.
        for (0..struct_obj.field_names.len) |field_index| {
            const name = struct_obj.field_names.get(ip)[field_index];
            if (ip.addFieldName(struct_obj.field_names, struct_obj.field_name_map, name)) |prev_field_index| {
                return sema.failWithOwnedErrorMsg(&block, msg: {
                    const src = block.builtinCallArgSrc(.zero, 2);
                    const msg = try sema.errMsg(src, "duplicate struct field '{f}' at index '{d}", .{ name.fmt(ip), field_index });
                    errdefer msg.destroy(gpa);
                    try sema.errNote(src, msg, "previous field at index '{d}'", .{prev_field_index});
                    break :msg msg;
                });
            }
        }
    } else {
        // Declared structs do not yet have field information populated:
        // * field names
        // * field comptime-ness
        // * field types
        // * field aligns
        // It's our job to populate these now.
        try sema.declareDependency(.{ .src_hash = struct_obj.zir_index });

        // Likewise, comptime bits may be set. We clear them all first because it avoids needing
        // "unset bit with AND" logic below (instead we only need the "set bit with OR" case).
        @memset(struct_obj.field_is_comptime_bits.getAll(ip), 0);

        const zir_struct = sema.code.getStructDecl(zir_index);
        var field_it = zir_struct.iterateFields();
        var any_comptime_fields = false;
        while (field_it.next()) |zir_field| {
            {
                const name_slice = sema.code.nullTerminatedString(zir_field.name);
                const name = try ip.getOrPutString(gpa, io, pt.tid, name_slice, .no_embedded_nulls);
                assert(ip.addFieldName(struct_obj.field_names, struct_obj.field_name_map, name) == null); // AstGen validated this for us
            }

            if (zir_field.is_comptime) {
                const bit_bag_index = zir_field.idx / 32;
                const mask = @as(u32, 1) << @intCast(zir_field.idx % 32);
                struct_obj.field_is_comptime_bits.getAll(ip)[bit_bag_index] |= mask;
                any_comptime_fields = true;
            }

            {
                const field_ty_src = block.src(.{ .container_field_type = zir_field.idx });
                const field_ty: Type = field_ty: {
                    block.comptime_reason = .{ .reason = .{
                        .src = field_ty_src,
                        .r = .{ .simple = .struct_field_types },
                    } };
                    const type_ref = try sema.resolveInlineBody(&block, zir_field.type_body, zir_index);
                    break :field_ty try sema.analyzeAsType(&block, field_ty_src, .struct_field_types, type_ref);
                };
                struct_obj.field_types.get(ip)[zir_field.idx] = field_ty.toIntern();
            }

            if (struct_obj.field_aligns.len == 0) {
                assert(zir_field.align_body == null);
            } else {
                const field_align_src = block.src(.{ .container_field_align = zir_field.idx });
                const field_align: Alignment = a: {
                    block.comptime_reason = .{ .reason = .{
                        .src = field_align_src,
                        .r = .{ .simple = .struct_field_attrs },
                    } };
                    const align_body = zir_field.align_body orelse break :a .none;
                    const align_ref = try sema.resolveInlineBody(&block, align_body, zir_index);
                    break :a try sema.analyzeAsAlign(&block, field_align_src, align_ref);
                };
                struct_obj.field_aligns.get(ip)[zir_field.idx] = field_align;
            }
        }

        // We also resolve the default values of any `comptime` fields now. This is not necessary in
        // the case of a reified struct because the the default values were already poulated and
        // validated by `Sema.zirReifyStruct`.
        if (any_comptime_fields) {
            try resolveStructDefaultsInner(sema, &block, &struct_obj, .comptime_fields);
        }
    }

    if (struct_obj.layout == .@"packed") {
        return resolvePackedStructLayout(sema, &block, struct_ty, &struct_obj);
    }

    // Resolve the layout of all fields, and check their types are allowed.
    for (struct_obj.field_types.get(ip), 0..) |field_ty_ip, field_index| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        assert(!field_ty.isGenericPoison());
        const field_ty_src = block.src(.{ .container_field_type = @intCast(field_index) });
        try sema.ensureLayoutResolved(field_ty, field_ty_src, .field);
        if (field_ty.zigTypeTag(zcu) == .@"opaque") {
            return sema.failWithOwnedErrorMsg(&block, msg: {
                const msg = try sema.errMsg(field_ty_src, "cannot directly embed opaque type '{f}' in struct", .{field_ty.fmt(pt)});
                errdefer msg.destroy(gpa);
                try sema.errNote(field_ty_src, msg, "opaque types have unknown size", .{});
                try sema.addDeclaredHereNote(msg, field_ty);
                break :msg msg;
            });
        }
        if (struct_obj.layout == .@"extern" and !field_ty.validateExtern(.struct_field, zcu)) {
            return sema.failWithOwnedErrorMsg(&block, msg: {
                const msg = try sema.errMsg(field_ty_src, "extern structs cannot contain fields of type '{f}'", .{field_ty.fmt(pt)});
                errdefer msg.destroy(gpa);
                try sema.explainWhyTypeIsNotExtern(msg, field_ty_src, field_ty, .struct_field);
                try sema.addDeclaredHereNote(msg, field_ty);
                break :msg msg;
            });
        }
    }

    // Fields are okay. Now we need to resolve the struct's overall layout (size, field offsets, etc).

    var any_comptime_fields = false;
    var struct_align: Alignment = .@"1";
    var has_no_possible_value = false;
    var has_runtime_state = false;
    var has_comptime_state = false;
    // Unlike `struct_obj.field_aligns`, these are not `.none`.
    const resolved_field_aligns = try sema.arena.alloc(Alignment, struct_obj.field_names.len);
    for (resolved_field_aligns, 0..) |*align_out, field_idx| {
        const field_ty: Type = .fromInterned(struct_obj.field_types.get(ip)[field_idx]);
        const field_align: Alignment = a: {
            if (struct_obj.field_aligns.len != 0) {
                const a = struct_obj.field_aligns.get(ip)[field_idx];
                if (a != .none) break :a a;
            }
            break :a field_ty.defaultStructFieldAlignment(struct_obj.layout, zcu);
        };
        align_out.* = field_align;
        if (struct_obj.field_is_comptime_bits.get(ip, field_idx)) {
            assert(struct_obj.layout == .auto); // comptime fields not allowed in extern or packed structs
            struct_obj.field_runtime_order.get(ip)[field_idx] = .omitted; // comptime fields are not in the runtime order
            any_comptime_fields = true;
            continue; // `comptime` fields do not contribute to the struct layout
        }
        struct_align = struct_align.maxStrict(field_align);
        if (struct_obj.layout == .auto) {
            struct_obj.field_runtime_order.get(ip)[field_idx] = @enumFromInt(field_idx);
        }
        switch (field_ty.classify(zcu)) {
            .one_possible_value => {},
            .no_possible_value => has_no_possible_value = true,
            .runtime => has_runtime_state = true,
            .fully_comptime => has_comptime_state = true,
            .partially_comptime => {
                has_runtime_state = true;
                has_comptime_state = true;
            },
        }
    }
    const class: Type.Class = class: {
        if (has_no_possible_value) break :class .no_possible_value;
        if (has_comptime_state) {
            break :class if (has_runtime_state) .partially_comptime else .fully_comptime;
        } else {
            break :class if (has_runtime_state) .runtime else .one_possible_value;
        }
    };

    switch (struct_obj.layout) {
        .auto => {},
        .@"extern" => assert(class != .no_possible_value), // field types are all extern, so are not NPV
        .@"packed" => unreachable,
    }

    if (struct_obj.layout == .auto) {
        const runtime_order = struct_obj.field_runtime_order.get(ip);
        // This logic does not reorder fields; it only moves the omitted ones to the end so that logic
        // elsewhere does not need to special-case. TODO: support field reordering in all the backends!
        if (!zcu.backendSupportsFeature(.field_reordering)) {
            var i: usize = 0;
            var off: usize = 0;
            while (i + off < runtime_order.len) {
                if (runtime_order[i + off] == .omitted) {
                    off += 1;
                } else {
                    runtime_order[i] = runtime_order[i + off];
                    i += 1;
                }
            }
        } else {
            // Sort by descending alignment to minimize padding.
            const RuntimeOrder = InternPool.LoadedStructType.RuntimeOrder;
            const AlignSortCtx = struct {
                aligns: []const Alignment,
                fn lessThan(ctx: @This(), a: RuntimeOrder, b: RuntimeOrder) bool {
                    assert(a != .unresolved);
                    assert(b != .unresolved);
                    if (a == .omitted) return false;
                    if (b == .omitted) return true;
                    const a_align = ctx.aligns[@intFromEnum(a)];
                    const b_align = ctx.aligns[@intFromEnum(b)];
                    return a_align.compare(.gt, b_align);
                }
            };
            mem.sortUnstable(
                RuntimeOrder,
                runtime_order,
                @as(AlignSortCtx, .{ .aligns = resolved_field_aligns }),
                AlignSortCtx.lessThan,
            );
        }
    }

    var runtime_order_it = struct_obj.iterateRuntimeOrder(ip);
    var cur_offset: u64 = 0;
    while (runtime_order_it.next()) |field_idx| {
        const field_ty: Type = .fromInterned(struct_obj.field_types.get(ip)[field_idx]);
        const offset = resolved_field_aligns[field_idx].forward(cur_offset);
        struct_obj.field_offsets.get(ip)[field_idx] = @truncate(offset); // truncate because the overflow is handled below
        cur_offset = offset + field_ty.abiSize(zcu);
    }
    const struct_size: u32 = switch (class) {
        .no_possible_value => 0,
        else => std.math.cast(u32, struct_align.forward(cur_offset)) orelse return sema.fail(
            &block,
            struct_ty.srcLoc(zcu),
            "struct layout requires size {d}, this compiler implementation supports up to {d}",
            .{ struct_align.forward(cur_offset), std.math.maxInt(u32) },
        ),
    };
    ip.resolveStructLayout(
        io,
        struct_ty.toIntern(),
        struct_size,
        struct_align,
        class,
    );
}

/// Asserts that `struct_ty` is a packed struct, and that `sema.owner` is that type.
/// This function *does* register the `src_hash` dependency on the struct.
fn resolvePackedStructLayout(
    sema: *Sema,
    block: *Block,
    struct_ty: Type,
    struct_obj: *const InternPool.LoadedStructType,
) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    // Resolve the layout of all fields, and check their types are allowed.
    // Also count the number of bits while we're at it.
    var field_bits: u64 = 0;
    for (struct_obj.field_types.get(ip), 0..) |field_ty_ip, field_index| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        assert(!field_ty.isGenericPoison());
        const field_ty_src = block.src(.{ .container_field_type = @intCast(field_index) });
        try sema.ensureLayoutResolved(field_ty, field_ty_src, .field);
        if (field_ty.zigTypeTag(zcu) == .@"opaque") {
            return sema.failWithOwnedErrorMsg(block, msg: {
                const msg = try sema.errMsg(field_ty_src, "cannot directly embed opaque type '{f}' in struct", .{field_ty.fmt(pt)});
                errdefer msg.destroy(gpa);
                try sema.errNote(field_ty_src, msg, "opaque types have unknown size", .{});
                try sema.addDeclaredHereNote(msg, field_ty);
                break :msg msg;
            });
        }
        if (field_ty.unpackable(zcu)) |reason| return sema.failWithOwnedErrorMsg(block, msg: {
            const msg = try sema.errMsg(field_ty_src, "packed structs cannot contain fields of type '{f}'", .{field_ty.fmt(pt)});
            errdefer msg.destroy(gpa);
            try sema.explainWhyTypeIsUnpackable(msg, field_ty_src, reason);
            break :msg msg;
        });
        switch (field_ty.classify(zcu)) {
            .one_possible_value, .runtime => {},
            .no_possible_value => unreachable, // packable types are not NPV
            .partially_comptime => unreachable, // packable types are not comptime-only
            .fully_comptime => unreachable, // packable types are not comptime-only
        }
        field_bits += field_ty.bitSize(zcu);
    }

    const explicit_backing_int_ty: ?Type = if (struct_obj.is_reified) ty: {
        break :ty switch (struct_obj.packed_backing_mode) {
            .explicit => .fromInterned(struct_obj.packed_backing_int_type),
            .auto => null,
        };
    } else ty: {
        const zir_index = struct_obj.zir_index.resolve(ip).?;
        const zir_struct = sema.code.getStructDecl(zir_index);
        const backing_int_type_body = zir_struct.backing_int_type_body orelse {
            break :ty null; // inferred backing type
        };
        // Explicitly specified, so evaluate the backing int type expression.
        const backing_int_type_src = block.src(.container_arg);
        block.comptime_reason = .{ .reason = .{
            .src = backing_int_type_src,
            .r = .{ .simple = .packed_struct_backing_int_type },
        } };
        const type_ref = try sema.resolveInlineBody(block, backing_int_type_body, zir_index);
        break :ty try sema.analyzeAsType(block, backing_int_type_src, .packed_struct_backing_int_type, type_ref);
    };

    // Finally, either validate or infer the backing int type.
    const backing_int_ty: Type = if (explicit_backing_int_ty) |backing_ty| ty: {
        if (backing_ty.zigTypeTag(zcu) != .int) return sema.fail(
            block,
            block.src(.container_arg),
            "expected backing integer type, found '{f}'",
            .{backing_ty.fmt(pt)},
        );
        if (field_bits != backing_ty.intInfo(zcu).bits) return sema.failWithOwnedErrorMsg(block, msg: {
            const src = struct_ty.srcLoc(zcu);
            const msg = try sema.errMsg(src, "backing integer bit width does not match total bit width of fields", .{});
            errdefer msg.destroy(gpa);
            try sema.errNote(
                block.src(.container_arg),
                msg,
                "backing integer '{f}' has bit width '{d}'",
                .{ backing_ty.fmt(pt), backing_ty.bitSize(zcu) },
            );
            try sema.errNote(src, msg, "struct fields have total bit width '{d}'", .{field_bits});
            break :msg msg;
        });
        break :ty backing_ty;
    } else ty: {
        // We need to generate the inferred tag.
        const backing_int_bits = std.math.cast(u16, field_bits) orelse return sema.fail(
            block,
            struct_ty.srcLoc(zcu),
            "packed struct bit width '{d}' exceeds maximum bit width of 65535",
            .{field_bits},
        );
        break :ty try pt.intType(.unsigned, backing_int_bits);
    };
    ip.resolvePackedStructLayout(
        io,
        struct_ty.toIntern(),
        backing_int_ty.toIntern(),
    );
}

/// Asserts that `struct_ty` is a non-tuple struct, and that `sema.owner` is that type.
///
/// Also asserts that the layout of `struct_ty` has *already* been resolved (though it is okay for
/// that resolution to have failed). This requirement exists to ensure better error messages in the
/// event of a dependency loop.
///
/// This function *does* register the `src_hash` dependency on the struct.
pub fn resolveStructDefaults(sema: *Sema, struct_ty: Type) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    assert(sema.owner.unwrap().struct_defaults == struct_ty.toIntern());

    // We always depend on the layout of `struct_ty`. However, we don't actually need to resolve it
    // now, because the caller has done so for us. Just mark the dependency so that the incremental
    // compilation handling understands the dependency graph.
    try sema.declareDependency(.{ .type_layout = struct_ty.toIntern() });
    struct_ty.assertHasLayout(zcu);
    const layout_unit: InternPool.AnalUnit = .wrap(.{ .type_layout = struct_ty.toIntern() });
    if (zcu.failed_analysis.contains(layout_unit) or zcu.transitive_failed_analysis.contains(layout_unit)) {
        return error.AnalysisFail;
    }

    const struct_obj = ip.loadStructType(struct_ty.toIntern());
    assert(struct_obj.want_layout);

    if (struct_obj.is_reified) {
        // `Sema.zirReifyStruct` has already populated the default field values *and* (by loading
        // the default values from pointers) validated their types, so we have nothing to do.
        return;
    }

    try sema.declareDependency(.{ .src_hash = struct_obj.zir_index });

    if (struct_obj.field_defaults.len == 0) {
        // The struct has no default field values, so the slice has been omitted.
        return;
    }

    var block: Block = .{
        .parent = null,
        .sema = sema,
        .namespace = struct_obj.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = undefined, // always set before using `block`
        .src_base_inst = struct_obj.zir_index,
        .type_name_ctx = struct_obj.name,
    };
    defer block.instructions.deinit(gpa);

    return resolveStructDefaultsInner(sema, &block, &struct_obj, .normal_fields);
}

/// Asserts that the struct is not reified, and that `struct_obj.field_defaults.len` is non-zero.
fn resolveStructDefaultsInner(
    sema: *Sema,
    block: *Block,
    struct_obj: *const InternPool.LoadedStructType,
    mode: enum { comptime_fields, normal_fields },
) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    assert(struct_obj.field_defaults.len > 0);

    // We'll need to map the struct decl instruction to provide result types
    const zir_index = struct_obj.zir_index.resolve(ip) orelse return error.AnalysisFail;
    try sema.inst_map.ensureSpaceForInstructions(gpa, &.{zir_index});

    const field_types = struct_obj.field_types.get(ip);

    const zir_struct = sema.code.getStructDecl(zir_index);
    var field_it = zir_struct.iterateFields();
    while (field_it.next()) |zir_field| {
        switch (mode) {
            .comptime_fields => if (!zir_field.is_comptime) continue,
            .normal_fields => if (zir_field.is_comptime) continue,
        }

        const default_val_src = block.src(.{ .container_field_value = zir_field.idx });
        block.comptime_reason = .{ .reason = .{
            .src = default_val_src,
            .r = .{ .simple = .struct_field_default_value },
        } };
        const default_body = zir_field.default_body orelse {
            struct_obj.field_defaults.get(ip)[zir_field.idx] = .none;
            continue;
        };
        const field_ty: Type = .fromInterned(field_types[zir_field.idx]);
        const uncoerced = ref: {
            // Provide the result type
            sema.inst_map.putAssumeCapacity(zir_index, .fromIntern(field_ty.toIntern()));
            defer assert(sema.inst_map.remove(zir_index));
            break :ref try sema.resolveInlineBody(block, default_body, zir_index);
        };
        const coerced = try sema.coerce(block, field_ty, uncoerced, default_val_src);
        const default_val = try sema.resolveConstValue(block, default_val_src, coerced, null);
        if (default_val.canMutateComptimeVarState(zcu)) {
            const field_name = struct_obj.field_names.get(ip)[zir_field.idx];
            return sema.failWithContainsReferenceToComptimeVar(block, default_val_src, field_name, "field default value", default_val);
        }
        struct_obj.field_defaults.get(ip)[zir_field.idx] = default_val.toIntern();
    }
}

/// This logic must be kept in sync with `Type.getUnionLayout`.
pub fn resolveUnionLayout(sema: *Sema, union_ty: Type) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    assert(sema.owner.unwrap().type_layout == union_ty.toIntern());

    const union_obj = ip.loadUnionType(union_ty.toIntern());
    assert(union_obj.want_layout);
    const zir_index = union_obj.zir_index.resolve(ip) orelse return error.AnalysisFail;

    var block: Block = .{
        .parent = null,
        .sema = sema,
        .namespace = union_obj.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = undefined, // always set before using `block`
        .src_base_inst = union_obj.zir_index,
        .type_name_ctx = union_obj.name,
    };
    defer block.instructions.deinit(gpa);

    const enum_tag_ty: Type = switch (union_obj.enum_tag_mode) {
        .explicit => validated_tag_ty: {
            // If the union is reified, its enum tag type is already populated. If the union is
            // declared, we need to evaluate the enum tag type expression (the `E` in `union(E)`).
            const tag_ty: Type = switch (union_obj.is_reified) {
                true => .fromInterned(union_obj.enum_tag_type),
                false => tag_ty: {
                    const zir_union = sema.code.getUnionDecl(zir_index);
                    assert(zir_union.kind == .tagged_explicit); // `Zcu.mapOldZirToNew` guarantees that the ZIR mapping preserves `kind`
                    const tag_type_body = zir_union.arg_type_body.?;
                    const tag_type_src = block.src(.container_arg);
                    block.comptime_reason = .{ .reason = .{
                        .src = tag_type_src,
                        .r = .{ .simple = .union_enum_tag_type },
                    } };
                    const type_ref = try sema.resolveInlineBody(&block, tag_type_body, zir_index);
                    break :tag_ty try sema.analyzeAsType(&block, tag_type_src, .union_enum_tag_type, type_ref);
                },
            };
            // Because the type is explicitly specified, we need to validate it.
            if (tag_ty.zigTypeTag(zcu) != .@"enum") return sema.fail(
                &block,
                block.src(.container_arg),
                "expected enum tag type, found '{f}'",
                .{tag_ty.fmt(pt)},
            );
            break :validated_tag_ty tag_ty;
        },
        // If no tag type was specified, we generate one keyed on this union type.
        .auto => switch (try ip.getGeneratedEnumTagType(gpa, io, pt.tid, .{
            .union_type = union_ty.toIntern(),
            // The int tag for this enum is usually inferred---the exception is `union(enum(T))`.
            .int_tag_mode = switch (union_obj.is_reified) {
                true => .auto,
                false => switch (sema.code.getUnionDecl(zir_index).kind) {
                    .tagged_enum_explicit => .explicit,
                    else => .auto,
                },
            },
            .fields_len = @intCast(union_obj.field_types.len),
        })) {
            .existing => |tag_ty| .fromInterned(tag_ty),
            .wip => |wip| tag_ty: {
                errdefer wip.cancel(ip, pt.tid);
                _ = wip.setName(ip, try ip.getOrPutStringFmt(
                    gpa,
                    io,
                    pt.tid,
                    "@typeInfo({f}).@\"union\".tag_type.?",
                    .{union_obj.name.fmt(ip)},
                    .no_embedded_nulls,
                ), .none);
                const new_namespace_index: InternPool.NamespaceIndex = try pt.createNamespace(.{
                    .parent = union_obj.namespace.toOptional(),
                    .owner_type = wip.index,
                    .file_scope = zcu.namespacePtr(union_obj.namespace).file_scope,
                    .generation = zcu.generation,
                });
                if (comp.debugIncremental()) try zcu.incremental_debug_state.newType(zcu, wip.index);
                break :tag_ty .fromInterned(wip.finish(ip, new_namespace_index));
            },
        },
    };

    try sema.ensureLayoutResolved(enum_tag_ty, block.src(.container_arg), .backing_enum);
    const enum_obj = ip.loadEnumType(enum_tag_ty.toIntern());

    if (union_obj.is_reified) {
        // We have field names in `union_obj.reified_field_names`, but we haven't
        // checked them against the backing type yet.
        const union_field_names = union_obj.reified_field_names.get(ip);
        match_fields: {
            // We can efficiently *check* if the fields match...
            if (union_field_names.len == enum_obj.field_names.len) {
                for (union_field_names, enum_obj.field_names.get(ip)) |union_field_name, enum_field_name| {
                    if (!std.mem.eql(u8, union_field_name.toSlice(ip), enum_field_name.toSlice(ip))) break;
                } else {
                    break :match_fields;
                }
            }
            // ...but if they don't, reporting a nice error is a little more involved. If some field
            // is present in the enum but not the union, or vice versa, we will report that instead
            // of a generic "field order mismatch" error. Of course, this error is impossible for a
            // generated tag type, because we populated that from the union ZIR!
            assert(enum_obj.owner_union != union_ty.toIntern());
            return failUnionFieldMismatch(sema, &block, union_field_names, enum_tag_ty, &enum_obj);
        }
    } else {
        // Declared unions do not have field types or aligns populated yet.
        // We also need to check the field names match the backing enum.
        try sema.declareDependency(.{ .src_hash = union_obj.zir_index });
        const zir_union = sema.code.getUnionDecl(zir_index);

        // We'll first check the field names against the backing enum, and only analyze the types
        // once we know the fields match one-to-one.
        match_fields: {
            // We can efficiently *check* if the fields match...
            if (zir_union.field_names.len == enum_obj.field_names.len) {
                for (zir_union.field_names, enum_obj.field_names.get(ip)) |union_field_name_zir, enum_field_name| {
                    const union_field_name_slice = sema.code.nullTerminatedString(union_field_name_zir);
                    if (!std.mem.eql(u8, union_field_name_slice, enum_field_name.toSlice(ip))) break;
                } else {
                    break :match_fields;
                }
            }
            // ...but if they don't, reporting a nice error is a little more involved. If some field
            // is present in the enum but not the union, or vice versa, we will report that instead
            // of a generic "field order mismatch" error. Of course, this error is impossible for a
            // generated tag type, because we populated that from the union ZIR!
            assert(enum_obj.owner_union != union_ty.toIntern());
            const union_field_names = try sema.arena.alloc(InternPool.NullTerminatedString, zir_union.field_names.len);
            for (zir_union.field_names, union_field_names) |name_zir, *name| {
                name.* = try ip.getOrPutString(gpa, io, pt.tid, sema.code.nullTerminatedString(name_zir), .no_embedded_nulls);
            }
            return failUnionFieldMismatch(sema, &block, union_field_names, enum_tag_ty, &enum_obj);
        }

        // Field names okay; populate types and aligns.
        var field_it = zir_union.iterateFields();
        while (field_it.next()) |zir_field| {
            const field_ty_src = block.src(.{ .container_field_type = zir_field.idx });
            const field_ty: Type = field_ty: {
                block.comptime_reason = .{ .reason = .{
                    .src = field_ty_src,
                    .r = .{ .simple = .union_field_types },
                } };
                const type_body = zir_field.type_body orelse break :field_ty .void;
                const type_ref = try sema.resolveInlineBody(&block, type_body, zir_index);
                break :field_ty try sema.analyzeAsType(&block, field_ty_src, .union_field_types, type_ref);
            };
            union_obj.field_types.get(ip)[zir_field.idx] = field_ty.toIntern();

            const field_align_src = block.src(.{ .container_field_align = zir_field.idx });
            const explicit_field_align: Alignment = a: {
                block.comptime_reason = .{ .reason = .{
                    .src = field_align_src,
                    .r = .{ .simple = .union_field_attrs },
                } };
                const align_body = zir_field.align_body orelse break :a .none;
                const align_ref = try sema.resolveInlineBody(&block, align_body, zir_index);
                break :a try sema.analyzeAsAlign(&block, field_align_src, align_ref);
            };
            if (union_obj.field_aligns.len != 0) {
                union_obj.field_aligns.get(ip)[zir_field.idx] = explicit_field_align;
            } else {
                assert(explicit_field_align == .none);
            }
        }
    }

    if (union_obj.layout == .@"packed") {
        return resolvePackedUnionLayout(sema, &block, union_ty, &union_obj, enum_tag_ty);
    }

    // Resolve the layout of all fields, and check their types are allowed.
    for (union_obj.field_types.get(ip), 0..) |field_ty_ip, field_index| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        assert(!field_ty.isGenericPoison());
        const field_ty_src = block.src(.{ .container_field_type = @intCast(field_index) });
        try sema.ensureLayoutResolved(field_ty, field_ty_src, .field);
        if (field_ty.zigTypeTag(zcu) == .@"opaque") {
            return sema.failWithOwnedErrorMsg(&block, msg: {
                const msg = try sema.errMsg(field_ty_src, "cannot directly embed opaque type '{f}' in union", .{field_ty.fmt(pt)});
                errdefer msg.destroy(gpa);
                try sema.errNote(field_ty_src, msg, "opaque types have unknown size", .{});
                try sema.addDeclaredHereNote(msg, field_ty);
                break :msg msg;
            });
        }
        if (union_obj.layout == .@"extern" and !field_ty.validateExtern(.union_field, zcu)) {
            return sema.failWithOwnedErrorMsg(&block, msg: {
                const msg = try sema.errMsg(field_ty_src, "extern unions cannot contain fields of type '{f}'", .{field_ty.fmt(pt)});
                errdefer msg.destroy(gpa);
                try sema.explainWhyTypeIsNotExtern(msg, field_ty_src, field_ty, .union_field);
                try sema.addDeclaredHereNote(msg, field_ty);
                break :msg msg;
            });
        }
    }

    // Fields are okay. Now we need to resolve the union's overall layout (size, alignment, etc).
    var payload_align: Alignment = .@"1";
    var payload_size: u64 = 0;
    var possible_tags: u32 = 0;
    var payload_has_comptime_state = false;
    for (0..union_obj.field_types.len) |field_idx| {
        const field_ty: Type = .fromInterned(union_obj.field_types.get(ip)[field_idx]);
        const field_align: Alignment = a: {
            if (union_obj.field_aligns.len != 0) {
                const a = union_obj.field_aligns.get(ip)[field_idx];
                if (a != .none) break :a a;
            }
            break :a field_ty.abiAlignment(zcu);
        };
        payload_align = payload_align.maxStrict(field_align);
        payload_size = @max(payload_size, field_ty.abiSize(zcu));

        switch (field_ty.classify(zcu)) {
            .no_possible_value => {}, // uninstantiable field has no effect
            .one_possible_value, .runtime => {
                possible_tags += 1;
            },
            .partially_comptime, .fully_comptime => {
                possible_tags += 1;
                payload_has_comptime_state = true;
            },
        }
    }

    // Uninstantiable `extern union`s don't make sense; disallow them.
    if (possible_tags == 0 and union_obj.layout != .auto) {
        // Field types are all extern, so not NPV; thus zero possible tags means no tags at all.
        assert(union_obj.field_types.len == 0);
        return sema.fail(&block, union_ty.srcLoc(zcu), "extern union has no fields", .{});
    }

    // We only need a runtime tag if there are multiple possible active fields *and* the union is
    // not going to be comptime-only. Even if there are still runtime bits in the payload, the tag
    // does not require runtime bits in a comptime-only union, because it is impossible to get a
    // pointer to a union's tag.
    const has_runtime_tag = switch (possible_tags) {
        0, 1 => false,
        else => union_obj.tag_usage != .none and !payload_has_comptime_state,
    };

    const class: Type.Class = class: {
        if (possible_tags == 0) {
            break :class .no_possible_value;
        }
        if (payload_has_comptime_state) {
            break :class if (payload_size > 0) .partially_comptime else .fully_comptime;
        }
        const have_runtime_bits = has_runtime_tag or payload_size > 0;
        break :class if (have_runtime_bits) .runtime else .one_possible_value;
    };

    const size: u64, const padding: u64, const alignment: Alignment = layout: {
        if (!has_runtime_tag) {
            break :layout .{ payload_align.forward(payload_size), 0, payload_align };
        }
        const tag_align = enum_tag_ty.abiAlignment(zcu);
        const tag_size = enum_tag_ty.abiSize(zcu);
        // The layout will either be (tag, payload, padding) or (payload, tag, padding) depending on
        // which has larger alignment. So the overall size is just the tag and payload sizes, added,
        // and padded to the larger alignment.
        const alignment = tag_align.maxStrict(payload_align);
        const unpadded_size = tag_size + payload_size;
        const size = alignment.forward(unpadded_size);
        break :layout .{ size, size - unpadded_size, alignment };
    };

    if (class == .no_possible_value or class == .one_possible_value) {
        assert(size == 0);
        assert(padding == 0);
    }

    const casted_size = std.math.cast(u32, size) orelse return sema.fail(
        &block,
        union_ty.srcLoc(zcu),
        "union layout requires size {d}, this compiler implementation supports up to {d}",
        .{ size, std.math.maxInt(u32) },
    );
    ip.resolveUnionLayout(
        io,
        union_ty.toIntern(),
        enum_tag_ty.toIntern(),
        class,
        has_runtime_tag,
        casted_size,
        @intCast(padding), // okay because padding is no greater than size
        alignment,
    );
}
fn failUnionFieldMismatch(sema: *Sema, block: *Block, union_field_names: []const InternPool.NullTerminatedString, enum_tag_ty: Type, enum_obj: *const InternPool.LoadedEnumType) CompileError {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;
    const enum_to_union_map = try sema.arena.alloc(?u32, enum_obj.field_names.len);
    @memset(enum_to_union_map, null);
    for (union_field_names, 0..) |field_name, union_field_index| {
        if (enum_obj.nameIndex(ip, field_name)) |enum_field_index| {
            enum_to_union_map[enum_field_index] = @intCast(union_field_index);
            continue;
        }
        const union_field_src = block.src(.{ .container_field_name = @intCast(union_field_index) });
        return sema.failWithOwnedErrorMsg(block, msg: {
            const msg = try sema.errMsg(union_field_src, "no field named '{f}' in enum '{f}'", .{ field_name.fmt(ip), enum_tag_ty.fmt(pt) });
            errdefer msg.destroy(gpa);
            try sema.addDeclaredHereNote(msg, enum_tag_ty);
            break :msg msg;
        });
    }
    for (enum_to_union_map, 0..) |union_field_index, enum_field_index| {
        if (union_field_index != null) continue;
        const field_name_ip = enum_obj.field_names.get(ip)[enum_field_index];
        const enum_field_src: LazySrcLoc = .{
            .base_node_inst = enum_tag_ty.typeDeclInstAllowGeneratedTag(zcu).?,
            .offset = .{ .container_field_name = @intCast(enum_field_index) },
        };
        return sema.failWithOwnedErrorMsg(block, msg: {
            const msg = try sema.errMsg(block.nodeOffset(.zero), "enum field '{f}' missing from union", .{field_name_ip.fmt(ip)});
            errdefer msg.destroy(gpa);
            try sema.errNote(enum_field_src, msg, "enum field here", .{});
            break :msg msg;
        });
    }
    // The only problem is the field ordering.
    for (enum_to_union_map, 0..) |union_field_index, enum_field_index| {
        if (union_field_index.? == enum_field_index) continue;
        const field_name = enum_obj.field_names.get(ip)[enum_field_index];
        const union_field_src = block.src(.{ .container_field_name = union_field_index.? });
        const enum_field_src: LazySrcLoc = .{
            .base_node_inst = enum_tag_ty.typeDeclInstAllowGeneratedTag(zcu).?,
            .offset = .{ .container_field_name = @intCast(enum_field_index) },
        };
        return sema.failWithOwnedErrorMsg(block, msg: {
            const msg = try sema.errMsg(block.nodeOffset(.zero), "union field order does not match tag enum field order", .{});
            errdefer msg.destroy(gpa);
            try sema.errNote(union_field_src, msg, "union field '{f}' is index {d}", .{ field_name.fmt(ip), union_field_index.? });
            try sema.errNote(enum_field_src, msg, "enum field '{f}' is index {d}", .{ field_name.fmt(ip), enum_field_index });
            break :msg msg;
        });
    }
    unreachable; // we already determined that *something* is wrong
}
fn resolvePackedUnionLayout(
    sema: *Sema,
    block: *Block,
    union_ty: Type,
    union_obj: *const InternPool.LoadedUnionType,
    enum_tag_ty: Type,
) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    // Uninstantiable `packed union`s don't make sense; disallow them.
    if (union_obj.field_types.len == 0) {
        return sema.fail(block, union_ty.srcLoc(zcu), "packed union has no fields", .{});
    }

    // Resolve the layout of all fields, and check their types are allowed.
    for (union_obj.field_types.get(ip), 0..) |field_ty_ip, field_index| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        assert(!field_ty.isGenericPoison());
        const field_ty_src = block.src(.{ .container_field_type = @intCast(field_index) });
        try sema.ensureLayoutResolved(field_ty, field_ty_src, .field);
        if (field_ty.zigTypeTag(zcu) == .@"opaque") {
            return sema.failWithOwnedErrorMsg(block, msg: {
                const msg = try sema.errMsg(field_ty_src, "cannot directly embed opaque type '{f}' in union", .{field_ty.fmt(pt)});
                errdefer msg.destroy(gpa);
                try sema.errNote(field_ty_src, msg, "opaque types have unknown size", .{});
                try sema.addDeclaredHereNote(msg, field_ty);
                break :msg msg;
            });
        }
        if (field_ty.unpackable(zcu)) |reason| return sema.failWithOwnedErrorMsg(block, msg: {
            const msg = try sema.errMsg(field_ty_src, "packed unions cannot contain fields of type '{f}'", .{field_ty.fmt(pt)});
            errdefer msg.destroy(gpa);
            try sema.explainWhyTypeIsUnpackable(msg, field_ty_src, reason);
            break :msg msg;
        });
        assert(!field_ty.comptimeOnly(zcu)); // packable types are not comptime-only
    }

    const explicit_backing_int_ty: ?Type = if (union_obj.is_reified) ty: {
        switch (union_obj.packed_backing_mode) {
            .explicit => break :ty .fromInterned(union_obj.packed_backing_int_type),
            .auto => break :ty null,
        }
    } else ty: {
        const zir_index = union_obj.zir_index.resolve(ip).?;
        const zir_union = sema.code.getUnionDecl(zir_index);
        const backing_int_type_body = zir_union.arg_type_body orelse {
            break :ty null; // inferred backing type
        };
        // Explicitly specified, so evaluate the backing int type expression.
        const backing_int_type_src = block.src(.container_arg);
        block.comptime_reason = .{ .reason = .{
            .src = backing_int_type_src,
            .r = .{ .simple = .packed_union_backing_int_type },
        } };
        const type_ref = try sema.resolveInlineBody(block, backing_int_type_body, zir_index);
        break :ty try sema.analyzeAsType(block, backing_int_type_src, .packed_union_backing_int_type, type_ref);
    };

    // Finally, either validate or infer the backing int type.
    const backing_int_ty: Type = if (explicit_backing_int_ty) |backing_ty| ty: {
        if (backing_ty.zigTypeTag(zcu) != .int) return sema.fail(
            block,
            block.src(.container_arg),
            "expected backing integer type, found '{f}'",
            .{backing_ty.fmt(pt)},
        );
        const backing_int_bits = backing_ty.intInfo(zcu).bits;
        for (union_obj.field_types.get(ip), 0..) |field_type_ip, field_idx| {
            const field_type: Type = .fromInterned(field_type_ip);
            const field_bits = field_type.bitSize(zcu);
            if (field_bits != backing_int_bits) return sema.failWithOwnedErrorMsg(block, msg: {
                const field_ty_src = block.src(.{ .container_field_type = @intCast(field_idx) });
                const msg = try sema.errMsg(field_ty_src, "field bit width does not match backing integer", .{});
                errdefer msg.destroy(gpa);
                try sema.errNote(field_ty_src, msg, "field type '{f}' has bit width '{d}'", .{ field_type.fmt(pt), field_bits });
                try sema.errNote(
                    block.src(.container_arg),
                    msg,
                    "backing integer '{f}' has bit width '{d}'",
                    .{ backing_ty.fmt(pt), backing_int_bits },
                );
                try sema.errNote(field_ty_src, msg, "all fields in a packed union must have the same bit width", .{});
                break :msg msg;
            });
        }
        break :ty backing_ty;
    } else ty: {
        const field_types = union_obj.field_types.get(ip);
        const first_field_type: Type = .fromInterned(field_types[0]);
        const first_field_bits = first_field_type.bitSize(zcu);
        for (field_types[1..], 1..) |field_type_ip, field_idx| {
            const field_type: Type = .fromInterned(field_type_ip);
            const field_bits = field_type.bitSize(zcu);
            if (field_bits != first_field_bits) return sema.failWithOwnedErrorMsg(block, msg: {
                const first_field_ty_src = block.src(.{ .container_field_type = 0 });
                const field_ty_src = block.src(.{ .container_field_type = @intCast(field_idx) });
                const msg = try sema.errMsg(field_ty_src, "field bit width does not match earlier field", .{});
                errdefer msg.destroy(gpa);
                try sema.errNote(field_ty_src, msg, "field type '{f}' has bit width '{d}'", .{ field_type.fmt(pt), field_bits });
                try sema.errNote(first_field_ty_src, msg, "other field type '{f}' has bit width '{d}'", .{ first_field_type.fmt(pt), first_field_bits });
                try sema.errNote(field_ty_src, msg, "all fields in a packed union must have the same bit width", .{});
                break :msg msg;
            });
        }
        const backing_int_bits = std.math.cast(u16, first_field_bits) orelse return sema.fail(
            block,
            union_ty.srcLoc(zcu),
            "packed union bit width '{d}' exceeds maximum bit width of 65535",
            .{first_field_bits},
        );
        break :ty try pt.intType(.unsigned, backing_int_bits);
    };
    ip.resolvePackedUnionLayout(
        io,
        union_ty.toIntern(),
        enum_tag_ty.toIntern(),
        backing_int_ty.toIntern(),
    );
}

pub fn resolveEnumLayout(sema: *Sema, enum_ty: Type) CompileError!void {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const comp = zcu.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ip = &zcu.intern_pool;

    assert(sema.owner.unwrap().type_layout == enum_ty.toIntern());

    const enum_obj = ip.loadEnumType(enum_ty.toIntern());
    assert(enum_obj.want_layout);

    const maybe_parent_union_obj: ?InternPool.LoadedUnionType = un: {
        if (enum_obj.owner_union == .none) break :un null;
        break :un ip.loadUnionType(enum_obj.owner_union);
    };

    const tracked_inst = enum_obj.zir_index.unwrap() orelse maybe_parent_union_obj.?.zir_index;
    const zir_index = tracked_inst.resolve(ip) orelse return error.AnalysisFail;

    var block: Block = .{
        .parent = null,
        .sema = sema,
        .namespace = enum_obj.namespace,
        .instructions = .empty,
        .inlining = null,
        .comptime_reason = undefined, // always set before using `block`
        .src_base_inst = tracked_inst,
        .type_name_ctx = enum_obj.name,
    };
    defer block.instructions.deinit(gpa);

    // There may be old field names in the map from a previous update.
    enum_obj.field_name_map.get(ip).clearRetainingCapacity();

    if (maybe_parent_union_obj) |*union_obj| {
        if (union_obj.is_reified) {
            // In the case of reification, the union stores the field names, just for us to copy.
            @memcpy(enum_obj.field_names.get(ip), union_obj.reified_field_names.get(ip));
            // The list of field names is now populated, but we haven't checked for duplicates yet,
            // nor have we populated the hash map.
            for (0..enum_obj.field_names.len) |field_index| {
                const name = enum_obj.field_names.get(ip)[field_index];
                if (ip.addFieldName(enum_obj.field_names, enum_obj.field_name_map, name)) |prev_field_index| {
                    return sema.failWithOwnedErrorMsg(&block, msg: {
                        const src = block.builtinCallArgSrc(.zero, 2);
                        const msg = try sema.errMsg(src, "duplicate union field '{f}' at index '{d}", .{ name.fmt(ip), field_index });
                        errdefer msg.destroy(gpa);
                        try sema.errNote(src, msg, "previous field at index '{d}'", .{prev_field_index});
                        break :msg msg;
                    });
                }
            }
        } else {
            // Generated tag enums for declared unions do not yet have field names populated. It is
            // our job to populate them now.
            try sema.declareDependency(.{ .src_hash = union_obj.zir_index });
            const zir_union = sema.code.getUnionDecl(zir_index);
            for (zir_union.field_names) |zir_field_name| {
                const name_slice = sema.code.nullTerminatedString(zir_field_name);
                const name = try ip.getOrPutString(gpa, io, pt.tid, name_slice, .no_embedded_nulls);
                assert(ip.addFieldName(enum_obj.field_names, enum_obj.field_name_map, name) == null); // AstGen validated this for us
            }
        }
    } else {
        if (enum_obj.is_reified) {
            // The field names are populated, but we haven't checked for duplicates (nor populated the map) yet.
            for (0..enum_obj.field_names.len) |field_index| {
                const name = enum_obj.field_names.get(ip)[field_index];
                if (ip.addFieldName(enum_obj.field_names, enum_obj.field_name_map, name)) |prev_field_index| {
                    return sema.failWithOwnedErrorMsg(&block, msg: {
                        const src = block.builtinCallArgSrc(.zero, 2);
                        const msg = try sema.errMsg(src, "duplicate enum field '{f}' at index '{d}'", .{ name.fmt(ip), field_index });
                        errdefer msg.destroy(gpa);
                        try sema.errNote(src, msg, "previous field at index '{d}'", .{prev_field_index});
                        break :msg msg;
                    });
                }
            }
        } else {
            // Declared enums do not yet have field names populated. It is our job to populate them now.
            try sema.declareDependency(.{ .src_hash = enum_obj.zir_index.unwrap().? });
            const zir_enum = sema.code.getEnumDecl(zir_index);
            for (zir_enum.field_names) |zir_field_name| {
                const name_slice = sema.code.nullTerminatedString(zir_field_name);
                const name = try ip.getOrPutString(gpa, io, pt.tid, name_slice, .no_embedded_nulls);
                assert(ip.addFieldName(enum_obj.field_names, enum_obj.field_name_map, name) == null); // AstGen validated this for us
            }
        }
    }

    // Field names populated; now deal with the backing integer type. If explicitly provided,
    // validate it; otherwise, infer it.

    const explicit_int_tag_ty: ?Type = if (enum_obj.is_reified) ty: {
        break :ty switch (enum_obj.int_tag_mode) {
            .explicit => .fromInterned(enum_obj.int_tag_type),
            .auto => null,
        };
    } else if (maybe_parent_union_obj) |*union_obj| ty: {
        if (union_obj.is_reified) {
            // Reification has no equivalent of 'union(enum(T))'.
            break :ty null;
        }
        const zir_union = sema.code.getUnionDecl(zir_index);
        if (zir_union.kind != .tagged_enum_explicit) {
            break :ty null; // int tag type will be inferred
        }
        // Explicitly specified, so evaluate the int tag type expression.
        const tag_type_body = zir_union.arg_type_body.?;
        const tag_type_src = block.src(.container_arg);
        block.comptime_reason = .{ .reason = .{
            .src = tag_type_src,
            .r = .{ .simple = .enum_int_tag_type },
        } };
        const type_ref = try sema.resolveInlineBody(&block, tag_type_body, zir_index);
        break :ty try sema.analyzeAsType(&block, tag_type_src, .enum_int_tag_type, type_ref);
    } else ty: {
        const zir_enum = sema.code.getEnumDecl(zir_index);
        const tag_type_body = zir_enum.tag_type_body orelse {
            break :ty null; // int tag type will be inferred
        };
        // Explicitly specified, so evaluate the int tag type expression.
        const tag_type_src = block.src(.container_arg);
        block.comptime_reason = .{ .reason = .{
            .src = tag_type_src,
            .r = .{ .simple = .enum_int_tag_type },
        } };
        const type_ref = try sema.resolveInlineBody(&block, tag_type_body, zir_index);
        break :ty try sema.analyzeAsType(&block, tag_type_src, .enum_int_tag_type, type_ref);
    };
    const int_tag_ty: Type = if (explicit_int_tag_ty) |int_tag_ty| ty: {
        if (int_tag_ty.zigTypeTag(zcu) != .int) return sema.fail(
            &block,
            block.src(.container_arg),
            "expected integer tag type, found '{f}'",
            .{int_tag_ty.fmt(pt)},
        );
        break :ty int_tag_ty;
    } else ty: {
        // Infer the int tag type from the field count
        const bits = Type.smallestUnsignedBits(enum_obj.field_names.len -| 1);
        break :ty try pt.intType(.unsigned, bits);
    };

    ip.resolveEnumLayout(io, enum_ty.toIntern(), int_tag_ty.toIntern());

    // Finally, deal with field values. For declared types we need to analyze the expressions, while
    // reified types already have them populated; but either way, we need to populate the hash map
    // (and validate the values along the way).

    // We'll populate this map.
    const field_value_map = enum_obj.field_value_map.unwrap() orelse {
        // The enum is auto-numbered with an inferred tag type. We know that the tag type generated
        // earlier is sufficient for the number of fields, so we have nothing more to do.
        assert(enum_obj.int_tag_mode == .auto);
        return;
    };

    // There may be old field values in here from a previous update.
    field_value_map.get(ip).clearRetainingCapacity();

    // Map the enum (or union) decl instruction to provide the tag type as the result type
    try sema.inst_map.ensureSpaceForInstructions(gpa, &.{zir_index});
    sema.inst_map.putAssumeCapacity(zir_index, .fromIntern(int_tag_ty.toIntern()));
    defer assert(sema.inst_map.remove(zir_index));

    // First, populate any explicitly provided values. This is the part that actually depends on
    // the ZIR, and hence depends on whether this is a declared or generated enum. If any explicit
    // value is straight-up invalid, we'll emit an error here.
    if (maybe_parent_union_obj) |union_obj| {
        if (union_obj.is_reified) {
            // Generated tag type for reified union; values already populated.
        } else {
            // Generated tag type for declared union; evaluate the expressions given in the union declaration.
            const zir_union = sema.code.getUnionDecl(zir_index);
            var field_it = zir_union.iterateFields();
            while (field_it.next()) |zir_field| {
                const field_val_src = block.src(.{ .container_field_value = zir_field.idx });
                block.comptime_reason = .{ .reason = .{
                    .src = field_val_src,
                    .r = .{ .simple = .enum_field_values },
                } };
                const value_body = zir_field.value_body orelse {
                    enum_obj.field_values.get(ip)[zir_field.idx] = .none;
                    continue;
                };
                const uncoerced = try sema.resolveInlineBody(&block, value_body, zir_index);
                const coerced = try sema.coerce(&block, int_tag_ty, uncoerced, field_val_src);
                const val = try sema.resolveConstValue(&block, field_val_src, coerced, null);
                enum_obj.field_values.get(ip)[zir_field.idx] = val.toIntern();
            }
        }
    } else if (enum_obj.is_reified) {
        // Reified enum; values already populated.
    } else {
        // Declared enum; evaluate the expressions given in the enum declaration.
        const zir_enum = sema.code.getEnumDecl(zir_index);
        var field_it = zir_enum.iterateFields();
        while (field_it.next()) |zir_field| {
            const field_val_src = block.src(.{ .container_field_value = zir_field.idx });
            block.comptime_reason = .{ .reason = .{
                .src = field_val_src,
                .r = .{ .simple = .enum_field_values },
            } };
            const value_body = zir_field.value_body orelse {
                enum_obj.field_values.get(ip)[zir_field.idx] = .none;
                continue;
            };
            const uncoerced = try sema.resolveInlineBody(&block, value_body, zir_index);
            const coerced = try sema.coerce(&block, int_tag_ty, uncoerced, field_val_src);
            const val = try sema.resolveConstDefinedValue(&block, field_val_src, coerced, null);
            enum_obj.field_values.get(ip)[zir_field.idx] = val.toIntern();
        }
    }

    // Explicit values are set. Now we'll go through the whole array and figure out the final
    // field values. This is also where we'll detect duplicates.

    for (0..enum_obj.field_names.len) |field_idx| {
        const field_val_src = block.src(.{ .container_field_value = @intCast(field_idx) });
        // If the field value was not specified, compute the implicit value.
        const field_val = val: {
            const explicit_val = enum_obj.field_values.get(ip)[field_idx];
            if (explicit_val != .none) {
                assert(ip.typeOf(explicit_val) == int_tag_ty.toIntern());
                break :val explicit_val;
            }
            if (field_idx == 0) {
                // Implicit value is 0, which is valid for every integer type.
                const val = (try pt.intValue(int_tag_ty, 0)).toIntern();
                enum_obj.field_values.get(ip)[field_idx] = val;
                break :val val;
            }
            // Implicit non-initial value: take the previous field value and add one.
            const prev_field_val: Value = .fromInterned(enum_obj.field_values.get(ip)[field_idx - 1]);
            const result = try arith.incrementDefinedInt(sema, int_tag_ty, prev_field_val);
            if (result.overflow) return sema.fail(
                &block,
                field_val_src,
                "enum tag value '{f}' too large for type '{f}'",
                .{ result.val.fmtValueSema(pt, sema), int_tag_ty.fmt(pt) },
            );
            const val = result.val.toIntern();
            enum_obj.field_values.get(ip)[field_idx] = val;
            break :val val;
        };
        if (ip.addFieldTagValue(enum_obj.field_values, field_value_map, field_val)) |prev_field_index| {
            return sema.failWithOwnedErrorMsg(&block, msg: {
                const prev_field_val_src = block.src(.{ .container_field_value = prev_field_index });
                const msg = try sema.errMsg(field_val_src, "enum tag value '{f}' for field '{f}' already taken", .{
                    Value.fromInterned(field_val).fmtValueSema(pt, sema),
                    enum_obj.field_names.get(ip)[field_idx].fmt(ip),
                });
                errdefer msg.destroy(gpa);
                try sema.errNote(prev_field_val_src, msg, "previous occurrence in field '{f}'", .{
                    enum_obj.field_names.get(ip)[prev_field_index].fmt(ip),
                });
                break :msg msg;
            });
        }
    }

    if (enum_obj.nonexhaustive) {
        const fields_len = enum_obj.field_names.len;
        if (fields_len >= 1 and std.math.log2_int(u64, fields_len) == int_tag_ty.bitSize(zcu)) {
            return sema.fail(&block, block.nodeOffset(.zero), "non-exhaustive enum specifies every value", .{});
        }
    }
}
