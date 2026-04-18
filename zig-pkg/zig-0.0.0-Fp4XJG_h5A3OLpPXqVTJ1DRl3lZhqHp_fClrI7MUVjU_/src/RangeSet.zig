const RangeSet = @This();

ranges: std.ArrayList(Range),

pub const Range = struct {
    first: Value,
    last: Value,
    src: LazySrcLoc,
};

pub const empty: RangeSet = .{ .ranges = .empty };

pub fn deinit(self: *RangeSet, allocator: Allocator) void {
    self.ranges.deinit(allocator);
    self.* = undefined;
}

pub fn ensureUnusedCapacity(self: *RangeSet, allocator: Allocator, additional_count: usize) Allocator.Error!void {
    return self.ranges.ensureUnusedCapacity(allocator, additional_count);
}

pub fn addAssumeCapacity(set: *RangeSet, new: Range, ty: Type, zcu: *Zcu) ?LazySrcLoc {
    assert(new.first.typeOf(zcu).eql(ty, zcu));
    assert(new.last.typeOf(zcu).eql(ty, zcu));

    for (set.ranges.items) |range| {
        if (new.last.compareScalar(.gte, range.first, ty, zcu) and
            new.first.compareScalar(.lte, range.last, ty, zcu))
        {
            return range.src; // They overlap.
        }
    }
    set.ranges.appendAssumeCapacity(new);
    return null;
}

pub fn add(set: *RangeSet, allocator: Allocator, new: Range, ty: Type, zcu: *Zcu) Allocator.Error!?LazySrcLoc {
    try set.ensureUnusedCapacity(allocator, 1);
    return set.addAssumeCapacity(new, ty, zcu);
}

const SortCtx = struct {
    ty: Type,
    zcu: *Zcu,
};
/// Assumes a and b do not overlap
fn lessThan(ctx: SortCtx, a: Range, b: Range) bool {
    return a.first.compareScalar(.lt, b.first, ctx.ty, ctx.zcu);
}

pub fn spans(
    set: *RangeSet,
    allocator: Allocator,
    first: Value,
    last: Value,
    ty: Type,
    zcu: *Zcu,
) Allocator.Error!bool {
    assert(first.typeOf(zcu).eql(ty, zcu));
    assert(last.typeOf(zcu).eql(ty, zcu));
    if (set.ranges.items.len == 0) return false;

    std.mem.sort(Range, set.ranges.items, SortCtx{ .ty = ty, .zcu = zcu }, lessThan);

    if (!set.ranges.items[0].first.eql(first, ty, zcu) or
        !set.ranges.items[set.ranges.items.len - 1].last.eql(last, ty, zcu))
    {
        return false;
    }

    const limbs = try allocator.alloc(
        std.math.big.Limb,
        std.math.big.int.calcTwosCompLimbCount(ty.intInfo(zcu).bits),
    );
    defer allocator.free(limbs);
    var counter: std.math.big.int.Mutable = .init(limbs, 0);

    var space: InternPool.Key.Int.Storage.BigIntSpace = undefined;

    // look for gaps
    for (set.ranges.items[1..], 0..) |cur, i| {
        // i starts counting from the second item.
        const prev = set.ranges.items[i];

        // prev.last + 1 == cur.first
        counter.copy(prev.last.toBigInt(&space, zcu));
        counter.addScalar(counter.toConst(), 1);

        const cur_start_int = cur.first.toBigInt(&space, zcu);
        if (!cur_start_int.eql(counter.toConst())) {
            return false;
        }
    }

    return true;
}

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const InternPool = @import("InternPool.zig");
const Type = @import("Type.zig");
const Value = @import("Value.zig");
const Zcu = @import("Zcu.zig");
const LazySrcLoc = Zcu.LazySrcLoc;
