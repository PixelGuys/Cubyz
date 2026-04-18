//! Supports single-threaded targets that have a sbrk-like primitive which includes
//! Linux and WebAssembly.
//!
//! On Linux, assumes exclusive access to the brk syscall.
const BrkAllocator = @This();
const builtin = @import("builtin");

const std = @import("../std.zig");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const assert = std.debug.assert;
const math = std.math;

comptime {
    if (!builtin.single_threaded) @compileError("unsupported");
}

next_addrs: [size_class_count]usize = @splat(0),
/// For each size class, points to the freed pointer.
frees: [size_class_count]usize = @splat(0),
/// For each big size class, points to the freed pointer.
big_frees: [big_size_class_count]usize = @splat(0),
prev_brk: usize = 0,

var global: BrkAllocator = .{};

pub const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

pub const Error = Allocator.Error;

const max_usize = math.maxInt(usize);
const ushift = math.Log2Int(usize);
const bigpage_size: comptime_int = @max(64 * 1024, std.heap.page_size_max);
const bigpage_count = max_usize / bigpage_size;

/// Because of storing free list pointers, the minimum size class is 3.
const min_class = math.log2(math.ceilPowerOfTwoAssert(usize, 1 + @sizeOf(usize)));
const size_class_count = math.log2(bigpage_size) - min_class;
/// 0 - 1 bigpage
/// 1 - 2 bigpages
/// 2 - 4 bigpages
/// etc.
const big_size_class_count = math.log2(bigpage_count);

fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, return_address: usize) ?[*]u8 {
    _ = ctx;
    _ = return_address;
    // Make room for the freelist next pointer.
    const actual_len = @max(len +| @sizeOf(usize), alignment.toByteUnits());
    const slot_size = math.ceilPowerOfTwo(usize, actual_len) catch return null;
    const class = math.log2(slot_size) - min_class;
    if (class < size_class_count) {
        const addr = a: {
            const top_free_ptr = global.frees[class];
            if (top_free_ptr != 0) {
                const node: *usize = @ptrFromInt(top_free_ptr + (slot_size - @sizeOf(usize)));
                global.frees[class] = node.*;
                break :a top_free_ptr;
            }

            const next_addr = global.next_addrs[class];
            if (next_addr % bigpage_size == 0) {
                const addr = allocBigPages(1);
                if (addr == 0) return null;
                //std.debug.print("allocated fresh slot_size={d} class={d} addr=0x{x}\n", .{
                //    slot_size, class, addr,
                //});
                global.next_addrs[class] = addr + slot_size;
                break :a addr;
            } else {
                global.next_addrs[class] = next_addr + slot_size;
                break :a next_addr;
            }
        };
        return @ptrFromInt(addr);
    }
    const bigpages_needed = bigPagesNeeded(actual_len);
    return @ptrFromInt(allocBigPages(bigpages_needed));
}

fn resize(
    ctx: *anyopaque,
    buf: []u8,
    alignment: Alignment,
    new_len: usize,
    return_address: usize,
) bool {
    _ = ctx;
    _ = return_address;
    // We don't want to move anything from one size class to another, but we
    // can recover bytes in between powers of two.
    const buf_align = alignment.toByteUnits();
    const old_actual_len = @max(buf.len + @sizeOf(usize), buf_align);
    const new_actual_len = @max(new_len +| @sizeOf(usize), buf_align);
    const old_small_slot_size = math.ceilPowerOfTwoAssert(usize, old_actual_len);
    const old_small_class = math.log2(old_small_slot_size) - min_class;
    if (old_small_class < size_class_count) {
        const new_small_slot_size = math.ceilPowerOfTwo(usize, new_actual_len) catch return false;
        return old_small_slot_size == new_small_slot_size;
    } else {
        const old_bigpages_needed = bigPagesNeeded(old_actual_len);
        const old_big_slot_pages = math.ceilPowerOfTwoAssert(usize, old_bigpages_needed);
        const new_bigpages_needed = bigPagesNeeded(new_actual_len);
        const new_big_slot_pages = math.ceilPowerOfTwo(usize, new_bigpages_needed) catch return false;
        return old_big_slot_pages == new_big_slot_pages;
    }
}

fn remap(
    context: *anyopaque,
    memory: []u8,
    alignment: Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
}

fn free(
    ctx: *anyopaque,
    buf: []u8,
    alignment: Alignment,
    return_address: usize,
) void {
    _ = ctx;
    _ = return_address;
    const buf_align = alignment.toByteUnits();
    const actual_len = @max(buf.len + @sizeOf(usize), buf_align);
    const slot_size = math.ceilPowerOfTwoAssert(usize, actual_len);
    const class = math.log2(slot_size) - min_class;
    const addr = @intFromPtr(buf.ptr);
    if (class < size_class_count) {
        const node: *usize = @ptrFromInt(addr + (slot_size - @sizeOf(usize)));
        node.* = global.frees[class];
        global.frees[class] = addr;
    } else {
        const bigpages_needed = bigPagesNeeded(actual_len);
        const pow2_pages = math.ceilPowerOfTwoAssert(usize, bigpages_needed);
        const big_slot_size_bytes = pow2_pages * bigpage_size;
        const node: *usize = @ptrFromInt(addr + (big_slot_size_bytes - @sizeOf(usize)));
        const big_class = math.log2(pow2_pages);
        node.* = global.big_frees[big_class];
        global.big_frees[big_class] = addr;
    }
}

inline fn bigPagesNeeded(byte_count: usize) usize {
    return (byte_count + (bigpage_size + (@sizeOf(usize) - 1))) / bigpage_size;
}

fn allocBigPages(n: usize) usize {
    const pow2_pages = math.ceilPowerOfTwoAssert(usize, n);
    const slot_size_bytes = pow2_pages * bigpage_size;
    const class = math.log2(pow2_pages);

    const top_free_ptr = global.big_frees[class];
    if (top_free_ptr != 0) {
        const node: *usize = @ptrFromInt(top_free_ptr + (slot_size_bytes - @sizeOf(usize)));
        global.big_frees[class] = node.*;
        return top_free_ptr;
    }

    if (builtin.cpu.arch.isWasm()) {
        comptime assert(std.heap.page_size_max == std.heap.page_size_min);
        const page_size = std.heap.page_size_max;
        const pages_per_bigpage = bigpage_size / page_size;
        const page_index = @wasmMemoryGrow(0, pow2_pages * pages_per_bigpage);
        if (page_index == -1) return 0;
        return @as(usize, @intCast(page_index)) * page_size;
    } else if (builtin.os.tag == .linux) {
        const prev_brk = global.prev_brk;
        const start_brk = if (prev_brk == 0)
            std.mem.alignForward(usize, std.os.linux.brk(0), bigpage_size)
        else
            prev_brk;
        const end_brk = start_brk + pow2_pages * bigpage_size;
        const new_prev_brk = std.os.linux.brk(end_brk);
        global.prev_brk = new_prev_brk;
        if (new_prev_brk != end_brk) return 0;
        return start_brk;
    } else {
        @compileError("no sbrk-like OS primitive available");
    }
}

const test_ally: Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};

test "small allocations - free in same order" {
    var list: [513]*u64 = undefined;

    var i: usize = 0;
    while (i < 513) : (i += 1) {
        const ptr = try test_ally.create(u64);
        list[i] = ptr;
    }

    for (list) |ptr| {
        test_ally.destroy(ptr);
    }
}

test "small allocations - free in reverse order" {
    var list: [513]*u64 = undefined;

    var i: usize = 0;
    while (i < 513) : (i += 1) {
        const ptr = try test_ally.create(u64);
        list[i] = ptr;
    }

    i = list.len;
    while (i > 0) {
        i -= 1;
        const ptr = list[i];
        test_ally.destroy(ptr);
    }
}

test "large allocations" {
    const ptr1 = try test_ally.alloc(u64, 42768);
    const ptr2 = try test_ally.alloc(u64, 52768);
    test_ally.free(ptr1);
    const ptr3 = try test_ally.alloc(u64, 62768);
    test_ally.free(ptr3);
    test_ally.free(ptr2);
}

test "very large allocation" {
    try std.testing.expectError(error.OutOfMemory, test_ally.alloc(u8, math.maxInt(usize)));
}

test "realloc" {
    var slice = try test_ally.alignedAlloc(u8, .of(u32), 1);
    defer test_ally.free(slice);
    slice[0] = 0x12;

    // This reallocation should keep its pointer address.
    const old_slice = slice;
    slice = try test_ally.realloc(slice, 2);
    try std.testing.expect(old_slice.ptr == slice.ptr);
    try std.testing.expect(slice[0] == 0x12);
    slice[1] = 0x34;

    // This requires upgrading to a larger size class
    slice = try test_ally.realloc(slice, 17);
    try std.testing.expect(slice[0] == 0x12);
    try std.testing.expect(slice[1] == 0x34);
}

test "shrink" {
    var slice = try test_ally.alloc(u8, 20);
    defer test_ally.free(slice);

    @memset(slice, 0x11);

    try std.testing.expect(test_ally.resize(slice, 17));
    slice = slice[0..17];

    for (slice) |b| {
        try std.testing.expect(b == 0x11);
    }

    try std.testing.expect(test_ally.resize(slice, 16));
    slice = slice[0..16];

    for (slice) |b| {
        try std.testing.expect(b == 0x11);
    }
}

test "large object - grow" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;

    var slice1 = try test_ally.alloc(u8, bigpage_size * 2 - 20);
    defer test_ally.free(slice1);

    const old = slice1;
    slice1 = try test_ally.realloc(slice1, bigpage_size * 2 - 10);
    try std.testing.expectEqual(slice1.ptr, old.ptr);

    slice1 = try test_ally.realloc(slice1, bigpage_size * 2);
    slice1 = try test_ally.realloc(slice1, bigpage_size * 2 + 1);
}

test "realloc small object to large object" {
    var slice = try test_ally.alloc(u8, 70);
    defer test_ally.free(slice);
    slice[0] = 0x12;
    slice[60] = 0x34;

    // This requires upgrading to a large object
    const large_object_size = bigpage_size * 2 + 50;
    slice = try test_ally.realloc(slice, large_object_size);
    try std.testing.expect(slice[0] == 0x12);
    try std.testing.expect(slice[60] == 0x34);
}

test "shrink large object to large object" {
    var slice = try test_ally.alloc(u8, bigpage_size * 2 + 50);
    defer test_ally.free(slice);
    slice[0] = 0x12;
    slice[60] = 0x34;

    try std.testing.expect(test_ally.resize(slice, bigpage_size * 2 + 1));
    slice = slice[0 .. bigpage_size * 2 + 1];
    try std.testing.expect(slice[0] == 0x12);
    try std.testing.expect(slice[60] == 0x34);

    try std.testing.expect(test_ally.resize(slice, bigpage_size * 2 + 1));
    try std.testing.expect(slice[0] == 0x12);
    try std.testing.expect(slice[60] == 0x34);

    slice = try test_ally.realloc(slice, bigpage_size * 2);
    try std.testing.expect(slice[0] == 0x12);
    try std.testing.expect(slice[60] == 0x34);
}

test "realloc large object to small object" {
    var slice = try test_ally.alloc(u8, bigpage_size * 2 + 50);
    defer test_ally.free(slice);
    slice[0] = 0x12;
    slice[16] = 0x34;

    slice = try test_ally.realloc(slice, 19);
    try std.testing.expect(slice[0] == 0x12);
    try std.testing.expect(slice[16] == 0x34);
}

test "objects of size 1024 and 2048" {
    const slice = try test_ally.alloc(u8, 1025);
    const slice2 = try test_ally.alloc(u8, 3000);

    test_ally.free(slice);
    test_ally.free(slice2);
}

test "standard allocator tests" {
    try std.heap.testAllocator(test_ally);
    try std.heap.testAllocatorAligned(test_ally);
}
