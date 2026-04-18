/// Helper type for debug information implementations (such as `link.Dwarf`) to help them emit
/// information about comptime-known values (constants), including types.
///
/// Every constant with associated debug information is assigned an `Index` by calling `get`. The
/// pool will track which container types do and do not have a resolved layout, as well as which
/// constants in the pool depend on which types, and call into the implementation to emit debug
/// information for a constant only when all information is available.
///
/// Indices into the pool are dense, and constants are never removed from the pool, so the debug
/// info implementation can store information for each one with a simple `ArrayList`.
///
/// To use `ConstPool`, the debug info implementation is required to:
/// * forward `updateContainerType` calls to its `ConstPool`
/// * expose some callback functions---see functions in `User`
/// * ensure that any `get` call is eventually followed by a `flushPending` call
const ConstPool = @This();

values: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
pending: std.ArrayList(Index),
complete_containers: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
container_deps: std.AutoArrayHashMapUnmanaged(InternPool.Index, ContainerDepEntry.Index),
container_dep_entries: std.ArrayList(ContainerDepEntry),

pub const empty: ConstPool = .{
    .values = .empty,
    .pending = .empty,
    .complete_containers = .empty,
    .container_deps = .empty,
    .container_dep_entries = .empty,
};

pub fn deinit(pool: *ConstPool, gpa: Allocator) void {
    pool.values.deinit(gpa);
    pool.pending.deinit(gpa);
    pool.complete_containers.deinit(gpa);
    pool.container_deps.deinit(gpa);
    pool.container_dep_entries.deinit(gpa);
}

pub const Index = enum(u32) {
    _,
    pub fn val(i: Index, pool: *const ConstPool) InternPool.Index {
        return pool.values.keys()[@intFromEnum(i)];
    }
};

pub const User = union(enum) {
    dwarf: *@import("Dwarf.zig"),
    c: *@import("C.zig"),
    llvm: @import("../codegen/llvm.zig").Object.Ptr,

    /// Inform the debug info implementation that the new constant `val` was added to the pool at
    /// the given index (which equals the current pool length) due to a `get` call. It is guaranteed
    /// that there will eventually be a call to either `updateConst` or `updateConstIncomplete`
    /// following the `addConst` call, to actually populate the constant's debug info.
    fn addConst(
        user: User,
        pt: Zcu.PerThread,
        index: Index,
        val: InternPool.Index,
    ) Allocator.Error!void {
        switch (user) {
            inline else => |impl| return impl.addConst(pt, index, val),
        }
    }

    /// Tell the debug info implementation to emit information for the constant `val`, which is in
    /// the pool at the given index. `val` is "complete", which means:
    /// * If it is a type, its layout is known.
    /// * Otherwise, the layout of its type is known.
    fn updateConst(
        user: User,
        pt: Zcu.PerThread,
        index: Index,
        val: InternPool.Index,
    ) Allocator.Error!void {
        switch (user) {
            inline else => |impl| return impl.updateConst(pt, index, val),
        }
    }

    /// Tell the debug info implementation to emit information for the constant `val`, which is in
    /// the pool at the given index. `val` is "incomplete", meaning the implementation cannot emit
    /// full information for it (for instance, perhaps it is a struct type which was never actually
    /// initialized so never had its layout resolved). Instead, the implementation must emit some
    /// form of placeholder entry representing an incomplete/unknown constant.
    fn updateConstIncomplete(
        user: User,
        pt: Zcu.PerThread,
        index: Index,
        val: InternPool.Index,
    ) Allocator.Error!void {
        switch (user) {
            inline else => |impl| return impl.updateConstIncomplete(pt, index, val),
        }
    }
};

const ContainerDepEntry = extern struct {
    next: ContainerDepEntry.Index.Optional,
    depender: ConstPool.Index,
    const Index = enum(u32) {
        _,
        const Optional = enum(u32) {
            none = std.math.maxInt(u32),
            _,
            fn unwrap(o: Optional) ?ContainerDepEntry.Index {
                return switch (o) {
                    .none => null,
                    else => @enumFromInt(@intFromEnum(o)),
                };
            }
        };
        fn toOptional(i: ContainerDepEntry.Index) Optional {
            return @enumFromInt(@intFromEnum(i));
        }
        fn ptr(i: ContainerDepEntry.Index, pool: *ConstPool) *ContainerDepEntry {
            return &pool.container_dep_entries.items[@intFromEnum(i)];
        }
    };
};

/// Calls to `link.File.updateContainerType` must be forwarded to this function so that the debug
/// constant pool has up-to-date information about the resolution status of types.
pub fn updateContainerType(
    pool: *ConstPool,
    pt: Zcu.PerThread,
    user: User,
    container_ty: InternPool.Index,
    success: bool,
) Allocator.Error!void {
    if (success) {
        const gpa = pt.zcu.comp.gpa;
        try pool.complete_containers.put(gpa, container_ty, {});
    } else {
        _ = pool.complete_containers.fetchSwapRemove(container_ty);
    }
    var opt_dep = pool.container_deps.get(container_ty);
    while (opt_dep) |dep| : (opt_dep = dep.ptr(pool).next.unwrap()) {
        try pool.update(pt, user, dep.ptr(pool).depender);
    }
}

/// After this is called, there may be a constant for which debug information (complete or not) has
/// not yet been emitted, so the user must call `flushPending` at some point after this call.
pub fn get(pool: *ConstPool, pt: Zcu.PerThread, user: User, val: InternPool.Index) Allocator.Error!ConstPool.Index {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.comp.gpa;
    const gop = try pool.values.getOrPut(gpa, val);
    const index: ConstPool.Index = @enumFromInt(gop.index);
    if (!gop.found_existing) {
        const ty: Type = switch (ip.typeOf(val)) {
            .type_type => if (ip.isUndef(val)) .type else .fromInterned(val),
            else => |ty| .fromInterned(ty),
        };
        try pool.registerTypeDeps(index, ty, zcu);
        try pool.pending.append(gpa, index);
        try user.addConst(pt, index, val);
    }
    return index;
}
pub fn flushPending(pool: *ConstPool, pt: Zcu.PerThread, user: User) Allocator.Error!void {
    while (pool.pending.pop()) |pending_ty| {
        try pool.update(pt, user, pending_ty);
    }
}

fn update(pool: *ConstPool, pt: Zcu.PerThread, user: User, index: ConstPool.Index) Allocator.Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const val = index.val(pool);
    const ty: Type = switch (ip.typeOf(val)) {
        .type_type => if (ip.isUndef(val)) .type else .fromInterned(val),
        else => |ty| .fromInterned(ty),
    };
    if (pool.checkType(ty, zcu)) {
        try user.updateConst(pt, index, val);
    } else {
        try user.updateConstIncomplete(pt, index, val);
    }
}
fn checkType(pool: *const ConstPool, ty: Type, zcu: *const Zcu) bool {
    if (ty.isGenericPoison()) return true;
    return switch (ty.zigTypeTag(zcu)) {
        .type,
        .void,
        .bool,
        .noreturn,
        .int,
        .float,
        .pointer,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .error_set,
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        => true,

        .array, .vector => pool.checkType(ty.childType(zcu), zcu),
        .optional => pool.checkType(ty.optionalChild(zcu), zcu),
        .error_union => pool.checkType(ty.errorUnionPayload(zcu), zcu),
        .@"fn" => {
            const ip = &zcu.intern_pool;
            const func = ip.indexToKey(ty.toIntern()).func_type;
            for (func.param_types.get(ip)) |param_ty_ip| {
                if (!pool.checkType(.fromInterned(param_ty_ip), zcu)) return false;
            }
            return pool.checkType(.fromInterned(func.return_type), zcu);
        },
        .@"struct" => if (ty.isTuple(zcu)) {
            for (0..ty.structFieldCount(zcu)) |field_index| {
                if (!pool.checkType(ty.fieldType(field_index, zcu), zcu)) return false;
            }
            return true;
        } else {
            return pool.complete_containers.contains(ty.toIntern());
        },
        .@"union", .@"enum" => {
            return pool.complete_containers.contains(ty.toIntern());
        },
    };
}
fn registerTypeDeps(pool: *ConstPool, root: Index, ty: Type, zcu: *const Zcu) Allocator.Error!void {
    if (ty.isGenericPoison()) return;
    switch (ty.zigTypeTag(zcu)) {
        .type,
        .void,
        .bool,
        .noreturn,
        .int,
        .float,
        .pointer,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .error_set,
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        => {},

        .array, .vector => try pool.registerTypeDeps(root, ty.childType(zcu), zcu),
        .optional => try pool.registerTypeDeps(root, ty.optionalChild(zcu), zcu),
        .error_union => try pool.registerTypeDeps(root, ty.errorUnionPayload(zcu), zcu),
        .@"fn" => {
            const ip = &zcu.intern_pool;
            const func = ip.indexToKey(ty.toIntern()).func_type;
            for (func.param_types.get(ip)) |param_ty_ip| {
                try pool.registerTypeDeps(root, .fromInterned(param_ty_ip), zcu);
            }
            try pool.registerTypeDeps(root, .fromInterned(func.return_type), zcu);
        },
        .@"struct", .@"union", .@"enum" => if (ty.isTuple(zcu)) {
            for (0..ty.structFieldCount(zcu)) |field_index| {
                try pool.registerTypeDeps(root, ty.fieldType(field_index, zcu), zcu);
            }
        } else {
            // `ty` is a container; register the dependency.

            const gpa = zcu.comp.gpa;
            try pool.container_deps.ensureUnusedCapacity(gpa, 1);
            try pool.container_dep_entries.ensureUnusedCapacity(gpa, 1);
            errdefer comptime unreachable;

            const gop = pool.container_deps.getOrPutAssumeCapacity(ty.toIntern());
            const entry: ContainerDepEntry.Index = @enumFromInt(pool.container_dep_entries.items.len);
            pool.container_dep_entries.appendAssumeCapacity(.{
                .next = if (gop.found_existing) gop.value_ptr.toOptional() else .none,
                .depender = root,
            });
            gop.value_ptr.* = entry;
        },
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const InternPool = @import("../InternPool.zig");
const Type = @import("../Type.zig");
const Zcu = @import("../Zcu.zig");
