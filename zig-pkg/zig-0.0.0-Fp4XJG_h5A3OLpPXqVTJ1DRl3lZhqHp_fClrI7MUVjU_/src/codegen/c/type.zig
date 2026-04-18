pub const CType = union(enum) {
    pub const render_defs = @import("type/render_defs.zig");

    // The first nodes are primitive types (or standard typedefs).

    void,
    bool,
    int: Int,
    float: Float,

    // These next nodes are all typedefs, structs, or unions.

    @"fn": Type,
    @"enum": Type,
    bitpack: Type,
    @"struct": Type,
    union_auto: Type,
    union_extern: Type,
    slice: Type,
    opt: Type,
    arr: Type,
    vec: Type,
    errunion: struct { payload_ty: Type },
    aligned: struct {
        ty: Type,
        alignment: InternPool.Alignment,
    },
    bigint: BigInt,

    // The remaining nodes have children.

    pointer: struct {
        @"const": bool,
        @"volatile": bool,
        elem_ty: *const CType,
        nonstring: bool,
    },
    array: struct {
        len: u64,
        elem_ty: *const CType,
        nonstring: bool,
    },
    function: struct {
        param_tys: []const CType,
        ret_ty: *const CType,
        varargs: bool,
    },

    /// Returns `true` if this node has a postfix operator, meaning an `[...]` or `(...)` appears
    /// after the identifier in a declarator with this type. In this case, if this node is wrapped
    /// in a pointer type, we will need to add parentheses due to operator precedence.
    ///
    /// For instance, when lowering a Zig declaration `foo: *const fn (c_int) void`, it would be a
    /// bug to write the C declarator as `void *foo(int)`, because the `(int)` suffix declaring the
    /// function type has higher precedence than the `*` prefix declaring the pointer type. Instead,
    /// this type must be lowered as `void (*foo)(int)`.
    fn kind(cty: *const CType) enum {
        /// `cty` is just a C type specifier, i.e. a typedef or a named struct/union type.
        specifier,
        /// `cty` is a C function or array type. It will have a postfix "operator" in its suffix to
        /// declare the type, either `(...)` (for a function type) or `[...]` (for an array type).
        postfix_op,
        /// `cty` is a C pointer type. Its prefix will end with "*".
        pointer,
    } {
        return switch (cty.*) {
            .void,
            .bool,
            .int,
            .float,
            .@"fn",
            .@"enum",
            .bitpack,
            .@"struct",
            .union_auto,
            .union_extern,
            .slice,
            .opt,
            .arr,
            .vec,
            .errunion,
            .aligned,
            .bigint,
            => .specifier,

            .array,
            .function,
            => .postfix_op,

            .pointer => .pointer,
        };
    }

    pub const Int = enum {
        char,

        @"unsigned short",
        @"unsigned int",
        @"unsigned long",
        @"unsigned long long",

        @"signed short",
        @"signed int",
        @"signed long",
        @"signed long long",

        uint8_t,
        uint16_t,
        uint32_t,
        uint64_t,
        zig_u128,

        int8_t,
        int16_t,
        int32_t,
        int64_t,
        zig_i128,

        uintptr_t,
        intptr_t,

        pub fn bits(int: Int, target: *const std.Target) u16 {
            return switch (int) {
                // zig fmt: off
            .char => target.cTypeBitSize(.char),

            .@"unsigned short"     => target.cTypeBitSize(.ushort),
            .@"unsigned int"       => target.cTypeBitSize(.uint),
            .@"unsigned long"      => target.cTypeBitSize(.ulong),
            .@"unsigned long long" => target.cTypeBitSize(.ulonglong),

            .@"signed short"     => target.cTypeBitSize(.short),
            .@"signed int"       => target.cTypeBitSize(.int),
            .@"signed long"      => target.cTypeBitSize(.long),
            .@"signed long long" => target.cTypeBitSize(.longlong),

            .uintptr_t, .intptr_t => target.ptrBitWidth(),

            .uint8_t,  .int8_t   => 8,
            .uint16_t, .int16_t  => 16,
            .uint32_t, .int32_t  => 32,
            .uint64_t, .int64_t  => 64,
            .zig_u128, .zig_i128 => 128,
            // zig fmt: on
            };
        }
    };

    pub const BigInt = struct {
        limb_size: LimbSize,
        /// Always greater than 1.
        limbs_len: u16,

        pub const LimbSize = enum {
            @"8",
            @"16",
            @"32",
            @"64",
            @"128",
            pub fn bits(s: LimbSize) u8 {
                return switch (s) {
                    .@"8" => 8,
                    .@"16" => 16,
                    .@"32" => 32,
                    .@"64" => 64,
                    .@"128" => 128,
                };
            }
            pub fn unsigned(s: LimbSize) Int {
                return switch (s) {
                    .@"8" => .uint8_t,
                    .@"16" => .uint16_t,
                    .@"32" => .uint32_t,
                    .@"64" => .uint64_t,
                    .@"128" => .zig_u128,
                };
            }
            pub fn signed(s: LimbSize) Int {
                return switch (s) {
                    .@"8" => .int8_t,
                    .@"16" => .int16_t,
                    .@"32" => .int32_t,
                    .@"64" => .int64_t,
                    .@"128" => .zig_i128,
                };
            }
        };
    };

    pub const Float = enum {
        @"long double",
        zig_f16,
        zig_f32,
        zig_f64,
        zig_f80,
        zig_f128,
        zig_u128,
        zig_i128,
    };

    pub fn isStringElem(cty: CType) bool {
        return switch (cty) {
            .int => |int| switch (int) {
                .char, .int8_t, .uint8_t => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn lower(
        ty: Type,
        deps: *Dependencies,
        arena: Allocator,
        zcu: *const Zcu,
    ) Allocator.Error!CType {
        return lowerInner(ty, false, deps, arena, zcu);
    }
    fn lowerInner(
        start_ty: Type,
        allow_incomplete: bool,
        deps: *Dependencies,
        arena: Allocator,
        zcu: *const Zcu,
    ) Allocator.Error!CType {
        const gpa = zcu.comp.gpa;
        const ip = &zcu.intern_pool;
        var cur_ty = start_ty;
        while (true) {
            switch (cur_ty.zigTypeTag(zcu)) {
                .type,
                .comptime_int,
                .comptime_float,
                .undefined,
                .null,
                .enum_literal,
                .@"opaque",
                .noreturn,
                .void,
                => return .void,

                .bool => return .bool,

                .int, .error_set => switch (classifyInt(cur_ty, zcu)) {
                    .void => return .void,
                    .small => |s| return .{ .int = s },
                    .big => |big| {
                        try deps.bigint.put(gpa, big, {});
                        return .{ .bigint = big };
                    },
                },

                .float => return .{ .float = switch (cur_ty.toIntern()) {
                    .c_longdouble_type => .@"long double",
                    .f16_type => .zig_f16,
                    .f32_type => .zig_f32,
                    .f64_type => .zig_f64,
                    .f80_type => .zig_f80,
                    .f128_type => .zig_f128,
                    else => unreachable,
                } },
                .vector => {
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    return .{ .vec = cur_ty };
                },
                .array => {
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    return .{ .arr = cur_ty };
                },

                .pointer => {
                    const ptr = cur_ty.ptrInfo(zcu);
                    switch (ptr.flags.size) {
                        .slice => {
                            try deps.addType(gpa, cur_ty, allow_incomplete);
                            return .{ .slice = cur_ty };
                        },
                        .one, .many, .c => {
                            const elem_ty: Type = .fromInterned(ptr.child);
                            const is_fn_ptr = elem_ty.zigTypeTag(zcu) == .@"fn";
                            const elem_cty: CType = elem_cty: {
                                if (ptr.packed_offset.host_size > 0 and ptr.flags.vector_index == .none) {
                                    switch (classifyBitInt(.unsigned, ptr.packed_offset.host_size * 8, zcu)) {
                                        .void => break :elem_cty .void,
                                        .small => |s| break :elem_cty .{ .int = s },
                                        .big => |big| {
                                            try deps.bigint.put(gpa, big, {});
                                            break :elem_cty .{ .bigint = big };
                                        },
                                    }
                                }
                                if (ptr.flags.alignment != .none and !is_fn_ptr) {
                                    // The pointer has an explicit alignment---if it's an underalignment
                                    // then we need to use an "aligned" typedef.
                                    const ptr_align = ptr.flags.alignment;
                                    if (!alwaysHasLayout(elem_ty, ip) or
                                        ptr_align.compareStrict(.lt, elem_ty.abiAlignment(zcu)))
                                    {
                                        const gop = try deps.aligned_type_fwd.getOrPut(gpa, elem_ty.toIntern());
                                        if (!gop.found_existing) gop.value_ptr.* = 0;
                                        gop.value_ptr.* |= @as(u64, 1) << ptr_align.toLog2Units();
                                        break :elem_cty .{ .aligned = .{
                                            .ty = elem_ty,
                                            .alignment = ptr_align,
                                        } };
                                    }
                                }
                                break :elem_cty try .lowerInner(elem_ty, true, deps, arena, zcu);
                            };
                            const elem_cty_buf = try arena.create(CType);
                            elem_cty_buf.* = elem_cty;
                            return .{ .pointer = .{
                                .@"const" = ptr.flags.is_const and !is_fn_ptr,
                                .@"volatile" = ptr.flags.is_volatile and !is_fn_ptr,
                                .elem_ty = elem_cty_buf,
                                .nonstring = nonstring: {
                                    if (!elem_cty.isStringElem()) break :nonstring false;
                                    if (ptr.sentinel == .none) break :nonstring true;
                                    break :nonstring Value.compareHetero(
                                        .fromInterned(ptr.sentinel),
                                        .neq,
                                        .zero_comptime_int,
                                        zcu,
                                    );
                                },
                            } };
                        },
                    }
                },

                .@"fn" => {
                    const func_type = ip.indexToKey(cur_ty.toIntern()).func_type;
                    direct: {
                        const ret_ty: Type = .fromInterned(func_type.return_type);
                        if (!alwaysHasLayout(ret_ty, ip)) break :direct;
                        var params_len: usize = 0; // only counts parameter types with runtime bits
                        for (func_type.param_types.get(ip)) |param_ty_ip| {
                            const param_ty: Type = .fromInterned(param_ty_ip);
                            if (!alwaysHasLayout(param_ty, ip)) break :direct;
                            if (param_ty.hasRuntimeBits(zcu)) params_len += 1;
                        }
                        // We can actually write this function type directly!
                        if (!cur_ty.fnHasRuntimeBits(zcu)) return .void;
                        const ret_cty_buf = try arena.create(CType);
                        if (!ret_ty.hasRuntimeBits(zcu)) {
                            // Incomplete function return types must always be `void`.
                            ret_cty_buf.* = .void;
                        } else {
                            ret_cty_buf.* = try .lowerInner(ret_ty, allow_incomplete, deps, arena, zcu);
                        }
                        const param_cty_buf = try arena.alloc(CType, params_len);
                        var param_index: usize = 0;
                        for (func_type.param_types.get(ip)) |param_ty_ip| {
                            const param_ty: Type = .fromInterned(param_ty_ip);
                            if (!param_ty.hasRuntimeBits(zcu)) continue;
                            param_cty_buf[param_index] = try .lowerInner(param_ty, allow_incomplete, deps, arena, zcu);
                            param_index += 1;
                        }
                        assert(param_index == params_len);
                        return .{ .function = .{
                            .ret_ty = ret_cty_buf,
                            .param_tys = param_cty_buf,
                            .varargs = func_type.is_var_args,
                        } };
                    }
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    return .{ .@"fn" = cur_ty };
                },

                .@"struct" => {
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    switch (cur_ty.containerLayout(zcu)) {
                        .auto, .@"extern" => return .{ .@"struct" = cur_ty },
                        .@"packed" => return .{ .bitpack = cur_ty },
                    }
                },
                .@"union" => {
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    switch (cur_ty.containerLayout(zcu)) {
                        .auto => return .{ .union_auto = cur_ty },
                        .@"extern" => return .{ .union_extern = cur_ty },
                        .@"packed" => return .{ .bitpack = cur_ty },
                    }
                },
                .@"enum" => {
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    return .{ .@"enum" = cur_ty };
                },

                .optional => {
                    // This query does not require any type resolution.
                    if (cur_ty.optionalReprIsPayload(zcu)) {
                        // Either a pointer-like optional, or an optional error set. Just lower the payload.
                        cur_ty = cur_ty.optionalChild(zcu);
                        continue;
                    }
                    if (alwaysHasLayout(cur_ty, ip)) switch (classifyOptional(cur_ty, zcu)) {
                        .error_set, .ptr_like, .slice_like => unreachable, // handled above
                        .npv_payload => return .void,
                        .opv_payload, .@"struct" => {},
                    };
                    try deps.addType(gpa, cur_ty, allow_incomplete);
                    return .{ .opt = cur_ty };
                },

                .error_union => {
                    const payload_ty = cur_ty.errorUnionPayload(zcu);
                    if (allow_incomplete) {
                        try deps.errunion_type_fwd.put(gpa, payload_ty.toIntern(), {});
                    } else {
                        try deps.errunion_type.put(gpa, payload_ty.toIntern(), {});
                    }
                    return .{ .errunion = .{
                        .payload_ty = payload_ty,
                    } };
                },

                .frame,
                .@"anyframe",
                => unreachable,
            }
            comptime unreachable;
        }
    }

    pub fn classifyOptional(opt_ty: Type, zcu: *const Zcu) enum {
        /// The optional is something like `?noreturn`; it lowers to `void`.
        npv_payload,
        /// The payload type is an error set; the representation matches that of the error set, with
        /// the value 0 representing `null`.
        error_set,
        /// The payload type is a non-optional pointer; the NULL pointer is used for `null`.
        ptr_like,
        /// The payload type is a non-optional slice; a NULL pointer field is used for `null`.
        slice_like,
        /// The optional is something like `?void`; it lowers to a struct, but one containing only
        /// one field `is_null` (the payload is omitted).
        opv_payload,
        /// The optional uses the "default" lowering of a struct with two fields, like this:
        ///   struct optional_1234 { payload_ty payload; bool is_null; }
        @"struct",
    } {
        const payload_ty = opt_ty.optionalChild(zcu);
        if (opt_ty.optionalReprIsPayload(zcu)) {
            return switch (payload_ty.zigTypeTag(zcu)) {
                .error_set => .error_set,
                .pointer => if (payload_ty.isSlice(zcu)) .slice_like else .ptr_like,
                else => unreachable,
            };
        } else {
            return switch (payload_ty.classify(zcu)) {
                .no_possible_value => .npv_payload,
                .one_possible_value => .opv_payload,
                else => .@"struct",
            };
        }
    }

    pub const IntClass = union(enum) {
        /// The integer type is zero-bit, so lowers to `void`.
        void,
        /// The integer is under 128 bits long, so lowers to this C integer type.
        small: Int,
        /// The integer is over 128 bits long, so lowers to an array of limbs.
        big: BigInt,
    };

    /// Asserts that `ty` is an integer, enum, bitpack, or error set.
    pub fn classifyInt(ty: Type, zcu: *const Zcu) IntClass {
        const int_ty: Type = switch (ty.zigTypeTag(zcu)) {
            .error_set => return classifyBitInt(.unsigned, zcu.errorSetBits(), zcu),
            .@"enum" => ty.intTagType(zcu),
            .@"struct", .@"union" => ty.bitpackBackingInt(zcu),
            .int => ty,
            else => unreachable,
        };
        switch (int_ty.toIntern()) {
            // zig fmt: off
        .usize_type => return .{ .small = .uintptr_t },
        .isize_type => return .{ .small = .intptr_t },

        .c_char_type => return .{ .small = .char },

        .c_short_type    => return .{ .small = .@"signed short" },
        .c_int_type      => return .{ .small = .@"signed int" },
        .c_long_type     => return .{ .small = .@"signed long" },
        .c_longlong_type => return .{ .small = .@"signed long long" },

        .c_ushort_type    => return .{ .small = .@"unsigned short" },
        .c_uint_type      => return .{ .small = .@"unsigned int" },
        .c_ulong_type     => return .{ .small = .@"unsigned long" },
        .c_ulonglong_type => return .{ .small = .@"unsigned long long" },
        // zig fmt: on

            else => {
                const int = ty.intInfo(zcu);
                return classifyBitInt(int.signedness, int.bits, zcu);
            },
        }
    }
    fn classifyBitInt(signedness: std.builtin.Signedness, bits: u16, zcu: *const Zcu) IntClass {
        return switch (bits) {
            0 => .void,
            1...8 => switch (signedness) {
                .unsigned => .{ .small = .uint8_t },
                .signed => .{ .small = .int8_t },
            },
            9...16 => switch (signedness) {
                .unsigned => .{ .small = .uint16_t },
                .signed => .{ .small = .int16_t },
            },
            17...32 => switch (signedness) {
                .unsigned => .{ .small = .uint32_t },
                .signed => .{ .small = .int32_t },
            },
            33...64 => switch (signedness) {
                .unsigned => .{ .small = .uint64_t },
                .signed => .{ .small = .int64_t },
            },
            65...128 => switch (signedness) {
                .unsigned => .{ .small = .zig_u128 },
                .signed => .{ .small = .zig_i128 },
            },
            else => {
                @branchHint(.unlikely);
                const target = zcu.getTarget();
                const limb_bytes = std.zig.target.intAlignment(target, bits);
                return .{ .big = .{
                    .limb_size = switch (limb_bytes) {
                        1 => .@"8",
                        2 => .@"16",
                        4 => .@"32",
                        8 => .@"64",
                        16 => .@"128",
                        else => unreachable,
                    },
                    .limbs_len = @divExact(
                        std.zig.target.intByteSize(target, bits),
                        limb_bytes,
                    ),
                } };
            },
        };
    }

    /// Describes a set of types which must be declared or completed in the C source file before
    /// some string of rendered C code (such as a function), due to said C code using these types.
    pub const Dependencies = struct {
        /// Key is any Zig type which corresponds to a C `struct`, `union`, or `typedef`. That C
        /// type must be declared and complete.
        type: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),

        /// Key is a Zig type which is the *payload* of an error union. The C `struct` type
        /// corresponding to such an error union must be declared and complete.
        ///
        /// These are separate from `type` to avoid redundant types for every different error set
        /// used with the same payload type---for instance a different C type for every `E!void`.
        errunion_type: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),

        /// Like `type`, but the type does not necessarily need to be completed yet: a forward
        /// declaration is sufficient.
        type_fwd: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),

        /// Like `errunion_type`, but the type does not necessarily need to be completed yet: a
        /// forward declaration is sufficient.
        errunion_type_fwd: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),

        /// Key is a Zig type; value is a bitmask of alignments. For every bit which is set, an
        /// aligned typedef is required. For instance, if bit 3 is set, the C type 'aligned__8_foo'
        /// must be declared through `typedef` (but not necessarily completed yet).
        aligned_type_fwd: std.AutoArrayHashMapUnmanaged(InternPool.Index, u64),

        /// Key specifies a big-int type whose C `struct` must be declared and complete.
        bigint: std.AutoArrayHashMapUnmanaged(BigInt, void),

        pub const empty: Dependencies = .{
            .type = .empty,
            .errunion_type = .empty,
            .type_fwd = .empty,
            .errunion_type_fwd = .empty,
            .aligned_type_fwd = .empty,
            .bigint = .empty,
        };

        pub fn deinit(deps: *Dependencies, gpa: Allocator) void {
            deps.type.deinit(gpa);
            deps.errunion_type.deinit(gpa);
            deps.type_fwd.deinit(gpa);
            deps.errunion_type_fwd.deinit(gpa);
            deps.aligned_type_fwd.deinit(gpa);
            deps.bigint.deinit(gpa);
        }

        pub fn clearRetainingCapacity(deps: *Dependencies) void {
            deps.type.clearRetainingCapacity();
            deps.errunion_type.clearRetainingCapacity();
            deps.type_fwd.clearRetainingCapacity();
            deps.errunion_type_fwd.clearRetainingCapacity();
            deps.aligned_type_fwd.clearRetainingCapacity();
            deps.bigint.clearRetainingCapacity();
        }

        pub fn move(deps: *Dependencies) Dependencies {
            const moved = deps.*;
            deps.* = .empty;
            return moved;
        }

        fn addType(deps: *Dependencies, gpa: Allocator, ty: Type, allow_incomplete: bool) Allocator.Error!void {
            if (allow_incomplete) {
                try deps.type_fwd.put(gpa, ty.toIntern(), {});
            } else {
                try deps.type.put(gpa, ty.toIntern(), {});
            }
        }
    };

    /// Formats the bytes which appear *before* the identifier in a declarator. This includes the
    /// type specifier and all "prefix type operators" in the declarator. e.g:
    /// * for the declarator "int foo", writes "int "
    /// * for the declarator "struct thing *foo", writes "struct thing *"
    /// * for the declarator "void *(*foo)(int)", writes "void *(*"
    pub fn fmtDeclaratorPrefix(cty: CType, zcu: *const Zcu) Formatter {
        return .{
            .cty = cty,
            .zcu = zcu,
            .kind = .declarator_prefix,
        };
    }
    /// Formats the bytes which appear *before* the identifier in a declarator. This includes the
    /// type specifier and all "prefix type operators" in the declarator. e.g:
    /// * for the declarator "int foo", writes ""
    /// * for the declarator "struct thing *foo", writes ""
    /// * for the declarator "void *(*foo)(int)", writes ")(int)"
    pub fn fmtDeclaratorSuffix(cty: CType, zcu: *const Zcu) Formatter {
        return .{
            .cty = cty,
            .zcu = zcu,
            .kind = .declarator_suffix,
        };
    }
    /// Like `fmtDeclaratorSuffix`, except never emits a `zig_nonstring` annotation.
    pub fn fmtDeclaratorSuffixIgnoreNonstring(cty: CType, zcu: *const Zcu) Formatter {
        return .{
            .cty = cty,
            .zcu = zcu,
            .kind = .declarator_suffix_ignore_nonstring,
        };
    }
    /// Formats a type's full name, e.g. "int", "struct foo *", "void *(uint32_t)".
    ///
    /// This is almost identical to `fmtDeclaratorPrefix` followed by `fmtDeclaratorSuffix`, but
    /// that sequence of calls may emit trailing whitespace where this one does not---for instance,
    /// those calls would write the type "void" as "void ".
    pub fn fmtTypeName(cty: CType, zcu: *const Zcu) Formatter {
        return .{
            .cty = cty,
            .zcu = zcu,
            .kind = .type_name,
        };
    }

    const Formatter = struct {
        cty: CType,
        zcu: *const Zcu,
        kind: enum { type_name, declarator_prefix, declarator_suffix, declarator_suffix_ignore_nonstring },

        pub fn format(ctx: Formatter, w: *Writer) Writer.Error!void {
            switch (ctx.kind) {
                .type_name => {
                    try ctx.cty.writeTypePrefix(w, ctx.zcu);
                    try ctx.cty.writeTypeSuffix(w, ctx.zcu);
                },
                .declarator_prefix => {
                    try ctx.cty.writeTypePrefix(w, ctx.zcu);
                    switch (ctx.cty.kind()) {
                        .specifier => try w.writeByte(' '), // write "int " rather than "int"
                        .pointer => {}, // we already have something like "foo *"
                        .postfix_op => {}, // we already have something like "ret_ty "
                    }
                },
                .declarator_suffix => {
                    try ctx.cty.writeTypeSuffix(w, ctx.zcu);
                    const nonstring = switch (ctx.cty) {
                        .array => |arr| arr.nonstring,
                        .pointer => |ptr| ptr.nonstring,
                        else => false,
                    };
                    if (nonstring) try w.writeAll(" zig_nonstring");
                },
                .declarator_suffix_ignore_nonstring => {
                    try ctx.cty.writeTypeSuffix(w, ctx.zcu);
                },
            }
        }
    };

    fn writeTypePrefix(cty: CType, w: *Writer, zcu: *const Zcu) Writer.Error!void {
        switch (cty) {
            .void => try w.writeAll("void"),
            .bool => try w.writeAll("bool"),
            .int => |int| try w.writeAll(@tagName(int)),
            .float => |float| try w.writeAll(@tagName(float)),
            .@"fn" => |ty| try w.print("{f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .@"enum" => |ty| try w.print("enum__{f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .bitpack => |ty| try w.print("bitpack__{f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .@"struct" => |ty| try w.print("struct {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .union_auto => |ty| try w.print("struct {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .union_extern => |ty| try w.print("union {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .slice => |ty| try w.print("struct {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .opt => |ty| try w.print("struct {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .arr => |ty| try w.print("struct {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .vec => |ty| try w.print("struct {f}_{d}", .{ fmtZigType(ty, zcu), ty.toIntern() }),
            .errunion => |eu| try w.print("struct errunion_{f}_{d}", .{
                fmtZigType(eu.payload_ty, zcu),
                eu.payload_ty.toIntern(),
            }),
            .aligned => |aligned| try w.print("aligned__{d}_{f}_{d}", .{
                aligned.alignment.toByteUnits().?,
                fmtZigType(aligned.ty, zcu),
                aligned.ty.toIntern(),
            }),
            .bigint => |bigint| try w.print("struct int_{d}x{d}", .{
                bigint.limb_size.bits(),
                bigint.limbs_len,
            }),

            .pointer => |ptr| {
                try ptr.elem_ty.writeTypePrefix(w, zcu);
                switch (ptr.elem_ty.kind()) {
                    .pointer, .postfix_op => {},
                    .specifier => {
                        // We want "foo *" or "foo const *" rather than "foo*" or "fooconst *".
                        try w.writeByte(' ');
                    },
                }
                if (ptr.@"const") try w.writeAll("const ");
                if (ptr.@"volatile") try w.writeAll("volatile ");
                switch (ptr.elem_ty.kind()) {
                    .specifier, .pointer => {},
                    .postfix_op => {
                        // Prefix "*" is lower precedence than postfix "(x)" or "[x]" so use parens
                        // to disambiguate; e.g. "void (*foo)(int)" instead of "void *foo(int)".
                        try w.writeByte('(');
                    },
                }
                try w.writeByte('*');
            },

            .array => |array| {
                try array.elem_ty.writeTypePrefix(w, zcu);
                switch (array.elem_ty.kind()) {
                    .pointer, .postfix_op => {},
                    .specifier => {
                        // We want e.g. "struct foo [5]" rather than "struct foo[5]".
                        try w.writeByte(' ');
                    },
                }
            },

            .function => |function| {
                try function.ret_ty.writeTypePrefix(w, zcu);
                switch (function.ret_ty.kind()) {
                    .pointer, .postfix_op => {},
                    .specifier => {
                        // We want e.g. "struct foo (void)" rather than "struct foo(void)".
                        try w.writeByte(' ');
                    },
                }
            },
        }
    }
    fn writeTypeSuffix(cty: CType, w: *Writer, zcu: *const Zcu) Writer.Error!void {
        switch (cty) {
            // simple type specifiers
            .void,
            .bool,
            .int,
            .float,
            .@"fn",
            .@"enum",
            .bitpack,
            .@"struct",
            .union_auto,
            .union_extern,
            .slice,
            .opt,
            .arr,
            .vec,
            .errunion,
            .aligned,
            .bigint,
            => {},

            .pointer => |ptr| {
                // Match opening paren "(" write `writeTypePrefix`.
                switch (ptr.elem_ty.kind()) {
                    .specifier, .pointer => {},
                    .postfix_op => try w.writeByte(')'),
                }
                try ptr.elem_ty.writeTypeSuffix(w, zcu);
            },

            .array => |array| {
                try w.print("[{d}]", .{array.len});
                try array.elem_ty.writeTypeSuffix(w, zcu);
            },

            .function => |function| {
                if (function.param_tys.len == 0 and !function.varargs) {
                    try w.writeAll("(void)");
                } else {
                    try w.writeByte('(');
                    for (function.param_tys, 0..) |param_ty, param_index| {
                        if (param_index > 0) try w.writeAll(", ");
                        try param_ty.writeTypePrefix(w, zcu);
                        try param_ty.writeTypeSuffix(w, zcu);
                    }
                    if (function.varargs) {
                        if (function.param_tys.len > 0) try w.writeAll(", ");
                        try w.writeAll("...");
                    }
                    try w.writeByte(')');
                }
                try function.ret_ty.writeTypeSuffix(w, zcu);
            },
        }
    }

    /// Renders Zig types using only bytes allowed in C identifiers in a somewhat-understandable
    /// way. The output is *not* guaranteed to be unique.
    fn fmtZigType(ty: Type, zcu: *const Zcu) FormatZigType {
        return .{ .ty = ty, .zcu = zcu };
    }
    const FormatZigType = struct {
        ty: Type,
        zcu: *const Zcu,
        pub fn format(ctx: FormatZigType, w: *Writer) Writer.Error!void {
            const ty = ctx.ty;
            const zcu = ctx.zcu;
            const ip = &zcu.intern_pool;
            switch (ty.zigTypeTag(zcu)) {
                .frame => unreachable,
                .@"anyframe" => unreachable,

                .type => try w.writeAll("type"),
                .void => try w.writeAll("void"),
                .bool => try w.writeAll("bool"),
                .noreturn => try w.writeAll("noreturn"),
                .comptime_int => try w.writeAll("comptime_int"),
                .comptime_float => try w.writeAll("comptime_float"),
                .enum_literal => try w.writeAll("enum_literal"),
                .undefined => try w.writeAll("undefined"),
                .null => try w.writeAll("null"),

                .int => switch (ty.toIntern()) {
                    .usize_type => try w.writeAll("usize"),
                    .isize_type => try w.writeAll("isize"),
                    .c_char_type => try w.writeAll("c_char"),
                    .c_short_type => try w.writeAll("c_short"),
                    .c_ushort_type => try w.writeAll("c_ushort"),
                    .c_int_type => try w.writeAll("c_int"),
                    .c_uint_type => try w.writeAll("c_uint"),
                    .c_long_type => try w.writeAll("c_long"),
                    .c_ulong_type => try w.writeAll("c_ulong"),
                    .c_longlong_type => try w.writeAll("c_longlong"),
                    .c_ulonglong_type => try w.writeAll("c_ulonglong"),
                    else => {
                        const info = ty.intInfo(zcu);
                        switch (info.signedness) {
                            .unsigned => try w.print("u{d}", .{info.bits}),
                            .signed => try w.print("i{d}", .{info.bits}),
                        }
                    },
                },
                .float => switch (ty.toIntern()) {
                    .c_longdouble_type => try w.writeAll("c_longdouble"),
                    .f16_type => try w.writeAll("f16"),
                    .f32_type => try w.writeAll("f32"),
                    .f64_type => try w.writeAll("f64"),
                    .f80_type => try w.writeAll("f80"),
                    .f128_type => try w.writeAll("f128"),
                    else => unreachable,
                },
                .error_set => switch (ty.toIntern()) {
                    .anyerror_type => try w.writeAll("anyerror"),
                    else => try w.print("error_{d}", .{@intFromEnum(ty.toIntern())}),
                },
                .optional => try w.print("opt_{f}", .{fmtZigType(ty.optionalChild(zcu), zcu)}),
                .error_union => try w.print("errunion_{f}", .{fmtZigType(ty.errorUnionPayload(zcu), zcu)}),

                .pointer => switch (ty.ptrSize(zcu)) {
                    .one, .many, .c => try w.print("ptr_{f}", .{fmtZigType(ty.childType(zcu), zcu)}),
                    .slice => try w.print("slice_{f}", .{fmtZigType(ty.childType(zcu), zcu)}),
                },
                .@"fn" => {
                    const func_type = ip.indexToKey(ty.toIntern()).func_type;
                    try w.writeAll("fn_"); // intentional double underscore to start
                    for (func_type.param_types.get(ip)) |param_ty_ip| {
                        const param_ty: Type = .fromInterned(param_ty_ip);
                        if (param_ty.isGenericPoison()) {
                            try w.writeAll("_Pgeneric");
                        } else {
                            try w.print("_P{f}", .{fmtZigType(param_ty, zcu)});
                        }
                    }
                    if (func_type.is_var_args) {
                        try w.writeAll("_VA");
                    }
                    const ret_ty: Type = .fromInterned(func_type.return_type);
                    if (ret_ty.isGenericPoison()) {
                        try w.writeAll("_Rgeneric");
                    } else if (ret_ty.zigTypeTag(zcu) == .error_union and ret_ty.errorUnionPayload(zcu).isGenericPoison()) {
                        try w.writeAll("_Rgeneric_ies");
                    } else {
                        try w.print("_R{f}", .{fmtZigType(ret_ty, zcu)});
                    }
                },

                .vector => try w.print("vec_{d}_{f}", .{
                    ty.arrayLen(zcu),
                    fmtZigType(ty.childType(zcu), zcu),
                }),

                .array => if (ty.sentinel(zcu)) |s| try w.print("arr_{d}s{d}_{f}", .{
                    ty.arrayLen(zcu),
                    @intFromEnum(s.toIntern()),
                    fmtZigType(ty.childType(zcu), zcu),
                }) else try w.print("arr_{d}_{f}", .{
                    ty.arrayLen(zcu),
                    fmtZigType(ty.childType(zcu), zcu),
                }),

                .@"struct" => if (ty.isTuple(zcu)) {
                    const len = ty.structFieldCount(zcu);
                    try w.print("tuple_{d}", .{len});
                    for (0..len) |field_index| {
                        const field_ty = ty.fieldType(field_index, zcu);
                        try w.print("_{f}", .{fmtZigType(field_ty, zcu)});
                    }
                } else {
                    const name = ty.containerTypeName(ip).toSlice(ip);
                    try w.print("{f}", .{@import("../c.zig").fmtIdentUnsolo(name)});
                },
                .@"opaque" => if (ty.toIntern() == .anyopaque_type) {
                    try w.writeAll("anyopaque");
                } else {
                    const name = ty.containerTypeName(ip).toSlice(ip);
                    try w.print("{f}", .{@import("../c.zig").fmtIdentUnsolo(name)});
                },
                .@"union", .@"enum" => {
                    const name = ty.containerTypeName(ip).toSlice(ip);
                    try w.print("{f}", .{@import("../c.zig").fmtIdentUnsolo(name)});
                },
            }
        }
    };

    /// Returns `true` if the layout of `ty` is known without any type resolution required. This
    /// allows some types to be lowered directly where 'typedef' would otherwise be necessary.
    fn alwaysHasLayout(ty: Type, ip: *const InternPool) bool {
        return switch (ip.indexToKey(ty.toIntern())) {
            .int_type,
            .ptr_type,
            .anyframe_type,
            .simple_type,
            .opaque_type,
            .error_set_type,
            .inferred_error_set_type,
            => true,

            .struct_type,
            .union_type,
            .enum_type,
            => false,

            .array_type => |arr| alwaysHasLayout(.fromInterned(arr.child), ip),
            .vector_type => |vec| alwaysHasLayout(.fromInterned(vec.child), ip),
            .opt_type => |child| alwaysHasLayout(.fromInterned(child), ip),
            .error_union_type => |eu| alwaysHasLayout(.fromInterned(eu.payload_type), ip),

            .tuple_type => |tuple| for (tuple.types.get(ip)) |field_ty| {
                if (!alwaysHasLayout(.fromInterned(field_ty), ip)) break false;
            } else true,

            .func_type => |f| for (f.param_types.get(ip)) |param_ty| {
                if (!alwaysHasLayout(.fromInterned(param_ty), ip)) break false;
            } else alwaysHasLayout(.fromInterned(f.return_type), ip),

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
};

const Zcu = @import("../../Zcu.zig");
const Type = @import("../../Type.zig");
const Value = @import("../../Value.zig");
const InternPool = @import("../../InternPool.zig");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
