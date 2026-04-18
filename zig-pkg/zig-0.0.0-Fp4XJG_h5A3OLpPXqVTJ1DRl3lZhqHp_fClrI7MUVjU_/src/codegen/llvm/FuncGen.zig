const FuncGen = @This();

object: *Object,
nav_index: InternPool.Nav.Index,
pt: Zcu.PerThread,
gpa: Allocator,
air: Air,
liveness: Air.Liveness,
wip: Builder.WipFunction,
is_naked: bool,
fuzz: ?Fuzz,

file: Builder.Metadata,
scope: Builder.Metadata,

inlined_at: Builder.Metadata.Optional,

base_line: u32,
prev_dbg_line: u32,
prev_dbg_column: u32,

/// This stores the LLVM values used in a function, such that they can be referred to
/// in other instructions. This table is cleared before every function is generated.
func_inst_table: std.AutoHashMapUnmanaged(Air.Inst.Ref, Builder.Value),

/// If the return type is sret, this is the result pointer. Otherwise null.
/// Note that this can disagree with isByRef for the return type in the case
/// of C ABI functions.
ret_ptr: Builder.Value,
/// Any function that needs to perform Valgrind client requests needs an array alloca
/// instruction, however a maximum of one per function is needed.
valgrind_client_request_array: Builder.Value = .none,
/// These fields are used to refer to the LLVM value of the function parameters
/// in an Arg instruction.
/// This list may be shorter than the list according to the zig type system;
/// it omits 0-bit types. If the function uses sret as the first parameter,
/// this slice does not include it.
args: []const Builder.Value,
arg_index: u32,
arg_inline_index: u32,

err_ret_trace: Builder.Value,

/// This data structure is used to implement breaking to blocks.
blocks: std.AutoHashMapUnmanaged(Air.Inst.Index, struct {
    parent_bb: Builder.Function.Block.Index,
    breaks: *BreakList,
}),

/// Maps `loop` instructions to the bb to branch to to repeat the loop.
loops: std.AutoHashMapUnmanaged(Air.Inst.Index, Builder.Function.Block.Index),

/// Maps `loop_switch_br` instructions to the information required to lower
/// dispatches (`switch_dispatch` instructions).
switch_dispatch_info: std.AutoHashMapUnmanaged(Air.Inst.Index, SwitchDispatchInfo),

sync_scope: Builder.SyncScope,

disable_intrinsics: bool,

/// Have we seen loads or stores involving `allowzero` pointers?
allowzero_access: bool,

/// In general, codegen should never emit errors; we cannot report useful source locations for them
/// and they don't really play nicely with incremental compilation. The LLVM backend mostly obeys
/// this rule. Where it does not, it calls `todo` to emit an error, and results in this error set
/// being used for the function
///
/// Please avoid using this error set in new code. Ideally, every fallible function in this file
/// should have the error set `Allocator.Error`.
const TodoError = Zcu.CodegenFailError;

/// Avoid introducing new calls to this function---see documentation comment on `TodoError`.
fn todo(fg: *FuncGen, comptime format: []const u8, args: anytype) TodoError {
    @branchHint(.cold);
    return fg.object.zcu.codegenFail(
        fg.nav_index,
        "TODO (LLVM): " ++ format,
        args,
    );
}

fn ownerModule(fg: *const FuncGen) *Package.Module {
    return fg.object.zcu.navFileScope(fg.nav_index).mod.?;
}

fn maybeMarkAllowZeroAccess(self: *FuncGen, info: InternPool.Key.PtrType) void {
    // LLVM already considers null pointers to be valid in non-generic address spaces, so avoid
    // pessimizing optimization for functions with accesses to such pointers.
    if (info.flags.address_space == .generic and info.flags.is_allowzero) self.allowzero_access = true;
}

pub const Fuzz = struct {
    counters_variable: Builder.Variable.Index,
    pcs: std.ArrayList(Builder.Constant),

    fn deinit(f: *Fuzz, gpa: Allocator) void {
        f.pcs.deinit(gpa);
        f.* = undefined;
    }
};

const SwitchDispatchInfo = struct {
    /// These are the blocks corresponding to each switch case.
    /// The final element corresponds to the `else` case.
    /// Slices allocated into `gpa`.
    case_blocks: []Builder.Function.Block.Index,
    /// This is `.none` if `jmp_table` is set, since we won't use a `switch` instruction to dispatch.
    switch_weights: Builder.Function.Instruction.BrCond.Weights,
    /// If not `null`, we have manually constructed a jump table to reach the desired block.
    /// `table` can be used if the value is between `min` and `max` inclusive.
    /// We perform this lowering manually to avoid some questionable behavior from LLVM.
    /// See `airSwitchBr` for details.
    jmp_table: ?JmpTable,

    const JmpTable = struct {
        min: Builder.Constant,
        max: Builder.Constant,
        in_bounds_hint: enum { none, unpredictable, likely, unlikely },
        /// Pointer to the jump table itself, to be used with `indirectbr`.
        /// The index into the jump table is the dispatch condition minus `min`.
        /// The table values are `blockaddress` constants corresponding to blocks in `case_blocks`.
        table: Builder.Constant,
        /// `true` if `table` conatins a reference to the `else` block.
        /// In this case, the `indirectbr` must include the `else` block in its target list.
        table_includes_else: bool,
    };
};

const BreakList = union {
    list: std.MultiArrayList(struct {
        bb: Builder.Function.Block.Index,
        val: Builder.Value,
    }),
    len: usize,
};

pub fn deinit(self: *FuncGen) void {
    const gpa = self.gpa;
    if (self.fuzz) |*f| f.deinit(self.gpa);
    self.wip.deinit();
    self.func_inst_table.deinit(gpa);
    self.blocks.deinit(gpa);
    self.loops.deinit(gpa);
    var it = self.switch_dispatch_info.valueIterator();
    while (it.next()) |info| {
        self.gpa.free(info.case_blocks);
    }
    self.switch_dispatch_info.deinit(gpa);
}

fn resolveInst(self: *FuncGen, inst: Air.Inst.Ref) Allocator.Error!Builder.Value {
    const gpa = self.gpa;
    const gop = try self.func_inst_table.getOrPut(gpa, inst);
    if (gop.found_existing) return gop.value_ptr.*;

    const llvm_val = try self.resolveValue(.fromInterned(inst.toInterned().?));
    gop.value_ptr.* = llvm_val.toValue();
    return llvm_val.toValue();
}

fn resolveValue(self: *FuncGen, val: Value) Allocator.Error!Builder.Constant {
    const o = self.object;
    const zcu = o.zcu;
    const ty = val.typeOf(zcu);
    if (!isByRef(ty, zcu)) {
        return o.lowerValue(val.toIntern());
    } else {
        // We need a pointer to a global constant, i.e. a UAV.
        return o.lowerUavRef(
            val.toIntern(),
            ty.abiAlignment(zcu),
            target_util.defaultAddressSpace(zcu.getTarget(), .global_constant),
        );
    }
}

pub fn genBody(self: *FuncGen, body: []const Air.Inst.Index, coverage_point: Air.CoveragePoint) TodoError!void {
    const o = self.object;
    const zcu = self.object.zcu;
    const ip = &zcu.intern_pool;
    const air_tags = self.air.instructions.items(.tag);
    switch (coverage_point) {
        .none => {},
        .poi => if (self.fuzz) |*fuzz| {
            const poi_index = fuzz.pcs.items.len;
            const base_ptr = fuzz.counters_variable.toValue(&o.builder);
            const ptr = try self.ptraddConst(base_ptr, poi_index);
            const one = try o.builder.intValue(.i8, 1);
            _ = try self.wip.atomicrmw(.normal, .add, ptr, one, self.sync_scope, .monotonic, .default, "");

            // LLVM does not allow blockaddress on the entry block.
            const pc = if (self.wip.cursor.block == .entry)
                self.wip.function.toConst(&o.builder)
            else
                try o.builder.blockAddrConst(self.wip.function, self.wip.cursor.block);
            const gpa = self.gpa;
            try fuzz.pcs.append(gpa, pc);
        },
    }
    for (body, 0..) |inst, i| {
        if (self.liveness.isUnused(inst) and !self.air.mustLower(inst, ip)) continue;

        const val: Builder.Value = switch (air_tags[@intFromEnum(inst)]) {
            // zig fmt: off

            // No "scalarize" legalizations are enabled, so these instructions never appear.
            .legalize_vec_elem_val   => unreachable,
            .legalize_vec_store_elem => unreachable,
            // No soft float legalizations are enabled.
            .legalize_compiler_rt_call => unreachable,

            .add            => try self.airAdd(inst, .normal),
            .add_optimized  => try self.airAdd(inst, .fast),
            .add_wrap       => try self.airAddWrap(inst),
            .add_sat        => try self.airAddSat(inst),

            .sub            => try self.airSub(inst, .normal),
            .sub_optimized  => try self.airSub(inst, .fast),
            .sub_wrap       => try self.airSubWrap(inst),
            .sub_sat        => try self.airSubSat(inst),

            .mul           => try self.airMul(inst, .normal),
            .mul_optimized => try self.airMul(inst, .fast),
            .mul_wrap      => try self.airMulWrap(inst),
            .mul_sat       => try self.airMulSat(inst),

            .add_safe => try self.airSafeArithmetic(inst, .@"sadd.with.overflow", .@"uadd.with.overflow"),
            .sub_safe => try self.airSafeArithmetic(inst, .@"ssub.with.overflow", .@"usub.with.overflow"),
            .mul_safe => try self.airSafeArithmetic(inst, .@"smul.with.overflow", .@"umul.with.overflow"),

            .div_float => try self.airDivFloat(inst, .normal),
            .div_trunc => try self.airDivTrunc(inst, .normal),
            .div_floor => try self.airDivFloor(inst, .normal),
            .div_exact => try self.airDivExact(inst, .normal),
            .rem       => try self.airRem(inst, .normal),
            .mod       => try self.airMod(inst, .normal),
            .abs       => try self.airAbs(inst),
            .ptr_add   => try self.airPtrAdd(inst),
            .ptr_sub   => try self.airPtrSub(inst),
            .shl       => try self.airShl(inst),
            .shl_sat   => try self.airShlSat(inst),
            .shl_exact => try self.airShlExact(inst),
            .min       => try self.airMin(inst),
            .max       => try self.airMax(inst),
            .slice     => try self.airSlice(inst),
            .mul_add   => try self.airMulAdd(inst),

            .div_float_optimized => try self.airDivFloat(inst, .fast),
            .div_trunc_optimized => try self.airDivTrunc(inst, .fast),
            .div_floor_optimized => try self.airDivFloor(inst, .fast),
            .div_exact_optimized => try self.airDivExact(inst, .fast),
            .rem_optimized       => try self.airRem(inst, .fast),
            .mod_optimized       => try self.airMod(inst, .fast),

            .add_with_overflow => try self.airOverflow(inst, .@"sadd.with.overflow", .@"uadd.with.overflow"),
            .sub_with_overflow => try self.airOverflow(inst, .@"ssub.with.overflow", .@"usub.with.overflow"),
            .mul_with_overflow => try self.airOverflow(inst, .@"smul.with.overflow", .@"umul.with.overflow"),
            .shl_with_overflow => try self.airShlWithOverflow(inst),

            .bit_and, .bool_and => try self.airAnd(inst),
            .bit_or, .bool_or   => try self.airOr(inst),
            .xor                => try self.airXor(inst),
            .shr                => try self.airShr(inst, false),
            .shr_exact          => try self.airShr(inst, true),

            .sqrt         => try self.airUnaryOp(inst, .sqrt),
            .sin          => try self.airUnaryOp(inst, .sin),
            .cos          => try self.airUnaryOp(inst, .cos),
            .tan          => try self.airUnaryOp(inst, .tan),
            .exp          => try self.airUnaryOp(inst, .exp),
            .exp2         => try self.airUnaryOp(inst, .exp2),
            .log          => try self.airUnaryOp(inst, .log),
            .log2         => try self.airUnaryOp(inst, .log2),
            .log10        => try self.airUnaryOp(inst, .log10),
            .floor        => try self.airUnaryOp(inst, .floor),
            .ceil         => try self.airUnaryOp(inst, .ceil),
            .round        => try self.airUnaryOp(inst, .round),
            .trunc_float  => try self.airUnaryOp(inst, .trunc),

            .neg           => try self.airNeg(inst, .normal),
            .neg_optimized => try self.airNeg(inst, .fast),

            .cmp_eq  => try self.airCmp(inst, .eq, .normal),
            .cmp_gt  => try self.airCmp(inst, .gt, .normal),
            .cmp_gte => try self.airCmp(inst, .gte, .normal),
            .cmp_lt  => try self.airCmp(inst, .lt, .normal),
            .cmp_lte => try self.airCmp(inst, .lte, .normal),
            .cmp_neq => try self.airCmp(inst, .neq, .normal),

            .cmp_eq_optimized  => try self.airCmp(inst, .eq, .fast),
            .cmp_gt_optimized  => try self.airCmp(inst, .gt, .fast),
            .cmp_gte_optimized => try self.airCmp(inst, .gte, .fast),
            .cmp_lt_optimized  => try self.airCmp(inst, .lt, .fast),
            .cmp_lte_optimized => try self.airCmp(inst, .lte, .fast),
            .cmp_neq_optimized => try self.airCmp(inst, .neq, .fast),

            .cmp_vector           => try self.airCmpVector(inst, .normal),
            .cmp_vector_optimized => try self.airCmpVector(inst, .fast),
            .cmp_lte_errors_len   => try self.airCmpLteErrorsLen(inst),

            .is_non_null     => try self.airIsNonNull(inst, false, .ne),
            .is_non_null_ptr => try self.airIsNonNull(inst, true , .ne),
            .is_null         => try self.airIsNonNull(inst, false, .eq),
            .is_null_ptr     => try self.airIsNonNull(inst, true , .eq),

            .is_non_err      => try self.airIsErr(inst, .eq, false),
            .is_non_err_ptr  => try self.airIsErr(inst, .eq, true),
            .is_err          => try self.airIsErr(inst, .ne, false),
            .is_err_ptr      => try self.airIsErr(inst, .ne, true),

            .alloc          => try self.airAlloc(inst),
            .ret_ptr        => try self.airRetPtr(inst),
            .arg            => try self.airArg(inst),
            .bitcast        => try self.airBitCast(inst),
            .breakpoint     => try self.airBreakpoint(inst),
            .ret_addr       => try self.airRetAddr(inst),
            .frame_addr     => try self.airFrameAddress(inst),
            .@"try"         => try self.airTry(inst, false),
            .try_cold       => try self.airTry(inst, true),
            .try_ptr        => try self.airTryPtr(inst, false),
            .try_ptr_cold   => try self.airTryPtr(inst, true),
            .intcast        => try self.airIntCast(inst, false),
            .intcast_safe   => try self.airIntCast(inst, true),
            .trunc          => try self.airTrunc(inst),
            .fptrunc        => try self.airFptrunc(inst),
            .fpext          => try self.airFpext(inst),
            .load           => try self.airLoad(inst),
            .not            => try self.airNot(inst),
            .store          => try self.airStore(inst, false),
            .store_safe     => try self.airStore(inst, true),
            .assembly       => try self.airAssembly(inst),
            .slice_ptr      => try self.airSliceField(inst, 0),
            .slice_len      => try self.airSliceField(inst, 1),

            .ptr_slice_ptr_ptr => try self.airPtrSliceFieldPtr(inst, 0),
            .ptr_slice_len_ptr => try self.airPtrSliceFieldPtr(inst, 1),

            .int_from_float           => try self.airIntFromFloat(inst, .normal),
            .int_from_float_optimized => try self.airIntFromFloat(inst, .fast),
            .int_from_float_safe           => unreachable, // handled by `legalizeFeatures`
            .int_from_float_optimized_safe => unreachable, // handled by `legalizeFeatures`

            .array_to_slice => try self.airArrayToSlice(inst),
            .float_from_int => try self.airFloatFromInt(inst),
            .cmpxchg_weak   => try self.airCmpxchg(inst, .weak),
            .cmpxchg_strong => try self.airCmpxchg(inst, .strong),
            .atomic_rmw     => try self.airAtomicRmw(inst),
            .atomic_load    => try self.airAtomicLoad(inst),
            .memset         => try self.airMemset(inst, false),
            .memset_safe    => try self.airMemset(inst, true),
            .memcpy         => try self.airMemcpy(inst),
            .memmove        => try self.airMemmove(inst),
            .set_union_tag  => try self.airSetUnionTag(inst),
            .get_union_tag  => try self.airGetUnionTag(inst),
            .clz            => try self.airClzCtz(inst, .ctlz),
            .ctz            => try self.airClzCtz(inst, .cttz),
            .popcount       => try self.airBitOp(inst, .ctpop),
            .byte_swap      => try self.airByteSwap(inst),
            .bit_reverse    => try self.airBitOp(inst, .bitreverse),
            .tag_name       => try self.airTagName(inst),
            .error_name     => try self.airErrorName(inst),
            .splat          => try self.airSplat(inst),
            .select         => try self.airSelect(inst),
            .shuffle_one    => try self.airShuffleOne(inst),
            .shuffle_two    => try self.airShuffleTwo(inst),
            .aggregate_init => try self.airAggregateInit(inst),
            .union_init     => try self.airUnionInit(inst),
            .prefetch       => try self.airPrefetch(inst),
            .addrspace_cast => try self.airAddrSpaceCast(inst),

            .is_named_enum_value => try self.airIsNamedEnumValue(inst),
            .error_set_has_value => try self.airErrorSetHasValue(inst),

            .reduce           => try self.airReduce(inst, .normal),
            .reduce_optimized => try self.airReduce(inst, .fast),

            .atomic_store_unordered => try self.airAtomicStore(inst, .unordered),
            .atomic_store_monotonic => try self.airAtomicStore(inst, .monotonic),
            .atomic_store_release   => try self.airAtomicStore(inst, .release),
            .atomic_store_seq_cst   => try self.airAtomicStore(inst, .seq_cst),

            .struct_field_ptr => try self.airStructFieldPtr(inst),
            .struct_field_val => try self.airStructFieldVal(inst),

            .struct_field_ptr_index_0 => try self.airStructFieldPtrIndex(inst, 0),
            .struct_field_ptr_index_1 => try self.airStructFieldPtrIndex(inst, 1),
            .struct_field_ptr_index_2 => try self.airStructFieldPtrIndex(inst, 2),
            .struct_field_ptr_index_3 => try self.airStructFieldPtrIndex(inst, 3),

            .field_parent_ptr => try self.airFieldParentPtr(inst),

            .array_elem_val     => try self.airArrayElemVal(inst),
            .slice_elem_val     => try self.airSliceElemVal(inst),
            .slice_elem_ptr     => try self.airSliceElemPtr(inst),
            .ptr_elem_val       => try self.airPtrElemVal(inst),
            .ptr_elem_ptr       => try self.airPtrElemPtr(inst),

            .optional_payload         => try self.airOptionalPayload(inst),
            .optional_payload_ptr     => try self.airOptionalPayloadPtr(inst),
            .optional_payload_ptr_set => try self.airOptionalPayloadPtrSet(inst),

            .unwrap_errunion_payload     => try self.airErrUnionPayload(inst, false),
            .unwrap_errunion_payload_ptr => try self.airErrUnionPayload(inst, true),
            .unwrap_errunion_err         => try self.airErrUnionErr(inst, false),
            .unwrap_errunion_err_ptr     => try self.airErrUnionErr(inst, true),
            .errunion_payload_ptr_set    => try self.airErrUnionPayloadPtrSet(inst),
            .err_return_trace            => try self.airErrReturnTrace(inst),
            .set_err_return_trace        => try self.airSetErrReturnTrace(inst),
            .save_err_return_trace_index => try self.airSaveErrReturnTraceIndex(inst),

            .wrap_optional         => try self.airWrapOptional(body[i..]),
            .wrap_errunion_payload => try self.airWrapErrUnionPayload(body[i..]),
            .wrap_errunion_err     => try self.airWrapErrUnionErr(body[i..]),

            .wasm_memory_size => try self.airWasmMemorySize(inst),
            .wasm_memory_grow => try self.airWasmMemoryGrow(inst),

            .runtime_nav_ptr => try self.airRuntimeNavPtr(inst),

            .inferred_alloc, .inferred_alloc_comptime => unreachable,

            .dbg_stmt => try self.airDbgStmt(inst),
            .dbg_empty_stmt => try self.airDbgEmptyStmt(inst),
            .dbg_var_ptr => try self.airDbgVarPtr(inst),
            .dbg_var_val => try self.airDbgVarVal(inst, false),
            .dbg_arg_inline => try self.airDbgVarVal(inst, true),

            .c_va_arg => try self.airCVaArg(inst),
            .c_va_copy => try self.airCVaCopy(inst),
            .c_va_end => try self.airCVaEnd(inst),
            .c_va_start => try self.airCVaStart(inst),

            .work_item_id => try self.airWorkItemId(inst),
            .work_group_size => try self.airWorkGroupSize(inst),
            .work_group_id => try self.airWorkGroupId(inst),

            // Instructions that are known to always be `noreturn` based on their tag.
            .br              => return self.airBr(inst),
            .repeat          => return self.airRepeat(inst),
            .switch_dispatch => return self.airSwitchDispatch(inst),
            .cond_br         => return self.airCondBr(inst),
            .switch_br       => return self.airSwitchBr(inst, false),
            .loop_switch_br  => return self.airSwitchBr(inst, true),
            .loop            => return self.airLoop(inst),
            .ret             => return self.airRet(inst, false),
            .ret_safe        => return self.airRet(inst, true),
            .ret_load        => return self.airRetLoad(inst),
            .trap            => return self.airTrap(inst),
            .unreach         => return self.airUnreach(inst),

            // Instructions which may be `noreturn`.
            .block => res: {
                const block = self.air.unwrapBlock(inst);
                const res = try self.lowerBlock(inst, null, block.body);
                if (block.ty.isNoReturn(zcu)) return;
                break :res res;
            },
            .dbg_inline_block => res: {
                const block = self.air.unwrapDbgBlock(inst);
                self.arg_inline_index = 0;
                const res = try self.lowerBlock(inst, block.func, block.body);
                if (block.ty.isNoReturn(zcu)) return;
                break :res res;
            },
            .call, .call_always_tail, .call_never_tail, .call_never_inline => |tag| res: {
                const res = try self.airCall(inst, switch (tag) {
                    .call              => .auto,
                    .call_always_tail  => .always_tail,
                    .call_never_tail   => .never_tail,
                    .call_never_inline => .never_inline,
                    else               => unreachable,
                });
                // TODO: the AIR we emit for calls is a bit weird - the instruction has
                // type `noreturn`, but there are instructions (and maybe a safety check) following
                // nonetheless. The `unreachable` or safety check should be emitted by backends instead.
                //if (self.typeOfIndex(inst).isNoReturn(mod)) return;
                break :res res;
            },

            // zig fmt: on
        };
        if (val != .none) try self.func_inst_table.putNoClobber(self.gpa, inst.toRef(), val);
    }
    unreachable;
}

fn genBodyDebugScope(
    self: *FuncGen,
    maybe_inline_func: ?InternPool.Index,
    body: []const Air.Inst.Index,
    coverage_point: Air.CoveragePoint,
) TodoError!void {
    const o = self.object;

    if (self.wip.strip) return self.genBody(body, coverage_point);

    const old_debug_location = self.wip.debug_location;
    const old_file = self.file;
    const old_inlined_at = self.inlined_at;
    const old_base_line = self.base_line;
    defer if (maybe_inline_func) |_| {
        self.wip.debug_location = old_debug_location;
        self.file = old_file;
        self.inlined_at = old_inlined_at;
        self.base_line = old_base_line;
    };

    const old_scope = self.scope;
    defer self.scope = old_scope;

    if (maybe_inline_func) |inline_func| {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;

        const func = zcu.funcInfo(inline_func);
        const nav = ip.getNav(func.owner_nav);
        const file_scope = zcu.navFileScopeIndex(func.owner_nav);
        const mod = zcu.fileByIndex(file_scope).mod.?;

        self.file = try o.getDebugFile(file_scope);

        self.base_line = zcu.navSrcLine(func.owner_nav);
        const line_number = self.base_line + 1;
        self.inlined_at = try self.wip.debug_location.toMetadata(&o.builder);

        self.scope = try o.builder.debugSubprogram(
            self.file,
            try o.builder.metadataString(nav.name.toSlice(&zcu.intern_pool)),
            try o.builder.metadataString(nav.fqn.toSlice(&zcu.intern_pool)),
            line_number,
            line_number + func.lbrace_line,
            try o.builder.debugSubroutineType(null),
            .{
                .di_flags = .{ .StaticMember = true },
                .sp_flags = .{
                    .Optimized = mod.optimize_mode != .Debug,
                    .Definition = true,
                    .LocalToUnit = true, // inline functions cannot be exported
                },
            },
            o.debug_compile_unit.unwrap().?,
        );
    }

    self.scope = try o.builder.debugLexicalBlock(
        self.scope,
        self.file,
        self.prev_dbg_line,
        self.prev_dbg_column,
    );
    self.wip.debug_location = .{ .location = .{
        .line = self.prev_dbg_line,
        .column = self.prev_dbg_column,
        .scope = self.scope.toOptional(),
        .inlined_at = self.inlined_at,
    } };

    try self.genBody(body, coverage_point);
}

const CallAttr = enum {
    Auto,
    NeverTail,
    NeverInline,
    AlwaysTail,
    AlwaysInline,
};

fn airCall(self: *FuncGen, inst: Air.Inst.Index, modifier: std.builtin.CallModifier) Allocator.Error!Builder.Value {
    const air_call = self.air.unwrapCall(inst);
    const args = air_call.args;
    const o = self.object;
    const pt = self.pt;
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const callee_ty = self.typeOf(air_call.callee);
    const zig_fn_ty = switch (callee_ty.zigTypeTag(zcu)) {
        .@"fn" => callee_ty,
        .pointer => callee_ty.childType(zcu),
        else => unreachable,
    };
    const fn_info = zcu.typeToFunc(zig_fn_ty).?;
    const return_type: Type = .fromInterned(fn_info.return_type);
    const llvm_fn = llvm_fn: {
        // If the callee is a function *body*, we need to use a pointer to the global.
        if (air_call.callee.toInterned()) |ip_index| switch (ip.indexToKey(ip_index)) {
            .@"extern" => |e| break :llvm_fn (try o.lowerNavRef(e.owner_nav)).toValue(),
            .func => |f| break :llvm_fn (try o.lowerNavRef(f.owner_nav)).toValue(),
            else => {},
        };
        // Otherwise, the operand is already a function pointer (possibly runtime-known).
        break :llvm_fn try self.resolveInst(air_call.callee);
    };
    const target = zcu.getTarget();
    const sret = firstParamSRet(fn_info, zcu, target);

    var llvm_args = std.array_list.Managed(Builder.Value).init(self.gpa);
    defer llvm_args.deinit();

    var attributes: Builder.FunctionAttributes.Wip = .{};
    defer attributes.deinit(&o.builder);

    if (self.disable_intrinsics) {
        try attributes.addFnAttr(.nobuiltin, &o.builder);
    }

    switch (modifier) {
        .auto, .always_tail => {},
        .never_tail, .never_inline => try attributes.addFnAttr(.@"noinline", &o.builder),
        .no_suspend, .always_inline, .compile_time => unreachable,
    }

    const ret_ptr = if (sret) ret_ptr: {
        const llvm_ret_ty = try o.lowerType(return_type);
        try attributes.addParamAttr(0, .{ .sret = llvm_ret_ty }, &o.builder);

        const alignment = return_type.abiAlignment(zcu).toLlvm();
        const ret_ptr = try self.buildAlloca(llvm_ret_ty, alignment);
        try llvm_args.append(ret_ptr);
        break :ret_ptr ret_ptr;
    } else ret_ptr: {
        if (ccAbiPromoteInt(fn_info.cc, zcu, Type.fromInterned(fn_info.return_type))) |s| switch (s) {
            .signed => try attributes.addRetAttr(.signext, &o.builder),
            .unsigned => try attributes.addRetAttr(.zeroext, &o.builder),
        };
        break :ret_ptr null;
    };

    const err_return_tracing = fn_info.cc == .auto and zcu.comp.config.any_error_tracing;
    if (err_return_tracing) {
        assert(self.err_ret_trace != .none);
        try llvm_args.append(self.err_ret_trace);
    }

    var it = iterateParamTypes(o, fn_info);
    while (try it.nextCall(self, args)) |lowering| switch (lowering) {
        .no_bits => continue,
        .byval => {
            const arg = args[it.zig_index - 1];
            const param_ty = self.typeOf(arg);
            const llvm_arg = try self.resolveInst(arg);
            const llvm_param_ty = try o.lowerType(param_ty);
            if (isByRef(param_ty, zcu)) {
                const alignment = param_ty.abiAlignment(zcu).toLlvm();
                const loaded = try self.wip.load(.normal, llvm_param_ty, llvm_arg, alignment, "");
                try llvm_args.append(loaded);
            } else {
                try llvm_args.append(llvm_arg);
            }
        },
        .byref => {
            const arg = args[it.zig_index - 1];
            const param_ty = self.typeOf(arg);
            const llvm_arg = try self.resolveInst(arg);
            if (isByRef(param_ty, zcu)) {
                try llvm_args.append(llvm_arg);
            } else {
                const alignment = param_ty.abiAlignment(zcu).toLlvm();
                const param_llvm_ty = llvm_arg.typeOfWip(&self.wip);
                const arg_ptr = try self.buildAlloca(param_llvm_ty, alignment);
                _ = try self.wip.store(.normal, llvm_arg, arg_ptr, alignment);
                try llvm_args.append(arg_ptr);
            }
        },
        .byref_mut => {
            const arg = args[it.zig_index - 1];
            const param_ty = self.typeOf(arg);
            const llvm_arg = try self.resolveInst(arg);

            const alignment = param_ty.abiAlignment(zcu).toLlvm();
            const param_llvm_ty = try o.lowerType(param_ty);
            const arg_ptr = try self.buildAlloca(param_llvm_ty, alignment);
            if (isByRef(param_ty, zcu)) {
                const loaded = try self.wip.load(.normal, param_llvm_ty, llvm_arg, alignment, "");
                _ = try self.wip.store(.normal, loaded, arg_ptr, alignment);
            } else {
                _ = try self.wip.store(.normal, llvm_arg, arg_ptr, alignment);
            }
            try llvm_args.append(arg_ptr);
        },
        .abi_sized_int => {
            const arg = args[it.zig_index - 1];
            const param_ty = self.typeOf(arg);
            const llvm_arg = try self.resolveInst(arg);
            const int_llvm_ty = try o.builder.intType(@intCast(param_ty.abiSize(zcu) * 8));

            if (isByRef(param_ty, zcu)) {
                const alignment = param_ty.abiAlignment(zcu).toLlvm();
                const loaded = try self.wip.load(.normal, int_llvm_ty, llvm_arg, alignment, "");
                try llvm_args.append(loaded);
            } else {
                // LLVM does not allow bitcasting structs so we must allocate
                // a local, store as one type, and then load as another type.
                const alignment = param_ty.abiAlignment(zcu).toLlvm();
                const int_ptr = try self.buildAlloca(int_llvm_ty, alignment);
                _ = try self.wip.store(.normal, llvm_arg, int_ptr, alignment);
                const loaded = try self.wip.load(.normal, int_llvm_ty, int_ptr, alignment, "");
                try llvm_args.append(loaded);
            }
        },
        .slice => {
            const arg = args[it.zig_index - 1];
            const llvm_arg = try self.resolveInst(arg);
            const ptr = try self.wip.extractValue(llvm_arg, &.{0}, "");
            const len = try self.wip.extractValue(llvm_arg, &.{1}, "");
            try llvm_args.appendSlice(&.{ ptr, len });
        },
        .multiple_llvm_types => {
            const arg = args[it.zig_index - 1];
            const param_ty = self.typeOf(arg);
            const llvm_types = it.types_buffer[0..it.types_len];
            const llvm_arg = try self.resolveInst(arg);
            const is_by_ref = isByRef(param_ty, zcu);
            const arg_ptr = if (is_by_ref) llvm_arg else ptr: {
                const alignment = param_ty.abiAlignment(zcu).toLlvm();
                const ptr = try self.buildAlloca(llvm_arg.typeOfWip(&self.wip), alignment);
                _ = try self.wip.store(.normal, llvm_arg, ptr, alignment);
                break :ptr ptr;
            };

            const llvm_ty = try o.builder.structType(.normal, llvm_types);
            try llvm_args.ensureUnusedCapacity(it.types_len);
            for (llvm_types, 0..) |field_ty, i| {
                const alignment: Builder.Alignment = .fromByteUnits(@divExact(target.ptrBitWidth(), 8));
                const field_ptr = try self.wip.gepStruct(llvm_ty, arg_ptr, i, "");
                const loaded = try self.wip.load(.normal, field_ty, field_ptr, alignment, "");
                llvm_args.appendAssumeCapacity(loaded);
            }
        },
        .float_array => |count| {
            const arg = args[it.zig_index - 1];
            const arg_ty = self.typeOf(arg);
            var llvm_arg = try self.resolveInst(arg);
            const alignment = arg_ty.abiAlignment(zcu).toLlvm();
            if (!isByRef(arg_ty, zcu)) {
                const ptr = try self.buildAlloca(llvm_arg.typeOfWip(&self.wip), alignment);
                _ = try self.wip.store(.normal, llvm_arg, ptr, alignment);
                llvm_arg = ptr;
            }

            const float_ty = try o.lowerType(aarch64_c_abi.getFloatArrayType(arg_ty, zcu).?);
            const array_ty = try o.builder.arrayType(count, float_ty);

            const loaded = try self.wip.load(.normal, array_ty, llvm_arg, alignment, "");
            try llvm_args.append(loaded);
        },
        .i32_array, .i64_array => |arr_len| {
            const elem_size: u8 = if (lowering == .i32_array) 32 else 64;
            const arg = args[it.zig_index - 1];
            const arg_ty = self.typeOf(arg);
            var llvm_arg = try self.resolveInst(arg);
            const alignment = arg_ty.abiAlignment(zcu).toLlvm();
            if (!isByRef(arg_ty, zcu)) {
                const ptr = try self.buildAlloca(llvm_arg.typeOfWip(&self.wip), alignment);
                _ = try self.wip.store(.normal, llvm_arg, ptr, alignment);
                llvm_arg = ptr;
            }

            const array_ty =
                try o.builder.arrayType(arr_len, try o.builder.intType(@intCast(elem_size)));
            const loaded = try self.wip.load(.normal, array_ty, llvm_arg, alignment, "");
            try llvm_args.append(loaded);
        },
    };

    {
        // Add argument attributes.
        it = iterateParamTypes(o, fn_info);
        it.llvm_index += @intFromBool(sret);
        it.llvm_index += @intFromBool(err_return_tracing);
        while (try it.next()) |lowering| switch (lowering) {
            .byval => {
                const param_index = it.zig_index - 1;
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[param_index]);
                if (!isByRef(param_ty, zcu)) {
                    try o.addByValParamAttrs(pt, &attributes, param_ty, param_index, fn_info, it.llvm_index - 1);
                }
            },
            .byref => {
                const param_index = it.zig_index - 1;
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[param_index]);
                const param_llvm_ty = try o.lowerType(param_ty);
                const alignment = param_ty.abiAlignment(zcu).toLlvm();
                try o.addByRefParamAttrs(&attributes, it.llvm_index - 1, alignment, it.byval_attr, param_llvm_ty);
            },
            .byref_mut => try attributes.addParamAttr(it.llvm_index - 1, .noundef, &o.builder),
            // No attributes needed for these.
            .no_bits,
            .abi_sized_int,
            .multiple_llvm_types,
            .float_array,
            .i32_array,
            .i64_array,
            => continue,

            .slice => {
                assert(!it.byval_attr);
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                const ptr_info = param_ty.ptrInfo(zcu);
                const llvm_arg_i = it.llvm_index - 2;

                if (math.cast(u5, it.zig_index - 1)) |i| {
                    if (@as(u1, @truncate(fn_info.noalias_bits >> i)) != 0) {
                        try attributes.addParamAttr(llvm_arg_i, .@"noalias", &o.builder);
                    }
                }
                if (param_ty.zigTypeTag(zcu) != .optional and
                    !ptr_info.flags.is_allowzero and
                    ptr_info.flags.address_space == .generic)
                {
                    try attributes.addParamAttr(llvm_arg_i, .nonnull, &o.builder);
                }
                if (ptr_info.flags.is_const) {
                    try attributes.addParamAttr(llvm_arg_i, .readonly, &o.builder);
                }
                const elem_align: Builder.Alignment.Lazy = switch (ptr_info.flags.alignment) {
                    else => |a| .wrap(a.toLlvm()),
                    .none => try o.lazyAbiAlignment(pt, .fromInterned(ptr_info.child)),
                };
                try attributes.addParamAttr(llvm_arg_i, .{ .@"align" = elem_align }, &o.builder);
            },
        };
    }

    const call = try self.wip.call(
        switch (modifier) {
            .auto, .never_inline => .normal,
            .never_tail => .notail,
            .always_tail => .musttail,
            .no_suspend, .always_inline, .compile_time => unreachable,
        },
        llvm.toLlvmCallConvTag(fn_info.cc, target).?,
        try attributes.finish(&o.builder),
        try o.lowerType(zig_fn_ty),
        llvm_fn,
        llvm_args.items,
        "",
    );

    if (fn_info.return_type == .noreturn_type and modifier != .always_tail) {
        return .none;
    }

    if (self.liveness.isUnused(inst) or !return_type.hasRuntimeBits(zcu)) {
        return .none;
    }

    const llvm_ret_ty = try o.lowerType(return_type);
    if (ret_ptr) |rp| {
        if (isByRef(return_type, zcu)) {
            return rp;
        } else {
            // our by-ref status disagrees with sret so we must load.
            const return_alignment = return_type.abiAlignment(zcu).toLlvm();
            return self.wip.load(.normal, llvm_ret_ty, rp, return_alignment, "");
        }
    }

    const abi_ret_ty = try lowerFnRetTy(o, fn_info);

    if (abi_ret_ty != llvm_ret_ty) {
        // In this case the function return type is honoring the calling convention by having
        // a different LLVM type than the usual one. We solve this here at the callsite
        // by using our canonical type, then loading it if necessary.
        const alignment = return_type.abiAlignment(zcu).toLlvm();
        const rp = try self.buildAlloca(abi_ret_ty, alignment);
        _ = try self.wip.store(.normal, call, rp, alignment);
        return if (isByRef(return_type, zcu))
            rp
        else
            try self.wip.load(.normal, llvm_ret_ty, rp, alignment, "");
    }

    if (isByRef(return_type, zcu)) {
        // our by-ref status disagrees with sret so we must allocate, store,
        // and return the allocation pointer.
        const alignment = return_type.abiAlignment(zcu).toLlvm();
        const rp = try self.buildAlloca(llvm_ret_ty, alignment);
        _ = try self.wip.store(.normal, call, rp, alignment);
        return rp;
    } else {
        return call;
    }
}

fn buildSimplePanic(fg: *FuncGen, panic_id: Zcu.SimplePanicId) Allocator.Error!void {
    const o = fg.object;
    const zcu = o.zcu;
    const target = zcu.getTarget();
    const panic_func = zcu.funcInfo(zcu.builtin_decl_values.get(panic_id.toBuiltin()));
    const fn_info = zcu.typeToFunc(.fromInterned(panic_func.ty)).?;
    const llvm_panic_fn_ty = try o.lowerType(.fromInterned(panic_func.ty));

    const llvm_panic_fn_ref = try o.lowerNavRef(panic_func.owner_nav);

    const has_err_trace = zcu.comp.config.any_error_tracing and fn_info.cc == .auto;
    if (has_err_trace) assert(fg.err_ret_trace != .none);
    _ = try fg.wip.callIntrinsicAssumeCold();
    _ = try fg.wip.call(
        .normal,
        llvm.toLlvmCallConvTag(fn_info.cc, target).?,
        .none,
        llvm_panic_fn_ty,
        llvm_panic_fn_ref.toValue(),
        if (has_err_trace) &.{fg.err_ret_trace} else &.{},
        "",
    );
    _ = try fg.wip.@"unreachable"();
}

fn airRet(self: *FuncGen, inst: Air.Inst.Index, safety: bool) Allocator.Error!void {
    const o = self.object;
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const ret_ty = self.typeOf(un_op);

    if (self.ret_ptr != .none) {
        const operand = try self.resolveInst(un_op);
        const val_is_undef = if (un_op.toInterned()) |i| Value.fromInterned(i).isUndef(zcu) else false;
        if (val_is_undef and safety) {
            const len = try o.builder.intValue(try o.lowerType(.usize), ret_ty.abiSize(zcu));
            _ = try self.wip.callMemSet(
                self.ret_ptr,
                ret_ty.abiAlignment(zcu).toLlvm(),
                try o.builder.intValue(.i8, 0xaa),
                len,
                .normal,
                self.disable_intrinsics,
            );
            const owner_mod = self.ownerModule();
            if (owner_mod.valgrind) {
                try self.valgrindMarkUndef(self.ret_ptr, len);
            }
            _ = try self.wip.retVoid();
            return;
        }

        const unwrapped_operand = operand.unwrap();
        const unwrapped_ret = self.ret_ptr.unwrap();

        // Return value was stored previously
        if (unwrapped_operand == .instruction and unwrapped_ret == .instruction and unwrapped_operand.instruction == unwrapped_ret.instruction) {
            _ = try self.wip.retVoid();
            return;
        }

        try self.store(
            self.ret_ptr,
            .none,
            operand,
            ret_ty,
        );
        _ = try self.wip.retVoid();
        return;
    }
    const fn_info = zcu.typeToFunc(Type.fromInterned(ip.getNav(self.nav_index).resolved.?.type)).?;
    if (!ret_ty.hasRuntimeBits(zcu)) {
        if (Type.fromInterned(fn_info.return_type).isError(zcu)) {
            // Functions with an empty error set are emitted with an error code
            // return type and return zero so they can be function pointers coerced
            // to functions that return anyerror.
            _ = try self.wip.ret(try o.builder.intValue(try o.errorIntType(), 0));
        } else {
            _ = try self.wip.retVoid();
        }
        return;
    }

    const abi_ret_ty = try lowerFnRetTy(o, fn_info);
    const operand = try self.resolveInst(un_op);
    const val_is_undef = if (un_op.toInterned()) |i| Value.fromInterned(i).isUndef(zcu) else false;
    const alignment = ret_ty.abiAlignment(zcu).toLlvm();

    if (val_is_undef and safety) {
        const llvm_ret_ty = operand.typeOfWip(&self.wip);
        const rp = try self.buildAlloca(llvm_ret_ty, alignment);
        const len = try o.builder.intValue(try o.lowerType(.usize), ret_ty.abiSize(zcu));
        _ = try self.wip.callMemSet(
            rp,
            alignment,
            try o.builder.intValue(.i8, 0xaa),
            len,
            .normal,
            self.disable_intrinsics,
        );
        const owner_mod = self.ownerModule();
        if (owner_mod.valgrind) {
            try self.valgrindMarkUndef(rp, len);
        }
        _ = try self.wip.ret(try self.wip.load(.normal, abi_ret_ty, rp, alignment, ""));
        return;
    }

    if (isByRef(ret_ty, zcu)) {
        // operand is a pointer however self.ret_ptr is null so that means
        // we need to return a value.
        _ = try self.wip.ret(try self.wip.load(.normal, abi_ret_ty, operand, alignment, ""));
        return;
    }

    const llvm_ret_ty = operand.typeOfWip(&self.wip);
    if (abi_ret_ty == llvm_ret_ty) {
        _ = try self.wip.ret(operand);
        return;
    }

    const rp = try self.buildAlloca(llvm_ret_ty, alignment);
    _ = try self.wip.store(.normal, operand, rp, alignment);
    _ = try self.wip.ret(try self.wip.load(.normal, abi_ret_ty, rp, alignment, ""));
    return;
}

fn airRetLoad(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!void {
    const o = self.object;
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const ptr_ty = self.typeOf(un_op);
    const ret_ty = ptr_ty.childType(zcu);
    const fn_info = zcu.typeToFunc(.fromInterned(ip.getNav(self.nav_index).resolved.?.type)).?;
    if (!ret_ty.hasRuntimeBits(zcu)) {
        if (Type.fromInterned(fn_info.return_type).isError(zcu)) {
            // Functions with an empty error set are emitted with an error code
            // return type and return zero so they can be function pointers coerced
            // to functions that return anyerror.
            _ = try self.wip.ret(try o.builder.intValue(try o.errorIntType(), 0));
        } else {
            _ = try self.wip.retVoid();
        }
        return;
    }
    if (self.ret_ptr != .none) {
        _ = try self.wip.retVoid();
        return;
    }
    const ptr = try self.resolveInst(un_op);
    const abi_ret_ty = try lowerFnRetTy(o, fn_info);
    const alignment = ret_ty.abiAlignment(zcu).toLlvm();
    _ = try self.wip.ret(try self.wip.load(.normal, abi_ret_ty, ptr, alignment, ""));
    return;
}

fn airCVaArg(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const list = try self.resolveInst(ty_op.operand);
    const arg_ty = ty_op.ty.toType();
    const llvm_arg_ty = try self.object.lowerType(arg_ty);

    return self.wip.vaArg(list, llvm_arg_ty, "");
}

fn airCVaCopy(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const src_list = try self.resolveInst(ty_op.operand);
    const va_list_ty = ty_op.ty.toType();
    const llvm_va_list_ty = try o.lowerType(va_list_ty);

    const result_alignment = va_list_ty.abiAlignment(zcu).toLlvm();
    const dest_list = try self.buildAlloca(llvm_va_list_ty, result_alignment);

    _ = try self.wip.callIntrinsic(.normal, .none, .va_copy, &.{dest_list.typeOfWip(&self.wip)}, &.{ dest_list, src_list }, "");
    return if (isByRef(va_list_ty, zcu))
        dest_list
    else
        try self.wip.load(.normal, llvm_va_list_ty, dest_list, result_alignment, "");
}

fn airCVaEnd(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const src_list = try self.resolveInst(un_op);

    _ = try self.wip.callIntrinsic(.normal, .none, .va_end, &.{src_list.typeOfWip(&self.wip)}, &.{src_list}, "");
    return .none;
}

fn airCVaStart(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const va_list_ty = self.typeOfIndex(inst);
    const llvm_va_list_ty = try o.lowerType(va_list_ty);

    const result_alignment = va_list_ty.abiAlignment(zcu).toLlvm();
    const dest_list = try self.buildAlloca(llvm_va_list_ty, result_alignment);

    _ = try self.wip.callIntrinsic(.normal, .none, .va_start, &.{dest_list.typeOfWip(&self.wip)}, &.{dest_list}, "");
    return if (isByRef(va_list_ty, zcu))
        dest_list
    else
        try self.wip.load(.normal, llvm_va_list_ty, dest_list, result_alignment, "");
}

fn airCmp(
    self: *FuncGen,
    inst: Air.Inst.Index,
    op: math.CompareOperator,
    fast: Builder.FastMathKind,
) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const operand_ty = self.typeOf(bin_op.lhs);

    return self.cmp(fast, op, operand_ty, lhs, rhs);
}

fn airCmpVector(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = self.air.extraData(Air.VectorCmp, ty_pl.payload).data;

    const lhs = try self.resolveInst(extra.lhs);
    const rhs = try self.resolveInst(extra.rhs);
    const vec_ty = self.typeOf(extra.lhs);
    const cmp_op = extra.compareOperator();

    return self.cmp(fast, cmp_op, vec_ty, lhs, rhs);
}

fn airCmpLteErrorsLen(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const errors_len_ptr = try o.getErrorsLen();
    const errors_len_val = try self.wip.load(
        .normal,
        try o.errorIntType(),
        errors_len_ptr.toValue(&o.builder),
        Type.errorAbiAlignment(o.zcu).toLlvm(),
        "",
    );
    return self.wip.icmp(.ule, operand, errors_len_val, "");
}

fn cmp(
    self: *FuncGen,
    fast: Builder.FastMathKind,
    op: math.CompareOperator,
    operand_ty: Type,
    lhs: Builder.Value,
    rhs: Builder.Value,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const scalar_ty = operand_ty.scalarType(zcu);
    const int_ty = switch (scalar_ty.zigTypeTag(zcu)) {
        .@"enum" => scalar_ty.intTagType(zcu),
        .int, .bool, .pointer, .error_set => scalar_ty,
        .optional => blk: {
            const payload_ty = operand_ty.optionalChild(zcu);
            if (!payload_ty.hasRuntimeBits(zcu) or
                operand_ty.optionalReprIsPayload(zcu))
            {
                break :blk operand_ty;
            }
            // We need to emit instructions to check for equality/inequality
            // of optionals that are not pointers.
            const lhs_non_null = try self.optCmpNull(.ne, scalar_ty, lhs, .normal);
            const rhs_non_null = try self.optCmpNull(.ne, scalar_ty, rhs, .normal);
            const llvm_i2 = try o.builder.intType(2);
            const lhs_non_null_i2 = try self.wip.cast(.zext, lhs_non_null, llvm_i2, "");
            const rhs_non_null_i2 = try self.wip.cast(.zext, rhs_non_null, llvm_i2, "");
            const lhs_shifted = try self.wip.bin(.shl, lhs_non_null_i2, try o.builder.intValue(llvm_i2, 1), "");
            const lhs_rhs_ored = try self.wip.bin(.@"or", lhs_shifted, rhs_non_null_i2, "");
            const both_null_block = try self.wip.block(1, "BothNull");
            const mixed_block = try self.wip.block(1, "Mixed");
            const both_pl_block = try self.wip.block(1, "BothNonNull");
            const end_block = try self.wip.block(3, "End");
            var wip_switch = try self.wip.@"switch"(lhs_rhs_ored, mixed_block, 2, .none);
            defer wip_switch.finish(&self.wip);
            try wip_switch.addCase(
                try o.builder.intConst(llvm_i2, 0b00),
                both_null_block,
                &self.wip,
            );
            try wip_switch.addCase(
                try o.builder.intConst(llvm_i2, 0b11),
                both_pl_block,
                &self.wip,
            );

            self.wip.cursor = .{ .block = both_null_block };
            _ = try self.wip.br(end_block);

            self.wip.cursor = .{ .block = mixed_block };
            _ = try self.wip.br(end_block);

            self.wip.cursor = .{ .block = both_pl_block };
            const lhs_payload = try self.optPayloadHandle(lhs, scalar_ty, true);
            const rhs_payload = try self.optPayloadHandle(rhs, scalar_ty, true);
            const payload_cmp = try self.cmp(fast, op, payload_ty, lhs_payload, rhs_payload);
            _ = try self.wip.br(end_block);
            const both_pl_block_end = self.wip.cursor.block;

            self.wip.cursor = .{ .block = end_block };
            const llvm_i1_0 = Builder.Value.false;
            const llvm_i1_1 = Builder.Value.true;
            const incoming_values: [3]Builder.Value = .{
                switch (op) {
                    .eq => llvm_i1_1,
                    .neq => llvm_i1_0,
                    else => unreachable,
                },
                switch (op) {
                    .eq => llvm_i1_0,
                    .neq => llvm_i1_1,
                    else => unreachable,
                },
                payload_cmp,
            };

            const phi = try self.wip.phi(.i1, "");
            phi.finish(
                &incoming_values,
                &.{ both_null_block, mixed_block, both_pl_block_end },
                &self.wip,
            );
            return phi.toValue();
        },
        .float => return self.buildFloatCmp(fast, op, operand_ty, .{ lhs, rhs }),
        .@"struct", .@"union" => scalar_ty.bitpackBackingInt(zcu),
        else => unreachable,
    };
    const is_signed = int_ty.isSignedInt(zcu);
    const cond: Builder.IntegerCondition = switch (op) {
        .eq => .eq,
        .neq => .ne,
        .lt => if (is_signed) .slt else .ult,
        .lte => if (is_signed) .sle else .ule,
        .gt => if (is_signed) .sgt else .ugt,
        .gte => if (is_signed) .sge else .uge,
    };
    return self.wip.icmp(cond, lhs, rhs, "");
}

fn lowerBlock(
    self: *FuncGen,
    inst: Air.Inst.Index,
    maybe_inline_func: ?InternPool.Index,
    body: []const Air.Inst.Index,
) TodoError!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const inst_ty = self.typeOfIndex(inst);

    if (inst_ty.isNoReturn(zcu)) {
        try self.genBodyDebugScope(maybe_inline_func, body, .none);
        return .none;
    }

    const have_block_result = inst_ty.hasRuntimeBits(zcu);

    var breaks: BreakList = if (have_block_result) .{ .list = .{} } else .{ .len = 0 };
    defer if (have_block_result) breaks.list.deinit(self.gpa);

    const parent_bb = try self.wip.block(0, "Block");
    try self.blocks.putNoClobber(self.gpa, inst, .{
        .parent_bb = parent_bb,
        .breaks = &breaks,
    });
    defer assert(self.blocks.remove(inst));

    try self.genBodyDebugScope(maybe_inline_func, body, .none);

    self.wip.cursor = .{ .block = parent_bb };

    // Create a phi node only if the block returns a value.
    if (have_block_result) {
        const raw_llvm_ty = try o.lowerType(inst_ty);
        const llvm_ty: Builder.Type = ty: {
            // If the zig tag type is a function, this represents an actual function body; not
            // a pointer to it. LLVM IR allows the call instruction to use function bodies instead
            // of function pointers, however the phi makes it a runtime value and therefore
            // the LLVM type has to be wrapped in a pointer.
            if (inst_ty.zigTypeTag(zcu) == .@"fn" or isByRef(inst_ty, zcu)) {
                break :ty .ptr;
            }
            break :ty raw_llvm_ty;
        };

        parent_bb.ptr(&self.wip).incoming = @intCast(breaks.list.len);
        const phi = try self.wip.phi(llvm_ty, "");
        phi.finish(breaks.list.items(.val), breaks.list.items(.bb), &self.wip);
        return phi.toValue();
    } else {
        parent_bb.ptr(&self.wip).incoming = @intCast(breaks.len);
        return .none;
    }
}

fn airBr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!void {
    const zcu = self.object.zcu;
    const branch = self.air.instructions.items(.data)[@intFromEnum(inst)].br;
    const block = self.blocks.get(branch.block_inst).?;

    // Add the values to the lists only if the break provides a value.
    const operand_ty = self.typeOf(branch.operand);
    if (operand_ty.hasRuntimeBits(zcu)) {
        const val = try self.resolveInst(branch.operand);

        // For the phi node, we need the basic blocks and the values of the
        // break instructions.
        try block.breaks.list.append(self.gpa, .{ .bb = self.wip.cursor.block, .val = val });
    } else block.breaks.len += 1;
    _ = try self.wip.br(block.parent_bb);
}

fn airRepeat(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!void {
    const repeat = self.air.instructions.items(.data)[@intFromEnum(inst)].repeat;
    const loop_bb = self.loops.get(repeat.loop_inst).?;
    loop_bb.ptr(&self.wip).incoming += 1;
    _ = try self.wip.br(loop_bb);
}

fn lowerSwitchDispatch(
    self: *FuncGen,
    switch_inst: Air.Inst.Index,
    cond_ref: Air.Inst.Ref,
    dispatch_info: SwitchDispatchInfo,
) Allocator.Error!void {
    const o = self.object;
    const zcu = o.zcu;
    const cond_ty = self.typeOf(cond_ref);
    const switch_br = self.air.unwrapSwitch(switch_inst);

    if (cond_ref.toInterned()) |cond_ip_index| {
        const cond_val: Value = .fromInterned(cond_ip_index);
        // Comptime-known dispatch. Iterate the cases to find the correct
        // one, and branch to the corresponding element of `case_blocks`.
        var it = switch_br.iterateCases();
        const target_case_idx = target: while (it.next()) |case| {
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
        } else dispatch_info.case_blocks.len - 1;
        const target_block = dispatch_info.case_blocks[target_case_idx];
        target_block.ptr(&self.wip).incoming += 1;
        _ = try self.wip.br(target_block);
        return;
    }

    // Runtime-known dispatch.
    const cond = try self.resolveInst(cond_ref);

    if (dispatch_info.jmp_table) |jmp_table| {
        // We should use the constructed jump table.
        // First, check the bounds to branch to the `else` case if needed.
        const inbounds = try self.wip.bin(
            .@"and",
            try self.cmp(.normal, .gte, cond_ty, cond, jmp_table.min.toValue()),
            try self.cmp(.normal, .lte, cond_ty, cond, jmp_table.max.toValue()),
            "",
        );
        const jmp_table_block = try self.wip.block(1, "Then");
        const else_block = dispatch_info.case_blocks[dispatch_info.case_blocks.len - 1];
        else_block.ptr(&self.wip).incoming += 1;
        _ = try self.wip.brCond(inbounds, jmp_table_block, else_block, switch (jmp_table.in_bounds_hint) {
            .none => .none,
            .unpredictable => .unpredictable,
            .likely => .then_likely,
            .unlikely => .else_likely,
        });

        self.wip.cursor = .{ .block = jmp_table_block };

        // Figure out the list of blocks we might branch to.
        // This includes all case blocks, but it might not include the `else` block if
        // the table is dense.
        const target_blocks_len = dispatch_info.case_blocks.len - @intFromBool(!jmp_table.table_includes_else);
        const target_blocks = dispatch_info.case_blocks[0..target_blocks_len];

        // Make sure to cast the index to a usize so it's not treated as negative!
        const table_index = try self.wip.conv(
            .unsigned,
            try self.wip.bin(.@"sub nuw", cond, jmp_table.min.toValue(), ""),
            try o.lowerType(.usize),
            "",
        );
        const target_ptr_ptr = try self.ptraddScaled(
            jmp_table.table.toValue(),
            table_index,
            Type.usize.abiSize(zcu),
        );
        const target_ptr = try self.wip.load(.normal, .ptr, target_ptr_ptr, .default, "");

        // Do the branch!
        _ = try self.wip.indirectbr(target_ptr, target_blocks);

        // Mark all target blocks as having one more incoming branch.
        for (target_blocks) |case_block| {
            case_block.ptr(&self.wip).incoming += 1;
        }

        return;
    }

    // We must lower to an actual LLVM `switch` instruction.
    // The switch prongs will correspond to our scalar cases. Ranges will
    // be handled by conditional branches in the `else` prong.

    const llvm_usize = try o.lowerType(.usize);
    const cond_int = if (cond_ty.zigTypeTag(zcu) == .pointer)
        try self.wip.cast(.ptrtoint, cond, llvm_usize, "")
    else
        cond;

    const llvm_cases_len, const last_range_case = info: {
        var llvm_cases_len: u32 = 0;
        var last_range_case: ?u32 = null;
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            if (case.ranges.len > 0) last_range_case = case.idx;
            llvm_cases_len += @intCast(case.items.len);
        }
        break :info .{ llvm_cases_len, last_range_case };
    };

    // The `else` of the LLVM `switch` is the actual `else` prong only
    // if there are no ranges. Otherwise, the `else` will have a
    // conditional chain before the "true" `else` prong.
    const llvm_else_block = if (last_range_case == null)
        dispatch_info.case_blocks[dispatch_info.case_blocks.len - 1]
    else
        try self.wip.block(0, "RangeTest");

    llvm_else_block.ptr(&self.wip).incoming += 1;

    var wip_switch = try self.wip.@"switch"(cond_int, llvm_else_block, llvm_cases_len, dispatch_info.switch_weights);
    defer wip_switch.finish(&self.wip);

    // Construct the actual cases. Set the cursor to the `else` block so
    // we can construct ranges at the same time as scalar cases.
    self.wip.cursor = .{ .block = llvm_else_block };

    var it = switch_br.iterateCases();
    while (it.next()) |case| {
        const case_block = dispatch_info.case_blocks[case.idx];

        for (case.items) |item| {
            const llvm_item = (try self.resolveInst(item)).toConst().?;
            const llvm_int_item = if (cond_ty.zigTypeTag(zcu) == .pointer)
                try o.builder.castConst(.ptrtoint, llvm_item, llvm_usize)
            else
                llvm_item;
            try wip_switch.addCase(llvm_int_item, case_block, &self.wip);
        }
        case_block.ptr(&self.wip).incoming += @intCast(case.items.len);

        if (case.ranges.len == 0) continue;

        // Add a conditional for the ranges, directing to the relevant bb.
        // We don't need to consider `cold` branch hints since that information is stored
        // in the target bb body, but we do care about likely/unlikely/unpredictable.

        const hint = switch_br.getHint(case.idx);

        var range_cond: ?Builder.Value = null;
        for (case.ranges) |range| {
            const llvm_min = try self.resolveInst(range[0]);
            const llvm_max = try self.resolveInst(range[1]);
            const cond_part = try self.wip.bin(
                .@"and",
                try self.cmp(.normal, .gte, cond_ty, cond, llvm_min),
                try self.cmp(.normal, .lte, cond_ty, cond, llvm_max),
                "",
            );
            if (range_cond) |prev| {
                range_cond = try self.wip.bin(.@"or", prev, cond_part, "");
            } else range_cond = cond_part;
        }

        // If the check fails, we either branch to the "true" `else` case,
        // or to the next range condition.
        const range_else_block = if (case.idx == last_range_case.?)
            dispatch_info.case_blocks[dispatch_info.case_blocks.len - 1]
        else
            try self.wip.block(0, "RangeTest");

        _ = try self.wip.brCond(range_cond.?, case_block, range_else_block, switch (hint) {
            .none, .cold => .none,
            .unpredictable => .unpredictable,
            .likely => .then_likely,
            .unlikely => .else_likely,
        });
        case_block.ptr(&self.wip).incoming += 1;
        range_else_block.ptr(&self.wip).incoming += 1;

        // Construct the next range conditional (if any) in the false branch.
        self.wip.cursor = .{ .block = range_else_block };
    }
}

fn airSwitchDispatch(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!void {
    const br = self.air.instructions.items(.data)[@intFromEnum(inst)].br;
    const dispatch_info = self.switch_dispatch_info.get(br.block_inst).?;
    return self.lowerSwitchDispatch(br.block_inst, br.operand, dispatch_info);
}

fn airCondBr(self: *FuncGen, inst: Air.Inst.Index) TodoError!void {
    const cond_br = self.air.unwrapCondBr(inst);
    const cond = try self.resolveInst(cond_br.condition);
    const then_body = cond_br.then_body;
    const else_body = cond_br.else_body;

    const Hint = enum {
        none,
        unpredictable,
        then_likely,
        else_likely,
        then_cold,
        else_cold,
    };
    const hint: Hint = switch (cond_br.branch_hints.true) {
        .none => switch (cond_br.branch_hints.false) {
            .none => .none,
            .likely => .else_likely,
            .unlikely => .then_likely,
            .cold => .else_cold,
            .unpredictable => .unpredictable,
        },
        .likely => switch (cond_br.branch_hints.false) {
            .none => .then_likely,
            .likely => .unpredictable,
            .unlikely => .then_likely,
            .cold => .else_cold,
            .unpredictable => .unpredictable,
        },
        .unlikely => switch (cond_br.branch_hints.false) {
            .none => .else_likely,
            .likely => .else_likely,
            .unlikely => .unpredictable,
            .cold => .else_cold,
            .unpredictable => .unpredictable,
        },
        .cold => .then_cold,
        .unpredictable => .unpredictable,
    };

    const then_block = try self.wip.block(1, "Then");
    const else_block = try self.wip.block(1, "Else");
    _ = try self.wip.brCond(cond, then_block, else_block, switch (hint) {
        .none, .then_cold, .else_cold => .none,
        .unpredictable => .unpredictable,
        .then_likely => .then_likely,
        .else_likely => .else_likely,
    });

    self.wip.cursor = .{ .block = then_block };
    if (hint == .then_cold) _ = try self.wip.callIntrinsicAssumeCold();
    try self.genBodyDebugScope(null, then_body, cond_br.branch_hints.then_cov);

    self.wip.cursor = .{ .block = else_block };
    if (hint == .else_cold) _ = try self.wip.callIntrinsicAssumeCold();
    try self.genBodyDebugScope(null, else_body, cond_br.branch_hints.else_cov);

    // No need to reset the insert cursor since this instruction is noreturn.
}

fn airTry(self: *FuncGen, inst: Air.Inst.Index, err_cold: bool) TodoError!Builder.Value {
    const unwrapped_try = self.air.unwrapTry(inst);
    const err_union = try self.resolveInst(unwrapped_try.error_union);
    const body = unwrapped_try.else_body;
    const err_union_ty = self.typeOf(unwrapped_try.error_union);
    const is_unused = self.liveness.isUnused(inst);
    return lowerTry(self, err_union, body, err_union_ty, false, .none, is_unused, err_cold);
}

fn airTryPtr(self: *FuncGen, inst: Air.Inst.Index, err_cold: bool) TodoError!Builder.Value {
    const zcu = self.object.zcu;
    const unwrapped_try = self.air.unwrapTryPtr(inst);
    const err_union_ptr = try self.resolveInst(unwrapped_try.error_union_ptr);
    const body = unwrapped_try.else_body;
    const err_union_ptr_ty = self.typeOf(unwrapped_try.error_union_ptr);
    const err_union_ty = err_union_ptr_ty.childType(zcu);
    const is_unused = self.liveness.isUnused(inst);

    self.maybeMarkAllowZeroAccess(self.typeOf(unwrapped_try.error_union_ptr).ptrInfo(zcu));

    return lowerTry(self, err_union_ptr, body, err_union_ty, true, err_union_ptr_ty.ptrAlignment(zcu), is_unused, err_cold);
}

fn lowerTry(
    fg: *FuncGen,
    err_union: Builder.Value,
    body: []const Air.Inst.Index,
    err_union_ty: Type,
    operand_is_ptr: bool,
    operand_ptr_align: InternPool.Alignment,
    is_unused: bool,
    err_cold: bool,
) TodoError!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    const payload_has_bits = payload_ty.hasRuntimeBits(zcu);
    const error_type = try o.errorIntType();

    const err_set_align: InternPool.Alignment, const payload_align: InternPool.Alignment = if (operand_is_ptr) .{
        operand_ptr_align.minStrict(Type.anyerror.abiAlignment(zcu)),
        operand_ptr_align.minStrict(payload_ty.abiAlignment(zcu)),
    } else .{ .none, .none };

    if (!err_union_ty.errorUnionSet(zcu).errorSetIsEmpty(zcu)) {
        const loaded = loaded: {
            const access_kind: Builder.MemoryAccessKind =
                if (err_union_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

            if (!payload_has_bits) {
                break :loaded if (operand_is_ptr)
                    try fg.wip.load(access_kind, error_type, err_union, err_set_align.toLlvm(), "")
                else
                    err_union;
            }

            assert(isByRef(err_union_ty, zcu)); // error unions are by-ref unless the payload has no bits
            const offset = codegen.errUnionErrorOffset(payload_ty, zcu);
            const err_field_ptr = try fg.ptraddConst(err_union, offset);
            break :loaded try fg.wip.load(
                if (operand_is_ptr) access_kind else .normal,
                error_type,
                err_field_ptr,
                err_set_align.toLlvm(),
                "",
            );
        };
        const zero = try o.builder.intValue(error_type, 0);
        const is_err = try fg.wip.icmp(.ne, loaded, zero, "");

        const return_block = try fg.wip.block(1, "TryRet");
        const continue_block = try fg.wip.block(1, "TryCont");
        _ = try fg.wip.brCond(is_err, return_block, continue_block, if (err_cold) .none else .else_likely);

        fg.wip.cursor = .{ .block = return_block };
        if (err_cold) _ = try fg.wip.callIntrinsicAssumeCold();
        try fg.genBodyDebugScope(null, body, .poi);

        fg.wip.cursor = .{ .block = continue_block };
    }
    if (is_unused) return .none;
    if (!payload_has_bits) return if (operand_is_ptr) err_union else .none;
    assert(isByRef(err_union_ty, zcu)); // error unions are by-ref unless the payload has no bits
    const payload_ptr = try fg.ptraddConst(err_union, codegen.errUnionPayloadOffset(payload_ty, zcu));
    if (operand_is_ptr) {
        return payload_ptr;
    } else if (isByRef(payload_ty, zcu)) {
        return fg.loadByRef(payload_ptr, payload_ty, payload_align.toLlvm(), .normal);
    } else {
        return fg.wip.load(.normal, try o.lowerType(payload_ty), payload_ptr, payload_align.toLlvm(), "");
    }
}

fn airSwitchBr(self: *FuncGen, inst: Air.Inst.Index, is_dispatch_loop: bool) TodoError!void {
    const o = self.object;
    const zcu = o.zcu;

    const switch_br = self.air.unwrapSwitch(inst);

    // For `loop_switch_br`, we need these BBs prepared ahead of time to generate dispatches.
    // For `switch_br`, they allow us to sometimes generate better IR by sharing a BB between
    // scalar and range cases in the same prong.
    // +1 for `else` case. This is not the same as the LLVM `else` prong, as that may first contain
    // conditionals to handle ranges.
    const case_blocks = try self.gpa.alloc(Builder.Function.Block.Index, switch_br.cases_len + 1);
    defer self.gpa.free(case_blocks);
    // We set incoming as 0 for now, and increment it as we construct dispatches.
    for (case_blocks[0 .. case_blocks.len - 1]) |*b| b.* = try self.wip.block(0, "Case");
    case_blocks[case_blocks.len - 1] = try self.wip.block(0, "Default");

    // There's a special case here to manually generate a jump table in some cases.
    //
    // Labeled switch in Zig is intended to follow the "direct threading" pattern. We would ideally use a jump
    // table, and each `continue` has its own indirect `jmp`, to allow the branch predictor to more accurately
    // use data patterns to predict future dispatches. The problem, however, is that LLVM emits fascinatingly
    // bad asm for this. Not only does it not share the jump table -- which we really need it to do to prevent
    // destroying the cache -- but it also actually generates slightly different jump tables for each case,
    // and *a separate conditional branch beforehand* to handle dispatching back to the case we're currently
    // within(!!).
    //
    // This asm is really, really, not what we want. As such, we will construct the jump table manually where
    // appropriate (the values are dense and relatively few), and use it when lowering dispatches.

    const jmp_table: ?SwitchDispatchInfo.JmpTable = jmp_table: {
        if (!is_dispatch_loop) break :jmp_table null;

        // Workaround for:
        // * https://github.com/llvm/llvm-project/blob/56905dab7da50bccfcceaeb496b206ff476127e1/llvm/lib/MC/WasmObjectWriter.cpp#L560
        // * https://github.com/llvm/llvm-project/blob/56905dab7da50bccfcceaeb496b206ff476127e1/llvm/test/MC/WebAssembly/blockaddress.ll
        if (zcu.comp.getTarget().cpu.arch.isWasm()) break :jmp_table null;

        // On a 64-bit target, 1024 pointers in our jump table is about 8K of pointers. This seems just
        // about acceptable - it won't fill L1d cache on most CPUs.
        const max_table_len = 1024;

        const cond_ty = self.typeOf(switch_br.operand);
        switch (cond_ty.zigTypeTag(zcu)) {
            .bool, .pointer => break :jmp_table null,
            .@"enum", .int, .error_set, .@"struct", .@"union" => {},
            else => unreachable,
        }

        if (cond_ty.intInfo(zcu).signedness == .signed) break :jmp_table null;

        // Don't worry about the size of the type -- it's irrelevant, because the prong values could be fairly dense.
        // If they are, then we will construct a jump table.
        const min, const max = self.switchCaseItemRange(switch_br) orelse break :jmp_table null;
        const min_int = min.getUnsignedInt(zcu) orelse break :jmp_table null;
        const max_int = max.getUnsignedInt(zcu) orelse break :jmp_table null;
        const table_len = max_int - min_int + 1;
        if (table_len > max_table_len) break :jmp_table null;

        const table_elems = try self.gpa.alloc(Builder.Constant, @intCast(table_len));
        defer self.gpa.free(table_elems);

        // Set them all to the `else` branch, then iterate over the AIR switch
        // and replace all values which correspond to other prongs.
        @memset(table_elems, try o.builder.blockAddrConst(
            self.wip.function,
            case_blocks[case_blocks.len - 1],
        ));
        var item_count: u32 = 0;
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            const case_block = case_blocks[case.idx];
            const case_block_addr = try o.builder.blockAddrConst(
                self.wip.function,
                case_block,
            );
            for (case.items) |item| {
                const val = Value.fromInterned(item.toInterned().?);
                const table_idx = val.toUnsignedInt(zcu) - min_int;
                table_elems[@intCast(table_idx)] = case_block_addr;
                item_count += 1;
            }
            for (case.ranges) |range| {
                const low = Value.fromInterned(range[0].toInterned().?);
                const high = Value.fromInterned(range[1].toInterned().?);
                const low_idx = low.toUnsignedInt(zcu) - min_int;
                const high_idx = high.toUnsignedInt(zcu) - min_int;
                @memset(table_elems[@intCast(low_idx)..@intCast(high_idx + 1)], case_block_addr);
                item_count += @intCast(high_idx + 1 - low_idx);
            }
        }

        const table_llvm_ty = try o.builder.arrayType(table_elems.len, .ptr);
        const table_val = try o.builder.arrayConst(table_llvm_ty, table_elems);

        const table_variable = try o.builder.addVariable(
            try o.builder.strtabStringFmt("__jmptab_{d}", .{@intFromEnum(inst)}),
            table_llvm_ty,
            .default,
        );
        try table_variable.setInitializer(table_val, &o.builder);
        const table_global = table_variable.ptrConst(&o.builder).global;
        table_global.setLinkage(if (o.builder.strip) .private else .internal, &o.builder);
        table_global.setUnnamedAddr(.unnamed_addr, &o.builder);

        const table_includes_else = item_count != table_len;

        break :jmp_table .{
            .min = try o.lowerValue(min.toIntern()),
            .max = try o.lowerValue(max.toIntern()),
            .in_bounds_hint = if (table_includes_else) .none else switch (switch_br.getElseHint()) {
                .none, .cold => .none,
                .unpredictable => .unpredictable,
                .likely => .likely,
                .unlikely => .unlikely,
            },
            .table = table_global.toConst(),
            .table_includes_else = table_includes_else,
        };
    };

    const weights: Builder.Function.Instruction.BrCond.Weights = weights: {
        if (jmp_table != null) break :weights .none; // not used

        // First pass. If any weights are `.unpredictable`, unpredictable.
        // If all are `.none` or `.cold`, none.
        var any_likely = false;
        for (0..switch_br.cases_len) |case_idx| {
            switch (switch_br.getHint(@intCast(case_idx))) {
                .none, .cold => {},
                .likely, .unlikely => any_likely = true,
                .unpredictable => break :weights .unpredictable,
            }
        }
        switch (switch_br.getElseHint()) {
            .none, .cold => {},
            .likely, .unlikely => any_likely = true,
            .unpredictable => break :weights .unpredictable,
        }
        if (!any_likely) break :weights .none;

        const llvm_cases_len = llvm_cases_len: {
            var len: u32 = 0;
            var it = switch_br.iterateCases();
            while (it.next()) |case| len += @intCast(case.items.len);
            break :llvm_cases_len len;
        };

        var weights = try self.gpa.alloc(Builder.Metadata, 1 + llvm_cases_len + 1);
        defer self.gpa.free(weights);
        var weight_idx: usize = 0;

        const branch_weights_str = try o.builder.metadataString("branch_weights");
        weights[weight_idx] = branch_weights_str.toMetadata();
        weight_idx += 1;

        const else_weight: u32 = switch (switch_br.getElseHint()) {
            .unpredictable => unreachable,
            .none, .cold => 1000,
            .likely => 2000,
            .unlikely => 1,
        };
        weights[weight_idx] = try o.builder.metadataConstant(try o.builder.intConst(.i32, else_weight));
        weight_idx += 1;

        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            const weight_val: u32 = switch (switch_br.getHint(case.idx)) {
                .unpredictable => unreachable,
                .none, .cold => 1000,
                .likely => 2000,
                .unlikely => 1,
            };
            const weight_meta = try o.builder.metadataConstant(try o.builder.intConst(.i32, weight_val));
            @memset(weights[weight_idx..][0..case.items.len], weight_meta);
            weight_idx += case.items.len;
        }

        assert(weight_idx == weights.len);
        break :weights .fromMetadata(try o.builder.metadataTuple(weights));
    };

    const dispatch_info: SwitchDispatchInfo = .{
        .case_blocks = case_blocks,
        .switch_weights = weights,
        .jmp_table = jmp_table,
    };

    if (is_dispatch_loop) {
        try self.switch_dispatch_info.putNoClobber(self.gpa, inst, dispatch_info);
    }
    defer if (is_dispatch_loop) {
        assert(self.switch_dispatch_info.remove(inst));
    };

    // Generate the initial dispatch.
    // If this is a simple `switch_br`, this is the only dispatch.
    try self.lowerSwitchDispatch(inst, switch_br.operand, dispatch_info);

    // Iterate the cases and generate their bodies.
    var it = switch_br.iterateCases();
    while (it.next()) |case| {
        const case_block = case_blocks[case.idx];
        self.wip.cursor = .{ .block = case_block };
        if (switch_br.getHint(case.idx) == .cold) _ = try self.wip.callIntrinsicAssumeCold();
        try self.genBodyDebugScope(null, case.body, .none);
    }
    self.wip.cursor = .{ .block = case_blocks[case_blocks.len - 1] };
    const else_body = it.elseBody();
    if (switch_br.getElseHint() == .cold) _ = try self.wip.callIntrinsicAssumeCold();
    if (else_body.len > 0) {
        try self.genBodyDebugScope(null, it.elseBody(), .none);
    } else {
        _ = try self.wip.@"unreachable"();
    }
}

fn switchCaseItemRange(self: *FuncGen, switch_br: Air.UnwrappedSwitch) ?[2]Value {
    const zcu = self.object.zcu;
    var it = switch_br.iterateCases();
    var min: ?Value = null;
    var max: ?Value = null;
    while (it.next()) |case| {
        for (case.items) |item| {
            const val = Value.fromInterned(item.toInterned().?);
            const low = if (min) |m| val.compareHetero(.lt, m, zcu) else true;
            const high = if (max) |m| val.compareHetero(.gt, m, zcu) else true;
            if (low) min = val;
            if (high) max = val;
        }
        for (case.ranges) |range| {
            const vals: [2]Value = .{
                Value.fromInterned(range[0].toInterned().?),
                Value.fromInterned(range[1].toInterned().?),
            };
            const low = if (min) |m| vals[0].compareHetero(.lt, m, zcu) else true;
            const high = if (max) |m| vals[1].compareHetero(.gt, m, zcu) else true;
            if (low) min = vals[0];
            if (high) max = vals[1];
        }
    }
    if (min == null) {
        assert(max == null);
        return null;
    }
    return .{ min.?, max.? };
}

fn airLoop(self: *FuncGen, inst: Air.Inst.Index) TodoError!void {
    const block = self.air.unwrapBlock(inst);
    const body = block.body;
    const loop_block = try self.wip.block(1, "Loop"); // `airRepeat` will increment incoming each time
    _ = try self.wip.br(loop_block);

    try self.loops.putNoClobber(self.gpa, inst, loop_block);
    defer assert(self.loops.remove(inst));

    self.wip.cursor = .{ .block = loop_block };
    try self.genBodyDebugScope(null, body, .none);
}

fn airArrayToSlice(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_ty = self.typeOf(ty_op.operand);
    const array_ty = operand_ty.childType(zcu);
    const llvm_usize = try o.lowerType(.usize);
    const len = try o.builder.intValue(llvm_usize, array_ty.arrayLen(zcu));
    const slice_llvm_ty = try o.lowerType(self.typeOfIndex(inst));
    const operand = try self.resolveInst(ty_op.operand);
    return self.wip.buildAggregate(slice_llvm_ty, &.{ operand, len }, "");
}

fn airFloatFromInt(self: *FuncGen, inst: Air.Inst.Index) TodoError!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const operand_scalar_ty = operand_ty.scalarType(zcu);
    const is_signed_int = operand_scalar_ty.isSignedInt(zcu);

    const dest_ty = self.typeOfIndex(inst);
    const dest_scalar_ty = dest_ty.scalarType(zcu);
    const dest_llvm_ty = try o.lowerType(dest_ty);
    const target = zcu.getTarget();

    if (intrinsicsAllowed(dest_scalar_ty, target)) return self.wip.conv(
        if (is_signed_int) .signed else .unsigned,
        operand,
        dest_llvm_ty,
        "",
    );

    const rt_int_bits = compilerRtIntBits(@intCast(operand_scalar_ty.bitSize(zcu))) orelse {
        return self.todo("float_from_int on {d} bit integer", .{operand_scalar_ty.bitSize(zcu)});
    };
    const rt_int_ty = try o.builder.intType(rt_int_bits);
    var extended = try self.wip.conv(
        if (is_signed_int) .signed else .unsigned,
        operand,
        rt_int_ty,
        "",
    );
    const dest_bits = dest_scalar_ty.floatBits(target);
    const compiler_rt_operand_abbrev = compilerRtIntAbbrev(rt_int_bits);
    const compiler_rt_dest_abbrev = compilerRtFloatAbbrev(dest_bits);
    const sign_prefix = if (is_signed_int) "" else "un";
    const fn_name = try o.builder.strtabStringFmt("__float{s}{s}i{s}f", .{
        sign_prefix,
        compiler_rt_operand_abbrev,
        compiler_rt_dest_abbrev,
    });

    var param_type = rt_int_ty;
    if (rt_int_bits == 128 and (target.os.tag == .windows and target.cpu.arch == .x86_64)) {
        // On Windows x86-64, "ti" functions must use Vector(2, u64) instead of the standard
        // i128 calling convention to adhere to the ABI that LLVM expects compiler-rt to have.
        param_type = try o.builder.vectorType(.normal, 2, .i64);
        extended = try self.wip.cast(.bitcast, extended, param_type, "");
    }

    const libc_fn = try o.getLibcFunction(fn_name, &.{param_type}, dest_llvm_ty);
    return self.wip.call(
        .normal,
        .ccc,
        .none,
        libc_fn.typeOf(&o.builder),
        libc_fn.toValue(&o.builder),
        &.{extended},
        "",
    );
}

fn airIntFromFloat(
    self: *FuncGen,
    inst: Air.Inst.Index,
    fast: Builder.FastMathKind,
) TodoError!Builder.Value {
    _ = fast;

    const o = self.object;
    const zcu = o.zcu;
    const target = zcu.getTarget();
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const operand_scalar_ty = operand_ty.scalarType(zcu);

    const dest_ty = self.typeOfIndex(inst);
    const dest_scalar_ty = dest_ty.scalarType(zcu);
    const dest_llvm_ty = try o.lowerType(dest_ty);

    if (intrinsicsAllowed(operand_scalar_ty, target)) {
        // TODO set fast math flag
        return self.wip.conv(
            if (dest_scalar_ty.isSignedInt(zcu)) .signed else .unsigned,
            operand,
            dest_llvm_ty,
            "",
        );
    }

    const rt_int_bits = compilerRtIntBits(@intCast(dest_scalar_ty.bitSize(zcu))) orelse {
        return self.todo("int_from_float to {d} bit integer", .{dest_scalar_ty.bitSize(zcu)});
    };
    const ret_ty = try o.builder.intType(rt_int_bits);
    const libc_ret_ty = if (rt_int_bits == 128 and (target.os.tag == .windows and target.cpu.arch == .x86_64)) b: {
        // On Windows x86-64, "ti" functions must use Vector(2, u64) instead of the standard
        // i128 calling convention to adhere to the ABI that LLVM expects compiler-rt to have.
        break :b try o.builder.vectorType(.normal, 2, .i64);
    } else ret_ty;

    const operand_bits = operand_scalar_ty.floatBits(target);
    const compiler_rt_operand_abbrev = compilerRtFloatAbbrev(operand_bits);

    const compiler_rt_dest_abbrev = compilerRtIntAbbrev(rt_int_bits);
    const sign_prefix = if (dest_scalar_ty.isSignedInt(zcu)) "" else "uns";

    const fn_name = try o.builder.strtabStringFmt("__fix{s}{s}f{s}i", .{
        sign_prefix,
        compiler_rt_operand_abbrev,
        compiler_rt_dest_abbrev,
    });

    const operand_llvm_ty = try o.lowerType(operand_ty);
    const libc_fn = try o.getLibcFunction(fn_name, &.{operand_llvm_ty}, libc_ret_ty);
    var result = try self.wip.call(
        .normal,
        .ccc,
        .none,
        libc_fn.typeOf(&o.builder),
        libc_fn.toValue(&o.builder),
        &.{operand},
        "",
    );

    if (libc_ret_ty != ret_ty) result = try self.wip.cast(.bitcast, result, ret_ty, "");
    if (ret_ty != dest_llvm_ty) result = try self.wip.cast(.trunc, result, dest_llvm_ty, "");
    return result;
}

fn sliceOrArrayPtr(fg: *FuncGen, ptr: Builder.Value, ty: Type) Allocator.Error!Builder.Value {
    const zcu = fg.object.zcu;
    return if (ty.isSlice(zcu)) fg.wip.extractValue(ptr, &.{0}, "") else ptr;
}

fn sliceOrArrayLenInBytes(fg: *FuncGen, ptr: Builder.Value, ty: Type) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const llvm_usize = try o.lowerType(.usize);
    switch (ty.ptrSize(zcu)) {
        .slice => {
            const len = try fg.wip.extractValue(ptr, &.{1}, "");
            const elem_ty = ty.childType(zcu);
            const abi_size = elem_ty.abiSize(zcu);
            if (abi_size == 1) return len;
            const abi_size_llvm_val = try o.builder.intValue(llvm_usize, abi_size);
            return fg.wip.bin(.@"mul nuw", len, abi_size_llvm_val, "");
        },
        .one => {
            const array_ty = ty.childType(zcu);
            const elem_ty = array_ty.childType(zcu);
            const abi_size = elem_ty.abiSize(zcu);
            return o.builder.intValue(llvm_usize, array_ty.arrayLen(zcu) * abi_size);
        },
        .many, .c => unreachable,
    }
}

fn airSliceField(self: *FuncGen, inst: Air.Inst.Index, index: u32) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    return self.wip.extractValue(operand, &.{index}, "");
}

fn airPtrSliceFieldPtr(self: *FuncGen, inst: Air.Inst.Index, index: u1) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const slice_ptr = try self.resolveInst(ty_op.operand);
    return self.ptraddConst(slice_ptr, index * Type.usize.abiSize(zcu));
}

fn airSliceElemVal(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const slice_ty = self.typeOf(bin_op.lhs);
    const slice = try self.resolveInst(bin_op.lhs);
    const index = try self.resolveInst(bin_op.rhs);
    const slice_info = slice_ty.ptrInfo(zcu);
    assert(slice_info.flags.size == .slice);
    const elem_ty: Type = .fromInterned(slice_info.child);
    const base_ptr = try self.wip.extractValue(slice, &.{0}, "");
    const ptr = try self.ptraddScaled(base_ptr, index, elem_ty.abiSize(zcu));
    const elem_align = slice_ty.ptrAlignment(zcu).min(elem_ty.abiAlignment(zcu));
    const access_kind: Builder.MemoryAccessKind = if (slice_info.flags.is_volatile) .@"volatile" else .normal;
    self.maybeMarkAllowZeroAccess(slice_info);
    if (isByRef(elem_ty, zcu)) {
        return self.loadByRef(ptr, elem_ty, elem_align.toLlvm(), access_kind);
    } else {
        return self.loadTruncate(access_kind, elem_ty, ptr, elem_align.toLlvm());
    }
}

fn airSliceElemPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = self.air.extraData(Air.Bin, ty_pl.payload).data;
    const slice_ty = self.typeOf(bin_op.lhs);

    const slice = try self.resolveInst(bin_op.lhs);
    const index = try self.resolveInst(bin_op.rhs);
    const base_ptr = try self.wip.extractValue(slice, &.{0}, "");
    return self.ptraddScaled(base_ptr, index, slice_ty.childType(zcu).abiSize(zcu));
}

fn airArrayElemVal(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;

    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const array_ty = self.typeOf(bin_op.lhs);
    const array_llvm_val = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const elem_ty = array_ty.childType(zcu);
    if (isByRef(array_ty, zcu)) {
        const elem_ptr = try self.ptraddScaled(array_llvm_val, rhs, elem_ty.abiSize(zcu));
        if (isByRef(elem_ty, zcu)) {
            const elem_align = elem_ty.abiAlignment(zcu).toLlvm();
            return self.loadByRef(elem_ptr, elem_ty, elem_align, .normal);
        } else {
            return self.loadTruncate(.normal, elem_ty, elem_ptr, .default);
        }
    }

    // This branch can be reached for vectors, which are always by-value.
    return self.wip.extractElement(array_llvm_val, rhs, "");
}

fn airPtrElemVal(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const ptr_ty = self.typeOf(bin_op.lhs);
    const elem_ty = ptr_ty.indexableElem(zcu);
    const base_ptr = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    self.maybeMarkAllowZeroAccess(ptr_ty.ptrInfo(zcu));

    return self.load(
        try self.ptraddScaled(base_ptr, rhs, elem_ty.abiSize(zcu)),
        elem_ty,
        ptr_ty.ptrAlignment(zcu).min(elem_ty.abiAlignment(zcu)).toLlvm(),
        if (ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal,
    );
}

fn airPtrElemPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = self.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr_ty = self.typeOf(bin_op.lhs);
    const elem_ty = ptr_ty.indexableElem(zcu);
    assert(elem_ty.hasRuntimeBits(zcu));

    const base_ptr = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    const elem_ptr = ty_pl.ty.toType();
    if (elem_ptr.ptrInfo(zcu).flags.vector_index != .none) return base_ptr;

    return self.ptraddScaled(base_ptr, rhs, elem_ty.abiSize(zcu));
}

fn airStructFieldPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const struct_field = self.air.extraData(Air.StructField, ty_pl.payload).data;
    const struct_ptr = try self.resolveInst(struct_field.struct_operand);
    const struct_ptr_ty = self.typeOf(struct_field.struct_operand);
    return self.fieldPtr(struct_ptr, struct_ptr_ty, struct_field.field_index);
}

fn airStructFieldPtrIndex(
    self: *FuncGen,
    inst: Air.Inst.Index,
    field_index: u32,
) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const struct_ptr = try self.resolveInst(ty_op.operand);
    const struct_ptr_ty = self.typeOf(ty_op.operand);
    return self.fieldPtr(struct_ptr, struct_ptr_ty, field_index);
}

fn airStructFieldVal(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const struct_field = self.air.extraData(Air.StructField, ty_pl.payload).data;
    const struct_ty = self.typeOf(struct_field.struct_operand);
    const struct_llvm_val = try self.resolveInst(struct_field.struct_operand);
    const field_index = struct_field.field_index;
    const field_ty = struct_ty.fieldType(field_index, zcu);
    assert(field_ty.hasRuntimeBits(zcu));

    if (!isByRef(struct_ty, zcu)) {
        // All auto/extern struct/union types are by-ref, unless they have no runtime bits, in which
        // case we shouldn't be seeing this instruction to begin with. Therefore we must be dealing
        // with a `packed struct` or `packed union`.
        assert(struct_ty.containerLayout(zcu) == .@"packed");
        assert(!isByRef(field_ty, zcu));
        const field_int_val: Builder.Value = switch (struct_ty.zigTypeTag(zcu)) {
            .@"struct" => field_int_val: {
                const llvm_field_int_ty = try o.builder.intType(@intCast(field_ty.bitSize(zcu)));
                const bit_offset = zcu.structPackedFieldBitOffset(
                    zcu.intern_pool.loadStructType(struct_ty.toIntern()),
                    field_index,
                );
                const shift_bits = try o.builder.intValue(struct_llvm_val.typeOfWip(&self.wip), bit_offset);
                const shifted = try self.wip.bin(.lshr, struct_llvm_val, shift_bits, "");
                break :field_int_val try self.wip.cast(.trunc, shifted, llvm_field_int_ty, "");
            },
            .@"union" => struct_llvm_val,
            else => unreachable,
        };
        switch (field_ty.zigTypeTag(zcu)) {
            else => unreachable, // not packable
            .void => unreachable, // opv bug in sema
            .int, .bool, .@"enum", .@"struct", .@"union" => {
                // Represented as integers, so already done
                return field_int_val;
            },
            .float => {
                // bitcast int->float
                return self.wip.cast(.bitcast, field_int_val, try o.lowerType(field_ty), "");
            },
        }
    }

    const offset: u64 = switch (struct_ty.zigTypeTag(zcu)) {
        .@"struct" => struct_ty.structFieldOffset(field_index, zcu),
        .@"union" => struct_ty.unionGetLayout(zcu).payloadOffset(),
        else => unreachable,
    };

    const struct_ptr_align = struct_ty.abiAlignment(zcu);
    const field_ptr = try self.ptraddConst(struct_llvm_val, offset);
    const field_ptr_align: InternPool.Alignment = switch (offset) {
        0 => struct_ptr_align,
        else => struct_ptr_align.minStrict(.fromLog2Units(@ctz(offset))),
    };

    if (isByRef(field_ty, zcu)) {
        return self.loadByRef(field_ptr, field_ty, field_ptr_align.toLlvm(), .normal);
    } else {
        return self.loadTruncate(.normal, field_ty, field_ptr, field_ptr_align.toLlvm());
    }
}

fn airFieldParentPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = self.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;

    const field_ptr = try self.resolveInst(extra.field_ptr);

    const parent_ty = ty_pl.ty.toType().childType(zcu);
    const field_offset = parent_ty.structFieldOffset(extra.field_index, zcu);
    if (field_offset == 0) return field_ptr;

    const res_ty = try o.lowerType(ty_pl.ty.toType());
    const llvm_usize = try o.lowerType(.usize);

    const field_ptr_int = try self.wip.cast(.ptrtoint, field_ptr, llvm_usize, "");
    const base_ptr_int = try self.wip.bin(
        .@"sub nuw",
        field_ptr_int,
        try o.builder.intValue(llvm_usize, field_offset),
        "",
    );
    return self.wip.cast(.inttoptr, base_ptr_int, res_ty, "");
}

fn airNot(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);

    return self.wip.not(operand, "");
}

fn airUnreach(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!void {
    _ = inst;
    _ = try self.wip.@"unreachable"();
}

fn airDbgStmt(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const dbg_stmt = self.air.instructions.items(.data)[@intFromEnum(inst)].dbg_stmt;
    self.prev_dbg_line = @intCast(self.base_line + dbg_stmt.line + 1);
    self.prev_dbg_column = @intCast(dbg_stmt.column + 1);

    self.wip.debug_location = .{ .location = .{
        .line = self.prev_dbg_line,
        .column = self.prev_dbg_column,
        .scope = self.scope.toOptional(),
        .inlined_at = self.inlined_at,
    } };

    return .none;
}

fn airDbgEmptyStmt(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    _ = self;
    _ = inst;
    return .none;
}

fn airDbgVarPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const pt = self.pt;
    const zcu = o.zcu;
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const operand = try self.resolveInst(pl_op.operand);
    const name: Air.NullTerminatedString = @enumFromInt(pl_op.payload);
    const ptr_ty = self.typeOf(pl_op.operand);

    const debug_local_var = try o.builder.debugLocalVar(
        try o.builder.metadataString(name.toSlice(self.air)),
        self.file,
        self.scope,
        self.prev_dbg_line,
        try o.getDebugType(pt, ptr_ty.childType(zcu)),
    );

    _ = try self.wip.callIntrinsic(
        .normal,
        .none,
        .@"dbg.declare",
        &.{},
        &.{
            (try self.wip.debugValue(operand)).toValue(),
            debug_local_var.toValue(),
            (try o.builder.debugExpression(&.{})).toValue(),
        },
        "",
    );

    return .none;
}

fn airDbgVarVal(self: *FuncGen, inst: Air.Inst.Index, is_arg: bool) Allocator.Error!Builder.Value {
    const o = self.object;
    const pt = self.pt;
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const operand = try self.resolveInst(pl_op.operand);
    const operand_ty = self.typeOf(pl_op.operand);
    const name: Air.NullTerminatedString = @enumFromInt(pl_op.payload);
    const name_slice = name.toSlice(self.air);
    const metadata_name = if (name_slice.len > 0) try o.builder.metadataString(name_slice) else null;
    const debug_local_var = if (is_arg) try o.builder.debugParameter(
        metadata_name,
        self.file,
        self.scope,
        self.prev_dbg_line,
        try o.getDebugType(pt, operand_ty),
        arg_no: {
            self.arg_inline_index += 1;
            break :arg_no self.arg_inline_index;
        },
    ) else try o.builder.debugLocalVar(
        metadata_name,
        self.file,
        self.scope,
        self.prev_dbg_line,
        try o.getDebugType(pt, operand_ty),
    );

    const zcu = o.zcu;
    const owner_mod = self.ownerModule();
    if (isByRef(operand_ty, zcu)) {
        _ = try self.wip.callIntrinsic(
            .normal,
            .none,
            .@"dbg.declare",
            &.{},
            &.{
                (try self.wip.debugValue(operand)).toValue(),
                debug_local_var.toValue(),
                (try o.builder.debugExpression(&.{})).toValue(),
            },
            "",
        );
    } else if (owner_mod.optimize_mode == .Debug and !self.is_naked) {
        // We avoid taking this path for naked functions because there's no guarantee that such
        // functions even have a valid stack pointer, making the `alloca` + `store` unsafe.

        const alignment = operand_ty.abiAlignment(zcu).toLlvm();
        const alloca = try self.buildAlloca(operand.typeOfWip(&self.wip), alignment);
        _ = try self.wip.store(.normal, operand, alloca, alignment);
        _ = try self.wip.callIntrinsic(
            .normal,
            .none,
            .@"dbg.declare",
            &.{},
            &.{
                (try self.wip.debugValue(alloca)).toValue(),
                debug_local_var.toValue(),
                (try o.builder.debugExpression(&.{})).toValue(),
            },
            "",
        );
    } else {
        _ = try self.wip.callIntrinsic(
            .normal,
            .none,
            .@"dbg.value",
            &.{},
            &.{
                (try self.wip.debugValue(operand)).toValue(),
                debug_local_var.toValue(),
                (try o.builder.debugExpression(&.{})).toValue(),
            },
            "",
        );
    }
    return .none;
}

fn airAssembly(self: *FuncGen, inst: Air.Inst.Index) TodoError!Builder.Value {
    // Eventually, the Zig compiler needs to be reworked to have inline
    // assembly go through the same parsing code regardless of backend, and
    // have LLVM-flavored inline assembly be *output* from that assembler.
    // We don't have such an assembler implemented yet though. For now,
    // this implementation feeds the inline assembly code directly to LLVM.

    const o = self.object;
    const unwrapped_asm = self.air.unwrapAsm(inst);
    const is_volatile = unwrapped_asm.is_volatile;
    const gpa = self.gpa;

    const outputs = unwrapped_asm.outputs;
    const inputs = unwrapped_asm.inputs;

    var llvm_constraints: std.ArrayList(u8) = .empty;
    defer llvm_constraints.deinit(gpa);

    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    // The exact number of return / parameter values depends on which output values
    // are passed by reference as indirect outputs (determined below).
    const max_return_count = outputs.len;
    const llvm_ret_types = try arena.alloc(Builder.Type, max_return_count);
    const llvm_ret_indirect = try arena.alloc(bool, max_return_count);
    const llvm_rw_vals = try arena.alloc(Builder.Value, max_return_count);

    const max_param_count = max_return_count + inputs.len + outputs.len;
    const llvm_param_types = try arena.alloc(Builder.Type, max_param_count);
    const llvm_param_values = try arena.alloc(Builder.Value, max_param_count);
    // This stores whether we need to add an elementtype attribute and
    // if so, the element type itself.
    const llvm_param_attrs = try arena.alloc(Builder.Type, max_param_count);
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const target = zcu.getTarget();

    var llvm_ret_i: usize = 0;
    var llvm_param_i: usize = 0;
    var total_i: usize = 0;

    var name_map: std.StringArrayHashMapUnmanaged(u16) = .empty;
    try name_map.ensureUnusedCapacity(arena, max_param_count);

    var it = unwrapped_asm.iterateOutputs();
    while (it.next()) |output| {
        const constraint = output.constraint;
        const name = output.name;

        try llvm_constraints.ensureUnusedCapacity(gpa, constraint.len + 3);
        if (total_i != 0) {
            llvm_constraints.appendAssumeCapacity(',');
        }
        llvm_constraints.appendAssumeCapacity('=');

        if (output.operand != .none) {
            const output_inst = try self.resolveInst(output.operand);
            const output_ty = self.typeOf(output.operand);
            assert(output_ty.zigTypeTag(zcu) == .pointer);
            const elem_llvm_ty = try o.lowerType(output_ty.childType(zcu));

            switch (constraint[0]) {
                '=' => {},
                '+' => llvm_rw_vals[output.index] = output_inst,
                else => return self.todo("unsupported output constraint on output type '{c}'", .{
                    constraint[0],
                }),
            }

            self.maybeMarkAllowZeroAccess(output_ty.ptrInfo(zcu));

            // Pass any non-return outputs indirectly, if the constraint accepts a memory location
            llvm_ret_indirect[output.index] = constraintAllowsMemory(constraint);
            if (llvm_ret_indirect[output.index]) {
                // Pass the result by reference as an indirect output (e.g. "=*m")
                llvm_constraints.appendAssumeCapacity('*');

                llvm_param_values[llvm_param_i] = output_inst;
                llvm_param_types[llvm_param_i] = output_inst.typeOfWip(&self.wip);
                llvm_param_attrs[llvm_param_i] = elem_llvm_ty;
                llvm_param_i += 1;
            } else {
                // Pass the result directly (e.g. "=r")
                llvm_ret_types[llvm_ret_i] = elem_llvm_ty;
                llvm_ret_i += 1;
            }
        } else {
            switch (constraint[0]) {
                '=' => {},
                else => return self.todo("unsupported output constraint on result type '{s}'", .{
                    constraint,
                }),
            }

            llvm_ret_indirect[output.index] = false;

            const ret_ty = self.typeOfIndex(inst);
            llvm_ret_types[llvm_ret_i] = try o.lowerType(ret_ty);
            llvm_ret_i += 1;
        }

        // LLVM uses commas internally to separate different constraints,
        // alternative constraints are achieved with pipes.
        // We still allow the user to use commas in a way that is similar
        // to GCC's inline assembly.
        // http://llvm.org/docs/LangRef.html#constraint-codes
        for (constraint[1..]) |byte| {
            switch (byte) {
                ',' => llvm_constraints.appendAssumeCapacity('|'),
                '*' => {}, // Indirect outputs are handled above
                else => llvm_constraints.appendAssumeCapacity(byte),
            }
        }

        if (!std.mem.eql(u8, name, "_")) {
            const gop = name_map.getOrPutAssumeCapacity(name);
            if (gop.found_existing) return self.todo("duplicate asm output name '{s}'", .{name});
            gop.value_ptr.* = @intCast(total_i);
        }
        total_i += 1;
    }

    it = unwrapped_asm.iterateInputs();
    while (it.next()) |input| {
        const constraint = input.constraint;
        const name = input.name;

        const arg_llvm_value = try self.resolveInst(input.operand);
        const arg_ty = self.typeOf(input.operand);
        const is_by_ref = isByRef(arg_ty, zcu);
        if (is_by_ref) {
            if (constraintAllowsMemory(constraint)) {
                llvm_param_values[llvm_param_i] = arg_llvm_value;
                llvm_param_types[llvm_param_i] = arg_llvm_value.typeOfWip(&self.wip);
            } else {
                const alignment = arg_ty.abiAlignment(zcu).toLlvm();
                const arg_llvm_ty = try o.lowerType(arg_ty);
                const load_inst =
                    try self.wip.load(.normal, arg_llvm_ty, arg_llvm_value, alignment, "");
                llvm_param_values[llvm_param_i] = load_inst;
                llvm_param_types[llvm_param_i] = arg_llvm_ty;
            }
        } else {
            if (constraintAllowsRegister(constraint)) {
                llvm_param_values[llvm_param_i] = arg_llvm_value;
                llvm_param_types[llvm_param_i] = arg_llvm_value.typeOfWip(&self.wip);
            } else {
                const alignment = arg_ty.abiAlignment(zcu).toLlvm();
                const arg_ptr = try self.buildAlloca(arg_llvm_value.typeOfWip(&self.wip), alignment);
                _ = try self.wip.store(.normal, arg_llvm_value, arg_ptr, alignment);
                llvm_param_values[llvm_param_i] = arg_ptr;
                llvm_param_types[llvm_param_i] = arg_ptr.typeOfWip(&self.wip);
            }
        }

        try llvm_constraints.ensureUnusedCapacity(gpa, constraint.len + 1);
        if (total_i != 0) {
            llvm_constraints.appendAssumeCapacity(',');
        }
        for (constraint) |byte| {
            llvm_constraints.appendAssumeCapacity(switch (byte) {
                ',' => '|',
                else => byte,
            });
        }

        if (!std.mem.eql(u8, name, "_")) {
            const gop = name_map.getOrPutAssumeCapacity(name);
            if (gop.found_existing) return self.todo("duplicate asm input name '{s}'", .{name});
            gop.value_ptr.* = @intCast(total_i);
        }

        // In the case of indirect inputs, LLVM requires the callsite to have
        // an elementtype(<ty>) attribute.
        llvm_param_attrs[llvm_param_i] = if (constraint[0] == '*') blk: {
            if (!is_by_ref) self.maybeMarkAllowZeroAccess(arg_ty.ptrInfo(zcu));

            break :blk try o.lowerType(if (is_by_ref) arg_ty else arg_ty.childType(zcu));
        } else .none;

        llvm_param_i += 1;
        total_i += 1;
    }

    it = unwrapped_asm.iterateOutputs();
    while (it.next()) |output| {
        const constraint = output.constraint;

        if (constraint[0] != '+') continue;

        const rw_ty = self.typeOf(output.operand);
        const llvm_elem_ty = try o.lowerType(rw_ty.childType(zcu));
        if (llvm_ret_indirect[output.index]) {
            llvm_param_values[llvm_param_i] = llvm_rw_vals[output.index];
            llvm_param_types[llvm_param_i] = llvm_rw_vals[output.index].typeOfWip(&self.wip);
        } else {
            const alignment = rw_ty.abiAlignment(zcu).toLlvm();
            const loaded = try self.wip.load(
                if (rw_ty.isVolatilePtr(zcu)) .@"volatile" else .normal,
                llvm_elem_ty,
                llvm_rw_vals[output.index],
                alignment,
                "",
            );
            llvm_param_values[llvm_param_i] = loaded;
            llvm_param_types[llvm_param_i] = llvm_elem_ty;
        }

        try llvm_constraints.print(gpa, ",{d}", .{output.index});

        // In the case of indirect inputs, LLVM requires the callsite to have
        // an elementtype(<ty>) attribute.
        llvm_param_attrs[llvm_param_i] = if (llvm_ret_indirect[output.index]) llvm_elem_ty else .none;

        llvm_param_i += 1;
        total_i += 1;
    }

    if (total_i != 0) try llvm_constraints.append(gpa, ',');
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
        const name = clobbers_ty.structFieldName(field_index, zcu).toSlice(ip).?;
        total_i += try appendConstraints(gpa, &llvm_constraints, name, target);
    }

    // We have finished scanning through all inputs/outputs, so the number of
    // parameters and return values is known.
    const param_count = llvm_param_i;
    const return_count = llvm_ret_i;

    // For some targets, Clang unconditionally adds some clobbers to all inline assembly.
    // While this is probably not strictly necessary, if we don't follow Clang's lead
    // here then we may risk tripping LLVM bugs since anything not used by Clang tends
    // to be buggy and regress often.
    switch (target.cpu.arch) {
        .x86_64, .x86 => {
            try llvm_constraints.appendSlice(gpa, "~{dirflag},~{fpsr},~{flags},");
            total_i += 3;
        },
        .mips, .mipsel, .mips64, .mips64el => {
            try llvm_constraints.appendSlice(gpa, "~{$1},");
            total_i += 1;
        },
        else => {},
    }

    if (std.mem.endsWith(u8, llvm_constraints.items, ",")) llvm_constraints.items.len -= 1;

    const asm_source = unwrapped_asm.source;

    // hackety hacks until stage2 has proper inline asm in the frontend.
    var rendered_template = std.array_list.Managed(u8).init(gpa);
    defer rendered_template.deinit();

    const State = enum { start, percent, input, modifier };

    var state: State = .start;

    var name_start: usize = undefined;
    var modifier_start: usize = undefined;
    for (asm_source, 0..) |byte, i| {
        switch (state) {
            .start => switch (byte) {
                '%' => state = .percent,
                '$' => try rendered_template.appendSlice("$$"),
                else => try rendered_template.append(byte),
            },
            .percent => switch (byte) {
                '%' => {
                    try rendered_template.append('%');
                    state = .start;
                },
                '[' => {
                    try rendered_template.append('$');
                    try rendered_template.append('{');
                    name_start = i + 1;
                    state = .input;
                },
                '=' => {
                    try rendered_template.appendSlice("${:uid}");
                    state = .start;
                },
                else => {
                    try rendered_template.append('%');
                    try rendered_template.append(byte);
                    state = .start;
                },
            },
            .input => switch (byte) {
                ']', ':' => {
                    const name = asm_source[name_start..i];

                    const index = name_map.get(name) orelse {
                        // we should validate the assembly in Sema; by now it is too late
                        return self.todo("unknown input or output name: '{s}'", .{name});
                    };
                    try rendered_template.print("{d}", .{index});
                    if (byte == ':') {
                        try rendered_template.append(':');
                        modifier_start = i + 1;
                        state = .modifier;
                    } else {
                        try rendered_template.append('}');
                        state = .start;
                    }
                },
                else => {},
            },
            .modifier => switch (byte) {
                ']' => {
                    try rendered_template.appendSlice(asm_source[modifier_start..i]);
                    try rendered_template.append('}');
                    state = .start;
                },
                else => {},
            },
        }
    }

    var attributes: Builder.FunctionAttributes.Wip = .{};
    defer attributes.deinit(&o.builder);
    for (llvm_param_attrs[0..param_count], 0..) |llvm_elem_ty, i| if (llvm_elem_ty != .none)
        try attributes.addParamAttr(i, .{ .elementtype = llvm_elem_ty }, &o.builder);

    const ret_llvm_ty = switch (return_count) {
        0 => .void,
        1 => llvm_ret_types[0],
        else => try o.builder.structType(.normal, llvm_ret_types),
    };
    const llvm_fn_ty = try o.builder.fnType(ret_llvm_ty, llvm_param_types[0..param_count], .normal);
    const call = try self.wip.callAsm(
        try attributes.finish(&o.builder),
        llvm_fn_ty,
        .{ .sideeffect = is_volatile },
        try o.builder.string(rendered_template.items),
        try o.builder.string(llvm_constraints.items),
        llvm_param_values[0..param_count],
        "",
    );

    var ret_val = call;
    llvm_ret_i = 0;
    for (outputs, 0..) |output, i| {
        if (llvm_ret_indirect[i]) continue;

        const output_value = if (return_count > 1)
            try self.wip.extractValue(call, &[_]u32{@intCast(llvm_ret_i)}, "")
        else
            call;

        if (output != .none) {
            const output_ptr = try self.resolveInst(output);
            const output_ptr_ty = self.typeOf(output);
            const alignment = output_ptr_ty.ptrAlignment(zcu).toLlvm();
            _ = try self.wip.store(
                if (output_ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal,
                output_value,
                output_ptr,
                alignment,
            );
        } else {
            ret_val = output_value;
        }
        llvm_ret_i += 1;
    }

    return ret_val;
}

fn airIsNonNull(
    self: *FuncGen,
    inst: Air.Inst.Index,
    operand_is_ptr: bool,
    cond: Builder.IntegerCondition,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const operand_ty = self.typeOf(un_op);
    const optional_ty = if (operand_is_ptr) operand_ty.childType(zcu) else operand_ty;
    const optional_llvm_ty = try o.lowerType(optional_ty);
    const payload_ty = optional_ty.optionalChild(zcu);

    const access_kind: Builder.MemoryAccessKind =
        if (operand_is_ptr and operand_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    if (operand_is_ptr) self.maybeMarkAllowZeroAccess(operand_ty.ptrInfo(zcu));

    if (optional_ty.optionalReprIsPayload(zcu)) {
        const loaded = if (operand_is_ptr)
            try self.wip.load(access_kind, optional_llvm_ty, operand, operand_ty.ptrAlignment(zcu).toLlvm(), "")
        else
            operand;
        if (payload_ty.isSlice(zcu)) {
            const slice_ptr = try self.wip.extractValue(loaded, &.{0}, "");
            const ptr_ty = try o.builder.ptrType(llvm.toLlvmAddressSpace(
                payload_ty.ptrAddressSpace(zcu),
                zcu.getTarget(),
            ));
            return self.wip.icmp(cond, slice_ptr, try o.builder.nullValue(ptr_ty), "");
        }
        return self.wip.icmp(cond, loaded, try o.builder.zeroInitValue(optional_llvm_ty), "");
    }

    comptime assert(optional_layout_version == 3);

    if (!payload_ty.hasRuntimeBits(zcu)) {
        const loaded = if (operand_is_ptr)
            try self.wip.load(access_kind, optional_llvm_ty, operand, operand_ty.ptrAlignment(zcu).toLlvm(), "")
        else
            operand;
        return self.wip.icmp(cond, loaded, try o.builder.intValue(.i8, 0), "");
    }

    return self.optCmpNull(cond, optional_ty, operand, access_kind);
}

fn airIsErr(
    self: *FuncGen,
    inst: Air.Inst.Index,
    cond: Builder.IntegerCondition,
    operand_is_ptr: bool,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const operand_ty = self.typeOf(un_op);
    const err_union_ty = if (operand_is_ptr) operand_ty.childType(zcu) else operand_ty;
    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    const error_type = try o.errorIntType();
    const zero = try o.builder.intValue(error_type, 0);

    const access_kind: Builder.MemoryAccessKind =
        if (operand_is_ptr and operand_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    if (err_union_ty.errorUnionSet(zcu).errorSetIsEmpty(zcu)) {
        const val: Builder.Constant = switch (cond) {
            .eq => .true, // 0 == 0
            .ne => .false, // 0 != 0
            else => unreachable,
        };
        return val.toValue();
    }

    if (operand_is_ptr) self.maybeMarkAllowZeroAccess(operand_ty.ptrInfo(zcu));

    if (!payload_ty.hasRuntimeBits(zcu)) {
        const loaded = if (operand_is_ptr)
            try self.wip.load(access_kind, try o.lowerType(err_union_ty), operand, operand_ty.ptrAlignment(zcu).toLlvm(), "")
        else
            operand;
        return self.wip.icmp(cond, loaded, zero, "");
    }
    assert(isByRef(err_union_ty, zcu)); // error unions with runtime bits are always by-ref

    const err_align = if (operand_is_ptr)
        operand_ty.ptrAlignment(zcu).minStrict(Type.anyerror.abiAlignment(zcu))
    else
        .none;
    const err_field_ptr = try self.ptraddConst(operand, codegen.errUnionErrorOffset(payload_ty, zcu));
    const loaded = try self.wip.load(access_kind, error_type, err_field_ptr, err_align.toLlvm(), "");
    return self.wip.icmp(cond, loaded, zero, "");
}

fn airOptionalPayloadPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    // If `Type.optionalReprIsPayload`, then the address should be the same. Otherwise, optional
    // layouts always put the payload at offset 0, so... the address should still be the same.
    return operand;
}

fn airOptionalPayloadPtrSet(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    comptime assert(optional_layout_version == 3);

    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const optional_ptr_ty = self.typeOf(ty_op.operand);
    const optional_ty = optional_ptr_ty.childType(zcu);
    const payload_ty = optional_ty.optionalChild(zcu);
    const non_null_bit = try o.builder.intValue(.i8, 1);

    const access_kind: Builder.MemoryAccessKind =
        if (optional_ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    if (!payload_ty.hasRuntimeBits(zcu)) {
        self.maybeMarkAllowZeroAccess(optional_ptr_ty.ptrInfo(zcu));

        // We have a pointer to a i8. We need to set it to 1 and then return the same pointer.
        // Default alignment store because align of the non null bit is 1 anyway.
        _ = try self.wip.store(access_kind, non_null_bit, operand, .default);
        return operand;
    }
    if (optional_ty.optionalReprIsPayload(zcu)) {
        // The payload and the optional are the same value.
        // Setting to non-null will be done when the payload is set.
        return operand;
    }

    // First set the non-null bit. It's always immediately after the payload (no padding) because it
    // has alignment 1.
    const non_null_ptr = try self.ptraddConst(operand, payload_ty.abiSize(zcu));

    self.maybeMarkAllowZeroAccess(optional_ptr_ty.ptrInfo(zcu));

    // Default alignment store because align of the non null bit is 1 anyway.
    _ = try self.wip.store(access_kind, non_null_bit, non_null_ptr, .default);

    // Then return the payload pointer (only if it's used).
    if (self.liveness.isUnused(inst)) return .none;

    return operand; // payload is at offset 0
}

fn airOptionalPayload(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const optional_ty = self.typeOf(ty_op.operand);
    const payload_ty = self.typeOfIndex(inst);
    if (!payload_ty.hasRuntimeBits(zcu)) return .none;

    if (optional_ty.optionalReprIsPayload(zcu)) {
        // Payload value is the same as the optional value.
        return operand;
    }

    return self.optPayloadHandle(operand, optional_ty, false);
}

fn airErrUnionPayload(self: *FuncGen, inst: Air.Inst.Index, operand_is_ptr: bool) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const err_union_ty = if (operand_is_ptr) operand_ty.childType(zcu) else operand_ty;
    const result_ty = self.typeOfIndex(inst);
    const payload_ty = if (operand_is_ptr) result_ty.childType(zcu) else result_ty;

    if (!payload_ty.hasRuntimeBits(zcu)) {
        return if (operand_is_ptr) operand else .none;
    }
    const payload_ptr = try self.ptraddConst(operand, codegen.errUnionPayloadOffset(payload_ty, zcu));
    if (operand_is_ptr) {
        return payload_ptr;
    }
    assert(isByRef(err_union_ty, zcu)); // error unions are by-ref unless the payload lacks runtime bits
    const payload_alignment = payload_ty.abiAlignment(zcu).toLlvm();
    if (isByRef(payload_ty, zcu)) {
        return self.loadByRef(payload_ptr, payload_ty, payload_alignment, .normal);
    } else {
        const payload_llvm_ty = try o.lowerType(payload_ty);
        return self.wip.load(.normal, payload_llvm_ty, payload_ptr, payload_alignment, "");
    }
}

fn airErrUnionErr(
    self: *FuncGen,
    inst: Air.Inst.Index,
    operand_is_ptr: bool,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const error_type = try o.errorIntType();
    const err_union_ty = if (operand_is_ptr) operand_ty.childType(zcu) else operand_ty;
    if (err_union_ty.errorUnionSet(zcu).errorSetIsEmpty(zcu)) {
        if (operand_is_ptr) {
            return operand;
        } else {
            return o.builder.intValue(error_type, 0);
        }
    }

    const access_kind: Builder.MemoryAccessKind =
        if (operand_is_ptr and operand_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    if (!payload_ty.hasRuntimeBits(zcu)) {
        if (!operand_is_ptr) return operand;

        self.maybeMarkAllowZeroAccess(operand_ty.ptrInfo(zcu));

        return self.wip.load(access_kind, error_type, operand, operand_ty.ptrAlignment(zcu).toLlvm(), "");
    }

    assert(isByRef(err_union_ty, zcu)); // error unions are by-ref unless the payload lacks runtime bits

    if (operand_is_ptr) self.maybeMarkAllowZeroAccess(operand_ty.ptrInfo(zcu));

    const err_align: InternPool.Alignment = a: {
        const err_abi_align = Type.anyerror.abiAlignment(zcu);
        if (!operand_is_ptr) break :a err_abi_align;
        break :a err_abi_align.minStrict(operand_ty.ptrAlignment(zcu));
    };

    const err_field_ptr = try self.ptraddConst(operand, codegen.errUnionErrorOffset(payload_ty, zcu));
    return self.wip.load(access_kind, error_type, err_field_ptr, err_align.toLlvm(), "");
}

fn airErrUnionPayloadPtrSet(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const err_union_ptr_ty = self.typeOf(ty_op.operand);
    const err_union_ty = err_union_ptr_ty.childType(zcu);
    const err_union_ptr_align = err_union_ptr_ty.ptrAlignment(zcu);

    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    const non_error_val = try o.builder.intValue(try o.errorIntType(), 0);

    const access_kind: Builder.MemoryAccessKind =
        if (err_union_ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    self.maybeMarkAllowZeroAccess(err_union_ptr_ty.ptrInfo(zcu));

    {
        const error_align = Type.anyerror.abiAlignment(zcu).minStrict(err_union_ptr_align).toLlvm();
        // First set the non-error value.
        const error_ptr = try self.ptraddConst(operand, codegen.errUnionErrorOffset(payload_ty, zcu));
        _ = try self.wip.store(access_kind, non_error_val, error_ptr, error_align);
    }

    // Then return the payload pointer (only if it is used).
    if (self.liveness.isUnused(inst)) return .none;
    return self.ptraddConst(operand, codegen.errUnionPayloadOffset(payload_ty, zcu));
}

fn airErrReturnTrace(self: *FuncGen, _: Air.Inst.Index) Allocator.Error!Builder.Value {
    assert(self.err_ret_trace != .none);
    return self.err_ret_trace;
}

fn airSetErrReturnTrace(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    self.err_ret_trace = try self.resolveInst(un_op);
    return .none;
}

fn airSaveErrReturnTraceIndex(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;

    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const struct_ty = ty_pl.ty.toType();
    const field_index = ty_pl.payload;

    assert(self.err_ret_trace != .none);

    const field_ty = struct_ty.fieldType(field_index, zcu);
    const field_offset = struct_ty.structFieldOffset(field_index, zcu);
    const field_align = switch (field_offset) {
        0 => struct_ty.abiAlignment(zcu),
        else => struct_ty.abiAlignment(zcu).minStrict(.fromLog2Units(@ctz(field_offset))),
    };

    const field_ptr = try self.ptraddConst(self.err_ret_trace, field_offset);
    return self.load(field_ptr, field_ty, field_align.toLlvm(), .normal);
}

/// As an optimization, we want to avoid unnecessary copies of
/// error union/optional types when returning from a function.
/// Here, we scan forward in the current block, looking to see
/// if the next instruction is a return (ignoring debug instructions).
///
/// The first instruction of `body_tail` is a wrap instruction.
fn isNextRet(
    self: *FuncGen,
    body_tail: []const Air.Inst.Index,
) bool {
    const air_tags = self.air.instructions.items(.tag);
    for (body_tail[1..]) |body_inst| {
        switch (air_tags[@intFromEnum(body_inst)]) {
            .ret => return true,
            .dbg_stmt => continue,
            else => return false,
        }
    }
    // The only way to get here is to hit the end of a loop instruction
    // (implicit repeat).
    return false;
}

fn airWrapOptional(self: *FuncGen, body_tail: []const Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const inst = body_tail[0];
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const payload_ty = self.typeOf(ty_op.operand);
    const non_null_bit = try o.builder.intValue(.i8, 1);
    comptime assert(optional_layout_version == 3);
    assert(payload_ty.hasRuntimeBits(zcu));
    const operand = try self.resolveInst(ty_op.operand);
    const optional_ty = self.typeOfIndex(inst);
    if (optional_ty.optionalReprIsPayload(zcu)) return operand;
    assert(isByRef(optional_ty, zcu)); // optionals with runtime bits are by-ref unless `optionalReprIsPayload`
    const llvm_optional_ty = try o.lowerType(optional_ty);
    const optional_ptr = if (self.isNextRet(body_tail))
        self.ret_ptr
    else brk: {
        const alignment = optional_ty.abiAlignment(zcu).toLlvm();
        const optional_ptr = try self.buildAlloca(llvm_optional_ty, alignment);
        break :brk optional_ptr;
    };

    const payload_ptr = optional_ptr; // payload always at offset 0
    try self.store(
        payload_ptr,
        .none,
        operand,
        payload_ty,
    );
    // Non-null bit immediately after payload (no padding because the bit has alignment 1).
    const non_null_ptr = try self.ptraddConst(optional_ptr, payload_ty.abiSize(zcu));
    _ = try self.wip.store(.normal, non_null_bit, non_null_ptr, .default);
    return optional_ptr;
}

fn airWrapErrUnionPayload(self: *FuncGen, body_tail: []const Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const inst = body_tail[0];
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const err_un_ty = self.typeOfIndex(inst);
    const operand = try self.resolveInst(ty_op.operand);
    const payload_ty = self.typeOf(ty_op.operand);
    assert(payload_ty.hasRuntimeBits(zcu));
    assert(isByRef(err_un_ty, zcu)); // error unions with runtime bits are always by-ref
    const ok_err_code = try o.builder.intValue(try o.errorIntType(), 0);
    const err_un_llvm_ty = try o.lowerType(err_un_ty);

    const result_ptr = if (self.isNextRet(body_tail))
        self.ret_ptr
    else brk: {
        const alignment = err_un_ty.abiAlignment(o.zcu).toLlvm();
        const result_ptr = try self.buildAlloca(err_un_llvm_ty, alignment);
        break :brk result_ptr;
    };

    const err_ptr = try self.ptraddConst(result_ptr, codegen.errUnionErrorOffset(payload_ty, zcu));
    const error_alignment = Type.anyerror.abiAlignment(o.zcu).toLlvm();
    _ = try self.wip.store(.normal, ok_err_code, err_ptr, error_alignment);
    const payload_ptr = try self.ptraddConst(result_ptr, codegen.errUnionPayloadOffset(payload_ty, zcu));
    try self.store(
        payload_ptr,
        .none,
        operand,
        payload_ty,
    );
    return result_ptr;
}

fn airWrapErrUnionErr(self: *FuncGen, body_tail: []const Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const inst = body_tail[0];
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const err_un_ty = self.typeOfIndex(inst);
    const payload_ty = err_un_ty.errorUnionPayload(zcu);
    const operand = try self.resolveInst(ty_op.operand);
    if (!payload_ty.hasRuntimeBits(zcu)) return operand;
    assert(isByRef(err_un_ty, zcu)); // error unions with runtime bits are always by-ref
    const err_un_llvm_ty = try o.lowerType(err_un_ty);

    const result_ptr = if (self.isNextRet(body_tail))
        self.ret_ptr
    else brk: {
        const alignment = err_un_ty.abiAlignment(zcu).toLlvm();
        const result_ptr = try self.buildAlloca(err_un_llvm_ty, alignment);
        break :brk result_ptr;
    };

    const err_ptr = try self.ptraddConst(result_ptr, codegen.errUnionErrorOffset(payload_ty, zcu));
    const error_alignment = Type.anyerror.abiAlignment(zcu).toLlvm();
    _ = try self.wip.store(.normal, operand, err_ptr, error_alignment);
    const payload_ptr = try self.ptraddConst(result_ptr, codegen.errUnionPayloadOffset(payload_ty, zcu));
    // TODO store undef to payload_ptr
    _ = payload_ptr;
    return result_ptr;
}

fn airWasmMemorySize(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const index = pl_op.payload;
    const llvm_usize = try o.lowerType(.usize);
    return self.wip.callIntrinsic(.normal, .none, .@"wasm.memory.size", &.{llvm_usize}, &.{
        try o.builder.intValue(.i32, index),
    }, "");
}

fn airWasmMemoryGrow(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const index = pl_op.payload;
    const llvm_isize = try o.lowerType(.isize);
    return self.wip.callIntrinsic(.normal, .none, .@"wasm.memory.grow", &.{llvm_isize}, &.{
        try o.builder.intValue(.i32, index), try self.resolveInst(pl_op.operand),
    }, "");
}

fn airRuntimeNavPtr(fg: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = fg.object;
    const ty_nav = fg.air.instructions.items(.data)[@intFromEnum(inst)].ty_nav;
    const llvm_ptr = try o.lowerNavRef(ty_nav.nav);
    return llvm_ptr.toValue();
}

fn airMin(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isAnyFloat()) return self.buildFloatOp(.fmin, .normal, inst_ty, 2, .{ lhs, rhs });
    return self.wip.callIntrinsic(
        .normal,
        .none,
        if (scalar_ty.isSignedInt(zcu)) .smin else .umin,
        &.{try o.lowerType(inst_ty)},
        &.{ lhs, rhs },
        "",
    );
}

fn airMax(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isAnyFloat()) return self.buildFloatOp(.fmax, .normal, inst_ty, 2, .{ lhs, rhs });
    return self.wip.callIntrinsic(
        .normal,
        .none,
        if (scalar_ty.isSignedInt(zcu)) .smax else .umax,
        &.{try o.lowerType(inst_ty)},
        &.{ lhs, rhs },
        "",
    );
}

fn airSlice(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = self.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr = try self.resolveInst(bin_op.lhs);
    const len = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    return self.wip.buildAggregate(try self.object.lowerType(inst_ty), &.{ ptr, len }, "");
}

fn airAdd(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isAnyFloat()) return self.buildFloatOp(.add, fast, inst_ty, 2, .{ lhs, rhs });
    return self.wip.bin(if (scalar_ty.isSignedInt(zcu)) .@"add nsw" else .@"add nuw", lhs, rhs, "");
}

fn airSafeArithmetic(
    fg: *FuncGen,
    inst: Air.Inst.Index,
    signed_intrinsic: Builder.Intrinsic,
    unsigned_intrinsic: Builder.Intrinsic,
) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;

    const bin_op = fg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try fg.resolveInst(bin_op.lhs);
    const rhs = try fg.resolveInst(bin_op.rhs);
    const inst_ty = fg.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    const intrinsic = if (scalar_ty.isSignedInt(zcu)) signed_intrinsic else unsigned_intrinsic;
    const llvm_inst_ty = try o.lowerType(inst_ty);
    const results =
        try fg.wip.callIntrinsic(.normal, .none, intrinsic, &.{llvm_inst_ty}, &.{ lhs, rhs }, "");

    const overflow_bits = try fg.wip.extractValue(results, &.{1}, "");
    const overflow_bits_ty = overflow_bits.typeOfWip(&fg.wip);
    const overflow_bit = switch (inst_ty.zigTypeTag(zcu)) {
        .vector => try fg.wip.callIntrinsic(
            .normal,
            .none,
            .@"vector.reduce.or",
            &.{overflow_bits_ty},
            &.{overflow_bits},
            "",
        ),
        else => overflow_bits,
    };

    const fail_block = try fg.wip.block(1, "OverflowFail");
    const ok_block = try fg.wip.block(1, "OverflowOk");
    _ = try fg.wip.brCond(overflow_bit, fail_block, ok_block, .none);

    fg.wip.cursor = .{ .block = fail_block };
    try fg.buildSimplePanic(.integer_overflow);

    fg.wip.cursor = .{ .block = ok_block };
    return fg.wip.extractValue(results, &.{0}, "");
}

fn airAddWrap(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    return self.wip.bin(.add, lhs, rhs, "");
}

fn airAddSat(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);
    assert(scalar_ty.zigTypeTag(zcu) == .int);
    return self.wip.callIntrinsic(
        .normal,
        .none,
        if (scalar_ty.isSignedInt(zcu)) .@"sadd.sat" else .@"uadd.sat",
        &.{try o.lowerType(inst_ty)},
        &.{ lhs, rhs },
        "",
    );
}

fn airSub(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isAnyFloat()) return self.buildFloatOp(.sub, fast, inst_ty, 2, .{ lhs, rhs });
    return self.wip.bin(if (scalar_ty.isSignedInt(zcu)) .@"sub nsw" else .@"sub nuw", lhs, rhs, "");
}

fn airSubWrap(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    return self.wip.bin(.sub, lhs, rhs, "");
}

fn airSubSat(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);
    assert(scalar_ty.zigTypeTag(zcu) == .int);
    return self.wip.callIntrinsic(
        .normal,
        .none,
        if (scalar_ty.isSignedInt(zcu)) .@"ssub.sat" else .@"usub.sat",
        &.{try o.lowerType(inst_ty)},
        &.{ lhs, rhs },
        "",
    );
}

fn airMul(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isAnyFloat()) return self.buildFloatOp(.mul, fast, inst_ty, 2, .{ lhs, rhs });
    return self.wip.bin(if (scalar_ty.isSignedInt(zcu)) .@"mul nsw" else .@"mul nuw", lhs, rhs, "");
}

fn airMulWrap(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    return self.wip.bin(.mul, lhs, rhs, "");
}

fn airMulSat(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);
    assert(scalar_ty.zigTypeTag(zcu) == .int);
    return self.wip.callIntrinsic(
        .normal,
        .none,
        if (scalar_ty.isSignedInt(zcu)) .@"smul.fix.sat" else .@"umul.fix.sat",
        &.{try o.lowerType(inst_ty)},
        &.{ lhs, rhs, .@"0" },
        "",
    );
}

fn airDivFloat(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);

    return self.buildFloatOp(.div, fast, inst_ty, 2, .{ lhs, rhs });
}

fn airDivTrunc(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isRuntimeFloat()) {
        const result = try self.buildFloatOp(.div, fast, inst_ty, 2, .{ lhs, rhs });
        return self.buildFloatOp(.trunc, fast, inst_ty, 1, .{result});
    }
    return self.wip.bin(if (scalar_ty.isSignedInt(zcu)) .sdiv else .udiv, lhs, rhs, "");
}

fn airDivFloor(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isRuntimeFloat()) {
        const result = try self.buildFloatOp(.div, fast, inst_ty, 2, .{ lhs, rhs });
        return self.buildFloatOp(.floor, fast, inst_ty, 1, .{result});
    }
    if (scalar_ty.isSignedInt(zcu)) {
        const scalar_llvm_ty = try o.lowerType(scalar_ty);
        const inst_llvm_ty = try o.lowerType(inst_ty);

        const ExpectedContents = [std.math.big.int.calcTwosCompLimbCount(256)]std.math.big.Limb;
        var stack align(@max(
            @alignOf(std.heap.StackFallbackAllocator(0)),
            @alignOf(ExpectedContents),
        )) = std.heap.stackFallback(@sizeOf(ExpectedContents), self.gpa);
        const allocator = stack.get();

        const scalar_bits = scalar_ty.intInfo(zcu).bits;
        var smin_big_int: std.math.big.int.Mutable = .{
            .limbs = try allocator.alloc(
                std.math.big.Limb,
                std.math.big.int.calcTwosCompLimbCount(scalar_bits),
            ),
            .len = undefined,
            .positive = undefined,
        };
        defer allocator.free(smin_big_int.limbs);
        smin_big_int.setTwosCompIntLimit(.min, .signed, scalar_bits);
        const smin = try o.builder.splatValue(inst_llvm_ty, try o.builder.bigIntConst(
            scalar_llvm_ty,
            smin_big_int.toConst(),
        ));

        const div = try self.wip.bin(.sdiv, lhs, rhs, "divFloor.div");
        const rem = try self.wip.bin(.srem, lhs, rhs, "divFloor.rem");
        const rhs_sign = try self.wip.bin(.@"and", rhs, smin, "divFloor.rhs_sign");
        const rem_xor_rhs_sign = try self.wip.bin(.xor, rem, rhs_sign, "divFloor.rem_xor_rhs_sign");
        const need_correction = try self.wip.icmp(.ugt, rem_xor_rhs_sign, smin, "divFloor.need_correction");
        const correction = try self.wip.cast(.sext, need_correction, inst_llvm_ty, "divFloor.correction");
        return self.wip.bin(.@"add nsw", div, correction, "divFloor");
    }
    return self.wip.bin(.udiv, lhs, rhs, "");
}

fn airDivExact(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isRuntimeFloat()) return self.buildFloatOp(.div, fast, inst_ty, 2, .{ lhs, rhs });
    return self.wip.bin(
        if (scalar_ty.isSignedInt(zcu)) .@"sdiv exact" else .@"udiv exact",
        lhs,
        rhs,
        "",
    );
}

fn airRem(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isRuntimeFloat())
        return self.buildFloatOp(.fmod, fast, inst_ty, 2, .{ lhs, rhs });
    return self.wip.bin(if (scalar_ty.isSignedInt(zcu))
        .srem
    else
        .urem, lhs, rhs, "");
}

fn airMod(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    const inst_ty = self.typeOfIndex(inst);
    const inst_llvm_ty = try o.lowerType(inst_ty);
    const scalar_ty = inst_ty.scalarType(zcu);

    if (scalar_ty.isRuntimeFloat()) {
        const a = try self.buildFloatOp(.fmod, fast, inst_ty, 2, .{ lhs, rhs });
        const b = try self.buildFloatOp(.add, fast, inst_ty, 2, .{ a, rhs });
        const c = try self.buildFloatOp(.fmod, fast, inst_ty, 2, .{ b, rhs });
        const zero = try o.builder.zeroInitValue(inst_llvm_ty);
        const ltz = try self.buildFloatCmp(fast, .lt, inst_ty, .{ lhs, zero });
        return self.wip.select(fast, ltz, c, a, "");
    }
    if (scalar_ty.isSignedInt(zcu)) {
        const ExpectedContents = [std.math.big.int.calcTwosCompLimbCount(256)]std.math.big.Limb;
        var stack align(@max(
            @alignOf(std.heap.StackFallbackAllocator(0)),
            @alignOf(ExpectedContents),
        )) = std.heap.stackFallback(@sizeOf(ExpectedContents), self.gpa);
        const allocator = stack.get();

        const scalar_bits = scalar_ty.intInfo(zcu).bits;
        var smin_big_int: std.math.big.int.Mutable = .{
            .limbs = try allocator.alloc(
                std.math.big.Limb,
                std.math.big.int.calcTwosCompLimbCount(scalar_bits),
            ),
            .len = undefined,
            .positive = undefined,
        };
        defer allocator.free(smin_big_int.limbs);
        smin_big_int.setTwosCompIntLimit(.min, .signed, scalar_bits);
        const smin = try o.builder.splatValue(inst_llvm_ty, try o.builder.bigIntConst(
            try o.lowerType(scalar_ty),
            smin_big_int.toConst(),
        ));

        const rem = try self.wip.bin(.srem, lhs, rhs, "mod.rem");
        const rhs_sign = try self.wip.bin(.@"and", rhs, smin, "mod.rhs_sign");
        const rem_xor_rhs_sign = try self.wip.bin(.xor, rem, rhs_sign, "mod.rem_xor_rhs_sign");
        const need_correction = try self.wip.icmp(.ugt, rem_xor_rhs_sign, smin, "mod.need_correction");
        const zero = try o.builder.zeroInitValue(inst_llvm_ty);
        const correction = try self.wip.select(.normal, need_correction, rhs, zero, "mod.correction");
        return self.wip.bin(.@"add nsw", correction, rem, "mod");
    }
    return self.wip.bin(.urem, lhs, rhs, "");
}

fn airPtrAdd(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = self.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr_or_slice = try self.resolveInst(bin_op.lhs);
    const index = try self.resolveInst(bin_op.rhs);
    const ptr_ty = self.typeOf(bin_op.lhs);
    const elem_ty = ptr_ty.indexableElem(zcu);
    const ptr = switch (ptr_ty.ptrSize(zcu)) {
        .one, .many, .c => ptr_or_slice,
        .slice => try self.wip.extractValue(ptr_or_slice, &.{0}, ""),
    };
    return self.ptraddScaled(ptr, index, elem_ty.abiSize(zcu));
}

fn airPtrSub(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = self.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr_or_slice = try self.resolveInst(bin_op.lhs);
    const llvm_usize_ty = try o.lowerType(.usize);
    const ptr_ty = self.typeOf(bin_op.lhs);
    const elem_ty = ptr_ty.indexableElem(zcu);
    const ptr = switch (ptr_ty.ptrSize(zcu)) {
        .one, .many, .c => ptr_or_slice,
        .slice => try self.wip.extractValue(ptr_or_slice, &.{0}, ""),
    };
    const scale_val = try o.builder.intValue(llvm_usize_ty, -@as(i65, elem_ty.abiSize(zcu)));
    const positive_index = try self.resolveInst(bin_op.rhs);
    const negative_offset = try self.wip.bin(.@"mul nsw", positive_index, scale_val, "");
    return self.wip.gep(.inbounds, .i8, ptr, &.{negative_offset}, "");
}

fn airOverflow(
    self: *FuncGen,
    inst: Air.Inst.Index,
    signed_intrinsic: Builder.Intrinsic,
    unsigned_intrinsic: Builder.Intrinsic,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = self.air.extraData(Air.Bin, ty_pl.payload).data;

    const lhs = try self.resolveInst(extra.lhs);
    const rhs = try self.resolveInst(extra.rhs);

    const lhs_ty = self.typeOf(extra.lhs);
    const scalar_ty = lhs_ty.scalarType(zcu);
    const inst_ty = self.typeOfIndex(inst);
    assert(isByRef(inst_ty, zcu)); // auto structs are by-ref

    const intrinsic = if (scalar_ty.isSignedInt(zcu)) signed_intrinsic else unsigned_intrinsic;
    const llvm_inst_ty = try o.lowerType(inst_ty);
    const llvm_lhs_ty = try o.lowerType(lhs_ty);
    const results =
        try self.wip.callIntrinsic(.normal, .none, intrinsic, &.{llvm_lhs_ty}, &.{ lhs, rhs }, "");

    const result_val = try self.wip.extractValue(results, &.{0}, "");
    const overflow_bit = try self.wip.extractValue(results, &.{1}, "");

    const result_alignment = inst_ty.abiAlignment(zcu).toLlvm();
    const alloca_inst = try self.buildAlloca(llvm_inst_ty, result_alignment);

    {
        // Store to 'result: IntType' field
        const field_ptr = try self.ptraddConst(alloca_inst, inst_ty.structFieldOffset(0, zcu));
        _ = try self.wip.store(.normal, result_val, field_ptr, lhs_ty.abiAlignment(zcu).toLlvm());
    }

    {
        // Store to 'overflow: u1' field
        const field_ptr = try self.ptraddConst(alloca_inst, inst_ty.structFieldOffset(1, zcu));
        _ = try self.wip.store(.normal, overflow_bit, field_ptr, comptime .fromByteUnits(1));
    }

    return alloca_inst;
}

fn buildElementwiseCall(
    self: *FuncGen,
    llvm_fn: Builder.Function.Index,
    args_vectors: []const Builder.Value,
    result_vector: Builder.Value,
    vector_len: usize,
) Allocator.Error!Builder.Value {
    const o = self.object;
    assert(args_vectors.len <= 3);

    var i: usize = 0;
    var result = result_vector;
    while (i < vector_len) : (i += 1) {
        const index_i32 = try o.builder.intValue(.i32, i);

        var args: [3]Builder.Value = undefined;
        for (args[0..args_vectors.len], args_vectors) |*arg_elem, arg_vector| {
            arg_elem.* = try self.wip.extractElement(arg_vector, index_i32, "");
        }
        const result_elem = try self.wip.call(
            .normal,
            .ccc,
            .none,
            llvm_fn.typeOf(&o.builder),
            llvm_fn.toValue(&o.builder),
            args[0..args_vectors.len],
            "",
        );
        result = try self.wip.insertElement(result, result_elem, index_i32, "");
    }
    return result;
}

/// Creates a floating point comparison by lowering to the appropriate
/// hardware instruction or softfloat routine for the target
fn buildFloatCmp(
    self: *FuncGen,
    fast: Builder.FastMathKind,
    pred: math.CompareOperator,
    ty: Type,
    params: [2]Builder.Value,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const target = zcu.getTarget();
    const scalar_ty = ty.scalarType(zcu);
    const scalar_llvm_ty = try o.lowerType(scalar_ty);

    if (intrinsicsAllowed(scalar_ty, target)) {
        const cond: Builder.FloatCondition = switch (pred) {
            .eq => .oeq,
            .neq => .une,
            .lt => .olt,
            .lte => .ole,
            .gt => .ogt,
            .gte => .oge,
        };
        return self.wip.fcmp(fast, cond, params[0], params[1], "");
    }

    const float_bits = scalar_ty.floatBits(target);
    const compiler_rt_float_abbrev = compilerRtFloatAbbrev(float_bits);
    const fn_base_name = switch (pred) {
        .neq => "ne",
        .eq => "eq",
        .lt => "lt",
        .lte => "le",
        .gt => "gt",
        .gte => "ge",
    };
    const fn_name = try o.builder.strtabStringFmt("__{s}{s}f2", .{ fn_base_name, compiler_rt_float_abbrev });

    const libc_fn = try o.getLibcFunction(fn_name, &.{ scalar_llvm_ty, scalar_llvm_ty }, .i32);

    const int_cond: Builder.IntegerCondition = switch (pred) {
        .eq => .eq,
        .neq => .ne,
        .lt => .slt,
        .lte => .sle,
        .gt => .sgt,
        .gte => .sge,
    };

    if (ty.zigTypeTag(zcu) == .vector) {
        const vec_len = ty.vectorLen(zcu);
        const vector_result_ty = try o.builder.vectorType(.normal, vec_len, .i32);

        const init = try o.builder.poisonValue(vector_result_ty);
        const result = try self.buildElementwiseCall(libc_fn, &params, init, vec_len);

        const zero_vector = try o.builder.splatValue(vector_result_ty, .@"0");
        return self.wip.icmp(int_cond, result, zero_vector, "");
    }

    const result = try self.wip.call(
        .normal,
        .ccc,
        .none,
        libc_fn.typeOf(&o.builder),
        libc_fn.toValue(&o.builder),
        &params,
        "",
    );
    return self.wip.icmp(int_cond, result, .@"0", "");
}

const FloatOp = enum {
    add,
    ceil,
    cos,
    div,
    exp,
    exp2,
    fabs,
    floor,
    fma,
    fmax,
    fmin,
    fmod,
    log,
    log10,
    log2,
    mul,
    neg,
    round,
    sin,
    sqrt,
    sub,
    tan,
    trunc,
};

const FloatOpStrat = union(enum) {
    intrinsic: []const u8,
    libc: Builder.String,
};

/// Creates a floating point operation (add, sub, fma, sqrt, exp, etc.)
/// by lowering to the appropriate hardware instruction or softfloat
/// routine for the target
fn buildFloatOp(
    self: *FuncGen,
    comptime op: FloatOp,
    fast: Builder.FastMathKind,
    ty: Type,
    comptime params_len: usize,
    params: [params_len]Builder.Value,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const target = zcu.getTarget();
    const scalar_ty = ty.scalarType(zcu);
    const llvm_ty = try o.lowerType(ty);

    if (op != .tan and intrinsicsAllowed(scalar_ty, target)) switch (op) {
        // Some operations are dedicated LLVM instructions, not available as intrinsics
        .neg => return self.wip.un(.fneg, params[0], ""),
        .add, .sub, .mul, .div, .fmod => return self.wip.bin(switch (fast) {
            .normal => switch (op) {
                .add => .fadd,
                .sub => .fsub,
                .mul => .fmul,
                .div => .fdiv,
                .fmod => .frem,
                else => unreachable,
            },
            .fast => switch (op) {
                .add => .@"fadd fast",
                .sub => .@"fsub fast",
                .mul => .@"fmul fast",
                .div => .@"fdiv fast",
                .fmod => .@"frem fast",
                else => unreachable,
            },
        }, params[0], params[1], ""),
        .fmax,
        .fmin,
        .ceil,
        .cos,
        .exp,
        .exp2,
        .fabs,
        .floor,
        .log,
        .log10,
        .log2,
        .round,
        .sin,
        .sqrt,
        .trunc,
        .fma,
        => return self.wip.callIntrinsic(fast, .none, switch (op) {
            .fmax => .maxnum,
            .fmin => .minnum,
            .ceil => .ceil,
            .cos => .cos,
            .exp => .exp,
            .exp2 => .exp2,
            .fabs => .fabs,
            .floor => .floor,
            .log => .log,
            .log10 => .log10,
            .log2 => .log2,
            .round => .round,
            .sin => .sin,
            .sqrt => .sqrt,
            .trunc => .trunc,
            .fma => .fma,
            else => unreachable,
        }, &.{llvm_ty}, &params, ""),
        .tan => unreachable,
    };

    const float_bits = scalar_ty.floatBits(target);
    const fn_name = switch (op) {
        .neg => {
            // In this case we can generate a softfloat negation by XORing the
            // bits with a constant.
            const int_ty = try o.builder.intType(@intCast(float_bits));
            const cast_ty = switch (ty.zigTypeTag(zcu)) {
                .vector => try o.builder.vectorType(.normal, ty.vectorLen(zcu), int_ty),
                else => int_ty,
            };
            const sign_mask = try o.builder.splatValue(
                cast_ty,
                try o.builder.intConst(int_ty, @as(u128, 1) << @intCast(float_bits - 1)),
            );
            const bitcasted_operand = try self.wip.cast(.bitcast, params[0], cast_ty, "");
            const result = try self.wip.bin(.xor, bitcasted_operand, sign_mask, "");
            return self.wip.cast(.bitcast, result, llvm_ty, "");
        },
        .add, .sub, .div, .mul => try o.builder.strtabStringFmt("__{s}{s}f3", .{
            @tagName(op), compilerRtFloatAbbrev(float_bits),
        }),
        .ceil,
        .cos,
        .exp,
        .exp2,
        .fabs,
        .floor,
        .fma,
        .fmax,
        .fmin,
        .fmod,
        .log,
        .log10,
        .log2,
        .round,
        .sin,
        .sqrt,
        .tan,
        .trunc,
        => try o.builder.strtabStringFmt("{s}{s}{s}", .{
            libcFloatPrefix(float_bits), @tagName(op), libcFloatSuffix(float_bits),
        }),
    };

    const scalar_llvm_ty = try o.lowerType(scalar_ty);
    const libc_fn = try o.getLibcFunction(
        fn_name,
        ([1]Builder.Type{scalar_llvm_ty} ** 3)[0..params.len],
        scalar_llvm_ty,
    );
    if (ty.zigTypeTag(zcu) == .vector) {
        const result = try o.builder.poisonValue(llvm_ty);
        return self.buildElementwiseCall(libc_fn, &params, result, ty.vectorLen(zcu));
    }

    return self.wip.call(
        fast.toCallKind(),
        .ccc,
        .none,
        libc_fn.typeOf(&o.builder),
        libc_fn.toValue(&o.builder),
        &params,
        "",
    );
}

fn airMulAdd(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = self.air.extraData(Air.Bin, pl_op.payload).data;

    const mulend1 = try self.resolveInst(extra.lhs);
    const mulend2 = try self.resolveInst(extra.rhs);
    const addend = try self.resolveInst(pl_op.operand);

    const ty = self.typeOfIndex(inst);
    return self.buildFloatOp(.fma, .normal, ty, 3, .{ mulend1, mulend2, addend });
}

fn airShlWithOverflow(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = self.air.extraData(Air.Bin, ty_pl.payload).data;

    const lhs = try self.resolveInst(extra.lhs);
    const rhs = try self.resolveInst(extra.rhs);

    const lhs_ty = self.typeOf(extra.lhs);
    if (lhs_ty.isVector(zcu) and !self.typeOf(extra.rhs).isVector(zcu)) {
        // `Sema` does not currently emit this pattern---instead it is specific to `Air.Legalize`
        // features which we do not use. Therefore this branch is currently impossible.
        unreachable;
    }

    const lhs_scalar_ty = lhs_ty.scalarType(zcu);

    const dest_ty = self.typeOfIndex(inst);
    assert(isByRef(dest_ty, zcu)); // auto structs are by-ref
    const llvm_dest_ty = try o.lowerType(dest_ty);

    const casted_rhs = try self.wip.conv(.unsigned, rhs, try o.lowerType(lhs_ty), "");

    const result = try self.wip.bin(.shl, lhs, casted_rhs, "");
    const reconstructed = try self.wip.bin(if (lhs_scalar_ty.isSignedInt(zcu))
        .ashr
    else
        .lshr, result, casted_rhs, "");

    const overflow_bit = try self.wip.icmp(.ne, lhs, reconstructed, "");

    const result_alignment = dest_ty.abiAlignment(zcu).toLlvm();
    const alloca_inst = try self.buildAlloca(llvm_dest_ty, result_alignment);

    {
        // Store to 'result: IntType' field
        const field_ptr = try self.ptraddConst(alloca_inst, dest_ty.structFieldOffset(0, zcu));
        _ = try self.wip.store(.normal, result, field_ptr, lhs_ty.abiAlignment(zcu).toLlvm());
    }

    {
        // Store to 'overflow: u1' field
        const field_ptr = try self.ptraddConst(alloca_inst, dest_ty.structFieldOffset(1, zcu));
        _ = try self.wip.store(.normal, overflow_bit, field_ptr, comptime .fromByteUnits(1));
    }

    return alloca_inst;
}

fn airAnd(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    return self.wip.bin(.@"and", lhs, rhs, "");
}

fn airOr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    return self.wip.bin(.@"or", lhs, rhs, "");
}

fn airXor(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);
    return self.wip.bin(.xor, lhs, rhs, "");
}

fn airShlExact(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    const lhs_ty = self.typeOf(bin_op.lhs);
    if (lhs_ty.isVector(zcu) and !self.typeOf(bin_op.rhs).isVector(zcu)) {
        // `Sema` does not currently emit this pattern---instead it is specific to `Air.Legalize`
        // features which we do not use. Therefore this branch is currently impossible.
        unreachable;
    }
    const lhs_scalar_ty = lhs_ty.scalarType(zcu);

    const casted_rhs = try self.wip.conv(.unsigned, rhs, try o.lowerType(lhs_ty), "");
    return self.wip.bin(if (lhs_scalar_ty.isSignedInt(zcu))
        .@"shl nsw"
    else
        .@"shl nuw", lhs, casted_rhs, "");
}

fn airShl(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    const lhs_ty = self.typeOf(bin_op.lhs);
    if (lhs_ty.isVector(zcu) and !self.typeOf(bin_op.rhs).isVector(zcu)) {
        // `Sema` does not currently emit this pattern---instead it is specific to `Air.Legalize`
        // features which we do not use. Therefore this branch is currently impossible.
        unreachable;
    }
    const casted_rhs = try self.wip.conv(.unsigned, rhs, try o.lowerType(lhs_ty), "");
    return self.wip.bin(.shl, lhs, casted_rhs, "");
}

fn airShlSat(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    const lhs_ty = self.typeOf(bin_op.lhs);
    const lhs_info = lhs_ty.intInfo(zcu);
    const llvm_lhs_ty = try o.lowerType(lhs_ty);
    const llvm_lhs_scalar_ty = try o.lowerType(lhs_ty.scalarType(zcu));

    const rhs_ty = self.typeOf(bin_op.rhs);
    if (lhs_ty.isVector(zcu) and !rhs_ty.isVector(zcu)) {
        // `Sema` does not currently emit this pattern---instead it is specific to `Air.Legalize`
        // features which we do not use. Therefore this branch is currently impossible.
        unreachable;
    }
    const rhs_info = rhs_ty.intInfo(zcu);
    assert(rhs_info.signedness == .unsigned);
    const llvm_rhs_ty = try o.lowerType(rhs_ty);
    const llvm_rhs_scalar_ty = try o.lowerType(rhs_ty.scalarType(zcu));

    const result = try self.wip.callIntrinsic(
        .normal,
        .none,
        switch (lhs_info.signedness) {
            .signed => .@"sshl.sat",
            .unsigned => .@"ushl.sat",
        },
        &.{llvm_lhs_ty},
        &.{ lhs, try self.wip.conv(.unsigned, rhs, llvm_lhs_ty, "") },
        "",
    );

    // LLVM langref says "If b is (statically or dynamically) equal to or
    // larger than the integer bit width of the arguments, the result is a
    // poison value."
    // However Zig semantics says that saturating shift left can never produce
    // undefined; instead it saturates.
    if (rhs_info.bits <= math.log2_int(u16, lhs_info.bits)) return result;
    const bits = try o.builder.splatValue(
        llvm_rhs_ty,
        try o.builder.intConst(llvm_rhs_scalar_ty, lhs_info.bits),
    );
    const in_range = try self.wip.icmp(.ult, rhs, bits, "");
    const lhs_sat = lhs_sat: switch (lhs_info.signedness) {
        .signed => {
            const zero = try o.builder.splatValue(
                llvm_lhs_ty,
                try o.builder.intConst(llvm_lhs_scalar_ty, 0),
            );
            const smin = try o.builder.splatValue(
                llvm_lhs_ty,
                try minIntConst(&o.builder, lhs_ty, llvm_lhs_ty, zcu),
            );
            const smax = try o.builder.splatValue(
                llvm_lhs_ty,
                try maxIntConst(&o.builder, lhs_ty, llvm_lhs_ty, zcu),
            );
            const lhs_lt_zero = try self.wip.icmp(.slt, lhs, zero, "");
            const slimit = try self.wip.select(.normal, lhs_lt_zero, smin, smax, "");
            const lhs_eq_zero = try self.wip.icmp(.eq, lhs, zero, "");
            break :lhs_sat try self.wip.select(.normal, lhs_eq_zero, zero, slimit, "");
        },
        .unsigned => {
            const zero = try o.builder.splatValue(
                llvm_lhs_ty,
                try o.builder.intConst(llvm_lhs_scalar_ty, 0),
            );
            const umax = try o.builder.splatValue(
                llvm_lhs_ty,
                try o.builder.intConst(llvm_lhs_scalar_ty, -1),
            );
            const lhs_eq_zero = try self.wip.icmp(.eq, lhs, zero, "");
            break :lhs_sat try self.wip.select(.normal, lhs_eq_zero, zero, umax, "");
        },
    };
    return self.wip.select(.normal, in_range, result, lhs_sat, "");
}

fn airShr(self: *FuncGen, inst: Air.Inst.Index, is_exact: bool) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const lhs = try self.resolveInst(bin_op.lhs);
    const rhs = try self.resolveInst(bin_op.rhs);

    const lhs_ty = self.typeOf(bin_op.lhs);
    if (lhs_ty.isVector(zcu) and !self.typeOf(bin_op.rhs).isVector(zcu)) {
        // `Sema` does not currently emit this pattern---instead it is specific to `Air.Legalize`
        // features which we do not use. Therefore this branch is currently impossible.
        unreachable;
    }
    const lhs_scalar_ty = lhs_ty.scalarType(zcu);

    const casted_rhs = try self.wip.conv(.unsigned, rhs, try o.lowerType(lhs_ty), "");
    const is_signed_int = lhs_scalar_ty.isSignedInt(zcu);

    return self.wip.bin(if (is_exact)
        if (is_signed_int) .@"ashr exact" else .@"lshr exact"
    else if (is_signed_int) .ashr else .lshr, lhs, casted_rhs, "");
}

fn airAbs(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const scalar_ty = operand_ty.scalarType(zcu);

    switch (scalar_ty.zigTypeTag(zcu)) {
        .int => return self.wip.callIntrinsic(
            .normal,
            .none,
            .abs,
            &.{try o.lowerType(operand_ty)},
            &.{ operand, try o.builder.intValue(.i1, 0) },
            "",
        ),
        .float => return self.buildFloatOp(.fabs, .normal, operand_ty, 1, .{operand}),
        else => unreachable,
    }
}

fn airIntCast(fg: *FuncGen, inst: Air.Inst.Index, safety: bool) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const ty_op = fg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const dest_ty = fg.typeOfIndex(inst);
    const dest_llvm_ty = try o.lowerType(dest_ty);
    const operand = try fg.resolveInst(ty_op.operand);
    const operand_ty = fg.typeOf(ty_op.operand);
    const operand_info = operand_ty.intInfo(zcu);

    const dest_is_enum = dest_ty.zigTypeTag(zcu) == .@"enum";

    bounds_check: {
        const dest_scalar = dest_ty.scalarType(zcu);
        const operand_scalar = operand_ty.scalarType(zcu);

        const dest_info = dest_ty.intInfo(zcu);

        const have_min_check, const have_max_check = c: {
            const dest_pos_bits = dest_info.bits - @intFromBool(dest_info.signedness == .signed);
            const operand_pos_bits = operand_info.bits - @intFromBool(operand_info.signedness == .signed);

            const dest_allows_neg = dest_info.signedness == .signed and dest_info.bits > 0;
            const operand_maybe_neg = operand_info.signedness == .signed and operand_info.bits > 0;

            break :c .{
                operand_maybe_neg and (!dest_allows_neg or dest_info.bits < operand_info.bits),
                dest_pos_bits < operand_pos_bits,
            };
        };

        if (!have_min_check and !have_max_check) break :bounds_check;

        const operand_llvm_ty = try o.lowerType(operand_ty);
        const operand_scalar_llvm_ty = try o.lowerType(operand_scalar);

        const is_vector = operand_ty.zigTypeTag(zcu) == .vector;
        assert(is_vector == (dest_ty.zigTypeTag(zcu) == .vector));

        const panic_id: Zcu.SimplePanicId = if (dest_is_enum) .invalid_enum_value else .integer_out_of_bounds;

        if (have_min_check) {
            const min_const_scalar = try minIntConst(&o.builder, dest_scalar, operand_scalar_llvm_ty, zcu);
            const min_val = if (is_vector) try o.builder.splatValue(operand_llvm_ty, min_const_scalar) else min_const_scalar.toValue();
            const ok_maybe_vec = try fg.cmp(.normal, .gte, operand_ty, operand, min_val);
            const ok = if (is_vector) ok: {
                const vec_ty = ok_maybe_vec.typeOfWip(&fg.wip);
                break :ok try fg.wip.callIntrinsic(.normal, .none, .@"vector.reduce.and", &.{vec_ty}, &.{ok_maybe_vec}, "");
            } else ok_maybe_vec;
            if (safety) {
                const fail_block = try fg.wip.block(1, "IntMinFail");
                const ok_block = try fg.wip.block(1, "IntMinOk");
                _ = try fg.wip.brCond(ok, ok_block, fail_block, .none);
                fg.wip.cursor = .{ .block = fail_block };
                try fg.buildSimplePanic(panic_id);
                fg.wip.cursor = .{ .block = ok_block };
            } else {
                _ = try fg.wip.callIntrinsic(.normal, .none, .assume, &.{}, &.{ok}, "");
            }
        }

        if (have_max_check) {
            const max_const_scalar = try maxIntConst(&o.builder, dest_scalar, operand_scalar_llvm_ty, zcu);
            const max_val = if (is_vector) try o.builder.splatValue(operand_llvm_ty, max_const_scalar) else max_const_scalar.toValue();
            const ok_maybe_vec = try fg.cmp(.normal, .lte, operand_ty, operand, max_val);
            const ok = if (is_vector) ok: {
                const vec_ty = ok_maybe_vec.typeOfWip(&fg.wip);
                break :ok try fg.wip.callIntrinsic(.normal, .none, .@"vector.reduce.and", &.{vec_ty}, &.{ok_maybe_vec}, "");
            } else ok_maybe_vec;
            if (safety) {
                const fail_block = try fg.wip.block(1, "IntMaxFail");
                const ok_block = try fg.wip.block(1, "IntMaxOk");
                _ = try fg.wip.brCond(ok, ok_block, fail_block, .none);
                fg.wip.cursor = .{ .block = fail_block };
                try fg.buildSimplePanic(panic_id);
                fg.wip.cursor = .{ .block = ok_block };
            } else {
                _ = try fg.wip.callIntrinsic(.normal, .none, .assume, &.{}, &.{ok}, "");
            }
        }
    }

    const result = try fg.wip.conv(switch (operand_info.signedness) {
        .signed => .signed,
        .unsigned => .unsigned,
    }, operand, dest_llvm_ty, "");

    if (safety and dest_is_enum and !dest_ty.isNonexhaustiveEnum(zcu)) {
        const llvm_fn = try o.getIsNamedEnumValueFunction(dest_ty);
        const is_valid_enum_val = try fg.wip.call(
            .normal,
            .fastcc,
            .none,
            llvm_fn.typeOf(&o.builder),
            llvm_fn.toValue(&o.builder),
            &.{result},
            "",
        );
        const fail_block = try fg.wip.block(1, "ValidEnumFail");
        const ok_block = try fg.wip.block(1, "ValidEnumOk");
        _ = try fg.wip.brCond(is_valid_enum_val, ok_block, fail_block, .none);
        fg.wip.cursor = .{ .block = fail_block };
        try fg.buildSimplePanic(.invalid_enum_value);
        fg.wip.cursor = .{ .block = ok_block };
    }

    return result;
}

fn airTrunc(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const dest_llvm_ty = try self.object.lowerType(self.typeOfIndex(inst));
    return self.wip.cast(.trunc, operand, dest_llvm_ty, "");
}

fn airFptrunc(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const dest_ty = self.typeOfIndex(inst);
    const target = zcu.getTarget();

    if (intrinsicsAllowed(dest_ty, target) and intrinsicsAllowed(operand_ty, target)) {
        return self.wip.cast(.fptrunc, operand, try o.lowerType(dest_ty), "");
    } else {
        const operand_llvm_ty = try o.lowerType(operand_ty);
        const dest_llvm_ty = try o.lowerType(dest_ty);

        const dest_bits = dest_ty.floatBits(target);
        const src_bits = operand_ty.floatBits(target);
        const fn_name = try o.builder.strtabStringFmt("__trunc{s}f{s}f2", .{
            compilerRtFloatAbbrev(src_bits), compilerRtFloatAbbrev(dest_bits),
        });

        const libc_fn = try o.getLibcFunction(fn_name, &.{operand_llvm_ty}, dest_llvm_ty);
        return self.wip.call(
            .normal,
            .ccc,
            .none,
            libc_fn.typeOf(&o.builder),
            libc_fn.toValue(&o.builder),
            &.{operand},
            "",
        );
    }
}

fn airFpext(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const operand_ty = self.typeOf(ty_op.operand);
    const dest_ty = self.typeOfIndex(inst);
    const target = zcu.getTarget();

    if (intrinsicsAllowed(dest_ty, target) and intrinsicsAllowed(operand_ty, target)) {
        return self.wip.cast(.fpext, operand, try o.lowerType(dest_ty), "");
    } else {
        const operand_llvm_ty = try o.lowerType(operand_ty);
        const dest_llvm_ty = try o.lowerType(dest_ty);

        const dest_bits = dest_ty.scalarType(zcu).floatBits(target);
        const src_bits = operand_ty.scalarType(zcu).floatBits(target);
        const fn_name = try o.builder.strtabStringFmt("__extend{s}f{s}f2", .{
            compilerRtFloatAbbrev(src_bits), compilerRtFloatAbbrev(dest_bits),
        });

        const libc_fn = try o.getLibcFunction(fn_name, &.{operand_llvm_ty}, dest_llvm_ty);
        if (dest_ty.isVector(zcu)) return self.buildElementwiseCall(
            libc_fn,
            &.{operand},
            try o.builder.poisonValue(dest_llvm_ty),
            dest_ty.vectorLen(zcu),
        );
        return self.wip.call(
            .normal,
            .ccc,
            .none,
            libc_fn.typeOf(&o.builder),
            libc_fn.toValue(&o.builder),
            &.{operand},
            "",
        );
    }
}

fn airBitCast(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_ty = self.typeOf(ty_op.operand);
    const inst_ty = self.typeOfIndex(inst);
    const operand = try self.resolveInst(ty_op.operand);
    return self.bitCast(operand, operand_ty, inst_ty);
}

fn bitCast(self: *FuncGen, operand: Builder.Value, operand_ty: Type, inst_ty: Type) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const operand_is_ref = isByRef(operand_ty, zcu);
    const result_is_ref = isByRef(inst_ty, zcu);
    const llvm_dest_ty = try o.lowerType(inst_ty);

    if (operand_is_ref and result_is_ref) {
        // They are both pointers, so just return the same opaque pointer :)
        return operand;
    }

    if (inst_ty.isAbiInt(zcu) and operand_ty.isAbiInt(zcu)) {
        return self.wip.conv(.unsigned, operand, llvm_dest_ty, "");
    }

    const operand_scalar_ty = operand_ty.scalarType(zcu);
    const inst_scalar_ty = inst_ty.scalarType(zcu);
    if (operand_scalar_ty.zigTypeTag(zcu) == .int and inst_scalar_ty.isPtrAtRuntime(zcu)) {
        return self.wip.cast(.inttoptr, operand, llvm_dest_ty, "");
    }
    if (operand_scalar_ty.isPtrAtRuntime(zcu) and inst_scalar_ty.zigTypeTag(zcu) == .int) {
        return self.wip.cast(.ptrtoint, operand, llvm_dest_ty, "");
    }

    if (operand_ty.zigTypeTag(zcu) == .vector and inst_ty.zigTypeTag(zcu) == .array) {
        const elem_ty = operand_scalar_ty;
        assert(result_is_ref); // arrays are always by-ref provided they have runtime bits
        const alignment = inst_ty.abiAlignment(zcu).toLlvm();
        const array_ptr = try self.buildAlloca(llvm_dest_ty, alignment);
        const bitcast_ok = elem_ty.bitSize(zcu) == elem_ty.abiSize(zcu) * 8;
        if (bitcast_ok) {
            _ = try self.wip.store(.normal, operand, array_ptr, alignment);
        } else {
            // If the ABI size of the element type is not evenly divisible by size in bits;
            // a simple bitcast will not work, and we fall back to extractelement.
            const elem_size = elem_ty.abiSize(zcu);
            const vector_len = operand_ty.arrayLen(zcu);
            var i: u64 = 0;
            while (i < vector_len) : (i += 1) {
                const arr_elem_ptr = try self.ptraddConst(array_ptr, i * elem_size);
                const vec_elem = try self.wip.extractElement(operand, try o.builder.intValue(.i32, i), "");
                _ = try self.wip.store(.normal, vec_elem, arr_elem_ptr, .default);
            }
        }
        return array_ptr;
    } else if (operand_ty.zigTypeTag(zcu) == .array and inst_ty.zigTypeTag(zcu) == .vector) {
        const elem_ty = operand_ty.childType(zcu);
        assert(operand_is_ref); // arrays are always by-ref provided they have runtime bits
        const llvm_vector_ty = try o.lowerType(inst_ty);

        const bitcast_ok = elem_ty.bitSize(zcu) == elem_ty.abiSize(zcu) * 8;
        if (bitcast_ok) {
            // The array is aligned to the element's alignment, while the vector might have a completely
            // different alignment. This means we need to enforce the alignment of this load.
            const alignment = elem_ty.abiAlignment(zcu).toLlvm();
            return self.wip.load(.normal, llvm_vector_ty, operand, alignment, "");
        } else {
            // If the ABI size of the element type is not evenly divisible by size in bits;
            // a simple bitcast will not work, and we fall back to extractelement.
            const elem_llvm_ty = try o.lowerType(elem_ty);
            const elem_size = elem_ty.abiSize(zcu);
            const vector_len = operand_ty.arrayLen(zcu);
            var vector = try o.builder.poisonValue(llvm_vector_ty);
            var i: u64 = 0;
            while (i < vector_len) : (i += 1) {
                const arr_elem_ptr = try self.ptraddConst(operand, i * elem_size);
                const arr_elem = try self.wip.load(.normal, elem_llvm_ty, arr_elem_ptr, .default, "");
                vector = try self.wip.insertElement(vector, arr_elem, try o.builder.intValue(.i32, i), "");
            }
            return vector;
        }
    }

    if (operand_is_ref) {
        const alignment = operand_ty.abiAlignment(zcu).toLlvm();
        return self.wip.load(.normal, llvm_dest_ty, operand, alignment, "");
    }

    if (result_is_ref) {
        const alignment = operand_ty.abiAlignment(zcu).max(inst_ty.abiAlignment(zcu)).toLlvm();
        const result_ptr = try self.buildAlloca(llvm_dest_ty, alignment);
        _ = try self.wip.store(.normal, operand, result_ptr, alignment);
        return result_ptr;
    }

    if (inst_ty.isSliceAtRuntime(zcu) or
        ((operand_ty.zigTypeTag(zcu) == .vector or inst_ty.zigTypeTag(zcu) == .vector) and
            operand_ty.bitSize(zcu) != inst_ty.bitSize(zcu)))
    {
        // Both our operand and our result are values, not pointers,
        // but LLVM won't let us bitcast struct values or vectors with padding bits.
        // Therefore, we store operand to alloca, then load for result.
        const alignment = operand_ty.abiAlignment(zcu).max(inst_ty.abiAlignment(zcu)).toLlvm();
        const result_ptr = try self.buildAlloca(llvm_dest_ty, alignment);
        _ = try self.wip.store(.normal, operand, result_ptr, alignment);
        return self.wip.load(.normal, llvm_dest_ty, result_ptr, alignment, "");
    }

    return self.wip.cast(.bitcast, operand, llvm_dest_ty, "");
}

fn airArg(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const pt = self.pt;
    const zcu = o.zcu;
    const arg_val = self.args[self.arg_index];
    self.arg_index += 1;

    // llvm does not support debug info for naked function arguments
    if (self.is_naked) return arg_val;

    const inst_ty = self.typeOfIndex(inst);

    const func = zcu.funcInfo(zcu.navValue(self.nav_index).toIntern());
    const func_zir = func.zir_body_inst.resolveFull(&zcu.intern_pool).?;
    const file = zcu.fileByIndex(func_zir.file);

    const mod = file.mod.?;
    if (mod.strip) return arg_val;
    const arg = self.air.instructions.items(.data)[@intFromEnum(inst)].arg;
    const zir = &file.zir.?;
    const name = zir.nullTerminatedString(zir.getParamName(zir.getParamBody(func_zir.inst)[arg.zir_param_index]).?);

    const lbrace_line = zcu.navSrcLine(func.owner_nav) + func.lbrace_line + 1;
    const lbrace_col = func.lbrace_column + 1;

    const debug_parameter = try o.builder.debugParameter(
        if (name.len > 0) try o.builder.metadataString(name) else null,
        self.file,
        self.scope,
        lbrace_line,
        try o.getDebugType(pt, inst_ty),
        self.arg_index,
    );

    const old_location = self.wip.debug_location;
    self.wip.debug_location = .{ .location = .{
        .line = lbrace_line,
        .column = lbrace_col,
        .scope = self.scope.toOptional(),
        .inlined_at = .none,
    } };

    if (isByRef(inst_ty, zcu)) {
        _ = try self.wip.callIntrinsic(
            .normal,
            .none,
            .@"dbg.declare",
            &.{},
            &.{
                (try self.wip.debugValue(arg_val)).toValue(),
                debug_parameter.toValue(),
                (try o.builder.debugExpression(&.{})).toValue(),
            },
            "",
        );
    } else if (mod.optimize_mode == .Debug) {
        const alignment = inst_ty.abiAlignment(zcu).toLlvm();
        const alloca = try self.buildAlloca(arg_val.typeOfWip(&self.wip), alignment);
        _ = try self.wip.store(.normal, arg_val, alloca, alignment);
        _ = try self.wip.callIntrinsic(
            .normal,
            .none,
            .@"dbg.declare",
            &.{},
            &.{
                (try self.wip.debugValue(alloca)).toValue(),
                debug_parameter.toValue(),
                (try o.builder.debugExpression(&.{})).toValue(),
            },
            "",
        );
    } else {
        _ = try self.wip.callIntrinsic(
            .normal,
            .none,
            .@"dbg.value",
            &.{},
            &.{
                (try self.wip.debugValue(arg_val)).toValue(),
                debug_parameter.toValue(),
                (try o.builder.debugExpression(&.{})).toValue(),
            },
            "",
        );
    }

    self.wip.debug_location = old_location;
    return arg_val;
}

fn airAlloc(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ptr_ty = self.typeOfIndex(inst);
    const ptr_align = ptr_ty.ptrAlignment(zcu);
    const elem_ty = ptr_ty.childType(zcu);
    if (!elem_ty.hasRuntimeBits(zcu)) {
        return (try o.lowerPtrToVoid(ptr_align, ptr_ty.ptrAddressSpace(zcu))).toValue();
    }
    const llvm_elem_ty = try o.lowerType(elem_ty);
    return self.buildAlloca(llvm_elem_ty, ptr_align.toLlvm());
}

fn airRetPtr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    if (self.ret_ptr != .none) return self.ret_ptr;
    const o = self.object;
    const zcu = o.zcu;
    const ptr_ty = self.typeOfIndex(inst);
    const ptr_align = ptr_ty.ptrAlignment(zcu);
    const elem_ty = ptr_ty.childType(zcu);
    if (!elem_ty.hasRuntimeBits(zcu)) {
        return (try o.lowerPtrToVoid(ptr_align, ptr_ty.ptrAddressSpace(zcu))).toValue();
    }
    const llvm_elem_ty = try o.lowerType(elem_ty);
    return self.buildAlloca(llvm_elem_ty, ptr_align.toLlvm());
}

/// Use this instead of builder.buildAlloca, because this function makes sure to
/// put the alloca instruction at the top of the function!
fn buildAlloca(
    self: *FuncGen,
    llvm_ty: Builder.Type,
    alignment: Builder.Alignment,
) Allocator.Error!Builder.Value {
    const target = self.object.zcu.getTarget();
    return buildAllocaInner(&self.wip, llvm_ty, alignment, target);
}

fn airStore(self: *FuncGen, inst: Air.Inst.Index, safety: bool) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_ptr = try self.resolveInst(bin_op.lhs);
    const ptr_ty = self.typeOf(bin_op.lhs);
    const operand_ty = ptr_ty.childType(zcu);

    const val_is_undef = if (bin_op.rhs.toInterned()) |i| Value.fromInterned(i).isUndef(zcu) else false;
    if (val_is_undef) {
        const owner_mod = self.ownerModule();

        // Even if safety is disabled, we still emit a memset to undefined since it conveys
        // extra information to LLVM, and LLVM will optimize it out. Safety makes the difference
        // between using 0xaa or actual undefined for the fill byte.
        //
        // However, for Debug builds specifically, we avoid emitting the memset because LLVM
        // will neither use the information nor get rid of the memset, thus leaving an
        // unexpected call in the user's code. This is problematic if the code in question is
        // not ready to correctly make calls yet, such as in our early PIE startup code, or in
        // the early stages of a dynamic linker, etc.
        if (!safety and owner_mod.optimize_mode == .Debug) {
            return .none;
        }

        const ptr_info = ptr_ty.ptrInfo(zcu);
        const needs_bitmask = (ptr_info.packed_offset.host_size != 0);
        if (needs_bitmask) {
            // TODO: only some bits are to be undef, we cannot write with a simple memset.
            // meanwhile, ignore the write rather than stomping over valid bits.
            // https://github.com/ziglang/zig/issues/15337
            return .none;
        }

        self.maybeMarkAllowZeroAccess(ptr_info);

        const len = try o.builder.intValue(try o.lowerType(.usize), operand_ty.abiSize(zcu));
        _ = try self.wip.callMemSet(
            dest_ptr,
            ptr_ty.ptrAlignment(zcu).toLlvm(),
            if (safety) try o.builder.intValue(.i8, 0xaa) else try o.builder.undefValue(.i8),
            len,
            if (ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal,
            self.disable_intrinsics,
        );
        if (safety and owner_mod.valgrind) {
            try self.valgrindMarkUndef(dest_ptr, len);
        }
        return .none;
    }

    self.maybeMarkAllowZeroAccess(ptr_ty.ptrInfo(zcu));

    const src_operand = try self.resolveInst(bin_op.rhs);
    try self.storeFull(dest_ptr, ptr_ty, src_operand, .none);
    return .none;
}

fn airLoad(fg: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const ty_op = fg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const ptr_ty = fg.typeOf(ty_op.operand);
    const ptr_info = ptr_ty.ptrInfo(zcu);
    const ptr = try fg.resolveInst(ty_op.operand);
    const elem_ty = ptr_ty.childType(zcu);
    const llvm_ptr_align = ptr_ty.ptrAlignment(zcu).toLlvm();

    fg.maybeMarkAllowZeroAccess(ptr_info);

    const access_kind: Builder.MemoryAccessKind =
        if (ptr_info.flags.is_volatile) .@"volatile" else .normal;

    if (ptr_info.flags.vector_index != .none) {
        const index_u32 = try o.builder.intValue(.i32, ptr_info.flags.vector_index);
        const vec_elem_ty = try o.lowerType(elem_ty);
        const vec_ty = try o.builder.vectorType(.normal, ptr_info.packed_offset.host_size, vec_elem_ty);

        const loaded_vector = try fg.wip.load(access_kind, vec_ty, ptr, llvm_ptr_align, "");
        return fg.wip.extractElement(loaded_vector, index_u32, "");
    }

    if (ptr_info.packed_offset.host_size == 0) {
        return fg.load(ptr, elem_ty, llvm_ptr_align, access_kind);
    }

    const containing_int_ty = try o.builder.intType(@intCast(ptr_info.packed_offset.host_size * 8));
    const containing_int =
        try fg.wip.load(access_kind, containing_int_ty, ptr, llvm_ptr_align, "");

    const elem_bits = ptr_ty.childType(zcu).bitSize(zcu);
    const shift_amt = try o.builder.intValue(containing_int_ty, ptr_info.packed_offset.bit_offset);
    const shifted_value = try fg.wip.bin(.lshr, containing_int, shift_amt, "");
    const elem_llvm_ty = try o.lowerType(elem_ty);

    if (isByRef(elem_ty, zcu)) {
        const result_align = elem_ty.abiAlignment(zcu).toLlvm();
        const result_ptr = try fg.buildAlloca(elem_llvm_ty, result_align);

        const same_size_int = try o.builder.intType(@intCast(elem_bits));
        const truncated_int = try fg.wip.cast(.trunc, shifted_value, same_size_int, "");
        _ = try fg.wip.store(.normal, truncated_int, result_ptr, result_align);
        return result_ptr;
    }

    if (elem_ty.zigTypeTag(zcu) == .float or elem_ty.zigTypeTag(zcu) == .vector) {
        const same_size_int = try o.builder.intType(@intCast(elem_bits));
        const truncated_int = try fg.wip.cast(.trunc, shifted_value, same_size_int, "");
        return fg.wip.cast(.bitcast, truncated_int, elem_llvm_ty, "");
    }

    if (elem_ty.isPtrAtRuntime(zcu)) {
        const same_size_int = try o.builder.intType(@intCast(elem_bits));
        const truncated_int = try fg.wip.cast(.trunc, shifted_value, same_size_int, "");
        return fg.wip.cast(.inttoptr, truncated_int, elem_llvm_ty, "");
    }

    return fg.wip.cast(.trunc, shifted_value, elem_llvm_ty, "");
}

fn airTrap(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!void {
    _ = inst;
    const target = self.object.zcu.getTarget();
    if ((target.cpu.arch == .mips or target.cpu.arch == .mipsel) and
        target.cpu.has(.mips, .notraps))
    {
        // Emit a MIPS `break` instruction followed by an infinite loop (to fulfil the noreturn)
        // since this CPU does not support trap instructions.
        const o = self.object;
        _ = try self.wip.callAsm(
            .none,
            try o.builder.fnType(.void, &.{}, .normal),
            .{ .sideeffect = true },
            try o.builder.string("break\n0:\nj 0b\nnop"),
            try o.builder.string("~{memory}"),
            &.{},
            "",
        );
    } else {
        _ = try self.wip.callIntrinsic(.normal, .none, .trap, &.{}, &.{}, "");
    }
    _ = try self.wip.@"unreachable"();
}

fn airBreakpoint(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    _ = inst;
    _ = try self.wip.callIntrinsic(.normal, .none, .debugtrap, &.{}, &.{}, "");
    return .none;
}

fn airRetAddr(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    _ = inst;
    const o = self.object;
    const llvm_usize = try o.lowerType(.usize);
    if (!target_util.supportsReturnAddress(self.object.zcu.getTarget(), self.ownerModule().optimize_mode)) {
        // https://github.com/ziglang/zig/issues/11946
        return o.builder.intValue(llvm_usize, 0);
    }
    const result = try self.wip.callIntrinsic(.normal, .none, .returnaddress, &.{}, &.{.@"0"}, "");
    return self.wip.cast(.ptrtoint, result, llvm_usize, "");
}

fn airFrameAddress(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    _ = inst;
    const result = try self.wip.callIntrinsic(.normal, .none, .frameaddress, &.{.ptr}, &.{.@"0"}, "");
    return self.wip.cast(.ptrtoint, result, try self.object.lowerType(.usize), "");
}

fn airCmpxchg(
    self: *FuncGen,
    inst: Air.Inst.Index,
    kind: Builder.Function.Instruction.CmpXchg.Kind,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = self.air.extraData(Air.Cmpxchg, ty_pl.payload).data;
    const ptr = try self.resolveInst(extra.ptr);
    const ptr_ty = self.typeOf(extra.ptr);
    var expected_value = try self.resolveInst(extra.expected_value);
    var new_value = try self.resolveInst(extra.new_value);
    const operand_ty = ptr_ty.childType(zcu);
    const llvm_operand_ty = try o.lowerType(operand_ty);
    const llvm_abi_ty = try self.getAtomicAbiType(operand_ty, false);
    if (llvm_abi_ty != .none) {
        // operand needs widening and truncating
        const signedness: Builder.Function.Instruction.Cast.Signedness =
            if (operand_ty.isSignedInt(zcu)) .signed else .unsigned;
        expected_value = try self.wip.conv(signedness, expected_value, llvm_abi_ty, "");
        new_value = try self.wip.conv(signedness, new_value, llvm_abi_ty, "");
    }

    self.maybeMarkAllowZeroAccess(ptr_ty.ptrInfo(zcu));

    const result = try self.wip.cmpxchg(
        kind,
        if (ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal,
        ptr,
        expected_value,
        new_value,
        self.sync_scope,
        toLlvmAtomicOrdering(extra.successOrder()),
        toLlvmAtomicOrdering(extra.failureOrder()),
        ptr_ty.ptrAlignment(zcu).toLlvm(),
        "",
    );

    const optional_ty = self.typeOfIndex(inst);

    var payload = try self.wip.extractValue(result, &.{0}, "");
    if (llvm_abi_ty != .none) payload = try self.wip.cast(.trunc, payload, llvm_operand_ty, "");
    const success_bit = try self.wip.extractValue(result, &.{1}, "");

    if (optional_ty.optionalReprIsPayload(zcu)) {
        const zero = try o.builder.zeroInitValue(payload.typeOfWip(&self.wip));
        return self.wip.select(.normal, success_bit, zero, payload, "");
    }

    assert(isByRef(optional_ty, zcu));

    comptime assert(optional_layout_version == 3);

    const non_null_bit = try self.wip.not(success_bit, "");

    const payload_align = operand_ty.abiAlignment(zcu).toLlvm();
    const alloca_inst = try self.buildAlloca(try o.lowerType(optional_ty), payload_align);

    // Payload is always the first field at offset 0, so address is `alloca_inst`
    _ = try self.wip.store(.normal, payload, alloca_inst, payload_align);

    // Non-null bit is after payload with no padding because it has alignment 1
    const non_null_ptr = try self.ptraddConst(alloca_inst, operand_ty.abiSize(zcu));
    _ = try self.wip.store(.normal, non_null_bit, non_null_ptr, comptime .fromByteUnits(1));

    return alloca_inst;
}

fn airAtomicRmw(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = self.air.extraData(Air.AtomicRmw, pl_op.payload).data;
    const ptr = try self.resolveInst(pl_op.operand);
    const ptr_ty = self.typeOf(pl_op.operand);
    const operand_ty = ptr_ty.childType(zcu);
    const operand = try self.resolveInst(extra.operand);
    const is_signed_int = operand_ty.isSignedInt(zcu);
    const is_float = operand_ty.isRuntimeFloat();
    const op = toLlvmAtomicRmwBinOp(extra.op(), is_signed_int, is_float);
    const ordering = toLlvmAtomicOrdering(extra.ordering());
    const llvm_abi_ty = try self.getAtomicAbiType(operand_ty, op == .xchg);
    const llvm_operand_ty = try o.lowerType(operand_ty);

    const access_kind: Builder.MemoryAccessKind =
        if (ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;
    const ptr_alignment = ptr_ty.ptrAlignment(zcu).toLlvm();

    self.maybeMarkAllowZeroAccess(ptr_ty.ptrInfo(zcu));

    if (llvm_abi_ty != .none) {
        // operand needs widening and truncating or bitcasting.
        return self.wip.cast(if (is_float) .bitcast else .trunc, try self.wip.atomicrmw(
            access_kind,
            op,
            ptr,
            try self.wip.cast(
                if (is_float) .bitcast else if (is_signed_int) .sext else .zext,
                operand,
                llvm_abi_ty,
                "",
            ),
            self.sync_scope,
            ordering,
            ptr_alignment,
            "",
        ), llvm_operand_ty, "");
    }

    // If we are storing a pointer we need to convert to and from a plain old integer.
    const non_ptr_operand = switch (operand_ty.zigTypeTag(zcu)) {
        .pointer => try self.wip.cast(.ptrtoint, operand, try o.lowerType(.usize), ""),
        else => operand,
    };

    const raw_result = try self.wip.atomicrmw(
        access_kind,
        op,
        ptr,
        non_ptr_operand,
        self.sync_scope,
        ordering,
        ptr_alignment,
        "",
    );

    // ...and then convert the result back.
    switch (operand_ty.zigTypeTag(zcu)) {
        .pointer => return self.wip.cast(.inttoptr, raw_result, llvm_operand_ty, ""),
        else => return raw_result,
    }
}

fn airAtomicLoad(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const atomic_load = self.air.instructions.items(.data)[@intFromEnum(inst)].atomic_load;
    const ptr = try self.resolveInst(atomic_load.ptr);
    const ptr_ty = self.typeOf(atomic_load.ptr);
    const info = ptr_ty.ptrInfo(zcu);
    const elem_ty = Type.fromInterned(info.child);
    if (!elem_ty.hasRuntimeBits(zcu)) return .none;
    const ordering = toLlvmAtomicOrdering(atomic_load.order);
    const llvm_abi_ty = try self.getAtomicAbiType(elem_ty, false);
    const ptr_alignment = (if (info.flags.alignment != .none)
        @as(InternPool.Alignment, info.flags.alignment)
    else
        Type.fromInterned(info.child).abiAlignment(zcu)).toLlvm();
    const access_kind: Builder.MemoryAccessKind =
        if (info.flags.is_volatile) .@"volatile" else .normal;
    const elem_llvm_ty = try o.lowerType(elem_ty);

    self.maybeMarkAllowZeroAccess(info);

    if (llvm_abi_ty != .none) {
        // operand needs widening and truncating
        const loaded = try self.wip.loadAtomic(
            access_kind,
            llvm_abi_ty,
            ptr,
            self.sync_scope,
            ordering,
            ptr_alignment,
            "",
        );
        return self.wip.cast(.trunc, loaded, elem_llvm_ty, "");
    }
    return self.wip.loadAtomic(
        access_kind,
        elem_llvm_ty,
        ptr,
        self.sync_scope,
        ordering,
        ptr_alignment,
        "",
    );
}

fn airAtomicStore(
    self: *FuncGen,
    inst: Air.Inst.Index,
    ordering: Builder.AtomicOrdering,
) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const ptr_ty = self.typeOf(bin_op.lhs);
    const operand_ty = ptr_ty.childType(zcu);
    if (!operand_ty.hasRuntimeBits(zcu)) return .none;
    const ptr = try self.resolveInst(bin_op.lhs);
    var element = try self.resolveInst(bin_op.rhs);
    const llvm_abi_ty = try self.getAtomicAbiType(operand_ty, false);

    if (llvm_abi_ty != .none) {
        // operand needs widening
        element = try self.wip.conv(
            if (operand_ty.isSignedInt(zcu)) .signed else .unsigned,
            element,
            llvm_abi_ty,
            "",
        );
    }

    self.maybeMarkAllowZeroAccess(ptr_ty.ptrInfo(zcu));

    try self.storeFull(ptr, ptr_ty, element, ordering);
    return .none;
}

fn airMemset(self: *FuncGen, inst: Air.Inst.Index, safety: bool) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_slice = try self.resolveInst(bin_op.lhs);
    const ptr_ty = self.typeOf(bin_op.lhs);
    const elem_ty = self.typeOf(bin_op.rhs);
    const dest_ptr_align = ptr_ty.ptrAlignment(zcu).toLlvm();
    const dest_ptr = try self.sliceOrArrayPtr(dest_slice, ptr_ty);
    const access_kind: Builder.MemoryAccessKind =
        if (ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    self.maybeMarkAllowZeroAccess(ptr_ty.ptrInfo(zcu));

    if (bin_op.rhs.toInterned()) |elem_ip_index| {
        const elem_val: Value = .fromInterned(elem_ip_index);
        if (elem_val.isUndef(zcu)) {
            // Even if safety is disabled, we still emit a memset to undefined since it conveys
            // extra information to LLVM. However, safety makes the difference between using
            // 0xaa or actual undefined for the fill byte.
            const fill_byte = if (safety)
                try o.builder.intValue(.i8, 0xaa)
            else
                try o.builder.undefValue(.i8);
            const len = try self.sliceOrArrayLenInBytes(dest_slice, ptr_ty);
            _ = try self.wip.callMemSet(
                dest_ptr,
                dest_ptr_align,
                fill_byte,
                len,
                access_kind,
                self.disable_intrinsics,
            );
            const owner_mod = self.ownerModule();
            if (safety and owner_mod.valgrind) {
                try self.valgrindMarkUndef(dest_ptr, len);
            }
            return .none;
        }

        // Test if the element value is compile-time known to be a
        // repeating byte pattern, for example, `@as(u64, 0)` has a
        // repeating byte pattern of 0 bytes. In such case, the memset
        // intrinsic can be used.
        if (try elem_val.hasRepeatedByteRepr(zcu)) |byte_val| {
            const fill_byte = try o.builder.intValue(.i8, byte_val);
            const len = try self.sliceOrArrayLenInBytes(dest_slice, ptr_ty);
            _ = try self.wip.callMemSet(
                dest_ptr,
                dest_ptr_align,
                fill_byte,
                len,
                access_kind,
                self.disable_intrinsics,
            );
            return .none;
        }
    }

    const value = try self.resolveInst(bin_op.rhs);
    const elem_abi_size = elem_ty.abiSize(zcu);

    if (elem_abi_size == 1 and elem_ty.bitSize(zcu) == 8) {
        // In this case we can take advantage of LLVM's intrinsic.
        const fill_byte = try self.bitCast(value, elem_ty, Type.u8);
        const len = try self.sliceOrArrayLenInBytes(dest_slice, ptr_ty);

        _ = try self.wip.callMemSet(
            dest_ptr,
            dest_ptr_align,
            fill_byte,
            len,
            access_kind,
            self.disable_intrinsics,
        );
        return .none;
    }

    // non-byte-sized element. lower with a loop. something like this:

    // entry:
    //   ...
    //   %end_ptr = getelementptr %ptr, %len
    //   br %loop
    // loop:
    //   %it_ptr = phi body %next_ptr, entry %ptr
    //   %end = cmp eq %it_ptr, %end_ptr
    //   br %end, %body, %end
    // body:
    //   store %it_ptr, %value
    //   %next_ptr = getelementptr %it_ptr, 1
    //   br %loop
    // end:
    //   ...
    const entry_block = self.wip.cursor.block;
    const loop_block = try self.wip.block(2, "InlineMemsetLoop");
    const body_block = try self.wip.block(1, "InlineMemsetBody");
    const end_block = try self.wip.block(1, "InlineMemsetEnd");

    const llvm_usize_ty = try o.lowerType(.usize);
    const end_ptr = switch (ptr_ty.ptrSize(zcu)) {
        .slice => try self.ptraddScaled(
            dest_ptr,
            try self.wip.extractValue(dest_slice, &.{1}, ""),
            elem_abi_size,
        ),
        .one => try self.ptraddConst(dest_ptr, ptr_ty.childType(zcu).abiSize(zcu)),
        .many, .c => unreachable,
    };
    _ = try self.wip.br(loop_block);

    self.wip.cursor = .{ .block = loop_block };
    const it_ptr = try self.wip.phi(.ptr, "");
    const end = try self.wip.icmp(.ne, it_ptr.toValue(), end_ptr, "");
    _ = try self.wip.brCond(end, body_block, end_block, .none);

    self.wip.cursor = .{ .block = body_block };
    const elem_abi_align = elem_ty.abiAlignment(zcu);
    const it_ptr_align = InternPool.Alignment.fromLlvm(dest_ptr_align).min(elem_abi_align).toLlvm();
    if (isByRef(elem_ty, zcu)) {
        _ = try self.wip.callMemCpy(
            it_ptr.toValue(),
            it_ptr_align,
            value,
            elem_abi_align.toLlvm(),
            try o.builder.intValue(llvm_usize_ty, elem_abi_size),
            access_kind,
            self.disable_intrinsics,
        );
    } else _ = try self.wip.store(access_kind, value, it_ptr.toValue(), it_ptr_align);
    const next_ptr = try self.ptraddConst(it_ptr.toValue(), elem_abi_size);
    _ = try self.wip.br(loop_block);

    self.wip.cursor = .{ .block = end_block };
    it_ptr.finish(&.{ next_ptr, dest_ptr }, &.{ body_block, entry_block }, &self.wip);
    return .none;
}

fn airMemcpy(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_slice = try self.resolveInst(bin_op.lhs);
    const dest_ptr_ty = self.typeOf(bin_op.lhs);
    const src_slice = try self.resolveInst(bin_op.rhs);
    const src_ptr_ty = self.typeOf(bin_op.rhs);
    const src_ptr = try self.sliceOrArrayPtr(src_slice, src_ptr_ty);
    const len = try self.sliceOrArrayLenInBytes(dest_slice, dest_ptr_ty);
    const dest_ptr = try self.sliceOrArrayPtr(dest_slice, dest_ptr_ty);
    const access_kind: Builder.MemoryAccessKind = if (src_ptr_ty.isVolatilePtr(zcu) or
        dest_ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    self.maybeMarkAllowZeroAccess(dest_ptr_ty.ptrInfo(zcu));
    self.maybeMarkAllowZeroAccess(src_ptr_ty.ptrInfo(zcu));

    _ = try self.wip.callMemCpy(
        dest_ptr,
        dest_ptr_ty.ptrAlignment(zcu).toLlvm(),
        src_ptr,
        src_ptr_ty.ptrAlignment(zcu).toLlvm(),
        len,
        access_kind,
        self.disable_intrinsics,
    );
    return .none;
}

fn airMemmove(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_slice = try self.resolveInst(bin_op.lhs);
    const dest_ptr_ty = self.typeOf(bin_op.lhs);
    const src_slice = try self.resolveInst(bin_op.rhs);
    const src_ptr_ty = self.typeOf(bin_op.rhs);
    const src_ptr = try self.sliceOrArrayPtr(src_slice, src_ptr_ty);
    const len = try self.sliceOrArrayLenInBytes(dest_slice, dest_ptr_ty);
    const dest_ptr = try self.sliceOrArrayPtr(dest_slice, dest_ptr_ty);
    const access_kind: Builder.MemoryAccessKind = if (src_ptr_ty.isVolatilePtr(zcu) or
        dest_ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    _ = try self.wip.callMemMove(
        dest_ptr,
        dest_ptr_ty.ptrAlignment(zcu).toLlvm(),
        src_ptr,
        src_ptr_ty.ptrAlignment(zcu).toLlvm(),
        len,
        access_kind,
    );
    return .none;
}

fn airSetUnionTag(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const bin_op = self.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const un_ptr_ty = self.typeOf(bin_op.lhs);
    const un_ty = un_ptr_ty.childType(zcu);
    const layout = un_ty.unionGetLayout(zcu);

    if (layout.tag_size == 0) return .none; // TODO: stop Sema emitting this

    const access_kind: Builder.MemoryAccessKind =
        if (un_ptr_ty.isVolatilePtr(zcu)) .@"volatile" else .normal;

    self.maybeMarkAllowZeroAccess(un_ptr_ty.ptrInfo(zcu));

    const union_ptr = try self.resolveInst(bin_op.lhs);
    const new_tag = try self.resolveInst(bin_op.rhs);
    const union_ptr_align = un_ptr_ty.ptrAlignment(zcu);
    if (layout.payload_size == 0) {
        _ = try self.wip.store(access_kind, new_tag, union_ptr, union_ptr_align.toLlvm());
        return .none;
    }
    const tag_field_ptr = try self.ptraddConst(union_ptr, layout.tagOffset());
    const tag_ptr_align: InternPool.Alignment = switch (layout.tagOffset()) {
        0 => union_ptr_align,
        else => |off| .minStrict(union_ptr_align, .fromLog2Units(@ctz(off))),
    };
    _ = try self.wip.store(access_kind, new_tag, tag_field_ptr, tag_ptr_align.toLlvm());
    return .none;
}

fn airGetUnionTag(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const un_ty = self.typeOf(ty_op.operand);
    const layout = un_ty.unionGetLayout(zcu);
    assert(layout.tag_size != 0);
    const operand = try self.resolveInst(ty_op.operand);
    if (isByRef(un_ty, zcu)) {
        const llvm_tag_ty = try o.lowerType(un_ty.unionTagTypeRuntime(zcu).?);
        const tag_field_ptr = try self.ptraddConst(operand, layout.tagOffset());
        return self.wip.load(.normal, llvm_tag_ty, tag_field_ptr, .default, "");
    } else {
        // This is only possible if all fields are zero-bit, in which case `operand` is already an
        // integer value (the union is lowered as its enum tag).
        assert(layout.payload_size == 0);
        return operand;
    }
}

fn airUnaryOp(self: *FuncGen, inst: Air.Inst.Index, comptime op: FloatOp) Allocator.Error!Builder.Value {
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const operand_ty = self.typeOf(un_op);

    return self.buildFloatOp(op, .normal, operand_ty, 1, .{operand});
}

fn airNeg(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const operand_ty = self.typeOf(un_op);

    return self.buildFloatOp(.neg, fast, operand_ty, 1, .{operand});
}

fn airClzCtz(self: *FuncGen, inst: Air.Inst.Index, intrinsic: Builder.Intrinsic) Allocator.Error!Builder.Value {
    const o = self.object;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const inst_ty = self.typeOfIndex(inst);
    const operand_ty = self.typeOf(ty_op.operand);
    const operand = try self.resolveInst(ty_op.operand);

    const result = try self.wip.callIntrinsic(
        .normal,
        .none,
        intrinsic,
        &.{try o.lowerType(operand_ty)},
        &.{ operand, .false },
        "",
    );
    return self.wip.conv(.unsigned, result, try o.lowerType(inst_ty), "");
}

fn airBitOp(self: *FuncGen, inst: Air.Inst.Index, intrinsic: Builder.Intrinsic) Allocator.Error!Builder.Value {
    const o = self.object;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const inst_ty = self.typeOfIndex(inst);
    const operand_ty = self.typeOf(ty_op.operand);
    const operand = try self.resolveInst(ty_op.operand);

    const result = try self.wip.callIntrinsic(
        .normal,
        .none,
        intrinsic,
        &.{try o.lowerType(operand_ty)},
        &.{operand},
        "",
    );
    return self.wip.conv(.unsigned, result, try o.lowerType(inst_ty), "");
}

fn airByteSwap(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_ty = self.typeOf(ty_op.operand);
    var bits = operand_ty.intInfo(zcu).bits;
    assert(bits % 8 == 0);

    const inst_ty = self.typeOfIndex(inst);
    var operand = try self.resolveInst(ty_op.operand);
    var llvm_operand_ty = try o.lowerType(operand_ty);

    if (bits % 16 == 8) {
        // If not an even byte-multiple, we need zero-extend + shift-left 1 byte
        // The truncated result at the end will be the correct bswap
        const scalar_ty = try o.builder.intType(@intCast(bits + 8));
        if (operand_ty.zigTypeTag(zcu) == .vector) {
            const vec_len = operand_ty.vectorLen(zcu);
            llvm_operand_ty = try o.builder.vectorType(.normal, vec_len, scalar_ty);
        } else llvm_operand_ty = scalar_ty;

        const shift_amt =
            try o.builder.splatValue(llvm_operand_ty, try o.builder.intConst(scalar_ty, 8));
        const extended = try self.wip.cast(.zext, operand, llvm_operand_ty, "");
        operand = try self.wip.bin(.shl, extended, shift_amt, "");

        bits = bits + 8;
    }

    const result =
        try self.wip.callIntrinsic(.normal, .none, .bswap, &.{llvm_operand_ty}, &.{operand}, "");
    return self.wip.conv(.unsigned, result, try o.lowerType(inst_ty), "");
}

fn airErrorSetHasValue(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try self.resolveInst(ty_op.operand);
    const error_set_ty = ty_op.ty.toType();

    const names = error_set_ty.errorSetNames(zcu);
    const valid_block = try self.wip.block(@intCast(names.len), "Valid");
    const invalid_block = try self.wip.block(1, "Invalid");
    const end_block = try self.wip.block(2, "End");
    var wip_switch = try self.wip.@"switch"(operand, invalid_block, @intCast(names.len), .none);
    defer wip_switch.finish(&self.wip);

    for (0..names.len) |name_index| {
        const err_int = ip.getErrorValueIfExists(names.get(ip)[name_index]).?;
        const this_tag_int_value = try o.builder.intConst(try o.errorIntType(), err_int);
        try wip_switch.addCase(this_tag_int_value, valid_block, &self.wip);
    }
    self.wip.cursor = .{ .block = valid_block };
    _ = try self.wip.br(end_block);

    self.wip.cursor = .{ .block = invalid_block };
    _ = try self.wip.br(end_block);

    self.wip.cursor = .{ .block = end_block };
    const phi = try self.wip.phi(.i1, "");
    phi.finish(&.{ .true, .false }, &.{ valid_block, invalid_block }, &self.wip);
    return phi.toValue();
}

fn airIsNamedEnumValue(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const enum_ty = self.typeOf(un_op);

    const llvm_fn = try o.getIsNamedEnumValueFunction(enum_ty);
    return self.wip.call(
        .normal,
        .fastcc,
        .none,
        llvm_fn.typeOf(&o.builder),
        llvm_fn.toValue(&o.builder),
        &.{operand},
        "",
    );
}

fn airTagName(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const enum_ty = self.typeOf(un_op);

    const llvm_fn = try o.getEnumTagNameFunction(enum_ty);
    return self.wip.call(
        .normal,
        .fastcc,
        .none,
        llvm_fn.typeOf(&o.builder),
        llvm_fn.toValue(&o.builder),
        &.{operand},
        "",
    );
}

fn airErrorName(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const un_op = self.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try self.resolveInst(un_op);
    const slice_ty = self.typeOfIndex(inst);
    const slice_llvm_ty = try o.lowerType(slice_ty);

    // If operand is small (e.g. `u8`), then signedness becomes a problem -- GEP always treats the index as signed.
    const operand_usize = try self.wip.conv(.unsigned, operand, try o.lowerType(.usize), "");

    const error_name_table_ptr = try o.getErrorNameTable();
    const error_name_ptr = try self.ptraddScaled(error_name_table_ptr.toValue(&o.builder), operand_usize, slice_ty.abiSize(zcu));
    return self.wip.load(.normal, slice_llvm_ty, error_name_ptr, .default, "");
}

fn airSplat(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const scalar = try self.resolveInst(ty_op.operand);
    const vector_ty = self.typeOfIndex(inst);
    return self.wip.splatVector(try self.object.lowerType(vector_ty), scalar, "");
}

fn airSelect(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = self.air.extraData(Air.Bin, pl_op.payload).data;
    const pred = try self.resolveInst(pl_op.operand);
    const a = try self.resolveInst(extra.lhs);
    const b = try self.resolveInst(extra.rhs);

    return self.wip.select(.normal, pred, a, b, "");
}

fn airShuffleOne(fg: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const gpa = zcu.gpa;

    const unwrapped = fg.air.unwrapShuffleOne(zcu, inst);

    const operand = try fg.resolveInst(unwrapped.operand);
    const mask = unwrapped.mask;
    const operand_ty = fg.typeOf(unwrapped.operand);
    const llvm_operand_ty = try o.lowerType(operand_ty);
    const llvm_result_ty = try o.lowerType(unwrapped.result_ty);
    const llvm_elem_ty = try o.lowerType(unwrapped.result_ty.childType(zcu));
    const llvm_poison_elem = try o.builder.poisonConst(llvm_elem_ty);
    const llvm_poison_mask_elem = try o.builder.poisonConst(.i32);
    const llvm_mask_ty = try o.builder.vectorType(.normal, @intCast(mask.len), .i32);

    // LLVM requires that the two input vectors have the same length, so lowering isn't trivial.
    // And, in the words of jacobly0: "llvm sucks at shuffles so we do have to hold its hand at
    // least a bit". So, there are two cases here.
    //
    // If the operand length equals the mask length, we do just the one `shufflevector`, where
    // the second operand is a constant vector with comptime-known elements at the right indices
    // and poison values elsewhere (in the indices which won't be selected).
    //
    // Otherwise, we lower to *two* `shufflevector` instructions. The first shuffles the runtime
    // operand with an all-poison vector to extract and correctly position all of the runtime
    // elements. We also make a constant vector with all of the comptime elements correctly
    // positioned. Then, our second instruction selects elements from those "runtime-or-poison"
    // and "comptime-or-poison" vectors to compute the result.

    // This buffer is used primarily for the mask constants.
    const llvm_elem_buf = try gpa.alloc(Builder.Constant, mask.len);
    defer gpa.free(llvm_elem_buf);

    // ...but first, we'll collect all of the comptime-known values.
    var any_defined_comptime_value = false;
    for (mask, llvm_elem_buf) |mask_elem, *llvm_elem| {
        llvm_elem.* = switch (mask_elem.unwrap()) {
            .elem => llvm_poison_elem,
            .value => |val| if (!Value.fromInterned(val).isUndef(zcu)) elem: {
                any_defined_comptime_value = true;
                break :elem try o.lowerValue(val);
            } else llvm_poison_elem,
        };
    }
    // This vector is like the result, but runtime elements are replaced with poison.
    const comptime_and_poison: Builder.Value = if (any_defined_comptime_value) vec: {
        break :vec try o.builder.vectorValue(llvm_result_ty, llvm_elem_buf);
    } else try o.builder.poisonValue(llvm_result_ty);

    if (operand_ty.vectorLen(zcu) == mask.len) {
        // input length equals mask/output length, so we lower to one instruction
        for (mask, llvm_elem_buf, 0..) |mask_elem, *llvm_elem, elem_idx| {
            llvm_elem.* = switch (mask_elem.unwrap()) {
                .elem => |idx| try o.builder.intConst(.i32, idx),
                .value => |val| if (!Value.fromInterned(val).isUndef(zcu)) mask_val: {
                    break :mask_val try o.builder.intConst(.i32, mask.len + elem_idx);
                } else llvm_poison_mask_elem,
            };
        }
        return fg.wip.shuffleVector(
            operand,
            comptime_and_poison,
            try o.builder.vectorValue(llvm_mask_ty, llvm_elem_buf),
            "",
        );
    }

    for (mask, llvm_elem_buf) |mask_elem, *llvm_elem| {
        llvm_elem.* = switch (mask_elem.unwrap()) {
            .elem => |idx| try o.builder.intConst(.i32, idx),
            .value => llvm_poison_mask_elem,
        };
    }
    // This vector is like our result, but all comptime-known elements are poison.
    const runtime_and_poison = try fg.wip.shuffleVector(
        operand,
        try o.builder.poisonValue(llvm_operand_ty),
        try o.builder.vectorValue(llvm_mask_ty, llvm_elem_buf),
        "",
    );

    if (!any_defined_comptime_value) {
        // `comptime_and_poison` is just poison; a second shuffle would be a nop.
        return runtime_and_poison;
    }

    // In this second shuffle, the inputs, the mask, and the output all have the same length.
    for (mask, llvm_elem_buf, 0..) |mask_elem, *llvm_elem, elem_idx| {
        llvm_elem.* = switch (mask_elem.unwrap()) {
            .elem => try o.builder.intConst(.i32, elem_idx),
            .value => |val| if (!Value.fromInterned(val).isUndef(zcu)) mask_val: {
                break :mask_val try o.builder.intConst(.i32, mask.len + elem_idx);
            } else llvm_poison_mask_elem,
        };
    }
    // Merge the runtime and comptime elements with the mask we just built.
    return fg.wip.shuffleVector(
        runtime_and_poison,
        comptime_and_poison,
        try o.builder.vectorValue(llvm_mask_ty, llvm_elem_buf),
        "",
    );
}

fn airShuffleTwo(fg: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const gpa = zcu.gpa;

    const unwrapped = fg.air.unwrapShuffleTwo(zcu, inst);

    const mask = unwrapped.mask;
    const llvm_elem_ty = try o.lowerType(unwrapped.result_ty.childType(zcu));
    const llvm_mask_ty = try o.builder.vectorType(.normal, @intCast(mask.len), .i32);
    const llvm_poison_mask_elem = try o.builder.poisonConst(.i32);

    // This is kind of simpler than in `airShuffleOne`. We extend the shorter vector to the
    // length of the longer one with an initial `shufflevector` if necessary, and then do the
    // actual computation with a second `shufflevector`.

    const operand_a_len = fg.typeOf(unwrapped.operand_a).vectorLen(zcu);
    const operand_b_len = fg.typeOf(unwrapped.operand_b).vectorLen(zcu);
    const operand_len: u32 = @max(operand_a_len, operand_b_len);

    // If we need to extend an operand, this is the type that mask will have.
    const llvm_operand_mask_ty = try o.builder.vectorType(.normal, operand_len, .i32);

    const llvm_elem_buf = try gpa.alloc(Builder.Constant, @max(mask.len, operand_len));
    defer gpa.free(llvm_elem_buf);

    const operand_a: Builder.Value = extend: {
        const raw = try fg.resolveInst(unwrapped.operand_a);
        if (operand_a_len == operand_len) break :extend raw;
        // Extend with a `shufflevector`, with a mask `<0, 1, ..., n, poison, poison, ..., poison>`
        const mask_elems = llvm_elem_buf[0..operand_len];
        for (mask_elems[0..operand_a_len], 0..) |*llvm_elem, elem_idx| {
            llvm_elem.* = try o.builder.intConst(.i32, elem_idx);
        }
        @memset(mask_elems[operand_a_len..], llvm_poison_mask_elem);
        const llvm_this_operand_ty = try o.builder.vectorType(.normal, operand_a_len, llvm_elem_ty);
        break :extend try fg.wip.shuffleVector(
            raw,
            try o.builder.poisonValue(llvm_this_operand_ty),
            try o.builder.vectorValue(llvm_operand_mask_ty, mask_elems),
            "",
        );
    };
    const operand_b: Builder.Value = extend: {
        const raw = try fg.resolveInst(unwrapped.operand_b);
        if (operand_b_len == operand_len) break :extend raw;
        // Extend with a `shufflevector`, with a mask `<0, 1, ..., n, poison, poison, ..., poison>`
        const mask_elems = llvm_elem_buf[0..operand_len];
        for (mask_elems[0..operand_b_len], 0..) |*llvm_elem, elem_idx| {
            llvm_elem.* = try o.builder.intConst(.i32, elem_idx);
        }
        @memset(mask_elems[operand_b_len..], llvm_poison_mask_elem);
        const llvm_this_operand_ty = try o.builder.vectorType(.normal, operand_b_len, llvm_elem_ty);
        break :extend try fg.wip.shuffleVector(
            raw,
            try o.builder.poisonValue(llvm_this_operand_ty),
            try o.builder.vectorValue(llvm_operand_mask_ty, mask_elems),
            "",
        );
    };

    // `operand_a` and `operand_b` now have the same length (we've extended the shorter one with
    // an initial shuffle if necessary). Now for the easy bit.

    const mask_elems = llvm_elem_buf[0..mask.len];
    for (mask, mask_elems) |mask_elem, *llvm_mask_elem| {
        llvm_mask_elem.* = switch (mask_elem.unwrap()) {
            .a_elem => |idx| try o.builder.intConst(.i32, idx),
            .b_elem => |idx| try o.builder.intConst(.i32, operand_len + idx),
            .undef => llvm_poison_mask_elem,
        };
    }
    return fg.wip.shuffleVector(
        operand_a,
        operand_b,
        try o.builder.vectorValue(llvm_mask_ty, mask_elems),
        "",
    );
}

/// Reduce a vector by repeatedly applying `llvm_fn` to produce an accumulated result.
///
/// Equivalent to:
///   reduce: {
///     var i: usize = 0;
///     var accum: T = init;
///     while (i < vec.len) : (i += 1) {
///       accum = llvm_fn(accum, vec[i]);
///     }
///     break :reduce accum;
///   }
///
fn buildReducedCall(
    self: *FuncGen,
    llvm_fn: Builder.Function.Index,
    operand_vector: Builder.Value,
    vector_len: usize,
    accum_init: Builder.Value,
) Allocator.Error!Builder.Value {
    const o = self.object;
    const usize_ty = try o.lowerType(.usize);
    const llvm_vector_len = try o.builder.intValue(usize_ty, vector_len);
    const llvm_result_ty = accum_init.typeOfWip(&self.wip);

    // Allocate and initialize our mutable variables
    const i_ptr = try self.buildAlloca(usize_ty, .default);
    _ = try self.wip.store(.normal, try o.builder.intValue(usize_ty, 0), i_ptr, .default);
    const accum_ptr = try self.buildAlloca(llvm_result_ty, .default);
    _ = try self.wip.store(.normal, accum_init, accum_ptr, .default);

    // Setup the loop
    const loop = try self.wip.block(2, "ReduceLoop");
    const loop_exit = try self.wip.block(1, "AfterReduce");
    _ = try self.wip.br(loop);
    {
        self.wip.cursor = .{ .block = loop };

        // while (i < vec.len)
        const i = try self.wip.load(.normal, usize_ty, i_ptr, .default, "");
        const cond = try self.wip.icmp(.ult, i, llvm_vector_len, "");
        const loop_then = try self.wip.block(1, "ReduceLoopThen");

        _ = try self.wip.brCond(cond, loop_then, loop_exit, .none);

        {
            self.wip.cursor = .{ .block = loop_then };

            // accum = f(accum, vec[i]);
            const accum = try self.wip.load(.normal, llvm_result_ty, accum_ptr, .default, "");
            const element = try self.wip.extractElement(operand_vector, i, "");
            const new_accum = try self.wip.call(
                .normal,
                .ccc,
                .none,
                llvm_fn.typeOf(&o.builder),
                llvm_fn.toValue(&o.builder),
                &.{ accum, element },
                "",
            );
            _ = try self.wip.store(.normal, new_accum, accum_ptr, .default);

            // i += 1
            const new_i = try self.wip.bin(.add, i, try o.builder.intValue(usize_ty, 1), "");
            _ = try self.wip.store(.normal, new_i, i_ptr, .default);
            _ = try self.wip.br(loop);
        }
    }

    self.wip.cursor = .{ .block = loop_exit };
    return self.wip.load(.normal, llvm_result_ty, accum_ptr, .default, "");
}

fn airReduce(self: *FuncGen, inst: Air.Inst.Index, fast: Builder.FastMathKind) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const target = zcu.getTarget();

    const reduce = self.air.instructions.items(.data)[@intFromEnum(inst)].reduce;
    const operand = try self.resolveInst(reduce.operand);
    const operand_ty = self.typeOf(reduce.operand);
    const llvm_operand_ty = try o.lowerType(operand_ty);
    const scalar_ty = self.typeOfIndex(inst);
    const llvm_scalar_ty = try o.lowerType(scalar_ty);

    switch (reduce.operation) {
        .And, .Or, .Xor => return self.wip.callIntrinsic(.normal, .none, switch (reduce.operation) {
            .And => .@"vector.reduce.and",
            .Or => .@"vector.reduce.or",
            .Xor => .@"vector.reduce.xor",
            else => unreachable,
        }, &.{llvm_operand_ty}, &.{operand}, ""),
        .Min, .Max => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => return self.wip.callIntrinsic(.normal, .none, switch (reduce.operation) {
                .Min => if (scalar_ty.isSignedInt(zcu))
                    .@"vector.reduce.smin"
                else
                    .@"vector.reduce.umin",
                .Max => if (scalar_ty.isSignedInt(zcu))
                    .@"vector.reduce.smax"
                else
                    .@"vector.reduce.umax",
                else => unreachable,
            }, &.{llvm_operand_ty}, &.{operand}, ""),
            .float => if (intrinsicsAllowed(scalar_ty, target))
                return self.wip.callIntrinsic(fast, .none, switch (reduce.operation) {
                    .Min => .@"vector.reduce.fmin",
                    .Max => .@"vector.reduce.fmax",
                    else => unreachable,
                }, &.{llvm_operand_ty}, &.{operand}, ""),
            else => unreachable,
        },
        .Add, .Mul => switch (scalar_ty.zigTypeTag(zcu)) {
            .int => return self.wip.callIntrinsic(.normal, .none, switch (reduce.operation) {
                .Add => .@"vector.reduce.add",
                .Mul => .@"vector.reduce.mul",
                else => unreachable,
            }, &.{llvm_operand_ty}, &.{operand}, ""),
            .float => if (intrinsicsAllowed(scalar_ty, target))
                return self.wip.callIntrinsic(fast, .none, switch (reduce.operation) {
                    .Add => .@"vector.reduce.fadd",
                    .Mul => .@"vector.reduce.fmul",
                    else => unreachable,
                }, &.{llvm_operand_ty}, &.{ switch (reduce.operation) {
                    .Add => try o.builder.fpValue(llvm_scalar_ty, -0.0),
                    .Mul => try o.builder.fpValue(llvm_scalar_ty, 1.0),
                    else => unreachable,
                }, operand }, ""),
            else => unreachable,
        },
    }

    // Reduction could not be performed with intrinsics.
    // Use a manual loop over a softfloat call instead.
    const float_bits = scalar_ty.floatBits(target);
    const fn_name = switch (reduce.operation) {
        .Min => try o.builder.strtabStringFmt("{s}fmin{s}", .{
            libcFloatPrefix(float_bits), libcFloatSuffix(float_bits),
        }),
        .Max => try o.builder.strtabStringFmt("{s}fmax{s}", .{
            libcFloatPrefix(float_bits), libcFloatSuffix(float_bits),
        }),
        .Add => try o.builder.strtabStringFmt("__add{s}f3", .{
            compilerRtFloatAbbrev(float_bits),
        }),
        .Mul => try o.builder.strtabStringFmt("__mul{s}f3", .{
            compilerRtFloatAbbrev(float_bits),
        }),
        else => unreachable,
    };

    const libc_fn = try o.getLibcFunction(fn_name, &.{ llvm_scalar_ty, llvm_scalar_ty }, llvm_scalar_ty);
    const init_val = switch (llvm_scalar_ty) {
        .i16 => try o.builder.intValue(.i16, @as(i16, @bitCast(
            @as(f16, switch (reduce.operation) {
                .Min, .Max => std.math.nan(f16),
                .Add => -0.0,
                .Mul => 1.0,
                else => unreachable,
            }),
        ))),
        .i80 => try o.builder.intValue(.i80, @as(i80, @bitCast(
            @as(f80, switch (reduce.operation) {
                .Min, .Max => std.math.nan(f80),
                .Add => -0.0,
                .Mul => 1.0,
                else => unreachable,
            }),
        ))),
        .i128 => try o.builder.intValue(.i128, @as(i128, @bitCast(
            @as(f128, switch (reduce.operation) {
                .Min, .Max => std.math.nan(f128),
                .Add => -0.0,
                .Mul => 1.0,
                else => unreachable,
            }),
        ))),
        else => unreachable,
    };
    return self.buildReducedCall(libc_fn, operand, operand_ty.vectorLen(zcu), init_val);
}

fn airAggregateInit(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const result_ty = self.typeOfIndex(inst);
    const len: usize = @intCast(result_ty.arrayLen(zcu));
    const elements: []const Air.Inst.Ref = @ptrCast(self.air.extra.items[ty_pl.payload..][0..len]);
    const llvm_result_ty = try o.lowerType(result_ty);

    switch (result_ty.zigTypeTag(zcu)) {
        .vector => {
            var vector = try o.builder.poisonValue(llvm_result_ty);
            for (elements, 0..) |elem, i| {
                const index_u32 = try o.builder.intValue(.i32, i);
                const llvm_elem = try self.resolveInst(elem);
                vector = try self.wip.insertElement(vector, llvm_elem, index_u32, "");
            }
            return vector;
        },
        .@"struct" => switch (result_ty.containerLayout(zcu)) {
            .@"packed" => {
                const struct_type = ip.loadStructType(result_ty.toIntern());
                const backing_int_ty: Type = .fromInterned(struct_type.packed_backing_int_type);
                const big_bits = backing_int_ty.bitSize(zcu);
                const int_ty = try o.builder.intType(@intCast(big_bits));
                comptime assert(Type.packed_struct_layout_version == 2);
                var running_int = try o.builder.intValue(int_ty, 0);
                var running_bits: u16 = 0;
                for (elements, struct_type.field_types.get(ip)) |elem, field_ty| {
                    if (!Type.fromInterned(field_ty).hasRuntimeBits(zcu)) continue;

                    const non_int_val = try self.resolveInst(elem);
                    const ty_bit_size: u16 = @intCast(Type.fromInterned(field_ty).bitSize(zcu));
                    const small_int_ty = try o.builder.intType(ty_bit_size);
                    const small_int_val = if (Type.fromInterned(field_ty).isPtrAtRuntime(zcu))
                        try self.wip.cast(.ptrtoint, non_int_val, small_int_ty, "")
                    else
                        try self.wip.cast(.bitcast, non_int_val, small_int_ty, "");
                    const shift_rhs = try o.builder.intValue(int_ty, running_bits);
                    const extended_int_val =
                        try self.wip.conv(.unsigned, small_int_val, int_ty, "");
                    const shifted = try self.wip.bin(.shl, extended_int_val, shift_rhs, "");
                    running_int = try self.wip.bin(.@"or", running_int, shifted, "");
                    running_bits += ty_bit_size;
                }
                return running_int;
            },
            .auto, .@"extern" => {
                assert(isByRef(result_ty, zcu));
                // TODO in debug builds init to undef so that the padding will be 0xaa
                // even if we fully populate the fields.
                const struct_align = result_ty.abiAlignment(zcu);
                const alloca_inst = try self.buildAlloca(llvm_result_ty, struct_align.toLlvm());

                for (elements, 0..) |elem, field_index| {
                    if (result_ty.structFieldIsComptime(field_index, zcu)) continue;
                    const field_ty = result_ty.fieldType(field_index, zcu);
                    if (!field_ty.hasRuntimeBits(zcu)) continue;
                    const offset = result_ty.structFieldOffset(field_index, zcu);
                    const field_ptr = try self.ptraddConst(alloca_inst, offset);
                    const field_ptr_align: InternPool.Alignment = switch (offset) {
                        0 => struct_align,
                        else => struct_align.minStrict(.fromLog2Units(@ctz(offset))),
                    };

                    const llvm_field_val = try self.resolveInst(elem);

                    if (isByRef(field_ty, zcu)) {
                        _ = try self.wip.callMemCpy(
                            field_ptr,
                            field_ptr_align.toLlvm(),
                            llvm_field_val,
                            field_ty.abiAlignment(zcu).toLlvm(),
                            try o.builder.intValue(try o.lowerType(.usize), field_ty.abiSize(zcu)),
                            .normal,
                            self.disable_intrinsics,
                        );
                    } else {
                        _ = try self.wip.store(
                            .normal,
                            llvm_field_val,
                            field_ptr,
                            field_ptr_align.toLlvm(),
                        );
                    }
                }

                return alloca_inst;
            },
        },
        .array => {
            assert(isByRef(result_ty, zcu));

            const alignment = result_ty.abiAlignment(zcu).toLlvm();
            const alloca_inst = try self.buildAlloca(llvm_result_ty, alignment);

            const array_info = result_ty.arrayInfo(zcu);

            const elem_size = array_info.elem_type.abiSize(zcu);

            for (elements, 0..) |elem, i| {
                const elem_ptr = try self.ptraddConst(alloca_inst, elem_size * i);
                const llvm_elem = try self.resolveInst(elem);
                try self.store(elem_ptr, .none, llvm_elem, array_info.elem_type);
            }
            if (array_info.sentinel) |sent_val| {
                const elem_ptr = try self.ptraddConst(alloca_inst, elem_size * array_info.len);
                const llvm_elem = try self.resolveValue(sent_val);
                try self.store(elem_ptr, .none, llvm_elem.toValue(), array_info.elem_type);
            }

            return alloca_inst;
        },
        else => unreachable,
    }
}

fn airUnionInit(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const ty_pl = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = self.air.extraData(Air.UnionInit, ty_pl.payload).data;
    const union_ty = self.typeOfIndex(inst);
    const union_llvm_ty = try o.lowerType(union_ty);
    const union_obj = zcu.typeToUnion(union_ty).?;

    assert(union_obj.layout != .@"packed");

    const layout = Type.getUnionLayout(union_obj, zcu);

    assert(layout.payload_size != 0); // otherwise the value would be comptime-known
    assert(isByRef(union_ty, zcu));

    const alignment = layout.abi_align.toLlvm();
    const result_ptr = try self.buildAlloca(union_llvm_ty, alignment);
    const llvm_payload = try self.resolveInst(extra.init);
    const field_ty = Type.fromInterned(union_obj.field_types.get(ip)[extra.field_index]);
    assert(field_ty.hasRuntimeBits(zcu));

    {
        const payload_ptr = try self.ptraddConst(result_ptr, layout.payloadOffset());
        try self.store(payload_ptr, layout.payload_align, llvm_payload, field_ty);
    }

    if (layout.tag_size != 0) {
        const loaded_enum = ip.loadEnumType(union_obj.enum_tag_type);
        const llvm_tag_val = switch (loaded_enum.field_values.getOrNone(ip, extra.field_index)) {
            .none => try o.builder.intConst(
                try o.lowerType(.fromInterned(union_obj.enum_tag_type)),
                extra.field_index, // auto-numbered
            ),
            else => |tag_val_ip| try o.lowerValue(tag_val_ip),
        };
        const tag_ptr = try self.ptraddConst(result_ptr, layout.tagOffset());
        _ = try self.wip.store(.normal, llvm_tag_val.toValue(), tag_ptr, layout.tag_align.toLlvm());
    }

    return result_ptr;
}

fn airPrefetch(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const o = self.object;
    const prefetch = self.air.instructions.items(.data)[@intFromEnum(inst)].prefetch;

    comptime assert(@intFromEnum(std.builtin.PrefetchOptions.Rw.read) == 0);
    comptime assert(@intFromEnum(std.builtin.PrefetchOptions.Rw.write) == 1);

    comptime assert(prefetch.locality >= 0);
    comptime assert(prefetch.locality <= 3);

    comptime assert(@intFromEnum(std.builtin.PrefetchOptions.Cache.instruction) == 0);
    comptime assert(@intFromEnum(std.builtin.PrefetchOptions.Cache.data) == 1);

    // LLVM fails during codegen of instruction cache prefetchs for these architectures.
    // This is an LLVM bug as the prefetch intrinsic should be a noop if not supported
    // by the target.
    // To work around this, don't emit llvm.prefetch in this case.
    // See https://bugs.llvm.org/show_bug.cgi?id=21037
    const zcu = self.object.zcu;
    const target = zcu.getTarget();
    switch (prefetch.cache) {
        .instruction => switch (target.cpu.arch) {
            .x86_64,
            .x86,
            .powerpc,
            .powerpcle,
            .powerpc64,
            .powerpc64le,
            => return .none,
            .arm, .armeb, .thumb, .thumbeb => {
                switch (prefetch.rw) {
                    .write => return .none,
                    else => {},
                }
            },
            else => {},
        },
        .data => {},
    }

    _ = try self.wip.callIntrinsic(.normal, .none, .prefetch, &.{.ptr}, &.{
        try self.sliceOrArrayPtr(try self.resolveInst(prefetch.ptr), self.typeOf(prefetch.ptr)),
        try o.builder.intValue(.i32, prefetch.rw),
        try o.builder.intValue(.i32, prefetch.locality),
        try o.builder.intValue(.i32, prefetch.cache),
    }, "");
    return .none;
}

fn airAddrSpaceCast(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const ty_op = self.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const inst_ty = self.typeOfIndex(inst);
    const operand = try self.resolveInst(ty_op.operand);
    return self.wip.cast(.addrspacecast, operand, try self.object.lowerType(inst_ty), "");
}

fn workIntrinsic(
    self: *FuncGen,
    dimension: u32,
    default: u32,
    comptime basename: []const u8,
) Allocator.Error!Builder.Value {
    return self.wip.callIntrinsic(.normal, .none, switch (dimension) {
        0 => @field(Builder.Intrinsic, basename ++ ".x"),
        1 => @field(Builder.Intrinsic, basename ++ ".y"),
        2 => @field(Builder.Intrinsic, basename ++ ".z"),
        else => return self.object.builder.intValue(.i32, default),
    }, &.{}, &.{}, "");
}

fn airWorkItemId(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const target = self.object.zcu.getTarget();

    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const dimension = pl_op.payload;

    return switch (target.cpu.arch) {
        .amdgcn => self.workIntrinsic(dimension, 0, "amdgcn.workitem.id"),
        .nvptx, .nvptx64 => self.workIntrinsic(dimension, 0, "nvvm.read.ptx.sreg.tid"),
        else => unreachable,
    };
}

fn airWorkGroupSize(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const target = self.object.zcu.getTarget();

    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const dimension = pl_op.payload;

    switch (target.cpu.arch) {
        .amdgcn => {
            if (dimension >= 3) return .@"1";

            // Fetch the dispatch pointer, which points to this structure:
            // https://github.com/RadeonOpenCompute/ROCR-Runtime/blob/adae6c61e10d371f7cbc3d0e94ae2c070cab18a4/src/inc/hsa.h#L2913
            const dispatch_ptr =
                try self.wip.callIntrinsic(.normal, .none, .@"amdgcn.dispatch.ptr", &.{}, &.{}, "");

            // Load the work_group_* member from the struct as u16.
            // Just treat the dispatch pointer as an array of u16 to keep things simple.
            const workgroup_size_ptr = try self.ptraddConst(dispatch_ptr, (2 + dimension) * 2);
            return self.wip.load(.normal, .i16, workgroup_size_ptr, comptime .fromByteUnits(2), "");
        },
        .nvptx, .nvptx64 => {
            return self.workIntrinsic(dimension, 1, "nvvm.read.ptx.sreg.ntid");
        },
        else => unreachable,
    }
}

fn airWorkGroupId(self: *FuncGen, inst: Air.Inst.Index) Allocator.Error!Builder.Value {
    const target = self.object.zcu.getTarget();

    const pl_op = self.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const dimension = pl_op.payload;

    return switch (target.cpu.arch) {
        .amdgcn => self.workIntrinsic(dimension, 0, "amdgcn.workgroup.id"),
        .nvptx, .nvptx64 => self.workIntrinsic(dimension, 0, "nvvm.read.ptx.sreg.ctaid"),
        else => unreachable,
    };
}

/// Assumes that `Type.optionalReprIsPayload` is `false` for `opt_ty` and that the payload has bits.
fn optCmpNull(
    self: *FuncGen,
    cond: Builder.IntegerCondition,
    opt_ty: Type,
    opt_ptr: Builder.Value,
    access_kind: Builder.MemoryAccessKind,
) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    assert(isByRef(opt_ty, zcu));
    comptime assert(optional_layout_version == 3);
    // Non-null bit is always after the payload, with no padding because it has alignment 1.
    const non_null_ptr = try self.ptraddConst(opt_ptr, opt_ty.optionalChild(zcu).abiSize(zcu));
    const non_null = try self.wip.load(access_kind, .i8, non_null_ptr, .default, "");
    return self.wip.icmp(cond, non_null, try self.object.builder.intValue(.i8, 0), "");
}

/// Assumes that `Type.optionalReprIsPayload` is `false` for `opt_ty` and that the payload has bits.
fn optPayloadHandle(
    fg: *FuncGen,
    opt_ptr: Builder.Value,
    opt_ty: Type,
    can_elide_load: bool,
) Allocator.Error!Builder.Value {
    const zcu = fg.object.zcu;
    assert(isByRef(opt_ty, zcu));
    const payload_ty = opt_ty.optionalChild(zcu);

    // Payload is first field so always at the same address as the optional itself.
    const payload_ptr = opt_ptr;

    const payload_align = payload_ty.abiAlignment(zcu).toLlvm();
    if (isByRef(payload_ty, zcu)) {
        if (can_elide_load) return payload_ptr;
        return fg.loadByRef(payload_ptr, payload_ty, payload_align, .normal);
    } else {
        return fg.loadTruncate(.normal, payload_ty, payload_ptr, payload_align);
    }
}

fn fieldPtr(
    self: *FuncGen,
    aggregate_ptr: Builder.Value,
    aggregate_ptr_ty: Type,
    field_index: u32,
) Allocator.Error!Builder.Value {
    const zcu = self.object.zcu;
    const aggregate_ty = aggregate_ptr_ty.childType(zcu);
    if (aggregate_ty.containerLayout(zcu) == .@"packed") {
        // A pointer to a bitpack field is equivalent to a pointer to the whole bitpack; the
        // bit offset is represented in the pointer *type*.
        return aggregate_ptr;
    }
    const offset: u64 = switch (aggregate_ty.zigTypeTag(zcu)) {
        .@"struct" => aggregate_ty.structFieldOffset(field_index, zcu),
        .@"union" => aggregate_ty.unionGetLayout(zcu).payloadOffset(),
        else => unreachable,
    };
    return self.ptraddConst(aggregate_ptr, offset);
}

/// Load a value and, if needed, mask out padding bits for non byte-sized integer values.
fn loadTruncate(
    fg: *FuncGen,
    access_kind: Builder.MemoryAccessKind,
    payload_ty: Type,
    payload_ptr: Builder.Value,
    payload_alignment: Builder.Alignment,
) Allocator.Error!Builder.Value {
    // from https://llvm.org/docs/LangRef.html#load-instruction :
    // "When loading a value of a type like i20 with a size that is not an integral number of bytes, the result is undefined if the value was not originally written using a store of the same type. "
    // => so load the byte aligned value and trunc the unwanted bits.

    const o = fg.object;
    const zcu = o.zcu;
    const payload_llvm_ty = try o.lowerType(payload_ty);
    const abi_size = payload_ty.abiSize(zcu);

    const load_llvm_ty = if (payload_ty.isAbiInt(zcu))
        try o.builder.intType(@intCast(abi_size * 8))
    else
        payload_llvm_ty;
    const loaded = try fg.wip.load(access_kind, load_llvm_ty, payload_ptr, payload_alignment, "");
    const shifted = if (payload_llvm_ty != load_llvm_ty and zcu.getTarget().cpu.arch.endian() == .big)
        try fg.wip.bin(.lshr, loaded, try o.builder.intValue(
            load_llvm_ty,
            (payload_ty.abiSize(zcu) - (std.math.divCeil(u64, payload_ty.bitSize(zcu), 8) catch unreachable)) * 8,
        ), "")
    else
        loaded;

    return fg.wip.conv(.unneeded, shifted, payload_llvm_ty, "");
}

/// Load a by-ref type by constructing a new alloca and performing a memcpy.
fn loadByRef(
    fg: *FuncGen,
    ptr: Builder.Value,
    pointee_type: Type,
    ptr_alignment: Builder.Alignment,
    access_kind: Builder.MemoryAccessKind,
) Allocator.Error!Builder.Value {
    const o = fg.object;
    const pointee_llvm_ty = try o.lowerType(pointee_type);
    const result_align = InternPool.Alignment.fromLlvm(ptr_alignment)
        .max(pointee_type.abiAlignment(o.zcu)).toLlvm();
    const result_ptr = try fg.buildAlloca(pointee_llvm_ty, result_align);
    const size_bytes = pointee_type.abiSize(o.zcu);
    _ = try fg.wip.callMemCpy(
        result_ptr,
        result_align,
        ptr,
        ptr_alignment,
        try o.builder.intValue(try o.lowerType(.usize), size_bytes),
        access_kind,
        fg.disable_intrinsics,
    );
    return result_ptr;
}

/// If `isByRef` returns `true` for `elem_ty`, this still performs a copy by memcpy'ing the value
/// into a new alloca.
fn load(
    fg: *FuncGen,
    ptr: Builder.Value,
    elem_ty: Type,
    ptr_alignment: Builder.Alignment,
    access_kind: Builder.MemoryAccessKind,
) Allocator.Error!Builder.Value {
    const zcu = fg.object.zcu;
    if (isByRef(elem_ty, zcu)) {
        return fg.loadByRef(ptr, elem_ty, ptr_alignment, access_kind);
    } else {
        return fg.loadTruncate(access_kind, elem_ty, ptr, ptr_alignment);
    }
}

fn storeFull(
    self: *FuncGen,
    ptr: Builder.Value,
    ptr_ty: Type,
    elem: Builder.Value,
    ordering: Builder.AtomicOrdering,
) Allocator.Error!void {
    const o = self.object;
    const zcu = o.zcu;
    const info = ptr_ty.ptrInfo(zcu);
    const elem_ty = Type.fromInterned(info.child);
    if (!elem_ty.hasRuntimeBits(zcu)) {
        return;
    }
    const ptr_alignment = ptr_ty.ptrAlignment(zcu).toLlvm();
    const access_kind: Builder.MemoryAccessKind =
        if (info.flags.is_volatile) .@"volatile" else .normal;

    if (info.flags.vector_index != .none) {
        const index_u32 = try o.builder.intValue(.i32, info.flags.vector_index);
        const vec_elem_ty = try o.lowerType(elem_ty);
        const vec_ty = try o.builder.vectorType(.normal, info.packed_offset.host_size, vec_elem_ty);

        const loaded_vector = try self.wip.load(.normal, vec_ty, ptr, ptr_alignment, "");

        const modified_vector = try self.wip.insertElement(loaded_vector, elem, index_u32, "");

        assert(ordering == .none);
        _ = try self.wip.store(access_kind, modified_vector, ptr, ptr_alignment);
        return;
    }

    if (info.packed_offset.host_size != 0) {
        const containing_int_ty = try o.builder.intType(@intCast(info.packed_offset.host_size * 8));
        assert(ordering == .none);
        const containing_int =
            try self.wip.load(.normal, containing_int_ty, ptr, ptr_alignment, "");
        const elem_bits = ptr_ty.childType(zcu).bitSize(zcu);
        const shift_amt = try o.builder.intConst(containing_int_ty, info.packed_offset.bit_offset);
        // Convert to equally-sized integer type in order to perform the bit
        // operations on the value to store
        const value_bits_type = try o.builder.intType(@intCast(elem_bits));
        const value_bits = if (elem_ty.isPtrAtRuntime(zcu))
            try self.wip.cast(.ptrtoint, elem, value_bits_type, "")
        else
            try self.wip.cast(.bitcast, elem, value_bits_type, "");

        const mask_val = blk: {
            const zext = try self.wip.cast(
                .zext,
                try o.builder.intValue(value_bits_type, -1),
                containing_int_ty,
                "",
            );
            const shl = try self.wip.bin(.shl, zext, shift_amt.toValue(), "");
            break :blk try self.wip.bin(
                .xor,
                shl,
                try o.builder.intValue(containing_int_ty, -1),
                "",
            );
        };

        const anded_containing_int = try self.wip.bin(.@"and", containing_int, mask_val, "");
        const extended_value = try self.wip.cast(.zext, value_bits, containing_int_ty, "");
        const shifted_value = try self.wip.bin(.shl, extended_value, shift_amt.toValue(), "");
        const ored_value = try self.wip.bin(.@"or", shifted_value, anded_containing_int, "");

        assert(ordering == .none);
        _ = try self.wip.store(access_kind, ored_value, ptr, ptr_alignment);
        return;
    }
    if (!isByRef(elem_ty, zcu)) {
        _ = try self.wip.storeAtomic(
            access_kind,
            elem,
            ptr,
            self.sync_scope,
            ordering,
            ptr_alignment,
        );
        return;
    }
    assert(ordering == .none);
    _ = try self.wip.callMemCpy(
        ptr,
        ptr_alignment,
        elem,
        elem_ty.abiAlignment(zcu).toLlvm(),
        try o.builder.intValue(try o.lowerType(.usize), elem_ty.abiSize(zcu)),
        access_kind,
        self.disable_intrinsics,
    );
}

/// Non-atomic, non-volatile, non-packed store.
fn store(
    fg: *FuncGen,
    ptr: Builder.Value,
    ptr_align: InternPool.Alignment,
    elem: Builder.Value,
    elem_ty: Type,
) Allocator.Error!void {
    const o = fg.object;
    const zcu = o.zcu;
    const llvm_ptr_align = switch (ptr_align) {
        .none => elem_ty.abiAlignment(zcu).toLlvm(),
        else => ptr_align.toLlvm(),
    };
    if (isByRef(elem_ty, zcu)) {
        _ = try fg.wip.callMemCpy(
            ptr,
            llvm_ptr_align,
            elem,
            elem_ty.abiAlignment(zcu).toLlvm(),
            try o.builder.intValue(
                try o.lowerType(.usize),
                elem_ty.abiSize(zcu),
            ),
            .normal,
            fg.disable_intrinsics,
        );
    } else {
        _ = try fg.wip.storeAtomic(
            .normal,
            elem,
            ptr,
            fg.sync_scope,
            .none,
            llvm_ptr_align,
        );
    }
}

fn valgrindMarkUndef(fg: *FuncGen, ptr: Builder.Value, len: Builder.Value) Allocator.Error!void {
    const VG_USERREQ__MAKE_MEM_UNDEFINED = 1296236545;
    const o = fg.object;
    const usize_ty = try o.lowerType(.usize);
    const zero = try o.builder.intValue(usize_ty, 0);
    const req = try o.builder.intValue(usize_ty, VG_USERREQ__MAKE_MEM_UNDEFINED);
    const ptr_as_usize = try fg.wip.cast(.ptrtoint, ptr, usize_ty, "");
    _ = try valgrindClientRequest(fg, zero, req, ptr_as_usize, len, zero, zero, zero);
}

fn valgrindClientRequest(
    fg: *FuncGen,
    default_value: Builder.Value,
    request: Builder.Value,
    a1: Builder.Value,
    a2: Builder.Value,
    a3: Builder.Value,
    a4: Builder.Value,
    a5: Builder.Value,
) Allocator.Error!Builder.Value {
    const o = fg.object;
    const zcu = o.zcu;
    const target = zcu.getTarget();
    if (!target_util.hasValgrindSupport(target, .stage2_llvm)) return default_value;

    const llvm_usize = try o.lowerType(.usize);
    const usize_alignment = Type.usize.abiAlignment(zcu).toLlvm();

    const array_llvm_ty = try o.builder.arrayType(6, llvm_usize);
    const array_ptr = if (fg.valgrind_client_request_array == .none) a: {
        const array_ptr = try fg.buildAlloca(array_llvm_ty, usize_alignment);
        fg.valgrind_client_request_array = array_ptr;
        break :a array_ptr;
    } else fg.valgrind_client_request_array;
    const array_elements = [_]Builder.Value{ request, a1, a2, a3, a4, a5 };
    for (array_elements, 0..) |elem, i| {
        const elem_ptr = try fg.ptraddConst(array_ptr, i * Type.usize.abiSize(zcu));
        _ = try fg.wip.store(.normal, elem, elem_ptr, usize_alignment);
    }

    const arch_specific: struct {
        template: [:0]const u8,
        constraints: [:0]const u8,
    } = switch (target.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => .{
            .template =
            \\ mov r12, r12, ror #3  ; mov r12, r12, ror #13
            \\ mov r12, r12, ror #29 ; mov r12, r12, ror #19
            \\ orr r10, r10, r10
            ,
            .constraints = "={r3},{r4},{r3},~{cc},~{memory}",
        },
        .aarch64, .aarch64_be => .{
            .template =
            \\ ror x12, x12, #3  ; ror x12, x12, #13
            \\ ror x12, x12, #51 ; ror x12, x12, #61
            \\ orr x10, x10, x10
            ,
            .constraints = "={x3},{x4},{x3},~{cc},~{memory}",
        },
        .mips, .mipsel => .{
            .template =
            \\ srl $$0,  $$0,  13
            \\ srl $$0,  $$0,  29
            \\ srl $$0,  $$0,  3
            \\ srl $$0,  $$0,  19
            \\ or  $$13, $$13, $$13
            ,
            .constraints = "={$11},{$12},{$11},~{memory},~{$1}",
        },
        .mips64, .mips64el => .{
            .template =
            \\ dsll $$0,  $$0,  3    ; dsll $$0, $$0, 13
            \\ dsll $$0,  $$0,  29   ; dsll $$0, $$0, 19
            \\ or   $$13, $$13, $$13
            ,
            .constraints = "={$11},{$12},{$11},~{memory},~{$1}",
        },
        .powerpc, .powerpcle => .{
            .template =
            \\ rlwinm 0, 0, 3,  0, 31 ; rlwinm 0, 0, 13, 0, 31
            \\ rlwinm 0, 0, 29, 0, 31 ; rlwinm 0, 0, 19, 0, 31
            \\ or     1, 1, 1
            ,
            .constraints = "={r3},{r4},{r3},~{cc},~{memory}",
        },
        .powerpc64, .powerpc64le => .{
            .template =
            \\ rotldi 0, 0, 3  ; rotldi 0, 0, 13
            \\ rotldi 0, 0, 61 ; rotldi 0, 0, 51
            \\ or     1, 1, 1
            ,
            .constraints = "={r3},{r4},{r3},~{cc},~{memory}",
        },
        .riscv64 => .{
            .template =
            \\ .option push
            \\ .option norvc
            \\ srli zero, zero, 3
            \\ srli zero, zero, 13
            \\ srli zero, zero, 51
            \\ srli zero, zero, 61
            \\ or   a0,   a0,   a0
            \\ .option pop
            ,
            .constraints = "={a3},{a4},{a3},~{cc},~{memory}",
        },
        .s390x => .{
            .template =
            \\ lr %r15, %r15
            \\ lr %r1,  %r1
            \\ lr %r2,  %r2
            \\ lr %r3,  %r3
            \\ lr %r2,  %r2
            ,
            .constraints = "={r3},{r2},{r3},~{cc},~{memory}",
        },
        .x86 => .{
            .template =
            \\ roll  $$3,  %edi ; roll $$13, %edi
            \\ roll  $$61, %edi ; roll $$51, %edi
            \\ xchgl %ebx, %ebx
            ,
            .constraints = "={edx},{eax},{edx},~{cc},~{memory},~{dirflag},~{fpsr},~{flags}",
        },
        .x86_64 => .{
            .template =
            \\ rolq  $$3,  %rdi ; rolq $$13, %rdi
            \\ rolq  $$61, %rdi ; rolq $$51, %rdi
            \\ xchgq %rbx, %rbx
            ,
            .constraints = "={rdx},{rax},{rdx},~{cc},~{memory},~{dirflag},~{fpsr},~{flags}",
        },
        else => unreachable,
    };

    return fg.wip.callAsm(
        .none,
        try o.builder.fnType(llvm_usize, &.{ llvm_usize, llvm_usize }, .normal),
        .{ .sideeffect = true },
        try o.builder.string(arch_specific.template),
        try o.builder.string(arch_specific.constraints),
        &.{ try fg.wip.cast(.ptrtoint, array_ptr, llvm_usize, ""), default_value },
        "",
    );
}

fn typeOf(fg: *FuncGen, inst: Air.Inst.Ref) Type {
    const zcu = fg.object.zcu;
    return fg.air.typeOf(inst, &zcu.intern_pool);
}

fn typeOfIndex(fg: *FuncGen, inst: Air.Inst.Index) Type {
    const zcu = fg.object.zcu;
    return fg.air.typeOfIndex(inst, &zcu.intern_pool);
}

const ParamTypeIterator = struct {
    object: *Object,
    fn_info: InternPool.Key.FuncType,
    zig_index: u32,
    llvm_index: u32,
    types_len: u32,
    types_buffer: [8]Builder.Type,
    byval_attr: bool,

    const Lowering = union(enum) {
        no_bits,
        byval,
        byref,
        byref_mut,
        abi_sized_int,
        multiple_llvm_types,
        slice,
        float_array: u8,
        i32_array: u8,
        i64_array: u8,
    };

    pub fn next(it: *ParamTypeIterator) Allocator.Error!?Lowering {
        if (it.zig_index >= it.fn_info.param_types.len) return null;
        const ip = &it.object.zcu.intern_pool;
        const ty = it.fn_info.param_types.get(ip)[it.zig_index];
        it.byval_attr = false;
        return nextInner(it, Type.fromInterned(ty));
    }

    /// `airCall` uses this instead of `next` so that it can take into account variadic functions.
    fn nextCall(it: *ParamTypeIterator, fg: *FuncGen, args: []const Air.Inst.Ref) Allocator.Error!?Lowering {
        const ip = &it.object.zcu.intern_pool;
        if (it.zig_index >= it.fn_info.param_types.len) {
            if (it.zig_index >= args.len) {
                return null;
            } else {
                return nextInner(it, fg.typeOf(args[it.zig_index]));
            }
        } else {
            return nextInner(it, Type.fromInterned(it.fn_info.param_types.get(ip)[it.zig_index]));
        }
    }

    fn nextInner(it: *ParamTypeIterator, ty: Type) Allocator.Error!?Lowering {
        const zcu = it.object.zcu;
        const target = zcu.getTarget();

        if (!ty.hasRuntimeBits(zcu)) {
            it.zig_index += 1;
            return .no_bits;
        }
        switch (it.fn_info.cc) {
            .@"inline" => unreachable,
            .auto => {
                it.zig_index += 1;
                it.llvm_index += 1;
                if (ty.isSlice(zcu) or
                    (ty.zigTypeTag(zcu) == .optional and ty.optionalChild(zcu).isSlice(zcu) and !ty.ptrAllowsZero(zcu)))
                {
                    it.llvm_index += 1;
                    return .slice;
                } else if (isByRef(ty, zcu)) {
                    return .byref;
                } else if (target.cpu.arch.isX86() and
                    !target.cpu.has(.x86, .evex512) and
                    ty.totalVectorBits(zcu) >= 512)
                {
                    // As of LLVM 18, passing a vector byval with fastcc that is 512 bits or more returns
                    // "512-bit vector arguments require 'evex512' for AVX512"
                    return .byref;
                } else {
                    return .byval;
                }
            },
            .async => {
                @panic("TODO implement async function lowering in the LLVM backend");
            },
            .x86_64_sysv => return it.nextSystemV(ty),
            .x86_64_win => return it.nextWin64(ty),
            .x86_stdcall => {
                it.zig_index += 1;
                it.llvm_index += 1;

                if (isScalar(zcu, ty)) {
                    return .byval;
                } else {
                    it.byval_attr = true;
                    return .byref;
                }
            },
            .aarch64_aapcs, .aarch64_aapcs_darwin, .aarch64_aapcs_win => {
                it.zig_index += 1;
                it.llvm_index += 1;
                switch (aarch64_c_abi.classifyType(ty, zcu)) {
                    .memory => return .byref_mut,
                    .float_array => |len| return Lowering{ .float_array = len },
                    .byval => return .byval,
                    .integer => {
                        it.types_len = 1;
                        it.types_buffer[0] = .i64;
                        return .multiple_llvm_types;
                    },
                    .double_integer => return Lowering{ .i64_array = 2 },
                }
            },
            .arm_aapcs, .arm_aapcs_vfp => {
                it.zig_index += 1;
                it.llvm_index += 1;
                switch (arm_c_abi.classifyType(ty, zcu, .arg)) {
                    .memory => {
                        it.byval_attr = true;
                        return .byref;
                    },
                    .byval => return .byval,
                    .i32_array => |size| return Lowering{ .i32_array = size },
                    .i64_array => |size| return Lowering{ .i64_array = size },
                }
            },
            .mips_o32 => {
                it.zig_index += 1;
                it.llvm_index += 1;
                switch (mips_c_abi.classifyType(ty, zcu, .arg)) {
                    .memory => {
                        it.byval_attr = true;
                        return .byref;
                    },
                    .byval => return .byval,
                    .i32_array => |size| return Lowering{ .i32_array = size },
                }
            },
            .riscv64_lp64, .riscv32_ilp32 => {
                it.zig_index += 1;
                it.llvm_index += 1;
                switch (riscv_c_abi.classifyType(ty, zcu)) {
                    .memory => return .byref_mut,
                    .byval => return .byval,
                    .integer => return .abi_sized_int,
                    .double_integer => return Lowering{ .i64_array = 2 },
                    .fields => {
                        it.types_len = 0;
                        for (0..ty.structFieldCount(zcu)) |field_index| {
                            const field_ty = ty.fieldType(field_index, zcu);
                            if (!field_ty.hasRuntimeBits(zcu)) continue;
                            it.types_buffer[it.types_len] = try it.object.lowerType(field_ty);
                            it.types_len += 1;
                        }
                        it.llvm_index += it.types_len - 1;
                        return .multiple_llvm_types;
                    },
                }
            },
            .wasm_mvp => switch (wasm_c_abi.classifyType(ty, zcu)) {
                .direct => |scalar_ty| {
                    if (isScalar(zcu, ty)) {
                        it.zig_index += 1;
                        it.llvm_index += 1;
                        return .byval;
                    } else {
                        var types_buffer: [8]Builder.Type = undefined;
                        types_buffer[0] = try it.object.lowerType(scalar_ty);
                        it.types_buffer = types_buffer;
                        it.types_len = 1;
                        it.llvm_index += 1;
                        it.zig_index += 1;
                        return .multiple_llvm_types;
                    }
                },
                .indirect => {
                    it.zig_index += 1;
                    it.llvm_index += 1;
                    it.byval_attr = true;
                    return .byref;
                },
            },
            // TODO investigate other callconvs
            else => {
                it.zig_index += 1;
                it.llvm_index += 1;
                return .byval;
            },
        }
    }

    fn nextWin64(it: *ParamTypeIterator, ty: Type) ?Lowering {
        const zcu = it.object.zcu;
        switch (x86_64_abi.classifyWindows(ty, zcu, zcu.getTarget(), .arg)) {
            .integer => {
                if (isScalar(zcu, ty)) {
                    it.zig_index += 1;
                    it.llvm_index += 1;
                    return .byval;
                } else {
                    it.zig_index += 1;
                    it.llvm_index += 1;
                    return .abi_sized_int;
                }
            },
            .win_i128 => {
                it.zig_index += 1;
                it.llvm_index += 1;
                return .byref;
            },
            .memory => {
                it.zig_index += 1;
                it.llvm_index += 1;
                return .byref_mut;
            },
            .sse => {
                it.zig_index += 1;
                it.llvm_index += 1;
                return .byval;
            },
            else => unreachable,
        }
    }

    fn nextSystemV(it: *ParamTypeIterator, ty: Type) Allocator.Error!?Lowering {
        const zcu = it.object.zcu;
        const ip = &zcu.intern_pool;
        ty.assertHasLayout(zcu);
        const classes = x86_64_abi.classifySystemV(ty, zcu, zcu.getTarget(), .arg);
        if (classes[0] == .memory) {
            it.zig_index += 1;
            it.llvm_index += 1;
            it.byval_attr = true;
            return .byref;
        }
        if (isScalar(zcu, ty)) {
            it.zig_index += 1;
            it.llvm_index += 1;
            return .byval;
        }
        var types_index: u32 = 0;
        var types_buffer: [8]Builder.Type = undefined;
        for (classes) |class| {
            switch (class) {
                .integer => {
                    types_buffer[types_index] = .i64;
                    types_index += 1;
                },
                .sse => {
                    types_buffer[types_index] = .double;
                    types_index += 1;
                },
                .sseup => {
                    if (types_buffer[types_index - 1] == .double) {
                        types_buffer[types_index - 1] = .fp128;
                    } else {
                        types_buffer[types_index] = .double;
                        types_index += 1;
                    }
                },
                .float => {
                    types_buffer[types_index] = .float;
                    types_index += 1;
                },
                .float_combine => {
                    types_buffer[types_index] = try it.object.builder.vectorType(.normal, 2, .float);
                    types_index += 1;
                },
                .x87 => {
                    it.zig_index += 1;
                    it.llvm_index += 1;
                    it.byval_attr = true;
                    return .byref;
                },
                .x87up => unreachable,
                .none => break,
                .memory => unreachable, // handled above
                .win_i128 => unreachable, // windows only
                .integer_per_element => {
                    @panic("TODO");
                },
            }
        }
        const first_non_integer = std.mem.indexOfNone(x86_64_abi.Class, &classes, &.{.integer});
        if (first_non_integer == null or classes[first_non_integer.?] == .none) {
            assert(first_non_integer orelse classes.len == types_index);
            if (types_index == 1) {
                it.zig_index += 1;
                it.llvm_index += 1;
                return .abi_sized_int;
            }
            if (it.llvm_index + types_index > 6) {
                it.zig_index += 1;
                it.llvm_index += 1;
                it.byval_attr = true;
                return .byref;
            }
            switch (ip.indexToKey(ty.toIntern())) {
                .struct_type => {
                    const size = ty.abiSize(zcu);
                    assert((std.math.divCeil(u64, size, 8) catch unreachable) == types_index);
                    if (size % 8 > 0) {
                        types_buffer[types_index - 1] =
                            try it.object.builder.intType(@intCast(size % 8 * 8));
                    }
                },
                else => {},
            }
        }
        it.types_len = types_index;
        it.types_buffer = types_buffer;
        it.llvm_index += types_index;
        it.zig_index += 1;
        return .multiple_llvm_types;
    }
};
pub fn iterateParamTypes(object: *Object, fn_info: InternPool.Key.FuncType) ParamTypeIterator {
    return .{
        .object = object,
        .fn_info = fn_info,
        .zig_index = 0,
        .llvm_index = 0,
        .types_len = 0,
        .types_buffer = undefined,
        .byval_attr = false,
    };
}

fn returnTypeByRef(zcu: *Zcu, target: *const std.Target, ty: Type) bool {
    if (isByRef(ty, zcu)) {
        return true;
    } else if (target.cpu.arch.isX86() and
        !target.cpu.has(.x86, .evex512) and
        ty.totalVectorBits(zcu) >= 512)
    {
        // As of LLVM 18, passing a vector byval with fastcc that is 512 bits or more returns
        // "512-bit vector arguments require 'evex512' for AVX512"
        return true;
    } else {
        return false;
    }
}

pub fn firstParamSRet(fn_info: InternPool.Key.FuncType, zcu: *Zcu, target: *const std.Target) bool {
    const return_type = Type.fromInterned(fn_info.return_type);
    if (!return_type.hasRuntimeBits(zcu)) return false;

    return switch (fn_info.cc) {
        .auto => returnTypeByRef(zcu, target, return_type),
        .x86_64_sysv => firstParamSRetSystemV(return_type, zcu, target),
        .x86_64_win => x86_64_abi.classifyWindows(return_type, zcu, target, .ret) == .memory,
        .x86_sysv, .x86_win => isByRef(return_type, zcu),
        .x86_stdcall => !isScalar(zcu, return_type),
        .wasm_mvp => wasm_c_abi.classifyType(return_type, zcu) == .indirect,
        .aarch64_aapcs,
        .aarch64_aapcs_darwin,
        .aarch64_aapcs_win,
        => aarch64_c_abi.classifyType(return_type, zcu) == .memory,
        .arm_aapcs, .arm_aapcs_vfp => switch (arm_c_abi.classifyType(return_type, zcu, .ret)) {
            .memory, .i64_array => true,
            .i32_array => |size| size != 1,
            .byval => false,
        },
        .riscv64_lp64, .riscv32_ilp32 => riscv_c_abi.classifyType(return_type, zcu) == .memory,
        .mips_o32 => switch (mips_c_abi.classifyType(return_type, zcu, .ret)) {
            .memory, .i32_array => true,
            .byval => false,
        },
        else => false, // TODO: investigate other targets/callconvs
    };
}

fn firstParamSRetSystemV(ty: Type, zcu: *Zcu, target: *const std.Target) bool {
    const class = x86_64_abi.classifySystemV(ty, zcu, target, .ret);
    if (class[0] == .memory) return true;
    if (class[0] == .x87 and class[2] != .none) return true;
    return false;
}

/// In order to support the C calling convention, some return types need to be lowered
/// completely differently in the function prototype to honor the C ABI, and then
/// be effectively bitcasted to the actual return type.
pub fn lowerFnRetTy(o: *Object, fn_info: InternPool.Key.FuncType) Allocator.Error!Builder.Type {
    const zcu = o.zcu;
    const return_type = Type.fromInterned(fn_info.return_type);
    if (!return_type.hasRuntimeBits(zcu)) {
        assert(!return_type.isError(zcu));
        return .void;
    }
    const target = zcu.getTarget();
    switch (fn_info.cc) {
        .@"inline" => unreachable,
        .auto => return if (returnTypeByRef(zcu, target, return_type)) .void else o.lowerType(return_type),

        .x86_64_sysv => return lowerSystemVFnRetTy(o, fn_info),
        .x86_64_win => return lowerWin64FnRetTy(o, fn_info),
        .x86_stdcall => return if (isScalar(zcu, return_type)) o.lowerType(return_type) else .void,
        .x86_sysv, .x86_win => return if (isByRef(return_type, zcu)) .void else o.lowerType(return_type),
        .aarch64_aapcs, .aarch64_aapcs_darwin, .aarch64_aapcs_win => switch (aarch64_c_abi.classifyType(return_type, zcu)) {
            .memory => return .void,
            .float_array => return o.lowerType(return_type),
            .byval => return o.lowerType(return_type),
            .integer => return o.builder.intType(@intCast(return_type.bitSize(zcu))),
            .double_integer => return o.builder.arrayType(2, .i64),
        },
        .arm_aapcs, .arm_aapcs_vfp => switch (arm_c_abi.classifyType(return_type, zcu, .ret)) {
            .memory, .i64_array => return .void,
            .i32_array => |len| return if (len == 1) .i32 else .void,
            .byval => return o.lowerType(return_type),
        },
        .mips_o32 => switch (mips_c_abi.classifyType(return_type, zcu, .ret)) {
            .memory, .i32_array => return .void,
            .byval => return o.lowerType(return_type),
        },
        .riscv64_lp64, .riscv32_ilp32 => switch (riscv_c_abi.classifyType(return_type, zcu)) {
            .memory => return .void,
            .integer => return o.builder.intType(@intCast(return_type.bitSize(zcu))),
            .double_integer => {
                const integer: Builder.Type = switch (zcu.getTarget().cpu.arch) {
                    .riscv64, .riscv64be => .i64,
                    .riscv32, .riscv32be => .i32,
                    else => unreachable,
                };
                return o.builder.structType(.normal, &.{ integer, integer });
            },
            .byval => return o.lowerType(return_type),
            .fields => {
                var types_len: usize = 0;
                var types: [8]Builder.Type = undefined;
                for (0..return_type.structFieldCount(zcu)) |field_index| {
                    const field_ty = return_type.fieldType(field_index, zcu);
                    if (!field_ty.hasRuntimeBits(zcu)) continue;
                    types[types_len] = try o.lowerType(field_ty);
                    types_len += 1;
                }
                return o.builder.structType(.normal, types[0..types_len]);
            },
        },
        .wasm_mvp => switch (wasm_c_abi.classifyType(return_type, zcu)) {
            .direct => |scalar_ty| return o.lowerType(scalar_ty),
            .indirect => return .void,
        },
        // TODO investigate other callconvs
        else => return o.lowerType(return_type),
    }
}

fn lowerWin64FnRetTy(o: *Object, fn_info: InternPool.Key.FuncType) Allocator.Error!Builder.Type {
    const zcu = o.zcu;
    const return_type = Type.fromInterned(fn_info.return_type);
    switch (x86_64_abi.classifyWindows(return_type, zcu, zcu.getTarget(), .ret)) {
        .integer => {
            if (isScalar(zcu, return_type)) {
                return o.lowerType(return_type);
            } else {
                return o.builder.intType(@intCast(return_type.abiSize(zcu) * 8));
            }
        },
        .win_i128 => return o.builder.vectorType(.normal, 2, .i64),
        .memory => return .void,
        .sse => return o.lowerType(return_type),
        else => unreachable,
    }
}

fn lowerSystemVFnRetTy(o: *Object, fn_info: InternPool.Key.FuncType) Allocator.Error!Builder.Type {
    const zcu = o.zcu;
    const ip = &zcu.intern_pool;
    const return_type = Type.fromInterned(fn_info.return_type);
    return_type.assertHasLayout(zcu);
    if (isScalar(zcu, return_type)) {
        return o.lowerType(return_type);
    }
    const classes = x86_64_abi.classifySystemV(return_type, zcu, zcu.getTarget(), .ret);
    var types_index: u32 = 0;
    var types_buffer: [8]Builder.Type = undefined;
    for (classes) |class| {
        switch (class) {
            .integer => {
                types_buffer[types_index] = .i64;
                types_index += 1;
            },
            .sse => {
                types_buffer[types_index] = .double;
                types_index += 1;
            },
            .sseup => {
                if (types_buffer[types_index - 1] == .double) {
                    types_buffer[types_index - 1] = .fp128;
                } else {
                    types_buffer[types_index] = .double;
                    types_index += 1;
                }
            },
            .float => {
                types_buffer[types_index] = .float;
                types_index += 1;
            },
            .float_combine => {
                types_buffer[types_index] = try o.builder.vectorType(.normal, 2, .float);
                types_index += 1;
            },
            .x87 => {
                if (types_index != 0 or classes[2] != .none) return .void;
                types_buffer[types_index] = .x86_fp80;
                types_index += 1;
            },
            .x87up => continue,
            .none => break,
            .memory, .integer_per_element => return .void,
            .win_i128 => unreachable, // windows only
        }
    }
    const first_non_integer = std.mem.indexOfNone(x86_64_abi.Class, &classes, &.{.integer});
    if (first_non_integer == null or classes[first_non_integer.?] == .none) {
        assert(first_non_integer orelse classes.len == types_index);
        switch (ip.indexToKey(return_type.toIntern())) {
            .struct_type => {
                const size = return_type.abiSize(zcu);
                assert((std.math.divCeil(u64, size, 8) catch unreachable) == types_index);
                if (size % 8 > 0) {
                    types_buffer[types_index - 1] = try o.builder.intType(@intCast(size % 8 * 8));
                }
            },
            else => {},
        }
        if (types_index == 1) return types_buffer[0];
    }
    return o.builder.structType(.normal, types_buffer[0..types_index]);
}

/// This function deliberately does not handle `_BitInt` because it typically
/// has different ABI than regular integer types, and there is no currently no
/// way to determine whether a Zig integer type is meant to represent e.g. `int`
/// or `_BitInt(32)`.
pub fn ccAbiPromoteInt(cc: std.builtin.CallingConvention, zcu: *Zcu, ty: Type) ?std.builtin.Signedness {
    switch (cc) {
        .auto, .@"inline", .async => return null,
        else => {},
    }

    const int_info = switch (ty.zigTypeTag(zcu)) {
        .bool => Type.u1.intInfo(zcu),
        else => if (ty.isAbiInt(zcu)) ty.intInfo(zcu) else return null,
    };
    assert(int_info.bits >= 0);

    const target = zcu.getTarget();
    return switch (target.cpu.arch) {
        .aarch64,
        .aarch64_be,
        => switch (target.os.tag) {
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => switch (int_info.bits) {
                8, 16 => int_info.signedness,
                else => null,
            },
            else => null,
        },

        .avr,
        => switch (int_info.bits) {
            8 => int_info.signedness,
            else => null,
        },

        .lanai,
        => null,

        .loongarch64,
        .riscv64,
        .riscv64be,
        => switch (int_info.bits) {
            8, 16 => int_info.signedness,
            32 => .signed,
            else => null,
        },

        .mips,
        .mipsel,
        .mips64,
        .mips64el,
        => switch (int_info.bits) {
            8, 16, 64 => int_info.signedness,
            // https://github.com/llvm/llvm-project/issues/179088
            // 32 => .signed,
            else => null,
        },

        .powerpc64,
        .powerpc64le,
        .s390x,
        .sparc64,
        .ve,
        => switch (int_info.bits) {
            8, 16, 32 => int_info.signedness,
            else => null,
        },

        else => switch (int_info.bits) {
            8, 16 => int_info.signedness,
            else => null,
        },
    };
}

fn isScalar(zcu: *Zcu, ty: Type) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .void,
        .bool,
        .noreturn,
        .int,
        .float,
        .pointer,
        .optional,
        .error_set,
        .@"enum",
        .@"anyframe",
        .vector,
        => true,

        .@"struct" => ty.containerLayout(zcu) == .@"packed",
        .@"union" => ty.containerLayout(zcu) == .@"packed",
        else => false,
    };
}

pub fn buildAllocaInner(
    wip: *Builder.WipFunction,
    llvm_ty: Builder.Type,
    alignment: Builder.Alignment,
    target: *const std.Target,
) Allocator.Error!Builder.Value {
    const address_space = llvmAllocaAddressSpace(target);

    const alloca = blk: {
        const prev_cursor = wip.cursor;
        const prev_debug_location = wip.debug_location;
        defer {
            wip.cursor = prev_cursor;
            if (wip.cursor.block == .entry) wip.cursor.instruction += 1;
            wip.debug_location = prev_debug_location;
        }

        wip.cursor = .{ .block = .entry };
        wip.debug_location = .no_location;
        break :blk try wip.alloca(.normal, llvm_ty, .none, alignment, address_space, "");
    };

    // The pointer returned from this function should have the generic address space,
    // if this isn't the case then cast it to the generic address space.
    return wip.conv(.unneeded, alloca, .ptr, "");
}

/// This is the one source of truth for whether a type is passed around as an LLVM pointer,
/// or as an LLVM value.
pub fn isByRef(ty: Type, zcu: *const Zcu) bool {
    return switch (ty.zigTypeTag(zcu)) {
        .type,
        .comptime_int,
        .comptime_float,
        .enum_literal,
        .undefined,
        .null,
        .@"opaque",
        => unreachable,

        .noreturn,
        .void,
        .bool,
        .int,
        .float,
        .pointer,
        .error_set,
        .@"fn",
        .@"enum",
        .vector,
        .@"anyframe",
        => false,

        .array,
        .frame,
        => ty.hasRuntimeBits(zcu),

        .error_union => ty.errorUnionPayload(zcu).hasRuntimeBits(zcu),

        .optional => !ty.optionalReprIsPayload(zcu) and ty.optionalChild(zcu).hasRuntimeBits(zcu),

        .@"struct" => switch (ty.containerLayout(zcu)) {
            .@"packed" => false,
            .auto, .@"extern" => ty.hasRuntimeBits(zcu),
        },
        .@"union" => switch (ty.containerLayout(zcu)) {
            .@"packed" => false,
            else => ty.hasRuntimeBits(zcu) and !ty.unionHasAllZeroBitFieldTypes(zcu),
        },
    };
}

/// If the operand type of an atomic operation is not byte sized we need to
/// widen it before using it and then truncate the result.
/// RMW exchange of floating-point values is bitcasted to same-sized integer
/// types to work around a LLVM deficiency when targeting ARM/AArch64.
fn getAtomicAbiType(fg: *const FuncGen, ty: Type, is_rmw_xchg: bool) Allocator.Error!Builder.Type {
    const zcu = fg.object.zcu;
    switch (ty.zigTypeTag(zcu)) {
        .int, .@"enum", .@"struct", .@"union" => {},
        .float => {
            if (!is_rmw_xchg) return .none;
            return fg.object.builder.intType(@intCast(ty.abiSize(zcu) * 8));
        },
        .bool => return .i8,
        else => return .none,
    }
    const bit_count = ty.bitSize(zcu);
    if (!std.math.isPowerOfTwo(bit_count) or (bit_count % 8) != 0) {
        return fg.object.builder.intType(@intCast(ty.abiSize(zcu) * 8));
    } else {
        return .none;
    }
}

fn ptraddConst(fg: *FuncGen, ptr: Builder.Value, offset: u64) Allocator.Error!Builder.Value {
    if (offset == 0) return ptr;
    const o = fg.object;
    const llvm_usize_ty = try o.lowerType(.usize);
    const offset_val = try o.builder.intValue(llvm_usize_ty, offset);
    return fg.wip.gep(.inbounds, .i8, ptr, &.{offset_val}, "");
}
fn ptraddScaled(fg: *FuncGen, ptr: Builder.Value, index: Builder.Value, scale: u64) Allocator.Error!Builder.Value {
    if (scale == 0) return ptr;
    // Right now LLVM seems to fare a bit worse with an explicit `mul nuw` instruction than it does
    // if we use a bigger type for the GEP, so we'll do that. As I understand it, it has not yet
    // been decided whether the planned `ptradd` instruction will accept a scale or not; if it does
    // not then presumably upstream will improve their handling of explicit `mul nuw` computing the
    // offset.
    const llvm_scale_ty = try fg.object.builder.arrayType(scale, .i8);
    return fg.wip.gep(.inbounds, llvm_scale_ty, ptr, &.{index}, "");
}

fn compilerRtIntBits(bits: u16) ?u16 {
    inline for (.{ 32, 64, 128 }) |b| {
        if (bits <= b) {
            return b;
        }
    }
    return null;
}

/// Returns true for asm constraint (e.g. "=*m", "=r") if it accepts a memory location
///
/// See also TargetInfo::validateOutputConstraint, AArch64TargetInfo::validateAsmConstraint, etc. in Clang
fn constraintAllowsMemory(constraint: []const u8) bool {
    // TODO: This implementation is woefully incomplete.
    for (constraint) |byte| {
        switch (byte) {
            '=', '*', ',', '&' => {},
            'm', 'o', 'X', 'g' => return true,
            else => {},
        }
    } else return false;
}

/// Returns true for asm constraint (e.g. "=*m", "=r") if it accepts a register
///
/// See also TargetInfo::validateOutputConstraint, AArch64TargetInfo::validateAsmConstraint, etc. in Clang
fn constraintAllowsRegister(constraint: []const u8) bool {
    // TODO: This implementation is woefully incomplete.
    for (constraint) |byte| {
        switch (byte) {
            '=', '*', ',', '&' => {},
            'm', 'o' => {},
            else => return true,
        }
    } else return false;
}

/// Appends zero or more LLVM constraints to `llvm_constraints`, returning how many were added.
fn appendConstraints(
    gpa: Allocator,
    llvm_constraints: *std.ArrayList(u8),
    zig_name: []const u8,
    target: *const std.Target,
) error{OutOfMemory}!usize {
    switch (target.cpu.arch) {
        .mips, .mipsel, .mips64, .mips64el => if (mips_clobber_overrides.get(zig_name)) |llvm_tag| {
            const llvm_name = @tagName(llvm_tag);
            try llvm_constraints.ensureUnusedCapacity(gpa, llvm_name.len + 4);
            llvm_constraints.appendSliceAssumeCapacity("~{");
            llvm_constraints.appendSliceAssumeCapacity(llvm_name);
            llvm_constraints.appendSliceAssumeCapacity("},");
            return 1;
        },
        else => {},
    }

    try llvm_constraints.ensureUnusedCapacity(gpa, zig_name.len + 4);
    llvm_constraints.appendSliceAssumeCapacity("~{");
    llvm_constraints.appendSliceAssumeCapacity(zig_name);
    llvm_constraints.appendSliceAssumeCapacity("},");
    return 1;
}

/// LLVM does not support all relevant intrinsics for all targets, so we
/// may need to manually generate a compiler-rt call.
fn intrinsicsAllowed(scalar_ty: Type, target: *const std.Target) bool {
    return switch (scalar_ty.toIntern()) {
        .f16_type => llvm.backendSupportsF16(target),
        .f80_type => (target.cTypeBitSize(.longdouble) == 80) and llvm.backendSupportsF80(target),
        .f128_type => (target.cTypeBitSize(.longdouble) == 128) and llvm.backendSupportsF128(target),
        else => true,
    };
}

fn toLlvmAtomicOrdering(atomic_order: std.builtin.AtomicOrder) Builder.AtomicOrdering {
    return switch (atomic_order) {
        .unordered => .unordered,
        .monotonic => .monotonic,
        .acquire => .acquire,
        .release => .release,
        .acq_rel => .acq_rel,
        .seq_cst => .seq_cst,
    };
}

fn toLlvmAtomicRmwBinOp(
    op: std.builtin.AtomicRmwOp,
    is_signed: bool,
    is_float: bool,
) Builder.Function.Instruction.AtomicRmw.Operation {
    return switch (op) {
        .Xchg => .xchg,
        .Add => if (is_float) .fadd else return .add,
        .Sub => if (is_float) .fsub else return .sub,
        .And => .@"and",
        .Nand => .nand,
        .Or => .@"or",
        .Xor => .xor,
        .Max => if (is_float) .fmax else if (is_signed) .max else return .umax,
        .Min => if (is_float) .fmin else if (is_signed) .min else return .umin,
    };
}

fn minIntConst(b: *Builder, min_ty: Type, as_ty: Builder.Type, zcu: *const Zcu) Allocator.Error!Builder.Constant {
    const info = min_ty.intInfo(zcu);
    if (info.signedness == .unsigned or info.bits == 0) {
        return b.intConst(as_ty, 0);
    }
    if (std.math.cast(u6, info.bits - 1)) |shift| {
        const min_val: i64 = @as(i64, std.math.minInt(i64)) >> (63 - shift);
        return b.intConst(as_ty, min_val);
    }
    var res: std.math.big.int.Managed = try .init(zcu.gpa);
    defer res.deinit();
    try res.setTwosCompIntLimit(.min, info.signedness, info.bits);
    return b.bigIntConst(as_ty, res.toConst());
}

fn maxIntConst(b: *Builder, max_ty: Type, as_ty: Builder.Type, zcu: *const Zcu) Allocator.Error!Builder.Constant {
    const info = max_ty.intInfo(zcu);
    switch (info.bits) {
        0 => return b.intConst(as_ty, 0),
        1 => switch (info.signedness) {
            .signed => return b.intConst(as_ty, 0),
            .unsigned => return b.intConst(as_ty, 1),
        },
        else => {},
    }
    const unsigned_bits = switch (info.signedness) {
        .unsigned => info.bits,
        .signed => info.bits - 1,
    };
    if (std.math.cast(u6, unsigned_bits)) |shift| {
        const max_val: u64 = (@as(u64, 1) << shift) - 1;
        return b.intConst(as_ty, max_val);
    }
    var res: std.math.big.int.Managed = try .init(zcu.gpa);
    defer res.deinit();
    try res.setTwosCompIntLimit(.max, info.signedness, info.bits);
    return b.bigIntConst(as_ty, res.toConst());
}

/// On some targets, local values that are in the generic address space must be generated into a
/// different address, space and then cast back to the generic address space.
/// For example, on GPUs local variable declarations must be generated into the local address space.
/// This function returns the address space local values should be generated into.
fn llvmAllocaAddressSpace(target: *const std.Target) Builder.AddrSpace {
    return switch (target.cpu.arch) {
        // On amdgcn, locals should be generated into the private address space.
        // To make Zig not impossible to use, these are then converted to addresses in the
        // generic address space and treates as regular pointers. This is the way that HIP also does it.
        .amdgcn => Builder.AddrSpace.amdgpu.private,
        else => .default,
    };
}

const mips_clobber_overrides = std.StaticStringMap(enum {
    @"$msair",
    @"$msacsr",
    @"$msaaccess",
    @"$msasave",
    @"$msamodify",
    @"$msarequest",
    @"$msamap",
    @"$msaunmap",
    @"$f0",
    @"$f1",
    @"$f2",
    @"$f3",
    @"$f4",
    @"$f5",
    @"$f6",
    @"$f7",
    @"$f8",
    @"$f9",
    @"$f10",
    @"$f11",
    @"$f12",
    @"$f13",
    @"$f14",
    @"$f15",
    @"$f16",
    @"$f17",
    @"$f18",
    @"$f19",
    @"$f20",
    @"$f21",
    @"$f22",
    @"$f23",
    @"$f24",
    @"$f25",
    @"$f26",
    @"$f27",
    @"$f28",
    @"$f29",
    @"$f30",
    @"$f31",
    @"$fcc0",
    @"$fcc1",
    @"$fcc2",
    @"$fcc3",
    @"$fcc4",
    @"$fcc5",
    @"$fcc6",
    @"$fcc7",
    @"$w0",
    @"$w1",
    @"$w2",
    @"$w3",
    @"$w4",
    @"$w5",
    @"$w6",
    @"$w7",
    @"$w8",
    @"$w9",
    @"$w10",
    @"$w11",
    @"$w12",
    @"$w13",
    @"$w14",
    @"$w15",
    @"$w16",
    @"$w17",
    @"$w18",
    @"$w19",
    @"$w20",
    @"$w21",
    @"$w22",
    @"$w23",
    @"$w24",
    @"$w25",
    @"$w26",
    @"$w27",
    @"$w28",
    @"$w29",
    @"$w30",
    @"$w31",
    @"$0",
    @"$1",
    @"$2",
    @"$3",
    @"$4",
    @"$5",
    @"$6",
    @"$7",
    @"$8",
    @"$9",
    @"$10",
    @"$11",
    @"$12",
    @"$13",
    @"$14",
    @"$15",
    @"$16",
    @"$17",
    @"$18",
    @"$19",
    @"$20",
    @"$21",
    @"$22",
    @"$23",
    @"$24",
    @"$25",
    @"$26",
    @"$27",
    @"$28",
    @"$29",
    @"$30",
    @"$31",
}).initComptime(.{
    .{ "msa_ir", .@"$msair" },
    .{ "msa_csr", .@"$msacsr" },
    .{ "msa_access", .@"$msaaccess" },
    .{ "msa_save", .@"$msasave" },
    .{ "msa_modify", .@"$msamodify" },
    .{ "msa_request", .@"$msarequest" },
    .{ "msa_map", .@"$msamap" },
    .{ "msa_unmap", .@"$msaunmap" },
    .{ "f0", .@"$f0" },
    .{ "f1", .@"$f1" },
    .{ "f2", .@"$f2" },
    .{ "f3", .@"$f3" },
    .{ "f4", .@"$f4" },
    .{ "f5", .@"$f5" },
    .{ "f6", .@"$f6" },
    .{ "f7", .@"$f7" },
    .{ "f8", .@"$f8" },
    .{ "f9", .@"$f9" },
    .{ "f10", .@"$f10" },
    .{ "f11", .@"$f11" },
    .{ "f12", .@"$f12" },
    .{ "f13", .@"$f13" },
    .{ "f14", .@"$f14" },
    .{ "f15", .@"$f15" },
    .{ "f16", .@"$f16" },
    .{ "f17", .@"$f17" },
    .{ "f18", .@"$f18" },
    .{ "f19", .@"$f19" },
    .{ "f20", .@"$f20" },
    .{ "f21", .@"$f21" },
    .{ "f22", .@"$f22" },
    .{ "f23", .@"$f23" },
    .{ "f24", .@"$f24" },
    .{ "f25", .@"$f25" },
    .{ "f26", .@"$f26" },
    .{ "f27", .@"$f27" },
    .{ "f28", .@"$f28" },
    .{ "f29", .@"$f29" },
    .{ "f30", .@"$f30" },
    .{ "f31", .@"$f31" },
    .{ "fcc0", .@"$fcc0" },
    .{ "fcc1", .@"$fcc1" },
    .{ "fcc2", .@"$fcc2" },
    .{ "fcc3", .@"$fcc3" },
    .{ "fcc4", .@"$fcc4" },
    .{ "fcc5", .@"$fcc5" },
    .{ "fcc6", .@"$fcc6" },
    .{ "fcc7", .@"$fcc7" },
    .{ "w0", .@"$w0" },
    .{ "w1", .@"$w1" },
    .{ "w2", .@"$w2" },
    .{ "w3", .@"$w3" },
    .{ "w4", .@"$w4" },
    .{ "w5", .@"$w5" },
    .{ "w6", .@"$w6" },
    .{ "w7", .@"$w7" },
    .{ "w8", .@"$w8" },
    .{ "w9", .@"$w9" },
    .{ "w10", .@"$w10" },
    .{ "w11", .@"$w11" },
    .{ "w12", .@"$w12" },
    .{ "w13", .@"$w13" },
    .{ "w14", .@"$w14" },
    .{ "w15", .@"$w15" },
    .{ "w16", .@"$w16" },
    .{ "w17", .@"$w17" },
    .{ "w18", .@"$w18" },
    .{ "w19", .@"$w19" },
    .{ "w20", .@"$w20" },
    .{ "w21", .@"$w21" },
    .{ "w22", .@"$w22" },
    .{ "w23", .@"$w23" },
    .{ "w24", .@"$w24" },
    .{ "w25", .@"$w25" },
    .{ "w26", .@"$w26" },
    .{ "w27", .@"$w27" },
    .{ "w28", .@"$w28" },
    .{ "w29", .@"$w29" },
    .{ "w30", .@"$w30" },
    .{ "w31", .@"$w31" },
    .{ "r0", .@"$0" },
    .{ "r1", .@"$1" },
    .{ "r2", .@"$2" },
    .{ "r3", .@"$3" },
    .{ "r4", .@"$4" },
    .{ "r5", .@"$5" },
    .{ "r6", .@"$6" },
    .{ "r7", .@"$7" },
    .{ "r8", .@"$8" },
    .{ "r9", .@"$9" },
    .{ "r10", .@"$10" },
    .{ "r11", .@"$11" },
    .{ "r12", .@"$12" },
    .{ "r13", .@"$13" },
    .{ "r14", .@"$14" },
    .{ "r15", .@"$15" },
    .{ "r16", .@"$16" },
    .{ "r17", .@"$17" },
    .{ "r18", .@"$18" },
    .{ "r19", .@"$19" },
    .{ "r20", .@"$20" },
    .{ "r21", .@"$21" },
    .{ "r22", .@"$22" },
    .{ "r23", .@"$23" },
    .{ "r24", .@"$24" },
    .{ "r25", .@"$25" },
    .{ "r26", .@"$26" },
    .{ "r27", .@"$27" },
    .{ "r28", .@"$28" },
    .{ "r29", .@"$29" },
    .{ "r30", .@"$30" },
    .{ "r31", .@"$31" },
});

const std = @import("std");
const Allocator = std.mem.Allocator;
const Builder = std.zig.llvm.Builder;
const assert = std.debug.assert;
const math = std.math;

const x86_64_abi = @import("../x86_64/abi.zig");
const wasm_c_abi = @import("../wasm/abi.zig");
const aarch64_c_abi = @import("../aarch64/abi.zig");
const arm_c_abi = @import("../arm/abi.zig");
const riscv_c_abi = @import("../riscv64/abi.zig");
const mips_c_abi = @import("../mips/abi.zig");

const Zcu = @import("../../Zcu.zig");
const Air = @import("../../Air.zig");
const Package = @import("../../Package.zig");
const InternPool = @import("../../InternPool.zig");
const Value = @import("../../Value.zig");
const Type = @import("../../Type.zig");
const codegen = @import("../../codegen.zig");

const target_util = @import("../../target.zig");
const libcFloatPrefix = target_util.libcFloatPrefix;
const libcFloatSuffix = target_util.libcFloatSuffix;
const compilerRtIntAbbrev = target_util.compilerRtIntAbbrev;
const compilerRtFloatAbbrev = target_util.compilerRtFloatAbbrev;

const llvm = @import("../llvm.zig");
const Object = llvm.Object;
const optional_layout_version = llvm.optional_layout_version;
