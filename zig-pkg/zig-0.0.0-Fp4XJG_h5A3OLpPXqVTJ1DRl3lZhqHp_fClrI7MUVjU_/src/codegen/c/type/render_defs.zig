/// Renders the `typedef` for an aligned type.
pub fn defineAligned(
    ty: Type,
    alignment: Alignment,
    complete: bool,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;

    const name_cty: CType = .{ .aligned = .{
        .ty = ty,
        .alignment = alignment,
    } };

    const cty: CType = try .lower(ty, deps, arena, zcu);

    try w.writeAll("typedef ");
    if (complete and alignment.compareStrict(.lt, ty.abiAlignment(zcu))) {
        try w.print("zig_under_align({d}) ", .{alignment.toByteUnits().?});
    }
    try w.print("{f}{f}{f}; /* align({d}) {f} */\n", .{
        cty.fmtDeclaratorPrefix(zcu),
        name_cty.fmtTypeName(zcu),
        cty.fmtDeclaratorSuffix(zcu),
        alignment.toByteUnits().?,
        ty.fmt(pt),
    });
}
/// Renders the definition of a big-int `struct`.
pub fn defineBigInt(big: CType.BigInt, w: *Writer, zcu: *const Zcu) Writer.Error!void {
    const name_cty: CType = .{ .bigint = .{
        .limb_size = big.limb_size,
        .limbs_len = big.limbs_len,
    } };
    const limb_cty: CType = .{ .int = big.limb_size.unsigned() };
    const array_cty: CType = .{ .array = .{
        .len = big.limbs_len,
        .elem_ty = &limb_cty,
        .nonstring = limb_cty.isStringElem(),
    } };
    try w.print("{f} {{ {f}limbs{f}; }}; /* {d} bits */\n", .{
        name_cty.fmtTypeName(zcu),
        array_cty.fmtDeclaratorPrefix(zcu),
        array_cty.fmtDeclaratorSuffix(zcu),
        big.limb_size.bits() * @as(u17, big.limbs_len),
    });
}

/// Renders a forward declaration of the `struct` which represents an error union whose payload type
/// is `payload_ty` (the error set type is unspecified).
pub fn errunionFwdDecl(payload_ty: Type, w: *Writer, zcu: *const Zcu) Writer.Error!void {
    const name_cty: CType = .{ .errunion = .{
        .payload_ty = payload_ty,
    } };
    try w.print("{f};\n", .{name_cty.fmtTypeName(zcu)});
}
/// Renders the definition of the `struct` which represents an error union whose payload type is
/// `payload_ty` (the error set type is unspecified).
///
/// Asserts that the layout of `payload_ty` is resolved.
pub fn errunionDefineComplete(
    payload_ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;

    payload_ty.assertHasLayout(zcu);

    const name_cty: CType = .{ .errunion = .{
        .payload_ty = payload_ty,
    } };

    const error_cty: CType = try .lower(.anyerror, deps, arena, zcu);

    if (payload_ty.hasRuntimeBits(zcu)) {
        const payload_cty: CType = try .lower(payload_ty, deps, arena, zcu);
        try w.print(
            \\{f} {{ /* anyerror!{f} */
            \\ {f}payload{f};
            \\ {f}error{f};
            \\}};
            \\
        , .{
            name_cty.fmtTypeName(zcu),
            payload_ty.fmt(pt),
            payload_cty.fmtDeclaratorPrefix(zcu),
            payload_cty.fmtDeclaratorSuffix(zcu),
            error_cty.fmtDeclaratorPrefix(zcu),
            error_cty.fmtDeclaratorSuffix(zcu),
        });
    } else {
        try w.print("{f} {{ {f}error{f}; }}; /* anyerror!{f} */\n", .{
            name_cty.fmtTypeName(zcu),
            error_cty.fmtDeclaratorPrefix(zcu),
            error_cty.fmtDeclaratorSuffix(zcu),
            payload_ty.fmt(pt),
        });
    }
}

/// If the Zig type `ty` lowers to a `struct` or `union` type, renders a forward declaration of that
/// type. Does not write anything for error union types, because their forward declarations are
/// instead rendered by `errunionFwdDecl`.
pub fn fwdDecl(ty: Type, w: *Writer, zcu: *const Zcu) Writer.Error!void {
    const name_cty: CType = switch (ty.zigTypeTag(zcu)) {
        .@"struct" => switch (ty.containerLayout(zcu)) {
            .auto, .@"extern" => .{ .@"struct" = ty },
            .@"packed" => return,
        },
        .@"union" => switch (ty.containerLayout(zcu)) {
            .auto => .{ .union_auto = ty },
            .@"extern" => .{ .union_extern = ty },
            .@"packed" => return,
        },
        .pointer => if (ty.isSlice(zcu)) .{ .slice = ty } else return,
        .optional => .{ .opt = ty },
        .array => .{ .arr = ty },
        .vector => .{ .vec = ty },
        else => return,
    };
    try w.print("{f};\n", .{name_cty.fmtTypeName(zcu)});
}

/// If the Zig type `ty` lowers to a `typedef`, renders a typedef of that type to `void`, because
/// the type's layout is not resolved. This is only necessary for `typedef`s because a `struct` or
/// `union` which is never defined is already an incomplete type, just like `void`.
pub fn defineIncomplete(ty: Type, w: *Writer, pt: Zcu.PerThread) Writer.Error!void {
    const zcu = pt.zcu;
    const name_cty: CType = switch (ty.zigTypeTag(zcu)) {
        .@"fn" => .{ .@"fn" = ty },
        .@"enum" => .{ .@"enum" = ty },
        .@"struct", .@"union" => switch (ty.containerLayout(zcu)) {
            .auto, .@"extern" => return,
            .@"packed" => .{ .bitpack = ty },
        },
        else => return,
    };
    try w.print("typedef void {f}; /* {f} */\n", .{
        name_cty.fmtTypeName(zcu),
        ty.fmt(pt),
    });
}

/// If the Zig type `ty` lowers to a `struct` or `union` type, or to a `typedef`, renders the
/// definition of that type. Does not write anything for error union types, because their
/// definitions are instead rendered by `errunionDefine`.
///
/// Asserts that the layout of `ty` is resolved.
pub fn defineComplete(
    ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;

    ty.assertHasLayout(zcu);

    switch (ty.zigTypeTag(zcu)) {
        .@"fn" => if (!ty.fnHasRuntimeBits(zcu)) {
            const name_cty: CType = .{ .@"fn" = ty };
            try w.print("typedef void {f}; /* {f} */\n", .{
                name_cty.fmtTypeName(zcu),
                ty.fmt(pt),
            });
        } else {
            const ip = &zcu.intern_pool;
            const func_type = ip.indexToKey(ty.toIntern()).func_type;

            // While incomplete types are usually an acceptable substitute for "void", this is not
            // true in function return types, where "void" is the only incomplete type permitted.
            const actual_ret_ty: Type = .fromInterned(func_type.return_type);
            const effective_ret_ty: Type = switch (actual_ret_ty.classify(zcu)) {
                .no_possible_value => .noreturn,
                .one_possible_value, .fully_comptime => .void, // no runtime bits
                .partially_comptime, .runtime => actual_ret_ty, // yes runtime bits
            };

            const name_cty: CType = .{ .@"fn" = ty };
            const ret_cty: CType = try .lower(effective_ret_ty, deps, arena, zcu);

            try w.print("typedef {f}{f}(", .{
                ret_cty.fmtDeclaratorPrefix(zcu),
                name_cty.fmtTypeName(zcu),
            });
            var any_params = false;
            for (func_type.param_types.get(ip)) |param_ty_ip| {
                const param_ty: Type = .fromInterned(param_ty_ip);
                if (!param_ty.hasRuntimeBits(zcu)) continue;
                if (any_params) try w.writeAll(", ");
                any_params = true;
                const param_cty: CType = try .lower(param_ty, deps, arena, zcu);
                try w.print("{f}", .{param_cty.fmtTypeName(zcu)});
            }
            if (func_type.is_var_args) {
                if (any_params) try w.writeAll(", ");
                try w.writeAll("...");
            } else if (!any_params) {
                try w.writeAll("void");
            }
            try w.print("){f}; /* {f} */\n", .{
                ret_cty.fmtDeclaratorSuffixIgnoreNonstring(zcu),
                ty.fmt(pt),
            });
        },
        .@"enum" => {
            const name_cty: CType = .{ .@"enum" = ty };
            const cty: CType = try .lower(ty.intTagType(zcu), deps, arena, zcu);
            try w.print("typedef {f}{f}{f}; /* {f} */\n", .{
                cty.fmtDeclaratorPrefix(zcu),
                name_cty.fmtTypeName(zcu),
                cty.fmtDeclaratorSuffix(zcu),
                ty.fmt(pt),
            });
        },
        .@"struct" => if (ty.isTuple(zcu)) {
            try defineTuple(ty, deps, arena, w, pt);
        } else switch (ty.containerLayout(zcu)) {
            .auto, .@"extern" => try defineStruct(ty, deps, arena, w, pt),
            .@"packed" => try defineBitpack(ty, deps, arena, w, pt),
        },
        .@"union" => switch (ty.containerLayout(zcu)) {
            .auto => try defineUnionAuto(ty, deps, arena, w, pt),
            .@"extern" => try defineUnionExtern(ty, deps, arena, w, pt),
            .@"packed" => try defineBitpack(ty, deps, arena, w, pt),
        },
        .pointer => if (ty.isSlice(zcu)) {
            const name_cty: CType = .{ .slice = ty };
            const ptr_cty: CType = try .lower(ty.slicePtrFieldType(zcu), deps, arena, zcu);
            try w.print(
                \\{f} {{ /* {f} */
                \\ {f}ptr{f};
                \\ size_t len;
                \\}};
                \\
            , .{
                name_cty.fmtTypeName(zcu),
                ty.fmt(pt),
                ptr_cty.fmtDeclaratorPrefix(zcu),
                ptr_cty.fmtDeclaratorSuffix(zcu),
            });
            // Don't bother with `writeStaticAssertLayout`---there's not really any way we could mess
            // slices up, and they're all obviously the same layout.
        },
        .optional => switch (CType.classifyOptional(ty, zcu)) {
            .error_set,
            .ptr_like,
            .slice_like,
            .npv_payload,
            => {},

            .opv_payload => {
                const name_cty: CType = .{ .opt = ty };
                try w.print("{f} {{ bool is_null; }}; /* {f} */\n", .{
                    name_cty.fmtTypeName(zcu),
                    ty.fmt(pt),
                });
                try writeStaticAssertLayout(ty, name_cty, w, zcu);
            },

            .@"struct" => {
                const name_cty: CType = .{ .opt = ty };
                const payload_cty: CType = try .lower(ty.optionalChild(zcu), deps, arena, zcu);
                try w.print(
                    \\{f} {{ /* {f} */
                    \\ {f}payload{f};
                    \\ bool is_null;
                    \\}};
                    \\
                , .{
                    name_cty.fmtTypeName(zcu),
                    ty.fmt(pt),
                    payload_cty.fmtDeclaratorPrefix(zcu),
                    payload_cty.fmtDeclaratorSuffix(zcu),
                });
                try writeStaticAssertLayout(ty, name_cty, w, zcu);
            },
        },
        .array => if (ty.hasRuntimeBits(zcu)) {
            const name_cty: CType = .{ .arr = ty };
            const elem_cty: CType = try .lower(ty.childType(zcu), deps, arena, zcu);
            const array_cty: CType = .{ .array = .{
                .len = ty.arrayLenIncludingSentinel(zcu),
                .elem_ty = &elem_cty,
                .nonstring = nonstring: {
                    if (!elem_cty.isStringElem()) break :nonstring false;
                    const s = ty.sentinel(zcu) orelse break :nonstring true;
                    break :nonstring Value.compareHetero(s, .neq, .zero_comptime_int, zcu);
                },
            } };
            try w.print("{f} {{ {f}array{f}; }}; /* {f} */\n", .{
                name_cty.fmtTypeName(zcu),
                array_cty.fmtDeclaratorPrefix(zcu),
                array_cty.fmtDeclaratorSuffix(zcu),
                ty.fmt(pt),
            });
            try writeStaticAssertLayout(ty, name_cty, w, zcu);
        },
        .vector => if (ty.hasRuntimeBits(zcu)) {
            const name_cty: CType = .{ .vec = ty };
            const elem_cty: CType = try .lower(ty.childType(zcu), deps, arena, zcu);
            const array_cty: CType = .{ .array = .{
                .len = ty.arrayLenIncludingSentinel(zcu),
                .elem_ty = &elem_cty,
                .nonstring = elem_cty.isStringElem(),
            } };
            try w.print("{f} {{ {f}array{f}; }}; /* {f} */\n", .{
                name_cty.fmtTypeName(zcu),
                array_cty.fmtDeclaratorPrefix(zcu),
                array_cty.fmtDeclaratorSuffix(zcu),
                ty.fmt(pt),
            });
            try writeStaticAssertLayout(ty, name_cty, w, zcu);
        },
        else => {},
    }
}
fn defineBitpack(
    ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;
    const name_cty: CType = .{ .bitpack = ty };
    const cty: CType = try .lower(ty.bitpackBackingInt(zcu), deps, arena, zcu);
    try w.print("typedef {f}{f}{f}; /* {f} */\n", .{
        cty.fmtDeclaratorPrefix(zcu),
        name_cty.fmtTypeName(zcu),
        cty.fmtDeclaratorSuffix(zcu),
        ty.fmt(pt),
    });
}
fn defineTuple(
    ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;
    if (!ty.hasRuntimeBits(zcu)) return;
    const ip = &zcu.intern_pool;
    const tuple = ip.indexToKey(ty.toIntern()).tuple_type;

    // Fields cannot be underaligned, because tuple fields cannot have specified alignments.
    // However, overaligned fields are possible thanks to intermediate zero-bit fields.

    const tuple_align = ty.abiAlignment(zcu);

    // If the alignment of other fields would not give the tuple sufficient alignment, we
    // need to align the first field (which does not affect its offset, because 0 is always
    // well-aligned) to indirectly specify the tuple alignment.
    const overalign: bool = for (tuple.types.get(ip)) |field_ty_ip| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        if (!field_ty.hasRuntimeBits(zcu)) continue;
        const natural_align = field_ty.defaultStructFieldAlignment(.auto, zcu);
        if (natural_align.compareStrict(.gte, tuple_align)) break false;
    } else true;

    const name_cty: CType = .{ .@"struct" = ty };
    try w.print("{f} {{ /* {f} */\n", .{
        name_cty.fmtTypeName(zcu),
        ty.fmt(pt),
    });
    var zig_offset: u64 = 0;
    var c_offset: u64 = 0;
    for (tuple.types.get(ip), tuple.values.get(ip), 0..) |field_ty_ip, field_val_ip, field_index| {
        if (field_val_ip != .none) continue; // `comptime` field
        const field_ty: Type = .fromInterned(field_ty_ip);
        const field_align = field_ty.abiAlignment(zcu);
        zig_offset = field_align.forward(zig_offset);
        if (!field_ty.hasRuntimeBits(zcu)) continue;
        c_offset = field_align.forward(c_offset);
        try w.writeByte(' ');
        if (zig_offset == 0 and overalign) {
            // This is the first field; specify its alignment to align the tuple.
            try writeFieldAlign(field_ty, tuple_align, w, zcu);
        } else if (zig_offset > c_offset) {
            // This field needs to be overaligned compared to what its offset would otherwise be.
            const need_align: Alignment = .minStrict(
                tuple_align, // don't make the struct more aligned than it should be
                .fromLog2Units(@ctz(zig_offset)),
            );
            try writeFieldAlign(field_ty, need_align, w, zcu);
            c_offset = need_align.forward(c_offset);
        }
        const field_cty: CType = try .lower(field_ty, deps, arena, zcu);
        try w.print("{f}f{d}{f};\n", .{
            field_cty.fmtDeclaratorPrefix(zcu),
            field_index,
            field_cty.fmtDeclaratorSuffix(zcu),
        });
        const field_size = field_ty.abiSize(zcu);
        zig_offset += field_size;
        c_offset += field_size;
    }
    try w.writeAll("};\n");

    try writeStaticAssertLayout(ty, name_cty, w, zcu);
}
fn defineStruct(
    ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;
    if (!ty.hasRuntimeBits(zcu)) return;
    const ip = &zcu.intern_pool;

    const struct_type = ip.loadStructType(ty.toIntern());

    // If there are any underaligned fields, we need to byte-pack the struct.
    const pack: bool = pack: {
        var it = struct_type.iterateRuntimeOrder(ip);
        var offset: u64 = 0;
        while (it.next()) |field_index| {
            const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
            if (!field_ty.hasRuntimeBits(zcu)) continue;
            const natural_align = field_ty.defaultStructFieldAlignment(struct_type.layout, zcu);
            const natural_offset = natural_align.forward(offset);
            const actual_offset = struct_type.field_offsets.get(ip)[field_index];
            if (actual_offset < natural_offset) break :pack true;
            // Also pack if any field is more aligned than the struct should be.
            if (natural_align.compareStrict(.gt, struct_type.alignment)) break :pack true;
            offset = actual_offset + field_ty.abiSize(zcu);
        }
        break :pack false;
    };

    // If the alignment of other fields would not give the struct sufficient alignment, we
    // need to align the first field (which does not affect its offset, because 0 is always
    // well-aligned) to indirectly specify the struct alignment.
    const overalign: bool = switch (pack) {
        true => struct_type.alignment.compareStrict(.gt, .@"1"),
        false => overalign: {
            var it = struct_type.iterateRuntimeOrder(ip);
            while (it.next()) |field_index| {
                const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
                if (!field_ty.hasRuntimeBits(zcu)) continue;
                const natural_align = field_ty.defaultStructFieldAlignment(struct_type.layout, zcu);
                if (natural_align.compareStrict(.gte, struct_type.alignment)) break :overalign false;
            }
            break :overalign true;
        },
    };

    if (pack) try w.writeAll("zig_packed(");
    const name_cty: CType = .{ .@"struct" = ty };
    try w.print("{f} {{ /* {f} */\n", .{
        name_cty.fmtTypeName(zcu),
        ty.fmt(pt),
    });
    var it = struct_type.iterateRuntimeOrder(ip);
    var offset: u64 = 0;
    while (it.next()) |field_index| {
        const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
        if (!field_ty.hasRuntimeBits(zcu)) continue;
        const natural_align = field_ty.defaultStructFieldAlignment(struct_type.layout, zcu);
        const natural_offset = switch (pack) {
            true => offset,
            false => natural_align.forward(offset),
        };
        const actual_offset = struct_type.field_offsets.get(ip)[field_index];
        try w.writeByte(' ');
        if (actual_offset == 0 and overalign) {
            // This is the first field; specify its alignment to align the struct.
            try writeFieldAlign(field_ty, struct_type.alignment, w, zcu);
        } else if (actual_offset > natural_offset) {
            // This field needs to be underaligned or overaligned compared to what its
            // offset would otherwise be.
            const need_align: Alignment = .minStrict(
                struct_type.alignment, // don't make the struct more aligned than it should be
                .fromLog2Units(@ctz(actual_offset)),
            );
            try writeFieldAlign(field_ty, need_align, w, zcu);
        }
        const field_cty: CType = try .lower(field_ty, deps, arena, zcu);
        const field_name = struct_type.field_names.get(ip)[field_index].toSlice(ip);
        try w.print("{f}{f}{f};\n", .{
            field_cty.fmtDeclaratorPrefix(zcu),
            fmtIdentSolo(field_name),
            field_cty.fmtDeclaratorSuffix(zcu),
        });
        offset = actual_offset + field_ty.abiSize(zcu);
    }
    assert(struct_type.alignment.forward(offset) == struct_type.size);
    try w.writeByte('}');
    if (pack) try w.writeByte(')');
    try w.writeAll(";\n");

    try writeStaticAssertLayout(ty, name_cty, w, zcu);
}
fn defineUnionAuto(
    ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;
    if (!ty.hasRuntimeBits(zcu)) return;
    const ip = &zcu.intern_pool;

    const union_type = ip.loadUnionType(ty.toIntern());
    const enum_tag_ty: Type = .fromInterned(union_type.enum_tag_type);

    const layout = Type.getUnionLayout(union_type, zcu);

    // If there are any underaligned fields, we need to byte-pack the union.
    const pack: bool = for (union_type.field_types.get(ip)) |field_ty_ip| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        if (!field_ty.hasRuntimeBits(zcu)) continue;
        const natural_align = field_ty.abiAlignment(zcu);
        if (natural_align.compareStrict(.gt, union_type.alignment)) break true;
        // The tag will immediately follow the payload. This layout may put the tag in what would
        // otherwise be padding on the payload union, because if the most-aligned union field is not
        // the largest one, a larger field may make the payload "underaligned" overall. As such, we
        // need to check whether this field is okay with the payload size, and if not then we must
        // byte-pack.
        if (!natural_align.check(layout.payload_size)) break true;
    } else false;

    // If the alignment of other fields would not give the union sufficient alignment, we
    // need to align the first field (which does not affect its offset, because 0 is always
    // well-aligned) to indirectly specify the union alignment.
    const overalign: bool = switch (pack) {
        true => union_type.alignment.compareStrict(.gt, .@"1"),
        false => for (union_type.field_types.get(ip)) |field_ty_ip| {
            const field_ty: Type = .fromInterned(field_ty_ip);
            if (!field_ty.hasRuntimeBits(zcu)) continue;
            const natural_align = field_ty.abiAlignment(zcu);
            if (natural_align.compareStrict(.gte, union_type.alignment)) break false;
        } else overalign: {
            if (union_type.has_runtime_tag) {
                const tag_align = enum_tag_ty.abiAlignment(zcu);
                if (tag_align.compareStrict(.gte, union_type.alignment)) break :overalign false;
            }
            break :overalign true;
        },
    };

    const payload_has_bits = !union_type.has_runtime_tag or union_type.size > enum_tag_ty.abiSize(zcu);

    const name_cty: CType = .{ .union_auto = ty };
    try w.print("{f} {{ /* {f} */\n", .{
        name_cty.fmtTypeName(zcu),
        ty.fmt(pt),
    });
    if (payload_has_bits) {
        try w.writeByte(' ');
        if (overalign) {
            // Specify the alignment of `union { ... } payload;` to align the union's `struct`.
            try w.print("zig_align({d}) ", .{union_type.alignment.toByteUnits().?});
        }
        if (pack) try w.writeAll("zig_packed(");
        try w.writeAll("union {\n");
        for (0..enum_tag_ty.enumFieldCount(zcu)) |field_index| {
            const field_ty = ty.fieldType(field_index, zcu);
            if (!field_ty.hasRuntimeBits(zcu)) continue;
            const field_name = enum_tag_ty.enumFieldName(field_index, zcu).toSlice(ip);
            const field_cty: CType = try .lower(field_ty, deps, arena, zcu);
            try w.print("  {f}{f}{f};\n", .{
                field_cty.fmtDeclaratorPrefix(zcu),
                fmtIdentSolo(field_name),
                field_cty.fmtDeclaratorSuffix(zcu),
            });
        }
        try w.writeAll(" }");
        if (pack) try w.writeByte(')');
        try w.writeAll(" payload;\n");
    }
    if (union_type.has_runtime_tag) {
        const tag_cty: CType = try .lower(enum_tag_ty, deps, arena, zcu);
        try w.print(" {f}tag{f};\n", .{
            tag_cty.fmtDeclaratorPrefix(zcu),
            tag_cty.fmtDeclaratorSuffix(zcu),
        });
    }
    try w.writeAll("};\n");

    try writeStaticAssertLayout(ty, name_cty, w, zcu);
}
fn defineUnionExtern(
    ty: Type,
    deps: *CType.Dependencies,
    arena: Allocator,
    w: *Writer,
    pt: Zcu.PerThread,
) (Allocator.Error || Writer.Error)!void {
    const zcu = pt.zcu;
    if (!ty.hasRuntimeBits(zcu)) return;
    const ip = &zcu.intern_pool;

    const union_type = ip.loadUnionType(ty.toIntern());
    assert(!union_type.has_runtime_tag);
    const enum_tag_ty: Type = .fromInterned(union_type.enum_tag_type);

    // If there are any underaligned fields, we need to byte-pack the union.
    const pack: bool = for (union_type.field_types.get(ip)) |field_ty_ip| {
        const field_ty: Type = .fromInterned(field_ty_ip);
        if (!field_ty.hasRuntimeBits(zcu)) continue;
        const natural_align = field_ty.abiAlignment(zcu);
        if (natural_align.compareStrict(.gt, union_type.alignment)) break true;
    } else false;

    // If the alignment of other fields would not give the union sufficient alignment, we
    // need to align the first field (which does not affect its offset, because 0 is always
    // well-aligned) to indirectly specify the union alignment.
    const overalign: bool = switch (pack) {
        true => union_type.alignment.compareStrict(.gt, .@"1"),
        false => for (union_type.field_types.get(ip)) |field_ty_ip| {
            const field_ty: Type = .fromInterned(field_ty_ip);
            if (!field_ty.hasRuntimeBits(zcu)) continue;
            const natural_align = field_ty.abiAlignment(zcu);
            if (natural_align.compareStrict(.gte, union_type.alignment)) break false;
        } else overalign: {
            if (union_type.has_runtime_tag) {
                const tag_align = enum_tag_ty.abiAlignment(zcu);
                if (tag_align.compareStrict(.gte, union_type.alignment)) break :overalign false;
            }
            break :overalign true;
        },
    };

    if (pack) try w.writeAll("zig_packed(");

    const name_cty: CType = .{ .union_extern = ty };
    try w.print("{f} {{ /* {f} */\n", .{
        name_cty.fmtTypeName(zcu),
        ty.fmt(pt),
    });

    for (0..enum_tag_ty.enumFieldCount(zcu)) |field_index| {
        const field_ty = ty.fieldType(field_index, zcu);
        if (!field_ty.hasRuntimeBits(zcu)) continue;
        const field_name = enum_tag_ty.enumFieldName(field_index, zcu).toSlice(ip);
        const field_cty: CType = try .lower(field_ty, deps, arena, zcu);
        try w.writeByte(' ');
        if (overalign and field_index == 0) {
            // This is the first field; specify its alignment to align the union.
            try writeFieldAlign(field_ty, union_type.alignment, w, zcu);
        }
        try w.print("{f}{f}{f};\n", .{
            field_cty.fmtDeclaratorPrefix(zcu),
            fmtIdentSolo(field_name),
            field_cty.fmtDeclaratorSuffix(zcu),
        });
    }
    try w.writeByte('}');
    if (pack) try w.writeByte(')');
    try w.writeAll(";\n");

    try writeStaticAssertLayout(ty, name_cty, w, zcu);
}

/// Writes an annotation which, placed before a struct/union field declaration with field type `ty`,
/// will specify that field as having the given alignment.
fn writeFieldAlign(
    ty: Type,
    alignment: Alignment,
    w: *Writer,
    zcu: *const Zcu,
) Writer.Error!void {
    if (alignment.compareStrict(.lt, ty.abiAlignment(zcu))) {
        try w.print("zig_under_align({d}) ", .{alignment.toByteUnits().?});
    } else {
        try w.print("zig_align({d}) ", .{alignment.toByteUnits().?});
    }
}

/// Emits static assertions that the size and alignment of `cty` match those of the Zig type `ty`.
fn writeStaticAssertLayout(
    ty: Type,
    cty: CType,
    w: *Writer,
    zcu: *const Zcu,
) Writer.Error!void {
    try w.print(
        \\zig_static_assert(sizeof ({f}) == {d}, "incorrect size");
        \\zig_static_assert(_Alignof ({f}) == {d}, "incorrect alignment");
        \\
    , .{
        cty.fmtTypeName(zcu), ty.abiSize(zcu),
        cty.fmtTypeName(zcu), ty.abiAlignment(zcu).toByteUnits().?,
    });
}

const std = @import("std");
const assert = std.debug.assert;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const Zcu = @import("../../../Zcu.zig");
const Type = @import("../../../Type.zig");
const Value = @import("../../../Value.zig");
const CType = @import("../type.zig").CType;
const Alignment = @import("../../../InternPool.zig").Alignment;

const fmtIdentSolo = @import("../../c.zig").fmtIdentSolo;
