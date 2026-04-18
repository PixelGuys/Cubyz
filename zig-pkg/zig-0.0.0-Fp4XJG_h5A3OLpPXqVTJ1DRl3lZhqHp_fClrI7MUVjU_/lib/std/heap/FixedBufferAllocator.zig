const std = @import("../std.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const mem = std.mem;

const FixedBufferAllocator = @This();

end_index: usize,
buffer: []u8,

pub fn init(buffer: []u8) FixedBufferAllocator {
    return .{
        .buffer = buffer,
        .end_index = 0,
    };
}

/// Using this at the same time as the interface returned by `threadSafeAllocator` is not thread safe.
pub fn allocator(self: *FixedBufferAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

/// Provides a lock free thread safe `Allocator` interface to the underlying `FixedBufferAllocator`
///
/// Using this at the same time as the interface returned by `allocator` is not thread safe.
pub fn threadSafeAllocator(self: *FixedBufferAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = threadSafeAlloc,
            .resize = threadSafeResize,
            .remap = threadSafeRemap,
            .free = threadSafeFree,
        },
    };
}

pub fn ownsPtr(self: *FixedBufferAllocator, ptr: [*]u8) bool {
    return sliceContainsPtr(self.buffer, ptr);
}

pub fn ownsSlice(self: *FixedBufferAllocator, slice: []u8) bool {
    return sliceContainsSlice(self.buffer, slice);
}

/// This has false negatives when the last allocation had an
/// adjusted_index. In such case we won't be able to determine what the
/// last allocation was because the alignForward operation done in alloc is
/// not reversible.
pub fn isLastAllocation(self: *FixedBufferAllocator, buf: []u8) bool {
    return buf.ptr + buf.len == self.buffer.ptr + self.end_index;
}

pub fn alloc(ctx: *anyopaque, n: usize, alignment: mem.Alignment, ra: usize) ?[*]u8 {
    const self: *FixedBufferAllocator = @ptrCast(@alignCast(ctx));
    _ = ra;
    const ptr_align = alignment.toByteUnits();
    const adjust_off = mem.alignPointerOffset(self.buffer.ptr + self.end_index, ptr_align) orelse return null;
    const adjusted_index = self.end_index + adjust_off;
    const new_end_index = adjusted_index + n;
    if (new_end_index > self.buffer.len) return null;
    self.end_index = new_end_index;
    return self.buffer.ptr + adjusted_index;
}

pub fn resize(
    ctx: *anyopaque,
    buf: []u8,
    alignment: mem.Alignment,
    new_size: usize,
    return_address: usize,
) bool {
    const self: *FixedBufferAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = return_address;
    assert(@inComptime() or self.ownsSlice(buf));

    if (!self.isLastAllocation(buf)) {
        if (new_size > buf.len) return false;
        return true;
    }

    if (new_size <= buf.len) {
        const sub = buf.len - new_size;
        self.end_index -= sub;
        return true;
    }

    const add = new_size - buf.len;
    if (add + self.end_index > self.buffer.len) return false;

    self.end_index += add;
    return true;
}

pub fn remap(
    context: *anyopaque,
    memory: []u8,
    alignment: mem.Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
}

pub fn free(
    ctx: *anyopaque,
    buf: []u8,
    alignment: mem.Alignment,
    return_address: usize,
) void {
    const self: *FixedBufferAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = return_address;
    assert(@inComptime() or self.ownsSlice(buf));

    if (self.isLastAllocation(buf)) {
        self.end_index -= buf.len;
    }
}

fn threadSafeAlloc(ctx: *anyopaque, n: usize, alignment: mem.Alignment, ret_addr: usize) ?[*]u8 {
    const self: *FixedBufferAllocator = @ptrCast(@alignCast(ctx));
    _ = ret_addr;
    const ptr_align = alignment.toByteUnits();
    var cur_end_index = @atomicLoad(usize, &self.end_index, .monotonic);
    while (true) {
        const adjust_off = mem.alignPointerOffset(self.buffer.ptr + cur_end_index, ptr_align) orelse return null;
        const adjusted_index = cur_end_index + adjust_off;
        const new_end_index = adjusted_index + n;
        if (new_end_index > self.buffer.len) return null;
        cur_end_index = @cmpxchgWeak(
            usize,
            &self.end_index,
            cur_end_index,
            new_end_index,
            .acquire, // acquire any memory that may have been freed
            .monotonic,
        ) orelse
            return self.buffer[adjusted_index..new_end_index].ptr;
    }
}

fn threadSafeResize(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const fba: *FixedBufferAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = ret_addr;

    const cur_end_index = @atomicLoad(usize, &fba.end_index, .monotonic);
    if (fba.buffer.ptr + cur_end_index != memory.ptr + memory.len) {
        // It's not the most recent allocation, so it cannot be expanded,
        // but it's fine if they want to make it smaller.
        return new_len <= memory.len;
    }

    if (new_len <= memory.len) {
        const new_end_index = cur_end_index - (memory.len - new_len);
        assert(fba.buffer.ptr + new_end_index == memory.ptr + new_len);

        _ = @cmpxchgStrong(
            usize,
            &fba.end_index,
            cur_end_index,
            new_end_index,
            .release, // release freed memory
            .monotonic,
        );
        return true; // Shrinking allocations should always succeed.
    }

    if (fba.buffer.len - cur_end_index >= new_len - memory.len) {
        const new_end_index = cur_end_index + (new_len - memory.len);
        assert(fba.buffer.ptr + new_end_index == memory.ptr + new_len);

        return null == @cmpxchgStrong(
            usize,
            &fba.end_index,
            cur_end_index,
            new_end_index,
            .acquire, // acquire any memory that may have been freed
            .monotonic,
        );
    }

    return false;
}

fn threadSafeRemap(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    return if (threadSafeResize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
}

fn threadSafeFree(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, ret_addr: usize) void {
    const fba: *FixedBufferAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = ret_addr;

    assert(memory.len > 0);

    const cur_end_index = @atomicLoad(usize, &fba.end_index, .monotonic);
    if (fba.buffer.ptr + cur_end_index != memory.ptr + memory.len) {
        // Not the most recent allocation; we cannot free it.
        return;
    }

    const new_end_index = cur_end_index - memory.len;
    assert(fba.buffer.ptr + new_end_index == memory.ptr);

    _ = @cmpxchgStrong(
        usize,
        &fba.end_index,
        cur_end_index,
        new_end_index,
        .release, // release freed memory
        .monotonic,
    );
}

pub fn reset(self: *FixedBufferAllocator) void {
    self.end_index = 0;
}

fn sliceContainsPtr(container: []u8, ptr: [*]u8) bool {
    return @intFromPtr(ptr) >= @intFromPtr(container.ptr) and
        @intFromPtr(ptr) < (@intFromPtr(container.ptr) + container.len);
}

fn sliceContainsSlice(container: []u8, slice: []u8) bool {
    return @intFromPtr(slice.ptr) >= @intFromPtr(container.ptr) and
        (@intFromPtr(slice.ptr) + slice.len) <= (@intFromPtr(container.ptr) + container.len);
}

var test_fixed_buffer_allocator_memory: [800000 * @sizeOf(u64)]u8 = undefined;

test FixedBufferAllocator {
    var fixed_buffer_allocator = mem.validationWrap(FixedBufferAllocator.init(test_fixed_buffer_allocator_memory[0..]));
    const a = fixed_buffer_allocator.allocator();

    try std.heap.testAllocator(a);
    try std.heap.testAllocatorAligned(a);
    try std.heap.testAllocatorLargeAlignment(a);
    try std.heap.testAllocatorAlignedShrink(a);
}

test reset {
    var buf: [8]u8 align(@alignOf(u64)) = undefined;
    var fba = FixedBufferAllocator.init(buf[0..]);
    const a = fba.allocator();

    const X = 0xeeeeeeeeeeeeeeee;
    const Y = 0xffffffffffffffff;

    const x = try a.create(u64);
    x.* = X;
    try std.testing.expectError(error.OutOfMemory, a.create(u64));

    fba.reset();
    const y = try a.create(u64);
    y.* = Y;

    // we expect Y to have overwritten X.
    try std.testing.expect(x.* == y.*);
    try std.testing.expect(y.* == Y);
}

test "reuse memory on realloc" {
    var small_fixed_buffer: [10]u8 = undefined;
    // check if we re-use the memory
    {
        var fixed_buffer_allocator = FixedBufferAllocator.init(small_fixed_buffer[0..]);
        const a = fixed_buffer_allocator.allocator();

        const slice0 = try a.alloc(u8, 5);
        try std.testing.expect(slice0.len == 5);
        const slice1 = try a.realloc(slice0, 10);
        try std.testing.expect(slice1.ptr == slice0.ptr);
        try std.testing.expect(slice1.len == 10);
        try std.testing.expectError(error.OutOfMemory, a.realloc(slice1, 11));
    }
    // check that we don't re-use the memory if it's not the most recent block
    {
        var fixed_buffer_allocator = FixedBufferAllocator.init(small_fixed_buffer[0..]);
        const a = fixed_buffer_allocator.allocator();

        var slice0 = try a.alloc(u8, 2);
        slice0[0] = 1;
        slice0[1] = 2;
        const slice1 = try a.alloc(u8, 2);
        const slice2 = try a.realloc(slice0, 4);
        try std.testing.expect(slice0.ptr != slice2.ptr);
        try std.testing.expect(slice1.ptr != slice2.ptr);
        try std.testing.expect(slice2[0] == 1);
        try std.testing.expect(slice2[1] == 2);
    }
}

test "thread safe version" {
    var fixed_buffer_allocator = FixedBufferAllocator.init(test_fixed_buffer_allocator_memory[0..]);

    try std.heap.testAllocator(fixed_buffer_allocator.threadSafeAllocator());
    try std.heap.testAllocatorAligned(fixed_buffer_allocator.threadSafeAllocator());
    try std.heap.testAllocatorLargeAlignment(fixed_buffer_allocator.threadSafeAllocator());
    try std.heap.testAllocatorAlignedShrink(fixed_buffer_allocator.threadSafeAllocator());
}
